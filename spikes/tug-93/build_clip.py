"""Build a synthetic 10-minute "playtest" clip with known events at known times.

Some events are visual only and some are speech only, so one clip tests both
timestamp accuracy and whether the model hears the audio track. There is no
on-screen clock, so the model can't read the time off the frame.

Usage: python build_clip.py OUT_DIR PIPER_VOICE.onnx
Writes native.mp4 (720p30 + speech), noaudio.mp4, speech.wav, ground_truth.json.
"""

import json
import subprocess
import sys
import wave
from pathlib import Path

from piper import PiperVoice

DURATION = 600
FONT = "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"

# (time_s, kind, text): on-screen label for visual events, spoken line for speech.
EVENTS = [
    (47, "visual", "YOU DIED"),
    (90, "speech", "Where am I supposed to go?"),
    (133, "visual", "CHECKPOINT"),
    (210, "visual", "KEY"),
    (260, "speech", "I can't see the quest marker at all."),
    (305, "visual", "YOU DIED"),
    (400, "speech", "Is this jump even possible?"),
    (455, "visual", "PAUSED"),
    (520, "speech", "Okay, that was actually fun."),
    (570, "visual", "LEVEL COMPLETE"),
]


def visual_filter(t: int, text: str) -> str:
    on = f"enable='between(t,{t},{t + 3})'"
    style = {
        "YOU DIED": ("red@0.6", "white"),
        "CHECKPOINT": (None, "lime"),
        "KEY": ("yellow", "black"),
        "PAUSED": ("blue", "white"),
        "LEVEL COMPLETE": (None, "gold"),
    }[text]
    box, color = style
    parts = []
    if box == "yellow":
        parts.append(f"drawbox=x=900:y=300:w=160:h=160:color=yellow:t=fill:{on}")
        parts.append(f"drawtext=fontfile={FONT}:text=KEY:x=935:y=360:fontsize=40:fontcolor=black:{on}")
        return ",".join(parts)
    if box:
        parts.append(f"drawbox=x=0:y=0:w=iw:h=ih:color={box}:t=fill:{on}")
    parts.append(
        f"drawtext=fontfile={FONT}:text='{text}':x=(w-text_w)/2:y=(h-text_h)/2"
        f":fontsize=90:fontcolor={color}:{on}"
    )
    return ",".join(parts)


def speech_track(out: Path, voice_path: str) -> None:
    voice = PiperVoice.load(voice_path)
    rate = voice.config.sample_rate
    pcm = bytearray(DURATION * rate * 2)
    for t, kind, text in EVENTS:
        if kind != "speech":
            continue
        clip = b"".join(c.audio_int16_bytes for c in voice.synthesize(text))
        start = t * rate * 2
        pcm[start : start + len(clip)] = clip
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(pcm))


def main(out_dir: str, voice_path: str) -> None:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    wav = out / "speech.wav"
    speech_track(wav, voice_path)

    filters = [
        # Ground strip and a "player" square that wanders left and right.
        "drawbox=x=0:y=600:w=iw:h=120:color=0x3a5a40:t=fill",
        "drawbox=x='540+400*sin(t/3)':y=540:w=60:h=60:color=0xe0e0e0:t=fill",
    ]
    for t, kind, text in EVENTS:
        if kind == "visual":
            filters.append(visual_filter(t, text))

    common = ["-f", "lavfi", "-i", f"color=c=0x1d2b3a:s=1280x720:r=30:d={DURATION}"]
    vf = ",".join(filters)
    venc = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "28", "-pix_fmt", "yuv420p"]
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", *common, "-i", str(wav), "-vf", vf, *venc,
         "-c:a", "aac", "-b:a", "64k", "-shortest", str(out / "native.mp4")],
        check=True,
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(out / "native.mp4"), "-an", "-c:v", "copy",
         str(out / "noaudio.mp4")],
        check=True,
    )
    truth = [{"t": t, "kind": k, "text": text} for t, k, text in EVENTS]
    (out / "ground_truth.json").write_text(json.dumps(truth, indent=2))


if __name__ == "__main__":
    main(*sys.argv[1:])
