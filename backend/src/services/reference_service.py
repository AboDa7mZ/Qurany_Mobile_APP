"""Loads and caches canonical surah reference text (MVP: Surah Al-Naba / 78).

Primary source is the locally seeded JSON in ``data/surah_naba/``. If that is
missing and the fallback is enabled, the text is fetched once from the
AlQuran Cloud API (the same source the Flutter app uses) and cached to disk.

For Surah 2 in riwayah **bazzi**, reference text comes from the canonical
``Al-Baqarah_Bazzi.txt`` file (285 ayahs) instead of the Hafs Uthmani API text.
"""
from __future__ import annotations

import json
import logging
from functools import lru_cache

from ..config import settings
from ..utils.arabic import normalize_arabic
from ..utils.bazzi_text import bazzi_ayah_numbers, parse_bazzi_reference_txt
from .riwayah import DEFAULT_RIWAYAH, normalize_riwayah, validate_riwayah_for_surah

logger = logging.getLogger(__name__)

_SEED_FILENAME = "surah_naba.json"
_BAZZI_CACHE_FILENAME = "surah_2_bazzi.json"


class SurahReference:
    """In-memory representation of a surah's reference text."""

    def __init__(
        self,
        surah_number: int,
        name: str,
        ayahs: list[dict],
        *,
        riwayah: str = DEFAULT_RIWAYAH,
    ):
        self.surah_number = surah_number
        self.name = name
        self.ayahs = ayahs  # [{numberInSurah, globalNumber, text}]
        self.riwayah = riwayah

    @property
    def full_text(self) -> str:
        """All ayahs joined into a single Uthmani reference string."""
        return " ".join(a["text"] for a in self.ayahs).strip()

    @property
    def normalized_text(self) -> str:
        return normalize_arabic(self.full_text)

    def to_dict(self) -> dict:
        return {
            "surah_number": self.surah_number,
            "name": self.name,
            "numberOfAyahs": len(self.ayahs),
            "ayahs": self.ayahs,
            "full_text": self.full_text,
            "normalized_text": self.normalized_text,
            "riwayah": self.riwayah,
        }


def _seed_path(surah_number: int, riwayah: str = DEFAULT_RIWAYAH):
    if riwayah == "bazzi":
        return settings.reference_cache_dir / _BAZZI_CACHE_FILENAME
    # Chapter 78 (Al-Naba) keeps its original hand-seeded path; every other
    # surah (e.g. 2 / Al-Baqarah) is cached generically under
    # data/surah_cache/surah_<n>.json the first time it's fetched from the API.
    if surah_number == 78:
        return settings.surah_naba_dir / _SEED_FILENAME
    return settings.reference_cache_dir / f"surah_{surah_number}.json"


def _load_from_disk(surah_number: int, riwayah: str = DEFAULT_RIWAYAH) -> SurahReference | None:
    path = _seed_path(surah_number, riwayah)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return SurahReference(
            surah_number=data.get("surah_number", surah_number),
            name=data.get("name", ""),
            ayahs=data["ayahs"],
            riwayah=data.get("riwayah", riwayah),
        )
    except (json.JSONDecodeError, KeyError) as exc:
        logger.warning("Failed to parse seed file %s: %s", path, exc)
        return None


def _build_bazzi_reference() -> SurahReference:
    text_path = settings.bazzi_reference_txt
    if not text_path.exists():
        raise RuntimeError(
            f"Bazzi reference text not found at {text_path}. "
            "Copy Al-Baqarah_Bazzi.txt into backend/data/reference/."
        )
    ayah_map = parse_bazzi_reference_txt(text_path)
    nums = bazzi_ayah_numbers(ayah_map)
    ayahs = [
        {
            "numberInSurah": n,
            "globalNumber": n,
            "text": ayah_map[n],
        }
        for n in nums
    ]
    ref = SurahReference(
        2,
        "Al-Baqarah (Al-Bazzi 'an Ibn Kathir)",
        ayahs,
        riwayah="bazzi",
    )

    try:
        path = _seed_path(2, "bazzi")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "surah_number": ref.surah_number,
                    "name": ref.name,
                    "numberOfAyahs": len(ayahs),
                    "riwayah": "bazzi",
                    "ayahs": ayahs,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
    except OSError as exc:
        logger.warning("Could not cache Bazzi reference: %s", exc)

    return ref


def _fetch_from_api(surah_number: int) -> SurahReference | None:
    if not settings.reference_fetch_fallback:
        return None
    import httpx

    url = f"{settings.alquran_api_base}/surah/{surah_number}/ar.uthmani"
    try:
        resp = httpx.get(url, timeout=30.0)
        resp.raise_for_status()
        payload = resp.json()["data"]
    except (httpx.HTTPError, KeyError) as exc:
        logger.error("Reference fetch failed for surah %s: %s", surah_number, exc)
        return None

    ayahs = [
        {
            "numberInSurah": a["numberInSurah"],
            "globalNumber": a["number"],
            "text": a["text"],
        }
        for a in payload["ayahs"]
    ]
    ref = SurahReference(surah_number, payload.get("name", ""), ayahs, riwayah="hafs")

    # Cache to disk for next time.
    try:
        path = _seed_path(surah_number, "hafs")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(
                {
                    "surah_number": ref.surah_number,
                    "name": ref.name,
                    "numberOfAyahs": len(ayahs),
                    "riwayah": "hafs",
                    "ayahs": ayahs,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
    except OSError as exc:  # caching is best-effort
        logger.warning("Could not cache reference for surah %s: %s", surah_number, exc)

    return ref


@lru_cache
def get_surah_reference(surah_number: int, riwayah: str | None = None) -> SurahReference:
    """Return the reference text for a surah, loading/caching as needed."""
    riwayah = normalize_riwayah(riwayah)
    validate_riwayah_for_surah(riwayah, surah_number)

    if not (1 <= surah_number <= 114):
        raise ValueError(f"Surah {surah_number} is out of range (valid: 1–114).")

    if riwayah == "bazzi":
        return _load_from_disk(surah_number, "bazzi") or _build_bazzi_reference()

    ref = _load_from_disk(surah_number, "hafs") or _fetch_from_api(surah_number)
    if ref is None:
        raise RuntimeError(
            f"Reference text for surah {surah_number} is unavailable "
            "(no local seed and API fallback failed)."
        )
    return ref


def clear_reference_cache() -> None:
    """Clear in-memory reference caches (tests only)."""
    get_surah_reference.cache_clear()
