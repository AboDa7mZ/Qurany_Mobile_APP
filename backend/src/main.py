"""FastAPI application entry point for the Qurany recitation backend."""
from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import schemas
from .api.auth_routes import router as auth_router
from .api.routes import router as api_router
from .database.session import init_db
from .config import settings
from .services.asr_service import asr_service
from .services.riwayah import SUPPORTED_RIWAYAT

logging.basicConfig(
    level=logging.DEBUG if settings.debug else logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    app = FastAPI(
        title="Qurany Recitation Backend",
        description=(
            "Receives recitation audio, transcribes it (faster-whisper or a "
            "fine-tuned Whisper checkpoint), aligns it against canonical Quran "
            "text, flags word-level mistakes, and layers best-effort Tajweed "
            "heuristics on top. MVP scope: Surah Al-Naba (78) and Al-Baqarah (2)."
        ),
        version="0.1.0",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(api_router)
    app.include_router(auth_router, prefix="/api/v1")

    @app.on_event("startup")
    def on_startup() -> None:
        init_db()
        logger.info("Database initialized")

    @app.get("/", include_in_schema=False)
    def root() -> dict:
        return {"service": settings.app_name, "docs": "/docs"}

    @app.get("/health", response_model=schemas.HealthResponse, summary="Health check")
    async def health() -> dict:
        # Must stay async so this responds instantly even while a heavy
        # analyze/transcribe job occupies the default sync thread pool.
        hafs = asr_service.backend_info("hafs")
        return {
            "status": "ok",
            "app": settings.app_name,
            "asr_backend": hafs["configured_backend"],
            "asr_model": hafs["configured_model"],
            "active_backend": hafs["active_backend"],
            "active_model": hafs["active_model"],
            "asr_loaded": asr_service.is_loaded,
            "supported_surahs": settings.supported_surahs,
            "supported_riwayat": list(SUPPORTED_RIWAYAT),
            "models": asr_service.models_status(),
        }

    return app


app = create_app()
