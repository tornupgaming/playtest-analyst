// `playtest metrics`: deaths, retries and times from the telemetry alone (src/metrics.ts), as markdown.
import { basename, resolve } from "node:path";
import { parseArgs } from "node:util";
import { readSession } from "../bundle.ts";
import { metrics } from "../metrics.ts";
import type { Metrics } from "../metrics.ts";

export const description = "Deaths, retries, time to complete and time per zone, per session";

const USAGE = "Usage: playtest metrics <session dir…> [--complete-event TYPE] [--out FILE.md]";

/** m:ss, as in the demo's "11:20". */
function clock(s: number | null) {
	if (s === null) return "n/a";
	const r = Math.round(s);
	return `${Math.floor(r / 60)}:${String(r % 60).padStart(2, "0")}`;
}
const causes = (m: Metrics) => Object.entries(m.deaths_by_cause).map(([c, n]) => `${c} ${n}`).join(", ") || "-";

export async function run(argv: string[]) {
	let args;
	try {
		args = parseArgs({ args: argv, allowPositionals: true, options: { "complete-event": { type: "string" }, out: { type: "string" } } });
	} catch (err) {
		console.error(`${err instanceof Error ? err.message : err}\n${USAGE}`);
		return 2;
	}
	if (args.positionals.length === 0) {
		console.error(USAGE);
		return 2;
	}
	const rows: { name: string; m: Metrics }[] = [];
	for (const dir of args.positionals) {
		const { meta, events } = await readSession(dir);
		rows.push({ name: basename(resolve(dir)), m: metrics(events, { completeEvent: args.values["complete-event"], endT: meta.duration }) });
	}

	const lines = ["# Metrics", "", "| session | deaths | by cause | retries | time to complete |", "|---|---|---|---|---|"];
	for (const { name, m } of rows) lines.push(`| ${name} | ${m.deaths} | ${causes(m)} | ${m.retries} | ${clock(m.time_to_complete)} |`);
	if (rows.length === 2) {
		const [a, b] = rows.map((r) => r.m) as [Metrics, Metrics];
		lines.push("", `**${rows[0]!.name} → ${rows[1]!.name}:** deaths ${a.deaths}→${b.deaths}, retries ${a.retries}→${b.retries}, time ${clock(a.time_to_complete)}→${clock(b.time_to_complete)}`);
	}

	const zones = [...new Set(rows.flatMap((r) => Object.keys(r.m.time_per_zone)))];
	lines.push("", "## Time per zone (s)", "", `| zone | ${rows.map((r) => r.name).join(" | ")} |`, `|---|${rows.map(() => "---|").join("")}`);
	for (const z of zones) lines.push(`| ${z} | ${rows.map((r) => r.m.time_per_zone[z]?.toFixed(1) ?? "-").join(" | ")} |`);

	const md = lines.join("\n");
	console.log(md);
	if (args.values.out) await Bun.write(args.values.out, md);
}
