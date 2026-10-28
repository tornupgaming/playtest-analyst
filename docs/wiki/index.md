# Wiki index

Facts established so far, each with a source. Rules: [CLAUDE.md](CLAUDE.md). History: [log.md](log.md).

## Meta Model API
- [Meta Model API keys](meta-model-api.md): measured that `GET /v1/models` returns 200 for a good key and 401 for a bad one, without running a model.
- [Muse Wonder video input](muse-wonder-video.md): formats, limits and price from the docs; measured timestamp accuracy, tokens per frame, cost and latency for a 10-minute clip at several fps, for a 40-second session through `playtest analyse`, and for the synthetic sessions through `playtest sweep`, with repeats.
- [SAM 3.1 segmentation](sam-3-1.md): `sam-3.1` request and response shape, mask encoding, per-image price and limits from the docs; measured latency and which noun phrases matched on four level frames, and on key frames with several phrasings per finding (TUG-123).
- [Muse Spark text and code](muse-spark.md): Spark ids, standard vs contributor mode, prices, reasoning effort and strict `json_schema` rules from the docs; tokens, cost and latency of one `playtest patch` run on `muse-spark-1.3`.
- [Meta ASR](meta-asr.md): `muse-voice-transcribe-1.0` limits (10 min, 32 MB, WAV), modes, request shape and measured timestamp accuracy.
- [Hackathon API credits](hackathon-credits.md): the $150 Meta Model API credit terms (claim deadline, expiry, billing after credits run out, and where the rules and Credit Terms disagree on validity); partner credit offers for open-weights models.

## Capture
- [Screen, mic and telemetry sync](capture-sync.md): measured offsets and drift for Godot + ffmpeg x11grab on Linux, Godot vs ffmpeg mic lag on a real mic, the mix-rate drift, the in-process ffmpeg mic on loopback and a real mic, how ffmpeg and the editor behave when a recording game dies; alignment after `playtest finalize`; an ffmpeg `adelay` pitfall.
- [Synthetic sessions](synthetic-sessions.md): measured speed and determinism of scripted SubViewport capture, Piper TTS on Python 3.14.

## Tools
- [git apply on overlapping patches](git-apply.md): `-C<n>`, `--check`, `--numstat` from the docs; measured that patches to neighbouring lines of one file fail plain `git apply` in sequence and apply with `-C0`, and that `git revert` of one of them conflicts where `git apply -R -C0` does not.
- [Running processes from GDScript](godot-os-execute.md): `OS.execute` with output runs through a shell and mangles NULs; `OS.execute_with_pipe` passes arguments unchanged.
