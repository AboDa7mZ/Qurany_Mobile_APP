"""Tests for thread-safe ASR model loading."""
from __future__ import annotations

import threading
from unittest.mock import MagicMock, patch

import torch

from src.services.asr_service import (
    ASRService,
    compute_whisper_max_new_tokens,
    faster_whisper_load_candidates,
    resolve_torch_device,
    truncate_whisper_prompt_ids,
)


def test_compute_whisper_max_new_tokens_without_prompt():
    assert compute_whisper_max_new_tokens(448, 4) == 256


def test_compute_whisper_max_new_tokens_with_long_prompt():
    # 181-token decoder prefix budget leaves 267 tokens for generation.
    assert compute_whisper_max_new_tokens(448, 181) == 256
    assert compute_whisper_max_new_tokens(448, 181, desired_max_new_tokens=400) == 267


def test_truncate_whisper_prompt_ids_keeps_tail():
    prompt_ids = torch.tensor([[1, 2, 3, 4, 5]])
    truncated = truncate_whisper_prompt_ids(prompt_ids, 3)
    assert truncated is not None
    assert truncated.tolist() == [[3, 4, 5]]


def test_faster_whisper_load_candidates_cpu_only():
    assert faster_whisper_load_candidates("cpu", "int8") == [("cpu", "int8")]


def test_faster_whisper_load_candidates_auto_falls_back_to_cpu():
    assert faster_whisper_load_candidates("auto", "float16") == [
        ("cuda", "float16"),
        ("cpu", "int8"),
    ]


def test_resolve_torch_device_forces_cpu():
    with patch("src.services.asr_service.cuda_runtime_usable", return_value=False):
        assert resolve_torch_device("auto") == "cpu"
        assert resolve_torch_device("cuda") == "cpu"
        assert resolve_torch_device("cpu") == "cpu"


def test_concurrent_load_instantiates_model_once():
    service = ASRService()
    mock_whisper = MagicMock()
    barrier = threading.Barrier(8)

    def load_model() -> None:
        barrier.wait()
        service.load()

    with patch("src.services.asr_service.settings.asr_backend", "faster_whisper"), patch(
        "faster_whisper.WhisperModel", mock_whisper
    ):
        threads = [threading.Thread(target=load_model) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

    assert mock_whisper.call_count == 1
    assert service.is_loaded


def test_load_is_idempotent_after_first_load():
    service = ASRService()
    mock_whisper = MagicMock()

    with patch("src.services.asr_service.settings.asr_backend", "faster_whisper"), patch(
        "faster_whisper.WhisperModel", mock_whisper
    ):
        service.load()
        service.load()
        service.load()

    assert mock_whisper.call_count == 1
