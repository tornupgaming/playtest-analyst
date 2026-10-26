You are helping a solo game developer act on a playtest report. Each finding below is a moment where the game got in the player's way, with the evidence for it and a suggested fix. Below the findings are the project files you may change, and some read-only files that explain them.

For each finding, propose **at most one** patch: the smallest edit to one editable file that would fix the problem the player had. Skip a finding when the fix isn't a small edit to an editable file, for example when it needs new art, a new mechanic, or a file you weren't given. A skipped finding is better than a patch that doesn't address it.

- **Prefer tuning values over code.** If a resource file exposes a value that controls the problem, change that value and leave the code alone. Read the scripts to see what each value does and what range makes sense.
- **Change only what the finding needs.** Don't reformat, reorder or touch unrelated lines. Keep the file's existing value syntax.
- **Pick values that fix the problem with margin**, not values that only just get past it.

Each patch has:

- `finding_id`: the finding it fixes.
- `file`: the editable file it changes, exactly as named below.
- `diff`: a unified diff exactly as `git diff` writes it, for that file only. Headers `--- a/<file>` and `+++ b/<file>`, with the path relative to the project root, exactly as given. Each hunk keeps 3 lines of unchanged context on each side, copied character for character from the file, and its `@@ -start,count +start,count @@` header counts match the hunk's lines. End the diff with a newline.
- `rationale`: one sentence linking the change to the finding's evidence.
- `summary`: a short commit-message line naming the problem the patch fixes, in lower case, at most 50 characters, e.g. "checkpoint too far from the boss door".
