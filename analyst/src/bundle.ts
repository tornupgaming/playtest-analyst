// Reads a session bundle (DECISIONS.md §2). This is the boundary: files in, typed data out.
import { join } from "node:path";
import { SessionMeta, TelemetryEvent } from "./schema.ts";

/** `events` are in time order. Recorders may write some lines late (input_idle is written when
 * the idle period ends but stamped at its start), so the order is fixed here, once. */
export type Session = { dir: string; meta: SessionMeta; events: TelemetryEvent[] };

export async function readSession(dir: string): Promise<Session> {
	const meta = SessionMeta.parse(await Bun.file(join(dir, "session.json")).json());
	const text = await Bun.file(join(dir, "events.jsonl")).text();
	const events = text
		.split("\n")
		.filter((line) => line.trim() !== "")
		.map((line, i) => {
			try {
				return TelemetryEvent.parse(JSON.parse(line));
			} catch (err) {
				throw new Error(`${dir}/events.jsonl line ${i + 1}: ${err}`);
			}
		})
		.sort((a, b) => a.t - b.t);
	return { dir, meta, events };
}
