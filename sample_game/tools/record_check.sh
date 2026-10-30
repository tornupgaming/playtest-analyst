#!/usr/bin/env bash
# Records a real session of the test level with --record and checks the bundle,
# without a person: the mic is a PipeWire loopback that hears beeps played into it.
#
#   tools/record_check.sh [--real] [SECONDS]
#
# --real uses the default mic and speakers instead of the loopback: turn the
# speakers up so the mic hears the beeps, and keep the room quiet.
#
# Prints whether the session closed cleanly, the ffmpeg mic's lag behind each
# beep, and whether analyst/ reads the bundle. The game window is closed through
# the window manager, the same as clicking its close button. Needs an X11 or
# XWayland display, pactl, paplay, python3 with numpy and python-xlib, and bun.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}  # override with GODOT=/path/to/godot

real=
[[ ${1:-} == --real ]] && { real=1; shift; }
seconds=${1:-30}
tmp=$(mktemp -d)
sink=()
if [[ -z $real ]]; then
	module=$(pactl load-module module-null-sink sink_name=pt_loop sink_properties=device.description=pt_loop)
	trap 'pactl unload-module "$module"' EXIT
	export PULSE_SINK=pt_loop PULSE_SOURCE=pt_loop.monitor
	sink=(--device=pt_loop)
fi
ffmpeg -v error -f lavfi -i "sine=frequency=1000:duration=0.2,apad=pad_dur=0.3" -ar 48000 "$tmp/beep.wav"

before=$(ls sessions 2>/dev/null || true)
"$GODOT" --path . --display-driver x11 -- --record --tester=record_check >"$tmp/godot.log" 2>&1 &
godot_pid=$!
sleep 3
end=$((SECONDS + seconds - 3))
while ((SECONDS < end)); do
	date +%s.%N >>"$tmp/beeps.txt"
	paplay "${sink[@]}" "$tmp/beep.wav"
	sleep 2.5
done
python3 -I tools/record_check.py close "$godot_pid"
wait

id=$(comm -13 <(echo "$before") <(ls sessions) | tail -1)
dir=sessions/$id
grep -E '^PlaytestRecorder|ERROR' "$tmp/godot.log" || true
ls "$dir"
[[ -e $dir/INCOMPLETE ]] && { echo "FAIL: $(cat "$dir/INCOMPLETE")"; exit 1; }
python3 -I tools/record_check.py beeps "$dir/screen.mkv" "$tmp/beeps.txt"
(cd ../analyst && bun -e "
	import { readSession } from './src/bundle.ts';
	const s = await readSession('../sample_game/$dir');
	console.log('readSession OK:', s.meta.id, 'duration', s.meta.duration, 's,', s.events.length, 'events');
")
