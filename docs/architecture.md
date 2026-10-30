# How the system works

This guide sits a level below the README. It explains what each piece of code does, what it reads and writes, and how a session moves through the system. It also covers what is built today and what the end state looks like. File references point at the code, so you can jump from a diagram to the code it describes.

Two rules shape everything:

1. **The session bundle is the contract** ([DECISIONS.md §2](../DECISIONS.md)). Godot writes a folder, and everything after that reads only the folder.
2. **One clock.** `t` is seconds since the recorder started. `finalize` moves every stream onto that clock once, so nothing downstream does clock maths.

---

## 1. The big picture (current state)

```mermaid
flowchart LR
  subgraph Godot["Godot 4.7 project"]
    direction TB
    Game["Your game<br/>level/level.gd calls<br/>PlaytestTelemetry.event()"]
    Tel["PlaytestTelemetry autoload<br/>telemetry.gd"]
    Rec["PlaytestRecorder autoload<br/>recorder.gd"]
    Dock["Playtest dock (editor)<br/>dock.gd + patches.gd + diff_view.gd"]
    Game --> Tel
  end

  FF["ffmpeg<br/>x11grab + pulse<br/>one process"]
  Bundle[("sessions/&lt;id&gt;/<br/>the bundle")]

  subgraph CLI["analyst/ — Bun + TypeScript CLI"]
    direction TB
    Fin["finalize"]
    Ana["analyse"]
    Pat["patch"]
    Srv["serve → viewer/"]
    Dev["eval · sweep · metrics · spend<br/>(developer tools)"]
  end

  subgraph Meta["Meta Model API (via meta.ts only)"]
    direction TB
    ASR["muse-voice-transcribe-1.0"]
    W["muse-wonder-1.0"]
    SAM["sam-3.1"]
    SP["muse-spark-1.3"]
  end

  Ledger[("spend.jsonl<br/>~/.local/state/playtest-analyst")]
  Repo[("your git repo<br/>playtest-fix: commits")]

  Rec -->|spawns| FF -->|screen.mkv| Bundle
  Tel -->|events.jsonl| Bundle
  Rec -->|session.json| Bundle
  Rec -.->|"bun cli.ts finalize"| Fin
  Dock -.->|"bun cli.ts analyse / serve / patch"| CLI
  Dock <-->|"debugger channel<br/>playtest_analyst:*"| Rec

  Bundle --> Fin --> Bundle
  Bundle --> Ana --> Bundle
  Bundle --> Pat --> Bundle
  Bundle --> Srv

  Ana --> ASR & W & SAM
  Pat --> SP
  Meta -.-> Ledger

  Dock -->|"git apply -C0 + commit"| Repo
```

**What runs where**

| Process | Code | Lifetime |
|---|---|---|
| Godot editor | `addons/playtest_analyst/plugin.gd`, `dock.gd` | While the editor is open |
| The game being playtested | `recorder.gd`, `telemetry.gd` (autoloads) + your game | One session |
| ffmpeg recorder | spawned by `recorder.gd` with a watchdog shell wrapper | One session; stopped with `q` on stdin |
| `bun analyst/src/cli.ts <cmd>` | `analyst/src/commands/*.ts` | One command; `serve` runs until killed |
| Viewer | `analyst/viewer/` in the browser, served by `serve` | While the tab is open |

The dock and the recorder never call each other directly. They talk over Godot's **debugger channel**: the dock is an `EditorDebuggerPlugin`, and the game sends `playtest_analyst:started` / `stopped` messages back. Every CLI call from Godot goes through the user's **login shell** (`recorder.gd` → `cli_command()`), so it picks up `META_MODEL_API_KEY` from `~/.zshenv`.

---

## 2. One session, end to end

```mermaid
sequenceDiagram
  autonumber
  actor Dev as Developer
  participant Dock as Playtest dock
  participant Game as Game + autoloads
  participant FF as ffmpeg
  participant CLI as analyst CLI
  participant Meta as Meta API
  participant Git as git repo

  Dev->>Dock: Record session
  Dock->>Game: play main scene with --record
  Game->>FF: start x11grab + pulse → screen.mkv
  Game->>Game: PlaytestTelemetry.start() → events.jsonl
  Game-->>Dock: started (debugger message)
  Note over Game: Player plays and thinks aloud.<br/>Game emits death, zone_enter, …
  Dev->>Game: F9 or close window
  Game->>FF: "q" on stdin
  Game->>Game: write session.json (bundle now complete)
  Game->>CLI: finalize (background)
  CLI->>CLI: video.mp4 + mic16k.wav aligned to t=0
  Game-->>Dock: stopped

  Dev->>Dock: Analyse
  Dock->>CLI: analyse <bundle>
  CLI->>Meta: ASR per ≤10-min chunk (retried on 429 / 5xx)
  CLI->>Meta: Files API upload (silent video, or with audio if ASR failed)
  CLI->>Meta: one /v1/responses to Muse Wonder<br/>video + transcript + telemetry
  Meta-->>CLI: findings JSON (strict schema)
  loop each finding with a highlight (4 at a time)
    CLI->>Meta: SAM 3.1 on key frame (≤9 tries)
  end
  CLI->>CLI: write report.json + analysis/frames/*.png

  Dev->>Dock: Open report
  Dock->>CLI: serve <bundle> → opens browser

  Dev->>Dock: Propose fixes
  Dock->>CLI: patch <bundle> --project <root>
  CLI->>Meta: one /v1/responses to Muse Spark
  CLI->>Git: git apply --check each diff
  CLI->>CLI: write patches.json
  Dev->>Dock: Apply (per patch)
  Dock->>Git: git apply -C0 + commit "playtest-fix: …"

  Note over Dev,Git: Next build: record again, then<br/>analyse --previous old/report.json (CLI only today)
```

---

## 3. The bundle: who writes and who reads each file

```mermaid
flowchart TB
  subgraph Written_by_Godot["Written by the game"]
    SJ["session.json<br/>SessionMeta"]
    EV["events.jsonl<br/>TelemetryEvent per line"]
    MKV["screen.mkv<br/>raw video + mic"]
    INC["INCOMPLETE<br/>only if it ended badly"]
  end
  subgraph Written_by_finalize["Written by finalize"]
    MP4["video.mp4<br/>H.264 ≤720p + AAC, t=0"]
    WAV["mic16k.wav<br/>16 kHz mono, t=0"]
  end
  subgraph Written_by_analyse["Written by analyse"]
    REP["report.json<br/>Report"]
    AN["analysis/<br/>transcript.json, upload.mp4,<br/>request-N / response-N.json,<br/>frames/&lt;config&gt;/&lt;id&gt;.png"]
  end
  subgraph Written_by_patch["Written by patch"]
    PJ["patches.json<br/>Patches"]
  end

  SJ & MKV --> F(["finalize"]) --> MP4 & WAV
  SJ & EV & MP4 & WAV --> A(["analyse"]) --> REP & AN
  REP --> P(["patch"]) --> PJ
  SJ & EV & REP & MP4 & AN --> S(["serve / viewer"])
  PJ --> D(["dock: Apply / Revert"])
  REP & EV & SJ --> E(["eval · metrics"])
```

Every arrow into the CLI goes through a zod parser in `analyst/src/schema.ts`. That file is the one place to look up a file's shape. `bundle.ts → readSession()` is the boundary for `session.json` and `events.jsonl`, and it sorts events by `t` once, because `input_idle` lines are written late.

---

## 4. The analyst CLI: modules and dependencies

```mermaid
flowchart LR
  cli["cli.ts<br/>globs commands/*.ts"]

  subgraph commands["commands/ (thin: parse args, call one function, print)"]
    cA["analyse"] ; cAn["annotate"] ; cF["finalize"] ; cP["patch"]
    cS["serve"] ; cX["export"] ; cE["eval"] ; cSw["sweep"] ; cM["metrics"] ; cSp["spend"]
  end

  subgraph core["src/ (the logic)"]
    analyse["analyse.ts<br/>orchestrates one run"]
    input["input.ts<br/>PURE: bundle → request body"]
    compare["compare.ts<br/>cross-build memory"]
    annotate["annotate.ts<br/>SAM + draw highlight"]
    patch["patch.ts<br/>Spark + git apply --check"]
    finalize["finalize.ts<br/>ffmpeg alignment"]
    eval["eval.ts<br/>PURE: report × ground truth → score"]
    metrics["metrics.ts<br/>PURE: events → deaths, time per zone"]
    sweep["sweep.ts<br/>configs × sessions"]
    bundle["bundle.ts<br/>readSession()"]
    config["config.ts<br/>AnalysisConfig"]
    meta["meta.ts<br/>ONLY door to the Meta API<br/>spend cap + ledger"]
    schema["schema.ts<br/>zod contracts"]
  end

  viewer["viewer/app.ts<br/>browser; imports schema types"]

  cli --> commands
  cA --> analyse & compare & config
  cAn --> annotate
  cF --> finalize
  cP --> patch
  cS --> bundle
  cS -.serves.-> viewer
  cX --> bundle
  cX -.builds.-> viewer
  cE --> eval & bundle
  cSw --> sweep & config
  cM --> metrics & bundle
  cSp --> meta

  analyse --> finalize & bundle & input & compare & annotate & meta
  sweep --> analyse & eval & finalize & bundle
  annotate --> meta
  patch --> meta
  input & compare & eval & patch & bundle & analyse --> schema
  viewer -.types.-> schema
```

How to read it:

- **`commands/` are shells.** Each exports `description` and `run(argv)`. To add a command, drop in a new file; `cli.ts` finds it with a glob.
- **The pure modules** are `input.ts`, `eval.ts`, `metrics.ts`, and `comparison()` in `compare.ts`. Data goes in and data comes out, so this is where the unit tests live (`*.test.ts`).
- **`meta.ts` is the only way out to the network.** `respond()` (Responses API), `uploadFile()` (Files API) and `metaFetch()` (ASR) all check the spend cap before the call and append to the ledger after it. `metaFetch()` retries a rate limit (429), a server error (5xx) or a timeout 3 times, 2, 4 then 8 s apart; the OpenAI SDK retries the other two itself. SAM goes through `respond()` too and is billed per image.
- **Configs** (`analyst/configs/*.json`) are plain data: prompt file, fps, and whether to include the transcript or telemetry. `sweep` runs every config on every session, so prompt changes can be compared.

---

## 5. Inside `analyse()`

`analyst/src/analyse.ts`

```mermaid
flowchart TB
  start(["analyse(dir, config, out, previous?)"])
  fin{"video.mp4 and<br/>mic16k.wav exist?"}
  doFin["finalize(dir)"]
  read["readSession → meta, events"]
  up["strip audio → upload.mp4<br/>uploadFile()"]
  asr["split mic16k.wav into ≤600 s chunks<br/>POST /asr/transcribe each<br/>(up to 3 retries on 429, 5xx, timeout)<br/>sessionTurns() → transcript.json"]
  asrok{"ASR ok?"}
  fallback["fallback (DECISIONS §4):<br/>upload video WITH audio,<br/>include_transcript = false"]
  req["modelRequest(): prompt + input_video @fps<br/>+ transcript text + telemetry text<br/>+ compare text if --previous"]
  wonder["respond() → Muse Wonder<br/>strict json_schema"]
  valid{"parses against<br/>ModelOutput?"}
  retry{"attempt 2<br/>used?"}
  fail(["throw: invalid twice"])
  ids["sort by t_start, assign f1…fN<br/>+ comparison() if --previous"]
  sam["annotate(): per finding with highlight<br/>try each prompt × {t, t−2, t+2}<br/>first mask ≥ 0.5 confidence wins<br/>draw outline + spotlight → PNG"]
  write(["write report.json"])

  start --> fin
  fin -- no --> doFin --> read
  fin -- yes --> read
  read --> asr --> asrok
  asrok -- no --> fallback --> req
  asrok -- yes --> up --> req
  req --> wonder --> valid
  valid -- yes --> ids
  valid -- no --> retry
  retry -- no --> req
  retry -- yes --> fail
  ids --> sam --> write
```

The validation error from attempt 1 is appended to the prompt for attempt 2. `patch` does the same when Muse Spark's answer doesn't match its schema. In compare mode, the output schema narrows `previous_id` to an enum of the previous report's ids, so the model can't make up a match.

---

## 6. The Godot side

```mermaid
flowchart TB
  subgraph Editor["Editor process"]
    plugin["plugin.gd (EditorPlugin)<br/>adds dock + debugger plugin,<br/>registers both autoloads"]
    dock["dock.gd (EditorDock)<br/>Record · session list · Analyse ·<br/>Open report · Propose fixes ·<br/>patch list · Apply · Revert"]
    patches["patches.gd (RefCounted)<br/>reads patches.json, works out which<br/>are applied from git log,<br/>apply / revert as commits"]
    diff["diff_view.gd<br/>coloured unified diff"]
    plugin --> dock --> patches & diff
  end

  subgraph GameProc["Game process"]
    rec["recorder.gd — PlaytestRecorder<br/>--record or F9 → start()<br/>F9 / window close / dock → stop()"]
    tel["telemetry.gd — PlaytestTelemetry<br/>event(type, data) → one JSONL line<br/>adds zone_exit.dwell, input_idle"]
    level["level/level.gd<br/>reads level/tuning.tres at _ready()<br/>emits deaths, zones, objectives"]
    level --> tel
    rec -->|"start(dir, t0)"| tel
  end

  dock <-->|"EditorDebuggerPlugin<br/>start / stop / started / stopped"| rec
  dock -.->|"OS.execute_with_pipe<br/>via login shell"| cli["bun analyst/src/cli.ts"]
  rec -.->|"finalize on stop"| cli
  patches -->|"git apply -C0 · git commit"| git[("project git")]
  cfg["playtest.json<br/>patch_allow globs"] --> patches
  cfg --> cli
```

`playtest.json` is read on both sides of the patch flow. `patch.ts` limits Muse Spark to the allowlisted files, and `patches.gd` checks the allowlist again before it applies a diff. It has to, because `patches.json` is model output read from disk.

### Lifecycle of one patch

```mermaid
stateDiagram-v2
  [*] --> Proposed: Muse Spark writes a diff
  Proposed --> Rejected: git apply --check fails<br/>or touches another file
  Rejected --> Proposed: one retry with git's error
  Rejected --> Dropped: fails again
  Proposed --> Listed: written to patches.json
  Listed --> Applied: Apply (clean tree, allowlisted)<br/>git apply -C0 + "playtest-fix:" commit
  Applied --> Listed: Revert<br/>git apply -R -C0 + "Revert" commit
  Dropped --> [*]
```

The dock works out whether a patch is applied from **git history** (`playtest-fix:` commits that haven't been reverted). It stores no state of its own, so the state can't drift from the repo.

---

## 7. The developer loop: measuring the analyser

This loop isn't part of the product. It's how prompts and configs get tuned against a known answer key. The test level has six **planted problems** ("plants"): spots we made hard, slow or misleading on purpose. The answer key lists them, and **synthetic sessions**, where a scripted bot plays the level and Piper TTS reads think-aloud lines, give the loop something to score without a human player.

```mermaid
flowchart LR
  tun["eval/tuning_planted.tres<br/>eval/tuning_clean.tres"] -->|cp| live["level/tuning.tres"]
  live --> level["test level"]
  bot["tools/make_synthetic.sh<br/>synth.gd bot + Piper TTS"] --> level
  human["real playtester"] --> level
  level --> bundles[("sessions/…")]
  bundles --> sweep["playtest sweep<br/>configs × sessions"]
  cfgs["analyst/configs/*.json<br/>analyst/prompts/*.md"] --> sweep
  sweep --> reports["report.json per run"]
  gt["eval/ground_truth.json<br/>6 plants, no timestamps"] --> eval
  reports --> eval["eval.ts<br/>plant windows from the session's<br/>own zone telemetry"]
  eval --> readme["eval/sweeps/&lt;date&gt;/README.md<br/>recall · precision · cost"]
```

`eval/` has a `.gdignore`, so Godot never imports the answer key, and the key can't end up in a recording.

---

## 8. Current state vs end state

What the CLAUDE.md brief asked for, against what the code does today and what was still open (as of 27 Oct). Round 1 is the first set of real playtests, on the level with its planted problems; round 2 is the next set, on the build after the suggested fixes are applied.

```mermaid
flowchart LR
  classDef done fill:#d3f9d8,stroke:#2b8a3e,color:#000
  classDef review fill:#fff3bf,stroke:#e67700,color:#000
  classDef todo fill:#ffe3e3,stroke:#c92a2a,color:#000,stroke-dasharray:4 3

  subgraph Product["Product loop"]
    R["1 Record<br/>screen + mic + telemetry"]:::review
    A["2 Analyse<br/>Muse Wonder"]:::review
    N["3 Annotate<br/>SAM 3.1 — 3 of 5 hit"]:::review
    F["4 Fix<br/>Spark patches + 1-click apply"]:::review
    M["5 Remember<br/>--previous compare"]:::review
    R --> A --> N --> F --> R2["record next build"] --> M
  end

  subgraph Evidence["Evidence the loop works"]
    SYN["Synthetic sweep<br/>24 runs, precision 1.00"]:::done
    COLD["Baseline cold test +<br/>freeze ground truth"]:::todo
    RD1["Round 1 real playtests"]:::todo
    TUNE["Prompt / fps tuning on<br/>real sessions"]:::todo
    RD2["Round 2 on patched build"]:::todo
    SYN --> COLD --> RD1 --> TUNE --> RD2
  end

  subgraph Ship["Submission"]
    VID["Demo video edit"]:::todo
    SUB["Submit by 2 AM UK Thu 5 Nov"]:::todo
    VID --> SUB
  end

  RD1 --> VID
  RD2 --> VID
```

Key: green = done; amber = built, in review; red dashed = not started.

### The gaps, concretely

| Area | Today | End state | Where the change would go |
|---|---|---|---|
| Evidence | Synthetic bot sessions, whose voice lines were written from the answer key, plus one think-aloud run by the developer. | Real round 1 and round 2 playtests, scored by `eval` | `sessions/`, `eval/sweeps/` |
| Ground truth | `frozen_at` not set yet | Frozen after the cold test, before any real analysis | `eval/ground_truth.json` |
| Annotation | Decided: keep SAM, with a plain frame when nothing matches. On the developer's own think-aloud run, all 3 highlights asked for landed on the right object. On synthetic planted-voice, 3 of 5 matched, one of them on the wrong platform | Done | `annotate.ts`, prompt `highlight` guidance |
| Remember | CLI flag only (`analyse --previous … --patches …`); the viewer shows the banner and chips | The demo video uses the comparison banner, if it ships | `dock.gd` would need a "compare with" picker |
| Metrics | `playtest metrics` is CLI only | Before/after table for the demo video | Captured from the CLI; no dock work needed |
| Platform | Linux + X11/XWayland only | Same for the hackathon (DECISIONS §3 limit) | `recorder.gd → _ffmpeg_args()` for other OSes |

On the product side, all five stages from the brief are now built, including both stretch goals. Every amber box is code waiting on review, not missing code. Between today and the end state the remaining work is **evidence and submission**: real playtests, tuning against them, and the video.
