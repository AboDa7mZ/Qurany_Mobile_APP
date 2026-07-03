"""Shared audio loading for asr.py and align.py.

Decodes via soundfile (libsndfile >=1.1 reads MP3 natively) instead of
letting each model library shell out to ffmpeg, since ffmpeg isn't
guaranteed to be on PATH (it isn't on a bare Kaggle/Windows Python install).
"""

from __future__ import annotations

import numpy as np
import soundfile as sf
from scipy import signal

TARGET_SR = 16000


def load_audio(path: str, target_sr: int = TARGET_SR) -> tuple[np.ndarray, int]:
    """Return (mono float32 waveform, sample_rate), resampled to target_sr."""
    data, sr = sf.read(path, always_2d=False)
    if data.ndim > 1:
        data = data.mean(axis=1)
    data = data.astype(np.float32)
    if sr != target_sr:
        num_samples = round(len(data) * target_sr / sr)
        data = signal.resample(data, num_samples).astype(np.float32)
        sr = target_sr
    return data, sr
