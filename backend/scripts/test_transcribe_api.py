#!/usr/bin/env python3
"""POST a local audio file to the running /api/v1/transcribe endpoint."""
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

audio_path = Path(sys.argv[1] if len(sys.argv) > 1 else "test_sample.mp3")
if not audio_path.is_file():
    raise SystemExit(f"Audio not found: {audio_path}")

boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
audio = audio_path.read_bytes()
body = (
    f"--{boundary}\r\n"
    f'Content-Disposition: form-data; name="file"; filename="{audio_path.name}"\r\n'
    f"Content-Type: audio/mpeg\r\n\r\n"
).encode("utf-8") + audio + f"\r\n--{boundary}--\r\n".encode("utf-8")

req = urllib.request.Request(
    "http://127.0.0.1:8000/api/v1/transcribe",
    data=body,
    headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    method="POST",
)

with urllib.request.urlopen(req, timeout=120) as resp:
    data = json.loads(resp.read().decode("utf-8"))

print(json.dumps(data, ensure_ascii=False, indent=2))
