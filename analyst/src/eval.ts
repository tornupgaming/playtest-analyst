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
	/** Session end (session.json duration). Closes an interval the player never exited. */
	endT: number;
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
	/** Findings that would hit a missed plant if they named its category: found, wrong category.
	 * The plant stays a miss, and the finding is not a false positive. */
	mislabelled: { plant: number; finding: string }[];
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

/** Merged, padded intervals the player spent in `zone`. An interval with no exit runs to `endT`. */
export function windows(events: TelemetryEvent[], zone: string, padS: number, endT: number): Window[] {
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
	for (const start of open.values()) spans.push([start, endT]);

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
	// A finding that names its zone never counts for a plant in another zone, at any strictness:
	// otherwise the ±pad window credits a plaza finding to the hall's plant next door.
	if (f.zone !== null && !inZone(f.zone, p.zone)) return false;
	if (strict === "zone" && f.zone === null) return false;
	return strict === "any" || f.category === p.category;
}

export function ratios(c: { hits: number; misses: number; duplicates: number; false_positives: number }) {
	const found = c.hits + c.duplicates + c.false_positives;
	return {
		recall: c.hits + c.misses ? c.hits / (c.hits + c.misses) : null,
		precision: found ? (c.hits + c.duplicates) / found : null,
	};
}

/** Counts summed over several scores, with the recall and precision of the sum. */
export function totals(scores: Score[]) {
	const t = { hits: 0, misses: 0, duplicates: 0, false_positives: 0, mislabelled: 0 };
	for (const s of scores) for (const k of Object.keys(t) as (keyof typeof t)[]) t[k] += s[k].length;
	return { ...t, ...ratios(t) };
}

/** A table cell for a ratio, cost or mean: "n/a" when there was nothing to measure. */
export const num = (x: number | null, digits = 2) => (x === null ? "n/a" : x.toFixed(digits));

/** A report's finding as list text: "f2 [30.9–70.9 s] ui in plaza: summary". */
export function findingText(report: Report, id: string): string {
	const f = report.findings.find((f) => f.id === id)!;
	return `${id} [${f.t_start.toFixed(1)}–${f.t_end.toFixed(1)} s] ${f.category}${f.zone ? ` in ${f.zone}` : ""}: ${f.summary}`;
}

export function score(report: Report, gt: GroundTruth, events: TelemetryEvent[], opts: Partial<Options> = {}): Score {
	const { padS = 10, strict = "category", profile = null, endT = events.at(-1)?.t ?? 0 } = opts;
	const plants = profile === "clean" ? [] : gt.plants;
	const wins = new Map(plants.map((p) => [p.id, windows(events, p.zone, padS, endT)]));
	const excusedZones = new Set(gt.known_unplanned.map((u) => u.zone));

	const hits: Score["hits"] = [];
	const duplicates: Score["duplicates"] = [];
	const mislabelled: Score["mislabelled"] = [];
	const excused: string[] = [];
	const false_positives: string[] = [];

	/** The plant `f` shares most time with, among those it passes for. With `relabel`, as if it
	 * named each plant's own category. */
	const nearest = (f: Finding, among: Plant[], relabel = false) => {
		let best: { plant: number; size: number } | undefined;
		for (const p of among) {
			const size = passes(relabel ? { ...f, category: p.category } : f, p, strict) ? overlap(f, wins.get(p.id) ?? []) : null;
			if (size !== null && (!best || size > best.size)) best = { plant: p.id, size };
		}
		return best?.plant;
	};

	const unmatched: Finding[] = [];
	for (const f of report.findings) {
		const plant = nearest(f, plants);
		if (plant === undefined) unmatched.push(f);
		else (hits.some((h) => h.plant === plant) ? duplicates : hits).push({ plant, finding: f.id });
	}
	// Only a missed plant can be mislabelled: next to a hit plant, another category is another problem.
	const missed = plants.filter((p) => !hits.some((h) => h.plant === p.id));
	for (const f of unmatched) {
		const plant = nearest(f, missed, true);
		if (plant !== undefined) mislabelled.push({ plant, finding: f.id });
		else if (f.zone !== null && excusedZones.has(f.zone)) excused.push(f.id);
		else false_positives.push(f.id);
	}

	const misses = missed.map((p) => p.id);
	return {
		session_id: report.session_id,
		profile,
		hits,
		duplicates,
		mislabelled,
		misses,
		excused,
		false_positives,
		...ratios({ hits: hits.length, misses: misses.length, duplicates: duplicates.length, false_positives: false_positives.length }),
	};
}
