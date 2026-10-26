#!/usr/bin/env bash
# Rebuilds the four synthetic session bundles (TUG-120) under sessions/synthetic/:
# planted-voice, planted-novoice, clean-voice and clean-novoice.
#
#   tools/make_synthetic.sh
#
# Each profile is one continuous bot run (tools/synth.gd) at 1280x720, 30 fps of
# game time. Its voice and no-voice bundles share that run's video and events and
# differ only in mic.wav: Piper think-aloud lines, or silence. Also writes a
# contact sheet per run, one frame every 10 s, to /tmp/synthetic/<profile>_sheet.png.
#
# Piper lives in a venv outside the repo (made on first use):
#   PIPER_VENV   default ~/.cache/playtest-analyst/piper-venv
#   PIPER_VOICE  default ~/.cache/playtest-analyst/voice/en_US-lessac-medium.onnx
#
# These bundles are a smoke test, not the eval: the voice lines are written from
# eval/ground_truth.json (DECISIONS.md §6).
set -euo pipefail
cd "$(dirname "$0")/.."

venv=${PIPER_VENV:-$HOME/.cache/playtest-analyst/piper-venv}
voice=${PIPER_VOICE:-$HOME/.cache/playtest-analyst/voice/en_US-lessac-medium.onnx}
if [[ ! -x $venv/bin/python ]]; then
	python3 -m venv "$venv"
	"$venv/bin/pip" install -q piper-tts
fi
if [[ ! -f $voice ]]; then
	"$venv/bin/python" -m piper.download_voices --download-dir "$(dirname "$voice")" "$(basename "$voice" .onnx)"
fi
godot --headless --path . --import >/dev/null 2>&1

# A private scratch dir per invocation, so builds in two worktrees can't clobber each other.
scratch=$(mktemp -d /tmp/synthetic-run.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
mkdir -p /tmp/synthetic

for profile in planted clean; do
	run=$scratch/$profile
	mkdir -p "$run"
	started=$(date +%s.%N)
	godot --path . --fixed-fps 60 --resolution 1280x720 -s res://tools/synth.gd -- \
		--profile "$profile" --out "$run" --telemetry-dir="$run" --telemetry-game-clock >"$run/godot.log" 2>&1 || true
	if ! grep -q '^finished at' "$run/godot.log"; then
		grep -E 'BOT FAILED|SCRIPT ERROR|Parse Error' -A2 "$run/godot.log" >&2
		cp "$run/godot.log" "/tmp/synthetic/$profile-failed.log"
		echo "$profile run failed; log: /tmp/synthetic/$profile-failed.log" >&2
		exit 1
	fi
	grep -E '^(t=|finished)' "$run/godot.log"

	"$venv/bin/python" -I tools/synth_bundle.py "$run" "sessions/synthetic/$profile-voice" \
		--profile "$profile" --started "$started" --voice "$voice"
	"$venv/bin/python" -I tools/synth_bundle.py "$run" "sessions/synthetic/$profile-novoice" \
		--profile "$profile" --started "$started"

	rm -rf "$run/sheet"
	mkdir "$run/sheet"
	duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$run/screen.mkv")
	for t in $(seq 0 10 "${duration%.*}"); do
		ffmpeg -loglevel error -y -ss "$t" -i "$run/screen.mkv" -frames:v 1 -vf scale=480:-1 \
			"$run/sheet/t=$(printf %03d "$t")s.png"
	done
	montage -font /usr/share/fonts/TTF/DejaVuSans.ttf -pointsize 16 \
		-label '%t' "$run"/sheet/*.png -tile 5x -geometry 480x270+2+2 \
		-background '#222' -fill white "/tmp/synthetic/${profile}_sheet.png"
	echo "/tmp/synthetic/${profile}_sheet.png"
done
