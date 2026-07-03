# Qurany Whisper fine-tunes (Kaggle) — Surah Al-Baqarah

This folder holds one self-contained Kaggle training pipeline per riwayah (qira'a). Both fine-tune [tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) with LoRA on Surah 2 (Al-Baqarah), keep full tashkeel/harakat in the labels, and export a Qurany-branded model — they only differ in riwayah and how the per-ayah audio is sourced.

| Riwayah | Notebook | Script | README |
|---|---|---|---|
| Hafs 'an 'Asim (حفص عن عاصم) | `Qurany_Whisper_Finetune_حفص_عن_عاصم.ipynb` | `qurany_whisper_finetune_hafs_an_asim.py` | [README_HafsAnAsim.md](./README_HafsAnAsim.md) |
| Al-Bazzi 'an Ibn Kathir (البزي عن ابن كثير) | `Qurany_Whisper_Finetune_البزي_عن_ابن_كثير.ipynb` | `qurany_whisper_finetune_bazzi_an_ibn_kathir.py` | [README_BazziAnIbnKathir.md](./README_BazziAnIbnKathir.md) |

**Start with the README matching the model you want to train** — each is fully self-contained (Kaggle setup, required "Add Data" datasets, cell-by-cell run instructions, output paths, and how to wire the result into `backend/.env` afterward).

## Why two separate pipelines instead of one parameterized script

Hafs 'an 'Asim has a ready-made per-ayah audio archive (EveryAyah.com) with matching Uthmani text (AlQuran Cloud API); Bazzi 'an Ibn Kathir has neither, so its script instead auto-segments a single user-supplied full-surah recording via ASR-based forced alignment against **your** canonical Bazzi text (`Al-Baqarah_Bazzi.txt`; Bazzi numbering, ~285 ayahs — see `README_BazziAnIbnKathir.md`). Keeping them as two scripts avoids a tangle of `if riwayah == ...` branches in the one part of the pipeline (data acquisition) that's genuinely different, while the training loop, evaluation, and model-card code are intentionally kept identical between the two files.

## Training text reference

- `training data/Al-Baqarah.txt` — canonical Hafs Uthmani text (286 ayahs).
- **Bazzi:** supply your own `Al-Baqarah_Bazzi.txt` (e.g. `training data2/Al-Baqarah_Bazzi.txt` in this repo). Do not use the old auto-generated file under `training data/` — it used Hafs ayah boundaries.
