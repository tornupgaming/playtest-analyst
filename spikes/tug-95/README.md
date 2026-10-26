# Spike: screen + mic capture in sync (TUG-95)

**Result: video and telemetry sync works. Godot's mic path is too slow on real hardware; record the mic with ffmpeg instead.**

- Video lines up with telemetry to within 0–45 ms, with no drift.
- On a real mic, Godot's mic recording (`AudioEffectRecord`) lags the sound by about **80 ms more than ffmpeg's** (`-f pulse`) recording of the same mic. In this test that put it at 108–136 ms, which is **over the 100 ms budget**.
- ffmpeg's copy of the same mic stays within ~50 ms, and most of that is the time the test's own beep takes to play.

## How it works

`session_recorder.gd` owns one **session clock**: seconds since `start()`, read from `Time.get_ticks_usec()`.

| Stream | Capture | How it lands on the session clock |
|---|---|---|
| Telemetry | `log_event()` → `events.jsonl` | `t` is read straight from the session clock |
| Video | External `ffmpeg -f x11grab -window_id <godot window>`, launched with `OS.execute_with_pipe` | x11grab stamps every frame with wall-clock time, and `-copyts` keeps those stamps in `screen.mkv`. `session.json` stores `t0_unix`, the wall time at session start, so session time = frame pts − `t0_unix` |
| Mic (Godot) | `AudioStreamMicrophone` → muted `Mic` bus → `AudioEffectRecord` → `mic.wav` | The first sample is at `audio_start`, the session time when recording was switched on |
| Mic (ffmpeg reference) | `run_spike.sh` runs `ffmpeg -f pulse -i default -copyts` → `ref_mic.mka` | Like the video: ffmpeg stamps each packet with wall-clock time minus PulseAudio's reported latency |

The recorder stops ffmpeg by writing `q` to its stdin. Killing the process would leave a truncated file. The recorder also stops itself when the window is closed (`NOTIFICATION_WM_CLOSE_REQUEST`), so ending a session early still gives a complete bundle.

## Running it

```sh
./run_spike.sh 120          # loopback: no mic or speakers needed
./run_spike.sh 120 --real   # real default mic: turn the speakers up so the mic hears the beeps
```

The test window closes itself after `SECONDS` (default 120), and you can close it earlier. The test scene "dies" at irregular intervals. Each death logs an event, flashes the screen white for 100 ms and plays a 1 kHz beep.

`tools/check_sync.py` puts every flash and beep on the session clock and compares them with the logged deaths. It finds beeps by their energy at 1 kHz over 4 ms windows, and a beep must last 30 ms to count. Room noise and speech are often as loud as a quiet beep, so a plain volume threshold picks up false beeps. Pass or fail covers video and the Godot mic only. The ffmpeg mic column is for reference.

In loopback mode the script creates a PipeWire null sink (`pt_loop`) and points Godot's output at it and its mic at `pt_loop.monitor`, so the beep travels through the full mic input path.

## Results

All runs: CachyOS (Wayland, XWayland, PipeWire 1.6.9), Godot 4.7.2 at a 48 kHz mix rate, ffmpeg 9.0.2, RTX 5060, 30 fps video. All times are stream minus event time.

| Run | Video | Godot mic | ffmpeg mic | Godot mic drift |
|---|---|---|---|---|
| Loopback, 2 min, 19 deaths | 4 – 33 ms (mean 17) | 84 – 94 ms (mean 89) | not recorded | +0.2 ms/min |
| Loopback, 40 s, 6 deaths | 6 – 31 ms | 81 – 89 ms (mean 85) | 22 – 30 ms (mean 26) | — |
| Real mic, 2 min, 19 deaths (laptop speakers into laptop mic) | −7 – 23 ms (mean 6) | 108 – 120 ms (mean 113) | not recorded | −1.4 ms/min |
| Real mic, 40 s, 6 deaths (same hardware) | −6 – 40 ms | 126 – 135 ms (mean 130) | 44 – 53 ms (mean 48) | — |

Two more 2-minute loopback runs gave Godot mic means of 91.4 and 87.9 ms.

**How to read the mic columns.** Every mic number includes the time the beep takes to leave the speakers. Godot's output latency is about 25 ms on the loopback sink and 35 ms on the laptop speakers (`AudioServer.get_output_latency()`, which matches the loopback ffmpeg figure). A player's voice has no output stage, so the latency that matters is how far each mic path lags the sound reaching the mic:

| | Loopback | Real mic |
|---|---|---|
| ffmpeg mic − output latency (the sound reaching the mic) | ~0 ms | ~13 ms (DAC, speaker, air, ADC) |
| Godot mic − ffmpeg mic (Godot's extra lag) | ~59 ms | ~82 ms |

So speech recorded through Godot would land ~80 ms late. Speech recorded through ffmpeg would land on time, to within its PulseAudio latency estimate.

## Findings

1. **Godot's mic path adds a steady 60–80 ms**, and it varied between runs on the same hardware: 113 ms and 130 ms means. A fixed correction would need calibrating on each machine.
2. **ffmpeg's `-f pulse` stamps are close to true.** On loopback, ffmpeg saw the beep exactly one output latency after the event.
3. **The mix rate must match the mic's rate, or Godot's mic drifts.** At Godot's default 44.1 kHz with a 48 kHz PipeWire mic, Godot mic latency grew by **~137 ms/min**: 109 ms at 3 s, 368 ms at 115 s. The WAV still has the right length, because the delay builds up in the input buffer. `AudioServer.get_input_mix_rate()` reports the mix rate rather than the device's rate, so Godot can't detect the mismatch. The spike pins `audio/driver/mix_rate=48000` in `project.godot`.
4. **Video is good as it is.** It is 0–45 ms late, which is frame quantisation at 30 fps plus the 1–2 frames before a rendered frame is presented. There is no drift.
5. **Movie Maker mode is not needed.** The external ffmpeg process plus wall-clock stamps is enough.

## Recommendation for TUG-98

Record the mic in the **same ffmpeg process as the video**: `-f x11grab … -f pulse -i default`, on Windows `-f dshow`, on macOS `avfoundation`.

- Video and audio would both be stamped against the same wall clock.
- The mix-rate drift trap goes away.
- Godot's ~80 ms extra mic lag goes away.
- You get one muxed file.

The cost: Godot no longer has the audio. Nothing in the plan needs it there.

## Limits

- **X11/XWayland only.** x11grab can't see native Wayland windows, so the spike launches Godot with `--display-driver x11`. Windows (`gdigrab`/`ddagrab`, `dshow`) and macOS (`avfoundation`) are untested. Native Wayland would need the PipeWire screencast portal, which shows a permission prompt.
- **The ffmpeg mic has only been measured as a separate process over 40 s.** Running it inside the video's ffmpeg process, and over a full 2 minutes, hasn't been measured.
- **One machine, one mic.** Real-mic numbers are from laptop speakers into a laptop mic.
- **`mic.wav` is big:** stereo 16-bit at 48 kHz is about 11.5 MB/min. Encode it (Opus/AAC, mono) when the session stops.
