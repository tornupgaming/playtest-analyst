// Scores one session's report against the planted-friction ground truth (DECISIONS.md §6).
// Pure: the plant windows come from the session's own telemetry, so the key holds no timestamps.
import type { Finding, GroundTruth, Plant, Report, TelemetryEvent } from "./schema.ts";

export type Strictness = "category" | "zone" | "any";
export type Options = {
	/** Seconds added either side of each interval spent in a plant's zone. */
	padS: number;
	strict: Strictness;
	/** The session's profile. "clean" has no plants, so every unexcused finding is a false positive. */
	profile: string | null;
};
export type Window = [start: number, end: number];

export type Score = {
	session_id: string;
	profile: string | null;
	hits: { plant: number; finding: string }[];
	/** Later findings on an already-hit plant. Not false positives. */
	duplicates: { plant: number; finding: string }[];
	/** Plant ids. */
	misses: number[];
	/** Findings in a known_unplanned zone that hit no plant. Not false positives. */
	excused: string[];
	false_positives: string[];
	/** null when there are no plants to find. */
	recall: number | null;
	/** null when there are no findings to judge. */
	precision: number | null;
};

/** `fork_left` belongs to zone `fork`. */
const inZone = (id: string, zone: string) => id === zone || id.startsWith(`${zone}_`);

/** Merged, padded intervals the player spent in `zone`. An interval with no exit runs to the last event. */
export function windows(events: TelemetryEvent[], zone: string, padS: number): Window[] {
	const open = new Map<string, number>();
	const spans: Window[] = [];
	for (const e of events) {
		const id = e.data.zone;
		if (typeof id !== "string" || !inZone(id, zone)) continue;
		const start = open.get(id);
		if (e.type === "zone_enter" && start === undefined) open.set(id, e.t);
		else if (e.type === "zone_exit" && start !== undefined) {
			spans.push([start, e.t]);
			open.delete(id);
		}
	}
	const lastT = events.at(-1)?.t ?? 0;
	for (const start of open.values()) spans.push([start, lastT]);

	const merged: Window[] = [];
	for (const [start, end] of spans.sort((a, b) => a[0] - b[0])) {
		const last = merged.at(-1);
		if (last && start - padS <= last[1]) last[1] = Math.max(last[1], end + padS);
		else merged.push([start - padS, end + padS]);
	}
	return merged;
}

/** Seconds the finding shares with the windows, or null if it touches none. */
function overlap(f: Finding, wins: Window[]): number | null {
	const parts = wins.map(([s, e]) => Math.min(e, f.t_end) - Math.max(s, f.t_start)).filter((x) => x >= 0);
	return parts.length ? parts.reduce((a, b) => a + b) : null;
}

function passes(f: Finding, p: Plant, strict: Strictness) {
	if (strict === "any") return true;
	if (f.category !== p.category) return false;
	return strict === "category" || (f.zone !== null && inZone(f.zone, p.zone));
}

export function ratios(c: { hits: number; misses: number; duplicates: number; false_positives: number }) {
	const found = c.hits + c.duplicates + c.false_positives;
	return {
		recall: c.hits + c.misses ? c.hits / (c.hits + c.misses) : null,
		precision: found ? (c.hits + c.duplicates) / found : null,
	};
}

export function score(report: Report, gt: GroundTruth, events: TelemetryEvent[], opts: Partial<Options> = {}): Score {
	const { padS = 10, strict = "category", profile = null } = opts;
	const plants = profile === "clean" ? [] : gt.plants;
	const wins = new Map(plants.map((p) => [p.id, windows(events, p.zone, padS)]));
	const excusedZones = new Set(gt.known_unplanned.map((u) => u.zone));

	const hits: Score["hits"] = [];
	const duplicates: Score["duplicates"] = [];
	const excused: string[] = [];
	const false_positives: string[] = [];

	for (const f of report.findings) {
		let best: { plant: number; size: number } | undefined;
		for (const p of plants) {
			const size = passes(f, p, strict) ? overlap(f, wins.get(p.id) ?? []) : null;
			if (size !== null && (!best || size > best.size)) best = { plant: p.id, size };
		}
		if (best) (hits.some((h) => h.plant === best.plant) ? duplicates : hits).push({ plant: best.plant, finding: f.id });
		else if (f.zone !== null && excusedZones.has(f.zone)) excused.push(f.id);
		else false_positives.push(f.id);
	}

	const misses = plants.filter((p) => !hits.some((h) => h.plant === p.id)).map((p) => p.id);
	return {
		session_id: report.session_id,
		profile,
		hits,
		duplicates,
		misses,
		excused,
		false_positives,
		...ratios({ hits: hits.length, misses: misses.length, duplicates: duplicates.length, false_positives: false_positives.length }),
	};
}
