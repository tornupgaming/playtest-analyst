# TUG-93: Muse Wonder video input. Findings

Measured on 2026-10-26 against `api.meta.ai/v1`, `muse-wonder-1.0`, default reasoning effort, one run per variant. Raw results are in `results/`.

## Decision

**Send silent MP4 video at 1 fps, plus a timestamped transcript from Meta's ASR (`muse-voice-transcribe-1.0`, `ENDPOINTING` mode) as text.** Upload the video through the Files API and reference it by `file_id`.

Muse Wonder places what it *sees* within 2 s but places what it *hears* 5–245 s off. ASR places speech within 0.3 s. Together they put all 10 test events within ±5 s, at the lowest cost of any variant tried.

## Results: 10-minute clip, 10 known events

| Variant | Input tok | Output tok | Cost | Latency | Within ±5 s | Mean abs error |
|---|---|---|---|---|---|---|
| Video + audio, default fps | 85,582 | 6,416 | $0.47 | 75 s | 7/10 | 6.4 s |
| Video + audio, `fps=1` | 85,582 | 7,418 | $0.49 | 100 s | 6/10 | 51.9 s |
| Video + audio, `fps=0.2` | 23,182 | 14,561 | $0.38 | 169 s | 2/10 (7 found) | 76.9 s |
| Silent video, `fps=1` (control) | 78,079 | 3,742 | $0.39 | 57 s | 6/10 (no speech found) | 0.3 s |
| **Silent video, `fps=1` + ASR transcript** | 78,140 | 4,592 | **$0.40** | **65 s** | **10/10** | **0.1 s** |

Speech errors per line (truth at 90 / 260 / 400 / 520 s):

| Variant | Speech error |
|---|---|
| Video + audio, default fps | +25, −15, −15, −5 s |
| Video + audio, `fps=1` | −78, −22, −170, −245 s |
| ASR alone (`ENDPOINTING`) | −0.3, −0.1, 0.0, −0.1 s |

Visual events were within 2 s in every run at 1 fps.

## Answers

**Formats and size.** Video must be `video/mp4`. The limit is 50 MB inline, or 1 GiB per file through the Files API (`POST /v1/files`, `purpose=user_data`). Team storage is capped at 100 GiB, and files don't expire unless you set `expires_after`. Upload of a 1–24 MB file took 8–30 s. ([docs][fh])

**Tokens.**
- The server samples at 1 fps by default. `fps=1` gave exactly the same input count as the default, and `fps=0.2` cut it by about 4×.
- One 720p frame is about 130 tokens. The audio track is about 12.5 tokens/s (7.5k per 10 min).
- `usage` has no per-modality split. These rates come from differencing the runs above.
- `POST /v1/responses/input_tokens` **ignores video**: it returned 234 for every clip from 10 to 180 min. It can't be used for budgeting.

**Cost for a 10-minute session.**
- About $0.40 at 1 fps. Input is about 78k tokens ($0.31); output is about 4–7k tokens ($0.09–0.15), mostly reasoning.
- "Native" 30 fps would be about 2.3M tokens. That is more than the 1M context, so it can't be sent. This is extrapolated, not run.
- ASR pricing isn't published on the pricing page.

**Max length.** No duration limit is published. Three bounds apply:
- **Context:** 1,048,576 tokens at about 130 tokens/s of silent 1 fps video is about 130 min, less prompt and telemetry.
- **File size:** 1 GiB at a 2.5 Mbps recording is about 57 min. Lower the bitrate for longer sessions.
- **ASR: 10 min and 32 MB per request** (16 or 24 kHz mono WAV). This binds first. Sessions over 10 minutes need the audio cut into ≤10-minute chunks, with each chunk's timestamps offset by its start time.

**Latency, end to end.** About 2 minutes for a 10-minute session. Upload (about 8 s) and ASR (about 57 s) can run in parallel. Analysis (about 65 s) has to wait for the transcript. Reasoning tokens drive most of the variance: 57–169 s across runs.

**Timestamp accuracy (±5 s).** Visual events: yes, within 2 s at 1 fps. Speech heard from the audio track: no. Speech from ASR: yes, within 0.3 s. Below 1 fps, events shorter than the sampling gap are missed, so don't go under 1 fps.

**Audio track.** The model does hear it: with audio it reported all 4 spoken lines, and the silent control found none. But it can't place them in time, so the separate transcript is needed for timing.

## Implications for other issues

- **TUG-98 recorder:** write the video as H.264 MP4 and keep the mic as a separate 16 kHz mono WAV. That WAV is exactly what ASR wants, so there's no need to mux and demux. Godot's Movie Maker doesn't write MP4, so the recorder needs an ffmpeg step. Target 720p at about 2–2.5 Mbps.
- **TUG-99 pipeline:**
  1. Upload the video (`expires_after` 1 day) and ASR the WAV in ≤10-minute chunks, in parallel.
  2. Make one `/v1/responses` call with `input_video` (`fps` 1), the transcript text, the telemetry text and a `text.format` json_schema.
  3. Set `max_output_tokens` to at least 16k, because reasoning shares that budget.
  4. Drop zero-length ASR turns; endpointing emits tail fragments like "all.".
- **Demo shot 5:** expect about 2 min and about $0.40 for a 10-minute session, not the placeholder 48 s.

## Caveats

- Each variant ran once, and latency and speech error varied a lot between the two runs with audio.
- The clip is synthetic, with flat-colour UI and clean TTS. Real gameplay has more visual detail per frame, and real think-aloud has noise and overlapping speech. Recheck accuracy on round 1 footage (TUG-106).
- Video token counts may depend on resolution. Only 720p was measured.

## Test clip

`build_clip.py` makes a 10-minute 720p30 clip with no on-screen clock, so the model has to timestamp from the video itself. It has 6 visual events (YOU DIED ×2, CHECKPOINT, KEY, PAUSED, LEVEL COMPLETE, each 3 s) and 4 spoken think-aloud lines (Piper TTS) with nothing on screen. Events are 45–90 s apart.

## Run it

```sh
python -m venv venv && venv/bin/pip install piper-tts httpx
venv/bin/python -m piper.download_voices en_US-lessac-medium
venv/bin/python build_clip.py /tmp/tug93/clip en_US-lessac-medium.onnx
export META_MODEL_API_KEY=...
venv/bin/python probe.py count      /tmp/tug93/clip              # shows input_tokens ignores video
venv/bin/python probe.py transcribe /tmp/tug93/clip              # ASR -> transcript.json, scored
venv/bin/python probe.py analyze    /tmp/tug93/clip native       # default fps
venv/bin/python probe.py analyze    /tmp/tug93/clip native 1
venv/bin/python probe.py analyze    /tmp/tug93/clip native 0.2
venv/bin/python probe.py analyze    /tmp/tug93/clip noaudio 1
venv/bin/python probe.py analyze    /tmp/tug93/clip noaudio 1 --transcript   # chosen strategy
```

Total spend for the runs above: $2.13 for Muse Wonder, plus ASR (unpriced).

[fh]: https://dev.meta.ai/docs/file-handling
