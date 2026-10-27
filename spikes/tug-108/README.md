# TUG-108: measurements behind the patch dock

27 Oct 2026, git 2.56.0, Godot 4.7.2, CachyOS. Each run used a scratch repo with `eval/tuning_planted.tres` committed as `level/tuning.tres` and the five patches of [`../tug-107/fixture-patches.json`](../tug-107/fixture-patches.json).

**`git revert` of a patch whose neighbour is applied.** p1…p5 applied in order with `git apply -C0 --index` and committed one by one, then `git revert --no-edit` of p2's commit (it changes lines 9–10; p3 changed line 11): exit 1, "CONFLICT (content): Merge conflict in level/tuning.tres". The same revert done as `git diff <c>^ <c>` piped to `git apply -R -C0 --index` applies (`tests/patches_test.gd`, `test_revert_restores_the_original_lines_between_applied_neighbours`).

**`OS.execute` with an output array goes through a shell.** `OS.execute("printf", ["[%s]\n", "$(whoami)", "a \"b\" c"], out, true)` printed `[psmith]` and `[a b c]`: the command substitution ran and the quotes were dropped. `OS.execute_with_pipe` with the same arguments printed them unchanged. Through `OS.execute`, `git commit -m 'Revert "playtest-fix: …"'` failed with "pathspec 'make' did not match any file(s)".

**`OS.execute` output with NUL bytes.** `git log -z` and `git apply --numstat -z` read through `OS.execute(…, output)` printed "Unicode parsing error … Unexpected NUL character" and the NULs were replaced with U+FFFD.

**The editor dirties the tree on open.** Opening a fresh copy of the project (its `.godot/` copied along) in the editor rewrote `art/kenney/Textures/colormap.png.import`, so the dock's first Apply was refused with "Uncommitted changes in art/kenney/Textures/colormap.png.import. Commit or stash them first." After committing that file, Apply and Revert committed (`playtest-fix: narrow ledge gap that caused repeated falls`, then `Revert "playtest-fix: …"`) and `level/tuning.tres` went 6.6 → 4.0 → 6.6.
