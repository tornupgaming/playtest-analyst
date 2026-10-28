# Telemetry

The `PlaytestTelemetry` autoload (`addons/playtest_analyst/telemetry.gd`) writes the session's `events.jsonl`. The analyst reads it with `TelemetryEvent` in `analyst/src/schema.ts`.

## Calling it

```gdscript
PlaytestTelemetry.event("death", {cause = "fall", zone = "ledge"})
PlaytestTelemetry.event("found_secret", {secret = "cave"})   # a custom event: any type name
```

`event()` does nothing when no session is running, so games can call it unconditionally. A session runs while `PlaytestRecorder` records ([recorder.md](recorder.md)), or from launch with `--telemetry-dir`.

## Line format

One JSON object per line:

| Field | Type | Meaning |
|---|---|---|
| `t` | number | Seconds on the session clock, to 1 ms |
| `type` | string | One of the types below, or a custom name |
| `player_pos` | `[x, y, z]` or `null` | Global position of the first node in the `player` group, to 1 cm. `null` if there is none |
| `data` | object | Per-type fields, below. `{}` if none |

Lines are in the order they were written. `input_idle` is written when the idle period ends but stamped with its start, so it comes after events with a later `t`. Sort by `t` to get a timeline.

## Event types

| Type | Written by | `data` |
|---|---|---|
| `death` | the game | `cause` (e.g. `"fall"`, `"enemy"`), `zone` (the current zone id, `""` if none; a fall counts in the zone the player fell from) |
| `retry` | the game, when the player respawns after a death | none |
| `zone_enter` | the game | `zone`: zone id |
| `zone_exit` | the game | `zone`; telemetry adds `dwell`: seconds since that zone's `zone_enter` |
| `objective_update` | the game, when the objective text changes | `text` |
| `ui_open`, `ui_close` | the game | `ui`: which screen or panel (e.g. `"map"`) |
| `input_idle` | telemetry, by itself | `duration`: seconds without input. `t` is when the last input happened |
| anything else | the game | anything |

The test level (`level/level.gd`) writes `death`, `retry`, `zone_enter`, `zone_exit` and `objective_update`. It has no UI screens.

### Idle detection

Any input event counts as input, except joypad axis motion under 0.2. Holding any key, button or action also counts, including actions pressed from code with `Input.action_press()`, which is how `tools/shot.gd` plays scripted input. After `idle_after` seconds (default 5) with none, the player is idle. When input resumes, or the session stops, one `input_idle` line is written for the whole period.

## The session clock

`t` is seconds since the session started, from `Time.get_ticks_usec()`. When the recorder runs it owns the clock and passes its t=0 to `PlaytestTelemetry.start()`, so events line up with the video (DECISIONS.md §2).

`--telemetry-game-clock` counts physics frames instead (`frames / physics_ticks_per_second`). Scripted runs at `--fixed-fps` use it so that `t` is game time, not wall time.

## User args

Pass these after `--`:

| Arg | Effect |
|---|---|
| `--telemetry-dir=PATH` | Start a session at launch, writing `PATH/events.jsonl`, without the recorder |
| `--telemetry-game-clock` | Stamp `t` from physics frames |

## Sample

[`telemetry-sample.jsonl`](telemetry-sample.jsonl) is a scripted run of the planted test level: the player starts in the drop zone, is killed by the enemy, respawns at the start, and stands still for 7 s before walking on.

```sh
godot --path . --fixed-fps 60 --resolution 480x270 -s res://tools/shot.gd -- --out /tmp/sample/end.png \
	--profile planted --view drop --play "move_forward:1,:7,move_forward:3" \
	--telemetry-dir=/tmp/sample --telemetry-game-clock
```

## Tests

```sh
tools/test.sh
```

`tests/telemetry_test.gd` drives the autoload through `event()`, `start()`, `stop()` and real input events, and checks the lines it writes. It covers zone dwell, player position, and idle detection.
