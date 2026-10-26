#!/usr/bin/env bash
# Renders views of the test level into one labelled contact sheet.
#
#   tools/shots.sh [-p clean|planted] [-o DIR] [VIEW...]
#
# VIEW is a name from VIEWS in tools/shot.gd (default: all of them), or
# name=eye_x,y,z:target_x,y,z for a free camera, e.g. over=40,60,20:0,0,-80.
# Writes DIR/<view>.png and DIR/sheet.png (default DIR: /tmp/shots), and
# prints the sheet's path.
set -euo pipefail
cd "$(dirname "$0")/.."

profile=clean
dir=/tmp/shots
while getopts "p:o:" opt; do
	case $opt in
		p) profile=$OPTARG ;;
		o) dir=$OPTARG ;;
		*) exit 2 ;;
	esac
done
shift $((OPTIND - 1))
views=("$@")
if [[ ${#views[@]} -eq 0 ]]; then
	views=(start ledge plaza terrace hall switch drop fork corridor finish over=50,70,30:0,0,-90)
fi
mkdir -p "$dir"

render() {
	local view=$1 profile=$2 dir=$3 name args
	if [[ $view == *=* ]]; then
		name=${view%%=*}
		local cam=${view#*=}
		args=(--eye "${cam%%:*}" --target "${cam#*:}")
	else
		name=$view
		args=(--view "$view")
	fi
	rm -f "$dir/$name.png"
	timeout 60 godot --path . --resolution 1280x720 -s res://tools/shot.gd -- \
		--out "$dir/$name.png" --profile "$profile" "${args[@]}" >"$dir/$name.log" 2>&1 || true
	if [[ ! -f $dir/$name.png ]]; then
		echo "no image for $name:" >&2
		grep -E 'ERROR|error' "$dir/$name.log" | head -5 >&2
	fi
}
export -f render
printf '%s\n' "${views[@]}" | xargs -P 6 -I{} bash -c 'render "$@"' _ {} "$profile" "$dir"

pngs=()
for view in "${views[@]}"; do
	name=${view%%=*}
	[[ -f $dir/$name.png ]] && pngs+=("$dir/$name.png")
done
montage -font /usr/share/fonts/TTF/DejaVuSans.ttf -pointsize 20 -label '%t' "${pngs[@]}" \
	-tile 3x -geometry 640x360+4+4 -background '#222' -fill white "$dir/sheet.png"
echo "$dir/sheet.png"
