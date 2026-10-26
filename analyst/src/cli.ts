#!/usr/bin/env bun
// `playtest <command> [args]`. Each command is a module in src/commands/ exporting
// `description` and `run(argv)`, so commands can be added without touching this file.
import { basename } from "node:path";

type Command = { description: string; run: (argv: string[]) => Promise<number | void> };

const dir = `${import.meta.dir}/commands`;
const names = Array.from(new Bun.Glob("*.ts").scanSync(dir))
	.filter((f) => !f.endsWith(".test.ts"))
	.map((f) => basename(f, ".ts"))
	.sort();

const [name, ...argv] = process.argv.slice(2);

if (!name || name === "--help" || name === "-h" || !names.includes(name)) {
	if (name && !["--help", "-h"].includes(name)) console.error(`Unknown command: ${name}\n`);
	console.log("Usage: playtest <command> [args]\n\nCommands:");
	for (const n of names) {
		const cmd = (await import(`${dir}/${n}.ts`)) as Command;
		console.log(`  ${n.padEnd(10)} ${cmd.description}`);
	}
	process.exit(name && !["--help", "-h"].includes(name) ? 2 : 0);
}

const cmd = (await import(`${dir}/${name}.ts`)) as Command;
process.exit((await cmd.run(argv)) ?? 0);
