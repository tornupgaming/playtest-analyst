# Wiki log

Append-only. Newest at the bottom. Entry format: `## [YYYY-MM-DD] <ingest|lint> | <source>`.

## [2026-10-26] ingest | spikes/tug-93 (FINDINGS.md, probe.py, results/*.json)
- Created muse-wonder-video.md. The measured rows come from results/*.json, which are newer than the "pending" rows in FINDINGS.md.
- Created meta-asr.md.

## [2026-10-26] ingest | spikes/tug-95/README.md
- Created capture-sync.md.

## [2026-10-26] ingest | spikes/tug-93 (results/run-native-0.2.json, results/asr-raw-endpointing.json, voice API docs)
- muse-wonder-video.md: added the fps 0.2 run (fps changes billed tokens, about 130 tokens per 720p frame, short visual events missed). Qualified the "visual within 2 s" claim to default fps or fps 1. Replaced the open question on whether fps changes billing.
- meta-asr.md: added documented limits (10 min, 32 MB, 16/24 kHz mono WAV), modes, turn fields and response formats. Added the zero-length repeat turns seen in the raw ENDPOINTING response. The raw file came from a manual curl with the same request as `probe.py transcribe`.

## [2026-10-26] ingest | spikes/tug-95/README.md (real-mic run, close-early fix)
- capture-sync.md: added the 30-second real-mic run (~120 ms mic lag, 3 clean beeps) and the recorder stopping on window close. Narrowed the real-mic open question.

## [2026-10-26] ingest | spikes/tug-95/README.md (real-mic runs with ffmpeg mic reference)
- capture-sync.md: replaced the single 30-second real-mic anecdote with two real-mic runs (2 min and 40 s) and an ffmpeg `-f pulse` reference column. Added the Godot-mic minus ffmpeg-mic gap (~59 ms on loopback, ~82 ms on the real mic). Updated the open questions.
- capture-sync.md: removed the unsourced claim that the mix rate only changes on restart. index.md: updated the capture-sync line.

## [2026-10-26] ingest | spikes/tug-94 (FINDINGS.md, probe.ts, results/), SAM docs pages
- Created sam-3-1.md.
- index.md: added sam-3-1.md.

## [2026-10-26] ingest | spikes/tug-99/results (first `playtest analyse` runs, finalize alignment, adelay)
- muse-wonder-video.md: added three 40-second `playtest analyse` runs (tokens, cost, latency) and that the strict schema with `anyOf` null and `max_output_tokens` 32000 are accepted. Added an open question on the output-token spread.
- meta-asr.md: added the TTS-on-real-mic ASR run (−0.22, −0.28 s, repeated words).
- capture-sync.md: added post-finalize alignment on the real-mic run and the `adelay` fractional-seconds behaviour.

## [2026-10-26] ingest | tools/make_synthetic.sh (TUG-120 synthetic runs)
- synthetic-sessions.md: new page. SubViewport capture speed at 720p30, headless vs rendered determinism, Piper on Python 3.14 and its output rate and onset lag. index.md: added the page.

## [2026-10-26] ingest | spikes/tug-104 (check.sh, results/run.txt)
- sam-3-1.md: added the key-frames-from-video run (matches as on PNG, except "the exit sign"; 4 calls in flight). Extended the JPEG open question.

## [2026-10-26] ingest | spikes/tug-107/README.md (first `playtest patch` run), Spark docs pages, git-apply man page
- Created muse-spark.md.
- Created git-apply.md.
- index.md: added both, and a Tools section.

## [2026-10-26] ingest | docs/recorder.md, tools/record_check.sh (TUG-98 recorder runs)
- capture-sync.md: added the in-process ffmpeg mic on loopback (60 s and 30 s runs, 13–25 ms including paplay start-up), ffmpeg orphaned by SIGKILL of Godot, SIGTERM finalising the file, run args from a plugin needing `settings_changed`, and the editor's Stop button leaving bundles incomplete. Narrowed the in-process mic open question to real mics and runs over 60 s.

## [2026-10-26] ingest | eval/sweeps/2026-10-26-synthetic (TUG-121 first sweep)
- muse-wonder-video.md: added tokens, cost and latency for 24 sweep runs on the 190 s and 63 s synthetic sessions, the input tokens added by telemetry and transcript, and run-to-run variation on identical input. index.md: updated the line.

## [2026-10-27] ingest | spikes/tug-108/README.md (patch dock runs)
- git-apply.md: added reverting one of five neighbouring-line patches (`git revert` conflicts, `git apply -R -C0` applies).
- Created godot-os-execute.md: `OS.execute` with output goes through a shell and replaces NULs; `OS.execute_with_pipe` doesn't.
- index.md: added godot-os-execute.md, extended the git-apply.md line.
