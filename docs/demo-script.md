# Demo script

The demo is what judges see. Every feature below earns its place by appearing in a shot. Anything not in a shot is on the [cut list](#cut-list).

**Length.** The rules don't set a video length yet (TUG-88), and the brief says 2 minutes. The script runs 3:00. The **2:00** column trims each shot instead of dropping any, so the arc survives either limit. Recheck when the submission form is visible.

**Judging weights it's written for:** Impact 30%, Meta tooling 25%, Demo 25%, Technical depth 20%. The Meta tooling score rewards going "beyond a basic integration", so the VO names what each Meta model does, in the shot where it does it.

`[brackets]` mark numbers to fill in from real runs. Never fake them: shot 8 shows the miss as well as the hits.

## Shots

| # | 3:00 | 2:00 | Shot | Voiceover (VO) | Depends on | If that feature is cut |
|---|---|---|---|---|---|---|
| 1 | 0:00 (12s) | 8s | **Problem.** A 15-minute playtest recording scrubbed at 1×. A counter shows "unwatched footage: 3h 40m". | "Solo devs record playtests. Then nobody watches them. I've got hours of my friends playing my game that I've never reviewed." | Round 1 footage (TUG-106) | — |
| 2 | 0:12 (10s) | 5s | **Title card.** "Playtest Analyst: a Godot plugin." Muse Wonder and SAM 3.1 named in text (logos only if Meta supplies approved files). | "Playtest Analyst records the session, Muse Wonder watches it, and SAM 3.1 points at the problem." | — | — |
| 3 | 0:22 (15s) | 8s | **Test level.** Editor flythrough of the level. Six numbered pins, labels hidden. | "To check it properly, I built a level with six planted problems. I know exactly what's wrong. Let's see if it does." | Test level + `ground_truth.json` (TUG-90) | — |
| 4 | 0:37 (15s) | 10s | **Record.** Click **Start session** in the editor dock. A tester plays, with a mic waveform and a telemetry ticker beside the game (`death`, `input_idle`, `zone_enter`). | "One click records the screen, the player thinking aloud, and gameplay telemetry, all on one clock." | Recorder (TUG-98), telemetry (TUG-97), round 1 footage (TUG-106) | — (core) |
| 5 | 0:52 (8s) | 7s | **Analyse.** Click **Analyse**. The status line reads "Muse Wonder · [11] min video + think-aloud audio + [214] events · one request". It finishes with "[48]s · $[0.xx]". | "The whole session goes to Muse Wonder in one request: video, voice and telemetry together." | Pipeline (TUG-99), cost/latency numbers (TUG-93) | — (core) |
| 6 | 1:00 (25s) | 18s | **Report.** Viewer timeline with finding markers coloured by category. Click the ledge finding: the video seeks there, and the card shows "[3] deaths in [40]s", the quote *"is this jump even possible?"* and the suggested fix. Then click one pacing finding ("[52]s idle, no objective in view"). | "Every finding is timestamped and backed by evidence: what the player said, lined up with what the telemetry recorded." | Viewer (TUG-100), polish + timeline (TUG-105) | Plain v0 list from TUG-100; zoom in harder in the edit |
| 7 | 1:25 (20s) | 14s | **SAM annotation.** Two finding cards, full screen. The beacon star is outlined in one and the mushroom enemy in the other. These two are known to land: both matched correctly on Phil's 29 Oct run, while ledges and HUD text often miss (TUG-94). Show the text prompt Muse Wonder chose above each frame (e.g. "bright yellow star beacon", "red mushroom with white spots"). | "Muse Wonder decides what to highlight. SAM 3.1 segments it from a text prompt. That's where the player looked, and that's what they missed." | SAM annotations (TUG-104, TUG-94) | Plain key frame with a bounding box from telemetry coordinates; VO drops the SAM line |
| 8 | 1:45 (15s) | 10s | **Scoreboard 1.** The six pins return with labels: [5] green ✓ and [1] red ✗, plus "[1] false positive". | "[Five] of six found from a single playtest. It missed the [dull stretch]." | Eval harness (TUG-102), round 1 bundles (TUG-106), prompt tuning (TUG-103) | — |
| 9 | 2:00 (20s) | 14s | **Patch.** The editor dock lists proposed patches. Open the ledge patch diff in `tuning.tres` (`ledge_gap_width = [5.2]` → `[4.4]`), then the switch prompt text patch. Click **Apply** to create a commit `playtest-fix: ledge gap too wide`. | "It also writes the fix: small GDScript and resource diffs, each tied to its finding. I can apply them with one click, and every fix is its own commit." | Patch generation (TUG-107), one-click apply (TUG-108) | Show the `suggested_fix` text and apply it by hand in 10s; VO: "I applied its suggestions". Still a closed loop |
| 10 | 2:20 (15s) | 10s | **Playtest 2.** Split screen at the same ledge: before, the player dies [3]×; after, they clear it first try. Then the quest marker, before and after. | "Then a second playtest on the patched build." | Round 2 footage (TUG-111) | — |
| 11 | 2:35 (15s) | 10s | **Headline.** A before/after table: deaths [14→4], retries [9→2], time to complete [11:20→6:45]. Big text: "Detected [5]/6 · fixed [4]". | "Five of six planted problems found, four fixed, and deaths down [70]%. That took one afternoon, not a weekend of scrubbing footage." | Round 2 metrics (TUG-111), eval (TUG-102) | — |
| 12 | 2:50 (10s) | 6s | **End card.** Repo URL. "Built with Muse Wonder + SAM 3.1 · Meta Model API". Name. | "Playtest Analyst. Link below." | Public repo (TUG-113, TUG-114) | — |

Totals: 180s / 120s.

**Ready-made shots.** Shots 2, 3, 8 (the pins and the list, without ticks) and 12 need no players. `tools/footage.sh` renders them from the planted level as 1080p 30 fps video and PNG stills; the files are in the [`demo-footage` release](https://github.com/tornupgaming/playtest-analyst/releases/tag/demo-footage), and [`demo-footage.jpg`](demo-footage.jpg) shows stills from each. The flythrough ends on the view shot 8 uses, so the pins "return" in the same place. Add the ✓ and ✗ for shot 8 in the edit. Re-render after any change to the level; the camera path, pin positions and card text are at the top of `tools/footage.gd`.

**Swap-in if cross-build memory ships (TUG-109):** in shot 11, replace the table header with the viewer's comparison banner, "[4] resolved · [1] new · [1] persisting". This adds no time. If TUG-109 doesn't ship, nothing changes.

## Capture checklist (for TUG-106 and TUG-111)

Round 1 (unpatched build):
- [ ] Full session recordings with think-aloud (shots 1, 4, 6, 10 "before")
- [ ] Screen recording of the editor: Start session → play → stop (shot 4)
- [ ] Screen recording of Analyse running, with real duration and cost (shot 5)
- [ ] Viewer screen recording at 1080p: timeline, two finding clicks, two SAM cards (shots 6, 7)
- [ ] Eval output for the scoreboard (shot 8)

Patch:
- [ ] Editor dock: patch list, diff, Apply, and the resulting commit in git log (shot 9)

Round 2 (patched build):
- [ ] The same two moments as round 1: the ledge and the quest marker (shot 10)
- [ ] Deaths, retries and time to complete for both rounds, same metric definitions (shot 11)
- [x] Flythrough of the level with pins (shot 3): `tools/footage.sh`, no players needed

## Cut list

Not in any shot, so it is not demo work. Build it only if it's needed for the pipeline to function, or for the README.

- Cross-build memory (TUG-109), except the optional shot 11 swap-in
- Patch **Revert**, dirty-tree refusal, path allowlist UI (TUG-107/108 safety, so README only)
- Telemetry overlay lane in the viewer (TUG-105 bullet), unless it's free
- Session metadata: build id, tester name, partial-bundle cleanup (TUG-98 internals)
- Eval harness internals, match-rule strictness, per-session tables (README results table only)
- Prompt iteration story, two-pass detect → explain (TUG-103 internals)
- Install and setup walkthrough, architecture diagram (README, TUG-113)
- Multiple testers compared side by side; one tester per round on screen
- Webcam / face-cam of testers
- Any other Meta model (Muse Image, Muse Code): no shot needs one. Muse Spark now writes the patches (TUG-107), so shot 9 can name it: "Muse Spark writes the fix."
