# TUG-94 / TUG-118: SAM 3.1 on level frames. Findings

Measured on 2026-10-26 against `api.meta.ai/v1`, model `sam-3.1`. The quality verdict and the fallback choice are Phil's (TUG-94). This file records what the API takes and returns, and what I saw.

**Contact sheet: [`results/sheet.png`](results/sheet.png).** First tile of each frame group is the input frame; red-captioned tiles are "no match". Per-result overlays are in `results/overlays/`.

## Setup

- 4 frames, 1280×720 PNG, rendered with `tools/shots.sh -p planted` from the restyled level: `beacon`, `ledge`, `drop`, `fork` ([`frames/`](frames/)).
- 25 prompts (24 noun phrases, 6 per frame, and 1 box+point request on `fork`), each run twice: 50 calls, one image per call. The prompt list is in [`probe.ts`](probe.ts).
- Calls go through `analyst/src/meta.ts` `respond()` (spend cap and ledger). Non-streaming, one at a time, image inline as a base64 `data:image/png` URL, `metadata.include_confidence: "true"`.
- Raw responses: [`results/raw/`](results/raw/). Parsed summary per call (latency, boxes, confidence, mask pixel counts): [`results/records.json`](results/records.json). Parsing and mask decoding use `@meta-sam/parser` 0.1.0. The overlays are drawn by [`overlay.py`](overlay.py) (Pillow): mask as a 43% fill plus outline, box as a thin rectangle. Only the contact sheet is committed. To redraw the per-prompt overlays, re-run `probe.ts`, which writes the decoded masks to `results/masks/` (paid, about $0.06 for one pass), then run `overlay.py`.

## API shape

Request: `POST /v1/responses`, `model: "sam-3.1"`, one user message with an `input_text` part and one `input_image` part (`image_url` is a URL or data URL).

```json
{ "model": "sam-3.1",
  "metadata": { "include_confidence": "true" },
  "input": [{ "type": "message", "role": "user", "content": [
    { "type": "input_text", "text": "the arrow sign" },
    { "type": "input_image", "image_url": "data:image/png;base64,…" } ]}] }
```

Response (non-streaming works and returns the full result in `output_text`): one line per image, `<0f>` then comma-separated records. Each record is an object id, one box, one mask:

```
<0f>0<|box;x1=603;y1=289;x2=672;y2=334;w=1280;h=720;c=0.87|><|mask;x=0;y=0;c=0.87;data=45,69,~<base85>|>,1<|box;…
```

- **Boxes** are in source pixels (`w`,`h` = image size). **Masks** are `data=H,W,<marker><base85>`: only the box region, not the full frame. `~` is lossless (default), `!` is one-bit (`metadata.mask_encoding`; box/point prompts always return one-bit). The parser's `decodeMaskToRaster` gives a 0/1 array and `record.bounds` gives where it sits.
- **Score:** `c` (0–1) on each box and mask, only when `metadata.include_confidence` is the string `"true"`. Box and mask carried the same value in every result here.
- **Multiple instances:** every match comes back, ids are integers.
- **No match** is `output_text: ""` and HTTP 200. The parser throws unless you also feed it an `output_text.done` event for an empty string.
- **Usage:** `input_tokens`/`output_tokens` are 0. `usage.images_processed` is 1 per image.
- **Box/point prompts:** the prompt text uses the same token grammar (`<0f>1<|box;x1=…;w=…;h=…|>,2<|point;x=…;y=…;w=…;h=…|>`), built with `buildObjectPrompt`. Worked in this probe (below).
- **Noun-phrase rules from the docs:** one concept per request, short phrase, no spatial phrasing or negation, up to 16 prompted objects. See the [wiki page](../../docs/wiki/sam-3-1.md).

**Price:** $2.50 per 1,000 images ($0.0025 each), no tokens. The final 50 calls cost $0.125. The ledger total for this task is $0.32 of the $2 budget (128 priced images, see Notes). Rate limit 3,000 RPM.

## Latency

Wall-clock per call from the client, including the base64 upload of a 0.23–0.45 MB PNG.

| Frame | Calls | Median | Min | Max |
|---|---|---|---|---|
| beacon | 12 | 1.13 s | 0.63 s | 3.85 s |
| ledge | 12 | 1.18 s | 0.73 s | 2.65 s |
| drop | 12 | 1.01 s | 0.58 s | 2.67 s |
| fork | 14 | 0.99 s | 0.76 s | 2.09 s |
| all | 50 | 1.06 s | 0.58 s | 3.85 s |

Calls that returned a match had a median of 1.28 s, calls with no match 0.99 s. The `ledge` "tree" call returned 31 instances (83 kB of output) in 1.9 s and 1.3 s. The first run of a prompt was slower than the second in 16 of 25 pairs.

## What I observed, per prompt

Counts were the same in both runs for every prompt. Boxes and mask pixel counts differed slightly between runs on 2 prompts (`the tree`, `the doorway`); the rest were identical in bounds and pixel count.

| Frame | Prompt | Matches (conf.) | What the overlay shows |
|---|---|---|---|
| beacon | "the glowing beacon" | 0 | No glowing object is visible to me in this frame. |
| beacon | "the doorway" | 0 | The blue rectangle in the far wall was not matched. |
| beacon | "the wooden crate" | 0 | A crate is visible at centre right; not matched. |
| beacon | "the star" | 1 (0.89) | The star outline above the blue rectangle, tight mask. |
| beacon | "the blue sky" | 0 | |
| beacon | "the player" | 0 | The player character is centre frame; not matched. |
| ledge | "the ledge edge" | 0 | |
| ledge | "the gap between the ledges" | 0 | |
| ledge | "the tree" | 31 (0.50–0.89) | The two big foreground trees have clean masks (the left one has some holes); the rest are small background trees on the far cliffs. |
| ledge | "the flower" | 8 (0.50–0.57) | Small masks (55–173 px) on flowers, in the foreground and along the path edges. |
| ledge | "the grass path" | 0 | |
| ledge | "the cliff" | 0 | |
| drop | "the exit sign" | 1 (0.51) | Only the 17×8 px "EXIT" text above the arrow, not the arrow sign. |
| drop | "the doorway" | 1 (0.55) | Outline traces the doorway frame at the end of the corridor; the mask is 10,054 px of its 14,042 px box. |
| drop | "the enemy" | 0 | The mushroom-hat character is not matched. |
| drop | "the arrow" | 1 (0.61) | The small red arrow in the doorway. |
| drop | "the mushroom" | 1 (0.86) | The red mushroom hat on the character. |
| drop | "the player" | 0 | |
| fork | "the exit sign" | 0 | The "EXIT" text and arrow sign are visible; not matched. |
| fork | "exit sign" (no article) | 0 | Same. |
| fork | "the arrow sign" | 1 (0.88) | The arrow board, tight mask (2,000 px). |
| fork | "the hedge wall" / "the hedge" / "the wooden sign" | 0 | |
| fork | box + point on the sign | 2 (0.94, 0.86) | Box prompt: mask of the whole arrow board (2,015 px). Point prompt at (640, 310): a 6-pixel mask. |

Summary of what I see: of the 24 noun phrases, 8 returned a match on the first and second run. All large, flat-coloured structural surfaces I tried (path, cliff, wall, hedge, sky, ledge edge) and the player character returned nothing. Objects with a distinct silhouette (star, tree, flower, arrow, mushroom hat) matched. "The exit sign" matched a text label in one frame and nothing in another.

## Fallback options (not tested unless stated)

- **No overlay**: plain key frame. Empty `output_text` is an ordinary 200 response, so the pipeline can detect it and fall back per finding (documented, and seen in 16 of 24 noun-phrase prompts).
- **Box prompt from known coordinates**: tested here with hand-picked pixels on `fork`; it segmented the sign. Where the box would come from (telemetry position projected through the camera, or a box from a Muse model) is untested.
- **Retry with a different phrase** (e.g. a shorter noun, or the object's name from the game): "the exit sign" and "the arrow sign" gave different results on the same sign in `fork`. No systematic test.
- **Draw a box only**: each result carries a box, and the box alone is enough for the "the player looked here" annotation.

## Not tested

Streaming, `file_id` input (inline base64 only), JPEG input, video, frames with other resolutions, larger prompt sets, concurrency.

## Notes

- `analyst/src/meta.ts`: added `sam-3.1` at $2.50 per 1,000 images (`PRICE_PER_IMAGE`), costed from `usage.images_processed`. Before this change a SAM call was written to the ledger as unpriced at $0.
- The first full run had a bug in `probe.ts` (box coordinates read from the wrong property), so I re-ran everything. The ledger's 128 images are the first 28-call run (before the extra prompts), a 50-call run discarded for the bug, and the final 50 calls. One exploratory call before the price change was ledgered at $0 and isn't in the total.
