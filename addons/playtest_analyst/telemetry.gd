extends Node
## The PlaytestTelemetry autoload: the game's event log for a playtest session.
## Games call `event(type, data)`. Each call writes one line of events.jsonl,
## `{t, type, player_pos, data}`, with `t` on the session clock. The schema is in
## docs/telemetry.md.
##
## It adds two things the game doesn't have to: `zone_exit` gets the seconds since
## the matching `zone_enter` as `data.dwell`, and `input_idle` is written by itself
## once input resumes after `idle_after` seconds without any.
##
## It writes nothing until a session starts: PlaytestRecorder starts one, or these
## user args (after `--`) do, for scripted runs without the recorder:
##   --telemetry-dir=PATH       write PATH/events.jsonl from launch
##   --telemetry-game-clock     stamp `t` from physics frames, not wall time, so scripted
##                              runs at --fixed-fps line up with frames captured per game second

## Seconds without input before the player counts as idle.
var idle_after := 5.0

var _file: FileAccess
var _t0_usec: int
var _t0_frame: int
var _game_clock := false
## Session time of the last input, and whether the player has been idle since.
var _last_input := 0.0
var _idle := false
## Zone id -> session time of its zone_enter.
var _zones := {}


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS  # input in a pause menu is not idle
	set_physics_process(false)
	set_process_input(false)
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--telemetry-dir="):
			start(arg.trim_prefix("--telemetry-dir="), "--telemetry-game-clock" in args)


## Starts a new events.jsonl in `dir`, with session t=0 at `t0_usec` (a
## Time.get_ticks_usec() reading). The game clock counts physics frames from now.
func start(dir: String, game_clock := false, t0_usec := Time.get_ticks_usec()) -> void:
	stop()
	DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(dir.path_join("events.jsonl"), FileAccess.WRITE)
	_game_clock = game_clock
	_t0_usec = t0_usec
	_t0_frame = Engine.get_physics_frames()
	_last_input = now()
	_idle = false
	_zones = {}
	set_physics_process(true)
	set_process_input(true)


## Closes events.jsonl. An idle period still running is written first.
func stop() -> void:
	if _file == null:
		return
	if _idle:
		_write_idle()
	_file.close()
	_file = null
	set_physics_process(false)
	set_process_input(false)


## Seconds on the session clock.
func now() -> float:
	if _game_clock:
		return (Engine.get_physics_frames() - _t0_frame) / float(Engine.physics_ticks_per_second)
	return (Time.get_ticks_usec() - _t0_usec) / 1e6


## Logs an event now. `type` is one of the types in docs/telemetry.md or a name of
## your own.
func event(type: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	if type == "zone_enter":
		_zones[data.zone] = now()
	elif type == "zone_exit" and _zones.has(data.zone):
		data = data.merged({dwell = snappedf(now() - _zones[data.zone], 0.001)})
		_zones.erase(data.zone)
	_write(now(), type, data)


func _input(input: InputEvent) -> void:
	if not (input is InputEventJoypadMotion and absf(input.axis_value) < 0.2):
		_on_input()


func _physics_process(_delta: float) -> void:
	# Held keys send no events, and Input.action_press() (scripted play) sends none at all.
	if Input.is_anything_pressed():
		_on_input()
	elif not _idle and now() - _last_input >= idle_after:
		_idle = true


func _on_input() -> void:
	if _idle:
		_write_idle()
		_idle = false
	_last_input = now()


## The idle period is stamped at its start, so this line is out of order in the file.
func _write_idle() -> void:
	_write(_last_input, "input_idle", {duration = snappedf(now() - _last_input, 0.001)})


func _write(t: float, type: String, data: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var pos: Variant = null
	if player:
		pos = [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.y, 0.01), snappedf(player.global_position.z, 0.01)]
	_file.store_line(JSON.stringify({
		t = snappedf(t, 0.001),
		type = type,
		player_pos = pos,
		data = data,
	}, "", false))
	_file.flush()
