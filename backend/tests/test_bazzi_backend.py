"""Bazzi riwayah reference + API wiring tests (no ASR model required)."""
from __future__ import annotations


def test_list_surahs_includes_riwayat(client):
    resp = client.get("/api/v1/surahs")
    assert resp.status_code == 200
    body = resp.json()
    assert set(body["supported_riwayat"]) == {"hafs", "bazzi"}


def test_get_surah_bazzi_reference(client):
    resp = client.get("/api/v1/surahs/2", params={"riwayah": "bazzi"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["riwayah"] == "bazzi"
    assert body["numberOfAyahs"] == 285
    assert len(body["ayahs"]) == 285
    assert body["ayahs"][0]["numberInSurah"] == 1


def test_bazzi_rejected_for_surah_78(client):
    resp = client.get("/api/v1/surahs/78", params={"riwayah": "bazzi"})
    assert resp.status_code == 400


def test_health_lists_both_models(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["supported_riwayat"] == ["hafs", "bazzi"]
    assert "hafs" in body["models"]
    assert "bazzi" in body["models"]
    assert "qurany-whisper-base-al-baqarah-bazzi" in body["models"]["bazzi"]["configured_model"]
