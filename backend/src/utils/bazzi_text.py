"""Parse canonical Bazzi Al-Baqarah reference text (mixed ayah markers)."""
from __future__ import annotations

import re
from pathlib import Path

_BAZZI_AYAH_MARKER_RE = re.compile(
    r"\((\d{1,3})\)"  # (123)
    r"|(?<=\s)(\d{1,3})(?=\s)"  # bare 106 … 285
)


def find_bazzi_ayah_markers(raw: str) -> list[tuple[int, int, int]]:
    """Return ordered [(marker_start, marker_end, ayah_num), …]."""
    candidates = [
        (m.start(), m.end(), int(m.group(1) or m.group(2)))
        for m in _BAZZI_AYAH_MARKER_RE.finditer(raw)
    ]
    markers: list[tuple[int, int, int]] = []
    expected = 1
    for start, end, num in candidates:
        if num < expected:
            continue
        if num == expected:
            markers.append((start, end, num))
            expected += 1
    return markers


def parse_bazzi_reference_txt(path: Path) -> dict[int, str]:
    """Parse mixed-marker Bazzi text into {ayah_number: ayah_text}."""
    raw = path.read_text(encoding="utf-8")
    markers = find_bazzi_ayah_markers(raw)
    if not markers:
        raise ValueError(
            f"{path.name}: no ayah markers found (expected '(1)' then '(2)' … "
            "or bare '106' … markers)."
        )

    ayahs: dict[int, str] = {}
    text_start = 0
    for marker_start, marker_end, num in markers:
        text = raw[text_start:marker_start].strip()
        if not text:
            raise ValueError(f"{path.name}: ayah {num} is empty after parsing.")
        ayahs[num] = text
        text_start = marker_end

    trailing = raw[text_start:].strip()
    if trailing:
        final_num = markers[-1][2] + 1
        if final_num in ayahs:
            raise ValueError(
                f"{path.name}: {len(trailing)} characters remain after ayah "
                f"{markers[-1][2]} but ayah {final_num} is already defined."
            )
        ayahs[final_num] = trailing
    return ayahs


def bazzi_ayah_numbers(ayah_map: dict[int, str]) -> list[int]:
    """Sorted Bazzi ayah keys, validating a contiguous 1…N sequence."""
    nums = sorted(ayah_map)
    if not nums or nums[0] != 1:
        raise ValueError("Bazzi text must start at ayah 1.")
    missing = [n for n in range(1, nums[-1] + 1) if n not in ayah_map]
    if missing:
        preview = missing[:10]
        suffix = "..." if len(missing) > 10 else ""
        raise ValueError(f"Bazzi text has gaps in ayah numbering: {preview}{suffix}")
    return nums
