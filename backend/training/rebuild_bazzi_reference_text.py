#!/usr/bin/env python3
"""Reconstruct correctly-numbered Bazzi ('an Ibn Kathir) Al-Baqarah ayah
boundaries from a raw scrape that had broken/off-by-one ayah markers.

Provenance: `bazzi_raw_scrape.txt` (next to this script) is the raw Surah
Al-Baqarah text for the Bazzi riwayah from the `Abdou/quran-riwayat` Hugging
Face dataset. Its ayah markers were unreliable — inconsistently placed, and
the marker for the final ayah (286) was missing entirely, leaving only 285
usable markers for 286 ayahs.

Fix: this script never trusts the raw markers. It strips them all, then uses
the known-good per-ayah word counts from the canonical Hafs text
(`training data/Al-Baqarah.txt`) as boundaries, and aligns the two
diacritic-stripped word streams with `difflib.SequenceMatcher` (interpolating
across the small number of genuine Bazzi/Hafs wording differences, e.g.
"تعملون" vs "يعملون") to map each Hafs ayah boundary onto the Bazzi word
stream. The result is written to `training data/Al-Baqarah_Bazzi.txt` in the
same "<ayah text> (<n>)" format as the Hafs file, with full tashkeel
preserved.

Verified output: 286/286 ayahs parsed, zero empty ayah chunks, zero leftover
unused tokens, and every non-"equal" opcode printed below corresponds to a
real qira'a variant (or the "۞" rub' marker being absent from the scrape),
not a misalignment.

Re-run with: python backend/training/rebuild_bazzi_reference_text.py
"""
import difflib
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

REPO_ROOT = Path(__file__).resolve().parents[2]
HAFS_PATH = REPO_ROOT / "training data" / "Al-Baqarah.txt"
BAZZI_RAW_PATH = Path(__file__).resolve().parent / "bazzi_raw_scrape.txt"
OUT_PATH = REPO_ROOT / "training data" / "Al-Baqarah_Bazzi.txt"
TOTAL_AYAHS = 286

_DIACRITICS_RE = re.compile(r"[\u064B-\u065F\u0670\u06D6-\u06ED]")


def strip_diacritics(word: str) -> str:
    return _DIACRITICS_RE.sub("", word)


def parse_ayah_map(raw: str) -> dict[int, str]:
    ayahs: dict[int, str] = {}
    for m in re.finditer(r"(.+?)\((\d+)\)", raw, flags=re.DOTALL):
        text, num = m.group(1).strip(), int(m.group(2))
        ayahs[num] = text
    return ayahs


def main() -> None:
    hafs_raw = HAFS_PATH.read_text(encoding="utf-8")
    ayahs = parse_ayah_map(hafs_raw)
    print("hafs ayahs parsed:", len(ayahs))

    hafs_words: list[str] = []
    for n in range(1, TOTAL_AYAHS + 1):
        hafs_words.extend(ayahs[n].split())
    print("total hafs words:", len(hafs_words))

    bazzi_raw = BAZZI_RAW_PATH.read_text(encoding="utf-8").strip()
    tokens = bazzi_raw.split()
    marker_re = re.compile(r"^\(?\d+\)?$")
    bazzi_words = [t for t in tokens if not marker_re.match(t)]
    print("bazzi word stream len (markers stripped):", len(bazzi_words))

    hafs_norm = [strip_diacritics(w) for w in hafs_words]
    bazzi_norm = [strip_diacritics(w) for w in bazzi_words]

    sm = difflib.SequenceMatcher(a=hafs_norm, b=bazzi_norm, autojunk=False)
    opcodes = sm.get_opcodes()
    print("opcodes:", len(opcodes))
    for tag, i1, i2, j1, j2 in opcodes:
        if tag != "equal":
            print(tag, i1, i2, j1, j2, hafs_words[i1:i2], "->", bazzi_words[j1:j2])

    # Map hafs word index -> bazzi word index using the "equal" blocks, then
    # interpolate proportionally across the small gaps (real word variants).
    map_h2b: dict[int, int] = {}
    for tag, i1, i2, j1, j2 in opcodes:
        if tag == "equal":
            for k in range(i2 - i1):
                map_h2b[i1 + k] = j1 + k

    n_hafs = len(hafs_words)

    def bazzi_pos_for_hafs_index(h_idx: int) -> int:
        """h_idx is an exclusive end boundary in the hafs word stream (0..n_hafs)."""
        if h_idx in map_h2b:
            return map_h2b[h_idx]
        if h_idx == 0:
            return 0
        if h_idx == n_hafs:
            return len(bazzi_words)
        lo, hi = h_idx - 1, h_idx
        while lo >= 0 and lo not in map_h2b:
            lo -= 1
        while hi < n_hafs and hi not in map_h2b:
            hi += 1
        if lo in map_h2b and hi in map_h2b:
            frac = (h_idx - lo) / (hi - lo)
            return round(map_h2b[lo] + frac * (map_h2b[hi] - map_h2b[lo]))
        if lo in map_h2b:
            return map_h2b[lo] + (h_idx - lo)
        if hi in map_h2b:
            return map_h2b[hi] - (hi - h_idx)
        return h_idx  # fallback, should not normally trigger

    ayah_end_hafs: dict[int, int] = {}
    running = 0
    for n in range(1, TOTAL_AYAHS + 1):
        running += len(ayahs[n].split())
        ayah_end_hafs[n] = running

    out_parts: list[str] = []
    prev_b = 0
    mismatches: list[int] = []
    for n in range(1, TOTAL_AYAHS + 1):
        b_end = bazzi_pos_for_hafs_index(ayah_end_hafs[n])
        b_end = max(b_end, prev_b)
        chunk = bazzi_words[prev_b:b_end]
        if not chunk:
            mismatches.append(n)
        out_parts.append(" ".join(chunk) + f" ({n})")
        prev_b = b_end

    leftover = bazzi_words[prev_b:]
    print("leftover unused tokens at end:", len(leftover), leftover[:20])
    print("ayahs with empty chunk:", mismatches)

    reconstructed = " ".join(out_parts)
    OUT_PATH.write_text(reconstructed, encoding="utf-8")
    print("wrote", OUT_PATH, len(reconstructed))


if __name__ == "__main__":
    main()
