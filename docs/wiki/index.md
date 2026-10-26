# Wiki index

Facts established so far, each with a source. Rules: [CLAUDE.md](CLAUDE.md). History: [log.md](log.md).

## Meta Model API
- [Muse Wonder video input](muse-wonder-video.md): formats, limits and price from the docs; measured timestamp accuracy, tokens per frame, cost and latency for a 10-minute clip at several fps, for a 40-second session through `playtest analyse`, and for the synthetic sessions through `playtest sweep`, with repeats.
- [SAM 3.1 segmentation](sam-3-1.md): `sam-3.1` request and response shape, mask encoding, per-image price and limits from the docs; measured latency and which noun phrases matched on four level frames.
- [Meta ASR](meta-asr.md): `muse-voice-transcribe-1.0` limits (10 min, 32 MB, WAV), modes, request shape and measured timestamp accuracy.

## Capture
- [Screen, mic and telemetry sync](capture-sync.md): measured offsets and drift for Godot + ffmpeg x11grab on Linux, Godot vs ffmpeg mic lag on a real mic, and the mix-rate drift; alignment after `playtest finalize`; an ffmpeg `adelay` pitfall.
- [Synthetic sessions](synthetic-sessions.md): measured speed and determinism of scripted SubViewport capture, Piper TTS on Python 3.14.
