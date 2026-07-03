"""Orchestrates the full recitation-analysis pipeline.

audio -> ASR transcription -> Arabic normalization -> alignment vs reference
-> word-by-word error feedback.

The returned dict matches the shape consumed by the Flutter client
(see `recitation_screen.dart::_performLocalComparison`).
"""
from __future__ import annotations

import logging

from ..config import settings
from .alignment_service import analyze_alignment
from .asr_service import TranscriptionResult, asr_service
from .ayah_localization_service import resolve_reference_segment
from .reference_service import get_surah_reference
from .riwayah import DEFAULT_RIWAYAH, normalize_riwayah
from .tajweed_heuristics import run_tajweed_heuristics

logger = logging.getLogger(__name__)


def _pick_reference(
    surah_number: int,
    transcribed_text: str,
    *,
    start_ayah: int | None = None,
    end_ayah: int | None = None,
    auto_detect: bool | None = None,
    riwayah: str | None = None,
) -> tuple[str, dict | None]:
    riwayah = normalize_riwayah(riwayah)
    reference = get_surah_reference(surah_number, riwayah=riwayah)
    if auto_detect is None:
        auto_detect = settings.auto_detect_ayah_range and surah_number == 2

    segment_text, localization = resolve_reference_segment(
        reference.ayahs,
        transcribed_text,
        start_ayah=start_ayah,
        end_ayah=end_ayah,
        full_text=reference.full_text,
        auto_detect=auto_detect and start_ayah is None,
    )

    meta: dict | None = {"riwayah": riwayah}
    if localization is not None:
        meta.update(
            {
                "detected_ayah_start": localization.start_ayah,
                "detected_ayah_end": localization.end_ayah,
                "reference_scope": "explicit_ayah_range"
                if localization.method == "explicit"
                else "auto_detected",
            }
        )
        if localization.method == "auto":
            meta["localization_score"] = localization.alignment_score
    else:
        meta["reference_scope"] = "full_surah"

    return segment_text, meta


def _build_result(
    reference_text: str,
    transcribed_text: str,
    segments: list[dict] | None = None,
    hyp_word_timings: list[dict] | None = None,
    audio_path: str | None = None,
    alignment_meta: dict | None = None,
    *,
    riwayah: str = DEFAULT_RIWAYAH,
) -> dict:
    feedback = analyze_alignment(reference_text, transcribed_text, hyp_word_timings=hyp_word_timings)

    tajweed_notes: list[dict] = []
    if settings.enable_tajweed_heuristics and audio_path and feedback.get("word_timeline"):
        try:
            tajweed_notes = run_tajweed_heuristics(audio_path, feedback["word_timeline"])
        except Exception as exc:  # heuristics are best-effort; never break /analyze
            logger.warning("Tajweed heuristics failed: %s", exc)

    result = {
        "transcribed_text": transcribed_text,
        "reference_text": reference_text,
        "similarity_score": feedback["similarity_score"],
        "total_words": feedback["total_words"],
        "matched_words": feedback["matched_words"],
        "mistakes": feedback["mistakes"],
        "errors": feedback["errors"],
        "segments": segments or [],
        "tajweed_notes": tajweed_notes,
        "harakat_score": feedback["harakat_score"],
        "harakat_mistakes": feedback["harakat_mistakes"],
        "harakat_checked": feedback["harakat_checked"],
        "riwayah": riwayah,
    }
    asr = asr_service.backend_info(riwayah)
    result["asr_backend"] = asr.get("active_backend") or asr["configured_backend"]
    result["asr_model"] = asr.get("active_model") or asr["configured_model"]
    if alignment_meta:
        result.update(alignment_meta)
    return result


def analyze_text(
    surah_number: int,
    transcribed_text: str,
    *,
    start_ayah: int | None = None,
    end_ayah: int | None = None,
    auto_detect_ayah_range: bool | None = None,
    riwayah: str | None = None,
) -> dict:
    """Compare already-transcribed text against a surah's reference."""
    riwayah = normalize_riwayah(riwayah)
    reference_text, meta = _pick_reference(
        surah_number,
        transcribed_text,
        start_ayah=start_ayah,
        end_ayah=end_ayah,
        auto_detect=auto_detect_ayah_range,
        riwayah=riwayah,
    )
    return _build_result(
        reference_text,
        transcribed_text,
        alignment_meta=meta,
        riwayah=riwayah,
    )


def analyze_audio(
    surah_number: int,
    audio_path: str,
    *,
    start_ayah: int | None = None,
    end_ayah: int | None = None,
    auto_detect_ayah_range: bool | None = None,
    riwayah: str | None = None,
) -> dict:
    """Full pipeline: transcribe the audio file, then compare."""
    riwayah = normalize_riwayah(riwayah)
    result: TranscriptionResult = asr_service.transcribe(audio_path, riwayah=riwayah)
    reference_text, meta = _pick_reference(
        surah_number,
        result.text,
        start_ayah=start_ayah,
        end_ayah=end_ayah,
        auto_detect=auto_detect_ayah_range,
        riwayah=riwayah,
    )
    segments = [s.to_dict() for s in result.segments]
    hyp_word_timings = [w.to_dict() for w in result.words]
    return _build_result(
        reference_text,
        result.text,
        segments,
        hyp_word_timings=hyp_word_timings,
        audio_path=audio_path,
        alignment_meta=meta,
        riwayah=riwayah,
    )
