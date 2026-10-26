## Records the game window (external ffmpeg), the mic (AudioEffectRecord on the
## "Mic" bus) and telemetry events against one session clock.
##
## Session clock: seconds since start(), from Time.get_ticks_usec() (monotonic).
## The clock is anchored to wall time once (t0_unix) so the video, whose frames
## ffmpeg stamps with wall time, can be placed on it after the fact.
extends Node

const MIC_BUS := &"Mic"
const FPS := 30

var _dir: String
var _t0_usec: int
var _ffmpeg: Dictionary
var _events: FileAccess
var _mic: AudioStreamPlayer
var _record: AudioEffectRecord
var _manifest: Dictionary


func now() -> float:
	return (Time.get_ticks_usec() - _t0_usec) / 1e6


func start(dir: String) -> void:
	_dir = dir
	DirAccess.make_dir_recursive_absolute(dir)

	var bus := AudioServer.get_bus_index(MIC_BUS)
	_record = AudioServer.get_bus_effect(bus, 0)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = MIC_BUS
	add_child(_mic)
	_mic.play()

	# Anchor: read both clocks back to back so they describe the same instant.
	_t0_usec = Time.get_ticks_usec()
	var t0_unix := Time.get_unix_time_from_system()

	_events = FileAccess.open(dir.path_join("events.jsonl"), FileAccess.WRITE)
	_ffmpeg = OS.execute_with_pipe("ffmpeg", _ffmpeg_args(dir.path_join("screen.mkv")), false)
	_record.set_recording_active(true)

	_manifest = {
		"t0_unix": t0_unix,
		"audio_start": now(),
		"video": "screen.mkv",
		"audio": "mic.wav",
		"events": "events.jsonl",
		"input_device": AudioServer.input_device,
		"mix_rate": AudioServer.get_mix_rate(),
		"output_latency": AudioServer.get_output_latency(),
	}


func log_event(type: String, data := {}) -> void:
	var event := {"t": now(), "type": type}
	event.merge(data)
	_events.store_line(JSON.stringify(event))


func is_recording() -> bool:
	return not _ffmpeg.is_empty()


## Closing the window mid-session still produces a complete bundle.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_recording():
		stop()


func stop() -> void:
	_manifest["duration"] = now()
	_record.set_recording_active(false)
	_record.get_recording().save_to_wav(_dir.path_join("mic.wav"))
	_mic.stop()
	_events.close()

	# "q" on stdin lets ffmpeg finalise the file; killing it would truncate it.
	var stdio: FileAccess = _ffmpeg["stdio"]
	stdio.store_string("q")
	stdio.flush()
	var deadline := Time.get_ticks_msec() + 5000
	while OS.is_process_running(_ffmpeg["pid"]) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
	if OS.is_process_running(_ffmpeg["pid"]):
		push_error("ffmpeg did not exit; killing it")
		OS.kill(_ffmpeg["pid"])

	var f := FileAccess.open(_dir.path_join("session.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(_manifest, "  "))
	_ffmpeg = {}


func _ffmpeg_args(out_path: String) -> PackedStringArray:
	var window_id := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	return [
		"-hide_banner", "-loglevel", "error", "-nostats", "-y",
		"-f", "x11grab", "-framerate", str(FPS), "-draw_mouse", "0",
		"-window_id", str(window_id), "-i", OS.get_environment("DISPLAY"),
		# x11grab stamps each frame with wall-clock µs. -copyts keeps those
		# stamps in the file, so the video's start_time is a unix time.
		"-copyts", "-fps_mode", "passthrough",
		"-c:v", "libx264", "-preset", "ultrafast", "-crf", "23", "-pix_fmt", "yuv420p",
		out_path,
	]
