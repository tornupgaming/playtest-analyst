---
name: codex-review
description: Get a branch's diff reviewed by GPT-6.1 Sol through `codex exec` before merging it. Use for every code task before it lands on the integration branch.
---

# Codex review

Phil wants every code change reviewed by GPT-6.1 Sol before it merges. Run:

```sh
.claude/skills/codex-review/review.sh <repo-or-worktree-dir> <base-ref> [TICKET-ID]
```

It reviews `git diff <base-ref>...HEAD` in that directory with a read-only sandbox. It prints the findings and the path of the saved review (`/tmp/codex-review/<ticket>-<sha>.md`). A review takes 3–10 minutes, so run it with `run_in_background`.

## After the review

- Check every finding against the code before acting on it. About 1 in 3 findings from a reviewer is minor or wrong.
- Fix the real ones yourself if they're small. Send big ones back to a builder.
- Record the review's outcome in the merge commit message: findings fixed, skipped and why.
