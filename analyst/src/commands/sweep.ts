import { mkdirSync } from "node:fs";
import { basename, join } from "node:path";
import { readJson } from "../boundary.ts";
import { loadConfig } from "../config.ts";
import { GroundTruth } from "../schema.ts";
import { readme, sweep } from "../sweep.ts";

export const description = "Run every config on every session, score each report, write a README";

const USAGE = `Usage: playtest sweep --configs <config.json…> --sessions <session dir…> [--out eval/sweeps/<date>/] [--concurrency 3]`;
const ROOT = join(import.meta.dir, "../../..");

export async function run(argv: string[]) {
	// --configs and --sessions each take every value up to the next flag.
	const lists: Record<string, string[]> = {};
	let flag: string | undefined;
	for (const arg of argv) {
		if (arg.startsWith("--")) lists[(flag = arg.slice(2))] ??= [];
		else if (flag) lists[flag]!.push(arg);
	}
	const { configs = [], sessions = [], out: [out = join(ROOT, "eval/sweeps", new Date().toISOString().slice(0, 10))] = [], concurrency: [c = "3"] = [] } = lists;
	const concurrency = Number(c);
	if (!configs.length || !sessions.length || !Number.isInteger(concurrency) || concurrency < 1) {
		console.error(USAGE);
		return 2;
	}

	const gt = await readJson(join(ROOT, "eval/ground_truth.json"), GroundTruth);
	const runs = await sweep(await Promise.all(configs.map(loadConfig)), sessions, out, gt, concurrency);
	mkdirSync(out, { recursive: true });
	const md = readme(basename(out), runs, gt);
	await Bun.write(join(out, "README.md"), md);
	console.log(md);
	return runs.some((r) => "error" in r.result) ? 1 : 0;
}
