// The SAM step (DECISIONS.md §5): for each finding with a highlight, segment its phrasings on the
// key frame with sam-3.1 and draw the first confident match onto analysis/frames/<config>/<id>.png.
// A finding SAM can't annotate gets no annotated_frame, so the viewer shows the plain frame instead.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { decodeMaskToRaster, parseImageStream, recordsOfKind, type ResponsesEvent } from "@meta-sam/parser";
import { respond } from "./meta.ts";
import type { Finding, Report } from "./schema.ts";

const CONCURRENCY = 4;
/** Every match in the TUG-118 probe scored 0.50–0.94 and covered the thing it was named for. */
const MIN_CONFIDENCE = 0.5;
/** When no phrasing matches at the key frame, try this far either side of it. At most 3 × 3 calls. */
const NEARBY_S = 2;
/** The viewer's highlight yellow, a translucent fill over the match and a solid stroke around it. */
const ACCENT = [255, 212, 0] as const;
const FILL_ALPHA = 0.2;
const STROKE_PX = 4;
/** A dark edge outside the stroke, so the yellow reads on bright footage. */
const HALO_PX = 2;
const HALO_ALPHA = 0.6;
/** Everything outside a soft circle around the match is darkened, so the eye goes to it. */
const SPOT_MARGIN_PX = 28;
const SPOT_FEATHER_PX = 36;
const SPOT_DIM = 0.55;

async function ffmpeg(args: string[], stdin?: Uint8Array): Promise<Uint8Array> {
	const proc = Bun.spawn(["ffmpeg", "-loglevel", "error", ...args], { stdin: stdin ?? "ignore", stdout: "pipe", stderr: "pipe" });
	const [out, err, code] = await Promise.all([new Response(proc.stdout).bytes(), new Response(proc.stderr).text(), proc.exited]);
	if (code !== 0) throw new Error(`ffmpeg exited ${code}: ${err.trim()}`);
	return out;
}

/** The parser needs a stream; a non-streaming reply is one delta. It throws on an empty result
 * unless it also sees `output_text.done` (docs/wiki/sam-3-1.md). */
async function* replay(text: string): AsyncIterable<ResponsesEvent> {
	if (text) yield { type: "response.output_text.delta", item_id: "m", output_index: 0, content_index: 0, delta: text };
	yield { type: "response.output_text.done", item_id: "m", output_index: 0, content_index: 0, text };
	yield { type: "response.completed" };
}

type Mask = { raster: ArrayLike<number>; left: number; top: number; width: number; height: number };

/** The frame with `mask` filled, outlined and spotlit. Pixels are rgb24. Distances are chamfer 3-4
 * (3 per straight step, 4 per diagonal), so `d / 3` is about the distance in pixels. */
function drawHighlight(rgb: Uint8Array, width: number, height: number, mask: Mask): Uint8Array {
	const far = 1 << 20;
	const d = new Int32Array(width * height).fill(far);
	for (let i = 0; i < mask.raster.length; i++) {
		if (mask.raster[i]) d[(mask.top + Math.floor(i / mask.width)) * width + mask.left + (i % mask.width)] = 0;
	}
	const relax = (i: number, j: number, cost: number) => {
		if (d[j]! + cost < d[i]!) d[i] = d[j]! + cost;
	};
	for (let y = 0; y < height; y++)
		for (let x = 0; x < width; x++) {
			const i = y * width + x;
			if (x > 0) relax(i, i - 1, 3);
			if (y > 0) {
				relax(i, i - width, 3);
				if (x > 0) relax(i, i - width - 1, 4);
				if (x < width - 1) relax(i, i - width + 1, 4);
			}
		}
	for (let y = height - 1; y >= 0; y--)
		for (let x = width - 1; x >= 0; x--) {
			const i = y * width + x;
			if (x < width - 1) relax(i, i + 1, 3);
			if (y < height - 1) {
				relax(i, i + width, 3);
				if (x < width - 1) relax(i, i + width + 1, 4);
				if (x > 0) relax(i, i + width - 1, 4);
			}
		}
	const out = rgb.slice();
	const blend = (i: number, color: readonly number[], alpha: number) => {
		for (let c = 0; c < 3; c++) out[i * 3 + c] = Math.round(out[i * 3 + c]! * (1 - alpha) + color[c]! * alpha);
	};
	const [cx, cy] = [mask.left + mask.width / 2, mask.top + mask.height / 2];
	const radius = Math.hypot(mask.width, mask.height) / 2 + SPOT_MARGIN_PX;
	for (let i = 0; i < d.length; i++) {
		const outside = Math.hypot((i % width) - cx, Math.floor(i / width) - cy) - radius;
		if (outside > 0) blend(i, [0, 0, 0], SPOT_DIM * Math.min(1, outside / SPOT_FEATHER_PX));
		if (d[i] === 0) blend(i, ACCENT, FILL_ALPHA);
		else if (d[i]! <= STROKE_PX * 3) blend(i, ACCENT, 1);
		else if (d[i]! <= (STROKE_PX + HALO_PX) * 3) blend(i, [0, 0, 0], HALO_ALPHA);
	}
	return out;
}

/** SAM's most confident mask for `prompt` on `png`, if it reaches MIN_CONFIDENCE. */
async function segment(png: Uint8Array, prompt: string, note: string) {
	const { response } = await respond(
		{
			model: "sam-3.1",
			metadata: { include_confidence: "true" },
			input: [{ type: "message", role: "user", content: [
				{ type: "input_text", text: prompt },
				{ type: "input_image", image_url: `data:image/png;base64,${Buffer.from(png).toString("base64")}` },
			] }],
		},
		note,
	);
	const masks = recordsOfKind((await parseImageStream(replay(response.output_text)).finalResult).records, "mask");
	return masks.filter((m) => (m.confidence ?? 0) >= MIN_CONFIDENCE).toSorted((a, b) => b.confidence! - a.confidence!)[0];
}

/** Tries each phrasing at `t`, then at t − 2 s and t + 2 s, and draws the first match to `out`.
 * Returns the phrasing and time that matched, or throws saying why there is none. */
async function annotateFinding(video: string, highlight: NonNullable<Finding["highlight"]>, out: string, note: string) {
	const times = [...new Set([highlight.t, highlight.t - NEARBY_S, highlight.t + NEARBY_S].map((t) => Math.max(t, 0)))];
	for (const t of times) {
		// Past the video's end there is no frame, so nothing to match.
		const png = await ffmpeg(["-ss", String(t), "-i", video, "-frames:v", "1", "-c:v", "png", "-f", "image2pipe", "-"]);
		if (png.length === 0) continue;
		for (const prompt of highlight.prompts) {
			const top = await segment(png, prompt, note);
			if (!top) continue;
			// PNG IHDR: width and height are the big-endian u32s at bytes 16 and 20.
			const header = new DataView(png.buffer, png.byteOffset);
			const [width, height] = [header.getUint32(16), header.getUint32(20)];
			const rgb = await ffmpeg(["-f", "png_pipe", "-i", "-", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], png);
			const mask = { raster: decodeMaskToRaster(top.mask), left: top.bounds.left, top: top.bounds.top, width: top.mask.width, height: top.mask.height };
			await ffmpeg(["-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", `${width}x${height}`, "-i", "-", out], drawHighlight(rgb, width, height, mask));
			return { prompt, t };
		}
	}
	throw new Error(`SAM found no match for ${highlight.prompts.map((p) => `"${p}"`).join(", ")} at ${times.join(", ")} s.`);
}

/** Runs `fn` over `items`, at most `limit` at a time, keeping their order. */
async function mapLimit<T, R>(items: readonly T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
	const results: R[] = [];
	let next = 0;
	const worker = async () => {
		while (next < items.length) {
			const i = next++;
			results[i] = await fn(items[i]!);
		}
	};
	await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
	return results;
}

/** The report with `annotated_frame`, `annotated_prompt` and `annotated_t` set on each finding SAM
 * could annotate, and cleared on the rest. */
export async function annotate(dir: string, report: Report): Promise<Report> {
	// One folder per config, so reports from different configs on one session keep their own frames.
	const frames = `analysis/frames/${report.config.replace(/[^\w.-]/g, "_")}`;
	mkdirSync(join(dir, frames), { recursive: true });
	const findings = await mapLimit(report.findings, CONCURRENCY, async ({ annotated_frame: _f, annotated_prompt: _p, annotated_t: _t, ...f }): Promise<Finding> => {
		if (!f.highlight) return f;
		const frame = `${frames}/${f.id}.png`;
		try {
			const { prompt, t } = await annotateFinding(join(dir, "video.mp4"), f.highlight, join(dir, frame), `annotate ${report.session_id} ${f.id}`);
			return { ...f, annotated_frame: frame, annotated_prompt: prompt, annotated_t: t };
		} catch (err) {
			console.error(`${f.id}: no annotated frame: ${(err as Error).message}`);
			return f;
		}
	});
	return { ...report, findings };
}
