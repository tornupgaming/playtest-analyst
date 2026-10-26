---
title: Meta ASR (muse-voice-transcribe)
updated: 2026-10-26
sources:
  - https://dev.meta.ai/docs/api-reference/voice/transcribe
  - https://dev.meta.ai/docs/api-reference/voice/schemas
  - https://dev.meta.ai/docs/speech-to-text
  - spikes/tug-93/probe.py
  - spikes/tug-93/results/asr.json
  - spikes/tug-93/results/asr-raw-endpointing.json
---

# Meta ASR (`muse-voice-transcribe-1.0`)

Speech-to-text on the Meta Model API. Used to give [Muse Wonder](muse-wonder-video.md) accurate speech timestamps.

## Documented

| Fact | Source |
|---|---|
| `POST /v1/asr/transcribe`, `multipart/form-data` with two parts: `request` (settings JSON) and `audio` (the clip). Realtime streaming is at `wss://api.meta.ai/v1/asr/realtime`. | [docs](https://dev.meta.ai/docs/api-reference/voice/transcribe) |
| Audio must be WAV and at most 10 minutes. A body over 32 MB returns HTTP 413. | [docs](https://dev.meta.ai/docs/api-reference/voice/transcribe) |
| `audioEncoding` is required and `WAV` is the only value: mono integer PCM at 16 kHz or 24 kHz. | [docs](https://dev.meta.ai/docs/api-reference/voice/schemas) |
| `mode`: `PUSH_TO_TALK` (default) treats the clip as one turn and returns an empty `turns`. `ENDPOINTING` returns one turn per detected speech segment. `DIARIZATION` does the same and adds a `speaker` label. | [docs](https://dev.meta.ai/docs/api-reference/voice/schemas) |
| Each turn has `turnId`, `startMs`, `endMs` and `transcript`. `startMs` and `endMs` are "not a precise acoustic boundary". | [docs](https://dev.meta.ai/docs/api-reference/voice/schemas) |
| Timestamps are turn-level, not word-level. | [docs](https://dev.meta.ai/docs/speech-to-text) |
| The `Accept` header picks the response: JSON (default), `text/event-stream`, or `text/plain` (one turn per line). | [docs](https://dev.meta.ai/docs/api-reference/voice/transcribe) |
| Other optional fields: `keywords`, `languageBias`, and `partialMode` / `emitAudioProgress` (streaming only). | [docs](https://dev.meta.ai/docs/api-reference/voice/schemas) |
| Exceeding the concurrency or hourly session limit returns HTTP 429. The limits themselves aren't stated. | [docs](https://dev.meta.ai/docs/api-reference/voice/transcribe) |

## Measured

**Conditions:** 2026-10-26, the 4 TTS lines from the TUG-93 test clip (10 minutes, Piper `en_US-lessac-medium`, otherwise silent), resampled to a 16 kHz mono WAV of 19.2 MB, `mode: ENDPOINTING`. Request shape is in [probe.py](../../spikes/tug-93/probe.py).

| Turns found | Start time error | Text | Latency | Source |
|---|---|---|---|---|
| 4/4 | −0.3, −0.1, 0.0, −0.1 s | All 4 word for word | 57.3 s | [asr.json](../../spikes/tug-93/results/asr.json) |

- The raw response had 6 turns, not 4. Two were zero-length (`startMs` = `endMs`) repeats of the previous turn's last word ("all.", "possible?"), 80 ms after it ended. The top-level `transcript` includes the repeats. [raw](../../spikes/tug-93/results/asr-raw-endpointing.json)
- `asr.json` holds the turns after dropping those with `endMs` ≤ `startMs`. [probe.py](../../spikes/tug-93/probe.py)

## Open questions

- Accuracy on a real microphone with game audio and background noise.
- Price per minute of audio. The [pricing page](https://dev.meta.ai/docs/pricing-rate-limits) doesn't list it.
- The concurrency and hourly session limits.
