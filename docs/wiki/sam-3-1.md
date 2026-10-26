---
title: SAM 3.1 segmentation
updated: 2026-10-26
sources:
  - spikes/tug-94/FINDINGS.md
  - spikes/tug-94/probe.ts
  - spikes/tug-94/results/
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

## Open questions

- Whether streaming changes latency.
- Whether `file_id` input is accepted for images, and any image size limit.
- Whether JPEG input changes results.
- How phrasing affects matches, beyond the few variants above.
