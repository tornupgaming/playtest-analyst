@tool
extends RefCounted
## The patches in one patches.json (DECISIONS.md §8) and their state in one project's
## git history. Apply commits a patch as `playtest-fix: <summary>`, Revert commits its
## reverse. Both refuse on uncommitted changes and return an error message, "" on success.

const SUBJECT := "playtest-fix: "
const FIELDS := ["id", "finding_id", "file", "diff", "rationale", "summary"]

## Why patches.json couldn't be read, "" when it could.
var error := ""
var session_id := ""
var _root: String
var _patches: Array[Dictionary] = []
var _reverts := RegEx.create_from_string("This reverts commit ([0-9a-f]{40})")


func _init(project_root: String, patches_path: String) -> void:
	_root = project_root
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(patches_path))
	if not data is Dictionary or not data.get("patches") is Array or not data.get("session_id") is String:
		error = "%s is not a patches.json." % patches_path
		return
	session_id = data.session_id
	for patch: Variant in data.patches:
		if not patch is Dictionary or not FIELDS.all(func(key: String) -> bool: return patch.get(key) is String):
			error = "%s has a patch without %s." % [patches_path, ", ".join(FIELDS)]
			_patches.clear()
			return
		_patches.append(patch)


## Each patch with `commit`: the SHA of the commit that applied it, "" if HEAD hasn't
## applied it or has reverted it.
func list() -> Array[Dictionary]:
	var applied := _applied()
	var out: Array[Dictionary] = []
	for patch in _patches:
		out.append(patch.merged({commit = applied.get(patch.id, "")}))
	return out


func apply(id: String) -> String:
	var patch := _find(id)
	if patch.is_empty():
		return "There is no patch %s." % id
	if _applied().has(id):
		return "%s is already applied." % id
	var err := _check_clean()
	if err.is_empty():
		err = _check_allowed(patch)
	if err.is_empty():
		err = _git_apply(patch.diff, ["-C0"])
	if err.is_empty():
		err = _commit(patch.diff, ["-R", "-C0"], patch.file, SUBJECT + patch.summary, [
			patch.rationale,
			"Finding: %s\nPatch: %s\nSession: %s" % [patch.finding_id, id, session_id],
		])
	return err


## Commits the patch's reverse, in `git revert`'s message format. Not `git revert` itself:
## its 3-way merge conflicts when a later patch changed a neighbouring line, which
## `git apply -R -C0` tolerates.
func revert(id: String) -> String:
	var patch := _find(id)
	if patch.is_empty():
		return "There is no patch %s." % id
	var commit: String = _applied().get(id, "")
	if commit.is_empty():
		return "%s is not applied." % id
	var err := _check_clean()
	if not err.is_empty():
		return err
	# The patch's own diff, reversed. Not `git diff <commit>`: git-style diffs name files from
	# the repository root, so they'd be skipped when the project is a subfolder of the repo.
	err = _git_apply(patch.diff, ["-R", "-C0"])
	if err.is_empty():
		err = _commit(patch.diff, ["-C0"], patch.file, 'Revert "%s%s"' % [SUBJECT, patch.summary], ["This reverts commit %s." % commit])
	return err


func _find(id: String) -> Dictionary:
	for patch in _patches:
		if patch.id == id:
			return patch
	return {}


## Patch id -> SHA, for this session's patches that HEAD applied and hasn't reverted.
func _applied() -> Dictionary:
	var history := _git(["log", "--fixed-strings", "--grep=" + SUBJECT, "--format=%H%n%B%x1e"])
	var applied := {}
	var reverted := {}
	if history.code != 0:
		return applied
	for entry: String in history.out.split("\u001e"):  # newest first, so a revert comes before its commit
		var sha := entry.strip_edges().get_slice("\n", 0)
		var message := entry.strip_edges().trim_prefix(sha).trim_prefix("\n") + "\n"
		var reverting := _reverts.search(message)
		if reverting:
			reverted[reverting.get_string(1)] = true
			continue
		for patch in _patches:
			var applies := message.begins_with(SUBJECT + patch.summary + "\n") \
				and ("\nPatch: %s\nSession: %s\n" % [patch.id, session_id]) in message
			if applies and not reverted.has(sha) and not applied.has(patch.id):
				applied[patch.id] = sha
	return applied


func _check_clean() -> String:
	var status := _git(["status", "--porcelain", "--untracked-files=no"])
	if status.code != 0:
		return status.out
	var files := Array(status.out.split("\n", false)).map(func(line: String) -> String: return line.substr(3))
	if files.is_empty():
		return ""
	return "Uncommitted changes in %s. Commit or stash them first." % ", ".join(files)


## The diff may touch only the patch's file, and playtest.json's patch_allow must allow it.
func _check_allowed(patch: Dictionary) -> String:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(_root.path_join("playtest.json")))
	var globs: Variant = config.get("patch_allow") if config is Dictionary else null
	if not globs is Array:
		return "playtest.json has no patch_allow list."
	var numstat := _with_diff_file(patch.diff, func(path: String) -> Dictionary: return _git(["apply", "--numstat", path]))
	if numstat.code != 0:
		return numstat.out
	# git reports paths from the repository root; the project may be a subfolder of it.
	var prefix: String = _git(["rev-parse", "--show-prefix"]).out.strip_edges()
	for line: String in numstat.out.split("\n", false):  # "added\tdeleted\tpath"; git quotes odd paths
		var path := line.get_slice("\t", 2).trim_prefix(prefix)
		if path != patch.file:
			return "%s's diff changes %s, not only %s." % [patch.id, path, patch.file]
	if not globs.any(func(glob: Variant) -> bool: return glob is String and _glob_match(patch.file, glob)):
		return "%s is not in playtest.json's patch_allow." % patch.file
	return ""


## Like Bun.Glob, which `playtest patch` uses: `*` and `?` stay within one path segment,
## `**` spans segments and `{a,b}` is a choice.
static func _glob_match(path: String, glob: String) -> bool:
	var pattern := "^"
	var i := 0
	while i < glob.length():
		var c := glob[i]
		if glob.substr(i, 3) == "**/":
			pattern += "(?:.*/)?"
			i += 3
			continue
		if glob.substr(i, 2) == "**":
			pattern += ".*"
			i += 2
			continue
		match c:
			"*": pattern += "[^/]*"
			"?": pattern += "[^/]"
			"{": pattern += "(?:"
			"}": pattern += ")"
			",": pattern += "|"
			_: pattern += c if c.is_valid_identifier() or c.is_valid_int() or c in "/-_" else "\\" + c
		i += 1
	return RegEx.create_from_string(pattern + "$").search(path) != null


func _git_apply(diff: String, flags: Array) -> String:
	var result := _with_diff_file(diff, func(path: String) -> Dictionary: return _git(["apply", "--index"] + flags + [path]))
	return "" if result.code == 0 else result.out


## Commits `file`. On failure, applies `diff` with `undo_flags` to take the index and the
## tree back to HEAD.
func _commit(diff: String, undo_flags: Array, file: String, subject: String, paragraphs: Array) -> String:
	var args := ["commit", "-q", "-m", subject]
	for paragraph: String in paragraphs:
		args += ["-m", paragraph]
	var result := _git(args + ["--", file])
	if result.code == 0:
		return ""
	var undo := _git_apply(diff, undo_flags)
	if not undo.is_empty():
		return "git commit failed, and undoing the change also failed, so %s is left staged:\n%s\n%s" % [file, result.out, undo]
	return "git commit failed, so nothing was changed:\n" + result.out


func _with_diff_file(diff: String, run: Callable) -> Dictionary:
	var file := FileAccess.create_temp(FileAccess.WRITE_READ, "playtest-patch", "diff")  # deleted when freed
	file.store_string(diff)
	file.flush()
	return run.call(file.get_path_absolute())


## {code, out}: git's exit code (-1 if it couldn't run) and its stdout and stderr.
## Not OS.execute(): with an output array it runs the command through `sh`, which would
## expand `$(…)` in a model-written summary or path.
func _git(args: Array) -> Dictionary:
	var git := OS.execute_with_pipe("git", PackedStringArray(["-C", _root] + args), false)
	if git.is_empty():
		return {code = -1, out = "Could not run git. Is it installed?"}
	var out := PackedByteArray()
	while true:
		var running := OS.is_process_running(git.pid)
		var read: PackedByteArray = git.stdio.get_buffer(65536) + git.stderr.get_buffer(65536)
		out += read
		if not running and read.is_empty():
			break
		if read.is_empty():
			OS.delay_msec(1)
	return {code = OS.get_process_exit_code(git.pid), out = out.get_string_from_utf8()}
