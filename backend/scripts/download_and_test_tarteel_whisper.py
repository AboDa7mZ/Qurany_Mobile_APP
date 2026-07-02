#!/usr/bin/env python3
"""Download and smoke-test the Tarteel Quranic Whisper ASR model.

Uses the CTranslate2 build of tarteel-ai/whisper-base-ar-quran:
  https://huggingface.co/tarteel-ai/whisper-base-ar-quran
  https://huggingface.co/OdyAsh/faster-whisper-base-ar-quran

Run from backend/:
  python scripts/download_and_test_tarteel_whisper.py
  python scripts/download_and_test_tarteel_whisper.py --audio path/to/recitation.wav
"""
from __future__ import annotations

import argparse
import re
import sys
import tempfile
import urllib.request
from pathlib import Path

# Windows consoles often default to cp1252; force UTF-8 so Arabic prints cleanly.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

# Allow `python scripts/...` without installing the package.
BACKEND_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_ROOT))

from src.config import settings  # noqa: E402
from src.services.asr_service import ASRService  # noqa: E402

# Short word-by-word clip from Quran.com (Al-Baqarah 2:38, first word).
_DEFAULT_SAMPLE_URL = (
    "https://verses.quran.com/wbw/002_038_001.mp3"
)

# Right-to-left mark — helps Arabic render in the correct direction in terminals.
_RLM = "\u200f"
_MULTISPACE = re.compile(r"\s+")


def _clean_text(text: str) -> str:
    """Collapse stray whitespace from ASR output."""
    return _MULTISPACE.sub(" ", text.strip())


def _format_timestamp(seconds: float) -> str:
    minutes, secs = divmod(int(seconds), 60)
    return f"{minutes:02d}:{secs:02d}"


def _wrap_arabic(text: str, width: int = 72) -> list[str]:
    """Wrap Arabic text at word boundaries for readable terminal output."""
    words = text.split()
    if not words:
        return []

    lines: list[str] = []
    current: list[str] = []
    current_len = 0

    for word in words:
        extra = len(word) + (1 if current else 0)
        if current and current_len + extra > width:
            lines.append(" ".join(current))
            current = [word]
            current_len = len(word)
        else:
            current.append(word)
            current_len += extra

    if current:
        lines.append(" ".join(current))
    return lines


def _print_transcription(
    *,
    audio_path: Path,
    language: str,
    duration: float,
    text: str,
    segments: list,
    line_width: int,
    save_path: Path | None,
) -> None:
    cleaned = _clean_text(text)
    body_lines = _wrap_arabic(cleaned, width=line_width)

    divider = "─" * min(line_width + 8, 80)
    out_blocks: list[str] = [
        "",
        divider,
        "  Transcription",
        divider,
        f"  Audio    : {audio_path.name}",
        f"  Language : {language}",
        f"  Duration : {_format_timestamp(duration)} ({duration:.1f}s)",
        "",
        "  Full text:",
    ]
    for line in body_lines:
        out_blocks.append(f"  {_RLM}{line}")

    if segments:
        out_blocks.extend(["", divider, "  Segments", divider])
        for i, seg in enumerate(segments, start=1):
            seg_text = _clean_text(seg.text)
            out_blocks.append(
                f"  [{i}] {_format_timestamp(seg.start)} → "
                f"{_format_timestamp(seg.end)}"
            )
            for line in _wrap_arabic(seg_text, width=line_width - 4):
                out_blocks.append(f"      {_RLM}{line}")
            out_blocks.append("")

    out_blocks.append(divider)
    rendered = "\n".join(out_blocks)
    print(rendered)

    if save_path is not None:
        save_path.write_text(rendered, encoding="utf-8")
        print(f"\nSaved to: {save_path}")


def _download_sample_audio(dest: Path) -> None:
    print(f"Downloading sample audio -> {dest}")
    urllib.request.urlretrieve(_DEFAULT_SAMPLE_URL, dest)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download and test tarteel-ai/whisper-base-ar-quran via faster-whisper."
    )
    parser.add_argument(
        "--audio",
        type=Path,
        help="Optional local audio file (wav/mp3). If omitted, downloads a short Quran clip.",
    )
    parser.add_argument(
        "--model",
        default=settings.whisper_model,
        help=f"Whisper model id or path (default: {settings.whisper_model})",
    )
    parser.add_argument(
        "--width",
        type=int,
        default=72,
        help="Max characters per line when wrapping Arabic text (default: 72).",
    )
    parser.add_argument(
        "--save",
        type=Path,
        help="Optional path to save formatted transcription as UTF-8 text.",
    )
    args = parser.parse_args()

    print("Tarteel Quranic Whisper ASR smoke test")
    print(f"  HF source model : tarteel-ai/whisper-base-ar-quran")
    print(f"  faster-whisper  : {args.model}")
    print(f"  device          : {settings.whisper_device}")
    print(f"  compute_type    : {settings.whisper_compute_type}")
    print()

    audio_path: Path
    temp_dir: tempfile.TemporaryDirectory[str] | None = None

    if args.audio:
        audio_path = args.audio.expanduser().resolve()
        if not audio_path.is_file():
            print(f"ERROR: audio file not found: {audio_path}", file=sys.stderr)
            return 1
    else:
        temp_dir = tempfile.TemporaryDirectory(prefix="tarteel-whisper-test-")
        audio_path = Path(temp_dir.name) / "sample.mp3"
        _download_sample_audio(audio_path)

    service = ASRService()
    # Override model for this run if requested.
    original_model = settings.whisper_model
    settings.whisper_model = args.model
    try:
        print("Loading model (first run downloads weights from Hugging Face)...")
        result = service.transcribe(str(audio_path), language=settings.asr_language)
    finally:
        settings.whisper_model = original_model
        if temp_dir is not None:
            temp_dir.cleanup()

    save_path = args.save
    if save_path is None and args.audio:
        save_path = audio_path.with_suffix(".transcript.txt")

    _print_transcription(
        audio_path=audio_path,
        language=result.language,
        duration=result.duration,
        text=result.text,
        segments=result.segments,
        line_width=max(40, args.width),
        save_path=save_path,
    )

    if not result.text.strip():
        print("\nWARNING: empty transcript — check audio format or model load.", file=sys.stderr)
        return 2

    print("\nOK: model downloaded and transcribed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
