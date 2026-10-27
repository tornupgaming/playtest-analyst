---
title: SAM 3.1 segmentation
updated: 2026-10-27
sources:
  - spikes/tug-94/FINDINGS.md
  - spikes/tug-94/probe.ts
  - spikes/tug-94/results/
  - spikes/tug-104/check.sh
  - spikes/tug-104/results/run.txt
  - spikes/tug-123/planted-voice.report.json
  - spikes/tug-123/probe.ts
  - spikes/tug-123/results.json
  - spikes/tug-123/sheet.jpg
  - https://dev.meta.ai/docs/media-segmentation
  - https://dev.meta.ai/docs/sam/overview
  - https://dev.meta.ai/docs/sam/segmenting
  - https://dev.meta.ai/docs/sam/reading-segmentation
  - https://dev.meta.ai/docs/sam/client-libraries
  - https://dev.meta.ai/docs/models
  - https://dev.meta.ai/docs/pricing-rate-limits
---

# SAM 3.1 segmentation

How `sam-3.1` on the Meta Model API (`https://api.meta.ai/v1`) takes an image and returns boxes and masks, what it costs, and what it returned on frames from our test level. For the other models on the same endpoint, see [Muse Wonder video input](muse-wonder-video.md).

## Documented

| Fact | Source |
|---|---|
| Model id `sam-3.1`. Input: text prompt, image, video. Output: boxes and masks. | [docs](https://dev.meta.ai/docs/models) |
| Called on `POST /v1/responses` with one user message holding one `input_text` part and one `input_image` or `input_video` part. | [docs](https://dev.meta.ai/docs/sam/overview) |
| Price: $2.50 per 1,000 images; $0.20 per 1,000 video frames with a 50-frame minimum per video request. Billed per image or frame, not per token. Streaming costs the same as non-streaming. | [docs](https://dev.meta.ai/docs/pricing-rate-limits) |
| Rate limit 3,000 RPM per team; no TPM limit. | [docs](https://dev.meta.ai/docs/pricing-rate-limits) |
| Concept prompt: one short noun phrase, one concept per request. Comma, semicolon and plus lists return zero matches. Plurals, case and punctuation are ignored. Docs advise against negation, boolean OR and spatial phrasing. | [docs](https://dev.meta.ai/docs/sam/segmenting) |
| An image returns every match. No match returns HTTP 200 with an empty `output_text`. | [docs](https://dev.meta.ai/docs/sam/segmenting) |
| Box and point prompts use the same token grammar as the output: `<0f>1<|box;x1=…;y1=…;x2=…;y2=…;w=…;h=…|>,2<|point;x=…;y=…;w=…;h=…|>`. `x2`,`y2` are inclusive. A negative point has a `-` before it. At most 16 prompted objects per request. A prompt is either a noun phrase or box/point, never both. `w`,`h` must match the media's aspect ratio or the call returns 400. | [docs](https://dev.meta.ai/docs/sam/segmenting) |
| Output: one line per image (per frame for video), `<Nf>` then comma-separated `id<|box;…|><|mask;…|>` records. Boxes are in source pixels. A mask is `data=H,W,<marker><base85>`, smaller than the frame (the box region). Marker `~` is lossless (default), `!` is one-bit. | [docs](https://dev.meta.ai/docs/sam/reading-segmentation) |
| `metadata.include_confidence: "true"` (a string) adds `c` (0–1) to each box and mask. `metadata.mask_encoding` is `lossless` or `one_bit`; box/point prompts always return `one_bit`. | [docs](https://dev.meta.ai/docs/sam/segmenting) |
| Video: MP4 or MOV, H.264/H.265/MPEG-4; no VP9 or WebM; up to 15,000 frames; tracks up to 16 objects per frame. | [docs](https://dev.meta.ai/docs/sam/segmenting) |
| Client libraries: `@meta-sam/parser` (npm, ESM, zero runtime dependencies: parse stream, decode mask to raster/COCO RLE/SVG path, build object prompts), `@meta-sam/graphics`, `@meta-sam/video`, `@meta-sam/react`, `meta-sam-parser` (PyPI). | [docs](https://dev.meta.ai/docs/sam/client-libraries) |
| The docs list no image size or format limit for SAM and no context window. | [docs](https://dev.meta.ai/docs/models) |

## Measured

**Conditions (all rows):** 2026-10-26, four 1280×720 PNG frames from the restyled test level (`beacon`, `ledge`, `drop`, `fork`, `-p planted`). Each prompt was run twice. Calls were non-streaming and sequential, with the image inline as a base64 data URL and `include_confidence` on. Latency is client wall-clock including the upload. Parsing used `@meta-sam/parser` 0.1.0. ([probe](../../spikes/tug-94/probe.ts), [raw responses](../../spikes/tug-94/results/raw/), [summary](../../spikes/tug-94/results/records.json), [contact sheet](../../spikes/tug-94/results/sheet.png))

| Fact | Source |
|---|---|
| A non-streaming call returns the same line format in `output_text`. `usage` has `input_tokens` 0, `output_tokens` 0 and `images_processed` 1. | [measured](../../spikes/tug-94/results/raw/fork__box-point-on-sign__r1.json) |
| Latency over 50 calls: median 1.06 s, min 0.58 s, max 3.85 s. Per frame medians: 0.99–1.18 s. | [measured](../../spikes/tug-94/results/records.json) |
| Box and mask carried the same `c` value in every result. | [measured](../../spikes/tug-94/results/records.json) |
| 24 noun-phrase prompts: 8 returned matches in both runs, 16 returned an empty `output_text` in both runs. | [measured](../../spikes/tug-94/results/records.json) |
| Matched: "the star" (1, c 0.89), "the tree" (31, c 0.50–0.89), "the flower" (8, c 0.50–0.57), "the arrow sign" (1, 0.88), "the arrow" (1, 0.61), "the mushroom" (1, 0.86), "the doorway" (1, 0.55, on the corridor frame), "the exit sign" (1, 0.51, on the corridor frame: a 17×8 px mask on the "EXIT" text). | [measured](../../spikes/tug-94/results/sheet.png) |
| Empty in both runs: "the glowing beacon", "the wooden crate", "the blue sky", "the player", "the doorway" (on the plaza frame), "the ledge edge", "the gap between the ledges", "the grass path", "the cliff", "the enemy", "the exit sign" and "exit sign" (on the fork frame), "the hedge wall", "the hedge", "the wooden sign". | [measured](../../spikes/tug-94/results/records.json) |
| Counts matched across the two runs for every prompt. Bounds or mask pixel counts differed slightly on "the tree" and "the doorway", and were identical otherwise. | [measured](../../spikes/tug-94/results/records.json) |
| A box prompt (hand-picked pixels) on the fork sign returned a mask of 2,015 px over the arrow board (c 0.94). A point prompt in the same request, at the board's centre, returned a 6-px mask (c 0.86). | [measured](../../spikes/tug-94/results/overlays/fork__box-point-on-sign.png) |
| The Responses `output_text` for 31 tree masks was about 83 kB. | [measured](../../spikes/tug-94/results/raw/ledge__the-tree__r1.json) |
| `@meta-sam/parser` 0.1.0 `parseImageStream` throws `ResponsesStreamLaneError` on an empty result unless the fed events include an `output_text.done` event (an empty-string one). | [measured](../../spikes/tug-94/probe.ts) |

### Key frames from a finalized video (TUG-104)

**Conditions:** 2026-10-26, one recorded run of [`check.sh`](../../spikes/tug-104/check.sh): three of the frames above encoded into a 1280×720 H.264 yuv420p slideshow (libx264 defaults), one frame each extracted by ffmpeg as PNG, five calls through `playtest annotate`, at most 4 in flight. ([run log](../../spikes/tug-104/results/run.txt))

| Fact | Source |
|---|---|
| "the star" (beacon), "the mushroom" (drop) and "the arrow sign" (fork) matched, as on the source PNGs. "the player" (beacon) returned no match, as on the source PNG. | [measured](../../spikes/tug-104/results/run.txt) |
| "the exit sign" on the drop frame returned no match, where it matched (c 0.51, 17×8 px) on the source PNG in both probe runs. | [measured](../../spikes/tug-104/results/run.txt) |
| All five calls with 4 in flight succeeded; the whole command, including ffmpeg and drawing, took 3.7 s wall-clock. | [measured](../../spikes/tug-104/results/run.txt) |

### Several phrasings and nearby frames (TUG-123)

**Conditions:** 2026-10-27, one `playtest analyse` run (config v0) on the rebuilt synthetic `planted-voice` session (1280×720 H.264). Muse Wonder gave each of 5 highlights 3 phrasings. `annotate` tried each phrasing at the key frame, then 2 s before and after it, and kept the first match with `c` ≥ 0.5. ([report](../../spikes/tug-123/planted-voice.report.json), [contact sheet](../../spikes/tug-123/sheet.jpg))

| Finding | Phrasings | Result |
|---|---|---|
| f1 ledge, t 12 | "small green floating platform", "isolated green square platform", "small green platform island" | 1st and 2nd: no match. 3rd matched at t 12, on the large platform under the player, not the small floating platform ahead of it. |
| f2 plaza, t 33 | "the white objective text", "Reach the beacon text", "top-left white text label" | No match at 33, 31 or 35 s (9 calls). The frame's HUD text reads "Reach the beacon." |
| f3 hall, t 74 | "the small red button", "the red oval button", "the button on orange shelf" | No match at 74, 72 or 76 s (9 calls). In the 74 s frame the button is unobstructed; the crop match below puts its box at about 32×10 px of the full frame. |
| f4 drop, t 109 | "the red mushroom character", … | 1st phrasing matched at t 109, on the mushroom hat. |
| f5 fork, t 128.5 | "the red arrow signpost", … | 1st phrasing matched at t 128.5, on the arrow board. |

The run made 23 SAM calls ($0.0575). The model call cost $0.405.

**Probe on the same frames** ([probe](../../spikes/tug-123/probe.ts), [frames](../../spikes/tug-123/frames/), [results](../../spikes/tug-123/results.json)), one call each:

| Frame | Prompt | Result |
|---|---|---|
| hall 74 s | "the red button", "the button" | No match. |
| hall 74 s | "the wooden shelf" | 1 match (c 0.93), the shelf under the button. |
| hall 74 s | "the wooden crate" | 2 matches (c 0.93, 0.83). |
| hall 74 s, 320×180 crop around the shelf scaled 4× to 1280×720 | "the red button" | 1 match (c 0.58), on the button. |
| same crop | "the small red button" | No match. |
| plaza 33 s | "the text", "the white text" | No match. |
| ledge 12 s | "the floating platform" | No match. |
| ledge 12 s | "the small green block" | 1 match (c 0.50), a 42×45 px grass tuft. |

## Open questions

- Whether streaming changes latency.
- Whether `file_id` input is accepted for images, and any image size limit.
- Whether JPEG input changes results, and whether the H.264 re-encode or chance explains the "the exit sign" miss (one run).
- Whether HUD text can be matched by any phrasing (none of 5 matched on one frame, TUG-123).
- Whether cropping around an expected location raises matches on small objects beyond the one probe above.
