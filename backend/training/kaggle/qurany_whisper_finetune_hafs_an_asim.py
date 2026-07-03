"""
Qurany Whisper fine-tune for Kaggle (2x GPU via `accelerate launch`).

Riwayah    : Hafs 'an 'Asim (حفص عن عاصم) — the standard riwayah used by nearly
             all mainstream reciters/mushafs, including EveryAyah's Alafasy
             reciter used below. For the Bazzi 'an Ibn Kathir (البزي عن ابن
             كثير) counterpart, see qurany_whisper_finetune_bazzi_an_ibn_kathir.py
             in this same folder — same architecture, different qira'a data.
Base model : tarteel-ai/whisper-base-ar-quran
Data scope : Surah 2 (Al-Baqarah), all 286 ayahs — single reciter (EveryAyah.com)
Output     : /kaggle/working/qurany-whisper-base-al-baqarah (+ checkpoint zips)

Why Al-Baqarah only: it lets us push epochs (not just 3-4) within an 8h Kaggle
session while keeping the base model's general Quranic knowledge intact (LoRA,
small rank), and gives clean, single-reciter labels for a focused MVP demo.

Extras vs. a plain fine-tune:
  - Harakat (tashkeel) are preserved in the training labels (Uthmani script
    from AlQuran Cloud), so the model is trained on full diacritics, not just
    bare letters — this is what a Tajweed-aware ASR needs.
  - `load_best_model_at_end` + `EarlyStoppingCallback` let you set a *high*
    epoch budget (default 60) without babysitting the run: training stops
    automatically once WER stops improving on the held-out split, and the
    best-by-WER checkpoint (not necessarily the last one) is what gets saved,
    which also guards against overfitting 286 ayahs for 60 epochs.
  - `AutoDownloadCheckpoint` zips every saved checkpoint straight to
    /kaggle/working (+ /kaggle/output) with a FileLink, so a Kaggle disconnect
    never loses progress (pattern adapted from a teammate's Kaggle training
    script that zips + auto-links checkpoints on `on_save`).
  - Optional external test set: point `cfg.external_test_dir` at a Kaggle
    "Add Data" dataset holding your own recordings (e.g. a full Al-Baqarah
    recitation by a different reciter + a handful of short clips) and
    `run_external_evaluation()` will transcribe them with the fine-tuned model
    and run them through a self-contained port of the backend's
    Needleman-Wunsch mistake-detector, so you can sanity-check real-world
    mistake detection before wiring the model into the FastAPI backend.

Copy this file into a Kaggle notebook or run cells from
Qurany_Whisper_Finetune_حفص_عن_عاصم.ipynb.
"""
from __future__ import annotations

import os

# Must be set before transformers/tokenizers is imported anywhere. HF's Rust
# tokenizers spin up an internal thread pool; if that pool already exists when
# accelerate.notebook_launcher forks worker processes, the child can deadlock
# silently (0% CPU/GPU, no error) instead of raising the usual "disabling
# parallelism to avoid deadlocks" warning. Cheap, safe to always set.
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import glob
import json
import re
import shutil
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path

# PyTorch 2.6+ flipped torch.load's default to weights_only=True, which breaks
# loading Trainer's rng_state.pth checkpoint files (they contain numpy/random
# state, not just tensors). Same fix a teammate needed for their Kaggle
# Trainer-based run; skipped entirely if torch isn't installed (e.g. running
# just the data-download half of this script without the ML stack).
try:
    import torch as _torch

    _ORIGINAL_TORCH_LOAD = _torch.load

    def _patched_torch_load(f, *args, **kwargs):
        path_str = f if isinstance(f, str) else getattr(f, "name", "")
        if "rng_state" in str(path_str):
            kwargs["weights_only"] = False
        return _ORIGINAL_TORCH_LOAD(f, *args, **kwargs)

    _torch.load = _patched_torch_load
except ImportError:
    pass

# ── Qurany branding (saved into the exported model card) ─────────────────────
QURANY_MODEL_NAME = "qurany-whisper-base-al-baqarah"
QURANY_MODEL_VERSION = "1.0.0"
QURANY_BASE_MODEL = "tarteel-ai/whisper-base-ar-quran"
QURANY_RIWAYAH = "Hafs 'an 'Asim (حفص عن عاصم)"
QURANY_DESCRIPTION = (
    "Fine-tuned from Tarteel's whisper-base-ar-quran on all 286 ayahs of Surah "
    "Al-Baqarah (riwayah: Hafs 'an 'Asim) for the Qurany graduation recitation "
    "assistant. Labels keep full Uthmani tashkeel (harakat) so the model stays "
    "diacritic-aware."
)

AL_BAQARAH_SURAH = 2

# Whisper hard limits — ayahs with full tashkeel (e.g. 2:282) can exceed these.
WHISPER_MAX_LABEL_LENGTH = 448   # model max_target_positions
WHISPER_MAX_AUDIO_SECONDS = 30   # feature extractor chunk size

RECITER_FOLDER = "Alafasy_128kbps"
# Optional extra EveryAyah reciters — downloaded automatically on Kaggle; no
# manual recording needed. Uncomment/add in TrainConfig.extra_reciters.
EVERYAYAH_RECITERS_EXTRA = (
    "Husary_128kbps",
    "Minshawy_Mujawwad_128kbps",
)
EVERYAYAH_URL = "https://everyayah.com/data/{reciter}/{s:03d}{a:03d}.mp3"
ALQURAN_API = "https://api.alquran.cloud/v1"

# Standard madani mushaf ayah counts per surah (1-indexed surah number).
SURAH_AYAH_COUNTS = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
    111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
    54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
    49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30,
    20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4,
    5, 6,
]


@dataclass
class TrainConfig:
    data_dir: Path = Path("/kaggle/working/quran_data")
    processed_dir: Path = Path("/kaggle/working/quran_data/processed_dataset")
    output_dir: Path = Path("/kaggle/working/runs")
    final_model_dir: Path = Path("/kaggle/working") / QURANY_MODEL_NAME
    kaggle_output: Path = Path("/kaggle/output")
    working_dir: Path = Path("/kaggle/working")

    # Point this at a Kaggle "Add Data" dataset holding your own recordings
    # (full Al-Baqarah recitation + short clips) for held-out evaluation only —
    # they are NEVER mixed into the training set, since we don't have a
    # verified per-ayah ground truth for them. Leave missing to skip.
    external_test_dir: Path | None = Path("/kaggle/input/qurany-training-data")

    reciter: str = RECITER_FOLDER
    # Additional EveryAyah reciter folders (same 286 ayahs, different voice).
    # Example: ("Husary_128kbps", "Minshawy_Mujawwad_128kbps")
    extra_reciters: tuple[str, ...] = ()
    surah_number: int = AL_BAQARAH_SURAH
    max_train_samples: int | None = None  # set for smoke tests

    num_train_epochs: float = 60
    per_device_train_batch_size: int = 8
    per_device_eval_batch_size: int = 8
    gradient_accumulation_steps: int = 2
    learning_rate: float = 1e-5
    warmup_steps: int = 50
    save_steps: int = 50
    eval_steps: int = 50
    logging_steps: int = 10
    lora_r: int = 32
    lora_alpha: int = 64
    eval_holdout_ratio: float = 0.1
    seed: int = 42

    # `load_best_model_at_end` picks the lowest-WER checkpoint; early stopping
    # kills the run once WER stops improving, so "60 epochs" is a ceiling, not
    # a target — this is what keeps a 286-ayah dataset from just overfitting.
    early_stopping_patience: int = 8         # evals without WER improvement
    early_stopping_threshold: float = 0.05   # in WER percentage points


def _http_get_json(url: str, timeout: float = 60.0) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "QuranyTrainer/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _download_file(url: str, dest: Path, retries: int = 3) -> bool:
    if dest.exists() and dest.stat().st_size > 0:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "QuranyTrainer/1.0"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                dest.write_bytes(resp.read())
            return dest.stat().st_size > 0
        except Exception:
            time.sleep(1.5 * (attempt + 1))
    return False


def _load_speech(path: str | Path, timeout_s: int = 30):
    """Load mono 16 kHz audio with a hard per-file timeout (Linux SIGALRM)."""
    import signal

    import librosa

    path = Path(path)

    def _on_timeout(signum, frame):
        raise TimeoutError(f"decode timed out after {timeout_s}s: {path}")

    had_alarm = hasattr(signal, "SIGALRM")
    old_handler = signal.signal(signal.SIGALRM, _on_timeout) if had_alarm else None
    if had_alarm:
        signal.alarm(timeout_s)
    try:
        speech, _ = librosa.load(str(path), sr=16000, mono=True)
        if len(speech) == 0:
            raise ValueError(f"empty audio: {path}")
        return speech
    finally:
        if had_alarm:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, old_handler)


def _validate_audio(path: Path, timeout_s: int = 20) -> bool:
    """Actually decode the file (not just check size > 0), with a hard timeout."""
    try:
        _load_speech(path, timeout_s=timeout_s)
        return True
    except Exception as exc:
        print(f"  audio validation failed for {path}: {exc}")
        return False


def _fetch_ayah_text(surah: int, ayah: int, cache: dict[tuple[int, int], str]) -> str:
    key = (surah, ayah)
    if key in cache:
        return cache[key]
    if surah not in cache.get("_surah_loaded", {}):
        payload = _http_get_json(f"{ALQURAN_API}/surah/{surah}/ar.uthmani")
        ayahs = payload["data"]["ayahs"]
        for a in ayahs:
            cache[(surah, a["numberInSurah"])] = a["text"]
        cache["_surah_loaded"] = cache.get("_surah_loaded", {})
        cache["_surah_loaded"][surah] = True
    return cache[(surah, ayah)]


def iter_surah_ayahs(surah_number: int):
    """Yield (surah, ayah) for every ayah in a single surah."""
    total = SURAH_AYAH_COUNTS[surah_number - 1]
    for ayah in range(1, total + 1):
        yield surah_number, ayah


def download_training_data(cfg: TrainConfig) -> Path:
    """Download EveryAyah audio + Uthmani labels; write manifest.csv."""
    audio_root = cfg.data_dir / "audio"
    manifest_path = cfg.data_dir / "manifest.csv"
    cfg.data_dir.mkdir(parents=True, exist_ok=True)

    text_cache: dict = {}
    rows: list[dict] = []
    failed: list[str] = []

    pairs = list(iter_surah_ayahs(cfg.surah_number))
    if cfg.max_train_samples:
        pairs = pairs[: cfg.max_train_samples]

    reciters = [cfg.reciter, *cfg.extra_reciters]
    print(
        f"Downloading {len(pairs)} ayah clips × {len(reciters)} reciter(s) "
        f"(Surah {cfg.surah_number})..."
    )

    total_steps = len(pairs) * len(reciters)
    step = 0
    for reciter_name in reciters:
        for surah, ayah in pairs:
            step += 1
            rel = f"{reciter_name}/{surah:03d}_{ayah:03d}.mp3"
            dest = audio_root / rel
            url = EVERYAYAH_URL.format(reciter=reciter_name, s=surah, a=ayah)
            if not _download_file(url, dest):
                failed.append(rel)
                continue
            if not _validate_audio(dest):
                dest.unlink(missing_ok=True)
                if not _download_file(url, dest) or not _validate_audio(dest):
                    failed.append(rel)
                    continue
            try:
                text = _fetch_ayah_text(surah, ayah, text_cache).strip()
            except Exception:
                failed.append(rel)
                continue
            if not text:
                failed.append(rel)
                continue
            rows.append(
                {
                    "audio_path": str(dest),
                    "text": text,
                    "surah": surah,
                    "ayah": ayah,
                    "reciter": reciter_name,
                }
            )
            if step % 50 == 0:
                print(f"  … {step}/{total_steps} processed, {len(rows)} ok, {len(failed)} failed")

    import pandas as pd

    df = pd.DataFrame(rows)
    df.to_csv(manifest_path, index=False)
    meta = {
        "total_requested": len(pairs),
        "downloaded": len(rows),
        "failed": len(failed),
        "reciter": cfg.reciter,
        "reciters": list(reciters),
        "scope": f"Surah {cfg.surah_number} (all ayahs)",
        "base_model": QURANY_BASE_MODEL,
        "qurany_model_name": QURANY_MODEL_NAME,
    }
    (cfg.data_dir / "download_meta.json").write_text(
        json.dumps(meta, indent=2), encoding="utf-8"
    )
    print(json.dumps(meta, indent=2))
    if len(rows) < 200:
        raise RuntimeError(
            f"Too few samples downloaded ({len(rows)}). Check Kaggle internet / EveryAyah URLs "
            f"(try a different RECITER_FOLDER, e.g. Husary_64kbps, if Alafasy_128kbps 404s)."
        )
    return manifest_path


def zip_and_link(
    source_path: Path,
    zip_basename: str,
    working_dir: Path,
    kaggle_output: Path,
) -> None:
    """Zip a file or directory and show Kaggle download links (main process only)."""
    try:
        from IPython.display import FileLink, display
    except ImportError:  # pragma: no cover - only missing outside Jupyter
        FileLink = None
        display = print

    working_dir.mkdir(parents=True, exist_ok=True)
    kaggle_output.mkdir(parents=True, exist_ok=True)

    zip_base = working_dir / zip_basename
    if source_path.is_dir():
        archive = shutil.make_archive(str(zip_base), "zip", root_dir=source_path)
    else:
        # single file: make a temp dir wrapper
        staging = working_dir / f"_stage_{zip_basename}"
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir(parents=True)
        shutil.copy2(source_path, staging / source_path.name)
        archive = shutil.make_archive(str(zip_base), "zip", root_dir=staging)
        shutil.rmtree(staging)

    archive_path = Path(archive)
    out_copy = kaggle_output / archive_path.name
    shutil.copy2(archive_path, out_copy)

    print(f"Saved checkpoint archive: {archive_path} ({archive_path.stat().st_size / 1e6:.1f} MB)")
    if FileLink is not None:
        display(FileLink(str(archive_path)))
        display(FileLink(str(out_copy)))


class AutoDownloadCheckpoint:
    """Zip each Trainer checkpoint and show a Kaggle FileLink (main process only)."""

    def __init__(
        self,
        working_dir: Path | str = "/kaggle/working",
        kaggle_output: Path | str = "/kaggle/output",
    ) -> None:
        from transformers import TrainerCallback

        self.working_dir = Path(working_dir)
        self.kaggle_output = Path(kaggle_output)
        self._base = TrainerCallback

    def __call__(self):
        """Return a TrainerCallback subclass instance (HF expects instances in callbacks=)."""
        working_dir = self.working_dir
        kaggle_output = self.kaggle_output
        BaseCallback = self._base

        class _Callback(BaseCallback):
            def on_save(self, args, state, control, **kwargs):
                if not state.is_world_process_zero:
                    return control
                step = state.global_step
                ckpt_dir = Path(args.output_dir) / f"checkpoint-{step}"
                if not ckpt_dir.is_dir():
                    return control
                try:
                    zip_and_link(ckpt_dir, f"checkpoint{step}", working_dir, kaggle_output)
                except Exception as exc:
                    print(f"AutoDownloadCheckpoint @ step {step}: {exc}")
                return control

        return _Callback()


# ── Self-contained mistake-detector (ported from backend/src/services) ───────
# Kept dependency-free (no import of the FastAPI backend package) so it runs
# standalone inside a Kaggle kernel.

_DIACRITICS_RE = re.compile(r"[\u064B-\u065F\u0670]")
_TATWEEL_CHAR = "\u0640"
_ALEF_VARIANTS_RE = re.compile(r"[\u0625\u0623\u0622\u0671\u0627]")
_NON_ARABIC_RE = re.compile(r"[^\u0621-\u064A\s]")
_MULTISPACE_RE = re.compile(r"\s+")


def _normalize_arabic(text: str) -> str:
    if not text:
        return ""
    text = _DIACRITICS_RE.sub("", text)
    text = text.replace(_TATWEEL_CHAR, "")
    text = _ALEF_VARIANTS_RE.sub("\u0627", text)
    text = text.replace("\u0624", "\u0648")
    text = text.replace("\u0626", "\u064A")
    text = text.replace("\u0649", "\u064A")
    text = text.replace("\u0629", "\u0647")
    text = text.replace("\u0621", "")
    text = _NON_ARABIC_RE.sub("", text)
    text = _MULTISPACE_RE.sub(" ", text).strip()
    return text


def _word_similarity(a: str, b: str) -> float:
    if a == b:
        return 1.0
    set_a, set_b = set(a), set(b)
    union = set_a | set_b
    return (len(set_a & set_b) / len(union)) if union else 0.0


def _needleman_wunsch_errors(reference_text: str, hyp_text: str, threshold: float = 0.6) -> dict:
    """Word-level Needleman-Wunsch alignment; mirrors alignment_service.py."""
    ref = [w for w in (_normalize_arabic(w) for w in reference_text.split()) if w]
    hyp = [w for w in (_normalize_arabic(w) for w in hyp_text.split()) if w]
    n, m = len(ref), len(hyp)

    def matches(a: str, b: str) -> bool:
        return a == b or _word_similarity(a, b) > threshold

    cost = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        cost[i][0] = i
    for j in range(1, m + 1):
        cost[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            sub = 0 if matches(ref[i - 1], hyp[j - 1]) else 1
            cost[i][j] = min(
                cost[i - 1][j - 1] + sub,
                cost[i - 1][j] + 1,
                cost[i][j - 1] + 1,
            )

    ops: list[tuple[str, str, str]] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and cost[i][j] == cost[i - 1][j - 1] + (0 if matches(ref[i - 1], hyp[j - 1]) else 1):
            kind = "match" if matches(ref[i - 1], hyp[j - 1]) else "substitution"
            ops.append((kind, ref[i - 1], hyp[j - 1]))
            i, j = i - 1, j - 1
        elif i > 0 and cost[i][j] == cost[i - 1][j] + 1:
            ops.append(("omission", ref[i - 1], ""))
            i -= 1
        else:
            ops.append(("addition", "", hyp[j - 1]))
            j -= 1
    ops.reverse()

    errors = [op for op in ops if op[0] != "match"]
    matched = n - sum(1 for op in errors if op[0] != "addition")
    similarity = max(0.0, min(100.0, (matched / n * 100) if n else 0.0))
    return {
        "total_words": n,
        "matched_words": max(matched, 0),
        "mistakes": len(errors),
        "similarity_score": round(similarity, 2),
        "errors": errors,
    }


def _parse_reference_txt(path: Path) -> dict[int, str]:
    """Parse the '<ayah text> (<n>) <ayah text> (<n>) ...' canonical-text format
    used by training data/Al-Baqarah.txt into {ayah_number: text}."""
    raw = path.read_text(encoding="utf-8")
    ayahs: dict[int, str] = {}
    for match in re.finditer(r"(.+?)\((\d+)\)", raw, flags=re.DOTALL):
        text, num = match.group(1).strip(), int(match.group(2))
        ayahs[num] = text
    return ayahs


def _ayah_map_from_rows(rows) -> dict[int, str]:
    ayahs: dict[int, str] = {}
    for row in rows:
        ayahs[int(row["ayah"])] = str(row["text"])
    return ayahs


def _localize_ayah_segment(ayah_map: dict[int, str], transcript: str) -> tuple[str, int, int] | None:
    """Return (segment_text, start_ayah, end_ayah) for the best matching window."""
    hyp_words = [w for w in (_normalize_arabic(w) for w in transcript.split()) if w]
    if not hyp_words:
        return None

    numbers = sorted(ayah_map)
    prefix = hyp_words[: min(8, len(hyp_words))]
    starts: list[int] = []
    for num in numbers:
        aw = [w for w in (_normalize_arabic(w) for w in ayah_map[num].split()) if w]
        overlap = sum(1 for i in range(min(len(prefix), len(aw), 8)) if prefix[i] == aw[i])
        if overlap >= 2:
            starts.append(num)
    if not starts:
        starts = numbers

    best: tuple[float, str, int, int] | None = None
    hyp_len = len(hyp_words)
    for start in starts[:12]:
        si = numbers.index(start)
        max_ei = min(si + 15, len(numbers) - 1, si + max(1, hyp_len // 8 + 2))
        for ei in range(si, max_ei + 1):
            seg_nums = numbers[si : ei + 1]
            ref = " ".join(ayah_map[n] for n in seg_nums)
            rw = len([w for w in (_normalize_arabic(w) for w in ref.split()) if w])
            if rw < max(1, hyp_len // 3) or rw > hyp_len * 4:
                continue
            score = _needleman_wunsch_errors(ref, transcript)["similarity_score"]
            if score < 55:
                continue
            item = (score, ref, seg_nums[0], seg_nums[-1])
            if best is None or item[0] > best[0]:
                best = item
    if best is None:
        return None
    _, ref_text, start_ayah, end_ayah = best
    return ref_text, start_ayah, end_ayah


def _transcribe_audio(model, processor, speech, device: str) -> str:
    """Decode with beam search + chunk overlap + prior-text prompt (matches backend)."""
    import torch

    chunk_len = 16000 * 30
    overlap = int(2.0 * 16000)
    step = max(chunk_len - overlap, chunk_len // 2)
    max_target = int(getattr(model.config, "max_target_positions", 448))
    max_prompt_tokens = 96
    parts: list[str] = []
    prompt_ids = None
    try:
        prompt_ids = processor.get_prompt_ids(
            "بسم الله الرحمن الرحيم", return_tensors="pt"
        )
        if prompt_ids.shape[-1] > max_prompt_tokens:
            prompt_ids = prompt_ids[:, -max_prompt_tokens:]
        prompt_ids = prompt_ids.to(device)
    except Exception:
        prompt_ids = None

    def _decoder_len(ids) -> int:
        if ids is None:
            return 4
        prefix = 4
        try:
            forced = processor.get_decoder_prompt_ids(language="ar", task="transcribe")
            if forced:
                prefix = len(forced)
        except Exception:
            pass
        return prefix + int(ids.shape[-1])

    pos = 0
    while pos < len(speech):
        chunk = speech[pos : pos + chunk_len]
        if chunk.size == 0:
            break
        inputs = processor.feature_extractor(
            chunk, sampling_rate=16000, return_tensors="pt"
        ).input_features.to(device)
        dec_len = _decoder_len(prompt_ids)
        max_new = max(1, min(256, max_target - dec_len))
        gen_kwargs: dict = {"max_new_tokens": max_new, "num_beams": 5}
        if prompt_ids is not None and max_new >= 32:
            gen_kwargs["prompt_ids"] = prompt_ids
        with torch.no_grad():
            generated_ids = model.generate(inputs, **gen_kwargs)
        text = processor.tokenizer.batch_decode(generated_ids, skip_special_tokens=True)[0].strip()
        parts.append(text)
        if text:
            try:
                prompt_ids = processor.get_prompt_ids(text[-80:], return_tensors="pt")
                if prompt_ids.shape[-1] > max_prompt_tokens:
                    prompt_ids = prompt_ids[:, -max_prompt_tokens:]
                prompt_ids = prompt_ids.to(device)
            except Exception:
                pass
        if pos + chunk_len >= len(speech):
            break
        pos += step
    return " ".join(parts).strip()


def run_per_ayah_evaluation(cfg: TrainConfig, model, processor, split: str = "test") -> None:
    """Held-out per-ayah WER — the honest metric for Al-Baqarah ASR quality."""
    import librosa
    import pandas as pd
    import torch
    from jiwer import wer

    manifest_path = cfg.data_dir / "manifest.csv"
    if not manifest_path.exists():
        print("No manifest.csv; skipping per-ayah evaluation.")
        return

    df = pd.read_csv(manifest_path)
    df = df.sample(frac=1.0, random_state=cfg.seed).reset_index(drop=True)
    n_test = max(1, int(len(df) * cfg.eval_holdout_ratio))
    eval_df = df.iloc[:n_test]

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)
    model.eval()

    print(f"\nPer-ayah evaluation on {len(eval_df)} held-out clips (split={split})...")
    results: list[dict] = []
    refs: list[str] = []
    hyps: list[str] = []

    for _, row in eval_df.iterrows():
        speech, _ = librosa.load(row["audio_path"], sr=16000, mono=True)
        hyp = _transcribe_audio(model, processor, speech, device)
        ref = str(row["text"])
        refs.append(_normalize_arabic(ref))
        hyps.append(_normalize_arabic(hyp))
        row_wer = wer(ref, hyp) if ref else 1.0
        results.append(
            {
                "ayah": int(row["ayah"]),
                "reciter": row.get("reciter", cfg.reciter),
                "wer": round(row_wer * 100, 2),
                "reference": ref,
                "hypothesis": hyp,
            }
        )

    corpus_wer = wer(refs, hyps) * 100 if refs else 100.0
    summary = {
        "corpus_wer_percent": round(corpus_wer, 2),
        "num_ayahs": len(results),
        "mean_ayah_wer_percent": round(
            sum(r["wer"] for r in results) / max(len(results), 1), 2
        ),
        "worst_ayahs": sorted(results, key=lambda r: r["wer"], reverse=True)[:10],
    }
    out_path = cfg.working_dir / f"per_ayah_eval_{split}.json"
    out_path.write_text(
        json.dumps({"summary": summary, "results": results}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(
        f"  corpus WER: {summary['corpus_wer_percent']}%  "
        f"mean per-ayah WER: {summary['mean_ayah_wer_percent']}%"
    )
    print(f"  -> saved {out_path}")


def run_external_evaluation(cfg: TrainConfig, model, processor) -> None:
    """Transcribe user recordings and compare with ayah-aware alignment.

    Looks in `cfg.external_test_dir` for:
      - Al-Baqarah.txt (canonical text) — optional
      - .mp3/.wav/.m4a/.ogg files: transcribed and aligned against the
        auto-detected ayah window (not the full surah).
    """
    import librosa
    import pandas as pd
    import torch

    test_dir = cfg.external_test_dir
    if test_dir is None or not test_dir.exists():
        print(f"No external test set at {test_dir}; skipping external evaluation.")
        return

    txt_path = test_dir / "Al-Baqarah.txt"
    if txt_path.exists():
        ayah_map = _parse_reference_txt(txt_path)
        print(f"Loaded canonical text from {txt_path} ({len(ayah_map)} ayahs).")
    else:
        manifest = pd.read_csv(cfg.data_dir / "manifest.csv")
        ayah_map = _ayah_map_from_rows(manifest.sort_values(["surah", "ayah"]).to_dict("records"))
        print("No Al-Baqarah.txt in external test dir; using downloaded manifest text instead.")

    audio_files = sorted(
        {
            p
            for ext in ("*.mp3", "*.wav", "*.m4a", "*.ogg")
            for p in glob.glob(str(test_dir / ext))
        }
    )
    if not audio_files:
        print(f"No audio files found in {test_dir}; skipping external evaluation.")
        return

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)
    model.eval()

    print(f"\nRunning external evaluation on {len(audio_files)} file(s) from {test_dir}...")
    for audio_path in audio_files:
        speech, _ = librosa.load(audio_path, sr=16000, mono=True)
        transcript = _transcribe_audio(model, processor, speech, device)

        localized = _localize_ayah_segment(ayah_map, transcript)
        if localized:
            ref_segment, start_ayah, end_ayah = localized
            scope = "auto_detected"
        else:
            ref_segment = " ".join(ayah_map[k] for k in sorted(ayah_map))
            start_ayah = end_ayah = None
            scope = "full_surah_fallback"

        report = _needleman_wunsch_errors(ref_segment, transcript)
        print(f"\n=== {Path(audio_path).name} ===")
        print(f"  scope: {scope}  ayahs: {start_ayah}-{end_ayah}")
        print(
            f"  similarity: {report['similarity_score']}%  "
            f"matched: {report['matched_words']}/{report['total_words']}  "
            f"mistakes: {report['mistakes']}"
        )
        for kind, expected, recited in report["errors"][:15]:
            print(f"    [{kind}] expected='{expected}' recited='{recited}'")

        out_path = cfg.working_dir / f"external_eval_{Path(audio_path).stem}.json"
        out_path.write_text(
            json.dumps(
                {
                    "audio": str(audio_path),
                    "transcript": transcript,
                    "reference_scope": scope,
                    "detected_ayah_start": start_ayah,
                    "detected_ayah_end": end_ayah,
                    **report,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(f"  -> saved {out_path}")


def _write_qurany_model_card(model_dir: Path, cfg: TrainConfig) -> None:
    card = f"""---
language: ar
license: apache-2.0
base_model: {QURANY_BASE_MODEL}
tags:
  - whisper
  - quran
  - qurany
  - automatic-speech-recognition
library_name: transformers
pipeline_tag: automatic-speech-recognition
---

# {QURANY_MODEL_NAME}

**Version:** {QURANY_MODEL_VERSION}

{QURANY_DESCRIPTION}

## Base model

Fine-tuned from [{QURANY_BASE_MODEL}](https://huggingface.co/{QURANY_BASE_MODEL}) (Tarteel AI).

## Training data

- **Riwayah (qira'a):** {QURANY_RIWAYAH}
- **Scope:** Surah {cfg.surah_number} (Al-Baqarah) — all 286 ayahs
- **Reciter:** {cfg.reciter} (EveryAyah.com)
- **Labels:** Uthmani script with full tashkeel/harakat (AlQuran Cloud API)
- **Epoch budget:** up to {cfg.num_train_epochs}, `load_best_model_at_end` on WER +
  early stopping (patience={cfg.early_stopping_patience}) to avoid overfitting a
  single-surah dataset.

## Intended use

Speech-to-text for Quranic Arabic recitation in the **Qurany** mobile app backend.
Downstream word alignment and mistake detection are handled separately
(see `backend/src/services/alignment_service.py`).

## Team

Cairo University — Faculty of Computing and Artificial Intelligence (Graduation Project 2025–2026)
"""
    model_dir.mkdir(parents=True, exist_ok=True)
    (model_dir / "README.md").write_text(card, encoding="utf-8")
    (model_dir / "qurany_model_info.json").write_text(
        json.dumps(
            {
                "name": QURANY_MODEL_NAME,
                "version": QURANY_MODEL_VERSION,
                "base_model": QURANY_BASE_MODEL,
                "riwayah": QURANY_RIWAYAH,
                "training_scope": f"Surah {cfg.surah_number} (Al-Baqarah)",
            },
            indent=2,
        ),
        encoding="utf-8",
    )


def prepare_and_cache_dataset(cfg: TrainConfig) -> Path:
    """Decode all audio + extract log-mel features/labels ONCE in a plain Python
    loop (no `datasets.map` — that can hang silently on Kaggle even with
    num_proc=1), then save an Arrow dataset to disk."""
    import pandas as pd
    from datasets import Dataset, DatasetDict
    from transformers import WhisperProcessor, WhisperTokenizer

    manifest = cfg.data_dir / "manifest.csv"
    if not manifest.exists():
        raise FileNotFoundError(
            f"{manifest} not found. Run download_training_data() in the notebook first."
        )

    df = pd.read_csv(manifest)
    df = df.sample(frac=1.0, random_state=cfg.seed).reset_index(drop=True)
    split_idx = int(len(df) * (1.0 - cfg.eval_holdout_ratio))
    train_df = df.iloc[:split_idx]
    test_df = df.iloc[split_idx:]

    hf_local = {"local_files_only": True}
    processor = WhisperProcessor.from_pretrained(
        QURANY_BASE_MODEL, language="ar", task="transcribe", **hf_local
    )
    tokenizer = WhisperTokenizer.from_pretrained(
        QURANY_BASE_MODEL, language="ar", task="transcribe", **hf_local
    )

    def _process_split(split_df: pd.DataFrame, split_name: str) -> Dataset:
        records: list[dict] = []
        skipped = 0
        truncated_labels = 0
        truncated_audio = 0
        max_samples = 16000 * WHISPER_MAX_AUDIO_SECONDS
        total = len(split_df)
        print(f"Pre-processing {split_name}: {total} clips (plain loop, no multiprocessing)...")
        for i, row in enumerate(split_df.itertuples(index=False), start=1):
            try:
                speech = _load_speech(row.audio_path)
                if len(speech) > max_samples:
                    speech = speech[:max_samples]
                    truncated_audio += 1
                full_len = len(tokenizer(row.text, add_special_tokens=False).input_ids)
                label_ids = tokenizer(
                    row.text,
                    truncation=True,
                    max_length=WHISPER_MAX_LABEL_LENGTH,
                ).input_ids
                if full_len > WHISPER_MAX_LABEL_LENGTH:
                    truncated_labels += 1
                records.append(
                    {
                        "input_features": processor.feature_extractor(
                            speech, sampling_rate=16000
                        ).input_features[0],
                        "labels": label_ids,
                    }
                )
            except Exception as exc:
                skipped += 1
                print(f"  skip [{i}/{total}] {Path(row.audio_path).name}: {exc}")
            if i % 25 == 0 or i == total:
                print(
                    f"  … {split_name} {i}/{total} done, {len(records)} ok, "
                    f"{skipped} skipped, {truncated_labels} label trunc, "
                    f"{truncated_audio} audio trunc"
                )
        if not records:
            raise RuntimeError(f"No samples processed for split '{split_name}'")
        return Dataset.from_list(records)

    ds = DatasetDict(
        {
            "train": _process_split(train_df, "train"),
            "test": _process_split(test_df, "test"),
        }
    )

    if len(ds["train"]) < 200:
        raise RuntimeError(
            f"Too few train samples after preprocessing ({len(ds['train'])}). "
            "Check audio downloads or try a different reciter."
        )

    if cfg.processed_dir.exists():
        shutil.rmtree(cfg.processed_dir)
    ds.save_to_disk(str(cfg.processed_dir))
    print(
        f"Cached processed dataset -> {cfg.processed_dir} "
        f"(train={len(ds['train'])}, test={len(ds['test'])})"
    )
    return cfg.processed_dir


def warm_hf_model_cache() -> None:
    """Download the base Whisper model once in the notebook main process.

    Without this, two `accelerate launch` workers can race on the same HF Hub
    download/cache files and hang around 'Loading weights: ~50%'.
    """
    from transformers import WhisperConfig, WhisperForConditionalGeneration, WhisperProcessor

    print(f"Caching HF model locally: {QURANY_BASE_MODEL} ...")
    WhisperProcessor.from_pretrained(QURANY_BASE_MODEL, language="ar", task="transcribe")
    WhisperConfig.from_pretrained(QURANY_BASE_MODEL)
    WhisperForConditionalGeneration.from_pretrained(QURANY_BASE_MODEL)
    print("HF model cached — GPU workers will load from disk only.")


def train_qurany_whisper(cfg: TrainConfig | None = None) -> None:
    """Main training entry (one process per GPU, launched by `accelerate launch`).

    Expects `prepare_and_cache_dataset(cfg)` to have already been run in the
    notebook main process — this function only loads the cached Arrow dataset
    from disk, it does not decode any audio itself.
    """
    import os

    from datasets import DatasetDict
    from peft import LoraConfig, get_peft_model
    from transformers import (
        EarlyStoppingCallback,
        Seq2SeqTrainer,
        Seq2SeqTrainingArguments,
        WhisperConfig,
        WhisperForConditionalGeneration,
        WhisperProcessor,
    )

    cfg = cfg or TrainConfig()
    cfg.kaggle_output.mkdir(parents=True, exist_ok=True)
    cfg.output_dir.mkdir(parents=True, exist_ok=True)

    if not cfg.processed_dir.exists():
        raise FileNotFoundError(
            f"{cfg.processed_dir} not found. Run prepare_and_cache_dataset(cfg) "
            "in the notebook (Cell 4) before launching training."
        )
    ds = DatasetDict.load_from_disk(str(cfg.processed_dir))

    # TrainingArguments must be created before model loading so distributed
    # state is set up cleanly in each spawned worker process.
    n_gpus = max(1, int(os.environ.get("WORLD_SIZE", "1")))
    effective_batch = (
        cfg.per_device_train_batch_size * n_gpus * cfg.gradient_accumulation_steps
    )
    steps_per_epoch = max(1, len(ds["train"]) // effective_batch)
    total_steps = int(steps_per_epoch * cfg.num_train_epochs)
    print(
        f"GPUs={n_gpus}, train_samples={len(ds['train'])}, "
        f"effective_batch={effective_batch}, est_steps≈{total_steps} "
        f"(ceiling of {cfg.num_train_epochs} epochs; early stopping may cut this short)"
    )

    ta_kwargs = dict(
        output_dir=str(cfg.output_dir),
        per_device_train_batch_size=cfg.per_device_train_batch_size,
        per_device_eval_batch_size=cfg.per_device_eval_batch_size,
        gradient_accumulation_steps=cfg.gradient_accumulation_steps,
        learning_rate=cfg.learning_rate,
        warmup_steps=cfg.warmup_steps,
        num_train_epochs=cfg.num_train_epochs,
        fp16=True,
        gradient_checkpointing=True,
        save_strategy="steps",
        save_steps=cfg.save_steps,
        logging_steps=cfg.logging_steps,
        # Skip generation during eval — the base Tarteel model's
        # generation_config is missing modern fields (lang_to_id/task_to_id)
        # that new transformers versions require, which crashes eval. We use
        # teacher-forced eval_loss instead (still monotonic with WER) for
        # early stopping / best-checkpoint selection. Real WER + mistake
        # detection is measured post-training by run_external_evaluation().
        predict_with_generate=False,
        load_best_model_at_end=True,
        metric_for_best_model="loss",
        greater_is_better=False,
        save_total_limit=4,
        remove_unused_columns=False,
        label_names=["labels"],
        dataloader_num_workers=0,
        report_to=[],
        seed=cfg.seed,
        ddp_find_unused_parameters=False,
    )
    try:
        training_args = Seq2SeqTrainingArguments(
            **ta_kwargs,
            eval_strategy="steps",
            eval_steps=cfg.eval_steps,
        )
    except TypeError:
        training_args = Seq2SeqTrainingArguments(
            **ta_kwargs,
            evaluation_strategy="steps",
            evaluation_steps=cfg.eval_steps,
        )

    # Load from local HF cache only — model was pre-downloaded in Cell 4.
    hf_local = {"local_files_only": True}
    processor = WhisperProcessor.from_pretrained(
        QURANY_BASE_MODEL, language="ar", task="transcribe", **hf_local
    )
    whisper_config = WhisperConfig.from_pretrained(QURANY_BASE_MODEL, **hf_local)
    model = WhisperForConditionalGeneration.from_pretrained(QURANY_BASE_MODEL, **hf_local)
    model.config.use_cache = False
    # Don't touch model.generation_config here — we use predict_with_generate=False
    # during training, and run_external_evaluation() sets everything correctly
    # for post-training inference.

    lora_config = LoraConfig(
        r=cfg.lora_r,
        lora_alpha=cfg.lora_alpha,
        target_modules=["q_proj", "v_proj"],
        lora_dropout=0.05,
        bias="none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    class DataCollatorSpeechSeq2Seq:
        def __init__(self, processor, decoder_start_token_id: int):
            self.processor = processor
            self.decoder_start_token_id = decoder_start_token_id

        def __call__(self, features):
            input_features = [{"input_features": f["input_features"]} for f in features]
            batch = self.processor.feature_extractor.pad(input_features, return_tensors="pt")
            label_features = [{"input_ids": f["labels"]} for f in features]
            labels_batch = self.processor.tokenizer.pad(label_features, return_tensors="pt")
            labels = labels_batch["input_ids"].masked_fill(
                labels_batch.attention_mask.ne(1), -100
            )
            if (labels[:, 0] == self.decoder_start_token_id).all().cpu().item():
                labels = labels[:, 1:]
            batch["labels"] = labels
            return batch

    data_collator = DataCollatorSpeechSeq2Seq(
        processor, whisper_config.decoder_start_token_id
    )

    # No compute_metrics — predict_with_generate=False means eval only returns
    # loss (Whisper generation is disabled to avoid base-model
    # generation_config incompatibilities). WER is measured post-training via
    # run_external_evaluation().
    trainer_kwargs = dict(
        args=training_args,
        model=model,
        train_dataset=ds["train"],
        eval_dataset=ds["test"],
        data_collator=data_collator,
        callbacks=[
            AutoDownloadCheckpoint(cfg.working_dir, cfg.kaggle_output)(),
            EarlyStoppingCallback(
                early_stopping_patience=cfg.early_stopping_patience,
                early_stopping_threshold=cfg.early_stopping_threshold,
            ),
        ],
    )
    import inspect

    sig = inspect.signature(Seq2SeqTrainer.__init__)
    if "processing_class" in sig.parameters:
        trainer_kwargs["processing_class"] = processor
    else:
        trainer_kwargs["tokenizer"] = processor

    trainer = Seq2SeqTrainer(**trainer_kwargs)

    trainer.train()

    # Save Qurany-branded final model (merge LoRA for easier inference).
    is_main = int(os.environ.get("LOCAL_RANK", os.environ.get("RANK", "0"))) == 0
    if is_main:
        merged = trainer.model.merge_and_unload()
        cfg.final_model_dir.mkdir(parents=True, exist_ok=True)
        merged.save_pretrained(str(cfg.final_model_dir))
        processor.save_pretrained(str(cfg.final_model_dir))
        _write_qurany_model_card(cfg.final_model_dir, cfg)

        zip_and_link(
            cfg.final_model_dir,
            QURANY_MODEL_NAME,
            cfg.working_dir,
            cfg.kaggle_output,
        )
        print(f"Done. Final model: {cfg.final_model_dir}")

        try:
            run_per_ayah_evaluation(cfg, merged, processor)
        except Exception as exc:
            print(f"Per-ayah evaluation skipped/failed: {exc}")

        try:
            run_external_evaluation(cfg, merged, processor)
        except Exception as exc:
            print(f"External evaluation skipped/failed: {exc}")


def launch_on_kaggle(num_processes: int = 2) -> None:
    """Download + pre-process, then train via `accelerate launch` (spawn)."""
    import subprocess
    import sys

    cfg = TrainConfig()
    download_training_data(cfg)
    prepare_and_cache_dataset(cfg)

    script = Path(__file__).resolve()
    cmd = [
        sys.executable,
        "-m",
        "accelerate.commands.launch",
        "--num_processes",
        str(num_processes),
        "--mixed_precision",
        "fp16",
        str(script),
        "--kaggle-train",
    ]
    print("Launching:", " ".join(cmd))
    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Qurany Whisper fine-tune")
    parser.add_argument(
        "--kaggle-train",
        action="store_true",
        help="Train only — expects data already downloaded/pre-processed in the notebook",
    )
    parser.add_argument(
        "--smoke-test",
        action="store_true",
        help="Local smoke test: 20 ayahs, 1 epoch",
    )
    args = parser.parse_args()

    if args.kaggle_train:
        train_qurany_whisper(TrainConfig())
    elif args.smoke_test:
        cfg = TrainConfig(max_train_samples=20, num_train_epochs=1, save_steps=5, eval_steps=5)
        download_training_data(cfg)
        prepare_and_cache_dataset(cfg)
        train_qurany_whisper(cfg)
    else:
        cfg = TrainConfig()
        download_training_data(cfg)
        prepare_and_cache_dataset(cfg)
        train_qurany_whisper(cfg)
