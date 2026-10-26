---
title: Screen, mic and telemetry capture sync (Godot on Linux)
updated: 2026-10-26
sources:
  - spikes/tug-95/README.md
  - spikes/tug-95/session_recorder.gd
  - spikes/tug-95/project.godot
  - spikes/tug-93/FINDINGS.md
---

# Screen, mic and telemetry capture sync

How well screen video, mic audio and telemetry events line up on one session clock when Godot records them. The method is in the [TUG-95 spike README](../../spikes/tug-95/README.md): telemetry is stamped from `Time.get_ticks_usec()`, video comes from an external `ffmpeg -f x11grab` with `-copyts` (wall-clock frame stamps), and the mic goes through `AudioStreamMicrophone` → `AudioEffectRecord`.

**Conditions:** CachyOS (Wayland with XWayland, PipeWire 1.6.9), Godot 4.7.2, ffmpeg 9.0.2, RTX 5060, 30 fps. PipeWire loopback (null sink → monitor as mic), so no real microphone. Runs on 2026-10-26.

## Measured

Final 2-minute run, 19 events (screen flash + 1 kHz beep), `audio/driver/mix_rate=48000` with a 48 kHz mic: [README](../../spikes/tug-95/README.md#results)

| Stream minus event time | Mean | Min | Max | Drift |
|---|---|---|---|---|
| Video | 16.9 ms | 4.0 | 33.2 | +1.2 ms/min |
| Mic (loopback round trip) | 88.7 ms | 84.2 | 93.9 | +0.2 ms/min |

- Two earlier 2-minute runs: mic means of 91.4 and 87.9 ms, max 96.5 ms.
- Godot's output latency was about 25 ms (a parallel `ffmpeg -f pulse` capture, matching `AudioServer.get_output_latency()`). That leaves about 62 ms of mic input latency.
- Video lagged events by 0–45 ms with no drift.
- Real microphone, a single 30-second run with `--real` (laptop speakers into the laptop mic, room noise present), 2026-10-26: the mic lagged the 3 clean beeps by 119.0, 118.6 and 123.7 ms. Room noise also triggered 3 false beep detections. Video lagged by 12–46 ms in the same run. [README](../../spikes/tug-95/README.md#limits-and-follow-ups-for-tug-98)

## Facts about the tools

- **Mix-rate mismatch causes mic drift.** At Godot's default 44.1 kHz mix rate with a 48 kHz PipeWire mic, mic latency grew by about 137 ms/min (109 ms at 3 s, 368 ms at 115 s). The WAV length was still correct, because the delay builds up in the input buffer. [README](../../spikes/tug-95/README.md#findings)
- `AudioServer.get_input_mix_rate()` returns the mix rate, not the device rate, so Godot can't detect the mismatch. [README](../../spikes/tug-95/README.md#findings)
- In Godot 4.7 the mix rate only changes on restart. [README](../../spikes/tug-95/README.md#limits-and-follow-ups-for-tug-98)
- `x11grab` can't capture native Wayland windows. The spike runs Godot with `--display-driver x11`. [README](../../spikes/tug-95/README.md#limits-and-follow-ups-for-tug-98)
- A recorder that stops on `NOTIFICATION_WM_CLOSE_REQUEST` writes a complete bundle when the window is closed early. The check passed after a close at about 13 s. [README](../../spikes/tug-95/README.md#how-it-works)
- Stopping ffmpeg by writing `q` to its stdin finalises the file. Killing the process leaves it truncated. [README](../../spikes/tug-95/README.md#how-it-works)
- Godot's Movie Maker mode doesn't write MP4. [FINDINGS](../../spikes/tug-93/FINDINGS.md#implications-for-other-issues)
- `mic.wav` (stereo, 16-bit, 48 kHz) is about 11.5 MB/min. [README](../../spikes/tug-95/README.md#limits-and-follow-ups-for-tug-98)

## Open questions

- Mic latency with a real microphone, measured over a full 2-minute run in a quiet room. So far there is only one 30-second run with 3 clean beeps (above).
- Capture on Windows (`gdigrab` / `ddagrab`) and macOS (`avfoundation`). Not tested.
- Sync when ffmpeg records the mic itself (`-f pulse`) instead of Godot. Not measured.
