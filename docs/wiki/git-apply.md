---
title: git apply on overlapping patches
updated: 2026-10-27
sources:
  - https://git-scm.com/docs/git-apply
  - spikes/tug-107/README.md
  - spikes/tug-108/README.md
---

# git apply on overlapping patches

How `git apply` treats several patches, each made against the same base, when they change neighbouring lines of one file, as `playtest patch` produces for `level/tuning.tres`.

## Documented

| Fact | Source |
|---|---|
| `-C<n>`: "Ensure at least `<n>` lines of surrounding context match before and after each change. When fewer lines of surrounding context exist they all must match. By default no context is ever ignored." | [docs](https://git-scm.com/docs/git-apply) |
| `--check`: "see if the patch is applicable to the current working tree and/or the index file and detects errors". `--numstat`: the number of added and deleted lines and the pathname per file. Both turn off "apply". | [docs](https://git-scm.com/docs/git-apply) |

## Measured

git 2.56.0 on Linux, five single-hunk patches with 3 lines of context, each made against the same 14-line `.tres`, changing lines 7, 9–10, 11, 12 and 13. [measured](../../spikes/tug-107/README.md)

| Applied in order with | Result |
|---|---|
| each alone, `git apply --check` | all pass |
| plain `git apply` | 2 of 5 apply; the other 3 fail with "patch failed", because their context includes a line an earlier patch changed |
| `git apply -C0` | all 5 apply, with "Context reduced to (0/0) to apply fragment at …" on stderr |

- `git apply --check --numstat -z` together exit 0 and print `added\tdeleted\tpath\0` for an applicable patch. Input that isn't a patch exits 128 with "No valid patches in input". A diff missing its last line exits 128 with "corrupt patch at <stdin>:N". [measured](../../spikes/tug-107/README.md)

## Reverting one of them

Measured on the same five patches, committed one by one after `git apply -C0`. [measured](../../spikes/tug-108/README.md)

| Revert p2 (lines 9–10) with p1 and p3 (line 11) committed after it | Result |
|---|---|
| `git revert --no-edit <p2 commit>` | exit 1, "CONFLICT (content): Merge conflict in level/tuning.tres" |
| `git diff <c>^ <c>`, then `git apply -R -C0 --index` | applies; lines 9–10 back to the base, p1's and p3's lines kept |
