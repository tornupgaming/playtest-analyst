// SAM 3.1 probe (TUG-123): the frames behind the misses of the first multi-phrasing run, with
// plainer phrasings, and one 4× crop around the hall's button.
//
//   bun spikes/tug-123/probe.ts
//
// Frames are the plain key frames from the run (frames/), extracted with ffmpeg from the
// rebuilt synthetic planted-voice video.mp4. Calls go through analyst/src/meta.ts (spend cap
// and ledger). Writes every reply's matches (box and confidence) to results.json.
import { join } from "node:path";
import { respond } from "../../analyst/src/meta.ts";

const PROBES: [frame: string, prompt: string][] = [
	// f3's three phrasings missed on this frame; the button is small, on the shelf.
	["hall-74.png", "the red button"],
	["hall-74.png", "the button"],
	["hall-74.png", "the wooden shelf"],
	["hall-74.png", "the wooden crate"],
	// 320×180 px around the shelf (x 550, y 170), scaled 4× to 1280×720.
	["hall-74-crop4x.png", "the small red button"],
	["hall-74-crop4x.png", "the red button"],
	// f2's three phrasings missed on the HUD text "Reach the beacon." at the top left.
	["plaza-33.png", "the text"],
	["plaza-33.png", "the white text"],
	// f1's "small green platform island" matched the platform under the player, not the one ahead.
	["ledge-12.png", "the floating platform"],
	["ledge-12.png", "the small green block"],
];

const dir = import.meta.dir;
const results = [];
for (const [frame, prompt] of PROBES) {
	const png = await Bun.file(join(dir, "frames", frame)).bytes();
	const { response } = await respond(
		{
			model: "sam-3.1",
			metadata: { include_confidence: "true" },
			input: [{ type: "message", role: "user", content: [
				{ type: "input_text", text: prompt },
				{ type: "input_image", image_url: `data:image/png;base64,${Buffer.from(png).toString("base64")}` },
			] }],
		},
		`tug-123 probe ${frame} ${prompt}`,
	);
	const boxes = [...response.output_text.matchAll(/<\|box;x1=(\d+);y1=(\d+);x2=(\d+);y2=(\d+);w=\d+;h=\d+;c=([\d.]+)\|>/g)].map((m) => ({
		box: [Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4])],
		c: Number(m[5]),
	}));
	console.log(`${frame}  "${prompt}": ${boxes.length ? boxes.map((b) => `${b.box.join(",")} c ${b.c}`).join("; ") : "no match"}`);
	results.push({ frame, prompt, matches: boxes });
}
await Bun.write(join(dir, "results.json"), JSON.stringify(results, null, 2) + "\n");
