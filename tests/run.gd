extends SceneTree
## Headless test runner. Run through tools/test.sh.
## Runs every `test_*` method of each suite in SUITES. A test returns "" when it
## passes, or a message saying what differed. Quits with 1 if any test failed.

const SUITES: Array[Script] = [
	preload("res://tests/telemetry_test.gd"),
	preload("res://tests/patches_test.gd"),
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed := 0
	var passed := 0
	for script in SUITES:
		for method in script.get_script_method_list():
			if not method.name.begins_with("test_"):
				continue
			var suite: Node = script.new()
			root.add_child(suite)
			var result: Variant = await suite.call(method.name)
			suite.free()
			# A test stopped by a script error returns null, which is not a pass.
			var error: String = result if result is String else "stopped with a script error (see above)"
			if error.is_empty():
				passed += 1
				print("ok    %s" % method.name)
			else:
				failed += 1
				print("FAIL  %s\n      %s" % [method.name, error.replace("\n", "\n      ")])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
