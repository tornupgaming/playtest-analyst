// `playtest finalize`: puts the raw capture on the session clock (DECISIONS.md §2).
// Writes video.mp4 (H.264 ≤720p + AAC mic) and mic16k.wav (16 kHz mono s16), both with
// t=0 at session t=0, so nothing downstream handles offsets again.
import { existsSync, renameSync, rmSync } from "node:fs";
import { join } from "node:path";
import { readJson, UserError } from "./boundary.ts";
import { SessionMeta } from "./schema.ts";

/** Session time of a stream's first frame or sample: the declared value, else the file's
 * wall-clock pts minus t0_unix (x11grab with -copyts stamps wall-clock pts). Rounded to 1 ms. */
export function streamStart(declared: number | undefined, ptsStart: number | null, t0Unix: number): number {
	const start = declared ?? (ptsStart === null ? null : ptsStart - t0Unix);
	if (start === null) throw new Error("stream has no declared start and no pts to derive it from");
	return Math.round(start * 1000) / 1000;
}

/** Filter chain that moves a video stream starting at session time `start` to t=0:
 * clone the first frame when it starts late, trim when it starts early. */
export function alignVideo(start: number): string {
	const reset = "setpts=PTS-STARTPTS";
	if (start > 0) return `${reset},tpad=start_duration=${start}:start_mode=clone`;
	if (start < 0) return `${reset},trim=start=${-start},${reset}`;
	return reset;
}

/** The same for audio: lead with silence when it starts late, trim when it starts early.
 * The delay is in whole ms: ffmpeg 9's adelay misreads fractional seconds ("0.5s" delays 0.5 ms). */
export function alignAudio(start: number): string {
	const reset = "asetpts=PTS-STARTPTS";
	if (start > 0) return `${reset},adelay=delays=${Math.round(start * 1000)}:all=1`;
	if (start < 0) return `${reset},atrim=start=${-start},${reset}`;
	return reset;
}

export async function run(cmd: string[]): Promise<string> {
	const proc = Bun.spawn(cmd, { stdout: "pipe", stderr: "pipe" });
	const [out, err, code] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited]);
	if (code !== 0) throw new Error(`${cmd[0]} exited ${code}: ${err.trim()}`);
	return out;
}

/** Wall-clock pts of the first stream of `kind` ("v" | "a"), or null when the file has none (e.g. WAV). */
async function ptsStart(path: string, kind: "v" | "a"): Promise<number | null> {
	const out = await run(["ffprobe", "-v", "error", "-select_streams", `${kind}:0`, "-show_entries", "stream=start_time", "-of", "csv=p=0", path]);
	const n = Number(out.trim());
	return out.trim() === "" || Number.isNaN(n) ? null : n;
}

export const finalized = (dir: string) => existsSync(join(dir, "video.mp4")) && existsSync(join(dir, "mic16k.wav"));

/** Re-encodes from the raw capture every time, so running it twice gives the same files.
 * Outputs are written under temporary names and renamed, so a failed run leaves no partial bundle.
 * The names are per process: the recorder finalizes on stop and Analyse may too, and two runs
 * sharing one temp file corrupt it. Each run writes a whole file and the last rename wins. */
export async function finalize(dir: string): Promise<void> {
	const meta = await readJson(join(dir, "session.json"), SessionMeta);
	const { capture, duration, t0_unix } = meta;
	const videoPath = join(dir, capture.video);
	if (!existsSync(videoPath)) throw new UserError(`No recording in ${dir}: it has neither video.mp4 and mic16k.wav nor ${capture.video} to make them from.`);
	// A start further out than the whole session means the pts weren't wall-clock (no -copyts).
	const start = (s: number, file: string) => {
		if (Math.abs(s) > duration) throw new Error(`${file} starts at ${s} s on a ${duration} s session; set its start in session.json`);
		return s;
	};
	const videoStart = start(streamStart(capture.video_start, await ptsStart(videoPath, "v"), t0_unix), videoPath);

	const inputs = ["-i", videoPath];
	let audio: string;
	if (capture.audio === null) {
		audio = "anullsrc=r=48000:cl=mono";
	} else {
		const audioPath = join(dir, capture.audio);
		const label = audioPath === videoPath ? "[0:a]" : "[1:a]";
		if (audioPath !== videoPath) inputs.push("-i", audioPath);
		audio = `${label}${alignAudio(start(streamStart(capture.audio_start, await ptsStart(audioPath, "a"), t0_unix), audioPath))}`;
	}

	const graph = [
		`[0:v]${alignVideo(videoStart)},scale=-2:'trunc(min(720,ih)/2)*2',format=yuv420p[v]`,
		`${audio},aresample=48000,apad,atrim=end=${duration},asplit=2[a1][a2]`,
	].join(";");
	const video = join(dir, `video.${process.pid}.tmp.mp4`);
	const mic = join(dir, `mic16k.${process.pid}.tmp.wav`);
	await run([
		"ffmpeg", "-y", "-loglevel", "error", ...inputs, "-filter_complex", graph,
		"-map", "[v]", "-map", "[a1]", "-t", String(duration), "-c:v", "libx264", "-preset", "veryfast",
		"-b:v", "2M", "-maxrate", "2.5M", "-bufsize", "4M", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", video,
		"-map", "[a2]", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-map_metadata", "-1", "-bitexact", mic,
	]).catch((err) => {
		for (const f of [video, mic]) rmSync(f, { force: true }); // else every failed run leaves its own
		throw err;
	});
	renameSync(video, join(dir, "video.mp4"));
	renameSync(mic, join(dir, "mic16k.wav"));
}
