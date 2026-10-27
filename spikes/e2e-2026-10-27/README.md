# End-to-end run of the merged `overnight` branch (27 Oct, early morning)

One pass of the whole pipeline on the synthetic sessions (TUG-120), after every overnight branch had merged. Logs: [e2e.log](e2e.log) (first pass) and [e2e2.log](e2e2.log) (patch and compare re-run after the fix below).

| Step | Result | Cost |
|---|---|---|
| `analyse planted-voice` (v0, with SAM) | 6 findings, 4 of 5 highlights annotated, 2 SAM misses (HUD text, the small button) | $0.39, 145 s model |
| `eval planted-voice` | recall 0.67, precision 1.00: 4 hits, 2 found with the wrong category (plaza as confusion, fork as ui), 0 false positives | — |
| `patch planted-voice` (Muse Spark) | 6 patches to `level/tuning.tres`, one per finding, corridor included. All apply in order with `git apply -C0`, and `tools/check.sh` prints OK on the result | $0.07, 49 s |
| `analyse clean-voice --previous planted --patches` | 0 findings: 6 resolved · 0 new · 0 persisting | $0.05 |
| `metrics planted-voice clean-voice` | deaths 6→0, retries 6→0, time 3:10→1:03 | — |

**Bug found and fixed.** On the first pass `patch` failed with "response incomplete (max_output_tokens)". Muse Spark's reasoning ran past 16,000 tokens on a six-finding report, where the fixture report had fit. The limit is now 32,000, as in `analyse`.

The viewer screenshot ([viewer-planted.png](viewer-planted.png)) shows a black video panel only because headless Chrome captured it before the first frame painted. `/media/video.mp4` serves H.264 with 206 range responses.
