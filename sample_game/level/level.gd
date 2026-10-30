@tool
extends Node3D
## The test course. The level is built in code at `_ready()` so that every
## value that differs between builds comes from `tuning` and nowhere else.
## The course runs along -Z: start, ledge, plaza, hall, drop, fork, corridor, finish.

const KILL_Y := -10.0
const CORRIDOR_SEGMENT_LENGTH := 20.0
const ENEMY_SCENE := preload("res://demo/enemy/enemy.tscn")
const GRASS := preload("res://art/blocks/grass.tres")
const SAND := preload("res://art/blocks/sand.tres")
const STONE := preload("res://art/blocks/stone.tres")
const WOOD := preload("res://art/blocks/wood.tres")
const HEDGE := preload("res://art/blocks/hedge.tres")
const SMALL_PLANTS: Array[StringName] = [&"grass", &"flowers", &"flowers-tall", &"plant", &"mushrooms"]

@export var tuning: LevelTuning

var _spawn: Vector3
var _current_zone := ""
var _ledge_deaths := 0
var _bridge_shown := false
var _switch_pressed := false
var _respawning := false
var _enemy: RigidBody3D
var _models := {}
var _rng := RandomNumberGenerator.new()

# Section anchors, filled in by _build() and used by the runtime handlers.
var _ledge_z: float
var _enemy_spawn: Vector3
var _gate: Node3D
var _marker: Node3D
var _switch_animation: AnimationPlayer

@onready var _built := $Built as Node3D
@onready var _player := $Player as Player
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
	# Paths and cliffs are grass-topped clay. Past the drop, the walls are hedges.
	# Blocks meet edge to edge: overlapping ones share faces, which flicker.
	var wall: Material = GRASS
	_rng.seed = 7

	# Start, with a short practice gap.
	_spawn = Vector3(0, 0, -1)
	_box(Vector3(-5, -1, 2), Vector3(5, 0, -20), GRASS)
	_box(Vector3(-5, -1, -22.5), Vector3(5, 0, -32), GRASS)
	_prop(&"tree", Vector3(-4.2, 0, 1.4), Vector3.ONE * 2.2)
	_prop(&"tree-pine", Vector3(4.2, 0, 1.3), Vector3.ONE * 2.0)
	for side in [-1, 1]:
		_scatter(Vector3(side * 4.6, 0, 1.5), Vector3(side * 3.8, 0, -19.5), SMALL_PLANTS, 9)
		_scatter(Vector3(side * 4.6, 0, -23), Vector3(side * 3.8, 0, -31.5), SMALL_PLANTS, 4)

	# Ledge: a narrow run-up, a gap, and a landing.
	var gap := tuning.ledge_gap_width
	_ledge_z = -44.0
	var z0 := _ledge_z - gap - 8.0
	_box(Vector3(-2, -1, -32), Vector3(2, 0, _ledge_z), GRASS)
	_box(Vector3(-2, -1, _ledge_z - gap), Vector3(2, 0, z0), GRASS)
	_checkpoint(Vector3(-2, 0, -32), Vector3(2, 4, -36), Vector3(0, 0, -34))
	_checkpoint(Vector3(-2, 0, z0 + 6), Vector3(2, 4, z0), Vector3(0, 0, z0 + 3))
	_zone("ledge", Vector3(-20, -14, -32), Vector3(20, 8, z0))
	for side in [-1, 1]:
		_scatter(Vector3(side * 1.75, 0, -36), Vector3(side * 1.55, 0, _ledge_z + 2), [&"grass"], 3)

	# Plaza: the way on is up the stepping blocks to the terrace door.
	_box(Vector3(-20, -1, z0), Vector3(20, 0, z0 - 40), SAND)
	_box(Vector3(-21, 0, z0), Vector3(-20, 16, z0 - 40), wall)
	_box(Vector3(20, 0, z0), Vector3(21, 16, z0 - 40), wall)
	_box(Vector3(-21, 0, z0 + 1), Vector3(-2, 6, z0), wall)
	_box(Vector3(2, 0, z0 + 1), Vector3(21, 6, z0), wall)
	_box(Vector3(-20, 0, z0 - 30), Vector3(20, 8, z0 - 40), wall)
	_box(Vector3(-21, 8, z0 - 40), Vector3(-2, 16, z0 - 41), wall)
	_box(Vector3(2, 8, z0 - 40), Vector3(21, 16, z0 - 41), wall)
	_box(Vector3(-2, 13, z0 - 40), Vector3(2, 16, z0 - 41), wall)
	for i in 3:
		var top := 2.0 + 2.0 * i
		var z := z0 - 18.0 - 4.0 * i
		_box(Vector3(14.5, top - 1, z + 1.5), Vector3(17.5, top, z - 1.5), GRASS)
	for p: Vector2 in [Vector2(-12, -8), Vector2(-12, -20), Vector2(12, -8), Vector2(12, -20),
			Vector2(-6, -14), Vector2(6, -14), Vector2(12, -26), Vector2(-12, -26)]:
		_box(Vector3(p.x - 1, 0, z0 + p.y + 1), Vector3(p.x + 1, 10, z0 + p.y - 1), GRASS)
	for c: Vector3 in [Vector3(-16, 0, -5), Vector3(-15, 0, -24), Vector3(4, 0, -22), Vector3(-3, 0, -9)]:
		_crate(Vector3(c.x - 1, 0, z0 + c.z + 1), Vector3(c.x + 1, 1.5, z0 + c.z - 1))
	_marker = _build_marker(Vector3(0, 14.5, z0 - 39.4))
	for side in [-1, 1]:
		_scatter(Vector3(side * 19.5, 0, z0 - 1), Vector3(side * 18, 0, z0 - 29), SMALL_PLANTS + [&"rocks"], 10)
		_row(&"tree", Vector3(side * 20.5, 16, z0 - 2), Vector3(side * 20.5, 16, z0 - 38), 4, 2.6)
		_row(&"tree-pine", Vector3(side * 12, 6, z0 + 0.5), Vector3(side * 4, 6, z0 + 0.5), 3, 1.8)
	_prop(&"barrel", Vector3(-13.8, 0, z0 - 5.5), Vector3.ONE * 2.5)
	_prop(&"barrel", Vector3(-13.6, 0, z0 - 23), Vector3.ONE * 2.5)
	_zone("plaza", Vector3(-20, -2, z0), Vector3(20, 16, z0 - 40))

	# Hall: a gate at the far end, opened by the switch on the balcony.
	var z1 := z0 - 40.0
	_box(Vector3(-9, -1, z1), Vector3(9, 8, z1 - 30), STONE)
	_box(Vector3(-9, 8, z1 - 1), Vector3(-8, 16, z1 - 30), wall)
	_box(Vector3(8, 8, z1 - 1), Vector3(9, 16, z1 - 30), wall)
	_box(Vector3(-9, 8, z1 - 30), Vector3(-2, 16, z1 - 31), wall)
	_box(Vector3(2, 8, z1 - 30), Vector3(9, 16, z1 - 31), wall)
	_box(Vector3(-2, 13, z1 - 30), Vector3(2, 16, z1 - 31), wall)
	_box(Vector3(-2, -1, z1 - 30), Vector3(2, 8, z1 - 31), STONE)
	_gate = _box(Vector3(-2, 8, z1 - 30.2), Vector3(2, 13, z1 - 30.8), WOOD)
	_box(Vector3(-8, 10.6, z1 - 12), Vector3(-5, 11, z1 - 18), WOOD)
	_crate(Vector3(-7.5, 8, z1 - 20.5), Vector3(-5.5, 9.5, z1 - 22.5))
	_crate(Vector3(5, 8, z1 - 8), Vector3(7, 9.5, z1 - 10))
	_crate(Vector3(4.5, 8, z1 - 19), Vector3(7.5, 10, z1 - 22))
	_build_switch(Vector3(-6.5, 11, z1 - 15))
	_checkpoint(Vector3(-2, 8, z1), Vector3(2, 12, z1 - 3), Vector3(0, 8, z1 - 1.5))
	_zone("hall", Vector3(-8, 7, z1), Vector3(8, 16, z1 - 30))
	for side in [-1, 1]:
		_scatter(Vector3(side * 7.6, 8, z1 - 1), Vector3(side * 7.0, 8, z1 - 29), [&"mushrooms", &"grass", &"rocks"], 6)
		_row(&"tree-pine", Vector3(side * 8.5, 16, z1 - 3), Vector3(side * 8.5, 16, z1 - 27), 4, 2.4)

	# Tunnel to a hole that drops into an enclosed room with the enemy.
	var z2 := z1 - 31.0
	_box(Vector3(-3, -1, z2), Vector3(3, 8, z2 - 6), STONE)
	_box(Vector3(-2, 7, z2 - 6), Vector3(2, 8, z2 - 10), STONE)
	_box(Vector3(-3, 8, z2), Vector3(-2, 13, z2 - 15), wall)
	_box(Vector3(2, 8, z2), Vector3(3, 13, z2 - 15), wall)
	_box(Vector3(-2, 8, z2 - 14), Vector3(2, 13, z2 - 15), wall)
	_box(Vector3(-3, 13, z2), Vector3(3, 13.5, z2 - 15), wall)
	_checkpoint(Vector3(-2, 8, z2), Vector3(2, 12, z2 - 3), Vector3(0, 8, z2 - 1.5))
	_box(Vector3(-9, 7, z2 - 6), Vector3(-2, 8, z2 - 26), STONE)
	_box(Vector3(2, 7, z2 - 6), Vector3(9, 8, z2 - 26), STONE)
	_box(Vector3(-2, 7, z2 - 14), Vector3(2, 8, z2 - 26), STONE)
	_box(Vector3(-8, -1, z2 - 6), Vector3(8, 0, z2 - 26), GRASS)
	_box(Vector3(-9, 0, z2 - 6), Vector3(-8, 7, z2 - 26), wall)
	_box(Vector3(8, 0, z2 - 6), Vector3(9, 7, z2 - 26), wall)
	_box(Vector3(-9, 0, z2 - 5), Vector3(-3, 7, z2 - 6), wall)
	_box(Vector3(3, 0, z2 - 5), Vector3(9, 7, z2 - 6), wall)
	_box(Vector3(-9, 0, z2 - 26), Vector3(-2, 7, z2 - 27), wall)
	_box(Vector3(2, 0, z2 - 26), Vector3(9, 7, z2 - 27), wall)
	_box(Vector3(-2, 4, z2 - 26), Vector3(2, 7, z2 - 27), wall)
	_box(Vector3(-2, -1, z2 - 26), Vector3(2, 0, z2 - 27), GRASS)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 6, z2 - 18)
	lamp.omni_range = 18.0
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 2.0
	_built.add_child(lamp)
	_enemy_spawn = Vector3(0, 0, z2 - 20)
	_zone("drop", Vector3(-8, 0, z2 - 6), Vector3(8, 7, z2 - 26))
	for side in [-1, 1]:
		_scatter(Vector3(side * 7.6, 0, z2 - 7), Vector3(side * 6.6, 0, z2 - 25), [&"mushrooms", &"rocks", &"stones"], 5)

	# Fork: a signpost, a walled branch each way. Left ends in a dead end;
	# right turns into the corridor.
	var z3 := z2 - 27.0
	wall = HEDGE
	_box(Vector3(-2, -1, z3), Vector3(2, 0, z3 - 8), GRASS)
	_box(Vector3(-3, 0, z3), Vector3(-2, 4, z3 - 7), wall)
	_box(Vector3(2, 0, z3), Vector3(3, 4, z3 - 7), wall)
	_box(Vector3(-5, -1, z3 - 8), Vector3(5, 0, z3 - 18), GRASS)
	_box(Vector3(-6, 0, z3 - 7), Vector3(-2, 4, z3 - 8), wall)
	_box(Vector3(2, 0, z3 - 7), Vector3(6, 4, z3 - 8), wall)
	_box(Vector3(-6, 0, z3 - 18), Vector3(6, 4, z3 - 19), wall)
	_build_sign(Vector3(0, 0, z3 - 16.5))
	_scatter(Vector3(-1.5, 0, z3 - 15.8), Vector3(1.5, 0, z3 - 17.4), [&"flowers", &"flowers-tall"], 4)
	_checkpoint(Vector3(-2, 0, z3), Vector3(2, 4, z3 - 3), Vector3(0, 0, z3 - 1.5))
	_zone("fork", Vector3(-5, -1, z3), Vector3(5, 6, z3 - 18))
	var corridor_end := z3 - 15.0 - tuning.corridor_segments * CORRIDOR_SEGMENT_LENGTH
	for side in [-1, 1]:
		_box(Vector3(side * 6, 0, z3 - 8), Vector3(side * 5, 4, z3 - 10), wall)
		_box(Vector3(side * 6, 0, z3 - 16), Vector3(side * 5, 4, z3 - 18), wall)
		_box(Vector3(side * 5, -1, z3 - 11), Vector3(side * 21, 0, z3 - 15), GRASS)
		_box(Vector3(side * 5, 0, z3 - 10), Vector3(side * 22, 4, z3 - 11), wall)
		_box(Vector3(side * 5, 0, z3 - 15), Vector3(side * 17, 4, z3 - 16), wall)
		var end := corridor_end if side == 1 else z3 - 35.0
		_box(Vector3(side * 17, -1, z3 - 15), Vector3(side * 21, 0, end), GRASS)
		_box(Vector3(side * 21, 0, z3 - 11), Vector3(side * 22, 4, end), wall)
		_box(Vector3(side * 16, 0, z3 - 16), Vector3(side * 17, 4, end), wall)
	_box(Vector3(-22, 0, z3 - 35), Vector3(-16, 4, z3 - 36), wall)
	_zone("fork_left", Vector3(-21, -1, z3 - 11), Vector3(-5.2, 6, z3 - 35))

	# Corridor: identical segments with a pillar pair at each joint.
	for i in tuning.corridor_segments:
		var z := z3 - 15.0 - i * CORRIDOR_SEGMENT_LENGTH
		_box(Vector3(17, 0, z - 0.5), Vector3(17.6, 5, z - 1.5), STONE)
		_box(Vector3(20.4, 0, z - 0.5), Vector3(21, 5, z - 1.5), STONE)
	_checkpoint(Vector3(17, 0, z3 - 11), Vector3(21, 4, z3 - 15), Vector3(19, 0, z3 - 13))
	_zone("corridor", Vector3(17, -1, z3 - 15), Vector3(21, 6, corridor_end))

	# Finish.
	_box(Vector3(15, -1, corridor_end), Vector3(23, 0, corridor_end - 10), SAND)
	_box(Vector3(14, 0, corridor_end), Vector3(17, 4, corridor_end - 10), wall)
	_box(Vector3(21, 0, corridor_end), Vector3(24, 4, corridor_end - 10), wall)
	_box(Vector3(14, 0, corridor_end - 10), Vector3(24, 4, corridor_end - 11), wall)
	_build_goal(Vector3(19, 0, corridor_end - 6))
	for side in [-1, 1]:
		_scatter(Vector3(19 + side * 3.6, 0, corridor_end - 1), Vector3(19 + side * 2.8, 0, corridor_end - 9.5), SMALL_PLANTS, 5)

	_build_backdrop(-corridor_end + 20.0)


## A solid block spanning the two corners.
func _box(a: Vector3, b: Vector3, mat: Material) -> StaticBody3D:
	var body := _solid(a, b)
	body.add_child(_block_mesh((b - a).abs(), mat))
	return body


## Collision only, spanning the two corners.
func _solid(a: Vector3, b: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = (a + b) / 2.0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = (b - a).abs()
	body.add_child(shape)
	_built.add_child(body)
	return body


func _block_mesh(size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.set_instance_shader_parameter(&"box_size", size)
	return instance


## A solid crate spanning the two corners.
func _crate(a: Vector3, b: Vector3) -> void:
	var body := _solid(a, b)
	_prop(&"crate", Vector3(body.position.x, minf(a.y, b.y), body.position.z), (b - a).abs() / 0.5)


## A Kenney model from art/kenney, standing at `at`. Decoration has no collision.
func _prop(model: StringName, at: Vector3, size: Vector3, yaw := 0.0) -> Node3D:
	if not _models.has(model):
		_models[model] = load("res://art/kenney/%s.glb" % model)
	var node := (_models[model] as PackedScene).instantiate() as Node3D
	node.position = at
	node.rotation.y = yaw
	node.scale = size
	_built.add_child(node)
	return node


## `count` random picks from `models` across the floor rectangle a..b.
func _scatter(a: Vector3, b: Vector3, models: Array, count: int) -> void:
	for i in count:
		var at := Vector3(_rng.randf_range(a.x, b.x), a.y, _rng.randf_range(a.z, b.z))
		var model: StringName = models[_rng.randi() % models.size()]
		_prop(model, at, Vector3.ONE * _rng.randf_range(1.6, 2.4), _rng.randf() * TAU)


## `count` copies of `model` evenly spaced from a to b.
func _row(model: StringName, a: Vector3, b: Vector3, count: int, size: float) -> void:
	for i in count:
		var at := a.lerp(b, i / maxf(1.0, count - 1.0))
		_prop(model, at, Vector3.ONE * size * _rng.randf_range(0.85, 1.15), _rng.randf() * TAU)


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
		var bottom := minf(a.y, b.y)
		area.body_exited.connect(func(body: Node3D) -> void:
			if body == _player:
				_exit_zone(id, _player.global_position.y < bottom))


func _checkpoint(a: Vector3, b: Vector3, spawn: Vector3) -> void:
	_on_player_enter(_area(a, b), func() -> void: _spawn = spawn)


func _build_marker(at: Vector3) -> Node3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tuning.marker_color
	mat.emission_enabled = tuning.marker_emission > 0.0
	mat.emission = tuning.marker_color
	mat.emission_energy_multiplier = tuning.marker_emission
	var marker := _prop(&"star", at + Vector3(0, -1.4, 0), Vector3.ONE * 8.0)
	marker.name = "Marker"
	for mesh: MeshInstance3D in marker.find_children("*", "MeshInstance3D"):
		mesh.material_override = mat
	return marker


func _build_switch(at: Vector3) -> void:
	var button := _prop(&"button-round", at, Vector3.ONE * 2.5)
	_switch_animation = button.find_child("AnimationPlayer") as AnimationPlayer
	_on_player_enter(_area(at + Vector3(-1, 0, 1), at + Vector3(1, 1.5, -1)), _press_switch)


func _build_sign(at: Vector3) -> void:
	# The model points +X. Mirroring it keeps the board's face towards the player.
	var mirror := -1.0 if tuning.fork_arrow_points_to == "left" else 1.0
	var arrow := _prop(&"arrow", at, Vector3(4.0 * mirror, 4.0, 4.0))
	arrow.name = "Arrow"
	var label := Label3D.new()
	label.text = "EXIT"
	label.font_size = 96
	label.outline_size = 16
	label.modulate = Color(1, 0.97, 0.88)
	label.outline_modulate = Color(0.35, 0.19, 0.13)
	label.position = at + Vector3(0, 3.2, 0.4)
	_built.add_child(label)


func _build_goal(at: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.27)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.27)
	mat.emission_energy_multiplier = 0.6
	var pad := CylinderMesh.new()
	pad.top_radius = 1.5
	pad.bottom_radius = 1.6
	pad.height = 0.2
	pad.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = pad
	instance.position = at + Vector3(0, 0.1, 0)
	_built.add_child(instance)
	_prop(&"flag", at + Vector3(-0.3, 0.2, 0), Vector3.ONE * 5.0)
	_on_player_enter(_area(at + Vector3(-1.5, 0, 1.5), at + Vector3(1.5, 2, -1.5)), _finish)


## Grass-topped mesas rising out of the clouds either side of the course, out of
## reach, with trees on top. Visual only.
func _build_backdrop(length: float) -> void:
	for side in [-1, 1]:
		var z := 40.0
		while z > -length - 40.0:
			var x: float = side * _rng.randf_range(42.0, 110.0)
			var size := Vector3(_rng.randf_range(8.0, 22.0), 0.0, _rng.randf_range(8.0, 22.0))
			var top := _rng.randf_range(-8.0, 22.0)
			size.y = top + 60.0
			var mesa := _block_mesh(size, GRASS)
			mesa.position = Vector3(x, top - size.y / 2.0, z)
			_built.add_child(mesa)
			for i in _rng.randi_range(1, 3):
				var at := mesa.position + Vector3(_rng.randf_range(-0.35, 0.35) * size.x, size.y / 2.0,
						_rng.randf_range(-0.35, 0.35) * size.z)
				_prop([&"tree", &"tree-pine"][_rng.randi() % 2], at, Vector3.ONE * _rng.randf_range(3.0, 5.0))
			z -= _rng.randf_range(18.0, 38.0)
	var puff := SphereMesh.new()
	puff.radial_segments = 16
	puff.rings = 8
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1, 1, 1)
	white.roughness = 1.0
	puff.material = white
	for i in int(length / 12.0):
		var centre := Vector3(_rng.randf_range(-140.0, 140.0), _rng.randf_range(-16.0, -6.0),
				_rng.randf_range(40.0, -length - 40.0))
		if absf(centre.x) < 30.0:
			centre.y -= 10.0
		for j in _rng.randi_range(3, 6):
			var instance := MeshInstance3D.new()
			instance.mesh = puff
			var r := _rng.randf_range(2.5, 6.0)
			instance.scale = Vector3(r * 1.3, r, r * 1.3)
			instance.position = centre + Vector3(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-1.0, 1.5), _rng.randf_range(-4.0, 4.0))
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_built.add_child(instance)


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


## A player who falls out of the bottom of a zone is still in it until they hit
## KILL_Y, so the death is logged in the zone they fell from.
func _exit_zone(id: String, fell: bool) -> void:
	if _current_zone == id and not fell:
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
	_switch_animation.play(&"toggle-on")
	var tween := create_tween()
	tween.tween_property(_gate, "position:y", _gate.position.y - 5.2, 1.0)
	tween.tween_callback(_gate.queue_free)
	_set_objective("The gate is open. Find the exit.")


func _finish() -> void:
	_set_objective("Course complete!")
	_banner.text = "Course complete!\nThanks for playing."
	_banner.show()
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
			_box(Vector3(-1, -0.5, _ledge_z), Vector3(1, 0, _ledge_z - gap), WOOD)
	_respawn_at.call_deferred(_spawn)
	_spawn_enemy.call_deferred()


func _respawn_at(at: Vector3) -> void:
	_player.place(at, 0.0)
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
