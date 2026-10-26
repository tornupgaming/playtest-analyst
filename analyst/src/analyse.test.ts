// Seam (b): analyse() at the HTTP edge, against a fake Meta API that replays canned replies.
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";
import { cpSync, existsSync, mkdirSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const tmp = mkdtempSync(join(tmpdir(), "analyse-"));
const seen = { asr: [] as unknown[], responses: [] as unknown[], sam: [] as unknown[], uploads: [] as string[] };
let replies: unknown[] = [];
/** Real sam-3.1 replies from the TUG-118 probe: one 66×55 px match at (607, 328) on a 1280×720 frame, and no match. */
const SAM_MATCH = await Bun.file(join(import.meta.dir, "../fixtures/sam/match.json")).json();
const SAM_EMPTY = await Bun.file(join(import.meta.dir, "../fixtures/sam/empty.json")).json();
let samReply: unknown = SAM_EMPTY;
let asrStatus = 200;

const server = Bun.serve({
	port: 0,
	async fetch(req) {
		const path = new URL(req.url).pathname;
		if (path === "/v1/files") {
			seen.uploads.push(((await req.formData()).get("file") as File).name);
			return Response.json({ id: "file-123", object: "file", bytes: 1, created_at: 0, filename: "upload.mp4", purpose: "user_data" });
		}
		if (path === "/v1/asr/transcribe") {
			if (asrStatus !== 200) return new Response("rate limited", { status: asrStatus });
			seen.asr.push(JSON.parse(await ((await req.formData()).get("request") as Blob).text()));
			return Response.json({
				transcript: "where do I go go.",
				turns: [
					{ turnId: 0, startMs: 1200, endMs: 2000, transcript: "where do I go" },
					{ turnId: 1, startMs: 2080, endMs: 2080, transcript: "go." },
				],
			});
		}
		if (path === "/v1/responses") {
			const body = (await req.json()) as { model: string };
			if (body.model === "sam-3.1") {
				seen.sam.push(body);
				return Response.json(samReply);
			}
			seen.responses.push(body);
			return Response.json(replies.shift());
		}
		return new Response("not found", { status: 404 });
	},
});

// meta.ts reads these at import, so set them first and import dynamically.
process.env.META_API_BASE = `http://localhost:${server.port}/v1`;
process.env.META_MODEL_API_KEY = "test-key";
process.env.PLAYTEST_SPEND_LEDGER = join(tmp, "spend.jsonl");
process.env.PLAYTEST_SPEND_CAP_USD = "100";
const { analyse } = await import("./analyse.ts");
const { run } = await import("./finalize.ts");

const LATE = {
	t_start: 2.0, t_end: 2.8, category: "confusion", severity: "medium", zone: null,
	summary: "The player asks where to go.",
	evidence: { quotes: [{ t: 1.2, text: "where do I go" }], telemetry: ["input_idle 1.0 s at 1.5 s"], visual: "The player stands still." },
	suggested_fix: "Point the camera at the exit.",
	highlight: { t: 2.0, prompt: "the exit door" },
};
const EARLY = { ...LATE, t_start: 0.5, t_end: 1.0, category: "ui", summary: "The objective text is hard to read.", highlight: null };

/** A canned /v1/responses reply whose output text is `output`, billed 50k in / 5k out = $0.30. */
const reply = (output: string) => ({
	id: "resp_1", object: "response", status: "completed", model: "muse-wonder-1.0",
	output: [{ type: "message", id: "msg_1", role: "assistant", status: "completed", content: [{ type: "output_text", text: output, annotations: [] }] }],
	usage: { input_tokens: 50000, input_tokens_details: { cached_tokens: 0 }, output_tokens: 5000, output_tokens_details: { reasoning_tokens: 4000 }, total_tokens: 55000 },
});
const VALID = reply(JSON.stringify({ findings: [LATE, EARLY] }));
const INVALID = reply(JSON.stringify({ findings: [{ ...LATE, t_start: "soon" }] }));

const raw = join(tmp, "raw");
const prompt = join(tmp, "prompt.md");
const config = { name: "test", prompt, fps: 1, include_transcript: true, include_telemetry: true, video_audio: false };
let dir: string;

beforeAll(async () => {
	mkdirSync(raw);
	await run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=s=1280x720:r=10:d=3", "-c:v", "libx264", join(raw, "screen.mkv")]);
	await run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "sine=f=440:d=3", join(raw, "mic.wav")]);
	await Bun.write(join(raw, "session.json"), JSON.stringify({
		schema: 1, id: "fake", started_at: "2026-10-26T00:00:00Z", t0_unix: 0, duration: 3, game: "Test", build: null, tester: null, profile: null,
		capture: { video: "screen.mkv", video_start: 0, audio: "mic.wav", audio_start: 0 },
	}));
	await Bun.write(join(raw, "events.jsonl"), '{"t": 1.5, "type": "input_idle", "data": {"duration": 1.0}}\n');
	await Bun.write(prompt, "Find the friction.");
});
afterAll(() => server.stop(true));

let n = 0;
beforeEach(() => {
	dir = join(tmp, `session-${++n}`);
	cpSync(raw, dir, { recursive: true });
	seen.asr = [];
	seen.responses = [];
	seen.sam = [];
	seen.uploads = [];
	asrStatus = 200;
	samReply = SAM_EMPTY;
});

test("writes report.json with findings in time order, ids, and the call's cost", async () => {
	replies = [VALID];
	await analyse(dir, config);

	const report = await Bun.file(join(dir, "report.json")).json();
	expect(report.findings).toEqual([{ id: "f1", ...EARLY }, { id: "f2", ...LATE }]);
	expect(report.usage).toEqual({ input_tokens: 50000, cached_tokens: 0, output_tokens: 5000, cost_usd: 0.3, latency_s: expect.any(Number) });
	expect(report.config).toBe("test");
	// The model got the uploaded video and the transcript on the session clock, minus the zero-length fragment.
	expect(seen.asr).toEqual([{ model: "muse-voice-transcribe-1.0", audioEncoding: "WAV", mode: "ENDPOINTING" }]);
	expect(await Bun.file(join(dir, "analysis/transcript.json")).json()).toEqual([{ start: 1.2, end: 2, text: "where do I go" }]);
	const sent = JSON.stringify(seen.responses[0]);
	expect(sent).toContain('{"type":"input_video","file_id":"file-123","fps":1}');
	expect(sent).toContain("[1.2–2.0s] where do I go");
	expect(sent).toContain("[1.5s] input_idle duration=1");
});

test("invalid output is retried once with the validation error, and both calls are billed", async () => {
	replies = [INVALID, VALID];
	await analyse(dir, config);

	const report = await Bun.file(join(dir, "report.json")).json();
	expect(report.findings.map((f: { id: string }) => f.id)).toEqual(["f1", "f2"]);
	expect(report.usage).toMatchObject({ input_tokens: 100000, output_tokens: 10000, cost_usd: 0.6 });
	expect(seen.responses).toHaveLength(2);
	expect(JSON.stringify(seen.responses[1])).toContain("findings[0].t_start");
});

test("invalid output twice fails without writing a report", async () => {
	replies = [INVALID, INVALID];
	await expect(analyse(dir, config)).rejects.toThrow("invalid twice");
	expect(seen.responses).toHaveLength(2);
	expect(existsSync(join(dir, "report.json"))).toBe(false);
});

test("when ASR fails, the video is sent with its audio track and no transcript", async () => {
	replies = [VALID];
	asrStatus = 429;
	await analyse(dir, config);

	expect(seen.uploads).toEqual(["upload.mp4", "video.mp4"]);
	const sent = JSON.stringify(seen.responses[0]);
	expect(sent).not.toContain("Think-aloud transcript");
	expect(sent).toContain("[1.5s] input_idle duration=1");
	expect((await Bun.file(join(dir, "report.json")).json()).findings).toHaveLength(2);
});

/** The output PNG's pixels and the bounding box of the pixels that differ from the plain frame at `t`. */
async function drawnRegion(png: string, t: number) {
	const rgb = async (args: string[], out: string) => {
		await run(["ffmpeg", "-y", "-loglevel", "error", ...args, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", out]);
		return Bun.file(out).bytes();
	};
	const [drawn, plain] = await Promise.all([rgb(["-i", png], join(tmp, "drawn.rgb")), rgb(["-ss", String(t), "-i", join(dir, "video.mp4")], join(tmp, "plain.rgb"))]);
	const box = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
	for (let i = 0; i < drawn.length; i += 3) {
		if (drawn[i] === plain[i] && drawn[i + 1] === plain[i + 1] && drawn[i + 2] === plain[i + 2]) continue;
		const x = (i / 3) % 1280, y = Math.floor(i / 3 / 1280);
		box.left = Math.min(box.left, x); box.top = Math.min(box.top, y); box.right = Math.max(box.right, x); box.bottom = Math.max(box.bottom, y);
	}
	return { bytes: drawn.length, box };
}

test("a finding with a highlight gets an annotated key frame drawn around SAM's match", async () => {
	replies = [VALID];
	samReply = SAM_MATCH;
	await analyse(dir, config);

	const report = await Bun.file(join(dir, "report.json")).json();
	expect(report.findings).toEqual([{ id: "f1", ...EARLY }, { id: "f2", ...LATE, annotated_frame: "analysis/frames/f2.png" }]);
	// SAM got the highlight's phrase and the key frame, once: f1 has no highlight.
	expect(seen.sam).toHaveLength(1);
	const sent = JSON.stringify(seen.sam[0]);
	expect(sent).toContain('{"type":"input_text","text":"the exit door"}');
	expect(sent).toContain('"image_url":"data:image/png;base64,');
	// A 1280×720 frame, drawn on only around the match's box (607–673, 328–383), not elsewhere.
	const { bytes, box } = await drawnRegion(join(dir, "analysis/frames/f2.png"), 2.0);
	expect(bytes).toBe(1280 * 720 * 3);
	expect(box.left).toBeGreaterThanOrEqual(597);
	expect(box.top).toBeGreaterThanOrEqual(318);
	expect(box.right).toBeLessThanOrEqual(683);
	expect(box.bottom).toBeLessThanOrEqual(393);
	expect(box.right - box.left).toBeGreaterThanOrEqual(60);
	expect(box.bottom - box.top).toBeGreaterThanOrEqual(50);
});

test("when SAM finds nothing, the finding has no annotated frame, the reason is logged, and the report is still written", async () => {
	replies = [VALID];
	const logged: string[] = [];
	const consoleError = console.error;
	console.error = (line: string) => logged.push(line);
	await analyse(dir, config).finally(() => (console.error = consoleError));

	const report = await Bun.file(join(dir, "report.json")).json();
	expect(report.findings).toEqual([{ id: "f1", ...EARLY }, { id: "f2", ...LATE }]);
	expect(existsSync(join(dir, "analysis/frames/f2.png"))).toBe(false);
	expect(logged).toEqual(['f2: no annotated frame: SAM found no match for "the exit door".']);
});
