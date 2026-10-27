import { join } from "node:path";
import { parseArgs } from "node:util";
import { analyse } from "../analyse.ts";
import { loadPrevious } from "../compare.ts";
import { DEFAULT_CONFIG, loadConfig } from "../config.ts";

export const description = "Analyse a session with Muse Wonder and write report.json";

export async function run(argv: string[]) {
	const { values, positionals } = parseArgs({
		args: argv,
		allowPositionals: true,
		options: { config: { type: "string", default: DEFAULT_CONFIG }, out: { type: "string" }, previous: { type: "string" }, patches: { type: "string" } },
	});
	const [dir] = positionals;
	if (!dir || (values.patches && !values.previous)) {
		console.error("Usage: playtest analyse <session> [--config analyst/configs/v0.json] [--out report.json] [--previous <previous report.json> [--patches patches.json]]");
		return 2;
	}
	const out = values.out ?? join(dir, "report.json");
	const started = performance.now();
	const previous = values.previous ? await loadPrevious(values.previous, values.patches) : undefined;
	const { findings, usage: u, comparison: c } = await analyse(dir, await loadConfig(values.config), out, previous);
	const total = ((performance.now() - started) / 1000).toFixed(1);
	console.log(`${findings.length} findings → ${out}`);
	if (c) console.log(`vs ${c.previous_session}: ${c.counts.resolved} resolved · ${c.counts.new} new · ${c.counts.persisting} persisting`);
	console.log(`$${u.cost_usd.toFixed(4)}, tokens ${u.input_tokens} in (${u.cached_tokens} cached) / ${u.output_tokens} out, model ${u.latency_s} s, total ${total} s`);
}
