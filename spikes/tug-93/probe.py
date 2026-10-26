"""Probe Muse Wonder video input: token counts, cost, latency, timestamp accuracy.

Needs META_MODEL_API_KEY. Writes JSON results to ./results/.

  python probe.py count CLIP_DIR                 # token counts per variant and fps (tokenise only)
  python probe.py transcribe CLIP_DIR             # Meta ASR on speech.wav -> CLIP_DIR/transcript.json
  python probe.py analyze CLIP_DIR VARIANT [FPS] [--transcript]
                                                  # one full analysis run, scored against ground truth;
                                                  # --transcript adds transcript.json as text
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import httpx

API = "https://api.meta.ai/v1"
MODEL = "muse-wonder-1.0"
PRICE_IN, PRICE_CACHED, PRICE_OUT = 4.00, 0.20, 20.00  # $ per 1M tokens
RESULTS = Path(__file__).parent / "results"
TOLERANCE_S = 5

PROMPT = """This is a 10-minute recording of a game playtest with the player's think-aloud audio.
List every notable moment: on-screen text or full-screen flashes, objects appearing, and every
sentence the player says. For each, give the time in seconds from the start of the video.
Report what you see and hear only; don't guess."""

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["events"],
    "properties": {
        "events": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["t_seconds", "kind", "text"],
                "properties": {
                    "t_seconds": {"type": "number"},
                    "kind": {"type": "string", "enum": ["visual", "speech"]},
                    "text": {"type": "string", "description": "On-screen text, or the words spoken"},
                },
            },
        }
    },
}

client = httpx.Client(
    base_url=API,
    headers={"Authorization": f"Bearer {os.environ['META_MODEL_API_KEY']}"},
    timeout=httpx.Timeout(900, connect=30),
)


def save(name: str, data) -> None:
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / name).write_text(json.dumps(data, indent=2))
    print(json.dumps(data, indent=2))


def upload(path: Path) -> str:
    """Upload once per file; cache ids in results/files.json."""
    cache_path = RESULTS / "files.json"
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    if str(path) not in cache:
        start = time.monotonic()
        with path.open("rb") as f:
            r = client.post("/files", data={"purpose": "user_data"}, files={"file": (path.name, f, "video/mp4")})
        r.raise_for_status()
        cache[str(path)] = {
            "id": r.json()["id"],
            "bytes": path.stat().st_size,
            "upload_s": round(time.monotonic() - start, 1),
        }
        RESULTS.mkdir(exist_ok=True)
        cache_path.write_text(json.dumps(cache, indent=2))
    return cache[str(path)]["id"]


def body(file_id: str, fps: float | None, transcript: list[dict] | None = None) -> dict:
    video = {"type": "input_video", "file_id": file_id}
    if fps is not None:
        video["fps"] = fps
    content = [{"type": "input_text", "text": PROMPT}, video]
    if transcript is not None:
        lines = "\n".join(f"[{t['start_s']:.1f}s] {t['text']}" for t in transcript)
        content.append({"type": "input_text", "text": f"Think-aloud transcript, timestamped:\n{lines}"})
    return {
        "model": MODEL,
        "input": [{"role": "user", "content": content}],
        "text": {"format": {"type": "json_schema", "name": "events", "strict": True, "schema": SCHEMA}},
        "max_output_tokens": 16000,
    }


def looped(src: Path, minutes: int) -> Path:
    out = src.with_name(f"long{minutes}.mp4")
    if not out.exists():
        loops = minutes // 10 - 1
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-stream_loop", str(loops), "-i", str(src), "-c", "copy", str(out)],
            check=True,
        )
    return out


def count(clip_dir: Path) -> None:
    native = clip_dir / "native.mp4"
    cases = [("native", native, fps) for fps in (None, 0.5, 1, 2, 5)]
    cases += [("noaudio", clip_dir / "noaudio.mp4", None), ("noaudio", clip_dir / "noaudio.mp4", 1)]
    cases += [(f"long{m}", looped(native, m), fps) for m in (60, 180) for fps in (None, 1)]
    rows = []
    for name, path, fps in cases:
        b = body(upload(path), fps)
        b.pop("text")
        r = client.post("/responses/input_tokens", json=b)
        row = {"variant": name, "fps": fps, "status": r.status_code}
        row.update(r.json() if r.is_success else {"error": r.text[:500]})
        rows.append(row)
        print(row)
    save("count.json", rows)


def score(truth: list[dict], events: list[dict]) -> dict:
    """Match each truth event to the nearest reported event of the same kind whose text overlaps."""

    def key(text: str) -> str:
        return max(text.lower().strip("?.!").split(), key=len)

    rows = []
    for t in truth:
        candidates = [e for e in events if e["kind"] == t["kind"] and key(t["text"]) in e["text"].lower()]
        best = min(candidates, key=lambda e: abs(e["t_seconds"] - t["t"]), default=None)
        err = None if best is None else round(best["t_seconds"] - t["t"], 1)
        rows.append({"truth_t": t["t"], "kind": t["kind"], "text": t["text"], "error_s": err})
    found = [r for r in rows if r["error_s"] is not None]
    return {
        "found": f"{len(found)}/{len(rows)}",
        "within_tolerance": f"{sum(abs(r['error_s']) <= TOLERANCE_S for r in found)}/{len(rows)}",
        "mean_abs_error_s": round(sum(abs(r["error_s"]) for r in found) / len(found), 1) if found else None,
        "events": rows,
    }


def transcribe(clip_dir: Path) -> None:
    """ENDPOINTING mode returns one turn per speech segment with start/end ms.

    The API wants 16 or 24 kHz mono WAV, at most 10 minutes and 32 MB.
    """
    wav = clip_dir / "speech16k.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(clip_dir / "speech.wav"), "-ar", "16000",
                    "-ac", "1", str(wav)], check=True)
    request = {"model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV", "mode": "ENDPOINTING"}
    start = time.monotonic()
    with wav.open("rb") as f:
        r = client.post("/asr/transcribe", files={
            "request": (None, json.dumps(request), "application/json"),
            "audio": (wav.name, f, "audio/wav"),
        })
    latency = round(time.monotonic() - start, 1)
    r.raise_for_status()
    # Endpointing sometimes emits a zero-length tail fragment ("all.") after a turn; drop those.
    turns = [{"start_s": t["startMs"] / 1000, "text": t["transcript"]} for t in r.json()["turns"]
             if t["endMs"] > t["startMs"]]
    (clip_dir / "transcript.json").write_text(json.dumps(turns, indent=2))
    truth = json.loads((clip_dir / "ground_truth.json").read_text())
    events = [{"t_seconds": t["start_s"], "kind": "speech", "text": t["text"]} for t in turns]
    speech = [t for t in truth if t["kind"] == "speech"]
    save("asr.json", {"latency_s": latency, "turns": turns, "score": score(speech, events)})


def analyze(clip_dir: Path, variant: str, fps: float | None, with_transcript: bool) -> None:
    file_id = upload(clip_dir / f"{variant}.mp4")
    transcript = json.loads((clip_dir / "transcript.json").read_text()) if with_transcript else None
    name = f"run-{variant}-{fps}{'-transcript' if with_transcript else ''}.json"
    start = time.monotonic()
    r = client.post("/responses", json=body(file_id, fps, transcript))
    latency = round(time.monotonic() - start, 1)
    if not r.is_success:
        save(name, {"status": r.status_code, "error": r.text[:2000], "latency_s": latency})
        return
    resp = r.json()
    u = resp["usage"]
    cached = u["input_tokens_details"].get("cached_tokens", 0)
    cost = ((u["input_tokens"] - cached) * PRICE_IN + cached * PRICE_CACHED + u["output_tokens"] * PRICE_OUT) / 1e6
    text = next(c["text"] for o in resp["output"] if o["type"] == "message" for c in o["content"] if c["type"] == "output_text")
    events = json.loads(text)["events"]
    truth = json.loads((clip_dir / "ground_truth.json").read_text())
    save(
        name,
        {"variant": variant, "fps": fps, "latency_s": latency, "usage": u, "cost_usd": round(cost, 4),
         "score": score(truth, events), "raw_events": events},
    )


if __name__ == "__main__":
    flag = "--transcript" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--transcript"]
    cmd, clip = args[0], Path(args[1])
    if cmd == "count":
        count(clip)
    elif cmd == "transcribe":
        transcribe(clip)
    else:
        analyze(clip, args[2], float(args[3]) if len(args) > 3 else None, flag)
