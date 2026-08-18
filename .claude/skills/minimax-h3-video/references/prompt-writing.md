# MiniMax H3 prompt-writing reference

Distilled from MiniMax's own official prompt-writing guide for H3, published at
https://github.com/MiniMax-AI/MiniMax-H3/tree/main/skills/h3-prompt-writing
(`SKILL.md`, `references/base-en.txt`, `references/ref-en.txt`). This file
restates their field structure and formatting conventions in condensed form
with fresh examples — read the source directly if you need the full
walkthrough or more worked examples than fit here.

Follow this structure for every prompt instead of writing a single freeform
paragraph: MiniMax H3 was trained on prompts organized this way, and following
it produces noticeably more controllable results (correct shot count, audio
that matches the picture, dialogue that's actually spoken by the right
character) than an unstructured description.

## Final prompt structure

The text you put in `MiniMaxH3ImageToVideo`'s `prompt` field is always built
from three core sections, written with **literal field-name labels**,
separated by a blank line, in this exact order:

```text
integrated_multimodal_description: <the shot-by-shot visual+audio timeline>

overall_soundscape: <ambient/physical sound across the whole video>

non_diegetic_music: <background score, or N/A>
```

For T2VA (plain text-to-video — the default for this setup, no reference
image), that's the whole prompt: no extra instruction line before it.

If you're using `first_frame`/`last_frame` (I2VA/FL2VA/L2VA — see "Image
inputs" below), the official convention adds one alignment-instruction line
before the three fields, describing which `<Picture N>` lands at which
timestamp. This ComfyUI node passes images to the text encoder separately
from the prompt string (`clip.tokenize(prompt, images=[...])`), so treat that
alignment line as something to try and verify rather than something guaranteed
to be interpreted identically to MiniMax's own hosted API — if results look
wrong, drop the alignment line and just describe the scene naturally instead.

## Writing `integrated_multimodal_description`

This is the main body: everything visible or audible, laid out along the
timeline. Rules that make the biggest difference:

- **Open with style + composition.** Start `[Shot 1]` by naming the visual
  style (`Cinematic`, `live-action`, `2D-animated`, `3D CG`, `claymation`,
  `watercolor`, `vintage film`, ...) and the initial framing, before
  describing what happens.
- **Mark every shot change explicitly**, and give every shot after the first
  an increasing timestamp: `[Shot 2] At 00:04.200, the camera cuts to...`. A
  cut should introduce genuinely new information (subject, space, angle,
  time) — if only the framing needs to tighten slightly, move the camera
  instead of cutting.
- **Describe camera motion as three dimensions in one natural sentence**: what
  moves (`Push In`/`Pull Out`, `Pan Left`/`Right`, `Truck Left`/`Right`,
  `Tilt Up`/`Down`, `Pedestal Up`/`Down`, `Arc Shot`, `Tracking Shot`,
  `Static Shot`, `Zoom In`/`Out`, `Shake Slightly`/`Strongly`, `POV`, `Roll
  Clockwise`/`Counterclockwise`), how far (`with small/large amplitude`,
  omit for medium), how fast (`at slow/fast speed`, omit for normal speed).
  Write it as an action in the sentence, not a tag stuck on the end:
  `The camera arcs left with small amplitude at slow speed around the
  dancer.`
- **Give speaking/singing characters a stable ID** — `(S1)`, `(S2)`, combined
  as `(S1,S2)` for simultaneous speech — introduced with enough visual/vocal
  detail to identify them the first time, then reused across shots. Only
  characters who actually vocalize get an ID. Wrap the literal spoken/sung
  content in `<d>[English] ...</d>` (language tag + verbatim text/lyrics,
  untranslated) right after the speaker's action:
  `The barista with a low, warm voice (S1) says: <d>[English] Order up.</d>`
  For a voiceover, say `says in an off-screen voiceover` and immediately
  note the on-screen character's lips stay closed.
- **Quote any text that's actually visible in frame** (signs, banners,
  subtitles baked into the scene) in double quotes, verbatim, untranslated:
  `A hand-lettered sign reading "OPEN" hangs in the window.`
- **Only describe what's on screen or audible** — no interpretation of mood,
  backstory, or camera-jargon abbreviations the model wasn't trained on.

## Writing `overall_soundscape` and `non_diegetic_music`

- `overall_soundscape`: 1–4 sentences, one paragraph, covering ambience,
  physical/impact sounds, and non-verbal human sounds (footsteps, wind,
  traffic, fabric, breathing) across the *whole* video. Don't repeat
  dialogue/singing/diegetic music here — that belongs in the description
  above. Use `N/A` only if the user explicitly wants total silence.
- `non_diegetic_music`: 1–3 sentences describing the score the audience hears
  but the characters don't — instrumentation, tempo, rhythm, how it changes —
  not mood adjectives. Music audible to characters (radio, a phone, a live
  band on screen) is diegetic and belongs in the description instead. Use
  `N/A` when there should be no score.

## Example (original, T2VA)

```text
integrated_multimodal_description: [Shot 1] 2D-animated, clean line art and cel shading, a wide shot frames a high school girl in a sailor uniform standing at the center of an empty rooftop at golden hour. The camera arcs left with small amplitude at slow speed as she raises both arms and spins once, skirt flaring outward. [Shot 2] At 00:02.800, the camera cuts to a low tracking shot following her feet as she steps into a energetic idol-style routine, hair ribbons bouncing with each move.

overall_soundscape: Wind moves steadily across the open rooftop, occasionally catching the fabric of her uniform. Her shoes tap lightly against the concrete on each landing.

non_diegetic_music: An upbeat synth-pop track at a driving tempo, with a bright synth lead doubling the melody and a punchy four-on-the-floor beat underneath.
```

## Image inputs (I2VA / FL2VA / L2VA)

If a request supplies a reference image via `first_frame` and/or
`last_frame`:

- **I2VA** (`first_frame` only): the video develops forward from that frame.
  Describe the frame's subject/composition/scene as the `[Shot 1]` opening,
  then how it develops — don't just re-describe a static image.
- **FL2VA** (`first_frame` + `last_frame`): describe the *motion path*
  between them, not two static descriptions — how the subject moves, poses
  change, lighting transitions, ending exactly at the second frame's state.
  Prefer a single shot; the official guide favors this so the model can
  interpolate continuously.
- **L2VA** (`last_frame` only): infer a plausible earlier state and describe
  the path that converges onto the supplied last frame by the end.

See MiniMax's `references/base-en.txt` (linked above) for the exact
alignment-instruction wording per mode and more worked examples if the short
version here isn't enough to get good results.

## Reference-to-video (Ref2VA)

For `MiniMaxH3ReferenceToVideo` (multiple reference images/videos/audio
composited into one new video — see `generate_video.md` in the repo root for
when this node applies), the official structure adds three sections *before*
the same three core fields, six total in order:

1. `subject_definitions` — one line per reusable piece of reference content
   (a person, object, environment, or track), naming its label and what to
   preserve. Labels: `<Subject N>` for a reusable person/object/style/action,
   `<Picture N>` for an image used as a concrete frame/anchor, `<Video N>`
   for a whole source video's structure/edit, `<Audio N>` for reused audio.
   A label means the same thing in every later section once assigned.
2. `summary` — a short statement of the task type and what's being combined.
3. `retention_analysis` — how each labelled item is preserved, transferred,
   or reused in the target video.
4. `detailed_description` — same conventions as
   `integrated_multimodal_description` above, but should explicitly call out
   *where* each reference actually takes effect, shot by shot.
5. `overall_soundscape` — same rules as above.
6. `non_diegetic_music` — same rules as above.

This is a more involved format than the base modes — read MiniMax's
`references/ref-en.txt` (linked above) before building a Ref2VA prompt for
anything non-trivial.
