#!/usr/bin/env bash
# Record a sync-test session, then check it.
#
#   ./run_spike.sh [SECONDS]         loopback: game audio is routed into a
#                                    virtual mic, so no speakers or mic needed
#   ./run_spike.sh [SECONDS] --real  real default mic; turn speakers up so
#                                    the mic hears the beeps
#
# Needs: godot 4.7, ffmpeg, PipeWire/PulseAudio (pactl), an X11 or XWayland
# display, python3 with numpy.
set -euo pipefail
cd "$(dirname "$0")"

duration=${1:-120}
mode=${2:-loopback}
out="$PWD/out/$(date +%Y%m%d-%H%M%S)"

if [[ $mode == loopback ]]; then
  module=$(pactl load-module module-null-sink sink_name=pt_loop sink_properties=device.description=pt_loop)
  trap 'pactl unload-module "$module"' EXIT
  export PULSE_SINK=pt_loop PULSE_SOURCE=pt_loop.monitor
fi

# Reference: ffmpeg records the same mic in parallel, stamped with wall time
# minus PulseAudio's reported latency, so check_sync.py can compare it with
# Godot's mic path.
mkdir -p "$out"
ffmpeg -hide_banner -loglevel error -nostdin -y -f pulse -i default -copyts -c:a pcm_s16le "$out/ref_mic.mka" &
ref_pid=$!

# x11grab can only see X11 windows, so run Godot through XWayland on Wayland.
godot --path . --display-driver x11 --audio-driver PulseAudio -- --duration="$duration" --out="$out"
kill -INT "$ref_pid"; wait "$ref_pid" || true
python3 -I tools/check_sync.py "$out"
