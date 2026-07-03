"""
Pure-Python/DSP rule engine: combines tajweed_data.VerseData (what the rules
require), align.WordTiming (when each word was actually recited), and
asr.transcribe's text (what was actually recited) into per-word feedback.

No training/fine-tuning involved -- see ai_prototype/README.md for why that's
out of scope for this milestone, and what it would take to add real
acoustic mispronunciation detection later.
"""

from __future__ import annotations

import difflib
import re
from dataclasses import dataclass, field

from rapidfuzz import fuzz

from align import WordTiming
from tajweed_data import VerseData, WordSpan

# Characters where Uthmani Qur'anic orthography and the "modern" Arabic
# orthography tarteel-ai/whisper-base-ar-quran was trained to output
# genuinely disagree on spelling convention, despite identical pronunciation:
#   - alef wasla (ٱ) / bare hamza (ء) as a word-initial seat vs. plain
#     alef/hamza-on-alef
#   - the Tanzil Uthmani text spells the "madda" combination in DECOMPOSED
#     form -- alef (ا) + combining maddah above (U+0653) + hamza (ء),
#     e.g. سَوَآءٌ is really سَوَآءٌ under the hood -- rather than the
#     precomposed آ most modern text (and this ASR model's output) uses
#   - sukun (ْ) is often omitted in Uthmani script where it's implied by a
#     following consonant cluster, but modern transcription writes it
#     explicitly (and vice versa)
#   - small-high marks (silent-letter circles, waqf/rub-el-hizb/sajda signs,
#     U+06D6-U+06ED) that aren't pronounced at all -- except a few (like the
#     small high yeh, U+06E6) that mark an elided-but-pronounced letter; see
#     README known-limitations for why those aren't fully handled here
#   - dagger alif / superscript alef (ٰ), used for a long "a" vowel, vs. a
#     plain alef
#   - alef maqsura (ى) at word-final position, used interchangeably with
#     plain yeh (ي) between Uthmani and modern spelling
# Comparing raw text against these treats near-every word as a "mismatch".
# Fold them away before judging equality/similarity; the ORIGINAL text is
# still what's shown to the user, this normalization is comparison-only.
_SMALL_HIGH_MARKS_RE = re.compile("[ۖ-ۭ]")
_SUKUN = "ْ"
_MADDAH_ABOVE = "ٓ"  # combining maddah above, U+0653
_DAGGER_ALEF = "ٰ"  # superscript alef, U+0670
_ALEF_MAQSURA = "ى"  # U+0649
_YEH = "ي"  # U+064A
_ALEF_HAMZA_FAMILY = "ءآأإٱ"  # ء آ أ إ ٱ
_PLAIN_ALEF = "ا"  # ا


def _normalize_for_comparison(word: str) -> str:
    word = _SMALL_HIGH_MARKS_RE.sub("", word)
    word = word.replace(_SUKUN, "")
    word = word.replace(_MADDAH_ABOVE, "")
    word = word.replace(_ALEF_MAQSURA, _YEH)
    for ch in _ALEF_HAMZA_FAMILY + _DAGGER_ALEF:
        word = word.replace(ch, _PLAIN_ALEF)
    return word

# Rough stretch multipliers relative to a normal (non-elongated) syllable's
# duration-per-character, expressed as mora counts (2/4/6 harakah-lengths).
# These are calibratable heuristic constants, not authoritative tajweed
# timing values -- see README for how to calibrate against reference qari
# audio before trusting the absolute flags.
MADD_MULTIPLIERS = {
    "madd_2": 1.3,
    "madd_246": 1.5,
    "madd_4": 1.6,
    "madd_muttasil": 1.7,
    "madd_munfasil": 1.7,
    "madd_6": 2.0,
}
MADD_TOLERANCE = (0.55, 1.9)  # (low, high) multiplier band around expected duration

WAQF_MUST_PAUSE = {"meem"}       # obligatory stop
WAQF_MUST_NOT_PAUSE = {"la"}     # do not stop
PAUSE_THRESHOLD_MS = 220.0       # gap between words counted as a pause


@dataclass
class WordFeedback:
    index: int
    expected: str
    recognized: str | None
    issues: list[str] = field(default_factory=list)


@dataclass
class VerseFeedback:
    surah: int
    ayah: int
    recognized_text: str
    words: list[WordFeedback]


def _baseline_ms_per_char(words: list[WordSpan], timings: list[WordTiming]) -> float:
    samples = []
    for w, t in zip(words, timings):
        if w.rules and any(r.startswith("madd") for r in w.rules):
            continue
        duration = t.end_ms - t.start_ms
        char_count = len(w.text)
        if duration > 0 and char_count > 0:
            samples.append(duration / char_count)
    if not samples:
        return 0.0
    samples.sort()
    return samples[len(samples) // 2]  # median


def check_madd(words: list[WordSpan], timings: list[WordTiming]) -> dict[int, list[str]]:
    """Flag words whose aligned duration falls outside the expected band for
    their madd rule, relative to this recitation's own pace (median ms/char
    of non-madd words), not an absolute duration.
    """
    baseline = _baseline_ms_per_char(words, timings)
    issues: dict[int, list[str]] = {}
    if baseline <= 0:
        return issues

    for w, t in zip(words, timings):
        madd_rules = [r for r in w.rules if r in MADD_MULTIPLIERS]
        if not madd_rules:
            continue
        rule = madd_rules[0]
        expected = baseline * len(w.text) * MADD_MULTIPLIERS[rule]
        actual = t.end_ms - t.start_ms
        low, high = MADD_TOLERANCE
        if actual < expected * low:
            issues.setdefault(w.index, []).append(f"{rule}_too_short")
        elif actual > expected * high:
            issues.setdefault(w.index, []).append(f"{rule}_too_long")
    return issues


def check_waqf(words: list[WordSpan], timings: list[WordTiming]) -> dict[int, list[str]]:
    """Flag missing obligatory pauses and unwanted pauses at "do not stop"
    marks, using the silence gap between consecutive aligned words as the
    pause signal.
    """
    issues: dict[int, list[str]] = {}
    for i, w in enumerate(words):
        if not w.waqf or i + 1 >= len(timings):
            continue
        gap = timings[i + 1].start_ms - timings[i].end_ms
        paused = gap >= PAUSE_THRESHOLD_MS
        if w.waqf in WAQF_MUST_PAUSE and not paused:
            issues.setdefault(w.index, []).append("missed_obligatory_stop")
        elif w.waqf in WAQF_MUST_NOT_PAUSE and paused:
            issues.setdefault(w.index, []).append("stopped_where_forbidden")
    return issues


def check_words(words: list[WordSpan], recognized_text: str) -> dict[int, tuple[str | None, list[str]]]:
    """Align the ASR transcript against the expected verse word-by-word and
    flag mismatches. Both sides are compared through
    _normalize_for_comparison first (see its docstring) -- without that,
    every word differs due to Uthmani-vs-modern spelling convention alone.
    A normalized exact match is fully correct; a close-but-not-exact
    normalized match is a likely harakat (vowel/shadda) slip; a distant
    match is effectively a different word.
    """
    expected_words = [w.text for w in words]
    recognized_words = recognized_text.split()
    norm_expected = [_normalize_for_comparison(w) for w in expected_words]
    norm_recognized = [_normalize_for_comparison(w) for w in recognized_words]

    result: dict[int, tuple[str | None, list[str]]] = {}
    matcher = difflib.SequenceMatcher(None, norm_expected, norm_recognized, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            for offset, exp_idx in enumerate(range(i1, i2)):
                result[words[exp_idx].index] = (recognized_words[j1 + offset], [])
            continue
        if tag == "replace":
            for offset, exp_idx in enumerate(range(i1, i2)):
                rec_idx = j1 + offset
                if rec_idx < j2:
                    recognized = recognized_words[rec_idx]
                    similarity = fuzz.ratio(norm_expected[exp_idx], norm_recognized[rec_idx])
                    issue = "harakat_mismatch" if similarity >= 85 else "word_mismatch"
                    result[words[exp_idx].index] = (recognized, [issue])
                else:
                    result[words[exp_idx].index] = (None, ["omitted"])
        elif tag == "delete":
            for exp_idx in range(i1, i2):
                result[words[exp_idx].index] = (None, ["omitted"])
        # "insert" (extra recognized words not in reference) isn't attached
        # to any expected word; surfaced separately by callers if needed.
    return result


def analyze_verse(
    verse: VerseData,
    timings: list[WordTiming],
    recognized_text: str,
) -> VerseFeedback:
    if len(timings) != len(verse.words):
        raise ValueError(
            f"timings length ({len(timings)}) must match verse word count ({len(verse.words)})"
        )

    madd_issues = check_madd(verse.words, timings)
    waqf_issues = check_waqf(verse.words, timings)
    word_issues = check_words(verse.words, recognized_text)

    feedback_words = []
    for w in verse.words:
        recognized, issues = word_issues.get(w.index, (w.text, []))
        issues = list(issues)
        issues.extend(madd_issues.get(w.index, []))
        issues.extend(waqf_issues.get(w.index, []))
        feedback_words.append(WordFeedback(index=w.index, expected=w.text, recognized=recognized, issues=issues))

    return VerseFeedback(
        surah=verse.surah,
        ayah=verse.ayah,
        recognized_text=recognized_text,
        words=feedback_words,
    )
