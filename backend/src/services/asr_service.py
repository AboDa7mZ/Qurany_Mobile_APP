"""Speech-to-text with a pluggable backend.

Two backends are supported (selected via `settings.asr_backend`):

  - "faster_whisper" (default): CTranslate2, fast on CPU, no torch/transformers
    dependency. Good for local dev / general-purpose transcription.
  - "transformers": loads any Hugging Face Whisper checkpoint directly,
    including our own Kaggle fine-tune (`custom_model_path`), which faster-
    whisper can't load without a CTranslate2 conversion step.

Both backends are imported lazily so the rest of the app (and the test suite)
can run even when the heavy ML dependencies are not installed, and both
report word-level timestamps when available so downstream Tajweed heuristics
(Madd/Qalqalah/Ghunnah/Waqf duration checks) have something to work with.
"""
from __future__ import annotations

import json
import logging
import threading
from dataclasses import dataclass, field
from pathlib import Path

from ..config import settings
from .riwayah import DEFAULT_RIWAYAH, normalize_riwayah

logger = logging.getLogger(__name__)

# Bundled once from `GenerationConfig.from_pretrained("openai/whisper-base")`
# (see backend/training/kaggle for regen instructions). Older Whisper
# checkpoints on the Hub — including `tarteel-ai/whisper-base-ar-quran` and
# anything fine-tuned/merged from it (e.g. our Kaggle export) — ship without a
# proper `generation_config.json`, only bare token ids. That's fine for plain
# `generate()`, but `generate(..., return_timestamps=True)` requires fields
# like `no_timestamps_token_id`/`lang_to_id` and raises a ValueError without
# them. Multilingual Whisper checkpoints all share the same 51865-token
# vocab/special-token layout, so this file is safe to reuse as-is for any of
# them; we only override language/task at load time.
_WHISPER_GENERATION_CONFIG_ASSET = (
    Path(__file__).resolve().parent.parent / "assets" / "whisper_multilingual_generation_config.json"
)

# Whisper prepends <|startoftranscript|><|lang|><|task|><|notimestamps|> before prompt_ids.
_WHISPER_DECODER_PREFIX_TOKENS = 4
# Cap conditioning text so long prior chunks do not consume the whole 448-token budget.
_WHISPER_MAX_PROMPT_TOKENS = 96


def compute_whisper_max_new_tokens(
    max_target_positions: int,
    decoder_input_length: int,
    *,
    desired_max_new_tokens: int = 256,
) -> int:
    """Return ``max_new_tokens`` that keeps total decoder length under the model limit."""
    available = max_target_positions - decoder_input_length
    return max(1, min(desired_max_new_tokens, available))


def truncate_whisper_prompt_ids(prompt_ids, max_prompt_tokens: int):
    """Keep only the trailing prompt tokens so generation budget stays available."""
    if max_prompt_tokens <= 0 or prompt_ids is None:
        return None
    if prompt_ids.shape[-1] > max_prompt_tokens:
        return prompt_ids[:, -max_prompt_tokens:]
    return prompt_ids


def estimate_whisper_decoder_input_length(
    processor,
    prompt_ids,
    *,
    prefix_tokens: int = _WHISPER_DECODER_PREFIX_TOKENS,
) -> int:
    """Estimate decoder length after HF merges language/task prefix + ``prompt_ids``."""
    if prompt_ids is None:
        return prefix_tokens
    prompt_len = int(prompt_ids.shape[-1])
    try:
        forced = processor.get_decoder_prompt_ids(language="ar", task="transcribe")
        if forced:
            prefix_tokens = len(forced)
    except Exception:
        pass
    return prefix_tokens + prompt_len


def cuda_runtime_usable() -> bool:
    """True only when CUDA drivers and libraries (e.g. cuBLAS) actually load."""
    try:
        import torch

        if not torch.cuda.is_available():
            return False
        torch.zeros(1, device="cuda")
        return True
    except Exception:
        return False


def resolve_torch_device(requested: str) -> str:
    """Map WHISPER_DEVICE to a torch device, falling back to CPU when CUDA is broken."""
    if requested == "cpu":
        return "cpu"
    if cuda_runtime_usable():
        return "cuda"
    if requested in ("cuda", "auto"):
        logger.warning(
            "CUDA was requested (WHISPER_DEVICE=%s) but is not usable on this machine; using CPU.",
            requested,
        )
    return "cpu"


def faster_whisper_load_candidates(requested_device: str, compute_type: str) -> list[tuple[str, str]]:
    """Ordered (device, compute_type) pairs to try when loading faster-whisper."""
    cpu_compute = compute_type
    if compute_type in ("float16", "int8_float16"):
        cpu_compute = "int8"
    if requested_device == "cpu":
        return [("cpu", cpu_compute)]
    if requested_device == "cuda":
        return [("cuda", compute_type), ("cpu", cpu_compute)]
    # auto
    return [("cuda", compute_type), ("cpu", cpu_compute)]


@dataclass
class WordTiming:
    word: str
    start: float
    end: float

    def to_dict(self) -> dict:
        return {"word": self.word, "start": self.start, "end": self.end}


@dataclass
class TranscriptionSegment:
    start: float
    end: float
    text: str
    words: list[WordTiming] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {"start": self.start, "end": self.end, "text": self.text}


@dataclass
class TranscriptionResult:
    text: str
    language: str
    duration: float = 0.0
    segments: list[TranscriptionSegment] = field(default_factory=list)

    @property
    def words(self) -> list[WordTiming]:
        """Flattened word-level timings across all segments, in order."""
        out: list[WordTiming] = []
        for seg in self.segments:
            out.extend(seg.words)
        return out


class _FasterWhisperBackend:
    """CTranslate2-based backend (default; CPU-friendly, no torch needed)."""

    def __init__(self) -> None:
        self._model = None

    def load(self) -> None:
        if self._model is not None:
            return
        try:
            from faster_whisper import WhisperModel
        except ImportError as exc:  # pragma: no cover - depends on env
            raise RuntimeError(
                "faster-whisper is not installed. Run `pip install -r requirements.txt`."
            ) from exc

        logger.info(
            "Loading faster-whisper model '%s' (requested device=%s, compute_type=%s)...",
            settings.whisper_model,
            settings.whisper_device,
            settings.whisper_compute_type,
        )
        last_exc: Exception | None = None
        for device, compute_type in faster_whisper_load_candidates(
            settings.whisper_device,
            settings.whisper_compute_type,
        ):
            try:
                self._model = WhisperModel(
                    settings.whisper_model,
                    device=device,
                    compute_type=compute_type,
                )
                logger.info(
                    "faster-whisper model loaded (device=%s, compute_type=%s).",
                    device,
                    compute_type,
                )
                return
            except Exception as exc:
                last_exc = exc
                logger.warning(
                    "faster-whisper load failed on device=%s compute_type=%s: %s",
                    device,
                    compute_type,
                    exc,
                )
        raise RuntimeError(
            f"Could not load faster-whisper model '{settings.whisper_model}': {last_exc}"
        ) from last_exc

    def transcribe(self, audio_path: str, language: str | None) -> TranscriptionResult:
        assert self._model is not None
        segments_iter, info = self._model.transcribe(
            audio_path,
            language=language or settings.asr_language,
            beam_size=settings.whisper_beam_size,
            vad_filter=True,
            word_timestamps=True,
        )

        segments: list[TranscriptionSegment] = []
        parts: list[str] = []
        for seg in segments_iter:
            text = seg.text.strip()
            words = [
                WordTiming(word=w.word.strip(), start=w.start, end=w.end)
                for w in (seg.words or [])
            ]
            segments.append(TranscriptionSegment(start=seg.start, end=seg.end, text=text, words=words))
            parts.append(text)

        return TranscriptionResult(
            text=" ".join(parts).strip(),
            language=getattr(info, "language", language or settings.asr_language),
            duration=getattr(info, "duration", 0.0) or 0.0,
            segments=segments,
        )


def _ensure_whisper_generation_config(model) -> None:
    """Fill in any missing Whisper generation-config fields on `model` in place.

    See the module-level comment on `_WHISPER_GENERATION_CONFIG_ASSET` for why
    this is needed. Safe to call on any Whisper checkpoint: only fields that
    are currently unset (None) get filled in, so a checkpoint that already has
    a complete generation_config is left untouched.
    """
    try:
        with _WHISPER_GENERATION_CONFIG_ASSET.open(encoding="utf-8") as f:
            defaults = json.load(f)
    except OSError as exc:
        logger.warning("Could not load bundled Whisper generation config defaults: %s", exc)
        return

    gen_config = model.generation_config
    for key, value in defaults.items():
        if getattr(gen_config, key, None) is None:
            setattr(gen_config, key, value)

    # Pin to Arabic transcription regardless of what the checkpoint shipped
    # with, since that's the only mode this backend is used for.
    gen_config.language = "ar"
    gen_config.task = "transcribe"


class _TransformersBackend:
    """Loads a raw HF Whisper checkpoint (e.g. our fine-tuned model) via
    `transformers`. Heavier (torch + transformers) but needed for checkpoints
    that were never converted to CTranslate2, like a fresh Kaggle export."""

    def __init__(self, model_path: str, *, label: str = "transformers") -> None:
        self._model_path = model_path
        self._label = label
        self._model = None
        self._processor = None
        self._device = None

    def load(self) -> None:
        if self._model is not None:
            return
        try:
            import torch
            from transformers import WhisperForConditionalGeneration, WhisperProcessor
        except ImportError as exc:  # pragma: no cover - depends on env
            raise RuntimeError(
                "transformers/torch are not installed. Run "
                "`pip install transformers torch` (see requirements.txt)."
            ) from exc

        logger.info("Loading transformers Whisper model '%s' (%s)...", self._model_path, self._label)
        self._device = resolve_torch_device(settings.whisper_device)
        self._num_beams = (
            settings.whisper_num_beams
            if self._device == "cuda"
            else min(settings.whisper_num_beams, 1)
        )
        self._processor = WhisperProcessor.from_pretrained(
            self._model_path, language="ar", task="transcribe"
        )
        self._model = WhisperForConditionalGeneration.from_pretrained(self._model_path).to(
            self._device
        )
        self._model.eval()
        _ensure_whisper_generation_config(self._model)
        logger.info(
            "transformers Whisper model loaded on %s (%s).",
            self._device,
            self._label,
        )

    def transcribe(self, audio_path: str, language: str | None) -> TranscriptionResult:
        import librosa
        import torch

        assert self._model is not None and self._processor is not None
        speech, _ = librosa.load(audio_path, sr=16000, mono=True)
        duration = len(speech) / 16000.0
        # Single-ayah Muallim clips are short; skip slow decode options.
        short_clip = duration <= 25.0

        chunk_len = 16000 * 30  # Whisper decodes ~30s per forward pass
        overlap_samples = int(settings.whisper_chunk_overlap_seconds * 16000)
        step = max(chunk_len - overlap_samples, chunk_len // 2)

        parts: list[str] = []
        segments: list[TranscriptionSegment] = []
        offset_s = 0.0
        max_target = int(getattr(self._model.config, "max_target_positions", 448))
        prompt_ids = None
        if settings.whisper_condition_on_previous_text and not short_clip:
            try:
                prompt_ids = self._processor.get_prompt_ids(
                    "بسم الله الرحمن الرحيم",
                    return_tensors="pt",
                )
                prompt_ids = truncate_whisper_prompt_ids(prompt_ids, _WHISPER_MAX_PROMPT_TOKENS)
                if prompt_ids is not None:
                    prompt_ids = prompt_ids.to(self._device)
            except Exception:
                prompt_ids = None

        pos = 0
        while pos < len(speech):
            chunk = speech[pos : pos + chunk_len]
            if chunk.size == 0:
                break
            inputs = self._processor.feature_extractor(
                chunk, sampling_rate=16000, return_tensors="pt"
            ).input_features.to(self._device)

            prompt_len = estimate_whisper_decoder_input_length(self._processor, prompt_ids)
            if short_clip:
                # ~2 tokens per second of speech is plenty for a single ayah.
                max_new = min(
                    compute_whisper_max_new_tokens(max_target, prompt_len),
                    max(48, int(duration * 2.5) + 16),
                )
            else:
                max_new = compute_whisper_max_new_tokens(max_target, prompt_len)
            if prompt_ids is not None and max_new < 32:
                prompt_ids = None
                prompt_len = estimate_whisper_decoder_input_length(self._processor, None)
                max_new = compute_whisper_max_new_tokens(max_target, prompt_len)

            gen_kwargs: dict = {
                "max_new_tokens": max_new,
                "num_beams": self._num_beams,
                "return_timestamps": not short_clip,
            }
            if prompt_ids is not None:
                gen_kwargs["prompt_ids"] = prompt_ids

            with torch.no_grad():
                generated = self._model.generate(inputs, **gen_kwargs)
            text = self._processor.tokenizer.batch_decode(generated, skip_special_tokens=True)[0].strip()
            parts.append(text)
            chunk_duration = len(chunk) / 16000.0
            segments.append(
                TranscriptionSegment(start=offset_s, end=offset_s + chunk_duration, text=text, words=[])
            )
            offset_s += (step / 16000.0)

            if settings.whisper_condition_on_previous_text and text and not short_clip:
                try:
                    # Last ~80 chars only — enough context without blowing the token budget.
                    prompt_ids = self._processor.get_prompt_ids(
                        text[-80:],
                        return_tensors="pt",
                    )
                    prompt_ids = truncate_whisper_prompt_ids(prompt_ids, _WHISPER_MAX_PROMPT_TOKENS)
                    if prompt_ids is not None:
                        prompt_ids = prompt_ids.to(self._device)
                except Exception:
                    pass

            if pos + chunk_len >= len(speech):
                break
            pos += step

        return TranscriptionResult(
            text=" ".join(parts).strip(),
            language=language or settings.asr_language,
            duration=duration,
            segments=segments,
        )


class ASRService:
    """Thin wrapper that lazily loads and delegates to the configured backend."""

    def __init__(self) -> None:
        self._backends: dict[str, _FasterWhisperBackend | _TransformersBackend] = {}
        self._load_lock = threading.Lock()

    @property
    def is_loaded(self) -> bool:
        return bool(self._backends)

    def _hafs_model_path(self) -> str:
        return settings.custom_model_path or "tarteel-ai/whisper-base-ar-quran"

    def _bazzi_model_path(self) -> str:
        if settings.bazzi_model_path:
            return settings.bazzi_model_path
        raise RuntimeError(
            "Bazzi model path is not configured. Set BAZZI_MODEL_PATH in .env "
            "(e.g. ./models/qurany-whisper-base-al-baqarah-bazzi)."
        )

    def _configured_model_for(self, riwayah: str) -> str:
        if riwayah == "bazzi":
            return self._bazzi_model_path()
        if settings.asr_backend == "transformers":
            return self._hafs_model_path()
        return settings.whisper_model

    def _active_backend_name(self, backend) -> str | None:
        if backend is None:
            return None
        if isinstance(backend, _TransformersBackend):
            return "transformers"
        return "faster_whisper"

    def backend_info(self, riwayah: str | None = None) -> dict:
        """Configured vs actually loaded ASR backend for a riwayah."""
        riwayah = normalize_riwayah(riwayah)
        configured_model = self._configured_model_for(riwayah)
        configured_backend = (
            "transformers" if riwayah == "bazzi" or settings.asr_backend == "transformers" else "faster_whisper"
        )
        backend = self._backends.get(riwayah)
        info = {
            "riwayah": riwayah,
            "configured_backend": configured_backend,
            "configured_model": configured_model,
            "active_backend": self._active_backend_name(backend),
            "active_model": None,
            "loaded": backend is not None,
        }
        if isinstance(backend, _TransformersBackend):
            info["active_model"] = backend._model_path
            info["device"] = backend._device
        elif isinstance(backend, _FasterWhisperBackend):
            info["active_model"] = settings.whisper_model
        return info

    def models_status(self) -> dict:
        """Summary of both riwayah models for /health."""
        from .riwayah import SUPPORTED_RIWAYAT

        return {r: self.backend_info(r) for r in SUPPORTED_RIWAYAT}

    def _make_backend(self, riwayah: str):
        if riwayah == "bazzi":
            return _TransformersBackend(self._bazzi_model_path(), label="bazzi")
        if settings.asr_backend == "transformers":
            return _TransformersBackend(self._hafs_model_path(), label="hafs")
        return _FasterWhisperBackend()

    def _get_backend(self, riwayah: str):
        riwayah = normalize_riwayah(riwayah)
        backend = self._backends.get(riwayah)
        if backend is not None:
            return backend
        with self._load_lock:
            backend = self._backends.get(riwayah)
            if backend is not None:
                return backend
            backend = self._make_backend(riwayah)
            backend.load()
            self._backends[riwayah] = backend
            info = self.backend_info(riwayah)
            logger.info(
                "ASR ready (%s): backend=%s model=%s device=%s",
                riwayah,
                info.get("active_backend"),
                info.get("active_model"),
                info.get("device", "n/a"),
            )
            return backend

    def load(self, riwayah: str | None = None) -> None:
        """Load the ASR backend for a riwayah into memory (idempotent)."""
        self._get_backend(normalize_riwayah(riwayah))

    def transcribe(
        self,
        audio_path: str,
        language: str | None = None,
        *,
        riwayah: str | None = None,
    ) -> TranscriptionResult:
        """Transcribe an audio file to Arabic text."""
        backend = self._get_backend(normalize_riwayah(riwayah))
        return backend.transcribe(audio_path, language)


# Module-level singleton.
asr_service = ASRService()
