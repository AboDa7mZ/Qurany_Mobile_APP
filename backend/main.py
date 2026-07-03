"""Root entry point. Run with: python main.py  (or: uvicorn src.main:app)."""
from __future__ import annotations

import uvicorn

from src.config import settings

if __name__ == "__main__":
    # Auto-reload watches the whole backend tree (including large model files)
    # and can restart mid-inference, leaving the browser spinning. Disable it
    # for the heavy transformers backend unless explicitly re-enabled.
    use_reload = settings.uvicorn_reload and (
        settings.asr_backend != "transformers" or settings.uvicorn_reload_with_transformers
    )
    uvicorn.run(
        "src.main:app",
        host=settings.host,
        port=settings.port,
        reload=use_reload,
        reload_excludes=[
            "models/*",
            "data/*",
            "*.safetensors",
            "*.bin",
            "*.pt",
            "*.pth",
            "__pycache__/*",
            ".pytest_cache/*",
        ],
    )
