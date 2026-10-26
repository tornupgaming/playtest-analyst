// SAM 3.1 probe (TUG-118): segment level frames with noun-phrase, box and point prompts.
//
//   cd spikes/tug-94 && bun install && bun probe.ts
//
// Calls the API through analyst/src/meta.ts (spend cap + ledger). Writes raw responses to
// results/raw/, one summary to results/records.json and each mask to results/masks/ (PGM),
// which overlay.py draws onto the frames.
import { mkdirSync } from "node:fs";
import {
	buildObjectPrompt,
	decodeMaskToRaster,
	parseImageStream,
	recordsOfKind,
	type ResponsesEvent,
} from "@meta-sam/parser";
import { respond } from "../../analyst/src/meta.ts";

const FRAMES: Record<string, string[]> = {
	// First the prompts the app would plausibly ask for, then plainer nouns to tell "SAM can't
	// do this style" apart from "that object isn't in the frame".
	beacon: ["the glowing beacon", "the doorway", "the wooden crate", "the star", "the blue sky", "the player"],
	ledge: ["the ledge edge", "the gap between the ledges", "the tree", "the flower", "the grass path", "the cliff"],
	drop: ["the exit sign", "the doorway", "the enemy", "the arrow", "the mushroom", "the player"],
	fork: ["the exit sign", "exit sign", "the arrow sign", "the hedge wall", "the wooden sign", "the hedge"],
};
const REPS = 2;
const FRAME_SIZE = { width: 1280, height: 720 };

type Job = { frame: string; label: string; text: string; metadata: Record<string, string> };

const jobs: Job[] = Object.entries(FRAMES).flatMap(([frame, prompts]) =>
	prompts.map((text) => ({ frame, label: text, text, metadata: { include_confidence: "true" } })),
);
// Box and point prompts on the fork sign (hand-picked pixels from frames/fork.png).
jobs.push({
	frame: "fork",
	label: "box+point on sign",
	text: buildObjectPrompt({
		size: FRAME_SIZE,
		objects: [
			{ id: 1, prompts: [{ box: { left: 600, top: 285, right: 673, bottom: 341 } }] },
			{ id: 2, prompts: [{ points: [{ x: 640, y: 310 }] }] },
		],
	}),
	metadata: { include_confidence: "true" },
});

async function* events(text: string): AsyncIterable<ResponsesEvent> {
	if (text) yield { type: "response.output_text.delta", item_id: "m", output_index: 0, content_index: 0, delta: text };
	yield { type: "response.output_text.done", item_id: "m", output_index: 0, content_index: 0, text };
	yield { type: "response.completed" };
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
mkdirSync("results/raw", { recursive: true });
mkdirSync("results/masks", { recursive: true });

const records: unknown[] = [];
for (let rep = 1; rep <= REPS; rep++) {
	for (const job of jobs) {
		const b64 = Buffer.from(await Bun.file(`frames/${job.frame}.png`).arrayBuffer()).toString("base64");
		const { response, latencyS, costUsd } = await respond(
			{
				model: "sam-3.1",
				metadata: job.metadata,
				input: [
					{
						type: "message",
						role: "user",
						content: [
							{ type: "input_text", text: job.text },
							{ type: "input_image", image_url: `data:image/png;base64,${b64}` },
						],
					},
				],
			},
			`tug-118 ${job.frame} "${job.label}" rep ${rep}`,
		);
		const name = `${job.frame}__${slug(job.label)}__r${rep}`;
		await Bun.write(`results/raw/${name}.json`, JSON.stringify(response, null, 2));

		const parsed = parseImageStream(events(response.output_text));
		const result = await parsed.finalResult;
		const boxes = recordsOfKind(result.records, "box");
		const masks = recordsOfKind(result.records, "mask");
		const instances = masks.map((m, i) => {
			const raster = decodeMaskToRaster(m.mask);
			const w = m.bounds.right - m.bounds.left;
			const h = m.bounds.bottom - m.bounds.top;
			const pgm = new Uint8Array(raster.length);
			raster.forEach((v, k) => (pgm[k] = v ? 255 : 0));
			Bun.write(`results/masks/${name}__${i}.pgm`, Buffer.concat([Buffer.from(`P5\n${w} ${h}\n255\n`), pgm]));
			const b = boxes.find((x) => x.objectId === m.objectId);
			return {
				objectId: m.objectId,
				bounds: m.bounds,
				box: b ? { left: b.left, top: b.top, right: b.right, bottom: b.bottom } : null,
				confidence: b?.confidence ?? null,
				maskConfidence: (m as { confidence?: number }).confidence ?? null,
				maskPixels: raster.reduce((a, v) => a + v, 0),
				maskFile: `masks/${name}__${i}.pgm`,
			};
		});
		records.push({
			frame: job.frame,
			prompt: job.label,
			rep,
			latencyS: +latencyS.toFixed(3),
			costUsd,
			imagesProcessed: (response.usage as { images_processed?: number } | undefined)?.images_processed,
			outputChars: response.output_text.length,
			diagnostics: result.diagnostics,
			instances,
		});
		console.log(`${name}: ${instances.length} instance(s), ${latencyS.toFixed(2)} s, $${costUsd.toFixed(4)}`);
	}
}
await Bun.write("results/records.json", JSON.stringify(records, null, 2));
