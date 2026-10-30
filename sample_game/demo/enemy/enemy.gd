extends RigidBody3D
## Waits until `trigger()` is called, then charges the target `delay` seconds
## after it lands. Touching the target emits `hit_player`, unless the target
## lands on top of it: a stomp squashes it.

signal hit_player

const ACCEL: float = 20.0
const DEACCEL: float = 20.0
const MAX_SPEED: float = 4.5
## How far above the enemy's origin the player's feet must be to stomp it.
const STOMP_HEIGHT: float = 0.7

var dying: bool = false
var _target: CharacterBody3D
var _wait: float = 0.0
var _landed: bool = false
var _charging := false
var _clock := 0.0

@onready var _pivot := $Pivot as Node3D
@onready var _model := $Pivot/Model as Node3D
@onready var _ray_floor := $Pivot/RayFloor as RayCast3D


func _ready() -> void:
	var hurtbox := Area3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 1.1
	shape.position = Vector3(0, 0.8, 0)
	hurtbox.add_child(shape)
	add_child(hurtbox)
	hurtbox.body_entered.connect(_on_touch)


## Charge `target` `delay` seconds after it first touches the floor.
## Pass null to stand down.
func trigger(target: CharacterBody3D, delay: float) -> void:
	_target = target
	_wait = delay
	_landed = false


func _on_touch(body: Node3D) -> void:
	if dying or not body is Player:
		return
	var player := body as Player
	if player.velocity.y < 0.0 and player.global_position.y > global_position.y + STOMP_HEIGHT:
		player.bounce()
		_die()
	else:
		hit_player.emit()


func _process(delta: float) -> void:
	if dying:
		return
	# Idle: a slow breathing squash. Charging: quick hops.
	_clock += delta
	if _charging:
		var hop := absf(sin(_clock * 14.0))
		_model.position.y = hop * 0.25
		_model.scale = Vector3(1.0 + (1.0 - hop) * 0.12, 1.0 - (1.0 - hop) * 0.12, 1.0 + (1.0 - hop) * 0.12)
	else:
		var breath := sin(_clock * 3.0) * 0.04
		_model.position.y = 0.0
		_model.scale = Vector3(1.0 - breath, 1.0 + breath, 1.0 - breath)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.get_step()
	var lin_velocity := state.get_linear_velocity() + get_gravity() * delta
	var up := -get_gravity().normalized()

	if dying:
		state.set_linear_velocity(Vector3.ZERO)
		return

	var horizontal := Vector3(lin_velocity.x, 0, lin_velocity.z)
	if _target != null and _target.is_on_floor():
		_landed = true
	if _landed:
		_wait -= delta
	var charging := _target != null and _landed and _wait <= 0.0
	if _target != null and not charging:
		_face(_target.global_position - global_position, up)

	_charging = charging and _ray_floor.is_colliding()
	if _charging:
		if not $SoundWalkLoop.playing:
			$SoundWalkLoop.play()
		var dir := _face(_target.global_position - global_position, up)
		horizontal = (horizontal + dir * ACCEL * delta).limit_length(MAX_SPEED)
	else:
		$SoundWalkLoop.stop()
		horizontal = horizontal.move_toward(Vector3.ZERO, DEACCEL * delta)

	state.set_linear_velocity(horizontal + up * lin_velocity.dot(up))


## Turn to face `to` on the horizontal plane and return that direction.
func _face(to: Vector3, up: Vector3) -> Vector3:
	var dir := (to - up * to.dot(up)).normalized()
	if not dir.is_zero_approx():
		_pivot.basis = Basis.looking_at(dir, up, true)
	return dir


func _die() -> void:
	dying = true
	# Called from a physics callback, so collision changes wait for the next step.
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	$SoundWalkLoop.stop()
	$SoundHit.play()
	$Puff.emitting = true
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3(1.5, 0.15, 1.5), 0.12)
	tween.tween_interval(0.3)
	tween.tween_property(_model, "scale", Vector3.ZERO, 0.15)
	tween.tween_interval(0.6)
	tween.tween_callback(queue_free)
