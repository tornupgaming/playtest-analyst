import { join } from "node:path";
import { parseArgs } from "node:util";
import { annotate } from "../annotate.ts";
import { Report } from "../schema.ts";

export const description = "Redraw each finding's SAM 3.1 highlight on its key frame and update report.json";

export async function run(argv: string[]) {
	const { values, positionals } = parseArgs({ args: argv, allowPositionals: true, options: { report: { type: "string" } } });
	const [dir] = positionals;
	if (!dir) {
		console.error("Usage: playtest annotate <session> [--report report.json]");
		return 2;
	}
	const path = values.report ?? join(dir, "report.json");
	const report = await annotate(dir, Report.parse(await Bun.file(path).json()));
	await Bun.write(path, JSON.stringify(report, null, 2) + "\n");
	const { findings } = report;
	console.log(`${findings.filter((f) => f.annotated_frame).length} of ${findings.filter((f) => f.highlight).length} highlights annotated → ${path}`);
}
