// `playtest patch`: a report's findings → minimal diffs to allowlisted project files (TUG-107).
// One /v1/responses call proposes a patch per fixable finding. Each diff is checked with
// `git apply --check` in the project; the ones that fail get one retry with the error.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import { type Responded, respond } from "./meta.ts";
import { type Finding, ModelPatch, type Patches, Report } from "./schema.ts";

export const PATCH_MODEL = "muse-spark-1.3";
const PROMPT = join(import.meta.dir, "../prompts/patch.md");

/** playtest.json at the project root: which files patches may touch (globs relative to the root). */
const ProjectConfig = z.object({ patch_allow: z.array(z.string()).min(1) });

type ProjectFile = { path: string; text: string; editable: boolean };

/** The allowlisted files, plus the scripts their .tres resources use, so the model sees each
 * export's type and doc comment. Scripts outside the allowlist are read-only context. */
async function projectFiles(root: string): Promise<ProjectFile[]> {
	const { patch_allow } = ProjectConfig.parse(await Bun.file(join(root, "playtest.json")).json());
	const editable = new Set(patch_allow.flatMap((g) => Array.from(new Bun.Glob(g).scanSync({ cwd: root }))));
	if (editable.size === 0) throw new Error(`playtest.json: patch_allow matches no files under ${root}`);
	const paths = [...editable].sort();
	for (const path of paths.filter((p) => p.endsWith(".tres"))) {
		const text = await Bun.file(join(root, path)).text();
		for (const [, script] of text.matchAll(/\[ext_resource type="Script"[^\]]*path="res:\/\/([^"]+)"/g)) {
			if (!paths.includes(script!)) paths.push(script!);
		}
	}
	return Promise.all(paths.map(async (path) => ({ path, text: await Bun.file(join(root, path)).text(), editable: editable.has(path) })));
}

/** Why `git apply` would reject the patch in `root`, or null when it applies and touches only `p.file`. */
async function rejection(root: string, p: ModelPatch): Promise<string | null> {
	const proc = Bun.spawn(["git", "-C", root, "apply", "--check", "--numstat", "-z"], { stdin: new Blob([p.diff]), stdout: "pipe", stderr: "pipe" });
	const [out, err, code] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited]);
	if (code !== 0) return err.trim();
	const touched = out.split("\0").filter(Boolean).map((line) => line.split("\t")[2]);
	return touched.length === 1 && touched[0] === p.file ? null : `The diff touches ${touched.join(", ") || "no files"}; it must change only ${p.file}.`;
}

function findingText(f: Finding): string {
	const { id, category, severity, zone, summary, evidence, suggested_fix } = f;
	return JSON.stringify({ id, category, severity, zone, summary, evidence, suggested_fix });
}

/** The model's patches, parsed against the schema that limits ids and files to the ones it was given. */
function parsePatches(response: Responded["response"], schema: z.ZodType<{ patches: ModelPatch[] }>): ModelPatch[] {
	if (response.status === "incomplete") throw new Error(`The response is incomplete (${response.incomplete_details?.reason ?? "no reason given"}).`);
	const text = response.output.flatMap((o) => (o.type === "message" ? o.content : [])).find((c) => c.type === "output_text")?.text;
	if (text === undefined) throw new Error("The response has no output_text.");
	// A diff must end with a newline or git calls it corrupt; models often drop the last one.
	return schema.parse(JSON.parse(text)).patches.map((p) => ({ ...p, diff: p.diff.endsWith("\n") ? p.diff : `${p.diff}\n` }));
}

export async function patch(dir: string, reportPath: string, root: string): Promise<Patches> {
	const report = Report.parse(await Bun.file(reportPath).json());
	const files = await projectFiles(root);
	const editable = files.filter((f) => f.editable).map((f) => f.path);
	const usage = { input_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0, latency_s: 0 };
	const accepted: ModelPatch[] = [];

	if (report.findings.length > 0) {
		const Output = z.object({
			patches: z.array(ModelPatch.extend({ finding_id: z.enum(report.findings.map((f) => f.id)), file: z.enum(editable) })),
		});
		const { $schema, ...schema } = z.toJSONSchema(Output);
		const text = (t: string) => ({ type: "input_text", text: t });
		const context = [
			text(await Bun.file(PROMPT).text()),
			text(`Findings, one JSON object per line:\n${report.findings.map(findingText).join("\n")}`),
			...files.map((f) => text(`File ${f.path} (${f.editable ? "editable" : "read-only"}):\n\`\`\`\n${f.text}\`\`\``)),
		];
		mkdirSync(join(dir, "analysis"), { recursive: true });

		let rejected: { patch: ModelPatch; error: string }[] = [];
		for (let attempt = 1; attempt <= 2; attempt++) {
			const retry = rejected.map(({ patch: p, error }) => `Finding ${p.finding_id}, ${p.file}:\n${p.diff}git apply said: ${error}`);
			const body = {
				model: PATCH_MODEL,
				input: [{ role: "user", content: attempt === 1 ? context : [...context, text(`Your patches below were rejected. Answer with corrected patches for these findings only, or none for a finding you can't patch.\n\n${retry.join("\n\n")}`)] }],
				text: { format: { type: "json_schema", name: "playtest_patches", strict: true, schema } },
				max_output_tokens: 16000,
			};
			await Bun.write(join(dir, `analysis/patch-request-${attempt}.json`), JSON.stringify(body, null, 2));
			const { response, costUsd, latencyS } = await respond(body, `patch ${report.session_id} attempt ${attempt}`);
			await Bun.write(join(dir, `analysis/patch-response-${attempt}.json`), JSON.stringify(response, null, 2));
			usage.input_tokens += response.usage?.input_tokens ?? 0;
			usage.cached_tokens += response.usage?.input_tokens_details?.cached_tokens ?? 0;
			usage.output_tokens += response.usage?.output_tokens ?? 0;
			usage.cost_usd += costUsd;
			usage.latency_s += latencyS;

			const retried = new Set(rejected.map((r) => r.patch.finding_id));
			const proposed = parsePatches(response, Output).filter((p) => attempt === 1 || retried.has(p.finding_id));
			rejected = [];
			for (const p of proposed) {
				const error = await rejection(root, p);
				if (error === null) accepted.push(p);
				else rejected.push({ patch: p, error });
			}
			for (const { patch: p, error } of rejected) console.error(`Attempt ${attempt}: patch for ${p.finding_id} rejected: ${error}`);
			if (rejected.length === 0) break;
		}
	}

	const patches: Patches = {
		schema: 1,
		session_id: report.session_id,
		created_at: new Date().toISOString(),
		model: PATCH_MODEL,
		patches: accepted
			.toSorted((a, b) => report.findings.findIndex((f) => f.id === a.finding_id) - report.findings.findIndex((f) => f.id === b.finding_id))
			.map((p, i) => ({ id: `p${i + 1}`, ...p })),
		usage: { ...usage, cost_usd: Math.round(usage.cost_usd * 1e6) / 1e6, latency_s: Math.round(usage.latency_s * 10) / 10 },
	};
	await Bun.write(join(dir, "patches.json"), JSON.stringify(patches, null, 2) + "\n");
	return patches;
}
