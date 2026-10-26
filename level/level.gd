@tool
extends Node3D
## The test course. The level is built in code at `_ready()` so that every
## value that differs between builds comes from `tuning` and nowhere else.
## The course runs along -Z: start, ledge, plaza, hall, drop, fork, corridor, finish.

const KILL_Y := -10.0
const CORRIDOR_SEGMENT_LENGTH := 20.0
const ENEMY_SCENE := preload("res://demo/enemy/enemy.tscn")

@export var tuning: LevelTuning

var _spawn: Vector3
var _current_zone := ""
var _ledge_deaths := 0
var _bridge_shown := false
var _switch_pressed := false
var _respawning := false
var _enemy: RigidBody3D
var _materials := {}

# Section anchors, filled in by _build() and used by the runtime handlers.
var _ledge_z: float
var _enemy_spawn: Vector3
var _gate: Node3D
var _marker: Node3D

@onready var _built := $Built as Node3D
@onready var _player := $Player as CharacterBody3D
@onready var _objective := $HUD/Objective as Label
@onready var _banner := $HUD/Banner as Label


func _ready() -> void:
	for child in _built.get_children():
		child.free()
	_build()
	if Engine.is_editor_hint():
		return
	_player.add_to_group(&"player")
	_respawn_at(_spawn)
	_spawn_enemy()
	_set_objective("Follow the path.")


func _process(delta: float) -> void:
	if _marker:
		_marker.rotate_y(delta * 1.5)


func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint() and _player.global_position.y < KILL_Y:
		_kill("fall")


# --- Build -------------------------------------------------------------------

func _build() -> void:
	var stone := _mat(Color(0.75, 0.72, 0.66))
	var sand := _mat(Color(0.86, 0.76, 0.58))
	var slate := _mat(Color(0.5, 0.54, 0.6))
	var brick := _mat(Color(0.62, 0.42, 0.34))
	var wood := _mat(Color(0.55, 0.38, 0.22))

	# Start, with a short practice gap.
	_spawn = Vector3(0, 0, -1)
	_box(Vector3(-5, -1, 2), Vector3(5, 0, -20), stone)
	_box(Vector3(-5, -1, -22.5), Vector3(5, 0, -32), stone)

	# Ledge: a narrow run-up, a gap, and a landing.
	var gap := tuning.ledge_gap_width
	_ledge_z = -44.0
	var z0 := _ledge_z - gap - 8.0
	_box(Vector3(-2, -1, -32), Vector3(2, 0, _ledge_z), stone)
	_box(Vector3(-2, -1, _ledge_z - gap), Vector3(2, 0, z0), stone)
	_checkpoint(Vector3(-2, 0, -32), Vector3(2, 4, -36), Vector3(0, 0, -34))
	_checkpoint(Vector3(-2, 0, z0 + 6), Vector3(2, 4, z0), Vector3(0, 0, z0 + 3))
	_zone("ledge", Vector3(-20, -14, -32), Vector3(20, 8, z0))

	# Plaza: the way on is up the stepping blocks to the terrace door.
	_box(Vector3(-20, -1, z0), Vector3(20, 0, z0 - 40), sand)
	_box(Vector3(-21, 0, z0), Vector3(-20, 16, z0 - 40), brick)
	_box(Vector3(20, 0, z0), Vector3(21, 16, z0 - 40), brick)
	_box(Vector3(-21, 0, z0 + 1), Vector3(-2, 6, z0), brick)
	_box(Vector3(2, 0, z0 + 1), Vector3(21, 6, z0), brick)
	_box(Vector3(-20, 0, z0 - 30), Vector3(20, 8, z0 - 40), brick)
	_box(Vector3(-21, 8, z0 - 40), Vector3(-2, 16, z0 - 41), brick)
	_box(Vector3(2, 8, z0 - 40), Vector3(21, 16, z0 - 41), brick)
	_box(Vector3(-2, 13, z0 - 40), Vector3(2, 16, z0 - 41), brick)
	for i in 3:
		var top := 2.0 + 2.0 * i
		var z := z0 - 18.0 - 4.0 * i
		_box(Vector3(14.5, top - 1, z + 1.5), Vector3(17.5, top, z - 1.5), stone)
	for p: Vector2 in [Vector2(-12, -8), Vector2(-12, -20), Vector2(12, -8), Vector2(12, -20),
			Vector2(-6, -14), Vector2(6, -14), Vector2(12, -26), Vector2(-12, -26)]:
		_box(Vector3(p.x - 1, 0, z0 + p.y + 1), Vector3(p.x + 1, 10, z0 + p.y - 1), slate)
	for c: Vector3 in [Vector3(-16, 0, -5), Vector3(-15, 0, -24), Vector3(4, 0, -22), Vector3(-3, 0, -9)]:
		_box(Vector3(c.x - 1, 0, z0 + c.z + 1), Vector3(c.x + 1, 1.5, z0 + c.z - 1), wood)
	_marker = _build_marker(Vector3(0, 10, z0 - 31.5))
	_zone("plaza", Vector3(-20, -2, z0), Vector3(20, 16, z0 - 40))

	# Hall: a gate at the far end, opened by the switch on the balcony.
	var z1 := z0 - 40.0
	_box(Vector3(-9, -1, z1), Vector3(9, 8, z1 - 30), slate)
	_box(Vector3(-9, 8, z1), Vector3(-8, 16, z1 - 30), brick)
	_box(Vector3(8, 8, z1), Vector3(9, 16, z1 - 30), brick)
	_box(Vector3(-9, 8, z1 - 30), Vector3(-2, 16, z1 - 31), brick)
	_box(Vector3(2, 8, z1 - 30), Vector3(9, 16, z1 - 31), brick)
	_box(Vector3(-2, 13, z1 - 30), Vector3(2, 16, z1 - 31), brick)
	_box(Vector3(-2, -1, z1 - 30), Vector3(2, 8, z1 - 31), slate)
	_gate = _box(Vector3(-2, 8, z1 - 30.2), Vector3(2, 13, z1 - 30.8), wood)
	_box(Vector3(-8, 10.6, z1 - 12), Vector3(-5, 11, z1 - 18), stone)
	_box(Vector3(-7.5, 8, z1 - 20.5), Vector3(-5.5, 9.5, z1 - 22.5), wood)
	_box(Vector3(5, 8, z1 - 8), Vector3(7, 9.5, z1 - 10), wood)
	_box(Vector3(4.5, 8, z1 - 19), Vector3(7.5, 10, z1 - 22), wood)
	_build_switch(Vector3(-6.5, 11, z1 - 15))
	_checkpoint(Vector3(-2, 8, z1), Vector3(2, 12, z1 - 3), Vector3(0, 8, z1 - 1.5))
	_zone("hall", Vector3(-8, 7, z1), Vector3(8, 16, z1 - 30))

	# Tunnel to a hole that drops into an enclosed room with the enemy.
	var z2 := z1 - 31.0
	_box(Vector3(-3, -1, z2), Vector3(3, 8, z2 - 6), slate)
	_box(Vector3(-2, 7, z2 - 6), Vector3(2, 8, z2 - 10), slate)
	_box(Vector3(-3, 8, z2), Vector3(-2, 13, z2 - 15), brick)
	_box(Vector3(2, 8, z2), Vector3(3, 13, z2 - 15), brick)
	_box(Vector3(-2, 8, z2 - 14), Vector3(2, 13, z2 - 15), brick)
	_box(Vector3(-3, 13, z2), Vector3(3, 13.5, z2 - 15), brick)
	_checkpoint(Vector3(-2, 8, z2), Vector3(2, 12, z2 - 3), Vector3(0, 8, z2 - 1.5))
	_box(Vector3(-9, 7, z2 - 6), Vector3(-2, 8, z2 - 26), slate)
	_box(Vector3(2, 7, z2 - 6), Vector3(9, 8, z2 - 26), slate)
	_box(Vector3(-2, 7, z2 - 14), Vector3(2, 8, z2 - 26), slate)
	_box(Vector3(-8, -1, z2 - 6), Vector3(8, 0, z2 - 26), stone)
	_box(Vector3(-9, 0, z2 - 6), Vector3(-8, 7, z2 - 26), brick)
	_box(Vector3(8, 0, z2 - 6), Vector3(9, 7, z2 - 26), brick)
	_box(Vector3(-9, 0, z2 - 5), Vector3(9, 7, z2 - 6), brick)
	_box(Vector3(-9, 0, z2 - 26), Vector3(-2, 7, z2 - 27), brick)
	_box(Vector3(2, 0, z2 - 26), Vector3(9, 7, z2 - 27), brick)
	_box(Vector3(-2, 4, z2 - 26), Vector3(2, 7, z2 - 27), brick)
	_box(Vector3(-2, -1, z2 - 26), Vector3(2, 0, z2 - 27), stone)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 6, z2 - 18)
	lamp.omni_range = 16.0
	_built.add_child(lamp)
	_enemy_spawn = Vector3(0, 0, z2 - 20)
	_zone("drop", Vector3(-8, 0, z2 - 6), Vector3(8, 7, z2 - 26))

	# Fork: a signpost, a walled branch each way. Left ends in a dead end;
	# right turns into the corridor.
	var z3 := z2 - 27.0
	_box(Vector3(-2, -1, z3), Vector3(2, 0, z3 - 8), stone)
	_box(Vector3(-3, 0, z3), Vector3(-2, 4, z3 - 7), brick)
	_box(Vector3(2, 0, z3), Vector3(3, 4, z3 - 7), brick)
	_box(Vector3(-5, -1, z3 - 8), Vector3(5, 0, z3 - 18), stone)
	_box(Vector3(-6, 0, z3 - 7), Vector3(-2, 4, z3 - 8), brick)
	_box(Vector3(2, 0, z3 - 7), Vector3(6, 4, z3 - 8), brick)
	_box(Vector3(-6, 0, z3 - 18), Vector3(6, 4, z3 - 19), brick)
	_build_sign(Vector3(0, 0, z3 - 16.5))
	_checkpoint(Vector3(-2, 0, z3), Vector3(2, 4, z3 - 3), Vector3(0, 0, z3 - 1.5))
	_zone("fork", Vector3(-5, -1, z3), Vector3(5, 6, z3 - 18))
	var corridor_end := z3 - 15.0 - tuning.corridor_segments * CORRIDOR_SEGMENT_LENGTH
	for side in [-1, 1]:
		_box(Vector3(side * 6, 0, z3 - 8), Vector3(side * 5, 4, z3 - 11), brick)
		_box(Vector3(side * 6, 0, z3 - 15), Vector3(side * 5, 4, z3 - 18), brick)
		_box(Vector3(side * 5, -1, z3 - 11), Vector3(side * 21, 0, z3 - 15), stone)
		_box(Vector3(side * 5, 0, z3 - 10), Vector3(side * 22, 4, z3 - 11), brick)
		_box(Vector3(side * 5, 0, z3 - 15), Vector3(side * 17, 4, z3 - 16), brick)
		var end := corridor_end if side == 1 else z3 - 35.0
		_box(Vector3(side * 17, -1, z3 - 15), Vector3(side * 21, 0, end), stone)
		_box(Vector3(side * 21, 0, z3 - 10), Vector3(side * 22, 4, end), brick)
		_box(Vector3(side * 16, 0, z3 - 16), Vector3(side * 17, 4, end), brick)
	_box(Vector3(-22, 0, z3 - 35), Vector3(-16, 4, z3 - 36), brick)
	_zone("fork_left", Vector3(-21, -1, z3 - 11), Vector3(-5.2, 6, z3 - 35))

	# Corridor: identical segments with a pillar pair at each joint.
	for i in tuning.corridor_segments:
		var z := z3 - 15.0 - i * CORRIDOR_SEGMENT_LENGTH
		_box(Vector3(17, 0, z - 0.5), Vector3(17.6, 5, z - 1.5), slate)
		_box(Vector3(20.4, 0, z - 0.5), Vector3(21, 5, z - 1.5), slate)
	_checkpoint(Vector3(17, 0, z3 - 11), Vector3(21, 4, z3 - 15), Vector3(19, 0, z3 - 13))
	_zone("corridor", Vector3(17, -1, z3 - 15), Vector3(21, 6, corridor_end))

	# Finish.
	_box(Vector3(15, -1, corridor_end), Vector3(23, 0, corridor_end - 10), sand)
	_box(Vector3(14, 0, corridor_end), Vector3(17, 4, corridor_end - 11), brick)
	_box(Vector3(21, 0, corridor_end), Vector3(24, 4, corridor_end - 11), brick)
	_box(Vector3(14, 0, corridor_end - 10), Vector3(24, 4, corridor_end - 11), brick)
	_build_goal(Vector3(19, 0, corridor_end - 6))


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


## A solid block spanning the two corners.
func _box(a: Vector3, b: Vector3, mat: Material) -> StaticBody3D:
	var size := (b - a).abs()
	var body := StaticBody3D.new()
	body.position = (a + b) / 2.0
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = size
	body.add_child(instance)
	body.add_child(shape)
	_built.add_child(body)
	return body


func _area(a: Vector3, b: Vector3) -> Area3D:
	var area := Area3D.new()
	area.position = (a + b) / 2.0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = (b - a).abs()
	area.add_child(shape)
	_built.add_child(area)
	return area


func _on_player_enter(area: Area3D, callback: Callable) -> void:
	if Engine.is_editor_hint():
		return
	area.body_entered.connect(func(body: Node3D) -> void:
		if body == _player:
			callback.call())


func _zone(id: String, a: Vector3, b: Vector3) -> void:
	var area := _area(a, b)
	area.name = "Zone_" + id
	_on_player_enter(area, _enter_zone.bind(id))
	if not Engine.is_editor_hint():
		area.body_exited.connect(func(body: Node3D) -> void:
			if body == _player:
				_exit_zone(id))


func _checkpoint(a: Vector3, b: Vector3, spawn: Vector3) -> void:
	_on_player_enter(_area(a, b), func() -> void: _spawn = spawn)


func _build_marker(at: Vector3) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tuning.marker_color
	mat.emission_enabled = tuning.marker_emission > 0.0
	mat.emission = tuning.marker_color
	mat.emission_energy_multiplier = tuning.marker_emission
	var gem := SphereMesh.new()
	gem.radial_segments = 4
	gem.rings = 1
	gem.radius = 1.2
	gem.height = 3.2
	gem.material = mat
	var beam := CylinderMesh.new()
	beam.top_radius = 0.12
	beam.bottom_radius = 0.12
	beam.height = 2.5
	beam.material = mat
	var marker := Node3D.new()
	marker.name = "Marker"
	marker.position = at
	for part: Array in [[gem, Vector3.ZERO], [beam, Vector3(0, -2.9, 0)]]:
		var instance := MeshInstance3D.new()
		instance.mesh = part[0]
		instance.position = part[1]
		marker.add_child(instance)
	_built.add_child(marker)
	return marker


func _build_switch(at: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.1, 0.08)
	var button := CylinderMesh.new()
	button.top_radius = 0.6
	button.bottom_radius = 0.7
	button.height = 0.25
	button.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = button
	instance.position = at + Vector3(0, 0.12, 0)
	_built.add_child(instance)
	_on_player_enter(_area(at + Vector3(-1, 0, 1), at + Vector3(1, 1.5, -1)), _press_switch)


func _build_sign(at: Vector3) -> void:
	var wood := _mat(Color(0.55, 0.38, 0.22))
	_box(at + Vector3(-0.1, 0, 0.1), at + Vector3(0.1, 1.2, -0.1), wood)
	_box(at + Vector3(-1.2, 1.2, 0.05), at + Vector3(1.2, 2.4, -0.05), wood)
	var label := Label3D.new()
	label.text = "EXIT"
	label.font_size = 96
	label.outline_size = 12
	label.position = at + Vector3(0, 2.05, 0.07)
	_built.add_child(label)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.9, 0.8)
	var shaft := BoxMesh.new()
	shaft.size = Vector3(1.0, 0.25, 0.05)
	shaft.material = paint
	var head := PrismMesh.new()
	head.size = Vector3(0.6, 0.6, 0.05)
	head.material = paint
	var arrow := Node3D.new()
	arrow.name = "Arrow"
	arrow.position = at + Vector3(0, 1.5, 0.08)
	var shaft_instance := MeshInstance3D.new()
	shaft_instance.mesh = shaft
	shaft_instance.position.x = -0.15
	var head_instance := MeshInstance3D.new()
	head_instance.mesh = head
	head_instance.position.x = 0.5
	head_instance.rotation.z = -PI / 2.0
	arrow.add_child(shaft_instance)
	arrow.add_child(head_instance)
	if tuning.fork_arrow_points_to == "left":
		arrow.rotation.y = PI
	_built.add_child(arrow)


func _build_goal(at: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 0.4)
	var pad := CylinderMesh.new()
	pad.top_radius = 1.5
	pad.bottom_radius = 1.5
	pad.height = 0.2
	pad.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = pad
	instance.position = at + Vector3(0, 0.1, 0)
	_built.add_child(instance)
	_on_player_enter(_area(at + Vector3(-1.5, 0, 1.5), at + Vector3(1.5, 2, -1.5)), _finish)


# --- Runtime -----------------------------------------------------------------

func _enter_zone(id: String) -> void:
	_current_zone = id
	PlaytestTelemetry.event("zone_enter", {zone = id})
	match id:
		"plaza":
			_set_objective("Reach the beacon.")
		"hall":
			if not _switch_pressed:
				_set_objective(tuning.switch_prompt_text)
		"drop":
			if is_instance_valid(_enemy):
				_enemy.trigger(_player, tuning.enemy_aggro_delay)


func _exit_zone(id: String) -> void:
	if _current_zone == id:
		_current_zone = ""
	if id == "drop" and is_instance_valid(_enemy):
		_enemy.trigger(null, 0.0)
	PlaytestTelemetry.event("zone_exit", {zone = id})


func _set_objective(text: String) -> void:
	if _objective.text == text:
		return
	_objective.text = text
	PlaytestTelemetry.event("objective_update", {text = text})


func _press_switch() -> void:
	if _switch_pressed:
		return
	_switch_pressed = true
	var tween := create_tween()
	tween.tween_property(_gate, "position:y", _gate.position.y - 5.2, 1.0)
	tween.tween_callback(_gate.queue_free)
	_set_objective("The gate is open. Find the exit.")


func _finish() -> void:
	_set_objective("Course complete!")
	_banner.text = "Course complete!\nThanks for playing."
	_banner.show()
	_player.process_mode = Node.PROCESS_MODE_DISABLED


func _kill(cause: String) -> void:
	if _respawning:
		return
	_respawning = true
	PlaytestTelemetry.event("death", {cause = cause, zone = _current_zone})
	if _current_zone == "ledge":
		_ledge_deaths += 1
		if _ledge_deaths >= tuning.ledge_bypass_deaths and not _bridge_shown:
			_bridge_shown = true
			var gap := tuning.ledge_gap_width
			_box(Vector3(-1, -0.5, _ledge_z), Vector3(1, 0, _ledge_z - gap), _mat(Color(0.55, 0.38, 0.22)))
	_respawn_at.call_deferred(_spawn)
	_spawn_enemy.call_deferred()


func _respawn_at(at: Vector3) -> void:
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	var camera := _player.get_node(^"Target/Camera3D") as Camera3D
	camera.global_position = at + Vector3(0, 4.5, 3.5)
	camera.look_at(at + Vector3(0, 1.95, 0))
	camera.reset_physics_interpolation()
	if _respawning:
		_respawning = false
		PlaytestTelemetry.event("retry", {})


func _spawn_enemy() -> void:
	if is_instance_valid(_enemy):
		_enemy.free()
	_enemy = ENEMY_SCENE.instantiate()
	_enemy.position = _enemy_spawn
	_enemy.hit_player.connect(_kill.bind("enemy"))
	_built.add_child(_enemy)
