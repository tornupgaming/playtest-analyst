---
title: Screen, mic and telemetry capture sync (Godot on Linux)
updated: 2026-10-27
sources:
  - spikes/tug-95/README.md
  - spikes/tug-95/tools/check_sync.py
  - spikes/tug-95/session_recorder.gd
  - spikes/tug-95/project.godot
  - spikes/tug-93/FINDINGS.md
  - spikes/tug-99/results/finalize-alignment.txt
  - spikes/tug-99/results/adelay.txt
  - docs/recorder.md
  - tools/record_check.sh
---

# Screen, mic and telemetry capture sync

How well screen video, mic audio and telemetry events line up on one session clock when Godot records them. The method is in the [TUG-95 spike README](../../spikes/tug-95/README.md): telemetry is stamped from `Time.get_ticks_usec()`, video comes from an external `ffmpeg -f x11grab` with `-copyts` (wall-clock frame stamps), and the mic goes through `AudioStreamMicrophone` → `AudioEffectRecord`.

**Conditions:** CachyOS (Wayland with XWayland, PipeWire 1.6.9), Godot 4.7.2 with `audio/driver/mix_rate=48000`, ffmpeg 9.0.2, RTX 5060, 30 fps. Each event is a screen flash plus a 1 kHz beep. Loopback runs use a PipeWire null sink, with its monitor as the mic. Real-mic runs play laptop speakers into the laptop mic. The ffmpeg mic is `ffmpeg -f pulse -i default -copyts`, run as a separate process alongside Godot. All runs were on 2026-10-26.

## Measured

Stream minus event time: [README](../../spikes/tug-95/README.md#results)

| Run | Video | Godot mic | ffmpeg mic | Godot mic drift |
|---|---|---|---|---|
| Loopback, 2 min, 19 events | 4 – 33 ms (mean 17) | 84 – 94 ms (mean 89) | not recorded | +0.2 ms/min |
| Loopback, 40 s, 6 events | 6 – 31 ms | 81 – 89 ms (mean 85) | 22 – 30 ms (mean 26) | — |
| Real mic, 2 min, 19 events | −7 – 23 ms (mean 6) | 108 – 120 ms (mean 113) | not recorded | −1.4 ms/min |
| Real mic, 40 s, 6 events | −6 – 40 ms | 126 – 135 ms (mean 130) | 44 – 53 ms (mean 48) | — |

- Two more 2-minute loopback runs gave Godot mic means of 91.4 and 87.9 ms.
- `AudioServer.get_output_latency()` reported about 25 ms on the loopback sink and 35 ms on the laptop speakers. On loopback, the ffmpeg mic saw the beep 26 ms after the event.
- Godot mic minus ffmpeg mic: about 59 ms on loopback and about 82 ms on the real mic.
- Video lagged events by up to 45 ms with no drift.
- After `playtest finalize` on the 40-second real-mic run (offsets derived from wall-clock pts: video +0.068 s, ffmpeg mic −1.149 s), the mic was 22–30 ms and the video 5–26 ms after each event. [measured](../../spikes/tug-99/results/finalize-alignment.txt)

### ffmpeg mic in the same process as x11grab

`ffmpeg -f x11grab … -f pulse -i default -copyts` into one `screen.mkv`. The recorder from TUG-98 ran with a 1 kHz beep played through `paplay` every 3 s, either on loopback (a PipeWire null sink monitor as the mic) or through the laptop speakers into the laptop's analog mic. Lag is the time the beep was heard minus the moment `paplay` was called, so it includes paplay's own start-up. [measured](../recorder.md#measured)

| Run | Beeps heard | Lag |
|---|---|---|
| Loopback, 60 s (`tools/record_check.sh 60`) | 19 / 19 | 20 – 25 ms, no trend |
| Loopback, 30 s | 9 / 9 | 13 – 24 ms |
| Real mic, 120 s (`tools/record_check.sh --real 120`, 2026-10-27) | 39 / 39 | 14 – 21 ms, drift −0.8 ms/min |

- In the muxed file the audio stream's `start_time` was 39–58 ms after the video's in three runs. Each stream carries its own wall-clock pts. [measured](../recorder.md#measured)

## Facts about the tools

- **Mix-rate mismatch causes mic drift.** At Godot's default 44.1 kHz mix rate with a 48 kHz PipeWire mic, mic latency grew by about 137 ms/min (109 ms at 3 s, 368 ms at 115 s). The WAV length was still correct, because the delay builds up in the input buffer. [README](../../spikes/tug-95/README.md#findings)
- `AudioServer.get_input_mix_rate()` returns the mix rate, not the device rate, so Godot can't detect the mismatch. [README](../../spikes/tug-95/README.md#findings)
- `x11grab` can't capture native Wayland windows. The spike runs Godot with `--display-driver x11`. [README](../../spikes/tug-95/README.md#limits)
- A recorder that stops on `NOTIFICATION_WM_CLOSE_REQUEST` writes a complete bundle when the window is closed early. The check passed after a close at about 13 s. [README](../../spikes/tug-95/README.md#how-it-works)
- Stopping ffmpeg by writing `q` to its stdin finalises the file. Killing the process leaves it truncated. [README](../../spikes/tug-95/README.md#how-it-works)
- Godot's Movie Maker mode doesn't write MP4. [FINDINGS](../../spikes/tug-93/FINDINGS.md#implications-for-other-issues)
- `mic.wav` (stereo, 16-bit, 48 kHz) is about 11.5 MB/min. [README](../../spikes/tug-95/README.md#limits)
- ffmpeg 9.0.2's `adelay` misreads fractional seconds: `delays=0.5s` delayed 0.5 ms and `22.5s` 22.5 ms (the output grew by that much), while `9s` and `500` (ms) delayed correctly. [measured](../../spikes/tug-99/results/adelay.txt)
- **ffmpeg keeps recording after its parent dies.** When Godot was killed with SIGKILL, the ffmpeg it started with `OS.execute_with_pipe` was still running 4 s later. EOF on its stdin pipe doesn't stop it. [measured](../recorder.md#measured)
- **SIGTERM finalises the file.** An orphaned ffmpeg sent SIGTERM exited, and `ffprobe` then reported a container duration, which it hadn't before. [measured](../recorder.md#measured)
- **Run args from a plugin.** If you set `editor/run/main_run_args` and call `EditorInterface.play_main_scene()` in the same frame, the game launches without the new args. Waiting for `ProjectSettings.settings_changed` before playing passes them. The editor launched the game with `--wid` (game embedding), and x11grab of the game's window still captured the game view. Godot 4.7.2, editor on Wayland. [measured](../recorder.md#measured)
- **The editor's Stop button gives the game no chance to stop recording.** The recorder's stop code didn't run and the bundle was left incomplete. [measured](../recorder.md#measured) [README](../../spikes/tug-95/README.md#limits)

## Open questions

- Capture on Windows (`gdigrab` / `ddagrab`) and macOS (`avfoundation`). Not tested.
- Real-mic latency on other hardware (USB mics, headsets). Only one laptop has been measured.
