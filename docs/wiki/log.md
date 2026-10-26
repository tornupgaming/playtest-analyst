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
