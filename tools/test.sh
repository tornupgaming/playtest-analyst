#!/usr/bin/env bash
# Runs the GDScript tests in tests/ headless. Exit code 0 means all passed.
# --fixed-fps 120 gives one physics frame per frame, so tests can count game time.
# Any script error fails the run: a suite that doesn't compile would otherwise be skipped.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}  # override with GODOT=/path/to/godot

"$GODOT" --headless --path . --import >/dev/null 2>&1
out=$("$GODOT" --headless --path . --fixed-fps 120 -s res://tests/run.gd 2>&1)
code=$?
grep -v -e PagedAllocator -e 'resources still in use' -e 'ObjectDB instances' <<<"$out"
if grep -q -e 'SCRIPT ERROR' -e 'Parse Error' <<<"$out"; then
	echo "FAIL: script errors (above)"
	exit 1
fi
exit "$code"
