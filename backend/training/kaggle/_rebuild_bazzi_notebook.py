"""Regenerate Qurany_Whisper_Finetune_البزي_عن_ابن_كثير.ipynb from the .py script."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
py_lines = (HERE / "qurany_whisper_finetune_bazzi_an_ibn_kathir.py").read_text(encoding="utf-8").splitlines()

markdown = """# Qurany Whisper fine-tune (Kaggle) — Surah Al-Baqarah (Al-Bazzi 'an Ibn Kathir / البزي عن ابن كثير)

Fine-tunes [tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) on **Surah 2 (Al-Baqarah)** in riwayah **Al-Bazzi 'an Ibn Kathir** (~**285 Bazzi-numbered ayahs**; ayah 1 merges Hafs 1+2), with LoRA, full **tashkeel/harakat** labels, exporting **`qurany-whisper-base-al-baqarah-bazzi`**.

**Kaggle settings:** Internet ON · **GPU T4 x 1** (or x2 with `NUM_GPUS = 2` in the training cell)

**Setup — attach your dataset via Add Data before Cell 5:**
- `Al-Baqarah_Bazzi.txt` (your canonical Bazzi text)
- **One full** Al-Baqarah recitation (longest `.mp3`/`.wav` is auto-selected; ~150 MB)
- *(optional)* short clips for external eval only

Files can live in a subfolder (e.g. `training data2/`); Cell 5 auto-finds the text file under `/kaggle/input/`.

Run cells **top to bottom**. Check segmentation output for **285 ayahs** before training."""

data_cell = '''from pathlib import Path
from qurany_whisper_finetune_bazzi_an_ibn_kathir import (
    TrainConfig, download_training_data, prepare_and_cache_dataset, warm_hf_model_cache,
)

def find_bazzi_data_dir() -> Path:
    """Locate Al-Baqarah_Bazzi.txt anywhere under /kaggle/input (handles datasets/.../subfolders)."""
    root = Path("/kaggle/input")
    for name in ("Al-Baqarah_Bazzi.txt", "Al-Baqarah.txt"):
        for hit in root.rglob(name):
            return hit.parent
    raise FileNotFoundError(
        "Al-Baqarah_Bazzi.txt not found. Add your dataset via Add Data, then restart the session."
    )

!ls -la /kaggle/input/
DATA = find_bazzi_data_dir()
print("Using:", DATA)
!ls -lh "{DATA}"

cfg = TrainConfig()
cfg.bazzi_input_dir = DATA
cfg.external_test_dir = DATA

manifest = download_training_data(cfg)  # ~10-20 min: segments full recitation into 285 clips
warm_hf_model_cache()
processed_dir = prepare_and_cache_dataset(cfg)
print("ready:", processed_dir)
'''

cells = [
    {"cell_type": "markdown", "metadata": {}, "source": [markdown]},
    {
        "cell_type": "code",
        "metadata": {},
        "source": [
            "!pip install -q transformers datasets peft accelerate jiwer soundfile librosa torchaudio\n",
            "!pip uninstall -y -q torchao\n",
        ],
        "outputs": [],
        "execution_count": None,
    },
    {
        "cell_type": "code",
        "metadata": {},
        "source": ["%%writefile /kaggle/working/qurany_whisper_finetune_bazzi_an_ibn_kathir.py\n"]
        + [line + "\n" for line in py_lines],
        "outputs": [],
        "execution_count": None,
    },
    {
        "cell_type": "code",
        "metadata": {},
        "source": [
            "import sys\n",
            'sys.path.insert(0, "/kaggle/working")\n',
            "from qurany_whisper_finetune_bazzi_an_ibn_kathir import TrainConfig, download_training_data, prepare_and_cache_dataset, warm_hf_model_cache\n",
            "!nvidia-smi -L\n",
        ],
        "outputs": [],
        "execution_count": None,
    },
    {
        "cell_type": "code",
        "metadata": {},
        "source": [line + "\n" for line in data_cell.splitlines()],
        "outputs": [],
        "execution_count": None,
    },
    {
        "cell_type": "code",
        "metadata": {},
        "source": [
            "import subprocess, sys\n",
            "NUM_GPUS = 1  # set to 2 if you enabled GPU T4 x2\n",
            'cmd = [sys.executable, "-m", "accelerate.commands.launch", "--num_processes", str(NUM_GPUS), "--mixed_precision", "fp16", "/kaggle/working/qurany_whisper_finetune_bazzi_an_ibn_kathir.py", "--kaggle-train"]\n',
            'print(" ".join(cmd)); subprocess.run(cmd, check=True)\n',
        ],
        "outputs": [],
        "execution_count": None,
    },
    {
        "cell_type": "code",
        "metadata": {},
        "source": [
            "import glob\n",
            "import json\n",
            "\n",
            'for path in sorted(glob.glob("/kaggle/working/external_eval_*.json")):\n',
            '    data = json.load(open(path, encoding="utf-8"))\n',
            '    print(f"\\n{path}")\n',
            "    print(\n",
            '        f"  similarity={data[\'similarity_score\']}%  "\n',
            '        f"matched={data[\'matched_words\']}/{data[\'total_words\']}  "\n',
            '        f"mistakes={data[\'mistakes\']}"\n',
            "    )\n",
        ],
        "outputs": [],
        "execution_count": None,
    },
]

nb = {
    "nbformat": 4,
    "nbformat_minor": 5,
    "metadata": {
        "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
        "language_info": {"name": "python", "version": "3.10.0"},
    },
    "cells": cells,
}

out = HERE / "Qurany_Whisper_Finetune_البزي_عن_ابن_كثير.ipynb"
out.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"Wrote {out.name} ({len(cells)} cells, {len(py_lines)} lines of Python)")
