# Spike: screen + mic capture in sync (TUG-95)

**Result: works.** A 2-minute recording keeps video, mic audio and telemetry within ±100 ms of each other, with no measurable drift. This holds only if Godot's mix rate matches the mic's rate (see [Findings](#findings)).

## How it works

`session_recorder.gd` owns one **session clock**: seconds since `start()`, read from `Time.get_ticks_usec()`.

| Stream | Capture | How it lands on the session clock |
|---|---|---|
| Telemetry | `log_event()` → `events.jsonl` | `t` is read straight from the session clock |
| Video | External `ffmpeg -f x11grab -window_id <godot window>`, launched with `OS.execute_with_pipe` | x11grab stamps every frame with wall-clock time, and `-copyts` keeps those stamps in `screen.mkv`. `session.json` stores `t0_unix`, the wall time at session start, so session time = frame pts − `t0_unix` |
| Mic | `AudioStreamMicrophone` → muted `Mic` bus → `AudioEffectRecord` → `mic.wav` | The first sample is at `audio_start`, the session time when recording was switched on |

The recorder stops ffmpeg by writing `q` to its stdin. Killing the process would leave a truncated file. The recorder also stops itself when the window is closed (`NOTIFICATION_WM_CLOSE_REQUEST`), so ending a session early still gives a complete bundle.

## Running it

```sh
./run_spike.sh 120          # loopback: no mic or speakers needed
./run_spike.sh 120 --real   # real default mic: turn the speakers up so the mic hears the beeps
```

The test window closes itself after `SECONDS` (default 120), and you can close it earlier. The test scene "dies" at irregular intervals. Each death logs an event, flashes the screen white for 100 ms and plays a 1 kHz beep. `tools/check_sync.py` finds each flash and beep, puts them on the session clock and compares them with the logged deaths.

In loopback mode the script creates a PipeWire null sink (`pt_loop`) and points Godot's output at it and its mic at `pt_loop.monitor`, so the beep travels through the full mic input path.

## Results

These are loopback runs on CachyOS (Wayland, XWayland, PipeWire 1.6.9), Godot 4.7.2, ffmpeg 9.0.2, RTX 5060, at 30 fps.

Final 2-minute run, 19 deaths:

| | mean | min | max | drift |
|---|---|---|---|---|
| Video − event | 16.9 ms | 4.0 | 33.2 | +1.2 ms/min |
| Mic − event | 88.7 ms | 84.2 | 93.9 | +0.2 ms/min |

Two earlier 2-minute runs gave similar numbers: mic mean 91.4 and 87.9 ms, max 96.5 ms.

The 88 ms mic figure is a loopback **round trip**. A parallel `ffmpeg -f pulse` capture of the sink showed about 25 ms of Godot output latency, which matches `AudioServer.get_output_latency()`. That leaves about **62 ms of mic input latency**, and that's what a real mic adds, plus about 1 ms of air per 30 cm.

## Findings

1. **The mix rate must match the mic's rate, or the mic drifts.** At Godot's default 44.1 kHz with a 48 kHz PipeWire mic, mic latency grew by **~137 ms/min**: 109 ms at 3 s, 368 ms at 115 s. The WAV still has the right length, because the delay builds up in the input buffer, not in the sample count. So you can't fix it afterwards by rescaling. `AudioServer.get_input_mix_rate()` reports the mix rate rather than the device's rate, so Godot can't detect the mismatch. The spike pins `audio/driver/mix_rate=48000` in `project.godot`.
2. **The mic lags by a steady ~60 ms on loopback.** It varies by only ±5 ms, so TUG-98 can subtract a fixed offset. On loopback that is optional, but the one real-mic run was ~120 ms late (see below), so plan for it.
3. **Video is good as it is.** It is 0–45 ms late, which is frame quantisation at 30 fps plus the 1–2 frames before a rendered frame is presented. There is no drift.
4. **Movie Maker mode is not needed.** The external ffmpeg process plus wall-clock stamps is enough.

## Limits and follow-ups for TUG-98

- **This works on X11/XWayland only.** x11grab can't see native Wayland windows, so the spike launches Godot with `--display-driver x11`. Windows would need `gdigrab -i title=<window>` or `ddagrab`, and macOS would need `avfoundation`. Neither is tested. Native Wayland would need the PipeWire screencast portal, which shows a permission prompt.
- **The 48 kHz pin is a guess about the user's device.** A 44.1 kHz USB mic would drift the other way. There are two ways to make this robust:
  - **(a)** Read the device's rate (for example `pactl list sources`) and set the mix rate to match. In Godot 4.7 the mix rate can only be changed by restarting.
  - **(b)** Record the mic in the same ffmpeg process (`-f pulse` / `-f dshow` / `-f avfoundation`). ffmpeg stamps audio with wall-clock time minus device latency, so video and audio share one clock, there's no input-buffer drift, and you get one muxed file. **I'd go with (b)** if the plugin doesn't need the audio inside Godot.
- **`mic.wav` is big:** stereo 16-bit at 48 kHz is about 11.5 MB/min, so about 170 MB for a 15-minute session. Downmix to mono and encode (Opus/AAC) when the session stops.
- **Real-mic check (human):** run `./run_spike.sh 120 --real` with the speakers on. One accidental 30-second run on laptop speakers and a laptop mic had the mic **~120 ms** late on its 3 clean beeps, which is **over budget**. Room noise also produced false "beeps". So the real input path is slower than the loopback suggests, and a single run isn't a reliable measurement. Both fixes above would help: (a) subtracting a calibrated constant, or (b) ffmpeg's latency-corrected stamps. Repeat the run in a quiet room before deciding.
