# Install backend deps into backend/.venv on B: (avoids filling C: drive).
# Run from repo root or backend/:  .\scripts\install-deps.ps1

$ErrorActionPreference = "Stop"
$Backend = Split-Path $PSScriptRoot -Parent
$VenvPip = Join-Path $Backend ".venv\Scripts\pip.exe"

if (-not (Test-Path $VenvPip)) {
    Write-Error "Create venv first: cd backend; python -m venv .venv"
}

$env:PIP_CACHE_DIR = Join-Path $Backend ".pip-cache"
$env:TEMP = Join-Path $Backend ".tmp"
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:PIP_CACHE_DIR, $env:TEMP | Out-Null

Write-Host "Installing core requirements..."
& $VenvPip install -r (Join-Path $Backend "requirements.txt")

Write-Host "Installing CPU PyTorch (smaller than CUDA build)..."
& $VenvPip install torch --index-url https://download.pytorch.org/whl/cpu

Write-Host "Installing transformers stack..."
& $VenvPip install -r (Join-Path $Backend "requirements-transformers.txt")

Write-Host "Done. Activate: backend\.venv\Scripts\Activate.ps1"
