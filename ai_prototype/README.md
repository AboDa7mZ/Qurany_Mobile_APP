# Al-Baqarah tajweed feedback prototype

Standalone Python prototype demonstrating harakat/madd/waqf feedback on
Surah Al-Baqarah recitation. Built as a 4-day, ~30-Kaggle-GPU-hour milestone
deliverable — see the plan at
`C:\Users\ahmed\.claude\plans\hello-this-project-we-reactive-trinket.md` for
the full context and why this approach (pretrained ASR + rule engine, no
fine-tuning) was chosen over fine-tuning a model from scratch.

Not wired into the Flutter app yet — there's no backend service to
integrate with (see the technical plan's own later-phase roadmap), and
`../Test.py` remains the only prior AI artifact in this repo, which this
supersedes for accuracy but not for app integration.

## Architecture

```
recitation audio
   |
   +--> asr.py     (tarteel-ai/whisper-base-ar-quran)  --> what was said
   +--> align.py   (wav2vec2 CTC forced alignment)      --> when each word was said
   |
tajweed_data.py (cpfair/quran-tajweed + Tanzil Uthmani text via alquran.cloud)
   --> what the tajweed rules require, per word
   |
   v
rules.py --> per-word feedback: word/harakat mismatches, madd duration
             flags, waqf (stop-sign) flags
   |
   v
run_demo.py --> structured per-verse JSON
```

No training or fine-tuning anywhere in this pipeline — both ML models are
used purely for inference (transcription and forced alignment), and all
tajweed-rule knowledge comes from static, pre-existing datasets. See "Future
work" for what fine-tuning would add and what it would take.

## Key findings from building this

**Tarteel's model preserves harakat.** It wasn't documented anywhere
reliable whether `tarteel-ai/whisper-base-ar-quran`'s output keeps
diacritics. Verified empirically on a real Alafasy recitation of 2:6: the
transcription came back fully diacritized and nearly character-for-character
correct. This means word-level ASR-vs-reference comparison in `rules.py`
doubles as a harakat-level check, without needing a separate model.

**Raw text comparison is dominated by orthography noise, not pronunciation
errors.** The first end-to-end run against a *correct* reference recitation
(2:6, Alafasy) flagged 5 of 11 words as "harakat mismatches." Every single
one was a false positive caused by Uthmani Qur'anic script using different
spelling conventions than the modern Arabic text this ASR model was trained
to output — not an actual pronunciation difference:
- alef wasla (`ٱ`) vs. plain alef (`ا`)
- optional/implicit sukun in Uthmani script vs. explicit sukun in modern text
- the decomposed alef+combining-maddah+hamza spelling Tanzil uses (e.g. in
  `سَوَآءٌ`) vs. the precomposed `آ` most modern text uses
- small-high marks for silent letters (e.g. the extra alif in `كَفَرُوا۟`)
  that are never pronounced
- the `۞` rub-el-hizb marker and similar Quranic annotation glyphs, which
  Tanzil's text renders as their own space-separated "word" even though
  nothing is recited for them
- dagger alif (`ٰ`) vs. a full alef letter
- alef maqsura (`ى`) vs. plain yeh (`ي`) at word-final position

`rules.py`'s `_normalize_for_comparison()` folds all of these away before
judging equality/similarity (the *original* text is still what's shown to
the user — normalization is comparison-only). After adding it: **0/11 words
flagged on the 2:6 reference recitation**, and flagged word count on a
longer, harder verse (2:26, 39 words) dropped from 12 to 9 — with the
remaining 9 being genuine edge cases, documented below rather than chased
further given the time budget.

**`quran-align` was abandoned for a portable alternative.** The plan
originally called for `cpfair/quran-align` for forced alignment. Its README
turned out to require compiling CMU Sphinx/PocketSphinx from source, and
states its acoustic-model training script is unpublished — not something to
debug in a 4-day window. Swapped in `torchaudio.functional.forced_align`
(pure PyTorch) driven by `jonatasgrosman/wav2vec2-large-xlsr-53-arabic`, a
general-purpose Arabic wav2vec2-CTC model. This only needs to locate *where*
each word starts/ends, not judge correctness, so a Quran-specific model
isn't required for this step. Verified word timings are monotonic and
plausible (e.g. words carrying a madd rule got visibly longer aligned
durations than plain words, on both test verses).

**Verses longer than Whisper's 30s window need a generation_config patch.**
2:26 is ~43 seconds, past Whisper's context window, which forces the
`transformers` pipeline into chunked long-form decoding — that requires
timestamp tokens to stitch chunks together. `tarteel-ai/whisper-base-ar-quran`
was published without a `generation_config` carrying those tokens
([known issue](https://github.com/huggingface/transformers/issues/21878)).
Fixed in `asr.py` by borrowing the timestamp-related config fields from
`openai/whisper-base` (same architecture/tokenizer, this checkpoint only
fine-tunes the weights).

## Known limitations (not fixed — documented for the next phase)

- **Shadda/gemination is under-transcribed by the ASR even when correctly
  pronounced.** On 2:26 (Alafasy, a professional reciter), both idghaam
  words (`مَّا` from tanwin+meem idghaam, `رَّبِّهِمْ` from noon-sukun+ra
  idghaam) came back from the ASR without the shadda, producing
  `harakat_mismatch` flags despite the tajweed rule being correctly
  recited. This is an ASR acoustic-modeling weakness (gemination is subtle),
  not a bug in this pipeline — it means shadda-dependent tajweed rules
  (idghaam, iqlab) can't be reliably verified through ASR-transcript
  comparison alone with this model.
- **A few Uthmani small-high marks represent an elided-but-pronounced
  letter**, not silence (e.g. `ۦ` small-high-yeh in `يَسْتَحْىِۦٓ` implies
  an extra pronounced yeh that modern spelling writes out in full,
  `يَسْتَحْيِي`). `_normalize_for_comparison()` currently strips these the
  same as genuinely-silent marks, which under-counts a letter and produces
  a residual `word_mismatch`. Fixing this properly means mapping specific
  marks to their implied letter instead of deleting them.
- **A handful of classical Arabic words have irregular spelling**: `هَٰذَا`
  is pronounced "haadhaa" (long) but modern spelling just writes `هذا`
  (short) — the Uthmani dagger-alif correctly marks the length, but there's
  no letter-for-letter equivalent in modern spelling to normalize onto. A
  short hardcoded exception list (`هذا`, `هذه`, `ذلك`, `أولئك`, `الرحمن`,
  `لكن`, ...) would resolve this; not implemented here.
- **Occasional ASR word-concatenation.** On 2:26 the model output
  `مَثَلًايُضِلُّ` with no space between two words, breaking the
  whitespace-based word alignment for that segment. A production version
  would want a recovery heuristic (e.g. re-split on a partial match against
  the two nearest expected words) instead of whitespace-only splitting.
- **Madd-duration thresholds (`rules.py: MADD_MULTIPLIERS`,
  `MADD_TOLERANCE`) are unvalidated heuristic placeholders**, not measured
  from real tajweed timing data. They produced 2 spurious
  `*_too_short` flags on 2:26's correct recitation, suggesting the
  tolerance band is currently too tight. Before trusting madd flags,
  calibrate these constants against several correct reference reciters
  covering all `MADD_MULTIPLIERS` rule types, and prefer per-reciter
  relative bands (this file already computes a per-recitation baseline
  ms/char) over a single global constant.
- **Waqf detection uses the aligned-word silence gap as the pause signal**,
  not independent audio energy/VAD analysis. This is simpler and reuses the
  same alignment output, but hasn't been validated against a verse with an
  obligatory stop mark and a reciter who audibly pauses there vs. one who
  doesn't (time ran out before finding/testing such a sample — see
  Verification below for what *was* tested).

## Files

- `tajweed_data.py` — loads Tanzil Uthmani text (via alquran.cloud) +
  `cpfair/quran-tajweed`'s rule annotations, merges into per-word structures
  tagged with tajweed rules and waqf marks.
- `audio_utils.py` — shared MP3/WAV loading via `soundfile` (avoids an
  `ffmpeg`-on-PATH dependency the `transformers` pipeline would otherwise
  need).
- `asr.py` — wraps `tarteel-ai/whisper-base-ar-quran` for transcription.
- `align.py` — wraps a wav2vec2-CTC model for forced word-timing alignment.
- `rules.py` — the rule engine: madd duration check, waqf pause check,
  word/harakat mismatch check (with orthography normalization).
- `run_demo.py` — end-to-end CLI: audio + ayah number in, JSON feedback out.
- `data/` — cached downloads (Tanzil text, tajweed JSON) and audio samples.

## Usage

```
pip install -r requirements.txt
python run_demo.py data/samples/002006.mp3 6
```

Sample audio used for development/verification was downloaded from
[everyayah.com](https://everyayah.com/data/Alafasy_128kbps/) (Alafasy
recitation), e.g.:
```
curl -o data/samples/002006.mp3 https://everyayah.com/data/Alafasy_128kbps/002006.mp3
```

## Verification performed

- **2:6 (Alafasy, correct reference recitation, 11 words)**: 0/11 words
  flagged after the orthography-normalization fixes. Confirms near-zero
  false positives on correct recitation, as required.
- **2:26 (Alafasy, correct reference recitation, longer/harder verse, 39
  words after filtering the rub-el-hizb marker)**: 9/39 words flagged, all
  traced to the specific, documented limitations above (ASR
  under-transcribing shadda, one elided-letter mark, one irregular-spelling
  word, one ASR word-concatenation artifact, two madd-threshold
  calibration misses) — not unexplained/random noise.
- Word timing sanity-checked on both verses: monotonic, plausible durations,
  and words carrying a madd rule visibly longer than plain words.
- **Not done, suggested as the next manual test**: recording a
  deliberately mispronounced sample (wrong elongation length, skipped stop,
  wrong word) to confirm the rule engine flags *introduced* errors, not
  just correct recitation cleanly. All verification so far used correct
  reference audio only, which validates the false-positive rate but not
  true-positive detection.

## Future work: fine-tuning

Everything here is inference-only against pretrained models plus static
rule data. True acoustic harakat-mispronunciation detection (distinguishing
a student's wrong vowel from a correct one at the acoustic level, rather
than via ASR-transcript text comparison) would need a model trained on
labeled recitation errors — audio tagged with *specific, deliberate*
mistakes, not just correct recitations. That data doesn't exist yet. A
concrete next step: recruit a few Quran teachers to label common student
mistakes on Al-Baqarah verses (a few hundred labeled short clips would be a
reasonable start), then LoRA-fine-tune
`tarteel-ai/whisper-base-ar-quran` or train a lightweight classifier on top
of the wav2vec2 forced-aligner's frame-level features. Until that data
exists, this rule-based pipeline is the more realistic approach.
