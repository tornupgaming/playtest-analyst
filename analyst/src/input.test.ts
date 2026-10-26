// Seam (a), bundle → model input: transcript assembly and the telemetry timeline.
import { describe, expect, test } from "bun:test";
import { chunkStarts, sessionTurns, telemetryText, transcriptText } from "./input.ts";

describe("transcript assembly", () => {
	test("a session is cut into ASR chunks of at most 10 minutes", () => {
		expect(chunkStarts(40)).toEqual([0]);
		expect(chunkStarts(600)).toEqual([0]);
		expect(chunkStarts(1500.5)).toEqual([0, 600, 1200]);
	});

	test("turns are offset by their chunk's start and zero-length fragments dropped", () => {
		const turns = sessionTurns([
			{ start: 0, turns: [
				{ startMs: 89700, endMs: 92400, transcript: "Is this jump even possible?" },
				{ startMs: 92480, endMs: 92480, transcript: "possible?" },
			] },
			{ start: 600, turns: [{ startMs: 1250, endMs: 3900, transcript: " Where am I going? " }] },
		]);
		expect(turns).toEqual([
			{ start: 89.7, end: 92.4, text: "Is this jump even possible?" },
			{ start: 601.25, end: 603.9, text: "Where am I going?" },
		]);
		expect(transcriptText(turns)).toBe("[89.7–92.4s] Is this jump even possible?\n[601.3–603.9s] Where am I going?");
	});

	test("a silent session says so rather than sending nothing", () => {
		expect(transcriptText(sessionTurns([{ start: 0, turns: [] }]))).toBe("(no speech)");
	});
});

describe("telemetry timeline", () => {
	test("one line per event: time, type, then its data", () => {
		const text = telemetryText([
			{ t: 0, type: "objective_update", player_pos: null, data: { text: "Follow the path." } },
			{ t: 18.43, type: "death", player_pos: [1, 2, 3], data: { cause: "fall", zone: "ledge" } },
			{ t: 95, type: "input_idle", player_pos: null, data: { duration: 6.2 } },
			{ t: 96.04, type: "retry", player_pos: null, data: {} },
		]);
		expect(text).toBe([
			'[0.0s] objective_update text="Follow the path."',
			'[18.4s] death cause="fall" zone="ledge"',
			"[95.0s] input_idle duration=6.2",
			"[96.0s] retry",
		].join("\n"));
	});
});
