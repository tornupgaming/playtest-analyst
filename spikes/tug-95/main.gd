## Sync test scene. Every few seconds the player "dies": the recorder logs a
## death event, the screen flashes white and a beep plays. The beep reaches the
## mic through a loopback source (run_spike.sh) or through speakers (--real).
## tools/check_sync.py then finds each flash and beep and compares them with
## the logged event times.
##
## Args (after --): --duration=SECONDS --out=DIR
extends Node

const FLASH_SEC := 0.1
const BEEP_HZ := 1000.0
const BEEP_SEC := 0.08

const SessionRecorder := preload("res://session_recorder.gd")

var _recorder := SessionRecorder.new()
var _flash := ColorRect.new()
var _clock := Label.new()
var _beep := AudioStreamPlayer.new()
var _deaths: Array[float] = []
var _duration := 120.0
var _out := "user://session"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="):
			_duration = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_flash.color = Color.WHITE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.visible = false
	add_child(_flash)
	_clock.position = Vector2(20, 20)
	_clock.add_theme_font_size_override("font_size", 24)
	_clock.modulate = Color.GRAY
	add_child(_clock)
	_beep.stream = _make_beep()
	add_child(_beep)
	add_child(_recorder)

	# Irregular gaps so a constant offset can't match the wrong death.
	var rng := RandomNumberGenerator.new()
	rng.seed = 95
	var t := 3.0
	while t < _duration - 2.0:
		_deaths.append(t)
		t += rng.randf_range(4.0, 9.0)

	# Let the window map before ffmpeg looks it up.
	await get_tree().create_timer(0.5).timeout
	_recorder.start(ProjectSettings.globalize_path(_out))
	print("recording to ", ProjectSettings.globalize_path(_out))


func _process(_delta: float) -> void:
	if not _recorder.is_recording():
		return
	var t := _recorder.now()
	_clock.text = "%.2f / %.0f s   sync test: watch for white flashes + beeps.\nSpace = extra death. Closing early still saves the session." % [t, _duration]
	if not _deaths.is_empty() and t >= _deaths[0]:
		_deaths.pop_front()
		_die()
	if t >= _duration:
		set_process(false)
		_recorder.stop()
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and _recorder.is_recording():
		_die()


func _die() -> void:
	_recorder.log_event("death")
	_flash.visible = true
	_beep.play()
	await get_tree().create_timer(FLASH_SEC).timeout
	_flash.visible = false


func _make_beep() -> AudioStreamWAV:
	var rate := 48000
	var data := PackedByteArray()
	data.resize(int(rate * BEEP_SEC) * 2)
	for i in data.size() / 2:
		var s := sin(TAU * BEEP_HZ * i / rate) * 0.8
		data.encode_s16(i * 2, int(s * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
