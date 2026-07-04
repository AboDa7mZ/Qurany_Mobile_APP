"""HTTP API routes for recitation analysis."""
from __future__ import annotations

import logging
import shutil
import uuid
from pathlib import Path

from fastapi import (
    APIRouter,
    File,
    Form,
    HTTPException,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from ..concurrency import run_inference
from ..config import settings
from ..services.analysis_service import analyze_audio, analyze_text
from ..services.asr_service import asr_service
from ..services.reference_service import get_surah_reference
from ..services.riwayah import SUPPORTED_RIWAYAT, normalize_riwayah, validate_riwayah_for_surah
from . import schemas

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1")

_ALLOWED_AUDIO_SUFFIXES = {".wav", ".mp3", ".m4a", ".aac", ".ogg", ".flac", ".webm"}


def _validate_surah(surah_number: int) -> None:
    if not (1 <= surah_number <= 114):
        raise HTTPException(
            status_code=400,
            detail=f"Surah {surah_number} is out of range. Valid surahs: 1–114.",
        )


def _save_upload(file: UploadFile) -> Path:
    suffix = Path(file.filename or "").suffix.lower() or ".wav"
    if suffix not in _ALLOWED_AUDIO_SUFFIXES:
        raise HTTPException(
            status_code=415,
            detail=f"Unsupported audio type '{suffix}'. "
            f"Allowed: {sorted(_ALLOWED_AUDIO_SUFFIXES)}.",
        )
    settings.uploads_dir.mkdir(parents=True, exist_ok=True)
    dest = settings.uploads_dir / f"{uuid.uuid4().hex}{suffix}"
    with dest.open("wb") as out:
        shutil.copyfileobj(file.file, out)
    return dest


def _validate_riwayah(riwayah: str | None, surah_number: int) -> str:
    try:
        riwayah = normalize_riwayah(riwayah)
        validate_riwayah_for_surah(riwayah, surah_number)
        return riwayah
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/surahs", summary="List supported surahs")
def list_surahs() -> dict:
    return {
        "supported_surahs": settings.supported_surahs,
        "supported_riwayat": list(SUPPORTED_RIWAYAT),
    }


@router.get(
    "/surahs/{surah_number}",
    response_model=schemas.SurahReferenceResponse,
    summary="Get a surah's reference text",
)
def get_surah(surah_number: int, riwayah: str = "hafs") -> dict:
    _validate_surah(surah_number)
    riwayah = _validate_riwayah(riwayah, surah_number)
    ref = get_surah_reference(surah_number, riwayah=riwayah)
    return ref.to_dict()


@router.post(
    "/transcribe",
    response_model=schemas.TranscriptionResponse,
    summary="Transcribe a recitation audio file (no comparison)",
)
async def transcribe(
    file: UploadFile = File(...),
    riwayah: str = Form("hafs"),
) -> dict:
    try:
        riwayah = normalize_riwayah(riwayah)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    audio_path = _save_upload(file)
    try:
        result = await run_inference(asr_service.transcribe, str(audio_path), riwayah=riwayah)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    finally:
        audio_path.unlink(missing_ok=True)
    asr = asr_service.backend_info(riwayah)
    return {
        "text": result.text,
        "language": result.language,
        "duration": result.duration,
        "segments": [s.to_dict() for s in result.segments],
        "riwayah": riwayah,
        "asr_backend": asr.get("active_backend") or asr["configured_backend"],
        "asr_model": asr.get("active_model") or asr["configured_model"],
    }


@router.post(
    "/analyze",
    response_model=schemas.AnalysisResult,
    response_model_by_alias=True,
    summary="Transcribe audio and compare it against the surah reference",
)
async def analyze(
    file: UploadFile = File(...),
    surah_number: int = Form(78),
    start_ayah: int | None = Form(None),
    end_ayah: int | None = Form(None),
    auto_detect_ayah_range: bool | None = Form(None),
    skip_basmallah: bool | None = Form(None),
    riwayah: str = Form("hafs"),
) -> dict:
    _validate_surah(surah_number)
    riwayah = _validate_riwayah(riwayah, surah_number)
    audio_path = _save_upload(file)
    try:
        return await run_inference(
            analyze_audio,
            surah_number,
            str(audio_path),
            start_ayah=start_ayah,
            end_ayah=end_ayah,
            auto_detect_ayah_range=auto_detect_ayah_range,
            riwayah=riwayah,
            skip_basmallah=bool(skip_basmallah),
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    finally:
        audio_path.unlink(missing_ok=True)


@router.post(
    "/analyze-text",
    response_model=schemas.AnalysisResult,
    response_model_by_alias=True,
    summary="Compare an existing transcript against the surah reference",
)
async def analyze_transcript(payload: schemas.AnalyzeTextRequest) -> dict:
    _validate_surah(payload.surah_number)
    riwayah = _validate_riwayah(payload.riwayah, payload.surah_number)
    return await run_inference(
        analyze_text,
        payload.surah_number,
        payload.transcribed_text,
        start_ayah=payload.start_ayah,
        end_ayah=payload.end_ayah,
        auto_detect_ayah_range=payload.auto_detect_ayah_range,
        riwayah=riwayah,
        skip_basmallah=bool(payload.skip_basmallah),
    )


@router.websocket("/stream")
async def stream_alignment(websocket: WebSocket) -> None:
    """Live alignment feedback over WebSocket.

    The client sends JSON frames as the (partial) transcript grows:

        {"surah_number": 78, "transcribed_text": "..."}

    and receives an analysis result frame (same shape as ``/analyze-text``)
    for each message, enabling server-driven live highlighting without
    streaming audio. Send {"type": "end"} to close.
    """
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_json()
            if data.get("type") == "end":
                break
            surah_number = int(data.get("surah_number", 78))
            transcript = str(data.get("transcribed_text", ""))
            start_ayah = data.get("start_ayah") or data.get("startAyah")
            end_ayah = data.get("end_ayah") or data.get("endAyah")
            auto_detect = data.get("auto_detect_ayah_range")
            if auto_detect is None:
                auto_detect = data.get("autoDetectAyahRange")
            riwayah_raw = data.get("riwayah")
            if surah_number not in settings.supported_surahs:
                await websocket.send_json(
                    {"error": f"Surah {surah_number} not supported."}
                )
                continue
            try:
                riwayah = normalize_riwayah(riwayah_raw)
                validate_riwayah_for_surah(riwayah, surah_number)
            except ValueError as exc:
                await websocket.send_json({"error": str(exc)})
                continue
            result = await run_inference(
                analyze_text,
                surah_number,
                transcript,
                start_ayah=int(start_ayah) if start_ayah is not None else None,
                end_ayah=int(end_ayah) if end_ayah is not None else None,
                auto_detect_ayah_range=auto_detect,
                riwayah=riwayah,
            )
            await websocket.send_json(result)
    except WebSocketDisconnect:
        return
    except (ValueError, KeyError) as exc:
        await websocket.send_json({"error": str(exc)})
