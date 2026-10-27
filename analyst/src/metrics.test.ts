// Seam: metrics(events), the before/after numbers in demo shot 11.
import { expect, test } from "bun:test";
import { metrics } from "./metrics.ts";
import type { TelemetryEvent } from "./schema.ts";

const ev = (t: number, type: string, data: Record<string, unknown> = {}): TelemetryEvent => ({ t, type, player_pos: null, data });

test("counts deaths by cause, retries, finish time and time per zone", () => {
	const events = [
		ev(1, "zone_enter", { zone: "start" }),
		ev(5, "zone_exit", { zone: "start" }),
		ev(5, "zone_enter", { zone: "spikes" }),
		ev(8, "death", { cause: "spikes" }),
		ev(9, "retry"),
		ev(12, "death"),
		ev(13, "retry"),
		ev(20, "zone_exit", { zone: "spikes" }),
		ev(20, "zone_enter", { zone: "exit" }),
		// A second enter without an exit doesn't restart the zone's clock.
		ev(22, "zone_enter", { zone: "exit" }),
		ev(25, "objective_update", { text: "Course complete!" }),
	];

	// "exit" is never left, so it runs to the session's end at 30 s.
	expect(metrics(events, { endT: 30 })).toEqual({
		deaths: 2,
		deaths_by_cause: { spikes: 1, unknown: 1 },
		retries: 2,
		time_to_complete: 25,
		time_per_zone: { start: 4, spikes: 15, exit: 10 },
	});
});

test("a game without the test level's objective finishes at its own completion event, or never", () => {
	const events = [ev(3, "objective_update", { text: "Find the key" }), ev(12, "level_won"), ev(14, "level_won")];

	expect(metrics(events, { completeEvent: "level_won" }).time_to_complete).toBe(12);
	expect(metrics(events).time_to_complete).toBe(null);
});
