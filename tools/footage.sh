#!/usr/bin/env bash
# Renders the demo video's shots that need no players (docs/demo-script.md shots 2, 3, 8, 12)
# as 1080p 30 fps video and PNG stills. Camera path, pins and card text are in tools/footage.gd.
#
#   tools/footage.sh [DIR]     (default DIR: /tmp/footage)
#
# Writes DIR/flythrough.mp4 (shot 3, 18 s: 15 s of flight, then 3 s on the last view),
# DIR/scoreboard.mp4 (shot 8), DIR/title.mp4 (shot 2), DIR/end.mp4 (shot 12), a PNG of
# each, and DIR/sheet.jpg, a contact sheet of stills. Prints the sheet's path.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}  # override with GODOT=/path/to/godot

dir=${1:-/tmp/footage}
mkdir -p "$dir"
rm -f "$dir"/fly_*.png

render() {  # render NAME [ARGS...]: one Godot run, which must write DIR/NAME.png
	local name=$1
	shift
	rm -f "$dir/$name.png"
	timeout 600 "$GODOT" --path . --fixed-fps 30 --resolution 1920x1080 -s res://tools/footage.gd -- \
		--out "$dir" "$@" >"$dir/$name.log" 2>&1 || true
	if grep -E 'SCRIPT ERROR|^ERROR|Parse Error' -A1 "$dir/$name.log" | grep -v -e PagedAllocator -e 'still in use' >&2 \
		|| [[ ! -f $dir/$name.png ]]; then
		echo "FAIL: see $dir/$name.log" >&2
		exit 1
	fi
}
render scoreboard
render title --card title
render end --card end

encode() {  # encode OUT INPUT_ARGS...
	local out=$1
	shift
	ffmpeg -loglevel error -y "$@" -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -r 30 "$dir/$out"
}
encode flythrough.mp4 -framerate 30 -i "$dir/fly_%04d.png"
encode scoreboard.mp4 -loop 1 -framerate 30 -t 15 -i "$dir/scoreboard.png"
encode title.mp4 -loop 1 -framerate 30 -t 10 -i "$dir/title.png"
encode end.mp4 -loop 1 -framerate 30 -t 10 -i "$dir/end.png"

stills=()
for frame in 0000 0090 0150 0225 0300 0375; do
	cp "$dir/fly_$frame.png" "$dir/flythrough_$frame.png"
	stills+=("$dir/flythrough_$frame.png")
done
rm -f "$dir"/fly_*.png
montage -font DejaVu-Sans -pointsize 18 -label '%t' "${stills[@]}" "$dir/scoreboard.png" "$dir/title.png" \
	"$dir/end.png" -tile 3x -geometry 640x360+4+4 -background '#222' -fill white -quality 85 "$dir/sheet.jpg"
echo "$dir/sheet.jpg"
