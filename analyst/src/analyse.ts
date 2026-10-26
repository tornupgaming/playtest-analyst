// `playtest analyse`: session bundle → Muse Wonder → report.json (DECISIONS.md §4).
// Upload and ASR run in parallel, then one /v1/responses call. Invalid output is retried
// once with the validation error appended.
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import { readSession } from "./bundle.ts";
import type { AnalysisConfig } from "./config.ts";
import { finalize, finalized, run } from "./finalize.ts";
import { ASR_CHUNK_S, chunkStarts, MODEL, modelRequest, sessionTurns } from "./input.ts";
import { metaFetch, respond, type Responded, uploadFile } from "./meta.ts";
import { type ModelFinding, ModelOutput, type Report, type TranscriptTurn } from "./schema.ts";

const ASR_MODEL = "muse-voice-transcribe-1.0";
const AsrResponse = z.object({ turns: z.array(z.object({ startMs: z.number(), endMs: z.number(), transcript: z.string() })) });

async function uploadVideo(dir: string, withAudio: boolean): Promise<string> {
	if (withAudio) return uploadFile(join(dir, "video.mp4"));
	const silent = join(dir, "analysis/upload.mp4");
	await run(["ffmpeg", "-y", "-loglevel", "error", "-i", join(dir, "video.mp4"), "-map", "0:v", "-c", "copy", silent]);
	return uploadFile(silent);
}

async function transcribe(dir: string, duration: number): Promise<TranscriptTurn[]> {
	const chunks = await Promise.all(
		chunkStarts(duration).map(async (start, i) => {
			const wav = join(dir, `analysis/asr-${i}.wav`);
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
	await Bun.write(join(dir, "analysis/transcript.json"), JSON.stringify(turns, null, 2));
	return turns;
}

/** The model's findings, or an error saying why the output doesn't match the schema. */
function findings(response: Responded["response"]): ModelFinding[] {
	if (response.status === "incomplete") throw new Error(`The response is incomplete (${response.incomplete_details?.reason ?? "no reason given"}).`);
	const text = response.output.flatMap((o) => (o.type === "message" ? o.content : [])).find((c) => c.type === "output_text")?.text;
	if (text === undefined) throw new Error("The response has no output_text.");
	let json: unknown;
	try {
		json = JSON.parse(text);
	} catch (err) {
		throw new Error(`The output is not JSON: ${(err as Error).message}`);
	}
	const parsed = ModelOutput.safeParse(json);
	if (!parsed.success) throw new Error(z.prettifyError(parsed.error));
	return parsed.data.findings;
}

export async function analyse(dir: string, config: AnalysisConfig, out = join(dir, "report.json")): Promise<Report> {
	if (!finalized(dir)) await finalize(dir);
	const { meta, events } = await readSession(dir);
	mkdirSync(join(dir, "analysis"), { recursive: true });
	const prompt = await Bun.file(config.prompt).text();

	const [fileId, turns] = await Promise.all([
		uploadVideo(dir, config.video_audio),
		config.include_transcript && meta.capture.audio !== null ? transcribe(dir, meta.duration) : [],
	]);

	const usage = { input_tokens: 0, cached_tokens: 0, output_tokens: 0, cost_usd: 0, latency_s: 0 };
	let found: ModelFinding[] | undefined;
	let error: string | undefined;
	for (let attempt = 1; attempt <= 2 && !found; attempt++) {
		const body = modelRequest({ config, prompt, meta, fileId, turns, events, retryError: error });
		await Bun.write(join(dir, `analysis/request-${attempt}.json`), JSON.stringify(body, null, 2));
		const { response, costUsd, latencyS } = await respond(body, `analyse ${meta.id} ${config.name} attempt ${attempt}`);
		await Bun.write(join(dir, `analysis/response-${attempt}.json`), JSON.stringify(response, null, 2));
		usage.input_tokens += response.usage?.input_tokens ?? 0;
		usage.cached_tokens += response.usage?.input_tokens_details?.cached_tokens ?? 0;
		usage.output_tokens += response.usage?.output_tokens ?? 0;
		usage.cost_usd += costUsd;
		usage.latency_s += latencyS;
		try {
			found = findings(response);
		} catch (err) {
			error = (err as Error).message;
			console.error(`Attempt ${attempt}: the output doesn't match the schema:\n${error}`);
		}
	}
	if (!found) throw new Error(`The model's output was invalid twice. Last error:\n${error}`);

	const report: Report = {
		schema: 1,
		session_id: meta.id,
		created_at: new Date().toISOString(),
		model: MODEL,
		config: config.name,
		findings: found.toSorted((a, b) => a.t_start - b.t_start).map((f, i) => ({ id: `f${i + 1}`, ...f })),
		usage: { ...usage, cost_usd: Math.round(usage.cost_usd * 1e6) / 1e6, latency_s: Math.round(usage.latency_s * 10) / 10 },
	};
	await Bun.write(out, JSON.stringify(report, null, 2) + "\n");
	return report;
}
