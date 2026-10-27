---
title: Running processes from GDScript
updated: 2026-10-27
sources:
  - spikes/tug-108/README.md
---

# Running processes from GDScript

How Godot's `OS.execute` and `OS.execute_with_pipe` pass arguments and output, on Linux.

## Measured

Godot 4.7.2, CachyOS. [measured](../../spikes/tug-108/README.md)

| Call | Arguments `"$(whoami)"`, `a "b" c` | Output with NUL bytes |
|---|---|---|
| `OS.execute(path, args, output, true)` | Run through a shell: `$(whoami)` printed the user name, `a "b" c` arrived as `a b c` | NULs replaced with U+FFFD, plus "Unicode parsing error … Unexpected NUL character" |
| `OS.execute_with_pipe(path, args, false)` | Passed unchanged | Raw bytes from `stdio.get_buffer()` |

## Open questions

- Whether `OS.execute` without an output array also goes through a shell.
