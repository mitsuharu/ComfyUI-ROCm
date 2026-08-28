# ComfyUI + ROCm + MiniMax H3

ローカルのAMD Radeon GPU(ROCm)だけで、[ComfyUI](https://github.com/comfyanonymous/ComfyUI) 上で [MiniMax H3](https://huggingface.co/MiniMaxAI/MiniMax-H3)(Hailuo 3.0、33Bパラメータのオムニモーダル動画+音声生成モデル)を動かすためのセットアップ手順・スクリプト・使い方をまとめたリポジトリです。クラウドAPIやNVIDIA GPUなしで、テキスト/画像から音声付きの短い動画をローカル生成できます。

検証環境:

| GPU | VRAM | 備考 |
|---|---|---|
| AMD Radeon AI PRO R9700 x2 | 32GB(x2、実際に使うのは1枚分) | 主開発機。Windows 11, ROCm 7.2.1 |
| AMD Radeon RX 9060 XT | 16GB | 別マシンで動作確認済み。同条件で生成時間は約3倍(下記「動作要件」参照) |

> このリポジトリに **ComfyUI本体・モデルの重みファイルは含まれません**。合計100GB近くになる上、公式配布から誰でも再取得できるため、`.gitignore` で除外し、代わりに `scripts/setup.ps1` で毎回同じ構成を再現できるようにしています。

## 動作要件

このリポジトリのセットアップスクリプト・Claude Codeスキルは **Windows + AMD Radeon(ROCm)専用**です。手順・スクリプトがPowerShell/Windowsパス前提で書かれているため、**macOS/Linuxでは動きません**(ROCm自体はLinuxにも存在しますが、このリポジトリのスクリプト類は移植されていません)。

| 項目 | 要件 |
|---|---|
| OS | Windows 11(64bit) |
| GPU | ROCm対応のAMD Radeon(gfx110X / gfx120X系。例: RX 7900XTX, RX 9060XT, RX 9070XT, Radeon AI PRO R9700 等)。NVIDIA GPUは非対応(NVFP4量子化はNVIDIA専用フォーマットのため使わない設計) |
| GPU ドライバ | 最新のAMD Adrenalinドライバ(ROCmのバージョンごとに最低要件が異なる。[SETUP.md](SETUP.md) 参照) |
| VRAM | **16GB以上**で動作確認済み。32GB(R9700)なら追加のオフロードなしで動くが、16GB(RX 9060 XT)でも動く — text encoder単体で約26GB相当あるため、16GBカードではComfyUIのメモリ管理がモデルの一部をシステムRAMとの間でオフロードしながら実行する。その分**生成時間が長くなる**(同一条件でR9700が約5分に対しRX 9060 XTは約15分、目安で3倍程度)。VRAMが少ないほど遅くなる傾向は続くと考えられるが、8GB等での動作は未検証 |
| システムRAM | 32GB以上を推奨(モデルの一時展開・ページキャッシュ用) |
| ディスク空き容量 | 約60GB以上(モデル一式で約52GB、Reference to Video込みで約70GB) |
| ソフトウェア | Python 3.12(64bit)、git、PowerShell 5.1以降(Windows標準搭載のもので可) |
| Claude Codeスキルを使う場合 | [Claude Code](https://claude.com/claude-code) がこのリポジトリ配下で動作していること(パスは既定で `C:\Users\mitsuharu\ComfyUI-ROCm` 前提、違う場所にcloneした場合は `COMFYUI_ROCM_ROOT` 環境変数で上書き) |

## まず読むもの

| 目的 | ファイル |
|---|---|
| 環境をゼロから構築したい | [SETUP.md](SETUP.md) |
| 動画生成の指示方法・プロンプトのコツ・解像度目安を知りたい | [generate_video.md](generate_video.md) |
| 動作するワークフローの実例を見たい | [examples/](examples/)(アニメ調・実写風の2種類) |

## クイックスタート

```powershell
git clone <このリポジトリのURL> ComfyUI-ROCm
cd ComfyUI-ROCm
.\scripts\setup.ps1
.\.venv\Scripts\python.exe ComfyUI\main.py
```

ブラウザで `http://localhost:8188` を開けば使える。詳細・トラブルシューティングは [SETUP.md](SETUP.md) を参照。

## リポジトリ構成

```
ComfyUI-ROCm/
├── README.md              このファイル
├── SETUP.md                環境構築手順(ゼロから再現する場合はここから)
├── generate_video.md        動画生成の指示方法・パラメータの決め方
├── workflow_template.json   動作確認済みのComfyUI APIワークフロー(GGUFではなくnative int8_convrot量子化を使用)
├── examples/                 生成に成功した実例ワークフロー(anime_dance.json / realistic_dance.json)
├── scripts/
│   ├── setup.ps1              venv〜モデルダウンロードまで一括で行うセットアップスクリプト
│   └── download_models.ps1    モデルの重みだけを(再)ダウンロードするスクリプト。resume対応
├── .claude/skills/minimax-h3-video/   Claude Codeが動画生成を自動で行うためのスキル(下記参照)
├── .gitignore
│
│   以下はgitignore対象(再取得可能なので追跡しない):
├── .venv/                    Python仮想環境
└── ComfyUI/                  ComfyUI本体・カスタムノード・モデル・生成物一式
```

## なぜGGUFやデフォルトの量子化ではなくnative int8_convrotなのか

要点だけ([SETUP.md](SETUP.md)に詳細):

- MiniMax H3のコミュニティ製GGUF量子化版は、`ComfyUI-GGUF` カスタムノードのアーキテクチャ自動検出が未対応で読み込めない(2026年8月時点)
- 公式デフォルトのテキストエンコーダー(NVFP4量子化)はNVIDIA専用フォーマットで、ROCm(HIP)バックエンドには存在しない(`dequantize_nvfp4` 相当のカーネルがHIP側にない)
- 代わりに公式配布されている **native int8_convrot** 量子化版(UNet・テキストエンコーダーとも)はROCmのHIPバックエンドで正式にサポートされており、これが実際に動作する組み合わせ

## Claude Codeスキル: `minimax-h3-video`

`.claude/skills/minimax-h3-video/` は、[Claude Code](https://claude.com/claude-code) がこのリポジトリを開いているときに自動で有効になるスキルです。「〜のダンス動画を作って」のように頼むだけで、Claudeが

1. リクエストを詳細な英語プロンプトに組み立て
2. 解像度・尺を決定(未指定なら480p・約5秒がデフォルト)
3. `scripts/generate_video.py` でComfyUIにジョブを投入・監視(サーバーが落ちた場合の自動再起動込み)
4. 完成した動画ファイルを渡す

という一連の作業を行います。Claude Code以外(手動でのAPI利用)の場合は [generate_video.md](generate_video.md) と `workflow_template.json` を直接使ってください。

このスキルはリポジトリの場所を前提にパスを組み立てますが、`COMFYUI_ROCM_ROOT` 環境変数でインストール先を上書きできるので、`C:\Users\mitsuharu\ComfyUI-ROCm` 以外の場所にcloneした場合はそれを設定してください。

## 既知の問題

- 長時間の生成中にComfyUIサーバーが突然落ちることがある(Windows上のROCmスタックがまだ発展途上であることに起因すると思われるが未確定)。`generate_video.py` は自動検知・自動再起動・再投入で対処済み。詳細は [SETUP.md](SETUP.md) の「既知の問題」を参照。
- Windows 11のスマート アプリ コントロールが有効だと、署名のない `torchvision/_C.pyd` のロードがブロックされ、ComfyUIの起動に失敗することがある(毎回ではない)。こちらも `generate_video.py` の自動リトライで復帰する。詳細と対処の選択肢は [SETUP.md](SETUP.md) の「既知の問題」を参照。
