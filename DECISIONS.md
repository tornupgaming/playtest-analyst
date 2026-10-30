# Decisions

What we decided, why, and what we fall back to. The evidence lives in the [wiki](docs/wiki/index.md) and in [`spikes/`](spikes/), the small throwaway experiments behind the decisions. §5 (SAM 3.1) is still under evaluation.

## 1. Stack: one TypeScript CLI, a web viewer, Godot only records

**Decided 26 Oct (Phil).** Everything after capture is a Bun + TypeScript package at [`analyst/`](analyst/), with zod schemas. It is one CLI:

| Command | Does |
|---|---|
| `playtest finalize <session>` | Puts the raw capture on the session clock: writes `video.mp4` and `mic16k.wav` (§2) |
| `playtest analyse <session>` | Bundle → Muse Wonder (+ ASR, SAM) → `report.json` |
| `playtest annotate <session>` | Redraws the SAM key frames for an existing `report.json` (§5) |
| `playtest patch <session>` | `report.json` → Muse Spark → `patches.json`: one diff per fixable finding (§8) |
| `playtest eval <sessions…>` | Scores reports against `eval/ground_truth.json` |
| `playtest metrics <sessions…>` | Deaths, retries, time to complete and time per zone, with a before → after line for two sessions (used in the demo video) |
| `playtest serve <session>` | Serves the report viewer (`Bun.serve`) |
| `playtest export <session> <dir>` | Writes the same viewer as a static site: the files `serve` answers, with a smaller re-encode of the video. `tools/publish_pages.sh` puts it on GitHub Pages |

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

**Why.** A capture test measured video within 0–45 ms of telemetry on this clock, with no drift ([wiki](docs/wiki/capture-sync.md)). Normalising once, at the boundary, keeps the pipeline, eval and viewer free of clock maths.

## 3. Capture

- Video: external `ffmpeg -f x11grab -copyts` on the Godot window. Godot runs with `--display-driver x11` on Wayland.
- Mic: ffmpeg `-f pulse`, not Godot's `AudioEffectRecord`, which lags a real mic by ~80 ms more and drifts if the mix rate doesn't match ([wiki](docs/wiki/capture-sync.md)). Preferred: the same ffmpeg process as the video, so both share one wall clock. Measured 14–21 ms behind the beep with −0.8 ms/min drift over 120 s on a real mic ([wiki](docs/wiki/capture-sync.md)).
- Stop ffmpeg with `q` on stdin, never a kill. Stop on window close.

**Fallback.** If the in-process ffmpeg mic misbehaves, run it as a second ffmpeg process (measured: 44–53 ms on a real mic).

**Limit.** Linux/X11 only. Windows (`gdigrab`/`dshow`) and macOS (`avfoundation`) are untested.

## 4. Model input

One `POST /v1/responses` call to `muse-wonder-1.0` with:

1. the **silent** finalized video at `fps: 1`, uploaded through the Files API;
2. the think-aloud as a **timestamped transcript in text**, from `muse-voice-transcribe-1.0` (`ENDPOINTING`, ≤10-minute chunks, offset per chunk, zero-length turns dropped);
3. the telemetry as a text timeline;
4. a strict `json_schema` output format, `max_output_tokens` ≥ 16k.

**Why.** Muse Wonder places what it sees within 2 s but what it hears 5–245 s off; ASR places speech within 0.3 s. Silent video + transcript got 10/10 events within ±5 s for $0.40 per 10 minutes ([wiki](docs/wiki/muse-wonder-video.md)).

**Fallback.** If ASR fails, send the video with its audio track and accept loose speech timing.

## 5. SAM 3.1

**Decided 30 Oct (Phil): keep SAM as it is.** No extra confidence filter beyond the 0.5 below. On Phil's own think-aloud run (29 Oct), 3 of 4 findings asked for a highlight. SAM matched all 3: the pillar, the beacon star and the mushroom. Phil judged every highlight correct and well timed ([wiki](docs/wiki/sam-3-1.md)).

Muse Wonder's report names, for each finding, a key-frame time and one to three short noun phrases for the same element, best first (`highlight` in the report schema), so no extra call is needed to choose it. `sam-3.1` tries each phrasing on the frame at that time, then at 2 s before and after it, and stops at the first match with confidence ≥ 0.5: at most 9 calls, $0.0225, per finding. The finding records the phrasing and time that matched (`annotated_prompt`, `annotated_t`). We draw the top match by confidence: a yellow outline and light fill, with the rest of the frame dimmed outside a soft circle around it.

A probe of SAM 3.1 on frames from our test level ([wiki](docs/wiki/sam-3-1.md)) matched distinct objects named by how they look ("the star", "the mushroom", "the arrow sign"). It missed names based on game role ("the beacon", "the enemy"), large flat surfaces (ledges, paths) and spatial phrases ("the gap between…"). So each phrasing in `highlight.prompts` must describe the element as a concrete object, by its appearance, and the time must show it unobstructed, before the player reaches it. One call is about 1 s and $0.0025.

**Fallback.** Plain key frame, with no overlay, when SAM returns nothing or the finding names no highlight.

## 6. Eval

Six planted friction points on a dedicated test level, with the answer key frozen before analysis ([`eval/ground_truth.json`](eval/ground_truth.json)). A **planted problem** ("plant") is a spot we made hard, slow or misleading on purpose, such as an EXIT sign that points into a dead end, so we know where a player should struggle. A plant's time window comes from the session's own telemetry (time spent in its zone), so the key holds no timestamps. **Synthetic sessions**, where a scripted bot plays the level and a computer voice reads think-aloud lines, are a smoke test only, because their voice lines are written from the key.

**Category is the cause; reaction is the feeling.** A finding's `category` names what the developer would change: `difficulty`, `pacing`, `ui` or `bug`. Eval scores it. Its `reaction` is how the player felt (`confused`, `frustrated`, `bored`, `surprised`, or null), which is reported but not scored. We used to have a `confusion` category, but one problem was often both confusing and a UI fault, so the model's label and the key's disagreed on defensible readings. Plants 3 (goal text) and 5 (EXIT sign) became `ui` before the key froze, because the change planted in each is information the game shows.

## 7. Spend

Every Meta API call goes through `analyst/src/meta.ts`, which appends its cost to a ledger at `$XDG_STATE_HOME/playtest-analyst/spend.jsonl` (shared by all worktrees) and refuses to call once `PLAYTEST_SPEND_CAP_USD` is reached.

## 8. Patches

`playtest patch <session> [--report …] [--project <root>]` makes one `muse-spark-1.3` call with every finding, the files the project allows in `playtest.json` (`{"patch_allow": [globs]}`), and the scripts behind any allowlisted `.tres`, read-only, for their export docs. A strict `json_schema` limits each patch's finding id and file to the ones given. Each diff must pass `git apply --check` in the project and touch only its own file. The ones that fail get one retry with git's error, then are dropped. An answer that doesn't match the schema gets one retry with the validation error. Output: `patches.json` (`Patches` in `analyst/src/schema.ts`).

**Why Spark.** About a quarter of Muse Wonder's price per token, and the task needs no video. First run: 5 patches for 6 findings, all passing first time, $0.05 ([wiki](docs/wiki/muse-spark.md)). It also puts a second Meta model in the pipeline.

**Apply with `git apply -C0`.** Each diff is made against the same tree. In `tuning.tres` the tunables sit on neighbouring lines, so after one patch the next one's context no longer matches and plain `git apply` fails. `-C0` lets the context differ while the changed lines must still match ([wiki](docs/wiki/git-apply.md)). The Playtest dock applies with it, one commit per patch, and reverts with `git apply -R -C0` rather than `git revert`, whose 3-way merge conflicts on the same neighbouring lines.

**Fallback.** If Spark's diffs start failing, set `PATCH_MODEL` in `analyst/src/patch.ts` to `muse-wonder-1.0`.

