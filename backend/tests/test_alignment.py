"""Tests for word alignment and error classification."""
from __future__ import annotations

from src.services.alignment_service import analyze_alignment

REF = "عَمَّ يَتَسَاءَلُونَ عَنِ النَّبَإِ الْعَظِيمِ"


def test_perfect_match_scores_100():
    result = analyze_alignment(REF, REF)
    assert result["similarity_score"] == 100.0
    assert result["mistakes"] == 0
    assert result["errors"] == []
    assert result["matched_words"] == result["total_words"] == 5
    # REF has harakat and matches itself exactly -> fully checked, no mistakes.
    assert result["harakat_checked"] == 5
    assert result["harakat_mistakes"] == 0
    assert result["harakat_score"] == 100.0


def test_omission_detected():
    # Drop the last word "العظيم".
    recited = "عَمَّ يَتَسَاءَلُونَ عَنِ النَّبَإِ"
    result = analyze_alignment(REF, recited)
    types = [e["type"] for e in result["errors"]]
    assert "omission" in types
    assert result["matched_words"] == 4
    assert result["mistakes"] == 1


def test_addition_detected():
    recited = REF + " زِيَادَةٌ"
    result = analyze_alignment(REF, recited)
    additions = [e for e in result["errors"] if e["type"] == "addition"]
    assert len(additions) == 1
    # Additions do not reduce matched reference words.
    assert result["matched_words"] == 5
    assert result["similarity_score"] == 100.0


def test_substitution_detected():
    recited = "عَمَّ يَتَسَاءَلُونَ عَنِ الْكِتَابِ الْعَظِيمِ"
    result = analyze_alignment(REF, recited)
    subs = [e for e in result["errors"] if e["type"] == "substitution"]
    assert len(subs) == 1
    assert subs[0]["wordIndex"] == 3


def test_empty_recitation_all_omissions():
    result = analyze_alignment(REF, "")
    assert result["similarity_score"] == 0.0
    assert result["matched_words"] == 0
    assert all(e["type"] == "omission" for e in result["errors"])
    assert len(result["errors"]) == 5


def test_sequence_error_detected():
    # Swap "عن" and "النبإ".
    recited = "عَمَّ يَتَسَاءَلُونَ النَّبَإِ عَنِ الْعَظِيمِ"
    result = analyze_alignment(REF, recited)
    types = [e["type"] for e in result["errors"]]
    assert "sequence" in types


def test_word_timeline_maps_matched_words_to_timings():
    hyp_word_timings = [
        {"word": w, "start": i * 1.0, "end": i * 1.0 + 0.8}
        for i, w in enumerate(REF.split())
    ]
    result = analyze_alignment(REF, REF, hyp_word_timings=hyp_word_timings)
    assert len(result["word_timeline"]) == 5
    first = result["word_timeline"][0]
    assert first["word_index"] == 0
    assert first["start"] == 0.0
    assert first["end"] == 0.8


def test_word_timeline_skips_omissions():
    # Only the first two words were recited -> only 2 timeline entries.
    recited = "عَمَّ يَتَسَاءَلُونَ"
    hyp_word_timings = [
        {"word": "عم", "start": 0.0, "end": 0.5},
        {"word": "يتسالون", "start": 0.5, "end": 1.2},
    ]
    result = analyze_alignment(REF, recited, hyp_word_timings=hyp_word_timings)
    assert len(result["word_timeline"]) == 2


def test_missing_final_letter_counts_as_match_not_mistake():
    # Drop the last letter of "النبإ" ("النب") and "العظيم" ("العظي").
    recited = "عَمَّ يَتَسَاءَلُونَ عَنِ النَّب الْعَظِي"
    result = analyze_alignment(REF, recited)
    assert result["mistakes"] == 0
    assert result["matched_words"] == 5
    assert result["similarity_score"] == 100.0


## Dedicated reference/recitation pair for harakat tests: same base letters
## (ك ت ب) in the 3rd word, differing only by short-vowel diacritics
## ("كَتَبَ" kataba vs "كُتِبَ" kutiba) -- avoids alef/hamza-variant letters
## (e.g. أ/إ) which normalize to the same base letter and would otherwise
## make a real harakat-only difference indistinguishable from a letter fix.
_HARAKAT_REF = "قَالَ الرَّجُلُ كَتَبَ الدَّرْسَ"


def test_harakat_mistake_flagged_but_scored_separately_from_words():
    recited = "قَالَ الرَّجُلُ كُتِبَ الدَّرْسَ"
    result = analyze_alignment(_HARAKAT_REF, recited)
    types = [e["type"] for e in result["errors"]]
    assert "harakat" in types
    harakat_error = next(e for e in result["errors"] if e["type"] == "harakat")
    assert harakat_error["wordIndex"] == 2

    # Word score: letters are all correct, so a harakat-only mistake must
    # NOT count against it (the two scores are fully independent).
    assert result["mistakes"] == 0
    assert result["matched_words"] == 4
    assert result["similarity_score"] == 100.0

    # Harakat score: 1 wrong out of 4 checkable words.
    assert result["harakat_mistakes"] == 1
    assert result["harakat_checked"] == 4
    assert result["harakat_score"] == 75.0


def test_harakat_check_skipped_when_transcript_has_no_diacritics():
    # A plain (non-diacritized) transcript, as faster-whisper would produce,
    # must not be penalized for "missing" harakat it was never asked to output,
    # and the harakat score should be reported as unavailable (None), not 0.
    recited = "قال الرجل كتب الدرس"
    result = analyze_alignment(_HARAKAT_REF, recited)
    types = [e["type"] for e in result["errors"]]
    assert "harakat" not in types
    assert result["mistakes"] == 0
    assert result["harakat_checked"] == 0
    assert result["harakat_score"] is None


def test_harakat_check_disabled_via_settings(monkeypatch):
    from src.services import alignment_service

    monkeypatch.setattr(alignment_service.settings, "enable_harakat_check", False)
    recited = "قَالَ الرَّجُلُ كُتِبَ الدَّرْسَ"
    result = analyze_alignment(_HARAKAT_REF, recited)
    types = [e["type"] for e in result["errors"]]
    assert "harakat" not in types
    assert result["mistakes"] == 0
    assert result["harakat_checked"] == 0
    assert result["harakat_score"] is None
