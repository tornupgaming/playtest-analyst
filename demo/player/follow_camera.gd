class_name FollowCamera
extends Camera3D
## Trails the player at a fixed distance, a little above them and looking
## slightly down. Walking sideways swings it round; the mouse (click to
## capture, Esc to release) or the right stick orbits it and raises or lowers
## it. Walls pull it in towards the player.

const DISTANCE := 7.5
const HEIGHT := 2.8
const MIN_HEIGHT := 0.4
const MAX_HEIGHT := 6.5
## It looks at this point above the player's target, so the horizon stays in view.
const LOOK_UP := 1.0
const MOUSE_SENSITIVITY := 0.004
const STICK_SPEED := 2.5
const WALL_MARGIN := 0.4

var _orbit := 0.0
var _height := HEIGHT
var _exclude: Array[RID] = []

@onready var _target := get_parent() as Node3D


func _ready() -> void:
	_exclude.append((_target.get_parent() as CollisionObject3D).get_rid())
	set_as_top_level(true)


## Jump straight to the resting spot behind the player, facing `yaw`.
func snap(yaw: float) -> void:
	_height = HEIGHT
	_place(_target.global_position + Vector3(0, 0, DISTANCE).rotated(Vector3.UP, yaw))
	reset_physics_interpolation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		_orbit -= motion.x * MOUSE_SENSITIVITY
		_height = clampf(_height + motion.y * MOUSE_SENSITIVITY * 4.0, MIN_HEIGHT, MAX_HEIGHT)


func _physics_process(delta: float) -> void:
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(stick) > 0.2:
		_orbit -= stick * STICK_SPEED * delta
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(stick_y) > 0.2:
		_height = clampf(_height + stick_y * STICK_SPEED * 2.0 * delta, MIN_HEIGHT, MAX_HEIGHT)
	var offset := global_position - _target.global_position
	offset.y = 0.0
	offset = offset.rotated(Vector3.UP, _orbit)
	_orbit = 0.0
	_place(_target.global_position + offset)


## Rest DISTANCE behind and _height above the target, on the line from it to
## `from`, pulled in if a wall is in the way.
func _place(from: Vector3) -> void:
	var target := _target.global_position
	var flat := from - target
	flat.y = 0.0
	if flat.length() < 0.01:
		flat = Vector3.BACK
	var wanted := target + flat.normalized() * DISTANCE + Vector3.UP * _height
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(target, wanted, 0xffffffff, _exclude))
	if hit:
		var at: Vector3 = hit.position
		wanted = at + (target - at).normalized() * WALL_MARGIN
	look_at_from_position(wanted, target + Vector3.UP * LOOK_UP, Vector3.UP)
