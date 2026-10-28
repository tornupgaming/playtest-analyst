// Reads a session bundle (DECISIONS.md §2). This is the boundary: files in, typed data out.
import { existsSync } from "node:fs";
import { join } from "node:path";
import { parseJson, readJson, UserError } from "./boundary.ts";
import { SessionMeta, TelemetryEvent } from "./schema.ts";

/** `events` are in time order. Recorders may write some lines late (input_idle is written when
 * the idle period ends but stamped at its start), so the order is fixed here, once. */
export type Session = { dir: string; meta: SessionMeta; events: TelemetryEvent[] };

export async function readSession(dir: string): Promise<Session> {
	const meta = await readJson(join(dir, "session.json"), SessionMeta);
	const path = join(dir, "events.jsonl");
	if (!existsSync(path)) throw new UserError(`${path}: not found`);
	const events = (await Bun.file(path).text())
		.split("\n")
		.filter((line) => line.trim() !== "")
		.map((line, i) => parseJson(line, TelemetryEvent, `${path} line ${i + 1}`))
		.sort((a, b) => a.t - b.t);
	return { dir, meta, events };
}
