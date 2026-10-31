@tool
extends EditorDock
## The Playtest dock, three steps top to bottom. Record plays the main scene with --record;
## the game's PlaytestRecorder reports back over the debugger. Analyse, Open report and
## Propose fixes run the analyst CLI on the selected bundle in sessions/; their progress
## lines show in their step and their full output in the Log. The bundle's patches.json is
## listed under Fixes, each patch with its finding from report.json, to read, apply and revert.

const Recorder := preload("res://addons/playtest_analyst/recorder.gd")
const Patches := preload("res://addons/playtest_analyst/patches.gd")
const DiffView := preload("res://addons/playtest_analyst/diff_view.gd")
## Finding category colours, the report viewer's (analyst/viewer/style.css).
const CATEGORY_COLORS := {difficulty = Color("ec3f5f"), ui = Color("3fa9f5"), pacing = Color("62c83c"), bug = Color("f2843f")}
const SEVERITY_COLORS := {high = Color("ff8a8a"), medium = Color("ffc24a"), low = Color("9aa0a6")}
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


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
## Where Record is up to. Idle: {}. Starting: {run_args, asked_ms}: the project's own run args,
## put back once the game has launched with ours or hasn't 10 s after `asked_ms` (no main scene,
## a cancelled dialog, a launch error). Recording: {bundle}, the folder being written.
var _rec := {}
var _was_playing := false
## CLI processes whose output is streaming into the log: execute_with_pipe() results
## plus `command`, `started_ms`, and for `serve`, whether its URL has been opened.
var _jobs: Array[Dictionary] = []
var _url := RegEx.create_from_string("https?://\\S+")
## A progress line from the CLI, "[1:05] Uploading the video…"; group 1 is the step.
var _step_line := RegEx.create_from_string("(?m)^\\[\\d+:\\d\\d\\] (.+)…$")
## Why this OS can't record, "" if it can.
var _unsupported := Recorder.unsupported_os(OS.get_name())

var _tester := LineEdit.new()
var _record := Button.new()
var _status := Label.new()
var _sessions := OptionButton.new()
var _session_info := Label.new()
var _analyse := Button.new()
var _open := Button.new()
var _propose := Button.new()
## A job's progress lines, by command.
var _steps := {analyse = Label.new(), patch = Label.new()}
var _log_box := FoldableContainer.new()
var _log := TextEdit.new()
## The selected bundle's patches.json, null when it has none; its patches, each with
## `commit` (Patches.list()); and report.json's findings by id.
var _patches: Patches
var _patch_items: Array[Dictionary] = []
var _findings := {}
var _selected_id := ""
var _fix_count := Label.new()
var _fix_list := VBoxContainer.new()
## The open fix's details, moved under its row.
var _details := PanelContainer.new()
var _rationale := Label.new()
var _quote := Label.new()
var _diff := DiffView.new()
var _apply := Button.new()
var _patch_status := Label.new()


func _init() -> void:
	title = "Playtest"
	default_slot = DOCK_SLOT_RIGHT_UL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_tester.placeholder_text = "Who is playing? Optional"
	var field := _pill(Color(1, 1, 1, 0.45))  # an outline, so it reads as a box to type in
	field.set_corner_radius_all(4)
	field.bg_color = Color(0, 0, 0, 0.25)
	field.set_content_margin_all(6)
	_tester.add_theme_stylebox_override("normal", field)
	_record.text = "Record session"
	_record.pressed.connect(_on_record)
	_status.text = "Not recording." if _unsupported.is_empty() else _unsupported
	box.add_child(_section("1  Record", [_caption("Tester name"), _tester, _record, _status]))

	_sessions.item_selected.connect(func(_i: int) -> void:
		for label: Label in _steps.values():
			label.text = ""
			label.hide()
		_load_patches())
	_sessions.fit_to_longest_item = false
	_analyse.pressed.connect(_run.bind("analyse"))
	_open.text = "Open report"
	_open.pressed.connect(_run.bind("serve"))
	box.add_child(_section("2  Analyse", [_caption("Session"), _sessions, _session_info, _row([_analyse, _open]), _steps.analyse]))

	_propose.pressed.connect(func() -> void: _run("patch", ["--project", _project_root()]))
	_rationale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote.modulate = Color(1, 1, 1, 0.65)
	_diff.fit_content = true
	_apply.pressed.connect(_on_patch)
	var details := VBoxContainer.new()
	for control in [_rationale, _quote, _diff, _apply]:
		details.add_child(control)
	_details.add_child(details)
	for label: Label in _steps.values():
		label.hide()
	var fixes := _section("3  Fixes", [_propose, _steps.patch, _fix_list, _patch_status])
	fixes.add_title_bar_control(_fix_count)
	box.add_child(fixes)

	_log.editable = false
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.custom_minimum_size.y = 220
	_log_box.title = "Log"
	_log_box.folded = true
	_log_box.add_child(_log)
	box.add_child(_log_box)
	debugger.message.connect(_on_game_message)
	_refresh()


## A foldable step with `controls` stacked inside it.
static func _section(heading: String, controls: Array) -> FoldableContainer:
	var section := FoldableContainer.new()
	section.title = heading
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	for control: Control in controls:
		if control is Label:
			control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(control)
	section.add_child(box)
	return section


static func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.65)
	return label


static func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for button: Control in buttons:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	return row


func _exit_tree() -> void:
	for job in _jobs:
		if job.command == "serve":
			OS.kill(job.pid)


func _process(_delta: float) -> void:
	var playing := EditorInterface.is_playing_scene()
	var gave_up: bool = not playing and _rec.get("asked_ms", 0) > 0 and Time.get_ticks_msec() - _rec.asked_ms > 10000
	if (playing or gave_up) and _rec.has("run_args"):
		ProjectSettings.set_setting("editor/run/main_run_args", _rec.run_args)
		_rec = {}
		if gave_up:
			_status.text = "The game didn't start, so nothing is recording. Check the project's main scene."
	if _was_playing and not playing and _rec.has("bundle"):
		_status.text = "The game was stopped while recording, so %s is incomplete. Stop from this dock, F9 or by closing the game window." % _rec.bundle.get_file()
		_rec = {}
		_refresh()
	_was_playing = playing
	_record.text = "Stop recording" if _rec.has("bundle") else "Record session"
	_record.disabled = _rec.has("run_args") or not _unsupported.is_empty()
	for job in _jobs.duplicate():
		_read(job)
	_analyse.text = _job_label("analyse", "Analyse again" if _has("report.json") else "Analyse", "Analysing")
	_propose.text = _job_label("patch", "Propose fixes again" if _patches else "Propose fixes", "Proposing fixes")


func _on_record() -> void:
	if _rec.has("bundle"):
		debugger.send("stop")
		_status.text = "Stopping…"
		return
	if _rec.has("run_args"):
		return  # a second click before the game launched: the run args are ours by now
	var args := "-- --record"
	if not _tester.text.strip_edges().is_empty():
		args += " --tester=" + _tester.text.strip_edges().uri_encode()
	# x11grab can only see X11 windows, so run the game through XWayland on Wayland.
	if OS.get_name() == "Linux":
		args = "--display-driver x11 " + args
	_rec = {run_args = ProjectSettings.get_setting("editor/run/main_run_args"), asked_ms = 0}
	# Setting the same value emits nothing, e.g. when an editor crash left ours saved.
	if _rec.run_args != args:
		ProjectSettings.set_setting("editor/run/main_run_args", args)
		await ProjectSettings.settings_changed  # the editor rereads run args on this signal
	EditorInterface.play_main_scene()
	if _rec.has("run_args"):
		_rec.asked_ms = Time.get_ticks_msec()
	_status.text = "Starting the game…"


func _on_game_message(name: String, data: Array) -> void:
	if name == "started":
		if _rec.has("run_args"):  # the game is up, so the project's own run args go back now
			ProjectSettings.set_setting("editor/run/main_run_args", _rec.run_args)
		_rec = {bundle = data[0]}
		_status.text = "Recording %s. Stop here, with F9, or by closing the game window." % data[0].get_file()
	elif name == "stopped":
		var error: String = data[1]
		_status.text = "Saved %s." % data[0].get_file() if error.is_empty() else "%s is incomplete: %s" % [data[0].get_file(), error]
		_rec = {}
		_refresh(data[0])
	elif name == "refused":
		_status.text = "Not recording: %s" % data[0]


## Lists bundles newest first, then those one folder down (e.g. synthetic/planted-voice),
## selecting `select` if given, else the newest.
func _refresh(select := "") -> void:
	_sessions.clear()
	var root := Recorder.sessions_root()
	for id in _bundles(root):
		var dir := root.path_join(id)
		var complete := not FileAccess.file_exists(dir.path_join(Recorder.INCOMPLETE)) and FileAccess.file_exists(dir.path_join("session.json"))
		var analysed := complete and FileAccess.file_exists(dir.path_join("report.json"))
		_sessions.add_item(_session_name(id, dir) + ("  ✓ analysed" if analysed else "" if complete else "  (incomplete)"))
		_sessions.set_item_metadata(_sessions.item_count - 1, {dir = dir, complete = complete})
		if dir == select:
			_sessions.select(_sessions.item_count - 1)
	_load_patches()


## "29 Oct, 23:50 · Sam · 2:24" from session.json, in local time; the folder name for a bundle
## one folder down (e.g. synthetic/planted-voice) or without session.json.
static func _session_name(id: String, dir: String) -> String:
	var session: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("session.json")))
	if "/" in id or not session is Dictionary or not session.get("started_at") is String:
		return id
	var utc := Time.get_unix_time_from_datetime_string(session.started_at.trim_suffix("Z"))
	var t := Time.get_datetime_dict_from_unix_time(utc + Time.get_time_zone_from_system().bias * 60)
	var name := "%d %s, %02d:%02d" % [t.day, MONTHS[t.month - 1], t.hour, t.minute]
	if session.get("tester") is String:
		name += " · " + session.tester
	if session.get("duration") is float:
		name += " · " + _clock(session.duration)
	return name


static func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


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
	var session := _selected_session()
	var complete: bool = session.get("complete", false)
	var running := func(command: String) -> bool: return _jobs.any(func(job: Dictionary) -> bool: return job.command == command)
	_analyse.disabled = not complete or running.call("analyse")
	_open.disabled = not complete or not _has("report.json")
	_propose.disabled = not _has("report.json") or running.call("patch")
	var patch := _selected_patch()
	_apply.text = "Apply fix" if patch.get("commit", "").is_empty() else "Revert fix"


## Whether the selected bundle has `file`.
func _has(file: String) -> bool:
	var session := _selected_session()
	return not session.is_empty() and FileAccess.file_exists(session.dir.path_join(file))


func _run(command: String, args: Array = []) -> void:
	var dir: String = _selected_session().dir
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
	job.started_ms = Time.get_ticks_msec()
	job.opened = false
	job.steps = []
	_jobs.append(job)
	_update_buttons()


## Streams a job's output into the log and its progress lines into its step; opens the
## first URL `serve` prints.
func _read(job: Dictionary) -> void:
	var running := OS.is_process_running(job.pid)
	var text := ""
	for pipe: FileAccess in [job.stdio, job.stderr]:
		text += pipe.get_buffer(65536).get_string_from_utf8()
	_append(text)
	for line in _step_line.search_all(text):
		job.steps.append(line.get_string(1))
	if job.command == "serve" and not job.opened:
		var url := _url.search(text)
		if url:
			job.opened = true
			OS.shell_open(url.get_string())
	var code := 0 if running else OS.get_process_exit_code(job.pid)
	if _steps.has(job.command):
		_steps[job.command].text = _progress(job.steps, running, code)
		_steps[job.command].visible = not _steps[job.command].text.is_empty()
	if not running:
		_append("[playtest %s %s]\n" % [job.command, "finished" if code == 0 else "failed with code %d. The error is above." % code])
		if code != 0:
			_log_box.folded = false
		_jobs.erase(job)
		_refresh(_selected_session().get("dir", ""))


## A job's progress lines as a checklist: done ✓, the current one →, or ✗ where it failed.
static func _progress(steps: Array, running: bool, code: int) -> String:
	var lines := PackedStringArray()
	for i in steps.size():
		var last: bool = i == steps.size() - 1
		lines.append("%s  %s" % ["✓" if not last or (not running and code == 0) else "→" if running else "✗", steps[i]])
	if not running:
		lines.append("✓  Done" if code == 0 else "✗  Failed. The log below says why.")
	return "\n".join(lines)


## `idle`, or while `command` runs, `busy` and how long it has been running, e.g. "Analysing… 1:05".
func _job_label(command: String, idle: String, busy: String) -> String:
	for job in _jobs:
		if job.command == command:
			var s: int = (Time.get_ticks_msec() - job.started_ms) / 1000
			return "%s… %d:%02d" % [busy, s / 60, s % 60]
	return idle


func _append(text: String) -> void:
	if text.is_empty():
		return
	_log.text += text
	_log.scroll_vertical = _log.get_line_count()


func _project_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


## Lists the selected bundle's patches with their findings, keeping the open one open.
func _load_patches() -> void:
	var session := _selected_session()
	var path: String = session.dir.path_join("patches.json") if not session.is_empty() else ""
	_patches = Patches.new(_project_root(), path) if FileAccess.file_exists(path) else null
	_patch_items = _patches.list() if _patches else []
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(session.dir.path_join("report.json"))) if _has("report.json") else null
	var findings: Array = report.get("findings", []) if report is Dictionary else []
	_findings = {}
	for finding: Variant in findings:
		if finding is Dictionary:
			_findings[finding.get("id")] = finding
	_session_info.text = _summary(findings) if report else "Not analysed yet." if session.get("complete", false) else \
		"This recording is incomplete, so it can't be analysed." if not session.is_empty() else "No recordings yet."
	if _details.get_parent():
		_details.get_parent().remove_child(_details)
	for row in _fix_list.get_children():
		_fix_list.remove_child(row)  # now, so the new rows can take their names
		row.queue_free()
	_show_status("" if _patches else "No fixes yet." if report else "Analyse the session first, then propose fixes.")
	if _patches and not _patches.error.is_empty():
		_show_status(_patches.error, true)
	var applied := _patch_items.filter(func(p: Dictionary) -> bool: return not p.commit.is_empty()).size()
	_fix_count.text = "%d proposed · %d applied" % [_patch_items.size(), applied] if _patches else ""
	for patch in _patch_items:
		_fix_list.add_child(_fix_row(patch, _findings.get(patch.finding_id, {})))
	if not _patch_items.any(func(p: Dictionary) -> bool: return p.id == _selected_id):
		_selected_id = ""
	_show_patch()


## "4 findings: 2 high, 1 medium, 1 low".
static func _summary(findings: Array) -> String:
	var counts := PackedStringArray()
	for severity: String in SEVERITY_COLORS:
		var n := findings.filter(func(f: Variant) -> bool: return f is Dictionary and f.get("severity") == severity).size()
		if n > 0:
			counts.append("%d %s" % [n, severity])
	return "%d finding%s%s" % [findings.size(), "" if findings.size() == 1 else "s", ": " + ", ".join(counts) if counts else ""]


## One fix in the list: a dot in its finding's category colour, its summary, where and when
## the finding happened and the file it changes, and the finding's severity.
func _fix_row(patch: Dictionary, finding: Dictionary) -> PanelContainer:
	var theme := EditorInterface.get_editor_theme()
	var row := PanelContainer.new()
	row.name = patch.id
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "Patch %s, for finding %s in the report." % [patch.id, patch.finding_id]
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_selected_id = "" if _selected_id == patch.id else patch.id  # a second click closes it
			_show_patch())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var category: String = finding.get("category", "")
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", CATEGORY_COLORS.get(category, Color.GRAY))
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # beside the summary, not the middle
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var summary := Label.new()
	summary.text = patch.summary.left(1).to_upper() + patch.summary.substr(1)
	var where := PackedStringArray()
	if finding:
		where.append("UI" if category == "ui" else category.capitalize())
		if finding.get("zone") is String:
			where.append(finding.zone)
		where.append(_clock(float(finding.get("t_start", 0))))
	where.append(patch.file.get_file())
	if not patch.commit.is_empty():
		where.append("✓ Applied")
		summary.add_theme_color_override("font_color", theme.get_color("success_color", "Editor"))
	var detail := _caption(" · ".join(where))
	for label: Label in [summary, detail]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(label)
	line.add_child(dot)
	line.add_child(text)
	var severity: String = finding.get("severity", "")
	if SEVERITY_COLORS.has(severity):
		var chip := Label.new()
		chip.text = severity.capitalize()
		chip.add_theme_color_override("font_color", SEVERITY_COLORS[severity])
		chip.add_theme_font_size_override("font_size", roundi(theme.get_font_size("main_size", "EditorFonts") * 0.85))
		chip.add_theme_stylebox_override("normal", _pill(SEVERITY_COLORS[severity]))
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(chip)
	for control: Control in [dot, text, summary, detail]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


## A rounded outline in `color`.
static func _pill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(99)
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(color, 0.45)
	style.set_border_width_all(1)
	style.content_margin_left = 7
	style.content_margin_right = 7
	return style


## The selected bundle as {dir, complete}, {} when there is none.
func _selected_session() -> Dictionary:
	return _sessions.get_selected_metadata() if _sessions.selected >= 0 else {}


func _selected_patch() -> Dictionary:
	for patch in _patch_items:
		if patch.id == _selected_id:
			return patch
	return {}


## Highlights the open fix's row and shows its details under it.
func _show_patch() -> void:
	var patch := _selected_patch()
	var row: Control = null
	for child: Control in _fix_list.get_children():
		if child == _details:
			continue
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.08 if child.name == patch.get("id") else 0.0)
		style.set_corner_radius_all(5)
		style.set_content_margin_all(6)
		child.add_theme_stylebox_override("panel", style)
		if child.name == patch.get("id"):
			row = child
	if _details.get_parent():
		_details.get_parent().remove_child(_details)
	if row:
		var finding: Dictionary = _findings.get(patch.finding_id, {})
		var line := StyleBoxFlat.new()
		line.bg_color = Color.TRANSPARENT
		line.border_width_left = 2
		line.border_color = CATEGORY_COLORS.get(finding.get("category"), Color.GRAY)
		line.content_margin_left = 10
		line.content_margin_bottom = 6
		_details.add_theme_stylebox_override("panel", line)
		_rationale.text = patch.rationale
		var quotes: Variant = finding.get("evidence", {}).get("quotes")
		var quote: Variant = quotes[0] if quotes is Array and not quotes.is_empty() else null
		_quote.visible = quote is Dictionary
		if _quote.visible:
			_quote.text = "“%s”  The tester, at %s" % [quote.get("text", ""), _clock(float(quote.get("t", 0)))]
		_diff.show_diff("%s\n%s" % [patch.file, patch.diff])
		_fix_list.add_child(_details)
		_fix_list.move_child(_details, row.get_index() + 1)
	_update_buttons()


func _on_patch() -> void:
	var patch := _selected_patch()
	var apply: bool = patch.commit.is_empty()
	var error: String = _patches.apply(patch.id) if apply else _patches.revert(patch.id)
	_load_patches()
	if not error.is_empty():
		_show_status(error, true)
		return
	_show_status("Committed %s%s." % ["" if apply else "the revert of ", Patches.SUBJECT + patch.summary])
	EditorInterface.get_resource_filesystem().scan()  # reloads the changed file in the editor


func _show_status(text: String, error := false) -> void:
	_patch_status.text = text
	_patch_status.visible = not text.is_empty()
	if error:
		_patch_status.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("error_color", "Editor"))
	else:
		_patch_status.remove_theme_color_override("font_color")
