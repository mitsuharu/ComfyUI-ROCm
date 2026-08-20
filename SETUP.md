# ComfyUI + ROCm + MiniMax H3 セットアップ手順(Windows / Radeon)

Windows 11 + AMD Radeon GPU(ROCm対応機種)で、ComfyUIを使いローカルでMiniMax H3(Hailuo 3.0、33Bパラメータのオムニモーダル動画+音声生成モデル)を動かすための手順です。

検証環境: Windows 11, Python 3.12, ROCm 7.2.1, PyTorch 2.9.1+rocm7.2.1

- AMD Radeon AI PRO R9700 (32GB) x2 — 主開発機
- AMD Radeon RX 9060 XT (16GB) — 別マシンで動作確認済み。VRAMが少ない分ComfyUIが自動でオフロードを増やすため、同じ生成(1344x768・約5秒・20steps)でR9700が約5分のところ、RX 9060 XTでは約15分かかった(約3倍)

このリポジトリには**モデル本体やComfyUI本体は含まれていません**(合計100GB近くになり、かつ`git clone`/公式配布から再取得できるため)。含まれているのは、それらを正しい組み合わせで揃えるための手順・スクリプトと、動画生成用の設定一式です。リポジトリ全体の構成は [README.md](README.md) を参照してください。

## 0. 前提条件

- Windows 11
- 対応するAMD Radeon GPU(gfx110X / gfx120X系。例: RX 7900XTX, RX 9070XT, Radeon AI PRO R9700 等)
- 最新のAMD Adrenalinドライバ
- Python 3.12(64bit)がインストール済みで `py -3.12` が使えること
- ディスク空き容量 約60GB以上(モデル一式で約52GB)
- git

## 1. クイックスタート(推奨)

```powershell
git clone <このリポジトリのURL> ComfyUI-ROCm
cd ComfyUI-ROCm
.\scripts\setup.ps1
```

`scripts/setup.ps1` が以下を順番に行う(すべて再実行しても安全):
1. venv作成(`.venv`)
2. ROCm SDKのインストール
3. ComfyUI本体のクローンと依存関係インストール
4. ComfyUI-Managerのクローン
5. ROCm版PyTorchのインストール(最後に実行するのが重要。理由は下記「なぜこの順番か」参照)
6. モデル一式のダウンロード(`scripts/download_models.ps1` を内部で呼ぶ)

モデルのダウンロードだけ後回しにしたい場合は `.\scripts\setup.ps1 -SkipModels`、Reference to Video用のモデルも欲しい場合は `.\scripts\setup.ps1 -IncludeReferenceToVideo` を指定する。

途中で失敗しても(特にモデルダウンロードは50GBあるので回線切れが起きやすい)、同じコマンドを再実行すれば途中から再開される。モデルだけ個別に再取得したい場合は `.\scripts\download_models.ps1` を単独で実行してもよい。

完了したら「4. 起動」に進む。以降の章は「クイックスタートの中で何が起きているか」を知りたい場合や、手動でトラブルシューティングしたい場合の詳細。

## 2. 手動セットアップの詳細(参考)

### 2-1. venv作成とROCm本体のインストール

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip

# ROCm SDK (7.2.1) をインストール
.\.venv\Scripts\python.exe -m pip install --no-cache-dir `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_core-7.2.1-py3-none-win_amd64.whl `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_devel-7.2.1-py3-none-win_amd64.whl `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm_sdk_libraries_custom-7.2.1-py3-none-win_amd64.whl `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/rocm-7.2.1.tar.gz
```

バージョンは更新される可能性があるので、最新版は [AMD ROCm公式ドキュメント](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/windows/install-pytorch.html) を確認してください。GPUによって必要なグラフィックドライバのバージョンが指定されているので合わせて確認を。

### 2-2. ComfyUI本体のセットアップ

```powershell
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI
..\.venv\Scripts\python.exe -m pip install -r requirements.txt
cd ..
```

**なぜこの順番か**: `requirements.txt` の中に汎用版(CPU/CUDA向け)の `torch` が依存として含まれているため、このインストールで一旦ROCm版torchが上書きされる。次のステップ(2-4)で必ず上書きし直すこと。また2つのpipインストールを同時並行で走らせない(同一venvへの同時書き込みで壊れることがある。実際にROCm SDKインストールと`requirements.txt`インストールを並行実行して壊れた)。

### 2-3. カスタムノード(任意)

ComfyUI-Managerはあると便利(ノード管理UI)。**ComfyUI-GGUFはMiniMax H3では現状使えない(下記「GGUFについて」参照)ので、この用途では不要**。

```powershell
cd ComfyUI\custom_nodes
git clone https://github.com/Comfy-Org/ComfyUI-Manager.git
cd ComfyUI-Manager
..\..\..\.venv\Scripts\python.exe -m pip install -r requirements.txt
cd ..\..\..
```

### 2-4. ROCm版PyTorchのインストール(最後に実行、これが重要)

```powershell
.\.venv\Scripts\python.exe -m pip install --no-cache-dir `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torch-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchaudio-2.9.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl `
    https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/torchvision-0.24.1%2Brocm7.2.1-cp312-cp312-win_amd64.whl
```

確認:
```powershell
.\.venv\Scripts\python.exe -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.device_count())"
```
`2.9.1+rocm7.2.1 True <GPU枚数>` のように出ればOK。

### 2-5. モデルのダウンロード

**GGUFについて**: MiniMax H3のコミュニティ製GGUF量子化版(unsloth等)は、2026年8月時点で `ComfyUI-GGUF` カスタムノードのアーキテクチャ自動検出が対応しておらず、UNet・テキストエンコーダーともに読み込み時にエラーになる(`Unknown model architecture!` / `This gguf file is incompatible with llama.cpp!`)。**GGUF版は使わないこと。**

**NVFP4について**: 公式デフォルトのテキストエンコーダー(`qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`)はNVIDIA専用の量子化フォーマットで、ROCm(HIP)バックエンドでは動かない。**必ずint8_convrot版を使うこと。**

以下のnative量子化版(int8_convrot、ROCmのHIPバックエンドで正式サポート)が必要。`scripts/download_models.ps1` が resume 対応(`curl -C -`)でこれらを取得する(回線が不安定でも再実行すれば途中から再開する):

| 配置先 | ファイル | サイズ |
|---|---|---|
| `ComfyUI/models/diffusion_models/` | `minimax_h3_fl2va_pruned_int8_convrot.safetensors` | 約19.5GB |
| `ComfyUI/models/text_encoders/` | `qwen3vl_32b_minimax_h3_int8_convrot.safetensors` | 約25.3GB |
| `ComfyUI/models/vae/` | `minimax_h3_video_vae_fp16.safetensors` | 約4.9GB |
| `ComfyUI/models/vae/` | `minimax_h3_audio_vae_fp32.safetensors` | 約0.6GB |

参照画像/動画から生成したい場合(Reference to Video)は `minimax_h3_ref2va_pruned_int8_convrot.safetensors`(diffusion_models、約19.5GB)も追加で必要 (`download_models.ps1 -IncludeReferenceToVideo`)。

合計モデルサイズ: 約50GB(Reference to Video込みで約70GB)。ダウンロード元はいずれも https://huggingface.co/Comfy-Org/MiniMax-H3 。

## 3. 起動

```powershell
.\.venv\Scripts\python.exe ComfyUI\main.py
```

ログに以下が出ればGPU認識成功:
```
AMD arch: gfx1201            <- GPUのアーキテクチャコード
Device: cuda:0 AMD Radeon ... : native
Using pytorch attention
```
ブラウザで `http://localhost:8188` を開く。

## 4. 既知の問題

- **長時間生成中にサーバーが突然落ちることがある**(このセットアップの構築中に複数回発生)。原因未特定だが、Windows上のROCmスタックはまだ発展途上("the entire ROCm stack is not yet supported on Windows" と公式ドキュメントにも記載あり)であり、長時間のGPUカーネル実行に対するドライバ側のタイムアウト(TDR)が疑わしい。`.claude/skills/minimax-h3-video/scripts/generate_video.py` はこれを検知して自動でサーバーを再起動し、同じジョブを再投入する(ただし「サーバーがモデル読み込みで一時的に無応答なだけ」を誤って「クラッシュした」と判定しないよう、タイムアウトは長め・複数回確認してから再起動する作りにしてある)。手動でAPIを叩く場合も同様の考慮が要る。
- pip installを同一venvに対して並行実行すると壊れることがある。順番に実行すること(`scripts/setup.ps1` は直列に実行する)。

## 5. 生成方法

Claude Codeでこのリポジトリを開いている場合は `.claude/skills/minimax-h3-video/` が自動で使えるので、「〜な動画を作って」と頼むだけでよい。手動でAPIを直接叩く方法や、解像度/長さの目安、プロンプトのコツは [generate_video.md](generate_video.md) を参照。`examples/` に実際に生成できたワークフロー例(アニメ調・実写風)がある。
