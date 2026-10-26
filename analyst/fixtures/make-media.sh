#!/usr/bin/env bash
# Writes a placeholder video.mp4 (test pattern + burned-in session time) into each fixture
# bundle, so the viewer can be built and demoed without a real recording. Gitignored.
set -euo pipefail
cd "$(dirname "$0")"
for dir in session-mini; do
	duration=$(jq -r .duration "$dir/session.json")
	ffmpeg -hide_banner -loglevel error -y \
		-f lavfi -i "testsrc2=size=640x360:rate=10:duration=$duration" \
		-vf "drawtext=text='%{pts\:hms}':x=(w-tw)/2:y=h-th-24:fontsize=40:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
		-c:v libx264 -preset veryfast -b:v 150k -pix_fmt yuv420p -movflags +faststart \
		"$dir/video.mp4"
	echo "$dir/video.mp4"
done
