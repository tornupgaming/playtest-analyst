#!/usr/bin/env bash
# Review a branch diff with GPT-6.1 Sol via codex exec. See SKILL.md.
#   review.sh DIR BASE_REF [TICKET]
set -euo pipefail
dir=$(cd "$1" && pwd) base=$2 ticket=${3:-review}
sha=$(git -C "$dir" rev-parse --short HEAD)
mkdir -p /tmp/codex-review
out=/tmp/codex-review/$ticket-$sha.md

read -r -d '' prompt <<PROMPT || true
You are reviewing a change in the Playtest Analyst repo (a Godot plugin plus a Bun/TypeScript analysis CLI for a hackathon).

Review the diff from \`git diff $base...HEAD\` in this directory. Read the changed files in full where you need context, plus CLAUDE.md, DECISIONS.md and analyst/src/schema.ts. The ticket is $ticket. If the commit messages or docs state its acceptance criteria, check the change against them.

Look for, in this order:
1. Correctness bugs: wrong results, crashes, unhandled edge cases that real input will hit, races, resource leaks (ffmpeg processes, files), clock/offset errors on the session clock.
2. Contract breaks against analyst/src/schema.ts and the bundle layout in DECISIONS.md.
3. Tests that can't fail for a defect (they'd still pass if the code under test returned undefined), tests that mock internals, tests at seams other than the ones named in commit messages or the ticket.
4. Needless complexity: layers with one caller, speculative options, duplicated decisions.

Don't run commands that write files. Don't comment on style or naming unless it causes a bug.

Output: a ranked list, most severe first, with at most 10 findings and at most 600 words. Each finding gives: severity (high/medium/low), file:line, the concrete failure scenario (input → wrong outcome), and the fix in one sentence. If you find nothing real, say so. Don't pad the list.
PROMPT

codex exec -C "$dir" -s read-only -m gpt-6.1-sol -c model_reasoning_effort='"high"' --ephemeral \
	-o "$out" "$prompt" >"$out.log" 2>&1
echo "== $out"
cat "$out"
