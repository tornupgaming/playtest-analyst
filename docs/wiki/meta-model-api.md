---
title: Meta Model API keys
updated: 2026-10-28
sources:
  - docs/recorder.md (Before testers arrive)
---

# Meta Model API keys

Checking a Meta Model API key without running a model. For the models themselves, see [Muse Wonder](muse-wonder-video.md), [Muse Spark](muse-spark.md), [SAM 3.1](sam-3-1.md) and [ASR](meta-asr.md).

## Measured

`GET https://api.meta.ai/v1/models` with `Authorization: Bearer <key>`, curl 8.23, 28 Oct 2026, one run each. [measured](../recorder.md#before-testers-arrive)

| Key | HTTP status | Body |
|---|---|---|
| Our `META_MODEL_API_KEY` | 200 | `{"object":"list","data":[…]}` listing `muse-wonder-1.0`, `sam-3.1`, `muse-spark-1.3`, `muse-spark-1.3-contributor`, `muse-spark-1.2`, `muse-spark-1.2-contributor`, `muse-spark-1.1`, `muse-voice-transcribe-1.0`, `muse-image-1.0` |
| `bogus` | 401 | |

The call returns no `usage` and runs no model.

## Open questions

- Whether the pricing docs say anything about `GET /v1/models`; they list prices per token and per SAM image only (see the model pages).
