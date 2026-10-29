// `playtest eval`: scores session reports against the planted problems (src/eval.ts), as markdown.
import { join } from "node:path";
import { parseArgs } from "node:util";
import { readJson } from "../boundary.ts";
import { readSession } from "../bundle.ts";
import { findingText, num, score, totals, windows } from "../eval.ts";
import type { Strictness } from "../eval.ts";
import { GroundTruth, Report } from "../schema.ts";

export const description = "Score session reports against eval/ground_truth.json";

const USAGE = `Usage: playtest eval <session dir…> [--gt FILE] [--report NAME] [--strict category|zone|any] [--pad SECONDS] [--out FILE.md]`;
const DEFAULT_GT = join(import.meta.dir, "../../../eval/ground_truth.json");

const span = ([a, b]: [number, number]) => `${a.toFixed(1)}–${b.toFixed(1)} s`;

export async function run(argv: string[]) {
	let args;
	try {
		args = parseArgs({
			args: argv,
			allowPositionals: true,
			options: {
				gt: { type: "string", default: DEFAULT_GT },
				report: { type: "string", default: "report.json" },
				strict: { type: "string", default: "category" },
				pad: { type: "string", default: "10" },
				out: { type: "string" },
			},
		});
	} catch (err) {
		console.error(`${err instanceof Error ? err.message : err}\n${USAGE}`);
		return 2;
	}
	const { gt: gtPath, report: reportName, strict, pad, out } = args.values;
	const padS = Number(pad);
	if (args.positionals.length === 0 || !["category", "zone", "any"].includes(strict) || !Number.isFinite(padS) || padS < 0) {
		console.error(USAGE);
		return 2;
	}

	const gt = await readJson(gtPath, GroundTruth);
	const rows = [];
	for (const dir of args.positionals) {
		const session = await readSession(dir);
		const report = await readJson(join(dir, reportName), Report);
		const opts = { padS, strict: strict as Strictness, profile: session.meta.profile, endT: session.meta.duration };
		rows.push({ report, session, score: score(report, gt, session.events, opts) });
	}

	const lines = [`# Eval: ${gt.level}`, "", `${rows.length} session(s), strict=${strict}, pad=${padS} s`, ""];

	let cost = 0;
	let latency = 0;
	lines.push("| session | profile | recall | precision | hits | misses | wrong category | false pos | duplicates | cost $ | latency s |", "|---|---|---|---|---|---|---|---|---|---|---|");
	for (const { report, score: s } of rows) {
		cost += report.usage.cost_usd;
		latency += report.usage.latency_s;
		lines.push(`| ${s.session_id} | ${s.profile ?? "-"} | ${num(s.recall)} | ${num(s.precision)} | ${s.hits.length} | ${s.misses.length} | ${s.mislabelled.length} | ${s.false_positives.length} | ${s.duplicates.length} | ${num(report.usage.cost_usd)} | ${num(report.usage.latency_s, 1)} |`);
	}
	const all = totals(rows.map((r) => r.score));
	lines.push(`| **all** | | ${num(all.recall)} | ${num(all.precision)} | ${all.hits} | ${all.misses} | ${all.mislabelled} | ${all.false_positives} | ${all.duplicates} | ${num(cost)} | ${num(latency / rows.length, 1)} mean |`, "");

	for (const { report, session, score: s } of rows) {
		const items = [
			...s.misses.map((id) => {
				const p = gt.plants.find((p) => p.id === id)!;
				const wins = windows(session.events, p.zone, padS, session.meta.duration);
				return `- miss: plant ${id} ${p.category} in ${p.zone} (${wins.length ? wins.map(span).join(", ") : "zone never entered"}): ${p.symptom}`;
			}),
			...s.mislabelled.map((m) => `- found, wrong category: plant ${m.plant} ${gt.plants.find((p) => p.id === m.plant)!.category}: ${findingText(report, m.finding)}`),
			...s.false_positives.map((id) => `- false positive: ${findingText(report, id)}`),
			...s.duplicates.map((d) => `- duplicate of plant ${d.plant}: ${findingText(report, d.finding)}`),
			...s.excused.map((id) => `- excused (known unplanned): ${findingText(report, id)}`),
		];
		if (items.length) lines.push(`## ${s.session_id}`, "", ...items, "");
	}

	const md = lines.join("\n");
	console.log(md);
	if (out) await Bun.write(out, md);
}
