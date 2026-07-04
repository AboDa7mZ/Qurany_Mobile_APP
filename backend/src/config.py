"""Application configuration loaded from environment variables / .env."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/ root (this file lives in backend/src/config.py)
BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(BASE_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Application
    app_name: str = "qurany-backend"
    app_env: str = "development"
    debug: bool = True
    # Uvicorn auto-reload. Off by default with ASR_BACKEND=transformers (see main.py).
    uvicorn_reload: bool = True
    uvicorn_reload_with_transformers: bool = False
    host: str = "0.0.0.0"
    port: int = 8000

    # CORS - Flutter app origins (use ["*"] for local dev)
    cors_origins: list[str] = ["*"]

    # MVP scope: Surah Al-Naba (78) + Surah Al-Baqarah (2, fine-tuned model target)
    supported_surahs: list[int] = [78, 2]

    # ASR backend: "faster_whisper" (default, CTranslate2) or "transformers"
    # (HF checkpoint, e.g. our Kaggle fine-tunes).
    asr_backend: str = "faster_whisper"

    # faster-whisper: default CT2 build of tarteel-ai/whisper-base-ar-quran.
    whisper_model: str = "OdyAsh/faster-whisper-base-ar-quran"
    # compute type: int8 (fast, CPU) | int8_float16 | float16 (GPU) | float32
    whisper_compute_type: str = "int8"
    whisper_device: str = "cpu"  # auto | cpu | cuda
    whisper_beam_size: int = 5
    asr_language: str = "ar"

    # transformers Whisper decode (fine-tuned model inference)
    whisper_num_beams: int = 5
    whisper_chunk_overlap_seconds: float = 2.0
    whisper_condition_on_previous_text: bool = True

    # When True, partial recitations are aligned against a detected ayah window
    # instead of the full surah (critical for Al-Baqarah short clips).
    auto_detect_ayah_range: bool = True

    # Riwayah-specific fine-tuned Whisper checkpoints (transformers backend).
    # Hafs keeps the existing CUSTOM_MODEL_PATH name for backward compatibility.
    # Bazzi uses its own path and is selected per-request via ?riwayah=bazzi.
    bazzi_model_path: str | None = "./models/qurany-whisper-base-al-baqarah-bazzi"
    bazzi_reference_txt: Path = BASE_DIR / "data" / "reference" / "Al-Baqarah_Bazzi.txt"

    # transformers backend: path or HF repo id of a fine-tuned Whisper model
    # (e.g. the qurany-whisper-base-al-baqarah checkpoint downloaded from
    # Kaggle). Falls back to `tarteel-ai/whisper-base-ar-quran` if unset.
    custom_model_path: str | None = None

    @field_validator("custom_model_path", "bazzi_model_path")
    @classmethod
    def _resolve_custom_model_path(cls, value: str | None) -> str | None:
        """Resolve filesystem-looking paths against BASE_DIR so the model
        loads the same way regardless of the process's cwd (e.g. `python
        main.py` from backend/ vs. `uvicorn src.main:app` from repo root).
        Leaves Hugging Face repo ids (e.g. "org/model-name") and absolute
        paths untouched."""
        if not value:
            return value
        looks_like_path = value.startswith((".", "/", "\\")) or ":" in value[:3]
        if looks_like_path and not Path(value).is_absolute():
            return str((BASE_DIR / value).resolve())
        return value

    # Best-effort Tajweed heuristics (Madd, Qalqalah/Ghunnah, Waqf) applied as
    # post-processing on top of word-level ASR timestamps. Approximate, not a
    # substitute for a trained Tajweed classifier.
    enable_tajweed_heuristics: bool = True

    # Storage paths (resolved relative to backend/)
    data_dir: Path = BASE_DIR / "data"
    uploads_dir: Path = BASE_DIR / "data" / "uploads" / "recitations"
    surah_naba_dir: Path = BASE_DIR / "data" / "surah_naba"
    reference_cache_dir: Path = BASE_DIR / "data" / "surah_cache"

    # Reference text
    # If the local seed JSON is missing, fall back to this API.
    alquran_api_base: str = "https://api.alquran.cloud/v1"
    reference_fetch_fallback: bool = True

    # Comparison / scoring
    # Jaccard similarity threshold (on character sets) to treat two words as
    # "close enough" (partial match) rather than a hard error. Mirrors the
    # Flutter client's _isSimilar threshold.
    similarity_threshold: float = 0.6

    # Database (SQLite file in data/qurany.db; tables created on startup)
    database_url: str = f"sqlite:///{(BASE_DIR / 'data' / 'qurany.db').as_posix()}"

    # JWT auth
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7

    # Flag correct-letter words with wrong/missing tashkeel (harakat) as a
    # dedicated "harakat" mistake. Auto-skipped when transcript has no diacritics.
    enable_harakat_check: bool = True


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
