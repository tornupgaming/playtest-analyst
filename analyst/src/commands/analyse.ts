import { join } from "node:path";
import { parseArgs } from "node:util";
import { analyse } from "../analyse.ts";
import { DEFAULT_CONFIG, loadConfig } from "../config.ts";

export const description = "Analyse a session with Muse Wonder and write report.json";

export async function run(argv: string[]) {
	const { values, positionals } = parseArgs({
		args: argv,
		allowPositionals: true,
		options: { config: { type: "string", default: DEFAULT_CONFIG }, out: { type: "string" } },
	});
	const [dir] = positionals;
	if (!dir) {
		console.error("Usage: playtest analyse <session> [--config analyst/configs/v0.json] [--out report.json]");
		return 2;
	}
	const out = values.out ?? join(dir, "report.json");
	const started = performance.now();
	const { findings, usage: u } = await analyse(dir, await loadConfig(values.config), out);
	const total = ((performance.now() - started) / 1000).toFixed(1);
	console.log(`${findings.length} findings → ${out}`);
	console.log(`$${u.cost_usd.toFixed(4)}, tokens ${u.input_tokens} in (${u.cached_tokens} cached) / ${u.output_tokens} out, model ${u.latency_s} s, total ${total} s`);
}
