// Bundle → model input (DECISIONS.md §4). Pure transforms from session data to the text and
// request body Muse Wonder sees. Every time is seconds on the session clock.
import { z } from "zod";
import type { AnalysisConfig } from "./config.ts";
import { ModelOutput, type SessionMeta, type TelemetryEvent, type TranscriptTurn } from "./schema.ts";

export const MODEL = "muse-wonder-1.0";

/** ASR takes at most 10 minutes per request (wiki: meta-asr). */
export const ASR_CHUNK_S = 600;

/** Session times at which each ≤10-minute ASR chunk starts. */
export function chunkStarts(duration: number): number[] {
	return Array.from({ length: Math.max(1, Math.ceil(duration / ASR_CHUNK_S)) }, (_, i) => i * ASR_CHUNK_S);
}

export type AsrTurn = { startMs: number; endMs: number; transcript: string };

/** ASR turns per chunk → one transcript on the session clock. Drops the zero-length tail
 * fragments that ENDPOINTING emits (wiki: meta-asr). */
export function sessionTurns(chunks: { start: number; turns: AsrTurn[] }[]): TranscriptTurn[] {
	return chunks
		.flatMap(({ start, turns }) =>
			turns
				.filter((t) => t.endMs > t.startMs)
				.map((t) => ({ start: (start * 1000 + t.startMs) / 1000, end: (start * 1000 + t.endMs) / 1000, text: t.transcript.trim() })),
		)
		.sort((a, b) => a.start - b.start);
}

export function transcriptText(turns: TranscriptTurn[]): string {
	if (turns.length === 0) return "(no speech)";
	return turns.map((t) => `[${t.start.toFixed(1)}–${t.end.toFixed(1)}s] ${t.text}`).join("\n");
}

export function telemetryText(events: TelemetryEvent[]): string {
	if (events.length === 0) return "(no events)";
	return events
		.map((e) => [`[${e.t.toFixed(1)}s] ${e.type}`, ...Object.entries(e.data).map(([k, v]) => `${k}=${JSON.stringify(v)}`)].join(" "))
		.join("\n");
}

// The strict output format. `$schema` is dropped: it is metadata, not part of the format.
const { $schema, ...OUTPUT_SCHEMA } = z.toJSONSchema(ModelOutput);

/** The one /v1/responses body. `retryError` is the previous attempt's validation error. */
export function modelRequest(a: {
	config: AnalysisConfig;
	prompt: string;
	meta: SessionMeta;
	fileId: string;
	turns: TranscriptTurn[];
	events: TelemetryEvent[];
	retryError?: string;
}): Record<string, unknown> {
	const { config, meta } = a;
	const text = (t: string) => ({ type: "input_text", text: t });
	const content = [
		text(a.prompt),
		{ type: "input_video", file_id: a.fileId, fps: config.fps },
		text(`Session ${meta.id}: ${meta.game}${meta.build ? `, build ${meta.build}` : ""}. It lasts ${meta.duration.toFixed(1)} s.`),
		...(config.include_transcript ? [text(`Think-aloud transcript, one turn per line, [start–end] in session seconds:\n${transcriptText(a.turns)}`)] : []),
		...(config.include_telemetry ? [text(`Telemetry, one event per line, [time] type then its data, in session seconds:\n${telemetryText(a.events)}`)] : []),
		...(a.retryError ? [text(`Your previous answer was rejected because it did not match the schema:\n${a.retryError}\nAnswer again with JSON that matches the schema exactly.`)] : []),
	];
	return {
		model: MODEL,
		input: [{ role: "user", content }],
		text: { format: { type: "json_schema", name: "playtest_findings", strict: true, schema: OUTPUT_SCHEMA } },
		max_output_tokens: 32000,
	};
}
