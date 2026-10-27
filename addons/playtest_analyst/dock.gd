@tool
extends EditorDock
## The Playtest dock. Record session plays the main scene with --record; the game's
## PlaytestRecorder reports back over the debugger. Analyse, Open report and Propose
## fixes run the analyst CLI on the selected bundle in sessions/ and stream its output
## here. The bundle's patches.json is listed below them, to read, apply and revert.

const Recorder := preload("res://addons/playtest_analyst/recorder.gd")
const Patches := preload("res://addons/playtest_analyst/patches.gd")
const DiffView := preload("res://addons/playtest_analyst/diff_view.gd")


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
## The project's own run args, put back once the game has launched with ours. Non-null
## while a start is pending, so Record is disabled then.
var _saved_run_args: Variant = null
## Ticks (ms) when Record asked the editor to play; the run args are given back if the game
## hasn't started 10 s later (no main scene, a cancelled dialog, a launch error).
var _play_requested_ms := 0
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
var _propose := Button.new()
var _log := TextEdit.new()
## The selected bundle's patches.json, null when it has none.
var _patches: Patches
var _patch_list := Tree.new()
var _rationale := Label.new()
var _diff := DiffView.new()
var _apply := Button.new()
var _revert := Button.new()
var _patch_status := Label.new()


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
	_sessions.item_selected.connect(func(_i: int) -> void: _load_patches())
	_analyse.text = "Analyse"
	_analyse.pressed.connect(_run.bind("analyse"))
	_open.text = "Open report"
	_open.pressed.connect(_run.bind("serve"))
	_propose.text = "Propose fixes"
	_propose.pressed.connect(func() -> void: _run("patch", ["--project", _project_root()]))
	var actions := HBoxContainer.new()
	for button in [_analyse, _open, _propose]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	_patch_list.hide_root = true
	_patch_list.custom_minimum_size.y = 190
	_patch_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_patch_list.item_selected.connect(_show_patch)
	_rationale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff.custom_minimum_size.y = 300
	_apply.text = "Apply"
	_apply.pressed.connect(_on_patch.bind(true))
	_revert.text = "Revert"
	_revert.pressed.connect(_on_patch.bind(false))
	var patch_actions := HBoxContainer.new()
	for button in [_apply, _revert]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		patch_actions.add_child(button)
	_patch_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var patches := VBoxContainer.new()
	patches.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for control in [_patch_list, _rationale, _diff, patch_actions, _patch_status]:
		patches.add_child(control)
	_log.editable = false
	_log.custom_minimum_size.y = 120
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(patches)
	split.add_child(_log)
	for control in [_tester, _record, _status, _sessions, actions, split]:
		box.add_child(control)
	debugger.message.connect(_on_game_message)
	_refresh()


func _exit_tree() -> void:
	for job in _jobs:
		if job.command == "serve":
			OS.kill(job.pid)


func _process(_delta: float) -> void:
	var playing := EditorInterface.is_playing_scene()
	var gave_up := not playing and _play_requested_ms > 0 and Time.get_ticks_msec() - _play_requested_ms > 10000
	if (playing or gave_up) and _saved_run_args != null:
		ProjectSettings.set_setting("editor/run/main_run_args", _saved_run_args)
		_saved_run_args = null
		_play_requested_ms = 0
		if gave_up:
			_status.text = "The game didn't start, so nothing is recording. Check the project's main scene."
	if _was_playing and not playing and not _recording.is_empty():
		_status.text = "The game was stopped while recording, so %s is incomplete. Stop from this dock, F9 or by closing the game window." % _recording.get_file()
		_recording = ""
		_refresh()
	_was_playing = playing
	_record.text = "Stop recording" if not _recording.is_empty() else "Record session"
	_record.disabled = _saved_run_args != null
	for job in _jobs.duplicate():
		_read(job)


func _on_record() -> void:
	if not _recording.is_empty():
		debugger.send("stop")
		_status.text = "Stopping…"
		return
	if _saved_run_args != null:
		return  # a second click before the game launched: the run args are ours by now
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
	_play_requested_ms = Time.get_ticks_msec()
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


## Lists bundles newest first, then those one folder down (e.g. synthetic/planted-voice),
## selecting `select` if given, else the newest.
func _refresh(select := "") -> void:
	_sessions.clear()
	var root := Recorder.sessions_root()
	for id in _bundles(root):
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
	_load_patches()


## Bundle paths under `root`, relative to it. A bundle is a folder holding session.json or
## INCOMPLETE; any other folder is searched one level down.
static func _bundles(root: String) -> Array[String]:
	var is_bundle := func(dir: String) -> bool:
		return FileAccess.file_exists(dir.path_join("session.json")) or FileAccess.file_exists(dir.path_join(Recorder.INCOMPLETE))
	var newest_first := func(dir: String) -> Array:
		var ids := Array(DirAccess.get_directories_at(dir)) if DirAccess.dir_exists_absolute(dir) else []
		ids.sort()
		ids.reverse()
		return ids
	var top: Array[String] = []
	var nested: Array[String] = []
	for id: String in newest_first.call(root):
		if is_bundle.call(root.path_join(id)):
			top.append(id)
		else:
			for sub: String in newest_first.call(root.path_join(id)):
				if is_bundle.call(root.path_join(id).path_join(sub)):
					nested.append(id.path_join(sub))
	return top + nested


func _update_buttons() -> void:
	var i := _sessions.selected
	var complete := i >= 0 and not _sessions.get_item_text(i).ends_with("(incomplete)")
	var analysed := i >= 0 and FileAccess.file_exists(_sessions.get_item_metadata(i).path_join("report.json"))
	var running := func(command: String) -> bool: return _jobs.any(func(job: Dictionary) -> bool: return job.command == command)
	_analyse.disabled = not complete or running.call("analyse")
	_open.disabled = not complete or not analysed
	_propose.disabled = not analysed or running.call("patch")
	var patch := _selected_patch()
	_apply.disabled = patch.is_empty() or not patch.commit.is_empty()
	_revert.disabled = patch.is_empty() or patch.commit.is_empty()


func _run(command: String, args: Array = []) -> void:
	var dir: String = _sessions.get_selected_metadata()
	if command == "serve":
		for job in _jobs:
			if job.command == "serve":
				OS.kill(job.pid)  # one report server at a time
	var line := Recorder.analyst(command, dir) + PackedStringArray(args)
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


func _project_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


## Lists the selected bundle's patches, keeping the selected patch selected.
func _load_patches() -> void:
	var keep: String = _selected_patch().get("id", "")
	var i := _sessions.selected
	var path: String = _sessions.get_item_metadata(i).path_join("patches.json") if i >= 0 else ""
	_patches = Patches.new(_project_root(), path) if FileAccess.file_exists(path) else null
	_patch_list.clear()
	var root := _patch_list.create_item()
	_show_status("" if _patches else "No patches yet. Analyse, then Propose fixes.")
	if _patches and not _patches.error.is_empty():
		_show_status(_patches.error, true)
	for patch: Dictionary in _patches.list() if _patches else []:
		var applied: bool = not patch.commit.is_empty()
		var item := root.create_child()
		item.set_text(0, "%s\n%s%s" % [patch.summary, patch.file, "  ·  ✓ Applied" if applied else ""])
		item.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		item.set_metadata(0, patch)
		if applied:
			item.set_custom_color(0, EditorInterface.get_editor_theme().get_color("success_color", "Editor"))
		if patch.id == keep:
			item.select(0)
	_show_patch()


func _selected_patch() -> Dictionary:
	var item := _patch_list.get_selected()
	return item.get_metadata(0) if item else {}


func _show_patch() -> void:
	var patch := _selected_patch()
	_rationale.text = "" if patch.is_empty() else "%s, for finding %s: %s" % [patch.id, patch.finding_id, patch.rationale]
	_diff.show_diff("" if patch.is_empty() else "%s\n%s" % [patch.file, patch.diff])
	_update_buttons()


func _on_patch(apply: bool) -> void:
	var patch := _selected_patch()
	var error: String = _patches.apply(patch.id) if apply else _patches.revert(patch.id)
	_load_patches()
	if not error.is_empty():
		_show_status(error, true)
		return
	_show_status("Committed %s%s." % ["" if apply else "the revert of ", Patches.SUBJECT + patch.summary])
	EditorInterface.get_resource_filesystem().scan()  # reloads the changed file in the editor


func _show_status(text: String, error := false) -> void:
	_patch_status.text = text
	if error:
		_patch_status.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("error_color", "Editor"))
	else:
		_patch_status.remove_theme_color_override("font_color")
