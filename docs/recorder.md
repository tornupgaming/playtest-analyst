# Session recorder

The editor plugin (`addons/playtest_analyst/`) records a playtest into a session bundle (DECISIONS.md §2) and runs the analyst on it.

| File | What it is |
|---|---|
| `plugin.cfg`, `plugin.gd` | The editor plugin. Enabling it adds the dock and the two autoloads. |
| `dock.gd` | The **Playtest** dock |
| `patches.gd`, `diff_view.gd` | The dock's patch list: apply and revert a bundle's `patches.json` as git commits, and show a diff |
| `recorder.gd` | The `PlaytestRecorder` autoload. It runs in the game and writes the bundle. |
| `telemetry.gd` | The `PlaytestTelemetry` autoload. It writes `events.jsonl` ([telemetry.md](telemetry.md)). |

## Using it

1. In the **Playtest** dock, type the tester's name and click **Record session**. The dock plays the main scene with `--display-driver x11 -- --record --tester=<name>`. It sets those args for this one run only, then restores the project's run args.
2. Play. The game window's title ends in `[REC]`.
3. Stop the recording in any of these ways: **Stop recording** in the dock, **F9** in the game, or closing the game window. Don't use the editor's Stop button: it kills the game, so the bundle is left incomplete (see below).
4. Pick the session in the list and click **Analyse**. This runs `bun analyst/src/cli.ts analyse <dir>` and streams its output into the dock.
5. Click **Open report**. This runs `bun analyst/src/cli.ts serve <dir>` and opens the first URL it prints. Only one server runs at a time, and it is stopped when the editor closes.
6. Click **Propose fixes**. This runs `bun analyst/src/cli.ts patch <dir> --project <project root>` (DECISIONS.md §8), which writes `patches.json` into the bundle. The dock lists its patches; pick one to see its finding, rationale and diff.
7. Click **Apply**. The dock runs `git apply -C0 --index` and commits only that file as `playtest-fix: <summary>`. The body holds the rationale and `Finding:`, `Patch:` and `Session:` lines, which is how the list knows the patch is applied. The editor then rescans the filesystem, so it reloads the changed resource. **Revert** commits the reverse as `Revert "playtest-fix: <summary>"`, in `git revert`'s message format. It doesn't use `git revert` itself, because that conflicts when a neighbouring line has since been patched ([wiki](wiki/git-apply.md)).

   Both refuse while any tracked file has uncommitted changes, and Apply refuses a patch whose diff touches anything but its own file or whose file isn't in `playtest.json`'s `patch_allow`. Refusals and git errors appear under the buttons. Opening the project in the editor can itself rewrite `.import` files; commit those first.

You can also record without the editor. Run `godot --path . --display-driver x11 -- --record`, or press F9 in any running build.

Sessions go in `<project>/sessions/<id>/` when the game runs from the editor or a source checkout, and in `user://sessions/<id>/` in an exported game. `<id>` is the UTC start time, e.g. `2026-10-26T23-24-13`. The recorder puts a `.gdignore` in `sessions/` so Godot doesn't import the media.

## The bundle

| File | Written | Contents |
|---|---|---|
| `screen.mkv` | while recording | x11grab of the game window (H.264, 30 fps) and the default PulseAudio/PipeWire mic (PCM, mono), both from one ffmpeg process with `-copyts`. Each stream's `start_time` is a unix time. |
| `events.jsonl` | while recording | Telemetry ([telemetry.md](telemetry.md)) |
| `session.json` | last, on a clean stop | `SessionMeta` (`analyst/src/schema.ts`) |
| `INCOMPLETE` | at start; deleted on a clean stop | Why the bundle is unfinished |

`session.json` fields:

- `id`: the folder name.
- `started_at`: UTC, to the second.
- `t0_unix`: unix time at session t=0. It is read back to back with the `Time.get_ticks_usec()` that telemetry counts from.
- `duration`: seconds.
- `game`: `application/config/name`.
- `build`: the git short SHA when run from a checkout, otherwise `null`.
- `tester`: from the dock, or `null`.
- `profile`: the project setting `playtest_analyst/profile`, or `null` if it isn't set.
- `capture`: `{video: "screen.mkv", audio: "screen.mkv"}`. There is no `video_start` or `audio_start`, because both streams carry wall-clock pts.

After a clean stop the recorder starts `bun analyst/src/cli.ts finalize <dir>` in the background. If bun or the CLI is missing, it prints a line and carries on.

### Bundles that end early are marked, never deleted

A bundle without `session.json` is unfinished, and `readSession` rejects it. `INCOMPLETE` says why:

| What happened | `INCOMPLETE` says | `screen.mkv` |
|---|---|---|
| The game crashed or was killed (including the editor's Stop button) | "Recording started … and never stopped" | Finalised: a watchdog shell around ffmpeg sends it SIGTERM when Godot's process disappears, and ffmpeg writes the file's end on SIGTERM |
| ffmpeg exited by itself (e.g. no ffmpeg, no mic, bad window) | Its exit code and stderr | Whatever it wrote |
| ffmpeg didn't exit within 5 s of `q` | That, and that it was sent SIGTERM | Finalised on SIGTERM |

The dock lists these sessions as `(incomplete)` and disables Analyse for them.

## Checking it without a person

```sh
tools/record_check.sh [SECONDS]   # default 30
```

This records the real game with `--record`. A PipeWire null sink stands in for the mic, and a 1 kHz beep is played into it every 3 s. The script then closes the window through the window manager. It prints:

- whether the bundle is complete;
- each beep's lag in the mic track (beep heard minus the moment `paplay` was called, so it includes paplay's own start-up);
- whether `readSession` accepts the bundle.

From an agent shell a Godot window only presents its first frames, so the video in these runs shows a still frame. The script checks timing and files, not pictures.

## Measured

CachyOS (Wayland with XWayland, PipeWire), Godot 4.7.2, ffmpeg 9.0.2, 26 Oct 2026, run from an agent shell:

| Check | Result |
|---|---|
| `tools/record_check.sh 60`, loopback mic | Clean stop on window close. 19 of 19 beeps heard, lag 20–25 ms, no trend over 60 s. `readSession` OK. |
| Same, 30 s run (by hand, same method) | 9 of 9 beeps, 13–24 ms |
| `screen.mkv` stream start times, three runs | Audio `start_time` 52, 58 and 39 ms after video |
| F9 twice, then close | Two complete bundles |
| `kill -9` on Godot while recording | `INCOMPLETE` kept, no `session.json`. Without the watchdog, ffmpeg kept recording after Godot died. With it, ffmpeg exits and `screen.mkv` has a duration. |
| SIGTERM to ffmpeg only, mid-session | Recorder stopped itself within a frame; `INCOMPLETE` says "ffmpeg exited with code 255."; no `session.json` |
| Dock in a real editor: Record → Stop recording | The game got `--display-driver x11 -- --record --tester=Phil%20Smith`. `session.json` has `"tester": "Phil Smith"`, and `readSession` OK. |
| Dock: Record → the editor's Stop button | Status says the session is incomplete; the list shows `(incomplete)`; no ffmpeg left running |
| Dock: Analyse and Open report with no `analyse`/`serve` command yet | CLI output and `[exited with code 2]` streamed into the dock |

The x11grab frame from the dock-launched game shows the game view at 1152×648. In this setup the editor launched the game with `--wid`, which is its option for embedding the game in the Game tab, and the capture still showed the game.

## Phil: check by hand on a real play session

1. **Footage.** Record 2–3 minutes from the dock and play normally. Open `screen.mkv` and check that the video moves the whole way through, shows only the game window, and that the picture doesn't freeze when you alt-tab or move the window.
2. **Embedded game.** If the editor shows the game inside its Game tab rather than in its own window, check that the footage still shows the game. If it doesn't, turn embedding off (Editor Settings → Run → Window Placement → Game Embed Mode, or the embed toggle in the Game tab).
3. **Voice.** Think aloud while playing. In the recording, your voice should sit on the picture: say "jump" as you press Space, and check it lines up within about a frame.
4. **Mic device.** The recorder uses PulseAudio's `default` source. Check it is the mic you meant to use (`pactl get-default-source`).
5. **Stop paths.** Try each of the dock's Stop button, F9 and closing the window. Each should give a session without `(incomplete)`.
6. **finalize/analyse/serve.** Once those commands land, check that `video.mp4` appears after a stop, that Analyse streams progress, and that Open report opens the browser.
7. **Profile.** For eval runs of the test level, set `playtest_analyst/profile` (Project Settings, Advanced) to `planted` or `clean`, to match the tuning you copied.
