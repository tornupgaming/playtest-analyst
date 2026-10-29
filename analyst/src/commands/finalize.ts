// `playtest finalize`: a recording's raw capture → video.mp4 and mic16k.wav on the session clock.
import { join } from "node:path";
import { finalize } from "../finalize.ts";

export const description = "Put the raw capture on the session clock: write video.mp4 and mic16k.wav";

export async function run(argv: string[]) {
	const [dir] = argv;
	if (!dir) {
		console.error("Usage: playtest finalize <session>");
		return 2;
	}
	await finalize(dir);
	console.log(`Wrote ${join(dir, "video.mp4")} and ${join(dir, "mic16k.wav")}`);
}
