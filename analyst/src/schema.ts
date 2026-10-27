// The data contracts. Everything that crosses a file boundary is parsed with one of these.
// See DECISIONS.md §2 for the bundle layout and the session clock.
import { z } from "zod";

// --- Session bundle ---------------------------------------------------------

/** session.json, written by a recorder. Times are seconds on the session clock. */
export const SessionMeta = z.object({
	schema: z.literal(1),
	id: z.string(),
	/** ISO wall time when the session clock started. */
	started_at: z.string(),
	/** Unix wall time (s) at session t=0. Anchors streams stamped with wall-clock pts. */
	t0_unix: z.number(),
	duration: z.number(),
	game: z.string(),
	build: z.string().nullable(),
	tester: z.string().nullable(),
	/** Test-level tuning profile ("planted" | "clean"), null for a real game. */
	profile: z.string().nullable(),
	capture: z.object({
		/** Raw video file, relative to the bundle. */
		video: z.string(),
		/** Session time of the file's first frame. Omit to derive it from pts − t0_unix. */
		video_start: z.number().optional(),
		/** Raw mic file (may be the video file if muxed), or null for no mic. */
		audio: z.string().nullable(),
		audio_start: z.number().optional(),
	}),
});
export type SessionMeta = z.infer<typeof SessionMeta>;

/** One line of events.jsonl. Known types: death, retry, zone_enter, zone_exit, input_idle,
 * ui_open, ui_close, objective_update, plus any custom name. */
export const TelemetryEvent = z.object({
	t: z.number(),
	type: z.string(),
	player_pos: z.tuple([z.number(), z.number(), z.number()]).nullable().default(null),
	data: z.record(z.string(), z.unknown()).default({}),
});
export type TelemetryEvent = z.infer<typeof TelemetryEvent>;

/** One think-aloud turn in analysis/transcript.json (an array of these), on the session clock. */
export const TranscriptTurn = z.object({ start: z.number(), end: z.number(), text: z.string() });
export type TranscriptTurn = z.infer<typeof TranscriptTurn>;

// --- Report -----------------------------------------------------------------

/** What in the game caused the problem, i.e. what the developer would change. Scored by eval. */
export const Category = z.enum(["difficulty", "pacing", "ui", "bug"]);
export type Category = z.infer<typeof Category>;

/** How the player felt, from what they said and did. Reported, not scored (TUG-125). */
export const Reaction = z.enum(["confused", "frustrated", "bored", "surprised"]);
export type Reaction = z.infer<typeof Reaction>;

/** A finding as the model writes it. Every field is required (nullable instead of optional)
 * so the schema works as a strict json_schema output format. */
export const ModelFinding = z.object({
	t_start: z.number(),
	t_end: z.number(),
	category: Category,
	reaction: Reaction.nullable(),
	severity: z.enum(["low", "medium", "high"]),
	zone: z.string().nullable(),
	summary: z.string(),
	evidence: z.object({
		quotes: z.array(z.object({ t: z.number(), text: z.string() })),
		telemetry: z.array(z.string()),
		visual: z.string(),
	}),
	suggested_fix: z.string(),
	/** Key frame and 1–3 noun phrases for SAM to segment in it, best first, each saying how one
	 * element looks, e.g. ["the blue treasure chest", "the wooden chest"]. */
	highlight: z.object({ t: z.number(), prompts: z.array(z.string()).min(1).max(3) }).nullable(),
});
export type ModelFinding = z.infer<typeof ModelFinding>;

export const ModelOutput = z.object({ findings: z.array(ModelFinding) });

export const Finding = ModelFinding.extend({
	id: z.string(),
	/** Path relative to the bundle, added by the SAM step (TUG-104), with the phrasing that matched
	 * and the session time of the frame it was drawn on (TUG-123). */
	annotated_frame: z.string().optional(),
	annotated_prompt: z.string().optional(),
	annotated_t: z.number().optional(),
	/** Compare mode (TUG-109): the previous build's finding this one matches, or null if it is new. */
	previous_id: z.string().nullable().optional(),
});
export type Finding = z.infer<typeof Finding>;

export const Usage = z.object({
	input_tokens: z.number(),
	cached_tokens: z.number(),
	output_tokens: z.number(),
	cost_usd: z.number(),
	latency_s: z.number(),
});
export type Usage = z.infer<typeof Usage>;

export const Report = z.object({
	schema: z.literal(1),
	session_id: z.string(),
	created_at: z.string(),
	model: z.string(),
	/** Name of the analysis config that produced it (prompt variant, fps, …). */
	config: z.string(),
	findings: z.array(Finding),
	usage: Usage,
	/** Compare mode (TUG-109): the previous build's findings that no finding here matches are
	 * resolved. They carry their category and summary so a fully fixed build can still show them. */
	comparison: z
		.object({
			previous_session: z.string(),
			resolved: z.array(z.object({ id: z.string(), category: Category, summary: z.string() })),
			counts: z.object({ resolved: z.number(), new: z.number(), persisting: z.number() }),
		})
		.optional(),
});
export type Report = z.infer<typeof Report>;

// --- Patches (patches.json, written by `playtest patch`) --------------------

/** A patch as the model writes it: one minimal edit to one allowlisted file for one finding. */
export const ModelPatch = z.object({
	finding_id: z.string(),
	/** Path relative to the project root; the only file `diff` touches. */
	file: z.string(),
	/** Unified diff with `a/` and `b/` paths relative to the project root, as `git diff` writes it. */
	diff: z.string(),
	rationale: z.string(),
	/** Commit-message line; the dock commits the patch as `playtest-fix: <summary>`. */
	summary: z.string(),
});
export type ModelPatch = z.infer<typeof ModelPatch>;

/** Each diff passed `git apply --check` against the project tree it was made for. Patches to
 * neighbouring lines of one file overlap in context, so apply them with `git apply -C0`. */
export const Patches = z.object({
	schema: z.literal(1),
	session_id: z.string(),
	created_at: z.string(),
	model: z.string(),
	patches: z.array(ModelPatch.extend({ id: z.string() })),
	usage: Usage,
});
export type Patches = z.infer<typeof Patches>;

// --- Ground truth (eval/ground_truth.json) ----------------------------------

const Tunable = z.object({ path: z.string(), planted: z.unknown(), fixed: z.unknown() });

export const Plant = z.object({
	id: z.number(),
	category: Category,
	zone: z.string(),
	symptom: z.string(),
	evidence: z.object({ telemetry: z.string(), video: z.string(), voice: z.string() }),
	tunable: z.union([Tunable, z.array(Tunable)]),
});
export type Plant = z.infer<typeof Plant>;

export const GroundTruth = z.object({
	level: z.string(),
	profiles: z.record(z.string(), z.string()),
	frozen_at: z.string().nullable(),
	plants: z.array(Plant),
	known_unplanned: z.array(z.object({ zone: z.string(), description: z.string(), evidence: z.string() })),
});
export type GroundTruth = z.infer<typeof GroundTruth>;
