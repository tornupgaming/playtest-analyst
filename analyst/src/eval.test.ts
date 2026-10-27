import { describe, expect, test } from "bun:test";
import { readSession } from "./bundle.ts";
import { score } from "./eval.ts";
import { GroundTruth, Report } from "./schema.ts";
import type { Category, Finding, Plant, TelemetryEvent } from "./schema.ts";

// --- builders: small inline sessions -----------------------------------------

const plant = (id: number, category: Category, zone: string): Plant => ({
	id,
	category,
	zone,
	symptom: "",
	evidence: { telemetry: "", video: "", voice: "" },
	tunable: { path: "x", planted: 0, fixed: 1 },
});

const truth = (plants: Plant[], known_unplanned: GroundTruth["known_unplanned"] = []): GroundTruth => ({
	level: "test",
	profiles: {},
	frozen_at: null,
	plants,
	known_unplanned,
});

const finding = (id: string, t_start: number, t_end: number, category: Category, zone: string | null): Finding => ({
	id,
	t_start,
	t_end,
	category,
	reaction: null,
	severity: "medium",
	zone,
	summary: id,
	evidence: { quotes: [], telemetry: [], visual: "" },
	suggested_fix: "",
	highlight: null,
});

const report = (findings: Finding[]): Report => ({
	schema: 1,
	session_id: "s",
	created_at: "",
	model: "m",
	config: "c",
	findings,
	usage: { input_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0, latency_s: 0 },
});

const ev = (t: number, type: string, zone: string): TelemetryEvent => ({ t, type, player_pos: null, data: { zone } });
const enter = (t: number, zone: string) => ev(t, "zone_enter", zone);
const exit = (t: number, zone: string) => ev(t, "zone_exit", zone);

// ledge 10–40, fork 100–120 (with a fork_left detour inside), corridor 200–260.
const events = [
	enter(10, "ledge"),
	exit(40, "ledge"),
	enter(100, "fork"),
	exit(105, "fork"),
	enter(105.1, "fork_left"),
	exit(115, "fork_left"),
	enter(115.1, "fork"),
	exit(120, "fork"),
	enter(200, "corridor"),
	exit(260, "corridor"),
];
const gt = truth([plant(1, "difficulty", "ledge"), plant(5, "ui", "fork"), plant(6, "pacing", "corridor")]);

describe("score", () => {
	test("a finding inside a plant's zone time with the right category is a hit; a plant with no such finding is a miss", () => {
		const r = report([finding("a", 15, 35, "difficulty", "ledge"), finding("b", 101, 118, "ui", "fork")]);
		const s = score(r, gt, events);
		expect(s.hits).toEqual([
			{ plant: 1, finding: "a" },
			{ plant: 5, finding: "b" },
		]);
		expect(s.misses).toEqual([6]);
		expect(s.false_positives).toEqual([]);
		expect(s.recall).toBeCloseTo(2 / 3);
		expect(s.precision).toBe(1);
	});

	test("a later finding on an already-hit plant is a duplicate, not a false positive", () => {
		const r = report([finding("a", 15, 25, "difficulty", "ledge"), finding("b", 28, 38, "difficulty", "ledge")]);
		const s = score(r, gt, events);
		expect(s.hits).toEqual([{ plant: 1, finding: "a" }]);
		expect(s.duplicates).toEqual([{ plant: 1, finding: "b" }]);
		expect(s.false_positives).toEqual([]);
		expect(s.precision).toBe(1);
	});

	test("a finding that matches no plant is a false positive and lowers precision", () => {
		const r = report([
			finding("a", 15, 35, "difficulty", "ledge"),
			finding("wrong-zone", 15, 35, "difficulty", "hall"),
			finding("wrong-time", 150, 170, "difficulty", "ledge"),
		]);
		const s = score(r, gt, events);
		expect(s.false_positives).toEqual(["wrong-zone", "wrong-time"]);
		expect(s.precision).toBeCloseTo(1 / 3);
	});

	test("a finding in a missed plant's time and zone with the wrong category is mislabelled: the plant stays a miss, and it is not a false positive", () => {
		const r = report([
			finding("a", 15, 35, "difficulty", "ledge"),
			finding("wrong-cat", 101, 118, "pacing", "fork"),
			finding("next-to-hit", 15, 35, "ui", "ledge"),
			finding("wrong-time", 150, 170, "difficulty", "ledge"),
		]);
		const s = score(r, gt, events);
		expect(s.hits).toEqual([{ plant: 1, finding: "a" }]);
		expect(s.mislabelled).toEqual([{ plant: 5, finding: "wrong-cat" }]);
		expect(s.misses).toEqual([5, 6]);
		expect(s.false_positives).toEqual(["next-to-hit", "wrong-time"]);
		expect(s.recall).toBeCloseTo(1 / 3);
		expect(s.precision).toBeCloseTo(1 / 3);
		expect(score(r, gt, events, { strict: "any" }).hits).toEqual([
			{ plant: 1, finding: "a" },
			{ plant: 5, finding: "wrong-cat" },
		]);
	});

	test("a finding in a known_unplanned zone is excused, not a false positive", () => {
		const withKnown = truth(gt.plants, [{ zone: "plaza", description: "", evidence: "" }]);
		const r = report([finding("camera", 50, 60, "bug", "plaza"), finding("other", 50, 60, "bug", "hall")]);
		const s = score(r, withKnown, events);
		expect(s.excused).toEqual(["camera"]);
		expect(s.false_positives).toEqual(["other"]);
		expect(s.precision).toBe(0);
	});

	test("time in fork_left counts as time in zone fork", () => {
		const deadEndOnly = [enter(105.1, "fork_left"), exit(115, "fork_left")];
		const inDeadEnd = report([finding("a", 108, 112, "ui", "fork_left")]);
		const elsewhere = report([finding("b", 130, 140, "ui", "fork_left")]);
		expect(score(inDeadEnd, gt, deadEndOnly, { padS: 0 }).hits).toEqual([{ plant: 5, finding: "a" }]);
		expect(score(inDeadEnd, gt, deadEndOnly, { padS: 0, strict: "zone" }).hits).toEqual([{ plant: 5, finding: "a" }]);
		expect(score(elsewhere, gt, deadEndOnly, { padS: 0 }).false_positives).toEqual(["b"]);
	});

	test("the pad widens a plant's window by padS each side", () => {
		const r = report([finding("a", 45, 50, "difficulty", "ledge")]);
		expect(score(r, gt, events, { padS: 10 }).hits).toEqual([{ plant: 1, finding: "a" }]);
		expect(score(r, gt, events, { padS: 2 }).false_positives).toEqual(["a"]);
	});

	test("a zone with no exit runs to the end of the session", () => {
		const open = [enter(10, "ledge"), ev(90, "death", "ledge")];
		const r = report([finding("a", 130, 145, "difficulty", "ledge")]);
		expect(score(r, gt, open, { padS: 0, endT: 160 }).hits).toEqual([{ plant: 1, finding: "a" }]);
		expect(score(r, gt, open, { padS: 0, endT: 120 }).false_positives).toEqual(["a"]);
	});

	test("strictness: category needs the category, zone also needs finding.zone, any needs only time; a named zone must always match", () => {
		const wrongCat = report([finding("a", 15, 35, "ui", "ledge")]);
		const wrongZone = report([finding("b", 15, 35, "difficulty", "hall")]);
		const nullZone = report([finding("c", 15, 35, "difficulty", null)]);
		expect(score(wrongCat, gt, events, { strict: "category" }).hits).toEqual([]);
		expect(score(wrongCat, gt, events, { strict: "any" }).hits).toEqual([{ plant: 1, finding: "a" }]);
		expect(score(wrongZone, gt, events, { strict: "category" }).hits).toEqual([]);
		expect(score(wrongZone, gt, events, { strict: "any" }).hits).toEqual([]);
		expect(score(nullZone, gt, events, { strict: "category" }).hits).toEqual([{ plant: 1, finding: "c" }]);
		expect(score(wrongZone, gt, events, { strict: "zone" }).hits).toEqual([]);
		expect(score(nullZone, gt, events, { strict: "zone" }).hits).toEqual([]);
	});

	test("a finding overlapping two plants goes to the one with the larger overlap", () => {
		// ledge ends 40, fork starts 100; with pad 30 their windows are [-20,70] and [70,150] and touch.
		const r = report([finding("a", 60, 100, "difficulty", null)]);
		const both = truth([plant(1, "difficulty", "ledge"), plant(2, "difficulty", "fork")]);
		const s = score(r, both, events, { padS: 30, strict: "any" });
		expect(s.hits).toEqual([{ plant: 2, finding: "a" }]);
		expect(s.misses).toEqual([1]);
	});

	test("clean profile: no plants, so recall is null and every unexcused finding is a false positive", () => {
		const r = report([finding("a", 15, 35, "difficulty", "ledge"), finding("b", 101, 118, "ui", "fork")]);
		const s = score(r, gt, events, { profile: "clean" });
		expect(s.hits).toEqual([]);
		expect(s.misses).toEqual([]);
		expect(s.false_positives).toEqual(["a", "b"]);
		expect(s.recall).toBeNull();
		expect(s.precision).toBe(0);
	});

	test("the mini fixture session scores five of six plants, with the camera-clip bug as a false positive", async () => {
		const dir = `${import.meta.dir}/../fixtures/session-mini`;
		const session = await readSession(dir);
		const fixtureReport = Report.parse(await Bun.file(`${dir}/report.json`).json());
		const key = GroundTruth.parse(await Bun.file(`${import.meta.dir}/../../eval/ground_truth.json`).json());
		const s = score(fixtureReport, key, session.events, { profile: session.meta.profile });
		expect(s.hits.map((h) => `${h.plant}:${h.finding}`)).toEqual(["1:f1", "2:f2", "3:f3", "4:f4", "5:f5"]);
		expect(s.misses).toEqual([6]);
		expect(s.false_positives).toEqual(["f6"]);
		expect(s.recall).toBeCloseTo(5 / 6);
		expect(s.precision).toBeCloseTo(5 / 6);
	});
});
