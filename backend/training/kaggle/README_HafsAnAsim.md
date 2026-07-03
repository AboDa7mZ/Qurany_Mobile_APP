# Qurany Whisper fine-tune (Kaggle) — Surah Al-Baqarah — Hafs 'an 'Asim (حفص عن عاصم)

Fine-tunes [tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) on **all 286 ayahs of Surah 2 (Al-Baqarah)**, riwayah **Hafs 'an 'Asim** (the standard riwayah used by EveryAyah's Alafasy reciter and by nearly all mainstream mushafs), and exports a **Qurany-branded** model: `qurany-whisper-base-al-baqarah`. Training labels keep full **Uthmani tashkeel/harakat** (not stripped), so the model is diacritic-aware — a prerequisite for any Tajweed-level feedback.

For the **Bazzi 'an Ibn Kathir** (البزي عن ابن كثير) counterpart, see [`README_BazziAnIbnKathir.md`](./README_BazziAnIbnKathir.md) in this same folder — same architecture and pipeline, different qira'a data source.

## Path reference (read this before hitting Run All)

| What | Path | Who sets it up |
|------|------|-----------------|
| Training script on disk | `/kaggle/working/qurany_whisper_finetune_hafs_an_asim.py` | **Automatic** — Cell 2 of the notebook is `%%writefile /kaggle/working/qurany_whisper_finetune_hafs_an_asim.py` followed by the *entire* script, embedded verbatim in the `.ipynb`. Running that cell writes the file; nothing to copy/paste by hand. |
| Downloaded audio + labels | `/kaggle/working/quran_data/audio/*.mp3`, `/kaggle/working/quran_data/manifest.csv` | Automatic — `download_training_data()` fetches these from EveryAyah + AlQuran Cloud on Cell 4. |
| Pre-processed features (Arrow cache) | `/kaggle/working/quran_data/processed_dataset/` | Automatic — `prepare_and_cache_dataset()` decodes audio + tokenizes labels once, in Cell 4, *before* training forks any GPU workers (see "Avoiding the `Map … 0%` hang" below). |
| Trainer checkpoints | `/kaggle/working/runs/checkpoint-<step>/` | Automatic (Hugging Face `Trainer`). |
| Checkpoint zips (downloadable) | `/kaggle/working/checkpoint<step>.zip` + copy under `/kaggle/output/` | Automatic — `AutoDownloadCheckpoint` on every `on_save`. |
| Final merged model | `/kaggle/working/qurany-whisper-base-al-baqarah/` (+ `.zip`) | Automatic, written at the end of `train_qurany_whisper()`. |
| **Your own test recordings** | `/kaggle/input/qurany-training-data/` | **Manual, optional** — see below. This is the *only* path that needs action from you. |

### Setting up the optional external test set

1. On Kaggle, click **+ Add Data → New Dataset**, upload your `Al-Baqarah.txt` + full recitation + short clips, and title it exactly **`qurany-training-data`** (Kaggle slugifies the title into the folder name — matching titles avoids a slug mismatch, e.g. `Qurany Training Data` → `qurany-training-data`).
2. Put every file at the dataset's **root** — not inside a subfolder — since `run_external_evaluation()` only globs one level deep (`test_dir / "*.mp3"`, not recursive).
3. Attach the dataset to the notebook via **Add Data** in the right-hand panel before running Cell 4/5.
4. If Kaggle gives your dataset a different slug, either rename the dataset or edit `cfg.external_test_dir` in Cell 4 to match (or set it to `None` to skip this step entirely — training is unaffected either way, since this data is never mixed into the training set).

## Kaggle setup

1. Create a new **Notebook** on Kaggle and open/import `Qurany_Whisper_Finetune_حفص_عن_عاصم.ipynb` (File → Import Notebook), or copy its cells in manually.
2. **Settings → Accelerator → GPU T4 × 2** (recommended) or **GPU P100 × 1**.
3. Enable **Internet** (required for EveryAyah + Hugging Face + AlQuran Cloud).
4. *(Optional, for real-audio mistake-detection testing)* **Add Data** → upload a dataset named `qurany-training-data` containing:
   - `Al-Baqarah.txt` (canonical text — the same file as `training data/Al-Baqarah.txt` in this repo)
   - your full Al-Baqarah recitation (any reciter, even one with mistakes)
   - your short test clips (`.mp3` / `.wav` / `.m4a`)

   These files are **never used for training** (we don't have a verified per-ayah mapping for them) — they're only run through the fine-tuned model at the end for a held-out WER + mistake-detection sanity check. Skip this step and training still works fine; `cfg.external_test_dir` just won't be found and that step is silently skipped.

## Run

Open `Qurany_Whisper_Finetune_حفص_عن_عاصم.ipynb` in Kaggle and run cells **top to bottom**:

1. Cell 1 — installs dependencies, then uninstalls `torchao` (Kaggle ships an old 0.10.0 that makes recent `peft` versions raise `ImportError: Found an incompatible version of torchao...` inside `get_peft_model()`, even though this script never touches torchao/quantization — removing it makes `peft` skip that check and fall back to plain LoRA `Linear`).
2. Cell 2 — `%%writefile` writes `qurany_whisper_finetune_hafs_an_asim.py` to `/kaggle/working/` (the full source is embedded in this cell — no manual upload needed).
3. Cell 3 — imports it back + lists detected GPUs via `!nvidia-smi -L`. **Do not** replace this with a `torch.cuda.*` call — see "Avoiding the `Map … 0%` hang" below.
4. Cell 4 — downloads Al-Baqarah audio/text, then **pre-processes it** (`prepare_and_cache_dataset`): decodes every clip to log-mel features + tokenized labels here, in the main process, and caches the result to `/kaggle/working/quran_data/processed_dataset/`.
5. Cell 5 — launches training via **`accelerate launch`** (spawns fresh GPU worker processes). Do **not** use `notebook_launcher` here — on Kaggle/Python 3.12 it forks the Jupyter kernel after CUDA is already active and crashes with `Cannot re-initialize CUDA in forked subprocess`.
6. Cell 6 — prints the external-evaluation summary, if any.

### Avoiding training hangs / CUDA fork crashes

- **`Map (num_proc=1): 0%` hang:** all audio decoding happens in Cell 4 (`prepare_and_cache_dataset`) before any GPU workers start.
- **`Cannot re-initialize CUDA in forked subprocess`:** Cell 5 uses `accelerate launch` (spawn), not `notebook_launcher` (fork). Do not replace Cell 5 with `notebook_launcher` or call `torch.cuda.*` in Cells 3–4.

If you'd rather drive it from plain Python instead of stepping through cells:

```python
from qurany_whisper_finetune_hafs_an_asim import launch_on_kaggle
launch_on_kaggle(num_processes=2)   # T4 × 2
# launch_on_kaggle(num_processes=1)  # P100
```

## Outputs

| Path | Description |
|------|-------------|
| `/kaggle/working/qurany-whisper-base-al-baqarah/` | Merged final model + processor |
| `/kaggle/working/qurany-whisper-base-al-baqarah.zip` | Downloadable zip |
| `/kaggle/working/checkpoint{step}.zip` | Auto-zipped each `save_steps` |
| `/kaggle/working/external_eval_*.json` | Per-file WER + mistake-detection report (if you added a test dataset) |
| `/kaggle/output/*.zip` | Persisted copies (Save Version) |

Each checkpoint triggers **clickable `FileLink` downloads** in the notebook via `AutoDownloadCheckpoint` (adapted from a teammate's Kaggle BERT-training script that zips checkpoints on `on_save` and displays a `FileLink`).

## Training scope & strategy

- **Riwayah (qira'a):** Hafs 'an 'Asim (حفص عن عاصم)
- **Surah:** 2 (Al-Baqarah) — all 286 ayahs, single reciter (EveryAyah)
- **LoRA** on the Tarteel base (trainable ~1–2% of weights) — keeps the run fast and reduces overfitting risk on a small, single-surah dataset
- **Epoch budget: up to 60**, but `load_best_model_at_end=True` (metric = WER) + `EarlyStoppingCallback` (patience = 8 evals) mean training stops automatically once the held-out WER stops improving — "as many epochs as possible" without babysitting or memorizing the 286 ayahs
- **Harakat preserved:** labels come from AlQuran Cloud's `ar.uthmani` text (full tashkeel), never normalized/stripped during training
- Dual-GPU DDP via `accelerate launch`

## After Kaggle

1. Download `qurany-whisper-base-al-baqarah.zip`.
2. Extract into `backend/models/qurany-whisper-base-al-baqarah/` (i.e. `backend/models/qurany-whisper-base-al-baqarah/config.json`, `model.safetensors`, etc. should exist at that path).
3. In `backend/.env` (or environment), set:
   ```
   ASR_BACKEND=transformers
   CUSTOM_MODEL_PATH=./models/qurany-whisper-base-al-baqarah
   ```
   The backend's `asr_service.py` will load it via `transformers` instead of `faster-whisper` (see `backend/README.md` for details). `SUPPORTED_SURAHS` already includes `2` so `/api/v1/analyze?surah_number=2` works against it.

## Smoke test (local, 20 clips)

```bash
cd backend/training/kaggle
pip install transformers datasets peft accelerate jiwer soundfile librosa pandas torch
python qurany_whisper_finetune_hafs_an_asim.py --smoke-test
```
