extends Node
## The PlaytestRecorder autoload: records a playtest session into a bundle
## (DECISIONS.md §2, §3). One ffmpeg process grabs the game window (x11grab) and the
## mic (pulse) into screen.mkv, both stamped with wall-clock time (-copyts).
## PlaytestTelemetry writes events.jsonl on the same session clock. session.json is
## written last, so a bundle without it is unfinished.
##
## Starts with the user arg --record, or F9. Stops with F9, on window close, or when
## the editor dock asks. Needs X11 (on Wayland run the game with --display-driver x11)
## and ffmpeg: without them it records nothing and tells the dock why ("refused").
##
## User args (after `--`):
##   --record          start recording at launch
##   --tester=NAME     session.json `tester`, URI-encoded (the editor splits run args on spaces)
## Project setting playtest_analyst/profile, if set, becomes session.json `profile`.
## Project setting playtest_analyst/cli is where the analyst CLI is (cli_path()).
##
## A bundle that ends early keeps the file INCOMPLETE, which says why, and has no
## session.json. Nothing is deleted: the footage up to a crash is still playable.

const FPS := 30
const INCOMPLETE := "INCOMPLETE"
const VIDEO := "screen.mkv"
## Debugger message prefix shared with the editor dock.
const CHANNEL := "playtest_analyst"
## Runs ffmpeg with our stdin, so "q" reaches it, and SIGTERMs it if Godot dies
## without stopping it (a crash, or the editor's Stop button, which kills the game).
## ffmpeg finalises the file on SIGTERM. Exits with ffmpeg's exit code.
const WATCHDOG := "ffmpeg \"$@\" <&0 & f=$!; while kill -0 $PPID 2>/dev/null && kill -0 $f 2>/dev/null; do sleep 0.5; done; kill -TERM $f 2>/dev/null; wait $f"

var _dir := ""
var _meta := {}
var _ffmpeg := {}
var _was_resizable := true
var _tester: Variant = null


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS  # F9 and the ffmpeg check work while paused
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--tester="):
			_tester = arg.trim_prefix("--tester=").uri_decode()
	if EngineDebugger.is_active():
		EngineDebugger.register_message_capture(CHANNEL, _on_editor_message)
	if "--record" in args:
		start()


## Where bundles go: `<project>/sessions` when running from the editor or a source
## checkout, user://sessions in an exported game.
static func sessions_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://sessions")
	return ProjectSettings.globalize_path("user://sessions")


## The analyst CLI, analyst/src/cli.ts in a playtest-analyst checkout: the project setting
## playtest_analyst/cli, absolute or relative to the project folder.
static func cli_path() -> String:
	var path: String = ProjectSettings.get_setting("playtest_analyst/cli", "")
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path() if path.is_relative_path() else path


## The command line for `playtest <command> <dir>` (cli_path()) through bun, run by
## the user's login shell: an editor started from a desktop launcher lacks what is exported
## only in shell startup files, such as META_MODEL_API_KEY in ~/.zshenv. The arguments reach
## bun through "$@", never the script text. Runs bun directly when SHELL is unset or isn't
## a POSIX-style shell (fish, for one, rejects "$@").
static func analyst(command: String, dir: String) -> PackedStringArray:
	var bun := "bun"
	var home_bun := OS.get_environment("HOME").path_join(".bun/bin/bun")
	if FileAccess.file_exists(home_bun):
		bun = home_bun  # the editor may be launched without ~/.bun/bin on PATH
	var line := PackedStringArray([bun, cli_path(), command, dir])
	var shell := OS.get_environment("SHELL")
	if not shell.get_file() in ["sh", "bash", "zsh", "dash", "ksh"]:
		return line
	return PackedStringArray([shell, "-lc", 'exec "$@"', "playtest"]) + line


func is_recording() -> bool:
	return not _ffmpeg.is_empty()


func start() -> void:
	if is_recording():
		return
	var why_not := _cannot_record()
	if not why_not.is_empty():
		_refuse(why_not)
		return
	var id := Time.get_datetime_string_from_system(true).replace(":", "-")
	# Two sessions in one second (F9 twice) must not share, and overwrite, one bundle.
	var stem := id
	var n := 1
	while DirAccess.dir_exists_absolute(sessions_root().path_join(id)):
		n += 1
		id = "%s-%d" % [stem, n]
	_dir = sessions_root().path_join(id)
	DirAccess.make_dir_recursive_absolute(_dir)
	# Keep Godot from importing session media when sessions/ is inside the project.
	if not FileAccess.file_exists(sessions_root().path_join(".gdignore")):
		FileAccess.open(sessions_root().path_join(".gdignore"), FileAccess.WRITE).close()

	# Anchor: read both clocks back to back so they describe the same instant.
	var t0_usec := Time.get_ticks_usec()
	var t0_unix := Time.get_unix_time_from_system()
	_ffmpeg = OS.execute_with_pipe("sh", PackedStringArray(["-c", WATCHDOG, "sh"]) + _ffmpeg_args(_dir.path_join(VIDEO)), false)
	if _ffmpeg.is_empty():
		DirAccess.remove_absolute(_dir)  # still empty: nothing was recorded into it
		_refuse("ffmpeg could not be started.")
		return
	_mark_incomplete("Recording started %s and never stopped: the game crashed or was killed." % Time.get_datetime_string_from_system(true))
	PlaytestTelemetry.start(_dir, false, t0_usec)
	_meta = {
		schema = 1,
		id = id,
		started_at = Time.get_datetime_string_from_unix_time(int(t0_unix)) + "Z",
		t0_unix = t0_unix,
		duration = 0.0,
		game = ProjectSettings.get_setting("application/config/name", ""),
		build = _build(),
		tester = _tester,
		profile = ProjectSettings.get_setting("playtest_analyst/profile", null),
		# Muxed: video and mic share the file and its wall-clock pts, so no *_start.
		capture = {video = VIDEO, audio = VIDEO},
	}
	# x11grab captures the window's size at start: growing it crops the game, shrinking it
	# stops the capture. So the window can't be resized while recording.
	_was_resizable = not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	get_window().title += " [REC]"
	print("PlaytestRecorder: recording %s" % _dir)
	_tell_editor("started", [_dir])


## Stops ffmpeg with "q", then writes session.json and runs `playtest finalize`.
func stop() -> void:
	if not is_recording():
		return
	_meta.duration = snappedf(PlaytestTelemetry.now(), 0.001)
	PlaytestTelemetry.stop()
	var error := _stop_ffmpeg()
	_ffmpeg = {}
	get_window().title = get_window().title.trim_suffix(" [REC]")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, not _was_resizable)
	if error.is_empty():
		var f := FileAccess.open(_dir.path_join("session.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(_meta, "  ", false))
		f.close()
		DirAccess.remove_absolute(_dir.path_join(INCOMPLETE))
		print("PlaytestRecorder: saved %s" % _dir)
		_finalize()
	else:
		_mark_incomplete(error)
		push_error("PlaytestRecorder: %s is incomplete: %s" % [_dir, error])
	_tell_editor("stopped", [_dir, error])


func _process(_delta: float) -> void:
	if is_recording() and not OS.is_process_running(_ffmpeg.pid):
		stop()  # ffmpeg died: stop() marks the bundle incomplete with its error


func _input(input: InputEvent) -> void:
	if input is InputEventKey and input.pressed and not input.echo and input.keycode == KEY_F9:
		get_viewport().set_input_as_handled()
		if is_recording():
			stop()
		else:
			start()


## Closing the window mid-session still produces a complete bundle.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()


## Why this OS can't record at all, "" if it can. The editor dock asks before trying.
static func unsupported_os(os_name: String) -> String:
	if os_name == "Linux":
		return ""
	return "Recording works only on Linux: it captures the game window with ffmpeg's x11grab, which %s doesn't have." % os_name


## Why recording can't start in this game, "" if it can.
func _cannot_record() -> String:
	if DisplayServer.get_name() != "X11":
		return "the game is running on %s, not X11, so ffmpeg can't capture its window. Recording needs an X11 session, or XWayland on Wayland." % DisplayServer.get_name()
	if OS.execute("sh", ["-c", "command -v ffmpeg"]) != 0:
		return "ffmpeg isn't installed, or isn't on the PATH the game was started with."
	return ""


## Leaves nothing behind and tells the editor dock why, so it doesn't wait for "started".
func _refuse(reason: String) -> void:
	push_error("PlaytestRecorder: not recording: %s" % reason)
	_tell_editor("refused", [reason])


func _on_editor_message(message: String, _data: Array) -> bool:
	if message == "stop":
		stop()
		get_tree().quit()
		return true
	return false


func _tell_editor(message: String, data: Array) -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message("%s:%s" % [CHANNEL, message], data)


## Returns "" if ffmpeg exited cleanly and left a video, otherwise what went wrong.
func _stop_ffmpeg() -> String:
	# "q" on stdin lets ffmpeg finalise the file; killing it would truncate it.
	if OS.is_process_running(_ffmpeg.pid):  # writing to a dead process's pipe raises SIGPIPE
		var stdio: FileAccess = _ffmpeg.stdio
		stdio.store_string("q")
		stdio.flush()
	var deadline := Time.get_ticks_msec() + 5000
	while OS.is_process_running(_ffmpeg.pid) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(20)
	var stderr: FileAccess = _ffmpeg.stderr
	var output := stderr.get_buffer(65536).get_string_from_utf8().strip_edges()
	if OS.is_process_running(_ffmpeg.pid):
		OS.execute("pkill", ["-TERM", "-P", str(_ffmpeg.pid)])  # ffmpeg, under the watchdog
		return "ffmpeg did not exit within 5 s of q and was sent SIGTERM. %s" % output
	var code := OS.get_process_exit_code(_ffmpeg.pid)
	if code != 0:
		return "ffmpeg exited with code %d. %s" % [code, output]
	if not FileAccess.file_exists(_dir.path_join(VIDEO)):
		return "ffmpeg wrote no %s. %s" % [VIDEO, output]
	return ""


func _mark_incomplete(reason: String) -> void:
	var f := FileAccess.open(_dir.path_join(INCOMPLETE), FileAccess.WRITE)
	f.store_line(reason)
	f.close()


## Puts the capture on the session clock. Runs in the background and may outlive
## the game; a missing bun or analyst is not an error.
func _finalize() -> void:
	var command := analyst("finalize", _dir)
	if not FileAccess.file_exists(cli_path()) or OS.create_process(command[0], command.slice(1)) == -1:
		print("PlaytestRecorder: skipped `playtest finalize` (no bun, or no analyst CLI at %s: set playtest_analyst/cli)" % cli_path())


## The git short SHA of a source checkout, else null.
func _build() -> Variant:
	if not OS.has_feature("editor"):
		return null
	var out := []
	if OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out) != 0:
		return null
	return (out[0] as String).strip_edges()


func _ffmpeg_args(out_path: String) -> PackedStringArray:
	var window_id := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	return [
		"-hide_banner", "-loglevel", "error", "-nostats", "-y",
		"-f", "x11grab", "-framerate", str(FPS), "-draw_mouse", "0",
		"-window_id", str(window_id), "-i", OS.get_environment("DISPLAY"),
		"-thread_queue_size", "1024", "-f", "pulse", "-i", "default",
		# Both inputs stamp packets with wall-clock time. -copyts keeps those stamps
		# in the file, so each stream's start_time is a unix time.
		"-copyts", "-fps_mode", "passthrough",
		# libx264 needs even dimensions; a resized window may not have them.
		"-vf", "crop=trunc(iw/2)*2:trunc(ih/2)*2",
		"-c:v", "libx264", "-preset", "ultrafast", "-crf", "23", "-pix_fmt", "yuv420p",
		"-c:a", "pcm_s16le", "-ac", "1",
		out_path,
	]
