"""
Word-level forced alignment of recitation audio against known-correct verse
text, using CTC forced alignment (torchaudio.functional.forced_align).

cpfair/quran-align (https://github.com/cpfair/quran-align) was the original
plan for this, but it turned out to require compiling CMU Sphinx/PocketSphinx
from source, and its README states the acoustic-model training script is
unpublished -- not something to debug inside a 4-day budget. torchaudio's
forced_align is a portable, pure-PyTorch equivalent: run any CTC acoustic
model over the audio, then align its per-frame emissions to the expected
token sequence. This uses jonatasgrosman/wav2vec2-large-xlsr-53-arabic, a
general-purpose Arabic wav2vec2-CTC model (not Quran-specific, but alignment
only needs to locate where each word *starts and ends*, not judge
correctness -- ASR/tajweed correctness comes from asr.py and rules.py).

This model's vocab (checked directly against its vocab.json) turns out to
include the 8 standard tashkeel marks alongside the 28 Arabic letters, so
harakat are kept rather than stripped -- they give the forced aligner more
anchor points. What the vocab lacks is Quran-specific Uthmani-script
characters (alef wasla, dagger alif, maddah), which get normalized/dropped
before alignment; see _NORMALIZE below.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

import torch
import torchaudio.functional as AF
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

from audio_utils import load_audio

ALIGN_MODEL_NAME = "jonatasgrosman/wav2vec2-large-xlsr-53-arabic"

_ALEF_WASLA = chr(0x0671)
_DAGGER_ALEF = chr(0x0670)
_MADDAH_ABOVE = chr(0x0653)
_PLAIN_ALEF = chr(0x0627)

_NORMALIZE = {
    _ALEF_WASLA: _PLAIN_ALEF,
    _DAGGER_ALEF: _PLAIN_ALEF,
    _MADDAH_ABOVE: "",
}


def _to_vocab_tokens(text: str, vocab: dict, word_delim: str, pad_id: int) -> list[int]:
    """Map `text` to vocab token ids, normalizing Quranic-only characters and
    silently dropping anything the vocab has no symbol for. `pad_id` (the
    blank id) must never appear in this list -- forced_align rejects it as
    an explicit target -- so unknown characters are dropped, not padded.
    """
    ids = []
    for ch in text:
        if ch == " ":
            ids.append(vocab[word_delim])
            continue
        ch = _NORMALIZE.get(ch, ch)
        if not ch:
            continue
        tok_id = vocab.get(ch)
        if tok_id is not None and tok_id != pad_id:
            ids.append(tok_id)
    return ids


@dataclass
class WordTiming:
    word: str
    start_ms: float
    end_ms: float


@lru_cache(maxsize=1)
def _load_align_model(model_name: str = ALIGN_MODEL_NAME):
    processor = Wav2Vec2Processor.from_pretrained(model_name)
    model = Wav2Vec2ForCTC.from_pretrained(model_name)
    model.eval()
    return processor, model


def align_words(
    audio_path: str,
    reference_words: list[str],
    model_name: str = ALIGN_MODEL_NAME,
) -> list[WordTiming]:
    """Force-align `reference_words` (the expected verse, already split into
    words) against `audio_path`. Returns one WordTiming per input word, in
    order; a word contributing no vocab-recognizable characters gets a
    zero-length span so the output stays index-aligned with
    `reference_words`.
    """
    processor, model = _load_align_model(model_name)
    vocab = processor.tokenizer.get_vocab()
    id_to_token = {v: k for k, v in vocab.items()}
    blank_id = processor.tokenizer.pad_token_id
    word_delim = processor.tokenizer.word_delimiter_token or "|"

    waveform, sr = load_audio(audio_path)

    with torch.inference_mode():
        inputs = processor(waveform, sampling_rate=sr, return_tensors="pt")
        logits = model(inputs.input_values).logits
        emission = torch.log_softmax(logits, dim=-1)

    transcript = " ".join(reference_words)
    token_ids = _to_vocab_tokens(transcript, vocab, word_delim, blank_id)

    targets = torch.tensor([token_ids], dtype=torch.long)
    alignment, scores = AF.forced_align(emission, targets, blank=blank_id)
    spans = AF.merge_tokens(alignment[0], scores[0], blank=blank_id)

    num_frames = emission.shape[1]
    audio_duration_ms = len(waveform) / sr * 1000
    frame_ms = audio_duration_ms / num_frames

    # merge_tokens yields exactly one span per entry in `token_ids`, in
    # order (the standard torchaudio CTC-forced-alignment guarantee); walk
    # them in lockstep, splitting on the word-delimiter token to know where
    # each word's audio begins/ends.
    timings: list[WordTiming] = []
    cur_start_frame: int | None = None
    cur_end_frame: int | None = None
    word_idx = 0

    def flush():
        nonlocal cur_start_frame, cur_end_frame, word_idx
        if word_idx >= len(reference_words):
            return
        if cur_start_frame is not None:
            timings.append(
                WordTiming(reference_words[word_idx], cur_start_frame * frame_ms, cur_end_frame * frame_ms)
            )
        else:
            timings.append(WordTiming(reference_words[word_idx], 0.0, 0.0))
        word_idx += 1
        cur_start_frame = None
        cur_end_frame = None

    for span in spans:
        tok = id_to_token.get(span.token)
        if tok == word_delim:
            flush()
            continue
        if cur_start_frame is None:
            cur_start_frame = span.start
        cur_end_frame = span.end

    flush()  # last word has no trailing delimiter
    while word_idx < len(reference_words):
        timings.append(WordTiming(reference_words[word_idx], 0.0, 0.0))
        word_idx += 1

    return timings


if __name__ == "__main__":
    import sys

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    if len(sys.argv) < 3:
        print("Usage: python align.py <audio_file> <reference_text>")
        raise SystemExit(1)

    words = sys.argv[2].split(" ")
    for t in align_words(sys.argv[1], words):
        print(f"  {t.start_ms:8.1f} - {t.end_ms:8.1f} ms  {t.word}")
