"""
Speech-to-text for Quran recitation, using Tarteel AI's Quran-tuned Whisper
checkpoint instead of the plain OpenAI Whisper used in ../Test.py.

tarteel-ai/whisper-base-ar-quran (https://huggingface.co/tarteel-ai/whisper-base-ar-quran)
is Whisper-base fine-tuned on Tarteel's crowdsourced Quran recitation corpus,
so it should be far less prone to the "hallucinate a similar-sounding verse"
failure Test.py hit on plain Whisper.

Whether this checkpoint's transcriptions preserve tashkeel (harakat) is not
documented anywhere reliable — it must be checked empirically the first time
this runs (see transcribe() docstring / run_demo.py). Verified against a
real Alafasy recitation of Al-Baqarah 2:6: the output IS fully diacritized
and near-exactly matches the reference verse, so word-level ASR-vs-reference
comparison in rules.py doubles as a harakat-level check.

Any verse longer than Whisper's 30s window (e.g. 2:26, ~43s) forces the
`transformers` pipeline into chunked long-form decoding, which requires
timestamp tokens to stitch chunks together -- but tarteel-ai/whisper-base-ar-quran
was published without a generation_config carrying those tokens (see
https://github.com/huggingface/transformers/issues/21878). Fixed below by
borrowing openai/whisper-base's generation_config: same architecture/tokenizer,
this checkpoint just fine-tunes the weights, so the base config's timestamp
token ids are compatible.
"""

from __future__ import annotations

from functools import lru_cache

import torch
from transformers import GenerationConfig, pipeline

from audio_utils import load_audio

MODEL_NAME = "tarteel-ai/whisper-base-ar-quran"
_BASE_CONFIG_MODEL = "openai/whisper-base"


@lru_cache(maxsize=1)
def _asr_pipeline(model_name: str = MODEL_NAME):
    device = 0 if torch.cuda.is_available() else -1
    asr = pipeline(
        "automatic-speech-recognition",
        model=model_name,
        device=device,
    )
    if getattr(asr.model.generation_config, "no_timestamps_token_id", None) is None:
        base_config = GenerationConfig.from_pretrained(_BASE_CONFIG_MODEL)
        asr.model.generation_config.no_timestamps_token_id = base_config.no_timestamps_token_id
        asr.model.generation_config.forced_decoder_ids = base_config.forced_decoder_ids
        asr.model.generation_config.lang_to_id = base_config.lang_to_id
        asr.model.generation_config.task_to_id = base_config.task_to_id
    return asr


def transcribe(audio_path: str, model_name: str = MODEL_NAME) -> dict:
    """
    Transcribe a recitation audio file.

    Returns {"text": str}. This checkpoint's published generation_config
    doesn't carry the timestamp tokens Whisper needs for return_timestamps,
    so word timing comes from align.py's CTC forced alignment instead --
    this function is only responsible for *what* was said, not *when*.
    """
    asr = _asr_pipeline(model_name)
    waveform, sr = load_audio(audio_path)
    result = asr({"raw": waveform, "sampling_rate": sr})
    return {"text": result["text"].strip()}


def has_tashkeel(text: str) -> bool:
    """True if any Arabic diacritic (harakah) codepoint is present in text."""
    return any(0x064B <= ord(ch) <= 0x0652 for ch in text)


if __name__ == "__main__":
    import sys

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    if len(sys.argv) < 2:
        print("Usage: python asr.py <audio_file>")
        raise SystemExit(1)

    out = transcribe(sys.argv[1])
    print("Text:", out["text"])
    print("Tashkeel present in output:", has_tashkeel(out["text"]))
