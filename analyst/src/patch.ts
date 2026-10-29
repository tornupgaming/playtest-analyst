// `playtest patch`: a report's findings → minimal diffs to allowlisted project files (TUG-107).
// One /v1/responses call proposes a patch per fixable finding. Each diff is checked with
// `git apply --check` in the project; the ones that fail get one retry with the error. An answer
// that doesn't match the schema gets one retry with the validation error, as in analyse.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import { readJson } from "./boundary.ts";
import { attempts, outputJson, type Responded } from "./meta.ts";
import { type Finding, ModelPatch, type Patches, Report } from "./schema.ts";

export const PATCH_MODEL = "muse-spark-1.3";
const PROMPT = join(import.meta.dir, "../prompts/patch.md");

/** playtest.json at the project root: which files patches may touch (globs relative to the root). */
const ProjectConfig = z.object({ patch_allow: z.array(z.string()).min(1) });

type ProjectFile = { path: string; text: string; editable: boolean };

/** The allowlisted files, plus the scripts their .tres resources use, so the model sees each
 * export's type and doc comment. Scripts outside the allowlist are read-only context. */
async function projectFiles(root: string): Promise<ProjectFile[]> {
	const { patch_allow } = await readJson(join(root, "playtest.json"), ProjectConfig);
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
	// git reports paths from the repository root; the project root may be a subfolder of it.
	const prefix = (await new Response(Bun.spawn(["git", "-C", root, "rev-parse", "--show-prefix"], { stdout: "pipe" }).stdout).text()).trim();
	const touched = out.split("\0").filter(Boolean).map((line) => line.split("\t")[2]!.replace(prefix, ""));
	return touched.length === 1 && touched[0] === p.file ? null : `The diff touches ${touched.join(", ") || "no files"}; it must change only ${p.file}.`;
}

function findingText(f: Finding): string {
	const { id, category, severity, zone, summary, evidence, suggested_fix } = f;
	return JSON.stringify({ id, category, severity, zone, summary, evidence, suggested_fix });
}

/** The model's patches, parsed against the schema that limits ids and files to the ones it was given. */
function parsePatches(response: Responded["response"], schema: z.ZodType<{ patches: ModelPatch[] }>): ModelPatch[] {
	// A diff must end with a newline or git calls it corrupt; models often drop the last one.
	return outputJson(response, schema).patches.map((p) => ({ ...p, diff: p.diff.endsWith("\n") ? p.diff : `${p.diff}\n` }));
}

export async function patch(dir: string, reportPath: string, root: string): Promise<Patches> {
	const report = await readJson(reportPath, Report);
	const files = await projectFiles(root);
	const editable = files.filter((f) => f.editable).map((f) => f.path);
	const calls = attempts(join(dir, "analysis/patch-"));
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

		/** What the second attempt is told, and which findings it may answer for (null: all of them). */
		let retry: { text: string; findings: Set<string> | null } | undefined;
		for (let attempt = 1; attempt <= 2; attempt++) {
			const body = {
				model: PATCH_MODEL,
				input: [{ role: "user", content: retry ? [...context, text(retry.text)] : context }],
				text: { format: { type: "json_schema", name: "playtest_patches", strict: true, schema } },
				// Spark reasons at length: a 6-finding report ran past 16000 (TUG-124 e2e).
				max_output_tokens: 32000,
			};
			const response = await calls.respond(body, attempt, `patch ${report.session_id} attempt ${attempt}`);
			let proposed: ModelPatch[];
			try {
				proposed = parsePatches(response, Output);
			} catch (err) {
				const error = (err as Error).message;
				console.error(`Attempt ${attempt}: the output doesn't match the schema:\n${error}`);
				// Invalid after a valid first answer keeps the patches that first answer gave.
				if (attempt === 2 && retry?.findings === null) throw new Error(`The model's output was invalid twice. Last error:\n${error}`);
				retry = { text: `Your answer was invalid:\n${error}\n\nAnswer again, with a patch for each finding you can fix.`, findings: null };
				continue;
			}
			const allowed = retry?.findings;
			const rejected: { patch: ModelPatch; error: string }[] = [];
			for (const p of proposed.filter((p) => !allowed || allowed.has(p.finding_id))) {
				// One patch per finding: a second one for the same finding would fail once the first is applied.
				if (accepted.some((a) => a.finding_id === p.finding_id)) continue;
				const error = await rejection(root, p);
				if (error === null) accepted.push(p);
				else rejected.push({ patch: p, error });
			}
			for (const { patch: p, error } of rejected) console.error(`Attempt ${attempt}: patch for ${p.finding_id} rejected: ${error}`);
			if (rejected.length === 0) break;
			retry = {
				text: `Your patches below were rejected. Answer with corrected patches for these findings only, or none for a finding you can't patch.\n\n${rejected.map(({ patch: p, error }) => `Finding ${p.finding_id}, ${p.file}:\n${p.diff}git apply said: ${error}`).join("\n\n")}`,
				findings: new Set(rejected.map((r) => r.patch.finding_id)),
			};
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
		usage: calls.usage(),
	};
	await Bun.write(join(dir, "patches.json"), JSON.stringify(patches, null, 2) + "\n");
	return patches;
}
