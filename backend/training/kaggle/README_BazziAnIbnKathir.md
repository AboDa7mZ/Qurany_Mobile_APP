# Qurany Whisper fine-tune (Kaggle) — Surah Al-Baqarah — Al-Bazzi 'an Ibn Kathir (البزي عن ابن كثير)

Fine-tunes [tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) on **Surah 2 (Al-Baqarah)** in riwayah **Al-Bazzi 'an Ibn Kathir**, and exports a **Qurany-branded** model: `qurany-whisper-base-al-baqarah-bazzi`. Training labels keep full tashkeel/harakat, so the model stays diacritic-aware.

For the **Hafs 'an 'Asim** (حفص عن عاصم) counterpart, see [`README_HafsAnAsim.md`](./README_HafsAnAsim.md) — same architecture and training loop, different qira'a and (crucially) a different data-acquisition method, explained below.

## Why this pipeline differs from the Hafs one

Hafs 'an 'Asim has EveryAyah.com: a ready-made archive of one MP3 per ayah, per reciter, with matching Uthmani text from the AlQuran Cloud API. **No equivalent exists for Bazzi.** So instead of downloading 286 pre-segmented clips, this script:

1. Takes **one full-surah Bazzi recitation** that you upload.
2. Takes **your canonical Bazzi text** (`Al-Baqarah_Bazzi.txt`) — **you must supply this**; Bazzi numbering differs from Hafs (ayah 1 merges Hafs ayahs 1+2, so the surah has **285 Bazzi-numbered ayahs**, not 286).
3. Runs the base Whisper model over the full recording to get **word-level timestamps** (not the training target — just used to locate word boundaries in time).
4. Aligns the recognized words against the canonical Bazzi word stream with `difflib`-based sequence alignment, then interpolates a start/end timestamp for every ayah in the text file.
5. Slices the audio into per-ayah `.wav` clips and writes a `manifest.csv` — from this point on, training proceeds exactly like the Hafs script.
6. Writes a **`segmentation_qc.json`** report flagging any ayah whose detected duration is abnormally short/long, or whose boundary had no directly-aligned ASR word (pure interpolation) — **check this file before trusting a training run.**

### Canonical text: `Al-Baqarah_Bazzi.txt`

Use **your own** verified Bazzi Al-Baqarah text — do **not** use the old auto-generated file under `training data/Al-Baqarah_Bazzi.txt` (that was Hafs-aligned 286-ayah segmentation and is wrong for Bazzi).

Expected format (mixed markers are fine):

- Early ayahs: `<text> (1) <text> (2) …`
- Many publisher exports switch to bare numbers from ayah 106 onward: `… 106 … 107 …`
- Parentheses may reappear later (e.g. around ayat al-kursi): `… (253) … 254 …`
- **Ayah 1** must include the merged opening (Alif-Lam-Mim **and** “ذلك الكتاب…”), unlike Hafs where those are separate ayahs 1 and 2.

The training script parses whatever contiguous Bazzi numbering `1…N` is present (typically **N = 285**).

## Path reference (read this before hitting Run All)

| What | Path | Who sets it up |
|------|------|-----------------|
| Training script on disk | `/kaggle/working/qurany_whisper_finetune_bazzi_an_ibn_kathir.py` | **Automatic** — Cell 2's `%%writefile`, embedded verbatim in the `.ipynb`. |
| **Your Bazzi materials** | `/kaggle/input/qurany-bazzi-training-data/` | **Manual, required** — see below. Unlike the Hafs notebook, this is NOT optional; there's no fallback data source. |
| Auto-segmented audio + manifest | `/kaggle/working/quran_data/audio/*.wav`, `/kaggle/working/quran_data/manifest.csv` | Automatic — `segment_full_recitation()` on Cell 4 (first run only; reruns reuse the existing manifest). |
| Segmentation QC report | `/kaggle/working/quran_data/segmentation_qc.json` | Automatic — **inspect this before training.** |
| Pre-processed features (Arrow cache) | `/kaggle/working/quran_data/processed_dataset/` | Automatic — Cell 4, same as Hafs. |
| Trainer checkpoints / zips | `/kaggle/working/runs/checkpoint-<step>/`, `checkpoint<step>.zip` | Automatic. |
| Final merged model | `/kaggle/working/qurany-whisper-base-al-baqarah-bazzi/` (+ `.zip`) | Automatic. |

### Setting up the required `qurany-bazzi-training-data` dataset

1. On Kaggle, click **+ Add Data → New Dataset** and title it exactly **`qurany-bazzi-training-data`** (matching titles avoids a slug mismatch).
2. Upload, all at the dataset's **root** (not a subfolder):
   - `Al-Baqarah_Bazzi.txt` — **your** canonical Bazzi text (e.g. from `training data2/Al-Baqarah_Bazzi.txt` in this repo after you verify it).
   - Your **one full Al-Baqarah recitation** (any format in `.mp3`/`.wav`/`.m4a`/`.ogg`). The script auto-selects the **longest** audio file in the dataset as this recording, so don't upload multiple long files.
   - *(Optional)* any short test clips you also have — anything else in the folder is automatically treated as a held-out external evaluation set (transcribed + mistake-checked after training, never mixed into the training data).
3. Attach the dataset via **Add Data** before running Cell 4.
4. If you named the dataset differently, edit `cfg.bazzi_input_dir` in Cell 4 to match.

## Kaggle setup

1. Create a new **Notebook** on Kaggle and open/import `Qurany_Whisper_Finetune_البزي_عن_ابن_كثير.ipynb`.
2. **Settings → Accelerator → GPU T4 × 2** (recommended) or **GPU P100 × 1**.
3. Enable **Internet** (required for Hugging Face model downloads).
4. Complete the **required** `qurany-bazzi-training-data` dataset setup above.

## Run

Run cells **top to bottom**:

1. Cell 1 — installs dependencies, uninstalls `torchao` (same Kaggle/`peft` incompatibility workaround as the Hafs notebook).
2. Cell 2 — `%%writefile` writes `qurany_whisper_finetune_bazzi_an_ibn_kathir.py` to `/kaggle/working/`.
3. Cell 3 — imports it back + lists GPUs.
4. Cell 4 — **the main new step**: `download_training_data(cfg)` calls `segment_full_recitation()` the first time it's run (transcribes the full recording, aligns it against the canonical text, slices per-ayah clips, writes the QC report — this can take a few minutes depending on recitation length and GPU), then `warm_hf_model_cache()` + `prepare_and_cache_dataset()` as in the Hafs notebook. **Read the printed QC summary** — if many ayahs are flagged, inspect `segmentation_qc.json` before continuing; delete `/kaggle/working/quran_data/manifest.csv` to force re-segmentation after fixing the input data.
5. Cell 5 — launches training via `accelerate launch` (same CUDA-fork-safety reasoning as the Hafs notebook: do **not** swap in `notebook_launcher`).
6. Cell 6 — prints the external-evaluation summary for any leftover short clips.

### Avoiding training hangs / CUDA fork crashes

Identical caveats to the Hafs notebook: audio decoding happens in Cell 4 before any GPU workers start, and Cell 5 uses `accelerate launch` (spawn), not `notebook_launcher` (fork), to avoid `Cannot re-initialize CUDA in forked subprocess`.

### If segmentation quality looks poor

- Check `segmentation_qc.json` for flagged ayahs (`duration_out_of_range` or `no_aligned_asr_word`).
- The alignment model is controlled by `cfg.align_model_name` (default: the base `tarteel-ai/whisper-base-ar-quran`) — it's only used to *locate* word boundaries in time, never as the training label source, so its own transcription mistakes mostly wash out; but if your recording has heavy background noise or an unusual reciting pace, alignment quality can suffer. Re-running after fixing the audio (e.g. trimming leading/trailing silence) is cheap: just delete `manifest.csv` and `segmentation_meta.json` under `/kaggle/working/quran_data/` and re-run Cell 4.
- Flagged ayahs still get a clip (never silently dropped), just a shorter/longer/interpolated one — decide per-flag whether that's acceptable or worth fixing.

## Outputs

| Path | Description |
|------|-------------|
| `/kaggle/working/qurany-whisper-base-al-baqarah-bazzi/` | Merged final model + processor |
| `/kaggle/working/qurany-whisper-base-al-baqarah-bazzi.zip` | Downloadable zip |
| `/kaggle/working/checkpoint{step}.zip` | Auto-zipped each `save_steps` |
| `/kaggle/working/quran_data/segmentation_qc.json` | Auto-segmentation QC report — check this first |
| `/kaggle/working/external_eval_*.json` | Held-out clip evaluation (if you added extra clips) |
| `/kaggle/output/*.zip` | Persisted copies (Save Version) |

## Training scope & strategy

- **Riwayah (qira'a):** Al-Bazzi 'an Ibn Kathir (البزي عن ابن كثير)
- **Surah:** 2 (Al-Baqarah) — full Bazzi ayah set (~285 ayahs, Bazzi numbering), single user-supplied reciter, auto-segmented
- **LoRA**, epoch budget, early stopping: identical strategy to the Hafs script (see `README_HafsAnAsim.md` § Training scope & strategy) — nothing riwayah-specific here, only the data source changed.

## After Kaggle

1. Download `qurany-whisper-base-al-baqarah-bazzi.zip`.
2. Extract into `backend/models/qurany-whisper-base-al-baqarah-bazzi/`.
3. In `backend/.env` (or environment), set:
   ```
   ASR_BACKEND=transformers
   CUSTOM_MODEL_PATH=./models/qurany-whisper-base-al-baqarah-bazzi
   ```
   Same wiring as the Hafs model — see `backend/README.md`.

## Smoke test (local, 20 clips)

Requires a `manifest.csv` already produced by a Kaggle run (or point `cfg.bazzi_input_dir` at local test files):

```bash
cd backend/training/kaggle
pip install transformers datasets peft accelerate jiwer soundfile librosa pandas torch
python qurany_whisper_finetune_bazzi_an_ibn_kathir.py --smoke-test
```

## Verify your text file locally

```bash
cd backend
python -c "from pathlib import Path; from training.kaggle.qurany_whisper_finetune_bazzi_an_ibn_kathir import _parse_bazzi_reference_txt, _bazzi_ayah_numbers; p=Path('../training data2/Al-Baqarah_Bazzi.txt'); m=_parse_bazzi_reference_txt(p); n=_bazzi_ayah_numbers(m); print(len(n), 'ayahs', n[0], '->', n[-1])"
```

Expected: `285 ayahs 1 -> 285`.
