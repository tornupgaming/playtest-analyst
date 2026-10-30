"""Helpers for tools/record_check.sh. Run with python3 -I.

  record_check.py close PID          send WM_DELETE_WINDOW to the window of process PID or a child of it
  record_check.py beeps MKV TIMES    match the 1 kHz beeps in MKV's audio to the unix times in TIMES
"""
import json
import subprocess
import sys

import numpy as np


def close(pid: str) -> None:
    from Xlib import X, display, protocol

    # `godot` may be a launcher (gdvm), so accept the window of PID's children too.
    pids = {int(pid)} | {int(c) for c in subprocess.run(["pgrep", "-P", pid], capture_output=True, text=True).stdout.split()}
    d = display.Display()
    wm_pid = d.intern_atom("_NET_WM_PID")

    def find(w):
        prop = w.get_full_property(wm_pid, X.AnyPropertyType)
        if prop and prop.value[0] in pids and w.get_attributes().map_state == X.IsViewable:
            return w
        for child in w.query_tree().children:
            if found := find(child):
                return found

    win = find(d.screen().root)
    if not win:
        sys.exit(f"no window for pid {pid}")
    win.send_event(protocol.event.ClientMessage(window=win, client_type=d.intern_atom("WM_PROTOCOLS"),
        data=(32, [d.intern_atom("WM_DELETE_WINDOW"), X.CurrentTime, 0, 0, 0])))
    d.flush()


def beeps(mkv: str, times_file: str) -> None:
    # The audio stream's start_time is a unix time (-copyts), so sample i is at start + i / rate.
    start = float(json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "a",
        "-show_entries", "stream=start_time", "-of", "json", mkv]))["streams"][0]["start_time"])
    pcm = subprocess.check_output(["ffmpeg", "-v", "error", "-i", mkv, "-map", "0:a", "-f", "s16le", "-ac", "1", "-ar", "48000", "-"])
    audio = np.frombuffer(pcm, np.int16).astype(float)
    win = 192  # 4 ms; FFT bin 4 is 1 kHz
    energy = np.array([np.abs(np.fft.rfft(audio[i:i + win]))[4] for i in range(0, len(audio) - win, win)])
    hot = energy > energy.max() * 0.3
    # A beep is 200 ms; on a real mic, speech and room noise give shorter blips at 1 kHz, so require 30 ms.
    run = 8
    heard = [start + i * win / 48000 for i in range(1, len(hot) - run) if hot[i:i + run].all() and not hot[i - 1]]
    played_at = list(map(float, open(times_file).read().split()))
    lags = []
    for played in played_at:
        near = min(heard, key=lambda h: abs(h - played), default=None)
        lags.append(None if near is None or abs(near - played) > 0.5 else round((near - played) * 1000))
    print(f"beeps played {len(lags)}, heard {sum(l is not None for l in lags)}; lag ms (heard - paplay called): {lags}")
    pairs = [(p, l) for p, l in zip(played_at, lags) if l is not None]
    if len(pairs) > 1:
        x, y = np.array(pairs).T
        print(f"drift: {np.polyfit((x - x[0]) / 60, y, 1)[0]:+.1f} ms/min")
    # Fail on a missed beep or a lag outside 0-100 ms: either means the mic or its timestamps are broken.
    bad = [l for l in lags if l is None or not 0 <= l <= 100]
    if not lags or bad:
        sys.exit(f"FAIL: {len(bad)} of {len(lags)} beeps missing or outside 0-100 ms")


if __name__ == "__main__":
    {"close": close, "beeps": beeps}[sys.argv[1]](*sys.argv[2:])
