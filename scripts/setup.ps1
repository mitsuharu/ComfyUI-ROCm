<#
.SYNOPSIS
  End-to-end setup for ComfyUI + ROCm + MiniMax H3 on a Windows/Radeon machine.
  Run this from a fresh checkout of this repo. See ../SETUP.md for the
  reasoning behind each step and for troubleshooting if something here fails
  partway through (every step is safe to re-run).

.PARAMETER RocmVersion
  ROCm release to install from repo.radeon.com. Check
  https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/windows/install-pytorch.html
  for the current version and required graphics driver before changing this.

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
    [string]$RocmVersion = "7.2.1",
    [switch]$SkipModels,
    [switch]$IncludeReferenceToVideo
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

Write-Host "=== 1/5: Python venv ===" -ForegroundColor Cyan
if (-not (Test-Path ".venv")) {
    py -3.12 -m venv .venv
} else {
    Write-Host ".venv already exists, reusing it." -ForegroundColor DarkGray
}
$Py = Join-Path $Root ".venv\Scripts\python.exe"
& $Py -m pip install --upgrade pip

Write-Host "`n=== 2/5: ROCm SDK $RocmVersion ===" -ForegroundColor Cyan
$RocmBase = "https://repo.radeon.com/rocm/windows/rocm-rel-$RocmVersion"
& $Py -m pip install --no-cache-dir `
    "$RocmBase/rocm_sdk_core-$RocmVersion-py3-none-win_amd64.whl" `
    "$RocmBase/rocm_sdk_devel-$RocmVersion-py3-none-win_amd64.whl" `
    "$RocmBase/rocm_sdk_libraries_custom-$RocmVersion-py3-none-win_amd64.whl" `
    "$RocmBase/rocm-$RocmVersion.tar.gz"

Write-Host "`n=== 3/5: ComfyUI checkout + dependencies ===" -ForegroundColor Cyan
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

Write-Host "`n=== 4/5: ROCm PyTorch (installed last on purpose — step 3's requirements.txt pulls in generic torch as a dependency, and this overwrites it with the ROCm build) ===" -ForegroundColor Cyan
& $Py -m pip install --no-cache-dir `
    "$RocmBase/torch-2.9.1%2Brocm$RocmVersion-cp312-cp312-win_amd64.whl" `
    "$RocmBase/torchaudio-2.9.1%2Brocm$RocmVersion-cp312-cp312-win_amd64.whl" `
    "$RocmBase/torchvision-0.24.1%2Brocm$RocmVersion-cp312-cp312-win_amd64.whl"

Write-Host "`nVerifying GPU detection:" -ForegroundColor Cyan
& $Py -c "import torch; print(f'torch {torch.__version__}, ROCm available: {torch.cuda.is_available()}, GPUs: {torch.cuda.device_count()}')"

if ($SkipModels) {
    Write-Host "`n=== 5/5: Models skipped (-SkipModels) ===" -ForegroundColor Yellow
} else {
    Write-Host "`n=== 5/5: Model weights (~50GB, this is the slow part) ===" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "download_models.ps1") -IncludeReferenceToVideo:$IncludeReferenceToVideo
}

Write-Host "`nSetup complete. Start ComfyUI with:" -ForegroundColor Green
Write-Host "  .venv\Scripts\python.exe ComfyUI\main.py" -ForegroundColor Green
Write-Host "then open http://localhost:8188 — check the log for 'Device: cuda:N ... : native' to confirm GPU detection." -ForegroundColor Green
