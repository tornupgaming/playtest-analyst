# TUG-109 real check: cross-build comparison

Synthetic sessions rebuilt with `tools/make_synthetic.sh` on 26 Oct, analysed with config `v0` (`muse-wonder-1.0`).

| Run | Command (from `analyst/`) | Result | Cost |
|---|---|---|---|
| Build N−1 | `bun src/cli.ts analyse ../sessions/synthetic/planted-voice` | 6 findings, one per plant | $0.351 |
| Patched build | `… analyse ../sessions/synthetic/clean-voice --previous ../sessions/synthetic/planted-voice/report.json` | 0 findings: **6 resolved · 0 new · 0 persisting** | $0.069 |
| Same build again | `… analyse ../sessions/synthetic/planted-novoice --previous ../sessions/synthetic/planted-voice/report.json` | 6 findings, each matched to the right previous id: **0 resolved · 0 new · 6 persisting** | $0.314 |

Each run made one call with no retries.

Files:
- `planted-voice.report.json`: build N−1.
- `clean-voice.vs-planted.report.json`, `banner-clean.png`: the patched build in the viewer, 1920x1080.
- `planted-novoice.vs-planted.report.json`, `chips-persisting.png`: the persisting chips on the cards.
- `clean-voice.vs-planted.request.json`: the compare-mode request as sent. `file_id` has expired.

Screenshots: `bun src/cli.ts serve <session> --port N`, then
`google-chrome-stable --headless=new --disable-gpu --hide-scrollbars --window-size=1920,1080 --virtual-time-budget=5000 --screenshot=out.png http://127.0.0.1:N/`.
