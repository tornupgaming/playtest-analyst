extends Node
## Minimal event log so the test level can emit events now.
## TUG-97 replaces this with the full schema, idle detection and session bundles.
##
## User args (after `--`):
##   --no-telemetry             write nothing (scripted checks)
##   --telemetry-dir=PATH       write PATH/events.jsonl instead of user://sessions/<time>/
##   --telemetry-game-clock     stamp `t` from physics frames, not wall time, so scripted
##                              runs at --fixed-fps line up with frames captured per game second

var _file: FileAccess
var _start_usec: int
var _start_frame: int
var _game_clock := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# Scripted runs (tools/*.sh) pass this so they don't leave sessions behind.
	if "--no-telemetry" in args:
		return
	var dir := "user://sessions/%s" % Time.get_datetime_string_from_system().replace(":", "-")
	for arg in args:
		if arg.begins_with("--telemetry-dir="):
			dir = arg.trim_prefix("--telemetry-dir=")
	_game_clock = "--telemetry-game-clock" in args
	DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(dir.path_join("events.jsonl"), FileAccess.WRITE)
	_start_usec = Time.get_ticks_usec()
	_start_frame = Engine.get_physics_frames()


## Seconds on the session clock.
func now() -> float:
	if _game_clock:
		return (Engine.get_physics_frames() - _start_frame) / float(Engine.physics_ticks_per_second)
	return (Time.get_ticks_usec() - _start_usec) / 1e6


func event(type: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var pos: Variant = null
	if player:
		pos = [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.y, 0.01), snappedf(player.global_position.z, 0.01)]
	_file.store_line(JSON.stringify({
		t = snappedf(now(), 0.001),
		type = type,
		player_pos = pos,
		data = data,
	}))
	_file.flush()
