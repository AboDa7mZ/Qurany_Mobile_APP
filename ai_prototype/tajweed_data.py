"""
Loads Surah Al-Baqarah's Uthmani text and tajweed rule annotations, and merges
them into per-verse, per-word structures the rule engine can consume.

Sources (fetched once and cached under ai_prototype/data/):
- Uthmani text: alquran.cloud API (mirrors Tanzil.net's quran-uthmani text,
  including embedded waqf/stop-sign glyphs).
- Tajweed rule spans: cpfair/quran-tajweed's
  tajweed.hafs.uthmani-pause-sajdah.json, which gives Unicode-codepoint
  [start, end) spans *within each verse's Tanzil Uthmani text* for 18 rule
  categories (madd, ghunnah, idghaam, ikhfa, iqlab, qalqalah, hamzat_wasl,
  lam_shamsiyyah, silent). Verified against the live dataset: it does NOT
  include waqf/stop signs as a rule category, because those are already
  present as embedded characters in the Uthmani text itself.
"""

from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
UTHMANI_URL = "https://api.alquran.cloud/v1/surah/{surah}/quran-uthmani"
TAJWEED_URL = (
    "https://raw.githubusercontent.com/cpfair/quran-tajweed/master/"
    "output/tajweed.hafs.uthmani-pause-sajdah.json"
)

AL_BAQARAH = 2

# Waqf (stop-sign) marks embedded directly in the Tanzil Uthmani text.
# Unicode range U+06D6-U+06DC; other marks in the wider U+06D6-U+06ED band
# (e.g. small high meem for iqlab, small waw/yeh for madd) duplicate what the
# tajweed JSON already reports as separate rules, so they're not treated as
# waqf here.
WAQF_MARKS = {
    "ۖ": ("sali_lai", "preferred: continue"),
    "ۗ": ("qala_alayhi", "preferred: stop"),
    "ۘ": ("meem", "obligatory stop"),
    "ۙ": ("la", "do not stop"),
    "ۚ": ("jeem", "permissible to stop"),
    "ۛ": ("three_dots", "stop at one of two places, not both"),
    "ۜ": ("seen", "pause without breath (saktah)"),
}


@dataclass
class WordSpan:
    index: int          # word index within the verse (0-based)
    text: str            # word text incl. diacritics, as it appears in Uthmani text
    start: int           # codepoint offset of the word's first char in verse text
    end: int              # codepoint offset one past the word's last char
    rules: list[str] = field(default_factory=list)      # tajweed rules overlapping this word
    waqf: str | None = None                              # waqf mark name immediately after this word, if any


@dataclass
class VerseData:
    surah: int
    ayah: int
    text: str
    words: list[WordSpan]


def _download(url: str, cache_path: Path) -> bytes:
    if cache_path.exists():
        return cache_path.read_bytes()
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=30) as resp:
        raw = resp.read()
    cache_path.write_bytes(raw)
    return raw


def _load_uthmani_text(surah: int) -> dict[int, str]:
    raw = _download(UTHMANI_URL.format(surah=surah), DATA_DIR / f"uthmani_surah_{surah}.json")
    payload = json.loads(raw)
    return {a["numberInSurah"]: a["text"] for a in payload["data"]["ayahs"]}


def _load_tajweed_annotations(surah: int) -> dict[int, list[dict]]:
    raw = _download(TAJWEED_URL, DATA_DIR / "tajweed.hafs.uthmani-pause-sajdah.json")
    payload = json.loads(raw)
    return {v["ayah"]: v["annotations"] for v in payload if v["surah"] == surah}


def _split_words(text: str) -> list[tuple[int, int, str]]:
    """Split verse text on spaces, keeping codepoint offsets for each word."""
    words = []
    pos = 0
    for chunk in text.split(" "):
        if chunk:
            words.append((pos, pos + len(chunk), chunk))
        pos += len(chunk) + 1  # +1 for the space separator
    return words


def _tag_words(text: str, annotations: list[dict]) -> list[WordSpan]:
    raw_words = _split_words(text)

    # Tanzil's Uthmani text renders waqf marks -- and other unpronounced
    # Quranic annotation glyphs sharing the same Unicode block (U+06D6-U+06ED:
    # rub-el-hizb "۞", sajda "۩", etc.) -- as their own space-separated
    # token, placed right after the word they apply to (e.g.
    # "... رَّبِّهِمْ ۖ وَأُو۟لَٰٓئِكَ ..."). None of these are spoken, so
    # fold waqf marks onto the preceding real word and drop everything else
    # in the block instead of treating it as its own "word" (which would
    # otherwise show up as a spurious "omitted" flag -- nothing was ever
    # going to be recited for it).
    spans: list[WordSpan] = []
    for s, e, w in raw_words:
        if len(w) == 1 and 0x06D6 <= ord(w) <= 0x06ED:
            if w in WAQF_MARKS and spans:
                spans[-1].waqf = WAQF_MARKS[w][0]
            continue
        spans.append(WordSpan(index=len(spans), text=w, start=s, end=e))

    for ann in annotations:
        for w in spans:
            if ann["start"] < w.end and ann["end"] > w.start:
                w.rules.append(ann["rule"])

    return spans


def load_surah(surah: int = AL_BAQARAH) -> list[VerseData]:
    """Return every verse of `surah` with words tagged by tajweed rule and waqf mark."""
    texts = _load_uthmani_text(surah)
    annotations = _load_tajweed_annotations(surah)

    verses = []
    for ayah in sorted(texts):
        text = texts[ayah]
        words = _tag_words(text, annotations.get(ayah, []))
        verses.append(VerseData(surah=surah, ayah=ayah, text=text, words=words))
    return verses


def load_verse(ayah: int, surah: int = AL_BAQARAH) -> VerseData:
    for v in load_surah(surah):
        if v.ayah == ayah:
            return v
    raise ValueError(f"Surah {surah} ayah {ayah} not found")


if __name__ == "__main__":
    import sys

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    verses = load_surah(AL_BAQARAH)
    print(f"Loaded {len(verses)} verses of Surah Al-Baqarah")
    sample = verses[4]  # ayah 5, has madd_muttasil + idghaam per manual check
    print(f"Ayah {sample.ayah}: {sample.text}")
    for w in sample.words:
        if w.rules or w.waqf:
            print(f"  word[{w.index}] {w.text!r} rules={w.rules} waqf={w.waqf}")
