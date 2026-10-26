"""Turns one synthetic run (tools/synth.gd) into a session bundle (DECISIONS.md §2).

    python synth_bundle.py RUN_DIR OUT_DIR --profile P --started UNIX [--voice MODEL.onnx]

RUN_DIR holds screen.mkv, events.jsonl and think_aloud.json from the run. With
--voice, mic.wav carries each think-aloud line spoken by Piper at its time, and
think_aloud.json goes into the bundle with the times as spoken. Without it,
mic.wav is silence of the same length. Run with the Piper venv's python.
"""

import argparse
import json
import shutil
import subprocess
import wave
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

RATE = 22050  # Piper's lessac-medium rate; finalize resamples anyway
GAP = 0.3  # seconds kept between lines that would overlap


def video_duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        check=True, capture_output=True, text=True,
    )
    return float(out.stdout)


def speak(lines: list[dict], model: str, duration: float) -> tuple[np.ndarray, list[dict]]:
    """Mixes each line in at its time, pushing one later if the previous is still speaking."""
    from piper import PiperVoice

    voice = PiperVoice.load(model)
    assert voice.config.sample_rate == RATE
    mix = np.zeros(int(duration * RATE), dtype=np.float32)
    spoken, free_at = [], 0.0
    for line in lines:
        audio = np.concatenate([c.audio_float_array for c in voice.synthesize(line["text"])])
        t = max(line["t"], free_at)
        start = int(t * RATE)
        if start + len(audio) > len(mix):
            raise SystemExit(f"line at {t:.2f}s runs past the end ({duration:.2f}s): {line['text']}")
        mix[start : start + len(audio)] += audio * 0.7
        spoken.append({"t": round(t, 2), "text": line["text"]})
        free_at = t + len(audio) / RATE + GAP
    return mix, spoken


def write_wav(path: Path, samples: np.ndarray) -> None:
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("run", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--profile", required=True)
    ap.add_argument("--started", type=float, required=True)
    ap.add_argument("--voice")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    for stale in ["think_aloud.json", "mic.wav", "screen.mkv"]:
        (args.out / stale).unlink(missing_ok=True)
    shutil.copyfile(args.run / "screen.mkv", args.out / "screen.mkv")
    shutil.copyfile(args.run / "events.jsonl", args.out / "events.jsonl")
    duration = round(video_duration(args.out / "screen.mkv"), 3)

    if args.voice:
        lines = json.loads((args.run / "think_aloud.json").read_text())
        mic, spoken = speak(lines, args.voice, duration)
        (args.out / "think_aloud.json").write_text(json.dumps(spoken, indent="\t") + "\n")
    else:
        mic = np.zeros(int(duration * RATE), dtype=np.float32)
    write_wav(args.out / "mic.wav", mic)

    meta = {
        "schema": 1,
        "id": f"synthetic-{args.out.name}",
        "started_at": datetime.fromtimestamp(args.started, timezone.utc).isoformat(timespec="seconds"),
        "t0_unix": round(args.started, 3),
        "duration": duration,
        "game": "Playtest Analyst Test Level",
        "build": None,
        "tester": "synthetic-bot",
        "profile": args.profile,
        "capture": {"video": "screen.mkv", "video_start": 0, "audio": "mic.wav", "audio_start": 0},
    }
    (args.out / "session.json").write_text(json.dumps(meta, indent="\t") + "\n")
    print(f"{args.out}: {duration:.1f}s, {'voice' if args.voice else 'silent'} mic")


if __name__ == "__main__":
    main()
