"""Arabic text normalization and word-similarity helpers.

These mirror the on-device logic in the Flutter client
(`recitation_screen.dart::_normalizeArabic` / `_isSimilar`) so that the
backend produces results consistent with the existing app behaviour, with a
few extra normalizations for robustness.
"""
from __future__ import annotations

import re

# Quranic diacritics (tashkeel) + superscript alef.
_DIACRITICS = re.compile(r"[\u064B-\u065F\u0670]")
# Tatweel / kashida.
_TATWEEL = "\u0640"
# Alef variants -> bare alef.
_ALEF_VARIANTS = re.compile(r"[\u0625\u0623\u0622\u0671\u0627]")
# Anything that is not an Arabic letter or whitespace.
_NON_ARABIC = re.compile(r"[^\u0621-\u064A\s]")
# Same, but also keeps diacritics/superscript alef (for harakat comparisons).
_NON_ARABIC_KEEP_HARAKAT = re.compile(r"[^\u0621-\u065F\u0670\s]")
_MULTISPACE = re.compile(r"\s+")


def normalize_arabic(text: str) -> str:
    """Return a diacritic-free, normalized form suitable for comparison.

    Steps: strip tashkeel, remove tatweel, unify alef/hamza/ya/ta-marbuta
    variants, drop non-Arabic characters, and collapse whitespace.
    """
    if not text:
        return ""

    text = _DIACRITICS.sub("", text)
    text = text.replace(_TATWEEL, "")
    text = _ALEF_VARIANTS.sub("\u0627", text)
    # Hamza on waw / ya -> bare forms.
    text = text.replace("\u0624", "\u0648")  # ؤ -> و
    text = text.replace("\u0626", "\u064A")  # ئ -> ي
    # Alef maqsura -> ya.
    text = text.replace("\u0649", "\u064A")
    # Ta marbuta -> ha.
    text = text.replace("\u0629", "\u0647")
    # Standalone hamza removed.
    text = text.replace("\u0621", "")
    text = _NON_ARABIC.sub("", text)
    text = _MULTISPACE.sub(" ", text).strip()
    return text


def normalize_arabic_keep_harakat(text: str) -> str:
    """Like `normalize_arabic` but preserves tashkeel (diacritics).

    Used to compare harakat between two words that already matched on base
    letters, so a correctly-pronounced word read with the wrong short vowels
    can still be flagged (see `services/alignment_service.py`).
    """
    if not text:
        return ""

    text = text.replace(_TATWEEL, "")
    text = _ALEF_VARIANTS.sub("\u0627", text)
    text = text.replace("\u0624", "\u0648")  # ؤ -> و
    text = text.replace("\u0626", "\u064A")  # ئ -> ي
    text = text.replace("\u0649", "\u064A")  # alef maqsura -> ya
    text = text.replace("\u0629", "\u0647")  # ta marbuta -> ha
    text = text.replace("\u0621", "")
    text = _NON_ARABIC_KEEP_HARAKAT.sub("", text)
    text = _MULTISPACE.sub(" ", text).strip()
    return text


def contains_harakat(text: str) -> bool:
    """Whether `text` carries any tashkeel marks at all.

    Used to skip harakat-mistake checking entirely when the ASR backend
    doesn't output diacritics (e.g. generic faster-whisper models), so we
    don't flag every word as a false "missing harakat" mistake.
    """
    return bool(_DIACRITICS.search(text))


def normalize_words(text: str) -> list[str]:
    """Normalize then split into a list of non-empty word tokens."""
    norm = normalize_arabic(text)
    return [w for w in norm.split(" ") if w]


def word_similarity(a: str, b: str) -> float:
    """Jaccard similarity of the character sets of two words (0..1)."""
    if a == b:
        return 1.0
    set_a, set_b = set(a), set(b)
    union = set_a | set_b
    if not union:
        return 0.0
    return len(set_a & set_b) / len(union)


def _is_final_letter_variant(a: str, b: str, max_diff: int = 1) -> bool:
    """True when one word is the other with up to `max_diff` trailing
    letters missing (e.g. "امن" recited as "ام", or "قل" recited as "ق").

    Scoped tightly to *one* dropped letter so it only forgives the specific
    "mispronounced/dropped final letter" case, not arbitrary truncation
    (e.g. "كفروا" -> "كف" is NOT covered). Short words in particular lose too
    much of their character overlap for the Jaccard-based `word_similarity`
    to forgive a single missing letter, so this is checked separately.
    """
    if not a or not b or a == b:
        return False
    shorter, longer = (a, b) if len(a) < len(b) else (b, a)
    diff = len(longer) - len(shorter)
    if diff == 0 or diff > max_diff:
        return False
    return longer.startswith(shorter)


def is_similar(a: str, b: str, threshold: float = 0.6) -> bool:
    """Whether two normalized words are "close enough" to be a partial match."""
    if a == b:
        return True
    if _is_final_letter_variant(a, b):
        return True
    return word_similarity(a, b) > threshold


# Normalized tokens for بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ (after normalize_arabic).
_BASMALLAH_TOKENS = ("بسم", "الله", "الرحمن", "الرحيم")


def strip_leading_basmallah(text: str) -> str:
    """Remove an optional leading Basmallah prefix from [text].

    Used by المصحف المعلم so reciting (or skipping) the opening Basmallah
    does not affect scoring. Partial prefixes (e.g. only بسم الله) are also
    stripped when they match from the start.
    """
    if not text or not text.strip():
        return text

    original_words = [w for w in text.split() if w.strip()]
    if not original_words:
        return text

    norm_words = [normalize_arabic(w) for w in original_words]
    skip = 0
    for expected in _BASMALLAH_TOKENS:
        if skip >= len(norm_words):
            break
        token = norm_words[skip]
        if token == expected or is_similar(token, expected):
            skip += 1
        else:
            break

    if skip == 0:
        return text
    return " ".join(original_words[skip:]).strip()
