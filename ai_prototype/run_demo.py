"""
End-to-end demo: recitation audio + a known Al-Baqarah ayah number in ->
per-word tajweed feedback JSON out.

Usage:
    python run_demo.py <audio_file> <ayah_number> [--surah N]

Example (after downloading a sample -- see README):
    python run_demo.py data/samples/002006.mp3 6
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys

import asr
import align
import rules
import tajweed_data


def run(audio_path: str, ayah: int, surah: int = tajweed_data.AL_BAQARAH) -> rules.VerseFeedback:
    verse = tajweed_data.load_verse(ayah, surah=surah)
    expected_words = [w.text for w in verse.words]

    transcript = asr.transcribe(audio_path)
    timings = align.align_words(audio_path, expected_words)

    return rules.analyze_verse(verse, timings, transcript["text"])


def to_json(feedback: rules.VerseFeedback) -> dict:
    return dataclasses.asdict(feedback)


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio_file")
    parser.add_argument("ayah", type=int)
    parser.add_argument("--surah", type=int, default=tajweed_data.AL_BAQARAH)
    args = parser.parse_args()

    result = run(args.audio_file, args.ayah, args.surah)
    payload = to_json(result)
    print(json.dumps(payload, ensure_ascii=False, indent=2))

    flagged = [w for w in result.words if w.issues]
    print(f"\n{len(flagged)}/{len(result.words)} words flagged:", file=sys.stderr)
    for w in flagged:
        print(f"  [{w.index}] {w.expected!r} -> {w.recognized!r}: {w.issues}", file=sys.stderr)
