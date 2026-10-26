class_name FollowCamera
extends Camera3D
## Follows the player from a fixed angle, a little above them and looking
## slightly down. The angle only changes when the player turns it: the mouse
## (click to capture, Esc to release) or the right stick orbits it and raises
## or lowers it. Walls pull it in at once; it eases back out when they clear.

const DISTANCE := 7.5
const HEIGHT := 2.8
const MIN_HEIGHT := 0.4
const MAX_HEIGHT := 6.5
## It looks at this point above the player's target, so the horizon stays in view.
const LOOK_UP := 1.0
const MOUSE_SENSITIVITY := 0.004
const STICK_SPEED := 2.5
## The camera is a ball this size, so it can't clip into a wall it grazes.
const RADIUS := 0.3
const MIN_DISTANCE := 1.0
## How fast it eases back out once a wall stops blocking it, in metres per second.
const EASE_OUT_SPEED := 6.0

var _yaw := 0.0
var _height := HEIGHT
var _distance := DISTANCE
var _query := PhysicsShapeQueryParameters3D.new()

@onready var _target := get_parent() as Node3D


func _ready() -> void:
	var ball := SphereShape3D.new()
	ball.radius = RADIUS
	_query.shape = ball
	_query.exclude = [(_target.get_parent() as CollisionObject3D).get_rid()]
	set_as_top_level(true)


## Jump straight to the resting spot behind the player, facing `yaw`.
func snap(yaw: float) -> void:
	_yaw = yaw
	_height = HEIGHT
	_distance = DISTANCE
	_place(0.0)
	reset_physics_interpolation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		_yaw -= motion.x * MOUSE_SENSITIVITY
		_height = clampf(_height + motion.y * MOUSE_SENSITIVITY * 4.0, MIN_HEIGHT, MAX_HEIGHT)


func _physics_process(delta: float) -> void:
	var stick := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(stick) > 0.2:
		_yaw -= stick * STICK_SPEED * delta
	var stick_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(stick_y) > 0.2:
		_height = clampf(_height + stick_y * STICK_SPEED * 2.0 * delta, MIN_HEIGHT, MAX_HEIGHT)
	_place(delta)


## Sit behind the target at the current angle, as far out as the walls allow.
func _place(delta: float) -> void:
	var target := _target.global_position
	var offset := (Vector3(0, 0, DISTANCE).rotated(Vector3.UP, _yaw) + Vector3.UP * _height) / DISTANCE
	_query.transform = Transform3D(Basis.IDENTITY, target)
	_query.motion = offset * DISTANCE
	var clear := get_world_3d().direct_space_state.cast_motion(_query)[0] * DISTANCE
	_distance = maxf(MIN_DISTANCE, minf(clear, move_toward(_distance, DISTANCE, EASE_OUT_SPEED * delta)))
	look_at_from_position(target + offset * _distance, target + Vector3.UP * LOOK_UP, Vector3.UP)
