# ComfyUI + ROCm + MiniMax H3 セットアップ手順(Windows / Radeon)

Windows 11 + AMD Radeon GPU(ROCm対応機種)で、ComfyUIを使いローカルでMiniMax H3(Hailuo 3.0、33Bパラメータのオムニモーダル動画+音声生成モデル)を動かすための手順です。

検証環境: Windows 11, Python 3.12, ROCm 10.0.0, PyTorch 2.13.0+rocm10.0.0

- AMD Radeon AI PRO R9700 (32GB) x2 — 主開発機
- AMD Radeon RX 9060 XT (16GB) — 別マシンで動作確認済み(ROCm 7.2.1時点)。VRAMが少ない分ComfyUIが自動でオフロードを増やすため、同じ生成(1344x768・約5秒・20steps)でR9700が約5分のところ、RX 9060 XTでは約15分かかった(約3倍)

ROCm 7.2.1 でも動作するが、ROCm 10 の方が手順が簡潔になっている(下記「ROCm 7.2.1 からの変更点」参照)。

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
2. ROCm版PyTorchのインストール(ROCmランタイム一式が依存として付随する)
3. ComfyUI本体・ComfyUI-Managerのクローンと依存関係インストール
4. モデル一式のダウンロード(`scripts/download_models.ps1` を内部で呼ぶ)

モデルのダウンロードだけ後回しにしたい場合は `.\scripts\setup.ps1 -SkipModels`、Reference to Video用のモデルも欲しい場合は `.\scripts\setup.ps1 -IncludeReferenceToVideo` を指定する。

途中で失敗しても(特にモデルダウンロードは50GBあるので回線切れが起きやすい)、同じコマンドを再実行すれば途中から再開される。モデルだけ個別に再取得したい場合は `.\scripts\download_models.ps1` を単独で実行してもよい。

完了したら「4. 起動」に進む。以降の章は「クイックスタートの中で何が起きているか」を知りたい場合や、手動でトラブルシューティングしたい場合の詳細。

## 2. 手動セットアップの詳細(参考)

### 2-1. venv作成とROCm版PyTorchのインストール

ROCm 10 は独自のwheel URLを個別に指定する形式ではなく、**pipのインデックスとして公開されている**。`torch[device-all]` を入れると、ROCmランタイム(`rocm-sdk-core`、GPUアーキテクチャ別の `rocm-sdk-device-gfx*` など)が依存として一緒に入る。

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip

.\.venv\Scripts\python.exe -m pip install --retries 10 --timeout 60 `
    --index-url https://stable.repo.amd.com/rocm/whl-next/ `
    "torch[device-all]==2.13.0+rocm10.0.0" `
    "torchvision[device-all]==0.28.0+rocm10.0.0" `
    "torchaudio==2.11.0.2+rocm10.0.0"
```

`[device-all]` はGPUアーキテクチャ別のカーネルパッケージを取得するためのextras指定。数GBのダウンロードになり、AMD側のCDNで接続が切れることがあるため、リトライ回数を増やしてある(pipのキャッシュが効くので、中断しても再実行すれば途中から進む)。

torch / torchvision / torchaudio のバージョンは**セットで合わせる**こと。片方だけ変えるとPyTorchが読み込みを拒否する。最新版は [AMD ROCm公式ドキュメント](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/windows/install-pytorch.html) を確認。GPUによって必要なグラフィックドライバのバージョンが指定されているので合わせて確認を。

### 2-2. ComfyUI本体のセットアップ

```powershell
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI
..\.venv\Scripts\python.exe -m pip install -r requirements.txt
cd ..
```

**ROCm 10 ではtorchが上書きされない**: `requirements.txt` は汎用版(CPU/CUDA向け)の `torch` を依存に含むが、ROCm 10 のバージョン表記 `2.13.0+rocm10.0.0` がその要求を満たすため、pipは再インストールしない。ROCm 7.2.1 では上書きされてしまい、後からROCm版を入れ直す必要があった。

ただし ComfyUI 側の要求バージョンが上がると再び上書きされる可能性があるので、**この後で `torch.__version__` を必ず確認する**こと。

なお、2つのpipインストールを同時並行で走らせないこと(同一venvへの同時書き込みで壊れる。実際にROCm SDKインストールと`requirements.txt`インストールを並行実行して壊した)。

### 2-3. カスタムノード(任意)

ComfyUI-Managerはあると便利(ノード管理UI)。**ComfyUI-GGUFはMiniMax H3では現状使えない(下記「GGUFについて」参照)ので、この用途では不要**。

```powershell
cd ComfyUI\custom_nodes
git clone https://github.com/Comfy-Org/ComfyUI-Manager.git
cd ComfyUI-Manager
..\..\..\.venv\Scripts\python.exe -m pip install -r requirements.txt
cd ..\..\..
```

### 2-4. GPU認識の確認

```powershell
.\.venv\Scripts\python.exe -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.device_count())"
```
`2.13.0+rocm10.0.0 True <GPU枚数>` のように出ればOK。ここでバージョンから `+rocm10.0.0` が消えていたら、2-2 で汎用版に上書きされているので 2-1 のコマンドを再実行する。

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
.\.venv\Scripts\python.exe ComfyUI\main.py --disable-dynamic-vram
```

**`--disable-dynamic-vram` は ROCm 10 では必須**。理由は「既知の問題」の該当節を参照。

ログに以下が出ればGPU認識成功:
```
pytorch version: 2.13.0+rocm10.0.0
AMD arch: gfx1201            <- GPUのアーキテクチャコード
ROCm version: (7, 15)        <- HIPランタイムのバージョン。ROCm 10.0.0 では (7, 15) と表示される
Device: cuda:0 AMD Radeon ... : native
Using pytorch attention
```
ブラウザで `http://localhost:8188` を開く。

## 4. 既知の問題

- **長時間生成中にサーバーが突然落ちることがある**(このセットアップの構築中に複数回発生)。原因未特定だが、Windows上のROCmスタックはまだ発展途上("the entire ROCm stack is not yet supported on Windows" と公式ドキュメントにも記載あり)であり、長時間のGPUカーネル実行に対するドライバ側のタイムアウト(TDR)が疑わしい。`.claude/skills/minimax-h3-video/scripts/generate_video.py` はこれを検知して自動でサーバーを再起動し、同じジョブを再投入する(ただし「サーバーがモデル読み込みで一時的に無応答なだけ」を誤って「クラッシュした」と判定しないよう、タイムアウトは長め・複数回確認してから再起動する作りにしてある)。手動でAPIを叩く場合も同様の考慮が要る。
- pip installを同一venvに対して並行実行すると壊れることがある。順番に実行すること(`scripts/setup.ps1` は直列に実行する)。

### ROCm 10 では `--disable-dynamic-vram` が必要

ROCm 10 でオプションなしに起動すると、モデルのロード時に次のエラーで生成が失敗する:

```
aimdo: CUDA API FAILED (719): err = cuMemMap(vaddr, size, 0, h, 0): unspecified launch failure
aimdo: VRAM Allocation failed (non OOM)
!!! Exception during processing !!! CUDA error: unspecified launch failure  (hipErrorLaunchFailure)
```

ComfyUIの動的VRAMローディング(`comfy-aimdo`)が使う仮想メモリマッピング(`cuMemMap`)が、ROCm 10 のHIPランタイムで失敗している。ROCm 7.2.1 では発生しなかった。

`--disable-dynamic-vram` を付けて起動すると、従来どおりの推定ベースのモデルロードになり、正常に生成できる。VRAM 32GB の環境では実用上の問題は確認していないが、VRAMが少ない環境では動的ローディングが効かない分だけ不利になる可能性がある(未検証)。

### Smart App Control がネイティブバイナリをブロックする

Windows 11の**スマート アプリ コントロール(Smart App Control)**が有効な環境では、PyPIやAMDのリポジトリから入れた署名なしバイナリのロードが拒否される。**ROCm 10 ではこれが致命的**で、`torch/lib/dl.dll` がブロックされるため **torchのimport自体ができない**:

```
OSError: [WinError 4551] アプリケーションコントロールポリシーによってこのファイルがブロックされました。
Error loading "...\.venv\Lib\site-packages\torch\lib\dl.dll" or one of its dependencies.
```

ROCm 7.2.1 では影響が軽く、ブロック対象は `torchvision/_C.pyd` で、かつ**毎回再現しなかった**(ブロックされた直後の起動が成功する例も確認)。実際に発生した際のWindowsイベントログ(`Microsoft-Windows-CodeIntegrity/Operational`、イベントID 3077/3033)には次のように記録されていた:

```
Code Integrity determined that a process (python.exe) attempted to load
...\.venv\Lib\site-packages\torchvision\_C.pyd
that did not meet the Enterprise signing level requirements
```

```
Code Integrity determined that a process (python.exe) attempted to load
...\.venv\Lib\site-packages\torch\lib\dl.dll
that did not meet the Enterprise signing level requirements
```

ROCm 7.2.1 の場合は `RuntimeError: operator torchvision::nms does not exist` として現れる。MiniMax H3のサンプリング自体はtorchvisionを使わないが、ComfyUIが起動時に `comfy/ldm/cosmos/model.py` 経由で `torchvision.transforms` をimportするため、起動そのものができなくなる。AMDの公式ドキュメントにも「Smart App Controlが有効な場合ComfyUIが起動しない可能性がある」旨の記載がある。

**署名の有無だけが判定基準ではない**。ROCm 7.2.1 の `dl.dll` も未署名だが通っていた一方、ROCm 10 の同名ファイルは確定的にブロックされた。Smart App Control はファイルのレピュテーション(普及度・実績)も見ているため、リリース直後のバイナリほど弾かれやすいと考えられる。

対処:

- **Smart App Controlを無効にする** — ROCm 10 を使うにはこれが必要。「Windows セキュリティ」→「アプリとブラウザー制御」→「スマート アプリ コントロール」から変更できる。**Microsoftのドキュメントには一度オフにすると再度オンにできないと記載があるが、検証環境(Windows 11 26xxx)では自由にオン/オフを切り替えできた**。環境やバージョンによって挙動が異なる可能性があるため、事前に確認すること。
- **Microsoft Defenderの除外設定は効かない** — Defenderのウイルス対策とSmart App Controlは別系統の仕組みで、Defender側にパスを除外登録してもブロックは解消しない(実際に試して確認済み)。Smart App Control には除外リストの仕組み自体がない。記録先も異なり、Defenderの「保護の履歴」ではなく `Microsoft-Windows-CodeIntegrity/Operational` イベントログ(イベントID 3077/3033)に残る。
- **ROCm 7.2.1 で運用する** — こちらはブロックが断続的なため、`generate_video.py` の自動リトライ(サーバープロセスの生死を監視し、起動直後に落ちた場合は即座に再起動)で回避できる。実害は起動が数分遅れる程度。

## 5. ROCm 7.2.1 からの変更点

ROCm 10.0.0 への移行で変わった点。ROCm 7.2.1 の手順を知っている場合はここだけ読めばよい。

| | ROCm 7.2.1 | ROCm 10.0.0 |
|---|---|---|
| 配布形式 | `repo.radeon.com` の個別wheel URLを4つ手書き | `https://stable.repo.amd.com/rocm/whl-next/` をpipインデックスとして指定 |
| ROCmランタイム | `rocm_sdk_core` 等を明示的にインストール | `torch[device-all]` の依存として自動で入る |
| インストール順序 | requirements.txt が汎用torchで上書きするため、**ROCm版を最後に入れ直す**必要があった | バージョン表記が要求を満たすため上書きされない。入れ直し不要 |
| セットアップ手順 | 5ステップ | 4ステップ |
| 起動オプション | 不要 | **`--disable-dynamic-vram` が必要**(付けないと `cuMemMap` で失敗) |
| Smart App Control | 影響は断続的(`torchvision/_C.pyd`、リトライで回避可能) | **致命的**(`torch/lib/dl.dll` が確定的にブロックされ、torchのimport不可)。無効化が必要 |
| ログ上のROCmバージョン | `ROCm version: (7, 2)` | `ROCm version: (7, 15)`(HIPランタイムのバージョンであり、10とは表示されない) |
| ComfyUIの起動時間 | 40〜60秒 | 15秒程度 |

### 生成速度の比較

いずれも AMD Radeon AI PRO R9700・864x480・20steps・実測値。

| 尺 | フレーム数 | ROCm 7.2.1 | ROCm 10.0.0 | 短縮率 |
|---|---|---|---|---|
| 約5秒 | 124 | 322秒 (5分22秒) | **280秒 (4分40秒)** | 13% |
| 約15秒 | 362 | 1860秒 (31分) | **1250秒 (20分50秒)** | **33%** |

**尺が長いほど差が大きくなる**。短尺ではモデルのロード時間が全体に占める割合が大きく、そこは両者で大きく変わらないため差が縮む。実際のサンプリング処理そのものは ROCm 10 の方が明確に速い。

ROCm 7.2.1 に戻したい場合は、`.venv` を作り直して [git履歴](https://github.com/mitsuharu/ComfyUI-ROCm/commits/master/scripts/setup.ps1) の該当バージョンの `setup.ps1` を使う。モデルファイル(`ComfyUI/models/`)はそのまま流用できる。

## 6. 生成方法

Claude Codeでこのリポジトリを開いている場合は `.claude/skills/minimax-h3-video/` が自動で使えるので、「〜な動画を作って」と頼むだけでよい。手動でAPIを直接叩く方法や、解像度/長さの目安、プロンプトのコツは [generate_video.md](generate_video.md) を参照。`examples/` に実際に生成できたワークフロー例(アニメ調・実写風)がある。
