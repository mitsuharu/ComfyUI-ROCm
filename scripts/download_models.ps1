<#
.SYNOPSIS
  Download the MiniMax H3 model weights ComfyUI needs (native int8_convrot
  quantization — NOT the default NVFP4 text encoder, NOT GGUF; see SETUP.md
  for why). Safe to re-run: uses curl's resume support, so an interrupted
  download continues instead of restarting from zero.

.PARAMETER ComfyUIPath
  Path to the ComfyUI checkout. Defaults to ..\ComfyUI relative to this script.

.PARAMETER IncludeReferenceToVideo
  Also download the ref2va UNet variant (needed for MiniMaxH3ReferenceToVideo /
  image+video reference conditioning). Off by default since most use is plain
  text-to-video and it's another ~20GB.

.EXAMPLE
  .\download_models.ps1
  .\download_models.ps1 -IncludeReferenceToVideo
#>
param(
    [string]$ComfyUIPath = (Join-Path $PSScriptRoot "..\ComfyUI"),
    [switch]$IncludeReferenceToVideo
)

$ErrorActionPreference = "Stop"
$ModelsPath = Join-Path $ComfyUIPath "models"

$files = @(
    @{ Dir = "diffusion_models"; Name = "minimax_h3_fl2va_pruned_int8_convrot.safetensors";
       Url = "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors" },
    @{ Dir = "text_encoders"; Name = "qwen3vl_32b_minimax_h3_int8_convrot.safetensors";
       Url = "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors" },
    @{ Dir = "vae"; Name = "minimax_h3_video_vae_fp16.safetensors";
       Url = "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors" },
    @{ Dir = "vae"; Name = "minimax_h3_audio_vae_fp32.safetensors";
       Url = "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors" }
)

if ($IncludeReferenceToVideo) {
    $files += @{ Dir = "diffusion_models"; Name = "minimax_h3_ref2va_pruned_int8_convrot.safetensors";
        Url = "https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" }
}

Write-Host "Models will be placed under: $ModelsPath" -ForegroundColor Cyan
Write-Host "Total download size is roughly 50GB (70GB with -IncludeReferenceToVideo). This will take a while." -ForegroundColor Yellow

foreach ($f in $files) {
    $dir = Join-Path $ModelsPath $f.Dir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dest = Join-Path $dir $f.Name

    Write-Host "`n--- $($f.Name) ---" -ForegroundColor Cyan
    if (Test-Path $dest) {
        Write-Host "Already exists, will resume/verify with curl -C -." -ForegroundColor DarkGray
    }

    # -C - resumes a partial download instead of restarting (this setup hit a
    # dropped connection partway through a 20GB file once; without resume that
    # means re-downloading everything from zero).
    & curl.exe -L -C - -o $dest $f.Url
    if ($LASTEXITCODE -ne 0) {
        Write-Host "curl exited with code $LASTEXITCODE for $($f.Name). Re-run this script to resume." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "`nAll model files downloaded." -ForegroundColor Green
