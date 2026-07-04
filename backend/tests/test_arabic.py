"""Tests for Arabic normalization and similarity helpers."""
from __future__ import annotations

from src.utils.arabic import (
    contains_harakat,
    is_similar,
    normalize_arabic,
    normalize_arabic_keep_harakat,
    normalize_words,
    strip_leading_basmallah,
    word_similarity,
)


def test_strips_diacritics():
    assert normalize_arabic("عَمَّ يَتَسَاءَلُونَ") == "عم يتسالون"


def test_normalizes_alef_variants():
    assert normalize_arabic("إِنَّ") == normalize_arabic("انَّ") == "ان"


def test_removes_tatweel_and_non_arabic():
    assert normalize_arabic("الـرحمن 123 .") == "الرحمن"


def test_normalize_words_drops_empty():
    assert normalize_words("  الَّذِي   هُمْ  ") == ["الذي", "هم"]


def test_identical_words_are_fully_similar():
    assert word_similarity("هم", "هم") == 1.0


def test_is_similar_threshold():
    # share most characters
    assert is_similar("يعلمون", "تعلمون", threshold=0.6)
    # completely different
    assert not is_similar("نبا", "عظيم", threshold=0.6)


def test_is_similar_allows_missing_final_letter():
    # Long enough that Jaccard already forgives it, kept for regression safety.
    assert is_similar("امن", "ام", threshold=0.6)
    assert is_similar("الضالين", "الضالي", threshold=0.6)
    # Short words: Jaccard alone would reject these (too few shared chars),
    # but dropping exactly the final letter should still be forgiven.
    assert is_similar("من", "م", threshold=0.6)
    assert is_similar("قل", "ق", threshold=0.6)


def test_is_similar_rejects_more_than_final_letter():
    # Dropping two+ letters is a bigger miss than "final letter" leniency
    # is meant to cover, and stays a mistake.
    assert not is_similar("كفروا", "كف", threshold=0.6)


def test_contains_harakat():
    assert contains_harakat("عَمَّ")
    assert not contains_harakat("عم")
    assert not contains_harakat("")


def test_normalize_arabic_keep_harakat_round_trips_to_plain_normalize():
    original = "عَمَّ يَتَسَاءَلُونَ"
    kept = normalize_arabic_keep_harakat(original)
    # Stripping diacritics from the harakat-preserving form must match the
    # plain normalizer exactly, so the two stay comparable index-for-index.
    assert normalize_arabic(kept) == normalize_arabic(original)
    # But harakat must actually still be present (i.e. this isn't a no-op).
    assert contains_harakat(kept)


def test_strip_leading_basmallah_full_prefix():
    text = "بسم الله الرحمن الرحيم الم ذٰلِكَ"
    assert strip_leading_basmallah(text) == "الم ذٰلِكَ"


def test_strip_leading_basmallah_no_prefix():
    text = "الحمد لله رب العالمين"
    assert strip_leading_basmallah(text) == text


def test_strip_leading_basmallah_partial_prefix():
    text = "بسم الله الحمد لله"
    assert strip_leading_basmallah(text) == "الحمد لله"
