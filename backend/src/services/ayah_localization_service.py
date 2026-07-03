"""Detect which ayah range a partial recitation covers within a surah.

When a user recites only a few ayahs, aligning against the full surah inflates
omissions and collapses the similarity score. This module finds the best-matching
contiguous ayah window so comparison uses only the relevant reference segment.
"""
from __future__ import annotations

from dataclasses import dataclass

from ..utils.arabic import normalize_arabic
from .alignment_service import analyze_alignment


@dataclass(frozen=True)
class AyahLocalizationResult:
    start_ayah: int
    end_ayah: int
    reference_text: str
    alignment_score: float
    method: str  # "explicit" | "auto"


def _ayah_words(text: str) -> list[str]:
    return [w for w in (normalize_arabic(w) for w in text.split()) if w]


def _prefix_overlap(hyp_prefix: list[str], ayah_words: list[str]) -> int:
    """Count matching words at the start of hyp_prefix against ayah_words."""
    limit = min(len(hyp_prefix), len(ayah_words), 8)
    return sum(1 for i in range(limit) if hyp_prefix[i] == ayah_words[i])


def _score_window(reference_text: str, transcribed_text: str) -> float:
    return analyze_alignment(reference_text, transcribed_text)["similarity_score"]


def localize_ayah_window(
    ayahs: list[dict],
    transcribed_text: str,
    *,
    max_window_ayahs: int = 15,
    min_alignment_score: float = 55.0,
) -> AyahLocalizationResult | None:
    """Find the contiguous ayah range that best explains `transcribed_text`.

    Returns None when the transcript is empty or no window clears the minimum
    score (caller should fall back to full-surah alignment).
    """
    hyp_words = _ayah_words(transcribed_text)
    if not hyp_words or not ayahs:
        return None

    indexed = sorted(ayahs, key=lambda a: a["numberInSurah"])
    ayah_by_num = {a["numberInSurah"]: a for a in indexed}
    numbers = [a["numberInSurah"] for a in indexed]

    # Candidate starts: ayahs whose opening words overlap the transcript prefix.
    prefix = hyp_words[: min(8, len(hyp_words))]
    start_scores: list[tuple[int, int]] = []
    for num in numbers:
        overlap = _prefix_overlap(prefix, _ayah_words(ayah_by_num[num]["text"]))
        if overlap >= 2:
            start_scores.append((overlap, num))
    start_scores.sort(reverse=True)
    candidate_starts = [num for _, num in start_scores[:12]]
    if not candidate_starts:
        # Fallback: try every ayah as a start (slower but robust for noisy ASR).
        candidate_starts = numbers

    hyp_len = len(hyp_words)
    best: AyahLocalizationResult | None = None

    for start in candidate_starts:
        start_idx = numbers.index(start)
        max_end_idx = min(start_idx + max_window_ayahs, len(numbers) - 1)
        # Estimate how many ayahs the clip might span from word count.
        max_end_idx = min(max_end_idx, start_idx + max(1, (hyp_len // 8) + 2))

        for end_idx in range(start_idx, max_end_idx + 1):
            end = numbers[end_idx]
            segment_ayahs = [ayah_by_num[n] for n in numbers[start_idx : end_idx + 1]]
            ref_text = " ".join(a["text"] for a in segment_ayahs)
            ref_word_count = len(_ayah_words(ref_text))
            # Skip windows wildly shorter/longer than the transcript.
            if ref_word_count < max(1, hyp_len // 3) or ref_word_count > hyp_len * 4:
                continue

            score = _score_window(ref_text, transcribed_text)
            if score < min_alignment_score:
                continue

            candidate = AyahLocalizationResult(
                start_ayah=start,
                end_ayah=end,
                reference_text=ref_text,
                alignment_score=score,
                method="auto",
            )
            if best is None or score > best.alignment_score:
                best = candidate
            elif score == best.alignment_score and (end - start) < (best.end_ayah - best.start_ayah):
                # Prefer tighter windows on ties.
                best = candidate

    return best


def resolve_reference_segment(
    ayahs: list[dict],
    transcribed_text: str,
    *,
    start_ayah: int | None = None,
    end_ayah: int | None = None,
    full_text: str,
    auto_detect: bool = True,
) -> tuple[str, AyahLocalizationResult | None]:
    """Pick the reference text slice to align against."""
    if start_ayah is not None and end_ayah is not None:
        if start_ayah > end_ayah:
            start_ayah, end_ayah = end_ayah, start_ayah
        by_num = {a["numberInSurah"]: a for a in ayahs}
        segment = " ".join(
            by_num[n]["text"]
            for n in sorted(by_num)
            if start_ayah <= n <= end_ayah
        )
        meta = AyahLocalizationResult(
            start_ayah=start_ayah,
            end_ayah=end_ayah,
            reference_text=segment,
            alignment_score=0.0,
            method="explicit",
        )
        return segment, meta

    if auto_detect:
        located = localize_ayah_window(ayahs, transcribed_text)
        if located is not None:
            return located.reference_text, located

    return full_text, None
