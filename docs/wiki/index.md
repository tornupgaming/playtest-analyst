# Wiki index

Facts established so far, each with a source. Rules: [CLAUDE.md](CLAUDE.md). History: [log.md](log.md).

## Meta Model API
- [Muse Wonder video input](muse-wonder-video.md): formats, limits and price from the docs; measured timestamp accuracy, tokens per frame, cost and latency for a 10-minute clip at several fps.
- [Meta ASR](meta-asr.md): `muse-voice-transcribe-1.0` limits (10 min, 32 MB, WAV), modes, request shape and measured timestamp accuracy.

## Capture
- [Screen, mic and telemetry sync](capture-sync.md): measured offsets and drift for Godot + ffmpeg x11grab on Linux, Godot vs ffmpeg mic lag on a real mic, the mix-rate drift, the in-process ffmpeg mic on loopback, and how ffmpeg and the editor behave when a recording game dies.
