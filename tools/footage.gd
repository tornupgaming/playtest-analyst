extends SceneTree
## Renders the demo video's shots that need no players. Run through tools/footage.sh.
##
##   godot --path . --fixed-fps 30 --resolution 1920x1080 -s res://tools/footage.gd -- --out DIR
##       [--card title|end] [--at SECONDS]
##
## With the planted profile, writes:
##   DIR/fly_0000.png ...  shot 3: a flythrough of the level with six numbered pins (FLY_SECONDS at 30 fps)
##   DIR/scoreboard.png    shot 8: the flythrough's last view, with a numbered list of the problems
## --card writes DIR/title.png (shot 2) or DIR/end.png (shot 12) instead.
## --at writes DIR/at.png, one moment of the flythrough, for tuning PATH.
##
## Pins are drawn over the render, not added to the level. Each pin's tip touches
## the spot where its planted problem happens (eval/ground_truth.json) and its
## head stands above it, so it doesn't cover what it marks.

const LEVEL := "res://level/level.tscn"
const FONT := preload("res://art/fonts/fredoka_semibold.tres")
const FPS := 30

# Category colours, the same as the report viewer (analyst/viewer/style.css).
const DIFFICULTY := Color("#ec3f5f")
const UI := Color("#3fa9f5")
const PACING := Color("#62c83c")
const INK := Color("#0d0f12")
const PAPER := Color("#e7eaef")

## The planted problems, numbered as in eval/ground_truth.json: [number, tip, colour,
## stem height in pixels, label]. Tips are where level.gd builds each problem with
## the planted profile. Stems are staggered so close pins don't overlap.
const PINS := [
	[1, Vector3(0, 0, -47.3), DIFFICULTY, 80, "Ledge gap too wide"],  # middle of the gap
	[2, Vector3(0, 16.0, -98.0), UI, 200, "Beacon blends into the wall"],  # top of the beacon star
	[3, Vector3(-6.5, 11.5, -113.6), UI, 70, "Switch prompt doesn't point to it"],  # the switch
	[4, Vector3(0, 13.5, -138.0), DIFFICULTY, 150, "Enemy charges as you land"],  # over the hole you drop through
	[5, Vector3(0, 3.9, -173.1), UI, 80, "EXIT sign points to a dead end"],  # top of the sign
	[6, Vector3(19, 4, -282.0), PACING, 120, "Long, empty corridor"],  # over the middle of the corridor
]

## The flythrough: [seconds, camera position, looking at]. Catmull-Rom through these.
const PATH := [
	[0.0, Vector3(0, 12, 26), Vector3(0, 1, -24)],
	[2.5, Vector3(0, 20, -12), Vector3(0, 3, -60)],
	[5.0, Vector3(14, 34, -52), Vector3(-2, 10, -104)],
	[7.5, Vector3(10, 34, -100), Vector3(-2, 6, -150)],
	[10.0, Vector3(24, 40, -150), Vector3(10, 2, -210)],
	[12.5, Vector3(90, 150, -150), Vector3(10, 0, -205)],
	[15.0, Vector3(160, 223, -178), Vector3(8, 0, -190)],
]
const FLY_SECONDS := 18.0  # holds on the last view for 3 s

## Card text: [font size, colour, text] per line. An empty text is a gap that high.
const CARDS := {
	"title": [
		[150, PAPER, "Playtest Analyst"],
		[64, PAPER, "a Godot plugin"],
		[24, PAPER, ""],
		[50, UI, "Muse Wonder watches the playtest"],
		[50, PACING, "SAM 3.1 points at the problem"],
	],
	"end": [
		[110, PAPER, "Playtest Analyst"],
		[24, PAPER, ""],
		[58, UI, "github.com/tornupgaming/playtest-analyst"],
		[24, PAPER, ""],
		[46, PAPER, "Built with Muse Wonder + SAM 3.1 · Meta Model API"],
		[24, PAPER, ""],
		[46, Color(PAPER, 0.75), "Phil Smith"],
	],
}

var _viewport: SubViewport
var _camera: Camera3D
var _overlay: Overlay


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	var raw := OS.get_cmdline_user_args()
	for i in raw.size() - 1:
		if raw[i].begins_with("--"):
			args[raw[i].trim_prefix("--")] = raw[i + 1]
	var out: String = args.out
	_viewport = SubViewport.new()
	_viewport.size = root.size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(_viewport)

	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	level.set(&"tuning", load("res://eval/tuning_planted.tres"))
	_viewport.add_child(level)
	var player := level.get_node("Player") as Node3D
	player.hide()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	(level.get_node("HUD") as CanvasLayer).hide()
	# Shadows reach the far end of the wide shots too.
	(level.get_node("DirectionalLight3D") as DirectionalLight3D).directional_shadow_max_distance = 600.0
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 1500.0
	level.add_child(_camera)
	_camera.make_current()
	_overlay = Overlay.new()
	_overlay.camera = _camera
	_overlay.size = _viewport.size
	_viewport.add_child(_overlay)

	if args.has("card"):
		await _card(args.card, out + "/%s.png" % args.card)
	elif args.has("at"):
		_place_camera(float(args.at))
		_overlay.listed = float(args.at) >= FLY_SECONDS
		for i in 30:  # let the pins fade in
			await _grab()
		await _save(out + "/at.png")
	else:
		for frame in int(FLY_SECONDS * FPS):
			_place_camera(frame / float(FPS))
			await _save("%s/fly_%04d.png" % [out, frame])
		_overlay.listed = true
		await _save(out + "/scoreboard.png")
	quit()


## A title or end card over a blurred view of the start.
func _card(name: String, path: String) -> void:
	_overlay.hide()
	_place_camera(0.0)
	var backdrop := await _grab()
	backdrop.resize(backdrop.get_width() / 24, backdrop.get_height() / 24, Image.INTERPOLATE_BILINEAR)
	backdrop.resize(_viewport.size.x, _viewport.size.y, Image.INTERPOLATE_CUBIC)
	var card := Card.new()
	card.backdrop = ImageTexture.create_from_image(backdrop)
	card.lines = CARDS[name]
	card.size = _viewport.size
	_viewport.add_child(card)
	await _save(path)


func _place_camera(t: float) -> void:
	t = clampf(t, PATH[0][0], PATH[-1][0])
	var i := 0
	while i < PATH.size() - 2 and t > (PATH[i + 1][0] as float):
		i += 1
	var start: float = PATH[i][0]
	var u: float = (t - start) / (PATH[i + 1][0] - start)
	var before: Array = PATH[maxi(i - 1, 0)]
	var after: Array = PATH[mini(i + 2, PATH.size() - 1)]
	var eye: Vector3 = (PATH[i][1] as Vector3).cubic_interpolate(PATH[i + 1][1], before[1], after[1], u)
	var target: Vector3 = (PATH[i][2] as Vector3).cubic_interpolate(PATH[i + 1][2], before[2], after[2], u)
	_camera.look_at_from_position(eye, target)


## Draws the next frame and returns it. Waiting for frame_post_draw instead hung
## after a few frames on some runs: the hidden window stops drawing on its own.
func _grab() -> Image:
	await process_frame
	RenderingServer.force_draw()
	return _viewport.get_texture().get_image()


func _save(path: String) -> void:
	var image := await _grab()
	image.save_png(path)


## The numbered pins, and with `listed` a panel naming each problem. A pin fades
## out while something solid stands between it and the camera.
class Overlay extends Control:
	const FADE_FRAMES := 8.0
	var camera: Camera3D
	var listed := false
	var _alpha := {}

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for pin: Array in PINS:
			var world: Vector3 = pin[1]
			var ahead := not camera.is_position_behind(world)
			var alpha := move_toward(_alpha.get(pin[0], 0.0), 1.0 if ahead and _in_view(world) else 0.0,
					1.0 / FADE_FRAMES)
			_alpha[pin[0]] = alpha
			if alpha > 0.0 and ahead:
				_draw_pin(camera.unproject_position(world), pin[0], pin[2], pin[3], alpha)
		if listed:
			_draw_list()

	func _in_view(world: Vector3) -> bool:
		var space := camera.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position, world))
		return hit.is_empty() or (hit.position as Vector3).distance_to(world) < 2.0

	func _draw_pin(tip: Vector2, number: int, colour: Color, stem: float, alpha: float) -> void:
		var ink := Color(INK, alpha)
		var paper := Color(PAPER, alpha)
		# Shorten the stem rather than let the head leave the top of the frame.
		var head := Vector2(tip.x, maxf(tip.y - stem, minf(tip.y - 40.0, 48.0)))
		draw_line(tip, head, ink, 8.0, true)
		draw_line(tip, head, paper, 4.0, true)
		draw_circle(tip, 9.0, ink)
		draw_circle(tip, 6.0, paper)
		draw_circle(head, 38.0, ink)
		draw_circle(head, 34.0, paper)
		draw_circle(head, 29.0, Color(colour, alpha))
		_centred(head, str(number), 44, alpha)

	## Two columns of three along the bottom, with room after each line for a tick.
	func _draw_list() -> void:
		var row_height := 64.0
		var column_width := 860.0
		var box := Rect2(48, size.y - 40 - 32 - row_height * 3, size.x - 96, 32 + row_height * 3)
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(INK, 0.86)
		panel.set_corner_radius_all(20)
		draw_style_box(panel, box)
		for i in PINS.size():
			var pin: Array = PINS[i]
			var centre := box.position + Vector2(52 + column_width * (i / 3), 16 + row_height * (i % 3 + 0.5))
			draw_circle(centre, 25.0, pin[2])
			_centred(centre, str(pin[0]), 34, 1.0)
			draw_string(FONT, centre + Vector2(44, 13), pin[4], HORIZONTAL_ALIGNMENT_LEFT, -1, 38, PAPER)

	func _centred(centre: Vector2, text: String, font_size: int, alpha: float) -> void:
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := centre + Vector2(-width / 2.0, FONT.get_ascent(font_size) * 0.38)
		draw_string_outline(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color(INK, alpha))
		draw_string(FONT, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(PAPER, alpha))


## A title or end card: centred lines of text (a CARDS entry) over a blurred, darkened view.
class Card extends Control:
	var backdrop: Texture2D
	var lines: Array

	func _draw() -> void:
		draw_texture_rect(backdrop, Rect2(Vector2.ZERO, size), false)
		draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.62))
		var total := 0.0
		for line: Array in lines:
			total += line[0] * 1.3
		var y := (size.y - total) / 2.0
		for line: Array in lines:
			var font_size: int = line[0]
			y += font_size * 1.3
			var width := FONT.get_string_size(line[2], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var baseline := Vector2((size.x - width) / 2.0, y - font_size * 0.3)
			draw_string_outline(FONT, baseline, line[2], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 10, INK)
			draw_string(FONT, baseline, line[2], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, line[1])
