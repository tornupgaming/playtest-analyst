---
title: Muse Wonder video input
updated: 2026-10-26
sources:
  - spikes/tug-93/FINDINGS.md
  - spikes/tug-93/probe.py
  - spikes/tug-93/results/
  - spikes/tug-99/results/
  - https://dev.meta.ai/docs/file-handling
  - https://dev.meta.ai/docs/models
  - https://dev.meta.ai/docs/api-reference/responses/schemas
  - https://dev.meta.ai/docs/video-understanding
  - https://dev.meta.ai/docs/token-counting
  - https://dev.meta.ai/docs/pricing-rate-limits
---

# Muse Wonder video input

How `muse-wonder-1.0` on the Meta Model API (`https://api.meta.ai/v1`) takes video, and what it costs, how long it takes and how accurate it is. For speech-to-text, see [Meta ASR](meta-asr.md).

## Documented

| Fact | Source |
|---|---|
| Video input is `video/mp4` only. Audio input is MP3 or WAV. | [docs](https://dev.meta.ai/docs/file-handling) |
| Inline (base64 / data URL) input is capped at 50 MB per request. | [docs](https://dev.meta.ai/docs/file-handling) |
| The Files API (`POST /v1/files`, `purpose=user_data`) takes up to 1 GiB per file and 100 GiB per team. Files don't expire unless `expires_after` is set. | [docs](https://dev.meta.ai/docs/file-handling) |
| No video duration limit is published. The context window is 1,048,576 tokens. | [docs](https://dev.meta.ai/docs/models) |
| `input_video` takes an `fps` field for server-side frame sampling. The default fps isn't documented. | [docs](https://dev.meta.ai/docs/api-reference/responses/schemas) |
| Video is read as visual frames plus a transcription of the embedded audio. | [docs](https://dev.meta.ai/docs/video-understanding) |
| The video guide's examples use `muse-spark-1.3` and say audio understanding in Spark 1.3 is "not fully supported". Wonder's model page lists audio input. | [docs](https://dev.meta.ai/docs/video-understanding), [docs](https://dev.meta.ai/docs/models) |
| `usage` reports `input_tokens` and `cached_tokens` only, not split by modality. | [docs](https://dev.meta.ai/docs/api-reference/responses/schemas) |
| Price: $4/M input, $0.20/M cached input, $20/M output. There is no long-context premium. | [docs](https://dev.meta.ai/docs/pricing-rate-limits) |
| Rate limits: 3,000 RPM and 4M TPM per team. | [docs](https://dev.meta.ai/docs/pricing-rate-limits) |

## Measured

**Conditions (all rows):** one run each on 2026-10-26. The clip is a synthetic 10-minute 720p30 MP4 with no on-screen clock. It has 6 visual events (full-screen text) and 4 spoken lines (Piper TTS, `en_US-lessac-medium`) with nothing on screen ([clip builder](../../spikes/tug-93/build_clip.py)). It was uploaded through the Files API and referenced by `file_id`. The request used a strict `json_schema` output format and `max_output_tokens` 16000, and asked for every event with a time in seconds ([probe](../../spikes/tug-93/probe.py)). An event counts as on time if it is within ±5 s.

### Accuracy, tokens, cost and latency per 10-minute clip

| Input | fps | Visual events found / on time | Speech found / on time | Speech timestamp error (s) | Input tokens | Output tokens (reasoning) | Cost | Latency | Source |
|---|---|---|---|---|---|---|---|---|---|
| Video + audio track | default | 6/6, 6/6 (errors ≤1 s) | 4/4, 1/4 | +25, −15, −15, −5 | 85,582 | 6,416 (5,842) | $0.47 | 75.1 s | [run](../../spikes/tug-93/results/run-native-None.json) |
| Video + audio track | 1 | 6/6, 6/6 (errors ≤2 s) | 4/4, 0/4 | −78, −22, −170, −245 | 85,582 | 7,418 (7,141) | $0.49 | 99.5 s | [run](../../spikes/tug-93/results/run-native-1.0.json) |
| Video + audio track | 0.2 | 3/6, 2/6 (see below) | 4/4, 0/4 | +52, +92, +73, +62 | 23,182 | 14,561 (14,198) | $0.38 | 168.5 s | [run](../../spikes/tug-93/results/run-native-0.2.json) |
| Silent video | 1 | 6/6, 6/6 | 0/4 | — | 78,079 | 3,742 (3,169) | $0.39 | 57.2 s | [run](../../spikes/tug-93/results/run-noaudio-1.0.json) |
| Silent video + ASR transcript as text | 1 | 6/6, 6/6 | 4/4, 4/4 | −0.3, −0.1, 0.0, −0.1 | 78,140 | 4,592 (4,231) | $0.40 | 65.1 s | [run](../../spikes/tug-93/results/run-noaudio-1.0-transcript.json) |

These runs show that:
- The model uses the embedded audio track. With it, all 4 spoken lines were found. With the track removed, none were.
- Timestamps for speech heard in the audio track were off by 5–245 s. Timestamps for visual events were within 2 s in every run at default fps or fps 1.
- Speech timestamps were within 0.3 s when a timestamped transcript was passed as text.
- The audio track added 7,503 input tokens per 10 minutes (85,582 vs 78,079).
- Setting `fps` to 1 billed the same number of input tokens as the default (85,582 both).
- `fps` changes billed tokens: 0.2 billed 23,182 against 85,582 at 1 on the same clip. That is 62,400 tokens for 480 more frames, or 130 tokens per 720p frame.
- At fps 0.2, three of the six 3-second visual events (CHECKPOINT, PAUSED, LEVEL COMPLETE) weren't reported. The nearest report to the first YOU DIED was 253 s late. KEY (+1 s) and the second YOU DIED (−5 s) were on time.

### 40-second session through `playtest analyse`

**Conditions:** 2026-10-26, one run each, config [`v0`](../../analyst/configs/v0.json) (silent 720p video at `fps` 1 via the Files API, the [v0 prompt](../../analyst/prompts/v0.md), ASR transcript and telemetry as text, strict `json_schema` from `z.toJSONSchema(ModelOutput)`, `max_output_tokens` 32000). The session is the TUG-95 real-mic sync recording (40 s of screen flashes and beeps, 6 `death` events). "Voiced" adds two Piper TTS lines to the mic.

| Session | Input tokens | Output tokens (reasoning) | Cost | Model latency | Findings | Source |
|---|---|---|---|---|---|---|
| Flashes and beeps, no speech | 6,523 | 636 (621) | $0.039 | 11.9 s | 0 | [report](../../spikes/tug-99/results/flashes-report.json) |
| Voiced, second line misplaced at 0 s by a bad mix | 6,564 | 3,447 | $0.095 | — | 1 | ledger only |
| Voiced | 6,566 | 8,560 (8,213) | $0.197 | 78.0 s | 1 | [report](../../spikes/tug-99/results/voiced-report.json) |

- The API accepted the strict schema with a nullable object written as `anyOf: [object, null]`, and `max_output_tokens` 32000. [report](../../spikes/tug-99/results/voiced-report.json)
- Output tokens ranged 636–8,560 on about 6.5k input tokens, almost all of it reasoning.

### Token counting endpoint

`POST /v1/responses/input_tokens` returned 233–234 tokens for every case: the 10-minute clip at default fps and at fps 0.5, 1, 2 and 5, the silent clip, and the clip looped to 60 and 180 minutes. A real request with the same 10-minute clip billed 85,582. So the endpoint does not count video content and can't be used to estimate video cost. [measured](../../spikes/tug-93/results/count.json)

### Upload time (Files API)

| File | Size | Upload time |
|---|---|---|
| 10 min, with audio | 1.35 MB | 7.8 s |
| 10 min, silent | 0.95 MB | 8.6 s |
| 60 min (looped) | 8.1 MB | 10.6 s |
| 180 min (looped) | 24.3 MB | 30.3 s |

One upload each. [measured](../../spikes/tug-93/results/files.json)

## Open questions

- How many input tokens does a 60- or 180-minute video bill? The counting endpoint can't answer this, and only 10-minute requests have been run.
- Is the default `fps` 1? It billed the same as `fps=1` on one clip, but the docs don't say.
- How accurate are timestamps on real gameplay footage with a real voice, rather than the synthetic clip?
- How much do these numbers vary between runs? Each figure above comes from a single run.
- What drives the 13× spread in output (reasoning) tokens on the 40-second session?
