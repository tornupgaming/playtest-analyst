# Playtest Analyst

A Godot plugin that records a playtest (screen, think-aloud and telemetry), sends it to Muse Wonder for analysis, and proposes fixes.

## Layout

| Path | What it is |
|---|---|
| `addons/playtest_analyst/` | The plugin. `telemetry.gd` is the `PlaytestTelemetry` autoload. |
| `level/` | The test course (`level.tscn`). It reads every tunable from `level/tuning.tres` at `_ready()`. |
| `eval/` | Ground truth and the two tuning profiles. Godot ignores this folder (`.gdignore`), so its labels never reach the analysis. |
| `demo/` | Player, enemy and sky from the Godot 3D platformer demo (see Credits). |

## Test course

Open the project in Godot 4.7 and press Play. Pick a profile by copying it over the live tuning file:

```sh
cp eval/tuning_planted.tres level/tuning.tres   # round 1
cp eval/tuning_clean.tres level/tuning.tres     # baseline
```

`eval/ground_truth.json` lists what differs between the profiles and the evidence each difference should leave.

## Credits

The player, enemy, bullet and skybox in `demo/` come from [godotengine/godot-demo-projects `3d/platformer`](https://github.com/godotengine/godot-demo-projects/tree/master/3d/platformer) (commit `b761b4c`), © the Godot Engine contributors, MIT licence (`demo/LICENSE.md`). We changed the player and enemy scripts: the level handles respawns, the coin counter is gone, and the enemy waits to be triggered, then charges and kills on contact.
