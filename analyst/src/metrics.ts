// Play metrics for one session, for the before/after table in demo shot 11.
// Pure: everything comes from the session's own telemetry (docs/telemetry.md).
import type { TelemetryEvent } from "./schema.ts";

/** The objective the test level (level/level.gd) shows when the player reaches the exit. */
const COURSE_COMPLETE = "Course complete!";

export type Metrics = {
	deaths: number;
	/** `death` events by `data.cause` ("unknown" when it has none). */
	deaths_by_cause: Record<string, number>;
	retries: number;
	/** Session time the player finished, or null if they never did. */
	time_to_complete: number | null;
	/** Seconds in each zone id, from zone_enter/zone_exit pairs. `fork_left` is its own zone here. */
	time_per_zone: Record<string, number>;
};

export type Options = {
	/** An event type that marks completion, for games that don't emit the test level's objective. */
	completeEvent?: string;
	/** Session end (session.json duration). Closes a zone the player never exited. */
	endT?: number;
};

/** Counts only what the test level emits: `death` (with `cause`), `retry`, `zone_enter`/`zone_exit`
 * and `objective_update`. Completion is the "Course complete!" objective, else the first
 * `completeEvent`, else null. `events` must be in time order, as readSession returns them. */
export function metrics(events: TelemetryEvent[], opts: Options = {}): Metrics {
	const { completeEvent, endT = events.at(-1)?.t ?? 0 } = opts;
	const deaths_by_cause: Record<string, number> = {};
	const time_per_zone: Record<string, number> = {};
	const open = new Map<string, number>();
	const add = (zone: string, start: number, end: number) => (time_per_zone[zone] = (time_per_zone[zone] ?? 0) + end - start);
	let retries = 0;

	for (const e of events) {
		const zone = e.data.zone;
		if (e.type === "death") {
			const cause = typeof e.data.cause === "string" && e.data.cause ? e.data.cause : "unknown";
			deaths_by_cause[cause] = (deaths_by_cause[cause] ?? 0) + 1;
		} else if (e.type === "retry") retries++;
		else if (e.type === "zone_enter" && typeof zone === "string" && !open.has(zone)) open.set(zone, e.t);
		else if (e.type === "zone_exit" && typeof zone === "string" && open.has(zone)) {
			add(zone, open.get(zone)!, e.t);
			open.delete(zone);
		}
	}
	for (const [zone, start] of open) add(zone, start, endT);

	const complete =
		events.find((e) => e.type === "objective_update" && e.data.text === COURSE_COMPLETE) ??
		(completeEvent ? events.find((e) => e.type === completeEvent) : undefined);
	return {
		deaths: Object.values(deaths_by_cause).reduce((a, b) => a + b, 0),
		deaths_by_cause,
		retries,
		time_to_complete: complete?.t ?? null,
		time_per_zone,
	};
}
