"""Tests for the best-effort Tajweed heuristics (Madd / Ghunnah / Waqf / Qalqalah)."""
from __future__ import annotations

from src.services.tajweed_heuristics import (
    check_ghunnah,
    check_madd,
    check_qalqalah,
    check_waqf,
    run_tajweed_heuristics,
)


def test_madd_flags_short_elongation():
    # "آمَنُوا" carries an explicit maddah (\u0622); most other words are ~0.5s,
    # so a 0.5s duration for the madd word should be flagged as "too quick".
    timeline = [
        {"word_index": 0, "expected_word": "قَالُوا", "start": 0.0, "end": 0.5},
        {"word_index": 1, "expected_word": "آمَنُوا", "start": 0.5, "end": 1.0},
        {"word_index": 2, "expected_word": "بِاللَّهِ", "start": 1.0, "end": 1.5},
    ]
    notes = check_madd(timeline)
    assert len(notes) == 1
    assert notes[0].word_index == 1
    assert notes[0].type == "madd"


def test_madd_not_flagged_when_elongated():
    timeline = [
        {"word_index": 0, "expected_word": "قَالُوا", "start": 0.0, "end": 0.5},
        {"word_index": 1, "expected_word": "آمَنُوا", "start": 0.5, "end": 1.4},
        {"word_index": 2, "expected_word": "بِاللَّهِ", "start": 1.4, "end": 1.9},
    ]
    notes = check_madd(timeline)
    assert notes == []


def test_ghunnah_flags_shaddah_noon():
    timeline = [
        {"word_index": 0, "expected_word": "قَالَ", "start": 0.0, "end": 0.5},
        {"word_index": 1, "expected_word": "إِنَّ", "start": 0.5, "end": 0.9},
        {"word_index": 2, "expected_word": "اللَّهَ", "start": 0.9, "end": 1.4},
    ]
    notes = check_ghunnah(timeline)
    assert len(notes) == 1
    assert notes[0].word_index == 1
    assert notes[0].type == "ghunnah"


def test_waqf_lazim_flags_missing_pause():
    timeline = [
        {"word_index": 0, "expected_word": "فِيهِ\u06D8", "start": 0.0, "end": 0.5},
        {"word_index": 1, "expected_word": "هُدًى", "start": 0.52, "end": 1.0},
    ]
    notes = check_waqf(timeline)
    assert len(notes) == 1
    assert notes[0].type == "waqf"


def test_waqf_lazim_not_flagged_when_paused():
    timeline = [
        {"word_index": 0, "expected_word": "فِيهِ\u06D8", "start": 0.0, "end": 0.5},
        {"word_index": 1, "expected_word": "هُدًى", "start": 1.2, "end": 1.7},
    ]
    notes = check_waqf(timeline)
    assert notes == []


def test_qalqalah_returns_empty_without_librosa_or_matches():
    # No qalqalah-ending words -> short-circuits before touching audio.
    timeline = [{"word_index": 0, "expected_word": "الرَّحْمَٰنِ", "start": 0.0, "end": 0.5}]
    assert check_qalqalah("nonexistent.wav", timeline) == []


def test_run_tajweed_heuristics_empty_timeline_returns_empty():
    assert run_tajweed_heuristics("nonexistent.wav", []) == []
