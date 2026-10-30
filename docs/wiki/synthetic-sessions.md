---
title: Synthetic sessions (scripted capture and TTS)
updated: 2026-10-26
sources:
  - ../../sample_game/tools/make_synthetic.sh
  - ../../sample_game/tools/synth.gd
---

Measured on 2026-10-26 with `sample_game/tools/make_synthetic.sh` (TUG-120): Godot 4.7.2, Vulkan Forward+ on an NVIDIA GeForce RTX 5060 Laptop GPU, CachyOS Linux, Python 3.14.8. One run per profile.

## Godot SubViewport capture

| Run | Game time | Frames (1280x720, 30 fps game time) | Wall time |
|---|---|---|---|
| clean | 63.1 s | 1894 | 22 s |

The frames were piped as raw RGBA to `ffmpeg -c:v libx264 -preset veryfast -crf 20` with `OS.execute_with_pipe`, at `--fixed-fps 60` and 120 physics ticks per second. The planted run and the clean run each finished at the same session time (190.45 s and 63.11 s) headless (`--headless --no-video`) and rendered, and logged the same deaths at the same times. [measured](../../sample_game/tools/synth.gd)

## Piper TTS

- `pip install piper-tts` in a venv works on Python 3.14.8, and `PiperVoice.load` + `synthesize` run. [measured](../../sample_game/tools/synth_bundle.py)
- The `en_US-lessac-medium` voice outputs 22050 Hz mono. [measured](../../sample_game/tools/synth_bundle.py)
- On the mixed `mic.wav`, ffmpeg `silencedetect` (−40 dB, 0.6 s) put each line's speech onset 0.04–0.24 s after the time the line was placed. That is Piper's leading silence. 21 lines. [measured](../../sample_game/tools/make_synthetic.sh)
