# Wiki rules

This folder is the project's shared knowledge base: facts we have established about the APIs, tools and platforms the plugin depends on. Agents write it, any agent can read it, and it builds up over time so nobody has to re-derive a fact from scratch. The pattern comes from [Karpathy's LLM wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

## Facts only

A page holds only claims that have a source:

- **Documented:** a vendor doc, spec or changelog says so. Link the exact page.
- **Measured:** we ran it and recorded the result. Link the result file or the spike write-up, and state the conditions (input, settings, versions, number of runs).

Don't add hypotheses, recommendations, plans or anecdotes. Decisions and plans belong in spike write-ups and issues. Their *evidence* belongs here. If something is unknown, say so as an open question, without a guess.

When a measurement contradicts the docs, record both, side by side, each with its source.

## Layout

| File | What it holds |
|---|---|
| `index.md` | One line per page, by category. Read this first. |
| `log.md` | Append-only history of ingests and lint passes. |
| `<topic>.md` | One page per topic (an API, a tool, a platform behaviour), named in kebab-case. Not one page per spike: spikes are sources. |

Raw sources stay where they are (`spikes/*/`, vendor docs) and are never edited from here.

Each page starts with:

```markdown
---
title: <Topic>
updated: YYYY-MM-DD
sources:
  - <repo path or URL>
---
```

Then the facts, each followed by its source as a link: `[docs](https://…)`, `[measured](../../spikes/tug-93/results/run-native-None.json)`. Put tables where numbers compare. End with `## Open questions` if there are any. Link related pages with relative links.

## Operations

**Ingest** (after a spike, a run or reading new docs):
1. Read the source.
2. Update the existing topic pages it touches, or create a new one. Fix any claim it supersedes, and don't leave stale numbers behind.
3. Update `index.md`.
4. Append to `log.md`: `## [YYYY-MM-DD] ingest | <source>` and one line per page touched.

**Query:** read `index.md`, then the pages it points to. Cite the wiki page in your answer. If the wiki lacks the fact, find it at the source and ingest it.

**Lint** (when asked, or when a page looks stale): check for claims without a source, contradictions between pages, pages missing from the index, and broken source links. Log it as `## [YYYY-MM-DD] lint`.
