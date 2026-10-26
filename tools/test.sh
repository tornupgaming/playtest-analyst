#!/usr/bin/env bash
# Runs the GDScript tests in tests/ headless. Exit code 0 means all passed.
# --fixed-fps 120 gives one physics frame per frame, so tests can count game time.
set -uo pipefail
cd "$(dirname "$0")/.."

godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . --fixed-fps 120 -s res://tests/run.gd -- --no-telemetry 2>&1 \
	| grep -v -e PagedAllocator -e 'resources still in use' -e 'ObjectDB instances'
exit "${PIPESTATUS[0]}"
