<#
.SYNOPSIS
  End-to-end setup for ComfyUI + ROCm + MiniMax H3 on a Windows/Radeon machine.
  Run this from a fresh checkout of this repo. See ../SETUP.md for the
  reasoning behind each step and for troubleshooting if something here fails
  partway through (every step is safe to re-run).

.PARAMETER TorchVersion
  PyTorch version to pull from AMD's ROCm 10 index. The matching torchvision
  and torchaudio versions are pinned alongside it below; changing one without
  the others gives you a set PyTorch refuses to load.

.PARAMETER SkipModels
  Skip downloading model weights (~50GB). Use this if you just want the
  software stack, or if you already have the models from another install and
  will copy/symlink ComfyUI/models yourself.

.PARAMETER IncludeReferenceToVideo
  Passed through to download_models.ps1 — also fetch the ref2va UNet variant.

.EXAMPLE
  .\scripts\setup.ps1
  .\scripts\setup.ps1 -SkipModels
#>
param(
    [string]$TorchVersion = "2.13.0+rocm10.0.0",
    [string]$TorchvisionVersion = "0.28.0+rocm10.0.0",
    [string]$TorchaudioVersion = "2.11.0.2+rocm10.0.0",
    [switch]$SkipModels,
    [switch]$IncludeReferenceToVideo
)

# ROCm 10 moved to a proper pip index. Installing torch from here pulls the
# whole ROCm runtime (rocm-sdk-core, the per-architecture rocm-sdk-device-*
# kernels, and so on) in as dependencies, which is why this script no longer
# installs the ROCm SDK as a separate step the way the ROCm 7.2.1 setup did.
$RocmIndex = "https://stable.repo.amd.com/rocm/whl-next/"

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

Write-Host "=== 1/4: Python venv ===" -ForegroundColor Cyan
if (-not (Test-Path ".venv")) {
    py -3.12 -m venv .venv
} else {
    Write-Host ".venv already exists, reusing it." -ForegroundColor DarkGray
}
$Py = Join-Path $Root ".venv\Scripts\python.exe"
& $Py -m pip install --upgrade pip

Write-Host "`n=== 2/4: ROCm PyTorch (brings the ROCm runtime with it) ===" -ForegroundColor Cyan
# The [device-all] extra pulls the GPU-architecture kernel packages. Retries are
# generous because this pulls several GB and AMD's CDN has dropped connections
# mid-download here before; pip's cache lets an interrupted run resume.
& $Py -m pip install --retries 10 --timeout 60 `
    --index-url $RocmIndex `
    "torch[device-all]==$TorchVersion" `
    "torchvision[device-all]==$TorchvisionVersion" `
    "torchaudio==$TorchaudioVersion"

Write-Host "`n=== 3/4: ComfyUI checkout + dependencies ===" -ForegroundColor Cyan
if (-not (Test-Path "ComfyUI")) {
    git clone https://github.com/comfyanonymous/ComfyUI.git
} else {
    Write-Host "ComfyUI/ already exists, reusing it (run 'git pull' inside it yourself to update)." -ForegroundColor DarkGray
}
& $Py -m pip install -r "ComfyUI\requirements.txt"

$managerPath = "ComfyUI\custom_nodes\ComfyUI-Manager"
if (-not (Test-Path $managerPath)) {
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git $managerPath
    & $Py -m pip install -r "$managerPath\requirements.txt"
} else {
    Write-Host "ComfyUI-Manager already present." -ForegroundColor DarkGray
}

Write-Host "`nVerifying GPU detection:" -ForegroundColor Cyan
# ROCm 10's version string (e.g. 2.13.0+rocm10.0.0) satisfies ComfyUI's torch
# requirement, so step 3 leaves it alone. Under ROCm 7.2.1 it was replaced by a
# generic build and had to be reinstalled afterwards — check the version here
# rather than assuming that still holds after a ComfyUI upgrade.
& $Py -c "import torch; print(f'torch {torch.__version__}, ROCm available: {torch.cuda.is_available()}, GPUs: {torch.cuda.device_count()}')"

if ($SkipModels) {
    Write-Host "`n=== 4/4: Models skipped (-SkipModels) ===" -ForegroundColor Yellow
} else {
    Write-Host "`n=== 4/4: Model weights (~50GB, this is the slow part) ===" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "download_models.ps1") -IncludeReferenceToVideo:$IncludeReferenceToVideo
}

Write-Host "`nSetup complete. Start ComfyUI with:" -ForegroundColor Green
Write-Host "  .venv\Scripts\python.exe ComfyUI\main.py --disable-dynamic-vram" -ForegroundColor Green
Write-Host "then open http://localhost:8188 — check the log for 'Device: cuda:N ... : native' to confirm GPU detection." -ForegroundColor Green
Write-Host "`n--disable-dynamic-vram is required on ROCm 10: ComfyUI's dynamic VRAM loader" -ForegroundColor Yellow
Write-Host "fails with 'cuMemMap ... unspecified launch failure'. See SETUP.md." -ForegroundColor Yellow
