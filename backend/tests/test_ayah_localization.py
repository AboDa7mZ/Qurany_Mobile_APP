"""Tests for ayah-window localization (Al-Baqarah partial recitation)."""
from __future__ import annotations

import json
from pathlib import Path

from src.services.analysis_service import analyze_text
from src.services.ayah_localization_service import localize_ayah_window


def _baqarah_ayahs():
    path = Path(__file__).resolve().parents[1] / "data" / "surah_cache" / "surah_2.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    return data["ayahs"]


def test_localize_hajj_ayah_window():
    ayahs = _baqarah_ayahs()
    by_num = {a["numberInSurah"]: a["text"] for a in ayahs}
    # Perfect transcript for ayahs 197-199 (opening words).
    transcript = " ".join(by_num[i] for i in (197, 198, 199))
    result = localize_ayah_window(ayahs, transcript)
    assert result is not None
    assert result.start_ayah == 197
    assert result.end_ayah >= 197
    assert result.alignment_score >= 90.0


def test_analyze_text_explicit_ayah_range():
    ayahs = _baqarah_ayahs()
    by_num = {a["numberInSurah"]: a["text"] for a in ayahs}
    transcript = by_num[197]
    body = analyze_text(2, transcript, start_ayah=197, end_ayah=197)
    assert body["reference_scope"] == "explicit_ayah_range"
    assert body["detected_ayah_start"] == 197
    assert body["detected_ayah_end"] == 197
    assert body["similarity_score"] >= 95.0


def test_analyze_text_auto_detect_baqarah():
    ayahs = _baqarah_ayahs()
    by_num = {a["numberInSurah"]: a["text"] for a in ayahs}
    transcript = " ".join(by_num[i] for i in range(197, 201))
    body = analyze_text(2, transcript, auto_detect_ayah_range=True)
    assert body["reference_scope"] == "auto_detected"
    assert body["detected_ayah_start"] == 197
    assert body["similarity_score"] >= 85.0
