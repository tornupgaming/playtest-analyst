#!/usr/bin/env bash
# TUG-104 real check: a 6 s slideshow of three TUG-118 frames (beacon 0–2 s, drop 2–4 s, fork 4–6 s),
# a hand-written report with five highlights, then `playtest annotate` and a 2×2 contact sheet
# (f1, f2, f4, plain drop frame). Five sam-3.1 calls, $0.0125.
#   spikes/tug-104/check.sh [/tmp/annotate]
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out=${1:-/tmp/annotate}
frames=$root/spikes/tug-94/frames
mkdir -p "$out/session"
ffmpeg -y -loglevel error -loop 1 -t 2 -i "$frames/beacon.png" -loop 1 -t 2 -i "$frames/drop.png" -loop 1 -t 2 -i "$frames/fork.png" \
  -filter_complex "[0][1][2]concat=n=3:v=1,fps=10,format=yuv420p" -c:v libx264 "$out/session/video.mp4"
finding() { # id t prompt
  printf '{"id":"%s","t_start":%s,"t_end":%s,"category":"confusion","severity":"medium","zone":null,"summary":"","evidence":{"quotes":[],"telemetry":[],"visual":""},"suggested_fix":"","highlight":{"t":%s,"prompt":"%s"}}' "$1" "$2" "$2" "$2" "$3"
}
cat > "$out/session/report.json" <<JSON
{"schema":1,"session_id":"tug104-check","created_at":"2026-10-26T00:00:00Z","model":"muse-wonder-1.0","config":"hand",
 "findings":[$(finding f1 1 "the star"),$(finding f2 3 "the mushroom"),$(finding f3 3 "the exit sign"),$(finding f4 5 "the arrow sign"),$(finding f5 1 "the player")],
 "usage":{"input_tokens":0,"cached_tokens":0,"output_tokens":0,"cost_usd":0,"latency_s":0}}
JSON
cd "$root/analyst"
bun src/cli.ts spend
time bun src/cli.ts annotate "$out/session"
bun src/cli.ts spend
f=$out/session/analysis/frames
ffmpeg -y -loglevel error -i "$f/f1.png" -i "$f/f2.png" -i "$f/f4.png" -i "$frames/drop.png" \
  -filter_complex "[0][1][2][3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0" "$out/sheet.png"
echo "sheet: $out/sheet.png"
