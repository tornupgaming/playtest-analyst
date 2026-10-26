extends RigidBody3D
## Waits until `trigger()` is called, then charges the target `delay` seconds
## after it lands. Touching the target emits `hit_player`.
## A bullet kills it.

signal hit_player

const ACCEL: float = 20.0
const DEACCEL: float = 20.0
const MAX_SPEED: float = 4.5

var dying: bool = false
var _target: CharacterBody3D
var _wait: float = 0.0
var _landed: bool = false

@onready var _animation_player := $Enemy/AnimationPlayer as AnimationPlayer
@onready var _ray_floor := $Enemy/Skeleton/RayFloor as RayCast3D
@onready var _skeleton := $Enemy/Skeleton as Node3D


func _ready() -> void:
	var hurtbox := Area3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	(shape.shape as SphereShape3D).radius = 1.1
	shape.position = Vector3(0, 0.8, 0.3)
	hurtbox.add_child(shape)
	add_child(hurtbox)
	hurtbox.body_entered.connect(func(body: Node3D) -> void:
		if not dying and body is Player:
			hit_player.emit())


## Charge `target` `delay` seconds after it first touches the floor.
## Pass null to stand down.
func trigger(target: CharacterBody3D, delay: float) -> void:
	_target = target
	_wait = delay
	_landed = false


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var delta := state.get_step()
	var lin_velocity := state.get_linear_velocity() + get_gravity() * delta
	var up := -get_gravity().normalized()

	if dying:
		state.set_linear_velocity(lin_velocity)
		return

	for i in state.get_contact_count():
		var contact_collider := state.get_contact_collider_object(i)
		if contact_collider is Bullet and contact_collider.enabled:
			dying = true
			axis_lock_angular_x = false
			axis_lock_angular_y = false
			axis_lock_angular_z = false
			collision_layer = 0
			state.set_angular_velocity(-state.get_contact_local_normal(i).cross(up).normalized() * 33.0)
			_animation_player.play(&"impact")
			_animation_player.queue(&"extra/explode")
			contact_collider.enabled = false
			$SoundWalkLoop.stop()
			$SoundHit.play()
			return

	var horizontal := Vector3(lin_velocity.x, 0, lin_velocity.z)
	if _target != null and _target.is_on_floor():
		_landed = true
	if _landed:
		_wait -= delta
	var charging := _target != null and _landed and _wait <= 0.0
	if _target != null and not charging:
		_face(_target.global_position - global_position, up)

	if charging and _ray_floor.is_colliding():
		if _animation_player.current_animation != &"walk":
			_animation_player.play(&"walk")
			$SoundWalkLoop.play()
		var dir := _face(_target.global_position - global_position, up)
		horizontal = (horizontal + dir * ACCEL * delta).limit_length(MAX_SPEED)
	else:
		if _animation_player.current_animation == &"walk":
			_animation_player.play(&"idle")
			$SoundWalkLoop.stop()
		horizontal = horizontal.move_toward(Vector3.ZERO, DEACCEL * delta)

	state.set_linear_velocity(horizontal + up * lin_velocity.dot(up))


## Turn to face `to` on the horizontal plane and return that direction.
func _face(to: Vector3, up: Vector3) -> Vector3:
	var dir := (to - up * to.dot(up)).normalized()
	if not dir.is_zero_approx():
		_skeleton.transform = Transform3D(Basis.looking_at(-dir, up), _skeleton.position)
	return dir


func _die() -> void:
	queue_free()
