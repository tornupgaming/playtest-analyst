import { join } from "node:path";
import { parseArgs } from "node:util";
import { apiKey } from "../boundary.ts";
import { patch } from "../patch.ts";

export const description = "Propose diffs to allowlisted project files for a report's findings; write patches.json";

export async function run(argv: string[]) {
	const { values, positionals } = parseArgs({
		args: argv,
		allowPositionals: true,
		options: { report: { type: "string" }, project: { type: "string", default: "." } },
	});
	const [dir] = positionals;
	if (!dir) {
		console.error("Usage: playtest patch <session> [--report report.json] [--project <godot project root>]");
		return 2;
	}
	apiKey();
	const started = performance.now();
	const { patches, usage: u } = await patch(dir, values.report ?? join(dir, "report.json"), values.project);
	const total = ((performance.now() - started) / 1000).toFixed(1);
	for (const p of patches) console.log(`${p.id} ${p.finding_id} ${p.file}: ${p.summary}`);
	console.log(`${patches.length} patches → ${join(dir, "patches.json")}`);
	console.log(`$${u.cost_usd.toFixed(4)}, tokens ${u.input_tokens} in (${u.cached_tokens} cached) / ${u.output_tokens} out, model ${u.latency_s} s, total ${total} s`);
}
