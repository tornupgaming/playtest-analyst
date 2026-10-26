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

## [2026-10-26] ingest | docs/recorder.md, tools/record_check.sh (TUG-98 recorder runs)
- capture-sync.md: added the in-process ffmpeg mic on loopback (60 s and 30 s runs, 13–25 ms including paplay start-up), ffmpeg orphaned by SIGKILL of Godot, SIGTERM finalising the file, run args from a plugin needing `settings_changed`, and the editor's Stop button leaving bundles incomplete. Narrowed the in-process mic open question to real mics and runs over 60 s.
