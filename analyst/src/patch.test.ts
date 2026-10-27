// Seam: patch() at the HTTP edge, against a fake Meta API that replays canned replies and a
// real git repo whose game project sits in a subfolder. meta.ts keeps the first fake server it
// sees, so this and analyse.test.ts need a fresh module per file: `bun run test` (--isolate).
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const tmp = mkdtempSync(join(tmpdir(), "patch-"));
let replies: unknown[] = [];
let seen: unknown[] = [];

const server = Bun.serve({
	port: 0,
	async fetch(req) {
		if (new URL(req.url).pathname !== "/v1/responses") return new Response("not found", { status: 404 });
		seen.push(await req.json());
		return Response.json(replies.shift());
	},
});

// meta.ts reads these at import, so set them first and import dynamically.
process.env.META_API_BASE = `http://localhost:${server.port}/v1`;
process.env.META_MODEL_API_KEY = "test-key";
process.env.PLAYTEST_SPEND_LEDGER = join(tmp, "spend.jsonl");
process.env.PLAYTEST_SPEND_CAP_USD = "100";
const { patch } = await import("./patch.ts");
const { run } = await import("./finalize.ts");

const repo = join(tmp, "repo");
const root = join(repo, "game");
const TRES = `[gd_resource type="Resource" script_class="PlayerTuning" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/player_tuning.gd" id="1"]

[resource]
script = ExtResource("1")
jump_height = 2.0
coyote_time = 0.05
`;
const GD = "class_name PlayerTuning extends Resource\n## Metres.\n@export var jump_height := 2.0\n@export var coyote_time := 0.05\n";

const finding = (id: string, summary: string) => ({
	id, t_start: 1, t_end: 2, category: "difficulty", reaction: null, severity: "high", zone: "spikes", summary,
	evidence: { quotes: [], telemetry: [], visual: "" }, suggested_fix: "", highlight: null,
});
const usage = { input_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0, latency_s: 0 };
const REPORT = {
	schema: 1, session_id: "s1", created_at: "2026-10-27T00:00:00Z", model: "muse-wonder-1.0", config: "test",
	findings: [finding("f1", "The player can't clear the spike gap."), finding("f2", "Late jumps off ledges fail.")], usage,
};

const JUMP = "--- a/tuning/player.tres\n+++ b/tuning/player.tres\n@@ -7,2 +7,2 @@\n-jump_height = 2.0\n+jump_height = 3.0\n coyote_time = 0.05\n";
const COYOTE = "--- a/tuning/player.tres\n+++ b/tuning/player.tres\n@@ -7,2 +7,2 @@\n jump_height = 2.0\n-coyote_time = 0.05\n+coyote_time = 0.15\n";
/** Its context line doesn't match the file, so git apply rejects it. */
const STALE = "--- a/tuning/player.tres\n+++ b/tuning/player.tres\n@@ -7,2 +7,2 @@\n-jump_height = 9.0\n+jump_height = 3.0\n coyote_time = 0.05\n";
/** Applies, but to the read-only script rather than the file it claims. */
const SCRIPT = "--- a/scripts/player_tuning.gd\n+++ b/scripts/player_tuning.gd\n@@ -2,3 +2,3 @@\n ## Metres.\n-@export var jump_height := 2.0\n+@export var jump_height := 3.0\n @export var coyote_time := 0.05\n";

const p = (finding_id: string, diff: string) => ({ finding_id, file: "tuning/player.tres", diff, rationale: "r", summary: `fix ${finding_id}` });
/** A canned /v1/responses reply proposing `patches`, billed 10k in / 1k out on muse-spark-1.3 = $0.01675. */
const reply = (...patches: ReturnType<typeof p>[]) => ({
	id: "resp_1", object: "response", status: "completed", model: "muse-spark-1.3",
	output: [{ type: "message", id: "msg_1", role: "assistant", status: "completed", content: [{ type: "output_text", text: JSON.stringify({ patches }), annotations: [] }] }],
	usage: { input_tokens: 10000, input_tokens_details: { cached_tokens: 0 }, output_tokens: 1000, output_tokens_details: { reasoning_tokens: 0 }, total_tokens: 11000 },
});

const reportPath = join(tmp, "report.json");
let dir: string;

beforeAll(async () => {
	mkdirSync(join(root, "tuning"), { recursive: true });
	mkdirSync(join(root, "scripts"));
	await Bun.write(join(root, "playtest.json"), JSON.stringify({ patch_allow: ["tuning/*.tres"] }));
	await Bun.write(join(root, "tuning/player.tres"), TRES);
	await Bun.write(join(root, "scripts/player_tuning.gd"), GD);
	await Bun.write(reportPath, JSON.stringify(REPORT));
	await run(["git", "-C", repo, "init", "-q"]);
});
afterAll(() => server.stop(true));

let n = 0;
beforeEach(() => {
	dir = join(tmp, `session-${++n}`);
	mkdirSync(dir);
	seen = [];
});

const saved = async () => (await Bun.file(join(dir, "patches.json")).json()).patches;

test("a patch that applies is kept, though the project is a subfolder of the repo", async () => {
	replies = [reply(p("f1", JUMP))];
	const result = await patch(dir, reportPath, root);

	expect(await saved()).toEqual([{ id: "p1", ...p("f1", JUMP) }]);
	expect(result.usage).toMatchObject({ input_tokens: 10000, output_tokens: 1000, cost_usd: 0.01675 });
	// The model may only name allowlisted files; the script the .tres uses comes along read-only.
	const sent = JSON.stringify(seen[0]);
	expect(sent).toContain('"file":{"type":"string","enum":["tuning/player.tres"]}');
	expect(sent).toContain("File scripts/player_tuning.gd (read-only)");
});

test("only the first patch for a finding is kept", async () => {
	replies = [reply(p("f1", JUMP), p("f1", COYOTE))];
	await patch(dir, reportPath, root);

	expect(await saved()).toEqual([{ id: "p1", ...p("f1", JUMP) }]);
});

test("a rejected patch is retried once with git's error, and results come back in finding order", async () => {
	replies = [reply(p("f1", STALE), p("f2", COYOTE)), reply(p("f1", JUMP))];
	const result = await patch(dir, reportPath, root);

	expect(await saved()).toEqual([{ id: "p1", ...p("f1", JUMP) }, { id: "p2", ...p("f2", COYOTE) }]);
	expect(result.usage).toMatchObject({ input_tokens: 20000, output_tokens: 2000, cost_usd: 0.0335 });
	const retry = JSON.stringify(seen[1]);
	expect(retry).toContain("Finding f1, tuning/player.tres");
	expect(retry).toContain("git apply said: error: patch failed: game/tuning/player.tres:7");
});

test("a patch that touches a file other than the one it names is dropped after its retry", async () => {
	replies = [reply(p("f1", SCRIPT)), reply(p("f1", SCRIPT))];
	await patch(dir, reportPath, root);

	expect(await saved()).toEqual([]);
	expect(seen).toHaveLength(2);
	expect(JSON.stringify(seen[1])).toContain("The diff touches scripts/player_tuning.gd; it must change only tuning/player.tres.");
});
