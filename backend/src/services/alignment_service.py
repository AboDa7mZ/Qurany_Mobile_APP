"""Word-level alignment and error classification.

Aligns a (normalized) recited transcript against the (normalized) reference
recitation using Needleman-Wunsch dynamic programming, then classifies the
differences into the error types the Flutter client understands:

    substitution | omission | addition | sequence | harakat

Two independent scores are produced:
  - `similarity_score` / `matched_words` / `mistakes`: letters only (harakat
    never affects these, so this is exactly the pre-harakat-feature score).
  - `harakat_score` / `harakat_mistakes` / `harakat_checked`: diacritics only,
    computed over the subset of words where a harakat comparison was actually
    possible (exact letter match + the ASR output diacritics for that word).
    `harakat_score` is `None` when nothing was checkable (e.g. the transcript
    has no diacritics at all), so the UI can show "not available" instead of
    a misleading 0% or 100%.

The output dict matches the contract consumed by the app
(`recitation_screen.dart` / `recitation_session.dart`):

    {
      "similarity_score": float,          # 0..100, letters only
      "total_words": int,
      "matched_words": int,
      "mistakes": int,                    # letters only
      "errors": [{"type", "expectedWord", "recitedWord", "wordIndex"}],
      "harakat_score": float | None,      # 0..100, diacritics only
      "harakat_mistakes": int,
      "harakat_checked": int,
    }
"""
from __future__ import annotations

from dataclasses import dataclass

from ..config import settings
from ..utils.arabic import (
    contains_harakat,
    is_similar,
    normalize_arabic,
    normalize_arabic_keep_harakat,
)

# Backtrace operation kinds.
_MATCH = "match"
_SUB = "substitution"
_DEL = "omission"   # in reference, not recited
_INS = "addition"   # recited, not in reference
_HARAKAT = "harakat"  # correct letters, wrong/missing diacritics


@dataclass
class _Op:
    kind: str
    ref_index: int | None   # index into reference word list
    hyp_index: int | None   # index into hypothesis/transcribed word list (None for omissions)
    expected: str           # original reference word ("" for additions)
    recited: str            # transcribed word ("" for omissions)


def _tokenize(original_text: str) -> tuple[list[str], list[str], list[str]]:
    """Return (original_words, normalized_words, harakat_words) kept index-aligned.

    Words that normalize to empty (e.g. pure punctuation) are dropped from
    all three lists together so indices stay in sync. `harakat_words` keeps
    diacritics (tashkeel) and is only used by the harakat-mistake check.
    """
    originals: list[str] = []
    normalized: list[str] = []
    with_harakat: list[str] = []
    for raw in original_text.split():
        norm = normalize_arabic(raw)
        if not norm:
            continue
        originals.append(raw)
        normalized.append(norm)
        with_harakat.append(normalize_arabic_keep_harakat(raw))
    return originals, normalized, with_harakat


def _words_match(a: str, b: str, threshold: float) -> bool:
    return a == b or is_similar(a, b, threshold)


def _align(ref: list[str], hyp: list[str], threshold: float) -> list[_Op]:
    """Needleman-Wunsch alignment over normalized tokens.

    Returns the ordered list of operations describing how to turn the
    reference sequence into the recited sequence.
    """
    n, m = len(ref), len(hyp)
    # cost[i][j] = min edit cost aligning ref[:i] with hyp[:j]
    cost = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        cost[i][0] = i
    for j in range(1, m + 1):
        cost[0][j] = j

    for i in range(1, n + 1):
        for j in range(1, m + 1):
            sub_cost = 0 if _words_match(ref[i - 1], hyp[j - 1], threshold) else 1
            cost[i][j] = min(
                cost[i - 1][j - 1] + sub_cost,  # match / substitution
                cost[i - 1][j] + 1,             # deletion (omission)
                cost[i][j - 1] + 1,             # insertion (addition)
            )

    # Backtrace from (n, m) to (0, 0).
    ops: list[_Op] = []
    i, j = n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0:
            matched = _words_match(ref[i - 1], hyp[j - 1], threshold)
            sub_cost = 0 if matched else 1
            if cost[i][j] == cost[i - 1][j - 1] + sub_cost:
                ops.append(
                    _Op(
                        kind=_MATCH if matched else _SUB,
                        ref_index=i - 1,
                        hyp_index=j - 1,
                        expected=ref[i - 1],
                        recited=hyp[j - 1],
                    )
                )
                i -= 1
                j -= 1
                continue
        if i > 0 and cost[i][j] == cost[i - 1][j] + 1:
            ops.append(
                _Op(kind=_DEL, ref_index=i - 1, hyp_index=None, expected=ref[i - 1], recited="")
            )
            i -= 1
            continue
        # insertion
        ops.append(_Op(kind=_INS, ref_index=i, hyp_index=j - 1, expected="", recited=hyp[j - 1]))
        j -= 1

    ops.reverse()
    return ops


def _detect_harakat_errors(
    ops: list[_Op],
    ref_norm: list[str],
    hyp_norm: list[str],
    ref_harakat: list[str],
    hyp_harakat: list[str],
) -> int:
    """Reclassify letter-perfect matches whose tashkeel differs as a
    dedicated "harakat" mistake (correct letters, wrong/missing diacritics).

    Deliberately conservative to avoid false positives:
      - Only applies to *exact* base-letter matches. Words that matched via
        the fuzzy/near-miss leniency in `is_similar` (e.g. a dropped final
        letter) are left alone, since comparing their harakat wouldn't be
        apples-to-apples (different letters).
      - Only applies when the recited word itself carries at least one
        diacritic. If the ASR simply didn't output harakat for this word,
        we can't fairly call it "wrong" -- that's treated as unknown, not
        a mistake, so already-correct matches never regress silently.

    Returns the number of words that were actually checkable (correct or
    not), used as the denominator for `harakat_score`.
    """
    checked = 0
    for op in ops:
        if op.kind != _MATCH or op.ref_index is None or op.hyp_index is None:
            continue
        ri, hi = op.ref_index, op.hyp_index
        if not (0 <= ri < len(ref_norm) and 0 <= hi < len(hyp_norm)):
            continue
        if ref_norm[ri] != hyp_norm[hi]:
            continue  # fuzzy/leniency match, not a true letter-for-letter match
        if not (0 <= ri < len(ref_harakat) and 0 <= hi < len(hyp_harakat)):
            continue
        ref_word, hyp_word = ref_harakat[ri], hyp_harakat[hi]
        if not contains_harakat(hyp_word):
            continue
        checked += 1
        if ref_word and hyp_word and ref_word != hyp_word:
            op.kind = _HARAKAT
    return checked


def _detect_sequence_errors(ops: list[_Op]) -> None:
    """Re-label adjacent transposed substitutions as 'sequence' errors.

    A swap looks like: ref[A]->hyp[B] followed by ref[B]->hyp[A].
    """
    for k in range(len(ops) - 1):
        a, b = ops[k], ops[k + 1]
        if a.kind == _SUB and b.kind == _SUB:
            if a.expected == b.recited and b.expected == a.recited and a.expected:
                a.kind = "sequence"
                b.kind = "sequence"


def analyze_alignment(
    reference_text: str,
    transcribed_text: str,
    threshold: float | None = None,
    hyp_word_timings: list[dict] | None = None,
) -> dict:
    """Compare a recitation against the reference and produce feedback.

    If `hyp_word_timings` (a list of `{"word", "start", "end"}` in recitation
    order, e.g. from `TranscriptionResult.words`) is provided, the returned
    dict also includes `word_timeline`: for every reference word that was
    matched or substituted, its `[start, end]` audio timing. This lets
    downstream Tajweed heuristics (Madd/Qalqalah/Ghunnah/Waqf) know *when* a
    given reference word was actually spoken.
    """
    if threshold is None:
        threshold = settings.similarity_threshold

    ref_original, ref_norm, ref_harakat = _tokenize(reference_text)
    _, hyp_norm, hyp_harakat = _tokenize(transcribed_text)

    total_words = len(ref_norm)

    ops = _align(ref_norm, hyp_norm, threshold)
    _detect_sequence_errors(ops)

    harakat_checked = 0
    if settings.enable_harakat_check and contains_harakat(transcribed_text):
        harakat_checked = _detect_harakat_errors(ops, ref_norm, hyp_norm, ref_harakat, hyp_harakat)

    errors: list[dict] = []
    word_timeline: list[dict] = []
    for op in ops:
        if op.kind in (_MATCH, _SUB, "sequence", _HARAKAT) and op.hyp_index is not None:
            idx = op.ref_index if op.ref_index is not None else 0
            expected_display = (
                ref_original[idx] if 0 <= idx < len(ref_original) else op.expected
            )
            if hyp_word_timings and 0 <= op.hyp_index < len(hyp_word_timings):
                timing = hyp_word_timings[op.hyp_index]
                word_timeline.append(
                    {
                        "word_index": idx,
                        "expected_word": expected_display,
                        "start": timing.get("start", 0.0),
                        "end": timing.get("end", 0.0),
                    }
                )
        if op.kind == _MATCH:
            continue
        if op.kind in (_SUB, "sequence", _DEL, _HARAKAT):
            idx = op.ref_index if op.ref_index is not None else 0
            expected_display = (
                ref_original[idx] if 0 <= idx < len(ref_original) else op.expected
            )
            recited_display = op.recited
            if op.kind == _HARAKAT and op.hyp_index is not None and 0 <= op.hyp_index < len(hyp_harakat):
                # Show the diacritized recited word (not the bare-letter form)
                # so the harakat difference is actually visible to the user.
                recited_display = hyp_harakat[op.hyp_index]
            errors.append(
                {
                    "type": op.kind,
                    "expectedWord": expected_display if op.kind != _INS else "",
                    "recitedWord": recited_display,
                    "wordIndex": idx,
                }
            )
        elif op.kind == _INS:
            idx = min(op.ref_index or 0, max(total_words - 1, 0))
            errors.append(
                {
                    "type": _INS,
                    "expectedWord": "",
                    "recitedWord": op.recited,
                    "wordIndex": idx,
                }
            )

    # Reference words counted as wrong for the *word* score (letters only --
    # harakat mistakes are scored completely separately, see below).
    ref_errors = sum(1 for e in errors if e["type"] not in (_INS, _HARAKAT))
    matched_words = max(total_words - ref_errors, 0)
    # "mistakes" mirrors the pre-harakat-feature meaning: every letter-level
    # error (substitution/omission/addition/sequence), excluding harakat.
    mistakes = sum(1 for e in errors if e["type"] != _HARAKAT)

    similarity = (matched_words / total_words * 100) if total_words else 0.0
    similarity = max(0.0, min(100.0, similarity))

    harakat_mistakes = sum(1 for e in errors if e["type"] == _HARAKAT)
    harakat_score = None
    if harakat_checked > 0:
        harakat_correct = harakat_checked - harakat_mistakes
        harakat_score = round(max(0.0, min(100.0, harakat_correct / harakat_checked * 100)), 2)

    return {
        "similarity_score": round(similarity, 2),
        "total_words": total_words,
        "matched_words": matched_words,
        "mistakes": mistakes,
        "errors": errors,
        "word_timeline": word_timeline,
        "harakat_score": harakat_score,
        "harakat_mistakes": harakat_mistakes,
        "harakat_checked": harakat_checked,
    }
