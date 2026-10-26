"""Check that video, mic audio and telemetry line up on the session clock.

Finds every white flash in screen.mkv and every beep in mic.wav, maps both
onto the session clock using session.json, and pairs each with the nearest
`death` event. Exits 1 if any death has no flash or beep within the budget.

Usage: python3 check_sync.py SESSION_DIR [--budget-ms 100]
"""

import argparse
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np


def video_flashes(path: Path, t0_unix: float) -> list[float]:
    """Session times of frames where the screen turns white."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "frame=pts_time", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True)
    pts = np.array([float(x.strip(",")) for x in probe.stdout.split()])
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-copyts", "-i", str(path), "-fps_mode", "passthrough",
         "-vf", "scale=32:18,format=gray", "-f", "rawvideo", "-"],
        capture_output=True, check=True).stdout
    luma = np.frombuffer(raw, np.uint8).reshape(-1, 32 * 18).mean(axis=1)
    assert len(luma) == len(pts), (len(luma), len(pts))
    bright = luma > 128
    onsets = np.flatnonzero(bright[1:] & ~bright[:-1]) + 1
    return list(pts[onsets] - t0_unix)


def audio_beeps(path: Path, audio_start: float) -> list[float]:
    """Session times where the mic level jumps from quiet to loud."""
    with wave.open(str(path)) as w:
        rate, channels = w.getframerate(), w.getnchannels()
        samples = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    mono = np.abs(samples.reshape(-1, channels).astype(float)).max(axis=1)
    win = rate // 1000  # 1 ms envelope
    env = mono[: len(mono) // win * win].reshape(-1, win).max(axis=1)
    loud = env > env.max() * 0.3
    beeps, last = [], -1e9
    for ms in np.flatnonzero(loud):
        if ms - last > 1000:  # beeps are seconds apart
            beeps.append(audio_start + ms / 1000)
        last = ms
    return beeps


def pair(events: list[float], marks: list[float]) -> list[float | None]:
    """Offset (mark - event) of the nearest mark to each event, or None."""
    return [min((m - e for m in marks), key=abs, default=None) for e in events]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session", type=Path)
    ap.add_argument("--budget-ms", type=float, default=100)
    args = ap.parse_args()

    s = json.loads((args.session / "session.json").read_text())
    events = [json.loads(line) for line in (args.session / s["events"]).read_text().splitlines()]
    deaths = [e["t"] for e in events if e["type"] == "death"]
    flashes = video_flashes(args.session / s["video"], s["t0_unix"])
    beeps = audio_beeps(args.session / s["audio"], s["audio_start"])

    budget = args.budget_ms / 1000
    v_off, a_off = pair(deaths, flashes), pair(deaths, beeps)
    ok = len(flashes) == len(beeps) == len(deaths)
    print(f"duration {s['duration']:.1f}s  deaths {len(deaths)}  flashes {len(flashes)}  beeps {len(beeps)}")
    print(f"{'death t':>9} {'video ms':>9} {'audio ms':>9} {'a-v ms':>8}")
    for t, v, a in zip(deaths, v_off, a_off):
        row_ok = v is not None and a is not None and abs(v) <= budget and abs(a) <= budget and abs(a - v) <= budget
        ok &= row_ok
        fmt = lambda x: f"{x * 1000:9.1f}" if x is not None else f"{'-':>9}"
        av = f"{(a - v) * 1000:8.1f}" if v is not None and a is not None else f"{'-':>8}"
        print(f"{t:9.3f} {fmt(v)} {fmt(a)} {av}{'' if row_ok else '  FAIL'}")
    for name, offs in (("video", v_off), ("audio", a_off)):
        o = np.array([x for x in offs if x is not None]) * 1000
        if len(o):
            drift = np.polyfit(deaths[: len(o)], o, 1)[0] * 60 if len(o) > 1 else 0.0
            print(f"{name}: mean {o.mean():.1f}ms  min {o.min():.1f}  max {o.max():.1f}  drift {drift:+.1f}ms/min")
    print("PASS" if ok else "FAIL", f"(budget ±{args.budget_ms:.0f}ms)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
