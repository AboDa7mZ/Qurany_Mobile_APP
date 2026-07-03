#!/usr/bin/env python3
"""Local per-ayah WER benchmark for a fine-tuned Al-Baqarah Whisper model
(either riwayah — Hafs 'an 'Asim or Al-Bazzi 'an Ibn Kathir).

Downloads are NOT required if you already have manifest.csv + audio from a
prior Kaggle run. For a quick check without a manifest, pass a single
recording via --audio and optional --start-ayah/--end-ayah.

Examples:
  python training/eval_per_ayah.py --model ./models/qurany-whisper-base-al-baqarah
  python training/eval_per_ayah.py --model ./models/qurany-whisper-base-al-baqarah \\
      --audio ./my_clip.mp3 --start-ayah 197 --end-ayah 201
  python training/eval_per_ayah.py --model ./models/qurany-whisper-base-al-baqarah-bazzi \\
      --manifest ./quran_data_bazzi/manifest.csv --riwayah bazzi
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND / "training" / "kaggle"))
sys.path.insert(0, str(BACKEND))

from src.services.analysis_service import analyze_text  # noqa: E402
from src.services.asr_service import asr_service  # noqa: E402


def _eval_clip(model_path: str, audio: Path, start_ayah: int | None, end_ayah: int | None) -> dict:
    import os

    os.environ.setdefault("ASR_BACKEND", "transformers")
    os.environ.setdefault("CUSTOM_MODEL_PATH", model_path)
    from src.config import get_settings

    get_settings.cache_clear()
    asr_service._backend = None  # force reload with new env

    from src.services.analysis_service import analyze_audio

    return analyze_audio(
        2,
        str(audio),
        start_ayah=start_ayah,
        end_ayah=end_ayah,
        auto_detect_ayah_range=start_ayah is None,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate Al-Baqarah ASR locally")
    parser.add_argument(
        "--model",
        default=str(BACKEND / "models" / "qurany-whisper-base-al-baqarah"),
        help="Path to merged HuggingFace checkpoint",
    )
    parser.add_argument("--manifest", type=Path, help="manifest.csv from Kaggle download")
    parser.add_argument("--limit", type=int, default=29, help="Max held-out ayahs to score")
    parser.add_argument("--audio", type=Path, help="Single clip to transcribe + align")
    parser.add_argument("--start-ayah", type=int)
    parser.add_argument("--end-ayah", type=int)
    parser.add_argument(
        "--riwayah",
        choices=["hafs", "bazzi"],
        default="hafs",
        help="Which training script's TrainConfig/run_per_ayah_evaluation to use "
        "for the --manifest path (default: hafs)",
    )
    args = parser.parse_args()

    if args.audio:
        report = _eval_clip(args.model, args.audio, args.start_ayah, args.end_ayah)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return

    if args.manifest is None:
        print("Provide --manifest (Kaggle manifest.csv) or --audio for a single clip.")
        sys.exit(1)

    module_name = (
        "qurany_whisper_finetune_bazzi_an_ibn_kathir"
        if args.riwayah == "bazzi"
        else "qurany_whisper_finetune_hafs_an_asim"
    )
    train_config_module = __import__(module_name, fromlist=["TrainConfig", "run_per_ayah_evaluation"])
    TrainConfig = train_config_module.TrainConfig
    run_per_ayah_evaluation = train_config_module.run_per_ayah_evaluation
    from transformers import WhisperForConditionalGeneration, WhisperProcessor
    import torch

    cfg = TrainConfig(data_dir=args.manifest.parent)
    processor = WhisperProcessor.from_pretrained(args.model, language="ar", task="transcribe")
    model = WhisperForConditionalGeneration.from_pretrained(args.model)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model.to(device)
    run_per_ayah_evaluation(cfg, model, processor)


if __name__ == "__main__":
    main()
