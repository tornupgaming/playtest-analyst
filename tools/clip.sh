#!/usr/bin/env bash
# Plays scripted input through the test level and saves what the camera saw.
#
#   tools/clip.sh [-p clean|planted] [-v VIEW] [-c EYE] [-e SECONDS] [-n NAME] [-o DIR] STEPS
#
# STEPS: "actions:seconds,..." with actions joined by "+", e.g.
#   "move_forward:1.5,move_forward+jump:0.5,:1"   (an empty action list waits)
# -v VIEW   start from a view in tools/shot.gd (default: start)
# -c EYE    film from a fixed point x,y,z that follows the player, instead of the game camera
# -e SECS   seconds between frames (default 0.25)
#
# Writes DIR/NAME_strip.png (frames tiled 4 across, numbered) and DIR/NAME.mp4,
# then prints the strip's path and where the player ended up.
set -euo pipefail
cd "$(dirname "$0")/.."

profile=clean view=start eye="" every=0.25 name=clip dir=/tmp/shots
while getopts "p:v:c:e:n:o:" opt; do
	case $opt in
		p) profile=$OPTARG ;;
		v) view=$OPTARG ;;
		c) eye=$OPTARG ;;
		e) every=$OPTARG ;;
		n) name=$OPTARG ;;
		o) dir=$OPTARG ;;
		*) exit 2 ;;
	esac
done
shift $((OPTIND - 1))
steps=$1
mkdir -p "$dir"
rm -f "$dir/${name}"_[0-9][0-9][0-9].png

args=(--no-telemetry --out "$dir/$name.png" --profile "$profile" --view "$view" --play "$steps" --every "$every")
[[ -n $eye ]] && args+=(--eye "$eye")
timeout 300 godot --path . --fixed-fps 60 --resolution 960x540 -s res://tools/shot.gd -- "${args[@]}" \
	>"$dir/$name.log" 2>&1 || true
grep -E 'SCRIPT ERROR|^ERROR' -A1 "$dir/$name.log" | grep -v -e PagedAllocator -e 'still in use' | head -10 >&2 || true

frames=("$dir/${name}"_[0-9][0-9][0-9].png)
montage -font /usr/share/fonts/TTF/DejaVuSans.ttf -pointsize 16 -label '%f' "${frames[@]}" \
	-tile 4x -geometry 480x270+2+2 -background '#222' -fill white "$dir/${name}_strip.png"
ffmpeg -loglevel error -y -framerate "$(python3 -c "print(round(1/$every, 3))")" \
	-i "$dir/${name}_%03d.png" -pix_fmt yuv420p "$dir/$name.mp4"
echo "$dir/${name}_strip.png"
grep '^player at' "$dir/$name.log" || true
