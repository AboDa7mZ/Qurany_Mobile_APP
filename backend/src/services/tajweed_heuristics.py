"""Best-effort Tajweed heuristics: Madd, Ghunnah, Waqf, Qalqalah.

These are **not** a trained Tajweed classifier — they are lightweight,
explainable heuristics layered on top of ASR word-level timestamps (see
`alignment_service.analyze_alignment`'s `word_timeline`) and, for Qalqalah, a
short slice of raw audio. They exist as a "free" (no extra training data or
GPU time) Tajweed-adjacent feature that general-purpose Quran-ASR competitors
like Tarteel don't expose in their public app — not a certified tajweed judge.

Limitations (documented on purpose, not hidden):
  - Word timing comes from Whisper's own alignment, which is approximate for
    word boundaries in fast, continuous recitation.
  - Duration thresholds are computed *relative* to the reciter's own median
    word duration (not fixed milliseconds), so they adapt to different
    reciting speeds, but they remain a proxy for "elongated enough", not a
    letter-count-accurate Madd judge.
  - The Qalqalah "bounce" detector works on raw waveform energy and can be
    fooled by background noise or a low-quality microphone.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass

logger = logging.getLogger(__name__)

# Explicit madd marker (maddah / combining maddah) or a base letter (alef/waw/ya)
# carrying a superscript-alef style dagger (common in "hٰذا"-style obligatory madd).
_MADD_MARKERS = re.compile(r"[\u0622\u0653]|[\u0627\u0648\u064A]\u0670")
# Noon/meem with shaddah -> Ghunnah (idgham/ikhfa/mushaddad noon-meem).
# Shaddah and the accompanying vowel diacritic can be encoded in either order
# (letter+vowel+shadda or letter+shadda+vowel depending on input method), so
# allow 0-2 other diacritics between the base letter and the shadda itself.
_GHUNNAH_LETTERS = re.compile(r"[\u0646\u0645][\u064B-\u0650\u0652\u0670]{0,2}\u0651")
_QALQALAH_LETTERS = set("قطبجد")
_WAQF_LAZIM = "\u06D8"  # ۘ - compulsory stop
_WAQF_SIGNS = re.compile("[\u06D6-\u06ED]")


@dataclass
class TajweedNote:
    type: str  # "madd" | "ghunnah" | "waqf" | "qalqalah"
    word_index: int
    expected_word: str
    message: str
    severity: str = "info"  # "info" | "warning"

    def to_dict(self) -> dict:
        return {
            "type": self.type,
            "wordIndex": self.word_index,
            "expectedWord": self.expected_word,
            "message": self.message,
            "severity": self.severity,
        }


def _median_duration(word_timeline: list[dict]) -> float:
    durations = [
        max(0.0, w["end"] - w["start"])
        for w in word_timeline
        if w.get("end", 0) > w.get("start", 0)
    ]
    if not durations:
        return 0.0
    durations.sort()
    return durations[len(durations) // 2]


def check_madd(word_timeline: list[dict]) -> list[TajweedNote]:
    """Flag Madd (elongation) letters whose spoken duration looks short
    relative to the reciter's own median word duration."""
    median = _median_duration(word_timeline)
    if median <= 0:
        return []
    notes: list[TajweedNote] = []
    for w in word_timeline:
        word = w["expected_word"]
        if not _MADD_MARKERS.search(word):
            continue
        duration = w["end"] - w["start"]
        if duration < median * 1.3:
            notes.append(
                TajweedNote(
                    type="madd",
                    word_index=w["word_index"],
                    expected_word=word,
                    message=(
                        "This word contains a Madd (elongation) letter but was "
                        "recited quickly — check the elongation count (2/4/6 harakat)."
                    ),
                    severity="warning",
                )
            )
    return notes


def check_ghunnah(word_timeline: list[dict]) -> list[TajweedNote]:
    """Flag shaddah-marked noon/meem (Ghunnah) whose duration looks short."""
    median = _median_duration(word_timeline)
    if median <= 0:
        return []
    notes: list[TajweedNote] = []
    for w in word_timeline:
        word = w["expected_word"]
        if not _GHUNNAH_LETTERS.search(word):
            continue
        duration = w["end"] - w["start"]
        if duration < median * 1.15:
            notes.append(
                TajweedNote(
                    type="ghunnah",
                    word_index=w["word_index"],
                    expected_word=word,
                    message=(
                        "This word has a shaddah on ن/م (Ghunnah) — hold the "
                        "nasal sound for ~2 harakat."
                    ),
                    severity="info",
                )
            )
    return notes


def check_waqf(word_timeline: list[dict]) -> list[TajweedNote]:
    """Flag compulsory-stop (waqf lazim ۘ) marks with no pause before the next word."""
    notes: list[TajweedNote] = []
    ordered = sorted(word_timeline, key=lambda w: w["word_index"])
    for i, w in enumerate(ordered):
        word = w["expected_word"]
        if _WAQF_LAZIM not in word:
            continue
        if i + 1 >= len(ordered):
            continue
        gap = ordered[i + 1]["start"] - w["end"]
        if gap < 0.25:
            notes.append(
                TajweedNote(
                    type="waqf",
                    word_index=w["word_index"],
                    expected_word=word,
                    message=(
                        "This word is marked with a compulsory stop (waqf lazim, ۘ) "
                        "— a short pause is expected here before continuing."
                    ),
                    severity="warning",
                )
            )
    return notes


def check_qalqalah(audio_path: str, word_timeline: list[dict]) -> list[TajweedNote]:
    """Flag qalqalah letters (ق ط ب ج د) with no audible 'bounce' detected in
    a short window right after the word ends.

    Loads the raw waveform once and looks for a brief energy dip-then-rise
    pattern (the qalqalah "echo") in the ~150ms right after the word boundary.
    """
    candidates = [
        w
        for w in word_timeline
        if w.get("expected_word") and w["expected_word"][-1] in _QALQALAH_LETTERS
    ]
    if not candidates:
        return []

    try:
        import librosa
        import numpy as np
    except ImportError:
        logger.info("librosa/numpy not installed; skipping qalqalah acoustic check.")
        return []

    try:
        speech, sr = librosa.load(audio_path, sr=16000, mono=True)
    except Exception as exc:
        logger.warning("Could not load audio for qalqalah check: %s", exc)
        return []

    notes: list[TajweedNote] = []
    frame = 256
    for w in candidates:
        end_sample = int(w["end"] * sr)
        window = speech[end_sample : end_sample + int(0.15 * sr)]
        if len(window) < frame * 3:
            continue
        rms = np.array(
            [
                float(np.sqrt(np.mean(window[i : i + frame] ** 2)))
                for i in range(0, len(window) - frame, frame)
            ]
        )
        if rms.max() <= 1e-6:
            continue
        rms_norm = rms / rms.max()
        trough_idx = int(rms_norm.argmin())
        has_bounce = trough_idx < len(rms_norm) - 1 and rms_norm[trough_idx] < 0.35 and rms_norm[-1] > 0.4
        if not has_bounce:
            notes.append(
                TajweedNote(
                    type="qalqalah",
                    word_index=w["word_index"],
                    expected_word=w["expected_word"],
                    message=(
                        f"Word ends in a Qalqalah letter ('{w['expected_word'][-1]}') — "
                        "no audible bounce/echo detected; make sure to pronounce it clearly."
                    ),
                    severity="info",
                )
            )
    return notes


def run_tajweed_heuristics(audio_path: str, word_timeline: list[dict]) -> list[dict]:
    """Run all heuristics and return a flat list of note dicts, sorted by word index."""
    if not word_timeline:
        return []
    notes = (
        check_madd(word_timeline)
        + check_ghunnah(word_timeline)
        + check_waqf(word_timeline)
        + check_qalqalah(audio_path, word_timeline)
    )
    notes.sort(key=lambda n: n.word_index)
    return [n.to_dict() for n in notes]
