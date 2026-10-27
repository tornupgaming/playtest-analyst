# Playtest Analyst

A Godot plugin that records a playtest (screen, think-aloud and telemetry), sends it to Muse Wonder for analysis, and proposes fixes.

## Layout

| Path | What it is |
|---|---|
| `addons/playtest_analyst/` | The plugin: the Playtest dock, the `PlaytestRecorder` autoload that records a session bundle ([docs/recorder.md](docs/recorder.md)), and the `PlaytestTelemetry` autoload ([docs/telemetry.md](docs/telemetry.md)). |
| `tests/` | GDScript tests, run headless by `tools/test.sh`. |
| `level/` | The test course (`level.tscn`). It reads every tunable from `level/tuning.tres` at `_ready()`. |
| `eval/` | Ground truth and the two tuning profiles. Godot ignores this folder (`.gdignore`), so its labels never reach the analysis. |
| `demo/` | Player and enemy. The player's movement code comes from the Godot 3D platformer demo (see Credits). |
| `art/` | Kenney Platformer Kit models (`art/kenney/`), the toy-block shader and its materials (`art/blocks/`), the enemy and the Blender script that builds it (`art/enemy/`), and the HUD font. |
| `tools/` | Scripts for checking the level without playing it. See [Checking the level](#checking-the-level). |

## Test course

Open the project in Godot 4.7 and press Play. Pick a profile by copying it over the live tuning file:

```sh
cp eval/tuning_planted.tres level/tuning.tres   # round 1
cp eval/tuning_clean.tres level/tuning.tres     # baseline
```

`eval/ground_truth.json` lists what differs between the profiles and the evidence each difference should leave.

To record a playtest, use the **Playtest** dock in the editor ([docs/recorder.md](docs/recorder.md)).

Controls: WASD or arrows to move, Space to jump. Click to capture the mouse, then move it to orbit the camera (Esc releases it). Jump on the enemy to squash it.

### Art direction

Bright toybox platformer, in the family of Super Mario 3D World, Captain Toad and Astro Bot. Grass-topped clay cliffs and floating mesas over a sea of cloud, chunky bevelled blocks, a soft checker on walkable tops so distances read at a glance, saturated colours under a warm sun. Everything uses the Kenney Platformer Kit palette.

The level is still built from boxes in `level.gd`, so every plant keeps its exact geometry. `art/blocks/block.gdshader` makes any box look like a Kenney block. Each block kind (grass, sand, stone, wood, hedge) is a material in `art/blocks/`, editable in the inspector.

To rebuild the enemy after editing its script:

```sh
blender -b -P art/enemy/build_enemy.py -- art/enemy/enemy.glb /tmp/enemy_preview.png
```

## Checking the level

These run the real game from the command line and write images, so a change can be checked without playing it.

```sh
tools/check.sh                      # build both profiles headless; fails on script errors or z-fighting blocks
tools/test.sh                       # GDScript tests in tests/ (telemetry, patch apply), headless
tools/record_check.sh 60            # record a real 60 s session with a loopback mic; check the bundle and mic lag
tools/shots.sh                      # every named view -> /tmp/shots/sheet.png (one labelled contact sheet)
tools/shots.sh -p planted beacon    # one view, planted profile
tools/shots.sh over=50,70,30:0,0,-90                   # a free camera: name=eye:target
tools/clip.sh -v drop "move_forward+jump:0.7,:1"       # scripted input -> /tmp/shots/clip_strip.png and clip.mp4
tools/clip.sh -c 0,3,-14 "move_right:1,move_left:1"   # the same, filmed from a fixed point
```

Views are defined in `VIEWS` in `tools/shot.gd`: the player stands at an offset into a zone and the game camera frames it, so a shot shows what a tester sees. `clip.sh` prints where the player ended up. A player at the spawn after a run means they died.

## Credits

- **Godot platformer demo.** The player's movement code, the enemy's charge logic and the sounds in `demo/` come from [godotengine/godot-demo-projects `3d/platformer`](https://github.com/godotengine/godot-demo-projects/tree/master/3d/platformer) (commit `b761b4c`), © the Godot Engine contributors, MIT licence (`demo/LICENSE.md`). We replaced its models, camera, shooting and sky. The level handles respawns, and the enemy waits to be triggered, charges, kills on contact, and dies when stomped.
- **Kenney.** Models in `art/kenney/` come from the [Platformer Kit](https://kenney.nl/assets/platformer-kit) by Kenney (www.kenney.nl), CC0 (`art/kenney/License.txt`).
- **Fredoka.** The HUD font, © The Fredoka Project Authors, SIL Open Font License 1.1 (`art/fonts/OFL.txt`).
- The enemy model and the block shader are our own.
