# TUG-107: first real `playtest patch` run

**Run (26 Oct 2026).** `level/tuning.tres` replaced by `eval/tuning_planted.tres` (uncommitted), then `bun analyst/src/cli.ts patch analyst/fixtures/session-mini --project .` with `playtest.json` = `{"patch_allow": ["level/tuning.tres", "level/*.gd"]}`. The model got the six findings of `analyst/fixtures/session-mini/report.json`, `level/level.gd`, `level/tuning.gd` and `level/tuning.tres`. Output: [`fixture-patches.json`](fixture-patches.json).

| | |
|---|---|
| Model | `muse-spark-1.3`, reasoning effort not set, strict `json_schema`, `max_output_tokens` 16000 |
| Calls | 1 (no diff failed `git apply --check`, so no retry) |
| Tokens | 8,957 in (0 cached) / 9,689 out, of which 8,773 reasoning (`output_tokens_details.reasoning_tokens`); `total_tokens` 18,646 = in + out |
| Cost | $0.0524 (ledger) |
| Latency | 30.9 s |

**Patches.** Five, all to `level/tuning.tres`, each one changed line (two for the beacon). f6 (camera clips into a wall) got none; the camera code isn't in the allowlist.

| Patch | Finding | Change |
|---|---|---|
| p1 | f1 ledge | `ledge_gap_width` 6.6 → 4.0 |
| p2 | f2 beacon | `marker_color` → `Color(0.2, 0.85, 1, 1)`, `marker_emission` 0.0 → 2.0 |
| p3 | f3 objective | `switch_prompt_text` → "Press the red switch on the balcony." |
| p4 | f4 enemy | `enemy_aggro_delay` 0.0 → 2.5 |
| p5 | f5 sign | `fork_arrow_points_to` "left" → "right" |

**Applying them in sequence** (git 2.56.0). On a scratch copy of the tree with the planted tuning committed:

- Each patch alone passes `git apply --check`.
- Plain `git apply` p1…p5 in order: p1 and p3 apply; p2, p4 and p5 fail ("patch failed"), because their 3-line context includes a line an earlier patch changed.
- `git apply -C0` p1…p5 in order: all apply ("Context reduced to (0/0)" for p3–p5, "(1/1)" for p2).
- With the patched `tuning.tres` copied over `eval/tuning_planted.tres`, `tools/check.sh` prints OK (planted: 525 built nodes, all seven zones, player on floor).

**`git apply` output used by the validator** (git 2.56.0). `git apply --check --numstat -z` exits 0 and prints `added\tdeleted\tpath\0` for an applicable patch (`1\t1\tlevel/tuning.tres\0` for a one-line change). Input that isn't a patch exits 128 with "error: No valid patches in input (allow with "--allow-empty")". A diff with its last line cut off exits 128 with "error: corrupt patch at <stdin>:13".
