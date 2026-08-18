---
name: minimax-h3-video
description: Generate a short AI video (with synchronized audio) locally on this machine's ComfyUI + ROCm + MiniMax H3 install, running on the user's own Radeon GPUs — no cloud API, no cost per generation. Use this whenever the user asks to make/create/generate a video or animation, in English or Japanese ("make a video of X", "動画を作って", "〜のダンス動画作って", "アニメ風の動画", "実写風で〜のシーンを作って", "generate a clip of..."), including requests that only describe a scene or character without explicitly saying "video". Do NOT use this for editing/trimming/converting existing video files, for image-only generation, or for anything requiring a cloud/paid video API — this is strictly the local MiniMax H3 pipeline already installed at C:\Users\mitsuharu\ComfyUI-ROCm.
---

# MiniMax H3 local video generation (ComfyUI + ROCm)

This machine has a working local install of ComfyUI + MiniMax H3 (33B omni-modal
text/image-to-video-with-audio model) running on Radeon GPUs via ROCm. Full
install details and the reasoning behind every choice (why GGUF quantization
doesn't work here, why the NVFP4 text encoder is skipped, etc.) live in
`SETUP.md` at the repo root (`C:\Users\mitsuharu\ComfyUI-ROCm\SETUP.md` by
default) — read it if something in this skill seems to contradict what you
observe, since that file is the source of truth for the environment.

**Portability note**: paths below assume the default install location,
`C:\Users\mitsuharu\ComfyUI-ROCm`. If this repo was cloned somewhere else (or
this is the project-scoped copy of the skill living inside the repo itself
rather than the machine-wide `~/.claude/skills` install), check whether the
`COMFYUI_ROCM_ROOT` environment variable is set before assuming the default —
`generate_video.py` respects it, so pass it through (`$env:COMFYUI_ROCM_ROOT`
in PowerShell) rather than hardcoding a different path yourself.

## What this produces

A short (roughly 0.2–15s) MP4 with picture **and** synchronized audio (voice/SFX/
music are generated jointly with the video, not added afterward) at up to
1344x768. Generation takes a few minutes at 480p and up to ~20 minutes at the
model's max 16:9 resolution — always run it in the background and keep working
or say so, don't block the conversation waiting on it.

## How to generate a video

1. **Turn the user's request into a structured prompt using MiniMax's own
   format**, not a single freeform paragraph. Read
   `references/prompt-writing.md` in this skill (condensed from MiniMax's
   official h3-prompt-writing guide) before writing the prompt — it covers
   the exact field structure the model was trained on:
   `integrated_multimodal_description` (the shot-by-shot visual+audio
   timeline — style, shots with timestamps, camera motion, speaker IDs and
   `<d>...</d>` dialogue tags, on-screen text in quotes), then
   `overall_soundscape`, then `non_diegetic_music`, each on its own
   labelled section separated by a blank line. The user's request (often
   short, often Japanese) needs to be *expanded* into this structure, not
   just translated — invent the concrete shot/camera/sound detail the
   format calls for rather than leaving it vague. End the description with
   light negative guidance (no text, no watermark, no subtitles) if stray
   on-screen text is a risk. If the request supplies a reference image
   (`first_frame`/`last_frame`, i.e. I2VA/FL2VA/L2VA) or multiple references
   (Ref2VA), the same reference file covers how the structure changes —
   read it, don't guess.

2. **Pick resolution and length.** Default to 864x480 (~480p, the faster and
   more reliable option) and length=124 (~5 seconds) unless the user asks for
   something else. If they want higher quality and are OK waiting longer,
   1344x768 (this model's 16:9 ceiling, ~720p-equivalent) is the next step up
   — mention the time tradeoff (single digit minutes vs. up to ~20) before
   committing to it rather than assuming. For other durations, frame count
   must satisfy `length % 17 == 5`; the resolution/duration reference tables
   in `generate_video.md` cover the common cases (5 frames ≈ smoke test, 39 ≈
   2s, 73 ≈ 3s, 124 ≈ 5s, 243 ≈ 10s, 362 ≈ 15s, the model's trained ceiling).
   For portrait video, swap width/height.

3. **Run the generation script**, which builds the ComfyUI workflow from
   `workflow_template.json`, submits it, and polls for completion. It also
   owns the one real operational wrinkle of this setup: the ComfyUI server has
   been observed to die mid-generation on this Windows/ROCm combination
   (suspected driver TDR under sustained load, not yet root-caused) — the
   script detects that (a real connection failure, not just an empty history
   response) and automatically restarts the server and resubmits the exact
   same job, up to 3 times, rather than hanging forever. Prefer letting the
   script own this rather than re-deriving the restart logic by hand each
   time — it's had a chance to get the edge cases right that ad hoc curl
   polling hasn't.

   Run it with Bash, **in the background** (generation takes minutes):
   ```bash
   "C:/Users/mitsuharu/ComfyUI-ROCm/.venv/Scripts/python.exe" \
     "C:/Users/mitsuharu/.claude/skills/minimax-h3-video/scripts/generate_video.py" \
     --prompt "<the expanded English prompt>" \
     --width 864 --height 480 --length 124 --steps 20 \
     --seed <any integer, vary it across calls so repeats don't look identical> \
     --name <short_filename_no_spaces> \
     --timeout 1800
   ```
   On success its last line is `OUTPUT:<path to the mp4>`. On failure it exits
   non-zero with an `ERROR:` line explaining what went wrong (e.g. the server
   would not come back up after repeated restarts — in that case check
   `C:\Users\mitsuharu\ComfyUI-ROCm\server_autostart.log` for the underlying
   crash and tell the user, don't just retry silently in a loop yourself).

   If a ComfyUI instance is already open in the Browser pane (from a previous
   `preview_start` with the `comfyui-rocm` launch config), you can watch
   progress there instead of only relying on the script's own polling — the
   script talks to whatever is on port 8188 either way, and will start its own
   background instance if nothing answers, so there's no conflict either way.

4. **Deliver the result.** Once you have the `OUTPUT:` path, send it to the
   user with the file-delivery tool available to you (e.g. `SendUserFile`),
   with a short caption noting resolution/duration/style so they know what
   they're looking at without having to ask.

5. If the user wants changes (different action, different style, longer,
   higher-res), don't just re-run with the same seed — vary the seed and
   rebuild the prompt to reflect what they asked for, then repeat from step 3.

## Notes

- `steps` defaults to 20 (matches the official template). Lower it (e.g. 10)
  only for a quick smoke test where quality doesn't matter — don't lower it to
  save time on a real request without telling the user quality will suffer.
- This is a single-GPU-at-a-time pipeline: ComfyUI's memory manager loads the
  text encoder, encodes the prompt, unloads it, then loads the UNet to sample
  — you don't need to do anything to make this happen, and you don't need to
  pick which of the two R9700s to use.
- If you need to do something the script doesn't cover (reference-image/video
  conditioning via `MiniMaxH3ReferenceToVideo`, tuning the sampler, etc.),
  read `C:\Users\mitsuharu\ComfyUI-ROCm\generate_video.md`,
  `references/prompt-writing.md`'s Ref2VA section, and
  `C:\Users\mitsuharu\ComfyUI-ROCm\ComfyUI\comfy_extras\nodes_minimax_h3.py`,
  then either edit a copy of `workflow_template.json` by hand and POST it
  directly, or extend the script — don't fight the model into doing something
  the fixed template can't express.
- `references/prompt-writing.md` is a condensed version of MiniMax's own
  guide, not a replacement for it — if a generated video doesn't match the
  request and the prompt structure looks right, the official source (linked
  at the top of that file) has more worked examples per mode than were worth
  inlining here.
