extends Node
## Minimal event log so the test level can emit events now.
## TUG-97 replaces this with the full schema, idle detection and session bundles.

var _file: FileAccess
var _start_ms: int


func _ready() -> void:
	# Scripted runs (tools/*.sh) pass this so they don't leave sessions behind.
	if "--no-telemetry" in OS.get_cmdline_user_args():
		return
	var dir := "user://sessions/%s" % Time.get_datetime_string_from_system().replace(":", "-")
	DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(dir.path_join("telemetry.jsonl"), FileAccess.WRITE)
	_start_ms = Time.get_ticks_msec()


func event(type: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var pos: Variant = null
	if player:
		pos = [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.y, 0.01), snappedf(player.global_position.z, 0.01)]
	_file.store_line(JSON.stringify({
		t = (Time.get_ticks_msec() - _start_ms) / 1000.0,
		type = type,
		player_pos = pos,
		data = data,
	}))
	_file.flush()
