"""Tests for Bazzi canonical text parsing (mixed ayah markers, merged ayah 1)."""
from pathlib import Path

import pytest

from training.kaggle.qurany_whisper_finetune_bazzi_an_ibn_kathir import (
    _bazzi_ayah_numbers,
    _parse_bazzi_reference_txt,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
USER_BAZZI_TEXT = REPO_ROOT / "training data2" / "Al-Baqarah_Bazzi.txt"


@pytest.mark.skipif(not USER_BAZZI_TEXT.exists(), reason="user Bazzi text not present")
def test_user_bazzi_text_parses_full_surah():
    ayah_map = _parse_bazzi_reference_txt(USER_BAZZI_TEXT)
    nums = _bazzi_ayah_numbers(ayah_map)

    assert nums[0] == 1
    assert nums[-1] == 285
    assert len(nums) == 285

    ayah1 = ayah_map[1]
    assert "ذَ" in ayah1 or "ذ" in ayah1  # merged Hafs 1+2: alif-lam-mim + dhalika
    assert "ٱلۡكِتَ" in ayah1 or "الكتاب" in ayah1.replace(" ", "")


def test_mixed_markers_minimal():
    sample = Path(__file__).parent / "_bazzi_parser_sample.txt"
    sample.write_text(
        "first ayah merged (1) second ayah (2) third with bare 3 fourth ayah (4)",
        encoding="utf-8",
    )
    try:
        ayah_map = _parse_bazzi_reference_txt(sample)
        assert _bazzi_ayah_numbers(ayah_map) == [1, 2, 3, 4]
        assert ayah_map[1] == "first ayah merged"
        assert ayah_map[3] == "third with bare"
        assert ayah_map[4] == "fourth ayah"
    finally:
        sample.unlink(missing_ok=True)
