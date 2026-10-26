extends SceneTree
## Plays one continuous run of the test level with a scripted bot and records it.
## Run through tools/make_synthetic.sh.
##
##   godot --path . --fixed-fps 60 --resolution 1280x720 -s res://tools/synth.gd -- \
##       --profile planted|clean --out DIR [--no-video] \
##       --telemetry-dir=DIR --telemetry-game-clock
##
## Writes DIR/screen.mkv (30 fps of game time, frame i at session t = i/30) and
## DIR/think_aloud.json (the lines the bot "says", [{t, text}]). Telemetry writes
## DIR/events.jsonl on the same clock. --no-video skips capture, for fast headless
## checks of the bot's route.
##
## The bot drives the player the way a tester does: it holds the move actions
## towards its next waypoint, presses jump, and turns the game camera (a stand-in
## for the mouse) to face where it is going. Its route is a list of steps built
## from the level's zone boxes, so it follows the geometry of either profile.
## The planted route struggles where ground_truth.json says testers do; the clean
## route plays competently. A route step that expects a death ("die") is where
## the bot resumes after it respawns.

const LEVEL := "res://level/level.tscn"
const FPS := 30
## Camera turn speed, in radians per second at most.
const TURN_SPEED := 2.5
## How long jump is held: past the apex, so the jump is full height.
const JUMP_HOLD := 0.6

var _args := {}
var _level: Node3D
var _player: Player
var _camera: Camera3D
var _steps := []
var _i := 0
var _step_time := 0.0
var _left_floor := false
var _leg_start: Vector2
var _jump_time := -1.0
var _yaw_goal := 0.0
var _last_pos: Vector3
var _lines: Array[Dictionary] = []
var _done := false

var _viewport: SubViewport
var _ffmpeg: Dictionary
var _frames := 0


func _initialize() -> void:
	var raw := OS.get_cmdline_user_args()
	for i in raw.size():
		if raw[i].begins_with("--") and not "=" in raw[i]:
			var has_value := i + 1 < raw.size() and not raw[i + 1].begins_with("--")
			_args[raw[i].trim_prefix("--")] = raw[i + 1] if has_value else ""
	_run.call_deferred()


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = root.size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(_viewport)
	_level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	_level.set(&"tuning", load("res://eval/tuning_%s.tres" % _args.profile))
	_viewport.add_child(_level)
	_player = _level.get_node("Player") as Player
	_camera = _player.get_node("Target/Camera3D") as Camera3D
	_last_pos = _player.global_position
	_steps = _route(_args.profile == "planted")
	if not _args.has("no-video"):
		_ffmpeg = OS.execute_with_pipe("ffmpeg", [
				"-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba",
				"-s", "%dx%d" % [_viewport.size.x, _viewport.size.y], "-framerate", str(FPS), "-i", "pipe:0",
				"-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
				ProjectSettings.globalize_path(_args.out).path_join("screen.mkv")])
		RenderingServer.frame_post_draw.connect(_capture)
	physics_frame.connect(_tick)


# --- Route -------------------------------------------------------------------

func _go(x: float, z: float) -> Dictionary: return {do = "go", to = Vector2(x, z)}
## Press jump now and steer towards x, z until landing.
func _jump(x: float, z: float) -> Dictionary: return {do = "jump", to = Vector2(x, z)}
## Walk towards x, z for `secs` whether or not it gets there (into a wall, say).
func _push(x: float, z: float, secs: float) -> Dictionary: return {do = "push", to = Vector2(x, z), secs = secs}
func _wait(secs: float) -> Dictionary: return {do = "wait", secs = secs}
## Stand still and turn the camera by `deg` (positive is to the left) over `secs`.
func _look(deg: float, secs: float) -> Dictionary: return {do = "look", deg = deg, secs = secs}
## Wait until on the floor again.
func _land() -> Dictionary: return {do = "land"}
## Wait for the enemy to come close, then jump on it.
func _stomp() -> Dictionary: return {do = "stomp"}
## The steps before this one end in a death; resume here after the respawn.
func _die() -> Dictionary: return {do = "die"}
func _say(text: String) -> Dictionary: return {do = "say", text = text}


func _route(planted: bool) -> Array:
	var plaza := _zone_box("plaza")
	var z0 := plaza.end.z            # plaza entrance
	var z1 := _zone_box("hall").end.z
	var z2 := _zone_box("drop").end.z + 6.0  # tunnel entrance
	var z3 := _zone_box("fork").end.z
	var corridor_end := _zone_box("corridor").position.z
	var ledge: float = _level.get(&"_ledge_z")
	var gap: float = (_level.get(&"tuning") as LevelTuning).ledge_gap_width
	var land := ledge - gap - 6.0
	var r := []

	# Start, with the practice gap.
	r += [_wait(0.6), _say("Okay, let's see. Follow the path."), _go(0, -19.7), _jump(0, -26),
			_say("Easy enough."), _go(0, -38)]

	# Ledge.
	if planted:
		# Four misses (early, early, from a standstill, early), then a clean jump.
		# The bridge only appears on the fifth death, so it never shows.
		r += [_go(0, ledge + 1.6), _jump(0, land), _die(),
				_wait(1.0), _say("Oh. Missed it."), _go(0, ledge + 1.0), _jump(0, land), _die(),
				_wait(1.6), _say("Is this jump even possible?"), _go(0, ledge + 0.6), _wait(0.8), _jump(0, land), _die(),
				_wait(1.4), _say("Come on, that's way too far."), _go(0, ledge + 1.2), _jump(0, land), _die(),
				_wait(2.0), _go(0, ledge - 0.25), _jump(0, land), _say("Finally!")]
	else:
		r += [_go(0, ledge + 0.4), _jump(0, land), _say("Nice, made it.")]
	r += [_go(0, z0 + 2)]

	# Plaza: the way on is up the stepping blocks on the right to the terrace door.
	if planted:
		r += [_go(0, z0 - 5), _wait(0.4), _say("Reach the beacon... what beacon?"),
				_look(60, 1.2), _look(-120, 2.2), _look(60, 1.2),
				_go(-9, z0 - 6), _go(-9, z0 - 16), _say("Where am I going?"), _go(-9, z0 - 24), _go(-4, z0 - 28),
				_wait(0.5), _push(-4, z0 - 31, 0.8), _jump(-4, z0 - 31), _wait(0.6),
				_go(9, z0 - 28), _go(8, z0 - 17), _go(0, z0 - 12), _wait(0.6),
				_say("I'm just going in circles here."), _look(90, 1.5), _look(-180, 3.0), _look(90, 1.5),
				_go(9, z0 - 11), _say("Oh, steps. Maybe up there?"), _go(16, z0 - 13)]
	else:
		r += [_say("There's the beacon, up on the terrace."), _go(16, z0 - 13)]
	r += [_go(16, z0 - 15), _wait(0.3), _jump(16, z0 - 18.1), _wait(0.3), _jump(16, z0 - 22.1),
			_wait(0.3), _jump(16, z0 - 26.1), _go(16, z0 - 25), _wait(0.2), _go(16, z0 - 27.3), _jump(16, z0 - 33),
			_go(2, z0 - 36), _go(0, z0 - 38)]

	# Hall: the gate at the far end opens from the switch on the balcony (left).
	if planted:
		r += [_go(0, z1 - 9), _wait(0.4), _say("Find a way through... how?"),
				_look(70, 1.5), _look(-140, 2.5), _look(70, 1.5),
				_go(4, z1 - 14), _go(2, z1 - 27), _go(0, z1 - 29), _push(0, z1 - 32, 1.5),
				_jump(0, z1 - 32), _say("This gate won't budge."), _wait(1.0),
				_go(1, z1 - 24), _go(3, z1 - 16), _go(6, z1 - 14), _wait(0.5), _look(-60, 1.2),
				_go(2, z1 - 11), _wait(0.4), _look(100, 2.0), _say("Is that a button up there?"), _wait(0.6)]
	else:
		r += [_say("Press the red switch. Got it."), _go(0, z1 - 6)]
	# Onto the crate, onto the balcony, press the switch, drop back down.
	r += [_go(-3, z1 - 20.9), _wait(0.5), _jump(-6.3, z1 - 20.9), _wait(0.5), _jump(-6.5, z1 - 15.5),
			_go(-6.5, z1 - 15), _wait(1.2), _say("Gate's open."),
			_go(-2.5, z1 - 15), _land(), _go(0, z1 - 26), _go(0, z1 - 31)]

	# Drop: a hole in the tunnel floor into the enemy's room.
	var drop_in := [_go(0, z2 - 9.5), _wait(0.5), _go(0, z2 - 11.5), _land()]
	r += [_go(0, z2 - 5)]
	if planted:
		# Lands and freezes; lands and runs back into the wall; lands and stomps it.
		r += drop_in + [_wait(3.0), _die(),
				_wait(1.2), _say("What? I couldn't even see it!")]
		r += drop_in + [_push(-6, z2 - 7, 8.0), _die(),
				_wait(1.0), _say("That's not fair, it gets you the second you land.")]
		r += drop_in + [_stomp()]
	else:
		r += [_say("A hole. Down we go.")] + drop_in + [_say("Whoa, an enemy. Jump on it!"), _stomp(),
				_say("Ha, squashed him.")]
	r += [_go(0, z2 - 24), _go(0, z2 - 28)]

	# Fork: the sign; left is a dead end, right is the corridor.
	r += [_go(0, z3 - 12.5), _wait(0.8)]
	if planted:
		r += [_say("Exit sign points left. Okay."), _go(-8, z3 - 13), _go(-19, z3 - 13.5), _go(-19, z3 - 33.5),
				_wait(0.8), _say("Dead end? But the sign said exit."), _look(70, 1.2), _wait(0.6),
				_go(-19, z3 - 14), _go(-8, z3 - 13), _go(0, z3 - 13)]
	else:
		r += [_say("Exit's this way.")]
	r += [_go(8, z3 - 13), _go(19, z3 - 13.5), _go(19, z3 - 17)]

	# Corridor and finish.
	var length := z3 - 15.0 - corridor_end
	if planted:
		r += [_go(19, z3 - 15 - length * 0.4), _say("This goes on a while."),
				_go(19, z3 - 15 - length * 0.8), _say("Still walking...")]
	else:
		r += [_say("Nearly there.")]
	# The run ends just after the goal, so the video ends with the last event.
	r += [_go(19, corridor_end + 10), _say("There's the flag. Finally." if planted else "There's the flag. That was fun."),
			_go(19, corridor_end + 2), _push(19, corridor_end - 6, 1.4)]
	return r


func _zone_box(id: String) -> AABB:
	var zone := _level.get_node("Built/Zone_" + id) as Area3D
	var size := ((zone.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	return AABB(zone.position - size / 2.0, size)


# --- Bot ---------------------------------------------------------------------

func _tick() -> void:
	if _done:
		return
	var dt := 1.0 / Engine.physics_ticks_per_second
	var pos := _player.global_position
	if pos.distance_to(_last_pos) > 3.0:
		_respawned()
	_last_pos = pos
	if _jump_time >= 0.0:
		_jump_time += dt
		if _jump_time > JUMP_HOLD:
			Input.action_release(&"jump")
			_jump_time = -1.0

	while _i < _steps.size() and _steps[_i].do == "say":
		_lines.append({t = snappedf(_now(), 0.01), text = _steps[_i].text})
		_i += 1
	if _i >= _steps.size():
		_finish()
		return

	var step: Dictionary = _steps[_i]
	_step_time += dt
	var here := Vector2(pos.x, pos.z)
	var next := false
	match step.do:
		"go":
			var to: Vector2 = step.to
			if _step_time <= dt:
				_leg_start = here
			_drive(to, _stops_after(_i))
			# Arrived when close, or once past the target along the leg.
			next = here.distance_to(to) < 0.3 or (to - here).dot(to - _leg_start) <= 0.0
			if _step_time > _leg_start.distance_to(to) / 3.0 + 4.0:
				_fail("stuck going to %s" % to)
		"jump":
			if _step_time <= dt:
				Input.action_press(&"jump")
				_jump_time = 0.0
				_left_floor = false
			var to: Vector2 = step.to
			_drive(to, true)
			_left_floor = _left_floor or not _player.is_on_floor()
			next = _left_floor and _player.is_on_floor()
			if _step_time > 4.0:
				_fail("jump to %s never landed" % to)
		"push":
			_steer(step.to - here)
			_face(step.to - here)
			next = _step_time >= step.secs
		"wait":
			_steer(Vector2.ZERO)
			next = _step_time >= step.secs
		"look":
			_steer(Vector2.ZERO)
			if _step_time <= dt:
				_yaw_goal = _camera.get(&"_yaw") + deg_to_rad(step.deg)
			next = _step_time >= step.secs
		"land":
			_steer(Vector2.ZERO)
			_left_floor = _left_floor or not _player.is_on_floor()
			next = _left_floor and _player.is_on_floor()
			if _step_time > 4.0:
				_fail("never landed")
		"stomp":
			var enemy := _level.get(&"_enemy") as RigidBody3D
			if not is_instance_valid(enemy) or enemy.get(&"dying"):
				next = _player.is_on_floor()
				_steer(Vector2.ZERO)
			else:
				var to := Vector2(enemy.global_position.x, enemy.global_position.z) - here
				_face(to)
				if _jump_time < 0.0 and _player.is_on_floor() and to.length() < 3.6:
					Input.action_press(&"jump")
					_jump_time = 0.0
				_steer(to if not _player.is_on_floor() else Vector2.ZERO)
			if _step_time > 10.0:
				_fail("never stomped the enemy")
		"die":
			_fail("expected a death before step %d" % _i)
	_turn_camera(dt)
	if next:
		if _args.has("trace"):
			print("t=%.2f done %d %s at %s floor=%s" % [_now(), _i, step.do, pos.snappedf(0.01), _player.is_on_floor()])
		_i += 1
		_step_time = 0.0
		_left_floor = false


## Head for `to`. If `stop`, brake so as to stop there: on the floor by letting
## go of the keys, in the air by steering against the drift, as a player does.
func _drive(to: Vector2, stop: bool) -> void:
	var pos := _player.global_position
	var away := to - Vector2(pos.x, pos.z)
	var vel := Vector2(_player.velocity.x, _player.velocity.z)
	var floor := _player.is_on_floor()
	var speed := Player.MAX_SPEED
	if stop:
		speed = minf(speed, sqrt(2.0 * (12.0 if floor else 5.0) * away.length()))
	if floor:
		_steer(away if vel.length() < speed else Vector2.ZERO)
		if not away.is_zero_approx():
			_face(away)
	else:
		var error := away.normalized() * speed - vel
		_steer(error if error.length() > 0.3 else Vector2.ZERO)


## Whether the bot stands still after step i, rather than moving straight on.
func _stops_after(i: int) -> bool:
	for j in range(i + 1, _steps.size()):
		if _steps[j].do != "say":
			return not _steps[j].do in ["go", "jump", "push"]
	return true


## Hold the move actions so the player heads along `dir` (world x, z), or
## release them for a zero vector. The camera turns to follow, as a player's would.
func _steer(dir: Vector2) -> void:
	var x := 0.0
	var y := 0.0
	if dir.length() > 0.01:
		var basis := _camera.global_transform.basis
		var right := Vector2(basis.x.x, basis.x.z)
		var back := Vector2(basis.z.x, basis.z.z)
		# Input y maps through the camera's pitched back axis, which is shorter
		# than 1 on the ground plane; scale it up so the direction comes out true.
		x = dir.normalized().dot(right.normalized()) / right.length()
		y = dir.normalized().dot(back.normalized()) / back.length()
		var n := Vector2(x, y).normalized()
		x = n.x
		y = n.y
	_hold(&"move_right", x)
	_hold(&"move_left", -x)
	_hold(&"move_back", y)
	_hold(&"move_forward", -y)


func _hold(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


## Aim the camera along `dir` (world x, z): it sits behind the player.
func _face(dir: Vector2) -> void:
	_yaw_goal = atan2(-dir.x, -dir.y)


func _turn_camera(dt: float) -> void:
	var yaw: float = _camera.get(&"_yaw")
	var diff := wrapf(_yaw_goal - yaw, -PI, PI)
	_camera.set(&"_yaw", yaw + clampf(diff * 4.0 * dt, -TURN_SPEED * dt, TURN_SPEED * dt))


func _respawned() -> void:
	var j := _i
	while j < _steps.size() and _steps[j].do != "die":
		j += 1
	if j >= _steps.size():
		_fail("unexpected death during step %d %s" % [_i, _steps[_i]])
		return
	print("t=%.2f death during step %d, resuming at %d" % [_now(), _i, j + 1])
	_i = j + 1
	_step_time = 0.0
	_left_floor = false
	_yaw_goal = 0.0
	Input.action_release(&"jump")
	_jump_time = -1.0


## Session time, from the telemetry autoload (not a global in a -s script).
func _now() -> float:
	return root.get_node("PlaytestTelemetry").now()


func _fail(why: String) -> void:
	printerr("BOT FAILED at t=%.2f: %s" % [_now(), why])
	_done = true
	_end(1)


func _finish() -> void:
	_done = true
	var file := FileAccess.open(_args.out.path_join("think_aloud.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_lines, "\t") + "\n")
	file.close()
	print("finished at t=%.2f, %d frames" % [_now(), _frames])
	_end(0)


func _end(code: int) -> void:
	if not _ffmpeg.is_empty():
		RenderingServer.frame_post_draw.disconnect(_capture)
		(_ffmpeg.stdio as FileAccess).close()
		while OS.is_process_running(_ffmpeg.pid):
			OS.delay_msec(50)
	quit(code)


# --- Capture -----------------------------------------------------------------

## Pipe frame i to ffmpeg once the session clock reaches i / FPS, so frame i sits
## at session time i / FPS. The first frame also fills any slots before it.
func _capture() -> void:
	var t := _now()
	if _frames > t * FPS + 1e-6:
		return
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	while _frames <= t * FPS + 1e-6:
		(_ffmpeg.stdio as FileAccess).store_buffer(data)
		_frames += 1
