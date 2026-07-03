"""Dedicated executor for CPU-heavy inference so lightweight routes stay responsive."""
from __future__ import annotations

import asyncio
from concurrent.futures import ThreadPoolExecutor
from typing import Callable, TypeVar

T = TypeVar("T")

# One analyze/transcribe at a time keeps RAM predictable on laptops; health/docs
# stay on the async event loop and are not queued behind this pool.
_inference_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="qurany-inference")


async def run_inference(func: Callable[..., T], /, *args, **kwargs) -> T:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(
        _inference_executor,
        lambda: func(*args, **kwargs),
    )
