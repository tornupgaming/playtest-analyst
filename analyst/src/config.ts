// An analysis config: plain data naming one way to analyse a session, so runs can be
// compared config by config (TUG-121). Lives in analyst/configs/*.json.
import { dirname, resolve } from "node:path";
import { z } from "zod";

export const AnalysisConfig = z.strictObject({
	/** Written into report.json as `config`. */
	name: z.string(),
	/** Prompt file. In a config file it is relative to that file; loadConfig makes it absolute. */
	prompt: z.string(),
	/** Frame sampling for input_video. Below 1, short events are missed (wiki: muse-wonder-video). */
	fps: z.number().positive(),
	/** Send the ASR transcript as timestamped text. */
	include_transcript: z.boolean(),
	/** Send events.jsonl as a text timeline. */
	include_telemetry: z.boolean(),
	/** Upload the video with its mic track instead of silent. The fallback when ASR fails;
	 * speech timing from the track is loose (DECISIONS.md §4). */
	video_audio: z.boolean(),
});
export type AnalysisConfig = z.infer<typeof AnalysisConfig>;

export async function loadConfig(path: string): Promise<AnalysisConfig> {
	const config = AnalysisConfig.parse(await Bun.file(path).json());
	return { ...config, prompt: resolve(dirname(path), config.prompt) };
}

export const DEFAULT_CONFIG = resolve(import.meta.dir, "../configs/v0.json");
