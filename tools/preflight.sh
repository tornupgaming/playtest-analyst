#!/usr/bin/env bash
# Run before testers arrive: checks this machine can record and analyse a playtest.
#
#   tools/preflight.sh [planted|clean]    # the level profile you mean to test; default planted
#
# Prints one PASS or FAIL line per check, each FAIL with what to do, and exits 1 if
# any check failed. Spends nothing: the key is checked by listing models, which is free.
# The mic test reads 2 s of the default mic and keeps nothing.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}  # override with GODOT=/path/to/godot

profile=${1:-planted}
[[ -f eval/tuning_$profile.tres ]] || { echo "Unknown profile '$profile': use planted or clean."; exit 2; }

# About the most one analysis has cost (README: $0.30–0.50 for a 10-minute session).
ANALYSIS_USD=0.50
# A 2-minute record_check bundle (screen.mkv, video.mp4, mic WAV) took 39 MB, i.e. ~1.2 GB
# an hour, but of a still frame. Real play compresses worse, so allow about eight times that.
DISK_GB=10

failed=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }

if [[ $("$GODOT" --version 2>/dev/null | tail -1) == 4.7.* ]]; then
	pass "Godot 4.7"
else
	fail "Godot 4.7 not found on PATH. Install Godot 4.7 and make 'godot' run it."
fi

if ! command -v bun >/dev/null; then
	fail "Bun not found on PATH. Install it from https://bun.sh."
elif [[ ! -d analyst/node_modules ]]; then
	fail "The analyst's packages aren't installed. Run: (cd analyst && bun install)"
else
	pass "Bun, with the analyst's packages installed"
fi

devices=$(ffmpeg -hide_banner -devices 2>/dev/null)
if [[ $devices != *x11grab* || $devices != *pulse* ]]; then
	fail "ffmpeg is missing, or lacks x11grab or pulse input. Install a full ffmpeg build (e.g. your distro's ffmpeg package)."
elif ! timeout 10 ffmpeg -hide_banner -loglevel quiet -f x11grab -i "${DISPLAY:-}" -frames:v 1 -f null - </dev/null; then
	fail "ffmpeg can't capture the screen (DISPLAY='${DISPLAY:-}'). Run this from a terminal on the desktop you'll play on."
else
	pass "ffmpeg, with screen (x11grab) and mic (pulse) capture; grabbed a frame of $DISPLAY"
fi

# Reads the default mic exactly as the recorder does (-f pulse -i default). A muted mic
# records digital silence (-91 dB); a real one in a quiet room peaks around -30 dB.
max_db=$(timeout 10 ffmpeg -hide_banner -nostats -f pulse -i default -t 2 -af volumedetect -f null - 2>&1 |
	sed -n 's/.*max_volume: \(-*[0-9.]*\) dB.*/\1/p')
if [[ -z $max_db ]]; then
	fail "Couldn't record from the default mic. Check PulseAudio or PipeWire is running and a mic is plugged in (pactl get-default-source)."
elif (($(awk "BEGIN { print ($max_db < -60) }"))); then
	fail "The default mic recorded silence (peak $max_db dB). Unmute it (pactl set-source-mute @DEFAULT_SOURCE@ 0) and check it's the mic you mean (pactl get-default-source)."
else
	pass "The default mic hears sound (peak $max_db dB in 2 s)"
fi

if [[ -z ${META_MODEL_API_KEY:-} ]]; then
	fail "META_MODEL_API_KEY is not set. Export your Meta Model API key in ~/.zshenv and open a new terminal."
else
	code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
		-H "Authorization: Bearer $META_MODEL_API_KEY" "${META_API_BASE:-https://api.meta.ai/v1}/models")
	case $code in
	200) pass "META_MODEL_API_KEY is accepted by the Meta API" ;;
	401 | 403) fail "The Meta API rejected META_MODEL_API_KEY (HTTP $code). Copy a fresh key from dev.meta.ai into it." ;;
	*) fail "Couldn't reach the Meta API (HTTP ${code:-none}). Check the internet connection." ;;
	esac
fi

# `playtest spend` prints "$<spent> of $<cap>".
read -r spent cap < <(bun analyst/src/cli.ts spend 2>/dev/null | sed -n 's/^\$\([0-9.]*\) of \$\([0-9.]*\)$/\1 \2/p')
need=$(awk "BEGIN { printf \"%.2f\", 3 * $ANALYSIS_USD }")
if [[ -z ${spent:-} ]]; then
	fail "Couldn't read the spend ledger. Run: bun analyst/src/cli.ts spend"
elif (($(awk "BEGIN { print ($cap - $spent >= $need) }"))); then
	pass "Spend: \$$spent of \$$cap used, enough left for three analyses (\$$need)"
else
	fail "Spend: \$$spent of \$$cap used, less than the \$$need three analyses need. Raise PLAYTEST_SPEND_CAP_USD."
fi

if cmp -s level/tuning.tres "eval/tuning_$profile.tres"; then
	pass "level/tuning.tres is the $profile profile"
else
	fail "level/tuning.tres isn't the $profile profile. Run: cp eval/tuning_$profile.tres level/tuning.tres, then commit it."
fi

# Apply and Revert in the dock refuse while a tracked file has uncommitted changes.
if ! dirty=$(git status --porcelain --untracked-files=no 2>&1); then
	fail "git can't read this checkout: $(head -1 <<<"$dirty")"
elif [[ -z $dirty ]]; then
	pass "No uncommitted changes, so the dock's Apply will work"
else
	fail "Uncommitted changes in $(wc -l <<<"$dirty") tracked file(s), so the dock's Apply will refuse. Commit or discard them (git status)."
fi

free_gb=$(($(df -k --output=avail . | tail -1) / 1024 / 1024))
if ((free_gb >= DISK_GB)); then
	pass "$free_gb GB free on disk (an hour of recording needs about $DISK_GB GB)"
else
	fail "Only $free_gb GB free on disk; an hour of recording needs about $DISK_GB GB. Free some space."
fi

exit $failed
