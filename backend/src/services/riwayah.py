"""Riwayah (qira'a) identifiers shared across reference, ASR, and API layers."""
from __future__ import annotations

SUPPORTED_RIWAYAT: tuple[str, ...] = ("hafs", "bazzi")
DEFAULT_RIWAYAH = "hafs"
BAZZI_SURAH_NUMBER = 2


def normalize_riwayah(value: str | None) -> str:
    """Return a validated riwayah id (defaults to Hafs)."""
    riwayah = (value or DEFAULT_RIWAYAH).strip().lower()
    if riwayah not in SUPPORTED_RIWAYAT:
        raise ValueError(
            f"Unsupported riwayah '{value}'. Supported: {list(SUPPORTED_RIWAYAT)}."
        )
    return riwayah


def validate_riwayah_for_surah(riwayah: str, surah_number: int) -> None:
    """Bazzi reference + model are scoped to Surah Al-Baqarah only."""
    if riwayah == "bazzi" and surah_number != BAZZI_SURAH_NUMBER:
        raise ValueError(
            f"Bazzi riwayah is only supported for surah {BAZZI_SURAH_NUMBER} "
            f"(Al-Baqarah), not surah {surah_number}."
        )
