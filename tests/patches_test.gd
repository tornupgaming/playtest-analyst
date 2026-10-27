extends Node
## Patches (addons/playtest_analyst/patches.gd) driven against a throwaway git repo that
## holds the planted tuning, which the TUG-107 fixture patches were made against.

const PATCHES := preload("res://addons/playtest_analyst/patches.gd")
const FIXTURE := "res://spikes/tug-107/fixture-patches.json"
const ALLOW := "{ \"patch_allow\": [\"level/tuning.tres\", \"level/*.gd\"] }\n"
const PLANTED := """[gd_resource type="Resource" script_class="LevelTuning" format=3]

[ext_resource type="Script" path="res://level/tuning.gd" id="1_tuning"]

[resource]
script = ExtResource("1_tuning")
ledge_gap_width = 6.6
ledge_bypass_deaths = 5
marker_color = Color(0.816, 0.486, 0.337, 1)
marker_emission = 0.0
switch_prompt_text = "Find a way through."
enemy_aggro_delay = 0.0
fork_arrow_points_to = "left"
corridor_segments = 12
"""

var _repo: DirAccess  # a temp dir, deleted with this suite
var _root := ""
var _project := ""  # the Godot project inside the repo: _root, or a subfolder of it


func test_apply_commits_the_patch_as_playtest_fix() -> String:
	var patches = _fixture_repo()
	var error: String = patches.apply("p1")
	return _expect({
		error = error,
		line = _tuning().get_slice("\n", 6),
		message = _git(["log", "-1", "--format=%B"]),
		committed = _git(["show", "--format=", "--name-only", "HEAD"]),
		applied = _applied(patches),
	}, {
		error = "",
		line = "ledge_gap_width = 4.0",
		message = "playtest-fix: narrow ledge gap that caused repeated falls\n\nFour fall deaths falling just short show the gap is too wide, so the narrower width restores a comfortable margin.\n\nFinding: f1\nPatch: p1\nSession: fixture-planted\n\n",
		committed = "level/tuning.tres\n",
		applied = ["p1"],
	})


func test_all_five_apply_in_order_to_neighbouring_lines() -> String:
	var patches = _fixture_repo()
	var errors := ["p1", "p2", "p3", "p4", "p5"].map(func(id: String) -> String: return patches.apply(id))
	return _expect({errors = errors, tuning = _tuning(), applied = _applied(patches)}, {
		errors = ["", "", "", "", ""],
		tuning = PLANTED.replace("ledge_gap_width = 6.6", "ledge_gap_width = 4.0") \
			.replace("marker_color = Color(0.816, 0.486, 0.337, 1)", "marker_color = Color(0.2, 0.85, 1, 1)") \
			.replace("marker_emission = 0.0", "marker_emission = 2.0") \
			.replace("\"Find a way through.\"", "\"Press the red switch on the balcony.\"") \
			.replace("enemy_aggro_delay = 0.0", "enemy_aggro_delay = 2.5") \
			.replace("\"left\"", "\"right\""),
		applied = ["p1", "p2", "p3", "p4", "p5"],
	})


func test_a_dirty_tree_is_refused_and_nothing_changes() -> String:
	var patches = _fixture_repo()
	patches.apply("p1")
	_write("README.md", "edited\n")
	var errors := [patches.apply("p2"), patches.revert("p1")]
	return _expect({errors = errors, tuning = _tuning().get_slice("\n", 6) + " / " + _tuning().get_slice("\n", 8), applied = _applied(patches)}, {
		errors = [
			"Uncommitted changes in README.md. Commit or stash them first.",
			"Uncommitted changes in README.md. Commit or stash them first.",
		],
		tuning = "ledge_gap_width = 4.0 / marker_color = Color(0.816, 0.486, 0.337, 1)",
		applied = ["p1"],
	})


func test_revert_restores_the_original_lines_between_applied_neighbours() -> String:
	var patches = _fixture_repo()
	for id in ["p1", "p2", "p3"]:
		patches.apply(id)
	var error: String = patches.revert("p2")
	var after_revert := {
		error = error,
		lines = Array(_tuning().split("\n")).slice(6, 11),
		subject = _git(["log", "-1", "--format=%s"]),
		applied = _applied(patches),
	}
	return _expect({after_revert = after_revert, reapply = patches.apply("p2"), applied = _applied(patches)}, {
		after_revert = {
			error = "",
			lines = [
				"ledge_gap_width = 4.0",
				"ledge_bypass_deaths = 5",
				"marker_color = Color(0.816, 0.486, 0.337, 1)",
				"marker_emission = 0.0",
				"switch_prompt_text = \"Press the red switch on the balcony.\"",
			],
			subject = "Revert \"playtest-fix: make plaza beacon contrasting and emissive\"\n",
			applied = ["p1", "p3"],
		},
		reapply = "",
		applied = ["p1", "p2", "p3"],
	})


func test_a_patch_outside_the_allowlist_is_refused() -> String:
	_fixture_repo()
	var widen := "--- a/playtest.json\n+++ b/playtest.json\n@@ -1 +1 @@\n-%s+{ \"patch_allow\": [\"*\"] }\n" % ALLOW
	_write("outside.json", JSON.stringify({session_id = "s", patches = [
		{id = "p1", finding_id = "f1", file = "playtest.json", diff = widen, rationale = "r", summary = "allow everything"},
		{id = "p2", finding_id = "f1", file = "level/tuning.tres", diff = widen, rationale = "r", summary = "allow everything"},
	]}))
	var patches = PATCHES.new(_root, _root.path_join("outside.json"))
	return _expect({errors = [patches.apply("p1"), patches.apply("p2")], allow = _read("playtest.json"), applied = _applied(patches)}, {
		errors = [
			"playtest.json is not in playtest.json's patch_allow.",
			"p2's diff changes playtest.json, not only level/tuning.tres.",
		],
		allow = ALLOW,
		applied = [],
	})


func test_model_text_reaches_the_commit_message_verbatim() -> String:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fixture.patches = [fixture.patches[0].merged({summary = "ledge gap $(echo wide) \"too\" `wide`"}, true)]
	_fixture_repo()
	_write("quoted.json", JSON.stringify(fixture))
	var patches = PATCHES.new(_root, _root.path_join("quoted.json"))
	return _expect([patches.apply("p1"), _git(["log", "-1", "--format=%s"])], [
		"",
		"playtest-fix: ledge gap $(echo wide) \"too\" `wide`\n",
	])


## A repo with the planted tuning, playtest.json and a README committed; the fixture patches.
func test_a_project_in_a_subfolder_of_the_repo_applies_and_reverts() -> String:
	var patches = _fixture_repo("game")
	var errors := [patches.apply("p1"), patches.apply("p2"), patches.revert("p1")]
	return _expect({errors = errors, lines = _tuning().get_slice("\n", 6) + " / " + _tuning().get_slice("\n", 8), applied = _applied(patches)}, {
		errors = ["", "", ""],
		lines = "ledge_gap_width = 6.6 / marker_color = Color(0.2, 0.85, 1, 1)",
		applied = ["p2"],
	})


func test_the_allowlist_matches_globs_the_way_the_cli_does() -> String:
	var spans: String = _fixture_repo("", "{ \"patch_allow\": [\"**/*.tres\"] }\n").apply("p1")
	var choice: String = _fixture_repo("", "{ \"patch_allow\": [\"level/{tuning,other}.tres\"] }\n").apply("p1")
	var other: String = _fixture_repo("", "{ \"patch_allow\": [\"level/**/*.gd\"] }\n").apply("p1")
	return _expect([spans, choice, other], ["", "", "level/tuning.tres is not in playtest.json's patch_allow."])


func test_a_rejected_commit_leaves_the_tree_as_it_was() -> String:
	var patches = _fixture_repo()
	patches.apply("p1")
	_hook("#!/bin/sh\nexit 1\n")
	var errors := [patches.apply("p2").get_slice("\n", 0), patches.revert("p1").get_slice("\n", 0)]
	return _expect({errors = errors, lines = _tuning().get_slice("\n", 6) + " / " + _tuning().get_slice("\n", 8), status = _git(["status", "--porcelain"]), applied = _applied(patches)}, {
		errors = ["git commit failed, so nothing was changed:", "git commit failed, so nothing was changed:"],
		lines = "ledge_gap_width = 4.0 / marker_color = Color(0.816, 0.486, 0.337, 1)",
		status = "",
		applied = ["p1"],
	})


## A pre-commit hook in the temp repo, e.g. one that rejects every commit.
func _hook(script: String) -> void:
	var path := _root.path_join(".git/hooks/pre-commit")
	FileAccess.open(path, FileAccess.WRITE).store_string(script)
	OS.execute("chmod", ["+x", path])


func _fixture_repo(subfolder := "", allow := ALLOW) -> RefCounted:
	for name in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"]:
		OS.unset_environment(name)  # they would point git away from the temp repo
	_repo = DirAccess.create_temp("playtest-patches-test")
	_root = _repo.get_current_dir()
	_git(["init", "-q"])
	if _git(["rev-parse", "--show-toplevel"]).strip_edges() != _root:
		OS.crash("patches_test: git is not working in the temp repo %s" % _root)
	for setting in [["user.name", "Test"], ["user.email", "test@example.com"], ["commit.gpgsign", "false"]]:
		_git(["config"] + setting)
	_project = _root.path_join(subfolder)
	DirAccess.make_dir_recursive_absolute(_project.path_join("level"))
	_write("level/tuning.tres", PLANTED)
	_write("playtest.json", allow)
	_write("README.md", "fixture\n")
	_git(["add", "."])
	_git(["commit", "-q", "-m", "fixture"])
	return PATCHES.new(_project, ProjectSettings.globalize_path(FIXTURE))


func _applied(patches: RefCounted) -> Array:
	return patches.list().filter(func(p: Dictionary) -> bool: return not p.commit.is_empty()).map(func(p: Dictionary) -> String: return p.id)


func _tuning() -> String:
	return _read("level/tuning.tres")


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(_project.path_join(path))


func _write(path: String, text: String) -> void:
	FileAccess.open(_project.path_join(path), FileAccess.WRITE).store_string(text)


func _git(args: Array) -> String:
	var output := []
	OS.execute("git", PackedStringArray(["-C", _root] + args), output, true)
	return "".join(output)


func _expect(actual: Variant, expected: Variant) -> String:
	if actual == expected:
		return ""
	return "expected %s\ngot      %s" % [JSON.stringify(expected), JSON.stringify(actual)]
