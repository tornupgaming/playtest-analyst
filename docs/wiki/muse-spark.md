---
title: Muse Spark text and code
updated: 2026-10-26
sources:
  - https://dev.meta.ai/docs/models
  - https://dev.meta.ai/docs/pricing-rate-limits
  - https://dev.meta.ai/docs/reasoning
  - https://dev.meta.ai/docs/structured-output
  - spikes/tug-107/README.md
---

# Muse Spark text and code

The Muse Spark models on the Meta Model API (`https://api.meta.ai/v1`), and what `muse-spark-1.3` did as the `playtest patch` model. For Muse Wonder, see [Muse Wonder video input](muse-wonder-video.md).

## Documented

| Fact | Source |
|---|---|
| Ids `muse-spark-1.3`, `muse-spark-1.2`, `muse-spark-1.1`, plus `-contributor` variants of 1.3 and 1.2. Input text, image, video, audio, PDF; output text; 1,048,576-token context. 1.3: "improved coding over 1.2"; audio input not fully supported (1.2 recommended for audio). | [docs](https://dev.meta.ai/docs/models) |
| Standard mode: content is not used to train Meta models. Contributor mode: content may be used to train future models, for a lower price. | [docs](https://dev.meta.ai/docs/models) |
| Price per 1M tokens, standard (1.1, 1.2, 1.3): $1.25 input, $0.15 cached, $4.25 output. Contributor (1.2, 1.3): $0.10, $0.002, $0.20. Muse Wonder for comparison: $4.00, $0.20, $20.00. | [docs](https://dev.meta.ai/docs/pricing-rate-limits) |
| Rate limits per team: 3,000 RPM and 4M TPM (standard); 150 RPM and 3M TPM (contributor). | [docs](https://dev.meta.ai/docs/pricing-rate-limits) |
| Reasoning effort on `/v1/responses`: `"reasoning": {"effort": …}`, levels `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. `none` returns HTTP 400 on Muse Wonder and Spark. `max` isn't available on `muse-spark-1.3-contributor`. Omitted: "the model still reasons at a model-determined level". Reasoning tokens are billed as output and count toward `max_output_tokens`; reported in `output_tokens_details.reasoning_tokens`. | [docs](https://dev.meta.ai/docs/reasoning) |
| Strict `json_schema` (`text.format.strict`): plain-object root, no `allOf`/`oneOf`, `anyOf` allowed below the root, `additionalProperties: false` and every key `required` on each object. Nesting ≤ 10, ≤ 1,000 enum values by default. | [docs](https://dev.meta.ai/docs/structured-output) |

## Measured

One `playtest patch` run on `muse-spark-1.3`: six findings and three project files (~9k input tokens), strict `json_schema` with string enums for finding ids and file paths, reasoning effort not set, `max_output_tokens` 16000. [measured](../../spikes/tug-107/README.md)

| Input tokens | Output tokens | Of which reasoning | Cost | Latency | Patches | Passed `git apply --check` first time |
|---|---|---|---|---|---|---|
| 8,957 | 9,689 | 8,773 | $0.0524 | 30.9 s | 5 of 6 findings | 5 of 5 |

- `usage.output_tokens` includes the reasoning tokens: `total_tokens` (18,646) = input + output. [measured](../../spikes/tug-107/README.md)
- The strict schema with `z.enum` string enums was accepted. [measured](../../spikes/tug-107/README.md)

## Open questions

- Output-token spread across runs, and how a set reasoning effort changes tokens and patch quality (one run so far).
