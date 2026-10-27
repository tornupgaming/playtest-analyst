// Cross-build memory (TUG-109): `playtest analyse <session> --previous <report.json>`. The
// previous build's findings, and the patches applied since (TUG-107), go into the same Muse
// Wonder call as text. The model tags each finding with the previous finding it matches;
// previous findings that nothing matches are resolved.
import { resolve } from "node:path";
import { z } from "zod";
import { ModelFinding, Report } from "./schema.ts";

/** patches.json from TUG-107, reduced to what the model needs. */
const Patches = z.object({ patches: z.array(z.object({ finding_id: z.string(), file: z.string(), summary: z.string() })) });

export type Previous = { report: Report; patches: z.infer<typeof Patches>["patches"]; prompt: string };

export async function loadPrevious(reportPath: string, patchesPath?: string): Promise<Previous> {
	return {
		report: Report.parse(await Bun.file(reportPath).json()),
		patches: patchesPath ? Patches.parse(await Bun.file(patchesPath).json()).patches : [],
		prompt: await Bun.file(resolve(import.meta.dir, "../prompts/compare.md")).text(),
	};
}

/** The extra input text, and an output format whose previous_id can only be a previous finding's id. */
export function compareInput({ report, patches, prompt }: Previous) {
	const ids = report.findings.map((f) => f.id);
	const previousId = ids.length > 0 ? z.enum(ids as [string, ...string[]]).nullable() : z.null();
	const findings = report.findings.map((f) => `- ${f.id} [${f.category}${f.zone ? `, ${f.zone}` : ""}] ${f.summary} Suggested fix: ${f.suggested_fix}`);
	const applied = patches.map((p) => `- for ${p.finding_id}, in ${p.file}: ${p.summary}`);
	return {
		text: [
			prompt,
			`Previous build: session ${report.session_id}. Its findings, one per line:\n${findings.join("\n") || "(none)"}`,
			`Patches applied since:\n${applied.join("\n") || "(none recorded)"}`,
		].join("\n\n"),
		output: z.object({ findings: z.array(ModelFinding.extend({ previous_id: previousId })) }),
	};
}

export function comparison(previous: Report, found: { previous_id?: string | null }[]): NonNullable<Report["comparison"]> {
	const matched = new Set(found.map((f) => f.previous_id));
	const resolved = previous.findings.filter((f) => !matched.has(f.id)).map(({ id, category, summary }) => ({ id, category, summary }));
	const persisting = found.filter((f) => f.previous_id).length;
	return {
		previous_session: previous.session_id,
		resolved,
		counts: { resolved: resolved.length, new: found.length - persisting, persisting },
	};
}
