"""Pydantic request/response models.

Field aliases keep the JSON wire format identical to what the Flutter client
already expects (top-level keys are snake_case; error fields are camelCase, as
in `recitation_session.dart::RecitationError`).
"""
from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class RecitationError(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    type: str = Field(description="substitution | omission | addition | sequence | harakat")
    expected_word: str = Field(default="", alias="expectedWord")
    recited_word: str = Field(default="", alias="recitedWord")
    word_index: int = Field(default=0, alias="wordIndex")


class TranscriptionSegment(BaseModel):
    start: float
    end: float
    text: str


class TajweedNote(BaseModel):
    """Best-effort Tajweed heuristic flag (Madd / Ghunnah / Waqf / Qalqalah).

    Not a certified Tajweed judge — see `services/tajweed_heuristics.py` for
    the approximations involved. `severity` is "info" (gentle tip) or
    "warning" (likely missed rule).
    """

    model_config = ConfigDict(populate_by_name=True)

    type: str = Field(description="madd | ghunnah | waqf | qalqalah")
    expected_word: str = Field(default="", alias="expectedWord")
    word_index: int = Field(default=0, alias="wordIndex")
    message: str = ""
    severity: str = "info"


class AnalysisResult(BaseModel):
    transcribed_text: str
    reference_text: str
    similarity_score: float = Field(ge=0, le=100)
    total_words: int
    matched_words: int
    mistakes: int
    errors: list[RecitationError] = Field(default_factory=list)
    segments: list[TranscriptionSegment] = Field(default_factory=list)
    tajweed_notes: list[TajweedNote] = Field(default_factory=list)
    # Set when alignment uses an ayah window (auto-detected or client-provided).
    reference_scope: str | None = Field(
        default=None,
        description="full_surah | auto_detected | explicit_ayah_range",
    )
    detected_ayah_start: int | None = Field(default=None, alias="detectedAyahStart")
    detected_ayah_end: int | None = Field(default=None, alias="detectedAyahEnd")
    localization_score: float | None = Field(default=None, alias="localizationScore")
    asr_backend: str | None = None
    asr_model: str | None = None
    # Harakat (tashkeel) correctness, scored independently from word-level
    # mistakes above. `None` when nothing was checkable (e.g. the ASR
    # backend doesn't output diacritics) -- treat as "not available", not 0.
    harakat_score: float | None = Field(
        default=None, ge=0, le=100, alias="harakatScore"
    )
    harakat_mistakes: int = Field(default=0, alias="harakatMistakes")
    harakat_checked: int = Field(default=0, alias="harakatChecked")
    riwayah: str | None = None

    model_config = ConfigDict(populate_by_name=True)


class AnalyzeTextRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    surah_number: int = Field(default=78, description="Chapter number (MVP: 78, 2)")
    transcribed_text: str = Field(min_length=1)
    start_ayah: int | None = Field(default=None, alias="startAyah")
    end_ayah: int | None = Field(default=None, alias="endAyah")
    auto_detect_ayah_range: bool | None = Field(default=None, alias="autoDetectAyahRange")
    riwayah: str | None = Field(
        default="hafs",
        description="qira'a: hafs (default) or bazzi (Surah 2 only)",
    )


class TranscriptionResponse(BaseModel):
    text: str
    language: str
    duration: float
    segments: list[TranscriptionSegment] = Field(default_factory=list)
    riwayah: str | None = None
    asr_backend: str | None = None
    asr_model: str | None = None


class SurahAyah(BaseModel):
    numberInSurah: int
    globalNumber: int
    text: str


class SurahReferenceResponse(BaseModel):
    surah_number: int
    name: str
    numberOfAyahs: int
    full_text: str
    normalized_text: str
    ayahs: list[SurahAyah]
    riwayah: str | None = None


class HealthResponse(BaseModel):
    status: str
    app: str
    asr_backend: str
    asr_model: str
    active_backend: str | None = None
    active_model: str | None = None
    asr_loaded: bool
    supported_surahs: list[int]
    supported_riwayat: list[str] = Field(default_factory=list)
    models: dict | None = None
