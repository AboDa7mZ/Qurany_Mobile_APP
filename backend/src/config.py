"""Application configuration loaded from environment variables / .env."""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

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
    host: str = "0.0.0.0"
    port: int = 8000

    # CORS - Flutter app origins (use ["*"] for local dev)
    cors_origins: list[str] = ["*"]

    # MVP scope: only Surah Al-Naba (chapter 78)
    supported_surahs: list[int] = [78]

    # ASR (faster-whisper)
    # Default: CT2-converted tarteel-ai/whisper-base-ar-quran (Quranic Arabic).
    # See https://huggingface.co/tarteel-ai/whisper-base-ar-quran
    whisper_model: str = "OdyAsh/faster-whisper-base-ar-quran"
    # compute type: int8 (fast, CPU) | int8_float16 | float16 (GPU) | float32
    whisper_compute_type: str = "float32"
    whisper_device: str = "cpu"  # auto | cpu | cuda
    whisper_beam_size: int = 5
    asr_language: str = "ar"

    # Storage paths (resolved relative to backend/)
    data_dir: Path = BASE_DIR / "data"
    uploads_dir: Path = BASE_DIR / "data" / "uploads" / "recitations"
    surah_naba_dir: Path = BASE_DIR / "data" / "surah_naba"

    # Reference text
    # If the local seed JSON is missing, fall back to this API.
    alquran_api_base: str = "https://api.alquran.cloud/v1"
    reference_fetch_fallback: bool = True

    # Comparison / scoring
    # Jaccard similarity threshold (on character sets) to treat two words as
    # "close enough" (partial match) rather than a hard error. Mirrors the
    # Flutter client's _isSimilar threshold.
    similarity_threshold: float = 0.6

    # Database (PostgreSQL in Docker; SQLite fallback for local dev/tests)
    database_url: str = f"sqlite:///{(BASE_DIR / 'data' / 'qurany.db').as_posix()}"

    # JWT auth
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
