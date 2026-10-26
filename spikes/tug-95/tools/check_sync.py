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


def wav_mono(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path)) as w:
        rate, channels = w.getframerate(), w.getnchannels()
        samples = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    return samples.reshape(-1, channels).astype(float).mean(axis=1), rate


def ffmpeg_mono(path: Path, rate: int = 48000) -> tuple[np.ndarray, int, float]:
    """Samples plus the file's start_time (unix seconds, kept by -copyts)."""
    start = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=start_time", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True, check=True).stdout.strip(", \n")
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(rate), "-f", "s16le", "-"],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.int16).astype(float), rate, float(start)


def audio_beeps(mono: np.ndarray, rate: int, start: float, hz: float = 1000) -> list[float]:
    """Session times where a sustained tone at `hz` starts.

    Measures energy at `hz` only (a lock-in detector over 4 ms windows), so
    room noise and speech that are as loud as a quiet beep don't count.
    """
    mixed = np.cumsum(mono * np.exp(-2j * np.pi * hz * np.arange(len(mono)) / rate))
    ms, win = rate // 1000, rate // 250
    starts = np.arange(0, len(mono) - win, ms)
    level = np.abs(mixed[starts + win] - mixed[starts])  # tone level in [t, t + 4 ms)
    on = level > max(np.median(level) * 30, level.max() * 0.05)  # beep volume varies
    beeps, t = [], 0
    while t < len(on):
        if on[t] and on[t : t + 30].all():  # the beep lasts 80 ms; blips don't
            beeps.append(start + t / 1000)
            t += 1000  # beeps are seconds apart
        else:
            t += 1
    return beeps


def pair(events: list[float], marks: list[float], window: float = 1.0) -> list[float | None]:
    """Offset (mark - event) of the nearest mark within `window` s of each event, or None."""
    return [min((m - e for m in marks if abs(m - e) <= window), key=abs, default=None) for e in events]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session", type=Path)
    ap.add_argument("--budget-ms", type=float, default=100)
    args = ap.parse_args()

    s = json.loads((args.session / "session.json").read_text())
    events = [json.loads(line) for line in (args.session / s["events"]).read_text().splitlines()]
    deaths = [e["t"] for e in events if e["type"] == "death"]
    marks = {
        "video": video_flashes(args.session / s["video"], s["t0_unix"]),
        "mic": audio_beeps(*wav_mono(args.session / s["audio"]), s["audio_start"]),
    }
    # Optional reference: the same mic recorded by ffmpeg (run_spike.sh).
    ref = args.session / "ref_mic.mka"
    if ref.exists():
        mono, rate, start = ffmpeg_mono(ref)
        marks["ffmpeg mic"] = audio_beeps(mono, rate, start - s["t0_unix"])

    budget = args.budget_ms / 1000
    offs = {name: pair(deaths, m) for name, m in marks.items()}
    ok = all(len(marks[n]) == len(deaths) for n in ("video", "mic"))
    print(f"duration {s['duration']:.1f}s  deaths {len(deaths)}  "
          + "  ".join(f"{n} {len(m)}" for n, m in marks.items()))
    print(f"{'death t':>9}" + "".join(f"{n + ' ms':>14}" for n in offs) + f"{'mic-video ms':>14}")
    cell = lambda x: f"{x * 1000:14.1f}" if x is not None else f"{'-':>14}"
    for i, t in enumerate(deaths):
        v, a = offs["video"][i], offs["mic"][i]
        row_ok = v is not None and a is not None and abs(v) <= budget and abs(a) <= budget and abs(a - v) <= budget
        ok &= row_ok
        av = a - v if v is not None and a is not None else None
        print(f"{t:9.3f}" + "".join(cell(o[i]) for o in offs.values()) + cell(av) + ("" if row_ok else "  FAIL"))
    for name, o in offs.items():
        o = np.array([x for x in o if x is not None]) * 1000
        if len(o):
            drift = np.polyfit(deaths[: len(o)], o, 1)[0] * 60 if len(o) > 1 else 0.0
            print(f"{name}: mean {o.mean():.1f}ms  min {o.min():.1f}  max {o.max():.1f}  drift {drift:+.1f}ms/min")
    print("PASS" if ok else "FAIL", f"(video and mic within ±{args.budget_ms:.0f}ms)")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
