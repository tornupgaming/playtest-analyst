// `playtest analyse`: session bundle → Muse Wonder → SAM → report.json (DECISIONS.md §4, §5).
// ASR (retried on rate limits and server errors), then the upload, then one /v1/responses call. Invalid output is retried
// once with the validation error appended. Last, each finding's highlight is drawn on its key frame.
import { mkdirSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { z } from "zod";
import { annotate } from "./annotate.ts";
import { readSession } from "./bundle.ts";
import { comparison, compareInput, type Previous } from "./compare.ts";
import type { AnalysisConfig } from "./config.ts";
import { finalize, finalized, run } from "./finalize.ts";
import { ASR_CHUNK_S, chunkStarts, MODEL, modelRequest, sessionTurns } from "./input.ts";
import { metaFetch, outputJson, respond, uploadFile } from "./meta.ts";
import { type Finding, ModelOutput, type Report, type TranscriptTurn } from "./schema.ts";

const ASR_MODEL = "muse-voice-transcribe-1.0";
const AsrResponse = z.object({ turns: z.array(z.object({ startMs: z.number(), endMs: z.number(), transcript: z.string() })) });

async function uploadVideo(dir: string, work: string, withAudio: boolean): Promise<string> {
	if (withAudio) return uploadFile(join(dir, "video.mp4"));
	const silent = join(work, "upload.mp4");
	await run(["ffmpeg", "-y", "-loglevel", "error", "-i", join(dir, "video.mp4"), "-map", "0:v", "-c", "copy", silent]);
	return uploadFile(silent);
}

async function transcribe(dir: string, work: string, duration: number): Promise<TranscriptTurn[]> {
	const chunks = await Promise.all(
		chunkStarts(duration).map(async (start, i) => {
			const wav = join(work, `asr-${i}.wav`);
			await run(["ffmpeg", "-y", "-loglevel", "error", "-ss", String(start), "-t", String(ASR_CHUNK_S), "-i", join(dir, "mic16k.wav"), "-c", "copy", wav]);
			const form = new FormData();
			form.append("request", new Blob([JSON.stringify({ model: ASR_MODEL, audioEncoding: "WAV", mode: "ENDPOINTING" })], { type: "application/json" }));
			form.append("audio", new Blob([await Bun.file(wav).arrayBuffer()], { type: "audio/wav" }), `asr-${i}.wav`);
			const res = await metaFetch("/asr/transcribe", { method: "POST", body: form }, ASR_MODEL, `asr ${dir} chunk ${i}`);
			if (!res.ok) throw new Error(`ASR chunk ${i}: HTTP ${res.status}: ${(await res.text()).slice(0, 500)}`);
			return { start, turns: AsrResponse.parse(await res.json()).turns };
		}),
	);
	const turns = sessionTurns(chunks);
	await Bun.write(join(work, "transcript.json"), JSON.stringify(turns, null, 2));
	return turns;
}

/** Intermediate files go next to `out`: in `analysis/` for report.json, `<name>.analysis/` for any
 * other name, so two reports written to one folder never share an upload or ASR chunks.
 * With `previous`, the findings are compared with the previous build's (TUG-109). */
export async function analyse(dir: string, config: AnalysisConfig, out = join(dir, "report.json"), previous?: Previous): Promise<Report> {
	if (!finalized(dir)) await finalize(dir);
	const { meta, events } = await readSession(dir);
	const work = join(dirname(out), basename(out) === "report.json" ? "analysis" : `${basename(out, ".json")}.analysis`);
	mkdirSync(work, { recursive: true });
	const prompt = await Bun.file(config.prompt).text();

	// ASR before the upload, so the video goes up once: silent, or with its audio if ASR failed.
	const transcript =
		config.include_transcript && meta.capture.audio !== null
			? await transcribe(dir, work, meta.duration).catch((err: Error) => {
					console.error(`ASR failed, so the video goes with its audio track instead (DECISIONS.md §4): ${err.message}`);
					return null;
				})
			: [];
	// ASR failed: send the mic as the video's audio track. Speech timing is looser, but the words get through.
	if (transcript === null) config = { ...config, include_transcript: false, video_audio: true };
	const fileId = await uploadVideo(dir, work, config.video_audio);
	const turns = transcript ?? [];

	const usage = { input_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0, latency_s: 0 };
	const compare = previous && compareInput(previous);
	let found: Omit<Finding, "id">[] | undefined;
	let error: string | undefined;
	for (let attempt = 1; attempt <= 2 && !found; attempt++) {
		const body = modelRequest({ config, prompt, meta, fileId, turns, events, retryError: error, compare });
		await Bun.write(join(work, `request-${attempt}.json`), JSON.stringify(body, null, 2));
		const { response, costUsd, latencyS } = await respond(body, `analyse ${meta.id} ${config.name} attempt ${attempt}`);
		await Bun.write(join(work, `response-${attempt}.json`), JSON.stringify(response, null, 2));
		usage.input_tokens += response.usage?.input_tokens ?? 0;
		usage.cached_tokens += response.usage?.input_tokens_details?.cached_tokens ?? 0;
		usage.output_tokens += response.usage?.output_tokens ?? 0;
		usage.cost_usd += costUsd;
		usage.latency_s += latencyS;
		try {
			found = outputJson(response, compare?.output ?? ModelOutput).findings;
		} catch (err) {
			error = (err as Error).message;
			console.error(`Attempt ${attempt}: the output doesn't match the schema:\n${error}`);
		}
	}
	if (!found) throw new Error(`The model's output was invalid twice. Last error:\n${error}`);

	const report = await annotate(dir, {
		schema: 1,
		session_id: meta.id,
		created_at: new Date().toISOString(),
		model: MODEL,
		config: config.name,
		findings: found.toSorted((a, b) => a.t_start - b.t_start).map((f, i) => ({ id: `f${i + 1}`, ...f })),
		usage: { ...usage, cost_usd: Math.round(usage.cost_usd * 1e6) / 1e6, latency_s: Math.round(usage.latency_s * 10) / 10 },
		...(previous && { comparison: comparison(previous.report, found) }),
	});
	await Bun.write(out, JSON.stringify(report, null, 2) + "\n");
	return report;
}
