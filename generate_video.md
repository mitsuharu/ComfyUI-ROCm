# MiniMax H3 動画生成の指示方法(ComfyUI API直叩き)

`workflow_template.json` をベースに、必要な項目を書き換えて `POST http://localhost:8188/prompt` に投げる。

## 手順

1. ComfyUIが起動していることを確認(起動していなければ `.venv\Scripts\python.exe ComfyUI\main.py`)
2. `workflow_template.json` をコピーして、ノード `"5"`(`MiniMaxH3ImageToVideo`)の `inputs` を書き換える:
   - `prompt`: 生成したい内容の説明文(英語推奨。長め・具体的なほど良い結果になりやすい)
   - `width` / `height`: 下記の解像度表から選ぶ(32の倍数、短辺768が最高品質)
   - `length`: フレーム数。目安は `秒数 x 24` を切り上げて `n % 17 == 5` になる値に丸める(下記の長さ表を参照。5秒なら124)
3. ノード `"8"`(`RandomNoise`)の `noise_seed` を変える(同じシードだと同じ結果になりやすい。省略したければ都度違う値にする)
4. ノード `"7"`(`BasicScheduler`)の `steps`: 疎通確認なら10、実用品質なら20(既定)。上げるほど高品質・低速
5. ノード `"14"`(`SaveVideo`)の `filename_prefix` をわかりやすい名前にする(例 `video/my_video`)
6. 投げる:
   ```powershell
   curl.exe -s -X POST http://localhost:8188/prompt -H "Content-Type: application/json" --data-binary "@workflow_edited.json"
   ```
   レスポンスの `prompt_id` を控える
7. 完了待ち(生成には解像度・長さ・ステップ数次第で数分〜数十分かかる):
   ```powershell
   curl.exe -s http://localhost:8188/history/<prompt_id>
   ```
   `{}` の間は未完了。中身が返ってきたら `status.status_str` が `success` かを確認。
8. 出力ファイルは `ComfyUI\output\video\<filename_prefix>_00001_.mp4` にできる

## 解像度の目安(16:9、短辺768が上限)

| メガピクセル | 解像度 | 用途の目安 |
|---|---|---|
| 0.2 | 608 x 352 | 疎通確認・最速 |
| 0.4 | 864 x 480 | 480p相当 |
| 0.98 | 1344 x 768 | 720p相当(このモデルの16:9最大) |

縦長(9:16)にしたい場合は width/height を入れ替える。1:1やその他アスペクト比も可(幅x高さの合計ピクセル数が0.98MP=約1,032,192を超えないように)。

## 長さ(フレーム数)の目安(24fps、17フレーム単位+5に丸め)

| 秒数 | length |
|---|---|
| 最短(0.2秒、テスト用) | 5 |
| 約2秒 | 39 |
| 約3秒 | 73 |
| 約5秒 | 124 |
| 約10秒 | 243 |
| 約15秒(公式の上限目安) | 362 |

## プロンプトの書き方(MiniMax公式フォーマット)

自由な一文で書くよりも、MiniMax公式の [h3-prompt-writing](https://github.com/MiniMax-AI/MiniMax-H3/tree/main/skills/h3-prompt-writing) スキルが定める構造化フォーマットに従うと、狙ったショット数・音声が安定して出やすい。要点(詳細・具体例は `.claude/skills/minimax-h3-video/references/prompt-writing.md` を参照):

```text
integrated_multimodal_description: [Shot 1] スタイル、構図、被写体、動作、カメラワーク、セリフ等を時系列で記述...

overall_soundscape: 環境音・物理音の要約(1〜4文)

non_diegetic_music: 劇中人物には聞こえないBGM(1〜3文、無音ならN/A)
```

上記3つのラベルをこの順で、間に空行を挟んで1つの`prompt`文字列に連結する。ショット区切り(`[Shot 2] At 00:03.500, ...`)、カメラワークの書き方、セリフの`(S1)`+`<d>[English] ...</d>`タグ、画面内テキストの引用ルールなども `prompt-writing.md` にまとめてある。

## Reference to Video(参照画像/動画あり)を使いたい場合

`MiniMaxH3ImageToVideo` の代わりに `MiniMaxH3ReferenceToVideo` ノードを使い、`minimax_h3_ref2va_pruned_int8_convrot.safetensors` をUNetLoaderで指定する。参照画像/動画/音声はプロンプト中で `<Subject N>` / `<Picture N>` / `<Video N>` / `<Audio N>` のように参照し、`subject_definitions` → `summary` → `retention_analysis` → `detailed_description` → `overall_soundscape` → `non_diegetic_music` の6セクション構成になる。詳細は `prompt-writing.md` の「Reference-to-video」節、および `ComfyUI/comfy_extras/nodes_minimax_h3.py` のdocstringを参照。
