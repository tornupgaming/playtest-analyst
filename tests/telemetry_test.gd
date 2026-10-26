extends Node
## PlaytestTelemetry, tested through its public API: calls and input in, the lines
## of events.jsonl out. Game time is counted in physics frames (the game clock),
## so every run produces the same times.

const TELEMETRY := preload("res://addons/playtest_analyst/telemetry.gd")
## Times may differ by a physics frame, depending on when in the frame a call lands.
const TOLERANCE := 1.5 / 120.0

var _dir := "user://test_telemetry"
var _telemetry: Node


func test_zone_exit_carries_seconds_since_its_zone_enter() -> String:
	_start()
	_telemetry.event("zone_enter", {zone = "plaza"})
	await _seconds(2.5)
	_telemetry.event("zone_enter", {zone = "hall"})
	await _seconds(1.0)
	_telemetry.event("zone_exit", {zone = "plaza"})
	_telemetry.event("zone_exit", {zone = "hall"})
	return _expect([
		{t = 0.0, type = "zone_enter", player_pos = null, data = {zone = "plaza"}},
		{t = 2.5, type = "zone_enter", player_pos = null, data = {zone = "hall"}},
		{t = 3.5, type = "zone_exit", player_pos = null, data = {zone = "plaza", dwell = 3.5}},
		{t = 3.5, type = "zone_exit", player_pos = null, data = {zone = "hall", dwell = 1.0}},
	])


func test_event_records_the_player_position() -> String:
	var player := Node3D.new()
	player.add_to_group(&"player")
	add_child(player)
	player.position = Vector3(1.5, 2, -30.25)
	_start()
	_telemetry.event("found_secret", {secret = "cave"})
	return _expect([
		{t = 0.0, type = "found_secret", player_pos = [1.5, 2.0, -30.25], data = {secret = "cave"}},
	])


func test_idle_is_logged_at_its_start_once_input_resumes() -> String:
	_start()
	await _seconds(2.0)
	_key()  # 2 s without input is not idle
	await _seconds(7.0)
	_key()
	await _seconds(1.0)
	return _expect([
		{t = 2.0, type = "input_idle", player_pos = null, data = {duration = 7.0}},
	])


func test_a_held_action_is_not_idle() -> String:
	_start()
	Input.action_press(&"jump")
	await _seconds(7.0)
	Input.action_release(&"jump")
	await _seconds(6.0)
	_key()
	await _seconds(0.5)
	return _expect([
		{t = 7.0, type = "input_idle", player_pos = null, data = {duration = 6.0}},
	])


func test_stop_logs_an_idle_period_still_running() -> String:
	_start()
	await _seconds(6.0)
	return _expect([
		{t = 0.0, type = "input_idle", player_pos = null, data = {duration = 6.0}},
	])


func _start() -> void:
	_telemetry = TELEMETRY.new()
	add_child(_telemetry)
	_telemetry.start(_dir, true)


func _seconds(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _key() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_X
		key.pressed = pressed
		Input.parse_input_event(key)


## Stops the telemetry and compares events.jsonl with `expected`, line by line.
func _expect(expected: Array) -> String:
	_telemetry.stop()
	var actual := []
	for line in FileAccess.get_file_as_string(_dir.path_join("events.jsonl")).split("\n", false):
		actual.append(JSON.parse_string(line))
	if _same(actual, expected):
		return ""
	return "expected %s\n got     %s" % [JSON.stringify(expected), JSON.stringify(actual)]


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(a - b) <= TOLERANCE
	if a is Dictionary and b is Dictionary:
		return a.size() == b.size() and a.keys().all(func(k: Variant) -> bool: return b.has(k) and _same(a[k], b[k]))
	if a is Array and b is Array:
		return a.size() == b.size() and range(a.size()).all(func(i: int) -> bool: return _same(a[i], b[i]))
	return a == b
