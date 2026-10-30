class_name Player
extends CharacterBody3D
## Movement is the Godot platformer demo's, unchanged: the level's gap widths are
## tuned against these numbers. The model turns to face the way it is moving.

const MAX_SPEED: float = 6.0
const TURN_SPEED: float = 40.0
const JUMP_VELOCITY: float = 12.5
const AIR_IDLE_DEACCEL: bool = false
const ACCEL: float = 14.0
const DEACCEL: float = 14.0
const AIR_ACCEL_FACTOR: float = 0.5
const SHARP_TURN_THRESHOLD: float = deg_to_rad(140.0)
## Upward speed after stomping an enemy.
const BOUNCE_VELOCITY: float = 9.0
const LOOPING_ANIMS: Array[StringName] = [&"idle", &"walk", &"sprint", &"fall"]

var jumping: bool = false
var _facing := Vector3.FORWARD

@onready var _camera := $Target/Camera3D as FollowCamera
@onready var _model := $Model as Node3D
@onready var _animation := $Model/AnimationPlayer as AnimationPlayer


func _ready() -> void:
	for anim in LOOPING_ANIMS:
		_animation.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
	_animation.play(&"idle")
	# Layer 2 keeps the blob shadow off the player's own body.
	for mesh: VisualInstance3D in _model.find_children("*", "VisualInstance3D"):
		mesh.layers = 2


## Stand at `at` facing `yaw` (0 faces -Z), with the camera behind.
func place(at: Vector3, yaw: float) -> void:
	global_position = at
	velocity = Vector3.ZERO
	jumping = false
	_facing = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	_model.basis = Basis.looking_at(_facing, Vector3.UP, true).scaled(_model.basis.get_scale())
	reset_physics_interpolation()
	_camera.snap(yaw)


func bounce() -> void:
	velocity.y = BOUNCE_VELOCITY
	jumping = true


func _physics_process(delta: float) -> void:
	velocity += get_gravity() * delta

	var vertical_velocity := velocity.y
	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)

	var horizontal_direction := horizontal_velocity.normalized()
	var horizontal_speed := horizontal_velocity.length()

	# Player input.
	var cam_basis := _camera.get_global_transform().basis
	var movement_vec2 := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var movement_direction := cam_basis * Vector3(movement_vec2.x, 0, movement_vec2.y)
	movement_direction.y = 0
	movement_direction = movement_direction.normalized()

	var jump_attempt := Input.is_action_pressed(&"jump")

	if is_on_floor():
		var sharp_turn := horizontal_speed > 0.1 and \
				acos(movement_direction.dot(horizontal_direction)) > SHARP_TURN_THRESHOLD

		if movement_direction.length() > 0.1 and not sharp_turn:
			if horizontal_speed > 0.001:
				horizontal_direction = adjust_facing(
						horizontal_direction,
						movement_direction,
						delta,
						1.0 / horizontal_speed * TURN_SPEED,
						Vector3.UP
					)
			else:
				horizontal_direction = movement_direction

			if horizontal_speed < MAX_SPEED:
				horizontal_speed += ACCEL * delta
		else:
			horizontal_speed -= DEACCEL * delta
			if horizontal_speed < 0:
				horizontal_speed = 0

		horizontal_velocity = horizontal_direction * horizontal_speed

		if not jumping and jump_attempt:
			vertical_velocity = JUMP_VELOCITY
			jumping = true
			$SoundJump.play()

	else:
		if movement_direction.length() > 0.1:
			horizontal_velocity += movement_direction * (ACCEL * AIR_ACCEL_FACTOR * delta)
			if horizontal_velocity.length() > MAX_SPEED:
				horizontal_velocity = horizontal_velocity.normalized() * MAX_SPEED
		elif AIR_IDLE_DEACCEL:
			horizontal_speed = horizontal_speed - (DEACCEL * AIR_ACCEL_FACTOR * delta)
			if horizontal_speed < 0:
				horizontal_speed = 0
			horizontal_velocity = horizontal_direction * horizontal_speed

		if Input.is_action_just_released(&"jump") and velocity.y > 0.0:
			# Reduce jump height if releasing the jump key before reaching the apex.
			vertical_velocity *= 0.7

	if jumping and vertical_velocity < 0:
		jumping = false

	velocity = horizontal_velocity + Vector3.UP * vertical_velocity

	move_and_slide()

	_animate(delta)


func _animate(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	if horizontal.length() > 0.5:
		var target := horizontal.normalized()
		_facing = _facing.slerp(target, minf(1.0, 14.0 * delta)).normalized() \
				if _facing.dot(target) > -0.99 else target
		_model.basis = Basis.looking_at(_facing, Vector3.UP, true).scaled(_model.basis.get_scale())

	var anim := &"idle"
	var anim_speed := 1.0
	if not is_on_floor():
		anim = &"jump" if velocity.y > 0.0 else &"fall"
	elif horizontal.length() > MAX_SPEED * 0.6:
		anim = &"sprint"
		anim_speed = horizontal.length() / MAX_SPEED * 1.2
	elif horizontal.length() > 0.3:
		anim = &"walk"
		anim_speed = 1.5
	if _animation.current_animation != anim:
		_animation.play(anim, 0.12)
	_animation.speed_scale = anim_speed


func adjust_facing(facing: Vector3, target: Vector3, step: float, adjust_rate: float, \
		current_gn: Vector3) -> Vector3:
	var normal := target
	var t := normal.cross(current_gn).normalized()

	var x := normal.dot(facing)
	var y := t.dot(facing)

	var ang := atan2(y,x)

	if absf(ang) < 0.001:
		return facing

	var s := signf(ang)
	ang = ang * s
	var turn := ang * adjust_rate * step
	var a: float
	if ang < turn:
		a = ang
	else:
		a = turn
	ang = (ang - a) * s

	return (normal * cos(ang) + t * sin(ang)) * facing.length()
