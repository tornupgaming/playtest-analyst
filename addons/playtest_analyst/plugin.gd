@tool
extends EditorPlugin
## Adds the Playtest dock and the two runtime autoloads.

const Dock := preload("res://addons/playtest_analyst/dock.gd")
const AUTOLOADS := {
	PlaytestTelemetry = "res://addons/playtest_analyst/telemetry.gd",
	PlaytestRecorder = "res://addons/playtest_analyst/recorder.gd",
}

var _dock: Dock


func _enter_tree() -> void:
	_dock = Dock.new()
	add_debugger_plugin(_dock.debugger)
	add_dock(_dock)


func _exit_tree() -> void:
	remove_debugger_plugin(_dock.debugger)
	remove_dock(_dock)
	_dock.queue_free()


func _enable_plugin() -> void:
	for name: String in AUTOLOADS:
		add_autoload_singleton(name, AUTOLOADS[name])


func _disable_plugin() -> void:
	for name: String in AUTOLOADS:
		remove_autoload_singleton(name)
