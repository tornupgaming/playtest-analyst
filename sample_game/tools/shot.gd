extends SceneTree
## Renders the test level and quits. Run through tools/shots.sh or tools/clip.sh.
##
##   godot --path . --fixed-fps 60 -s res://tools/shot.gd -- --out /tmp/a.png
##       [--profile clean|planted] [--view NAME] [--eye x,y,z [--target x,y,z]]
##       [--play STEPS [--every SECONDS]]
##
## --view places the player in a zone and frames it with the game camera, so the
## shot shows what a tester sees. --eye adds a fixed camera instead: it looks at
## --target, or follows the player if there is no target.
##
## --play holds input actions for a time, then saves the last frame to --out.
## STEPS is "actions:seconds,..." with actions joined by "+" and empty for none,
## e.g. "move_forward:1.5,move_forward+jump:0.4,:1". With --every, it also saves
## a frame every SECONDS to <out>_000.png, <out>_001.png, ...
##
## The game renders into a SubViewport: a window launched from the agent shell
## stops presenting after its first frames, but a SubViewport keeps rendering.

const LEVEL := "res://level/level.tscn"
const PHYSICS_HZ := 120.0

## name: [zone, offset from the zone's entry (centre of its +Z face), yaw in degrees,
## measure from the zone's far end instead]. Yaw 0 faces -Z, the way the course runs.
const VIEWS := {
	"start": ["", Vector3(0, 0, -1), 0.0],
	"ledge": ["ledge", Vector3(0, 0, -7), 0.0],
	"plaza": ["plaza", Vector3(0, 0, -7), 0.0],
	"beacon": ["plaza", Vector3(0, 0, -14), 0.0],
	"terrace": ["plaza", Vector3(15, 0, -14), 0.0],
	"hall": ["hall", Vector3(0, 0, -6), 0.0],
	"switch": ["hall", Vector3(-3, 0, -8), 30.0],
	"drop": ["drop", Vector3(0, 0, -9), 0.0],
	"fork": ["fork", Vector3(0, 0, -9), 0.0],
	"corridor": ["corridor", Vector3(0, 0, -4), 0.0],
	"finish": ["corridor", Vector3(0, 0, -1), 0.0, true],
}

var _args := {}


func _initialize() -> void:
	var raw := OS.get_cmdline_user_args()
	for i in raw.size():
		if raw[i].begins_with("--"):
			var has_value := i + 1 < raw.size() and not raw[i + 1].begins_with("--")
			_args[raw[i].trim_prefix("--")] = raw[i + 1] if has_value else ""
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = root.msaa_3d
	root.add_child(viewport)
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	if _args.has("profile"):
		level.set(&"tuning", load("res://profiles/tuning_%s.tres" % _args.profile))
	viewport.add_child(level)
	var player := level.get_node("Player") as Player
	await physics_frame
	if _args.has("view"):
		player.place(_view_spot(level, _args.view), deg_to_rad((VIEWS[_args.view] as Array)[2]))

	var camera: Camera3D
	if _args.has("eye"):
		camera = Camera3D.new()
		camera.fov = 60.0
		camera.far = 600.0
		level.add_child(camera)
		camera.make_current()

	var out: String = _args.out
	var every := int(float(_args.get("every", "0")) * PHYSICS_HZ)
	var tick := 0
	for step in (_args.get("play", "") as String).split(",", false):
		var actions := step.get_slice(":", 0).split("+", false)
		for action in actions:
			Input.action_press(action)
		for i in int(float(step.get_slice(":", 1)) * PHYSICS_HZ):
			_aim(camera, player)
			await physics_frame
			if every > 0 and tick % every == 0:
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(out.trim_suffix(".png") + "_%03d.png" % (tick / every))
			tick += 1
		for action in actions:
			Input.action_release(action)

	_aim(camera, player)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out)
	print("player at %s, on floor: %s, zone: %s" % [
			player.global_position.snappedf(0.01), player.is_on_floor(), level.get(&"_current_zone")])
	quit()


func _aim(camera: Camera3D, player: Player) -> void:
	if camera == null:
		return
	var target := _vec(_args.target) if _args.has("target") else player.global_position + Vector3.UP
	camera.look_at_from_position(_vec(_args.eye), target)


## Where a view stands the player: on the floor below its zone offset.
func _view_spot(level: Node3D, view: String) -> Vector3:
	var spec: Array = VIEWS[view]
	var anchor := Vector3.ZERO
	if spec[0] != "":
		var zone := level.get_node("Built/Zone_" + spec[0]) as Area3D
		var size := ((zone.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
		var far_end: bool = spec.size() > 3 and spec[3]
		anchor = zone.position + Vector3(0, -size.y / 2.0, (-1.0 if far_end else 1.0) * size.z / 2.0)
	var at: Vector3 = anchor + spec[1]
	var space := level.get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 20.0))
	return hit.position if hit else at


func _vec(s: String) -> Vector3:
	var p := s.split_floats(",")
	return Vector3(p[0], p[1], p[2])
