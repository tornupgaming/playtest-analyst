@tool
extends EditorDock
## The Playtest dock. Record session plays the main scene with --record; the game's
## PlaytestRecorder reports back over the debugger. Analyse and Open report run the
## analyst CLI on the selected bundle in sessions/ and stream its output here.

const Recorder := preload("res://addons/playtest_analyst/recorder.gd")


## Relays PlaytestRecorder messages between the dock and the running game.
class Debugger extends EditorDebuggerPlugin:
	signal message(name: String, data: Array)

	func _has_capture(capture: String) -> bool:
		return capture == Recorder.CHANNEL

	func _capture(name: String, data: Array, _session_id: int) -> bool:
		message.emit(name.trim_prefix(Recorder.CHANNEL + ":"), data)
		return true

	func send(name: String) -> void:
		for session in get_sessions():
			if session.is_active():
				session.send_message("%s:%s" % [Recorder.CHANNEL, name])


var debugger := Debugger.new()
## The bundle the running game is recording, "" when it isn't.
var _recording := ""
var _was_playing := false
## The project's own run args, put back once the game has launched with ours.
var _saved_run_args: Variant = null
## CLI processes whose output is streaming into the log: execute_with_pipe() results
## plus `command`, and for `serve`, whether its URL has been opened.
var _jobs: Array[Dictionary] = []
var _url := RegEx.create_from_string("https?://\\S+")

var _tester := LineEdit.new()
var _record := Button.new()
var _status := Label.new()
var _sessions := OptionButton.new()
var _analyse := Button.new()
var _open := Button.new()
var _log := TextEdit.new()


func _init() -> void:
	title = "Playtest"
	default_slot = DOCK_SLOT_RIGHT_UL
	var box := VBoxContainer.new()
	add_child(box)
	_tester.placeholder_text = "Tester name"
	_record.text = "Record session"
	_record.pressed.connect(_on_record)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Not recording."
	_sessions.item_selected.connect(func(_i: int) -> void: _update_buttons())
	_analyse.text = "Analyse"
	_analyse.pressed.connect(_run.bind("analyse"))
	_open.text = "Open report"
	_open.pressed.connect(_run.bind("serve"))
	var actions := HBoxContainer.new()
	for button in [_analyse, _open]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	_log.editable = false
	_log.custom_minimum_size.y = 200
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for control in [_tester, _record, _status, _sessions, actions, _log]:
		box.add_child(control)
	debugger.message.connect(_on_game_message)
	_refresh()


func _exit_tree() -> void:
	for job in _jobs:
		if job.command == "serve":
			OS.kill(job.pid)


func _process(_delta: float) -> void:
	var playing := EditorInterface.is_playing_scene()
	if playing and _saved_run_args != null:
		ProjectSettings.set_setting("editor/run/main_run_args", _saved_run_args)
		_saved_run_args = null
	if _was_playing and not playing and not _recording.is_empty():
		_status.text = "The game was stopped while recording, so %s is incomplete. Stop from this dock, F9 or by closing the game window." % _recording.get_file()
		_recording = ""
		_refresh()
	_was_playing = playing
	_record.text = "Stop recording" if not _recording.is_empty() else "Record session"
	for job in _jobs.duplicate():
		_read(job)


func _on_record() -> void:
	if not _recording.is_empty():
		debugger.send("stop")
		_status.text = "Stopping…"
		return
	var args := "-- --record"
	if not _tester.text.strip_edges().is_empty():
		args += " --tester=" + _tester.text.strip_edges().uri_encode()
	# x11grab can only see X11 windows, so run the game through XWayland on Wayland.
	if OS.get_name() == "Linux":
		args = "--display-driver x11 " + args
	_saved_run_args = ProjectSettings.get_setting("editor/run/main_run_args")
	ProjectSettings.set_setting("editor/run/main_run_args", args)
	await ProjectSettings.settings_changed  # the editor rereads run args on this signal
	EditorInterface.play_main_scene()
	_status.text = "Starting the game…"


func _on_game_message(name: String, data: Array) -> void:
	if name == "started":
		_recording = data[0]
		_status.text = "Recording %s. Stop here, with F9, or by closing the game window." % _recording.get_file()
	elif name == "stopped":
		var error: String = data[1]
		_status.text = "Saved %s." % data[0].get_file() if error.is_empty() else "%s is incomplete: %s" % [data[0].get_file(), error]
		_recording = ""
		_refresh(data[0])


## Lists bundles newest first, selecting `select` if given.
func _refresh(select := "") -> void:
	_sessions.clear()
	var root := Recorder.sessions_root()
	var ids := Array(DirAccess.get_directories_at(root)) if DirAccess.dir_exists_absolute(root) else []
	ids.reverse()
	for id: String in ids:
		var dir := root.path_join(id)
		var label := id
		if FileAccess.file_exists(dir.path_join(Recorder.INCOMPLETE)) or not FileAccess.file_exists(dir.path_join("session.json")):
			label += "  (incomplete)"
		elif FileAccess.file_exists(dir.path_join("report.json")):
			label += "  (analysed)"
		_sessions.add_item(label)
		_sessions.set_item_metadata(_sessions.item_count - 1, dir)
		if dir == select:
			_sessions.select(_sessions.item_count - 1)
	_update_buttons()


func _update_buttons() -> void:
	var i := _sessions.selected
	var complete := i >= 0 and not _sessions.get_item_text(i).ends_with("(incomplete)")
	_analyse.disabled = not complete or _jobs.any(func(job: Dictionary) -> bool: return job.command == "analyse")
	_open.disabled = not complete


func _run(command: String) -> void:
	var dir: String = _sessions.get_selected_metadata()
	if command == "serve":
		for job in _jobs:
			if job.command == "serve":
				OS.kill(job.pid)  # one report server at a time
	var line := Recorder.analyst(command, dir)
	var job := OS.execute_with_pipe(line[0], line.slice(1), false)
	_append("$ playtest %s %s\n" % [command, dir.get_file()])
	if job.is_empty():
		_append("Could not run %s. Is bun installed?\n" % line[0])
		return
	job.command = command
	job.opened = false
	_jobs.append(job)
	_update_buttons()


## Streams a job's output into the log; opens the first URL `serve` prints.
func _read(job: Dictionary) -> void:
	var running := OS.is_process_running(job.pid)
	var text := ""
	for pipe: FileAccess in [job.stdio, job.stderr]:
		text += pipe.get_buffer(65536).get_string_from_utf8()
	_append(text)
	if job.command == "serve" and not job.opened:
		var url := _url.search(text)
		if url:
			job.opened = true
			OS.shell_open(url.get_string())
	if not running:
		_append("[playtest %s exited with code %d]\n" % [job.command, OS.get_process_exit_code(job.pid)])
		_jobs.erase(job)
		_refresh(_sessions.get_selected_metadata() if _sessions.selected >= 0 else "")


func _append(text: String) -> void:
	if text.is_empty():
		return
	_log.text += text
	_log.scroll_vertical = _log.get_line_count()
