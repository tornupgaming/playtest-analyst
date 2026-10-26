# Decisions

What we decided, why, and what we fall back to. The evidence lives in the [wiki](docs/wiki/index.md) and the spike write-ups. Draft for TUG-96 (TUG-119); Phil approves.

## 1. Stack: one TypeScript CLI, a web viewer, Godot only records

**Decided 26 Oct (Phil).** Everything after capture is a Bun + TypeScript package at [`analyst/`](analyst/), with zod schemas. It is one CLI:

| Command | Does |
|---|---|
| `playtest finalize <session>` | Puts the raw capture on the session clock: writes `video.mp4` and `mic16k.wav` (§2) |
| `playtest analyse <session>` | Bundle → Muse Wonder (+ ASR, SAM) → `report.json` |
| `playtest annotate <session>` | Redraws the SAM key frames for an existing `report.json` (§5) |
| `playtest eval <sessions…>` | Scores reports against `eval/ground_truth.json` |
| `playtest serve <session>` | Serves the report viewer (`Bun.serve`) |

Godot records the session and shells out to the CLI. No Electron, no Elysia, no Effect.

**Why.** The Meta Model API is driven with the official `openai` SDK ([docs](https://dev.meta.ai/docs/models)), so TypeScript needs no hand-written client. The viewer is a web page, so the pipeline, eval and viewer share one set of types. GDScript is the wrong place for media processing and inference, and keeping it out means another engine only needs a recorder that writes the bundle. Effect's strengths (typed errors, layers, structured concurrency) pay off in long-lived services; this is a short linear pipeline.

**Fallback.** None needed; this is the low-risk option.

## 2. The session bundle is the contract

Any recorder (Godot today, other engines later) writes a folder. Everything downstream reads only this folder.

```
sessions/<id>/
  session.json   # metadata + clock anchors (schema: analyst/src/schema.ts → SessionMeta)
  events.jsonl   # telemetry, one JSON object per line: {t, type, player_pos, data}
  screen.mkv     # raw capture as recorded (any container ffmpeg reads)
  mic.wav        # raw mic, if recorded separately from the video
  # written by `playtest finalize`:
  video.mp4      # H.264 ≤720p + AAC mic. t=0 is session t=0.
  mic16k.wav     # 16 kHz mono s16. t=0 is session t=0. What ASR wants.
  # written by `playtest analyse`:
  report.json
  analysis/      # intermediate files: transcript.json, upload.mp4, request/response dumps,
                 # frames/<config>/<finding id>.png (annotated key frames, §5)
```

**One clock.** `t` everywhere is seconds since the recorder started, read from `Time.get_ticks_usec()` in Godot. `session.json` anchors each raw stream to that clock (`video_start`, `audio_start`: the session time of the file's first frame or sample, or omitted to derive from the file's wall-clock pts minus `t0_unix`). `finalize` applies the offsets once, so nothing after it handles offsets again.

**Why.** TUG-95 measured video within 0–45 ms of telemetry on this clock, with no drift ([wiki](docs/wiki/capture-sync.md)). Normalising once, at the boundary, keeps the pipeline, eval and viewer free of clock maths.

## 3. Capture (TUG-95)

- Video: external `ffmpeg -f x11grab -copyts` on the Godot window. Godot runs with `--display-driver x11` on Wayland.
- Mic: ffmpeg `-f pulse`, not Godot's `AudioEffectRecord`, which lags a real mic by ~80 ms more and drifts if the mix rate doesn't match ([wiki](docs/wiki/capture-sync.md)). Preferred: the same ffmpeg process as the video, so both share one wall clock (not yet measured).
- Stop ffmpeg with `q` on stdin, never a kill. Stop on window close.

**Fallback.** If the in-process ffmpeg mic misbehaves, run it as a second ffmpeg process (measured: 44–53 ms on a real mic).

**Limit.** Linux/X11 only. Windows (`gdigrab`/`dshow`) and macOS (`avfoundation`) are untested.

## 4. Model input (TUG-93)

One `POST /v1/responses` call to `muse-wonder-1.0` with:

1. the **silent** finalized video at `fps: 1`, uploaded through the Files API;
2. the think-aloud as a **timestamped transcript in text**, from `muse-voice-transcribe-1.0` (`ENDPOINTING`, ≤10-minute chunks, offset per chunk, zero-length turns dropped);
3. the telemetry as a text timeline;
4. a strict `json_schema` output format, `max_output_tokens` ≥ 16k.

**Why.** Muse Wonder places what it sees within 2 s but what it hears 5–245 s off; ASR places speech within 0.3 s. Silent video + transcript got 10/10 events within ±5 s for $0.40 per 10 minutes ([wiki](docs/wiki/muse-wonder-video.md)).

**Fallback.** If ASR fails, send the video with its audio track and accept loose speech timing.

## 5. SAM 3.1 (TUG-94, pending)

Muse Wonder's report names, for each finding, a key-frame time and a short noun phrase to highlight (`highlight` in the report schema), so no extra call is needed to choose it. `sam-3.1` segments that phrase on the extracted frame and we draw the top match by confidence: a yellow outline and light fill, with the rest of the frame dimmed outside a soft circle around it (TUG-104).

The probe (TUG-118, [wiki](docs/wiki/sam-3-1.md)) matched distinct objects named by how they look ("the star", "the mushroom", "the arrow sign"). It missed names based on game role ("the beacon", "the enemy"), large flat surfaces (ledges, paths) and spatial phrases ("the gap between…"). So `highlight.prompt` must describe the element as a concrete object, by its appearance. One call is about 1 s and $0.0025.

**Fallback.** Plain key frame, with no overlay, when SAM returns nothing. Phil makes the final call in TUG-94.

## 6. Eval

Six planted friction points on a dedicated test level, with the answer key frozen before analysis ([`eval/ground_truth.json`](eval/ground_truth.json), TUG-90). A plant's time window comes from the session's own telemetry (time spent in its zone), so the key holds no timestamps. Synthetic sessions (TUG-120) are a smoke test only, because their voice lines are written from the key.

## 7. Spend

Every Meta API call goes through `analyst/src/meta.ts`, which appends its cost to a ledger at `$XDG_STATE_HOME/playtest-analyst/spend.jsonl` (shared by all worktrees) and refuses to call once `PLAYTEST_SPEND_CAP_USD` is reached.
