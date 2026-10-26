#!/usr/bin/env bash
# Smoke test: import assets, then build the level headless with both tuning
# profiles. Prints a summary per profile and any script errors.
# Exit code 0 means no errors.
set -uo pipefail
cd "$(dirname "$0")/.."

godot --headless --path . --import >/dev/null 2>&1
out=$(godot --headless --path . -s res://tools/check.gd -- --no-telemetry 2>&1)
# Leak reports at exit are engine noise from quitting a -s script, not our errors.
errors=$(grep -E 'SCRIPT ERROR|^ERROR|Parse Error' <<<"$out" \
	| grep -v -e 'PagedAllocator' -e 'resources still in use' -e 'ObjectDB instances')
summary=$(grep -E '^(clean|planted):' <<<"$out" || true)
echo "$summary"
if [[ -n "$errors" || $(wc -l <<<"$summary") -ne 2 || -z "$summary" ]]; then
	grep -A1 -E 'SCRIPT ERROR|^ERROR|Parse Error' <<<"$out" \
		| grep -v -e 'PagedAllocator' -e 'resources still in use' -e 'ObjectDB instances' | head -40
	echo "FAIL"
	exit 1
fi
echo "OK"
