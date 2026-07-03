#!/usr/bin/env python3
"""Smoke-test Hafs + Bazzi fine-tuned models and save JSON analysis output.

Downloads a short Al-Baqarah ayah clip, runs the full analyze pipeline for
each riwayah, and writes pretty-printed JSON files under backend/test_outputs/.

Usage (from backend/):
  python scripts/test_both_models.py
  python scripts/test_both_models.py --audio path/to/recitation.mp3 --start-ayah 2
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))
OUT_DIR = BACKEND / "test_outputs"

# Al-Baqarah 2:2 — short, well-known clip (Alafasy / Hafs numbering).
_DEFAULT_AUDIO_URL = "https://everyayah.com/data/Alafasy_128kbps/002002.mp3"


def _download(url: str, dest: Path) -> None:
    print(f"Downloading sample audio -> {dest}")
    urllib.request.urlretrieve(url, dest)


def _configure_hafs() -> None:
    os.environ["ASR_BACKEND"] = "transformers"
    os.environ.setdefault(
        "CUSTOM_MODEL_PATH",
        str(BACKEND / "models" / "qurany-whisper-base-al-baqarah"),
    )
    os.environ.setdefault(
        "BAZZI_MODEL_PATH",
        str(BACKEND / "models" / "qurany-whisper-base-al-baqarah-bazzi"),
    )


def _reset_services() -> None:
    from src.config import get_settings

    get_settings.cache_clear()
    from src.services.asr_service import asr_service

    asr_service._backends.clear()


def _run_analyze(
    audio: Path,
    *,
    riwayah: str,
    start_ayah: int | None,
    end_ayah: int | None,
) -> dict:
    from src.services.analysis_service import analyze_audio

    return analyze_audio(
        2,
        str(audio),
        start_ayah=start_ayah,
        end_ayah=end_ayah,
        auto_detect_ayah_range=start_ayah is None,
        riwayah=riwayah,
    )


def _save(name: str, payload: dict) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def _summarize(label: str, result: dict) -> None:
    print(f"\n{'=' * 60}")
    print(f"  {label}")
    print(f"{'=' * 60}")
    print(f"  riwayah           : {result.get('riwayah')}")
    print(f"  asr_backend       : {result.get('asr_backend')}")
    print(f"  asr_model         : {result.get('asr_model')}")
    print(f"  similarity_score  : {result.get('similarity_score')}%")
    print(f"  matched/total     : {result.get('matched_words')}/{result.get('total_words')}")
    print(f"  mistakes          : {result.get('mistakes')}")
    print(f"  harakat_score     : {result.get('harakat_score')}")
    print(f"  reference_scope   : {result.get('reference_scope')}")
    ayah_start = result.get("detected_ayah_start") or result.get("detectedAyahStart")
    ayah_end = result.get("detected_ayah_end") or result.get("detectedAyahEnd")
    if ayah_start:
        print(f"  ayah window       : {ayah_start}-{ayah_end}")
    print(f"  transcribed (80c) : {result.get('transcribed_text', '')[:80]}...")
    errors = result.get("errors") or []
    if errors:
        print(f"  first 3 errors:")
        for e in errors[:3]:
            print(
                f"    [{e.get('type')}] idx={e.get('wordIndex')} "
                f"expected={e.get('expectedWord')!r} recited={e.get('recitedWord')!r}"
            )
    else:
        print("  errors            : (none — perfect match)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Test Hafs + Bazzi ASR models")
    parser.add_argument("--audio", type=Path, help="Local audio file (mp3/wav)")
    parser.add_argument("--start-ayah", type=int, help="Explicit ayah start (Hafs numbering)")
    parser.add_argument("--end-ayah", type=int)
    args = parser.parse_args()

    _configure_hafs()
    _reset_services()

    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    if args.audio:
        audio = args.audio.expanduser().resolve()
        if not audio.is_file():
            print(f"ERROR: audio not found: {audio}", file=sys.stderr)
            return 1
    else:
        temp_dir = tempfile.TemporaryDirectory(prefix="qurany-model-test-")
        audio = Path(temp_dir.name) / "002002.mp3"
        _download(_DEFAULT_AUDIO_URL, audio)

    print("Testing fine-tuned Whisper models on Al-Baqarah audio...")
    print(f"  audio: {audio.name}")

    # --- analyze-text demo (instant, shows error JSON shape) ---
    from src.services.analysis_service import analyze_text

    demo = analyze_text(
        2,
        "ذلك الكتاب لا ريب فيه",  # partial + missing tashkeel
        start_ayah=2,
        end_ayah=2,
        riwayah="hafs",
    )
    demo_path = _save("demo_analyze_text_hafs_ayah2.json", demo)
    print(f"\nSaved analyze-text demo (with intentional partial recitation): {demo_path}")

    results: dict[str, dict] = {}
    for riwayah in ("hafs", "bazzi"):
        print(f"\nLoading {riwayah} model and transcribing (CPU — may take 1-3 min)...")
        try:
            report = _run_analyze(
                audio,
                riwayah=riwayah,
                start_ayah=args.start_ayah,
                end_ayah=args.end_ayah,
            )
        except Exception as exc:
            print(f"ERROR ({riwayah}): {exc}", file=sys.stderr)
            return 2
        out_name = f"analyze_audio_{riwayah}_baqarah.json"
        out_path = _save(out_name, report)
        results[riwayah] = report
        _summarize(f"{riwayah.upper()} — saved to {out_path.name}", report)

    combined = _save("analyze_audio_both_riwayat.json", results)
    print(f"\nCombined report: {combined}")

    if temp_dir is not None:
        temp_dir.cleanup()

    print("\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
