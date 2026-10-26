// Seam (a), bundle → model input: finalize's offsets, as pure functions and on real media.
import { describe, expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { alignAudio, alignVideo, finalize, run, streamStart } from "./finalize.ts";

describe("streamStart", () => {
	test("a declared start wins over the file's pts", () => {
		expect(streamStart(0.25, 1793045884.933, 1793045884.86487)).toBe(0.25);
	});
	test("without one, it is wall-clock pts minus t0_unix, to the millisecond", () => {
		expect(streamStart(undefined, 1793045884.933, 1793045884.86487)).toBe(0.068);
		expect(streamStart(undefined, 1793045883.716, 1793045884.86487)).toBe(-1.149);
	});
	test("a file with neither is an error", () => {
		expect(() => streamStart(undefined, null, 1000)).toThrow("no declared start");
	});
});

describe("align filters", () => {
	test("a late stream is padded, an early one trimmed, an on-time one only rebased", () => {
		expect(alignVideo(0.068)).toBe("setpts=PTS-STARTPTS,tpad=start_duration=0.068:start_mode=clone");
		expect(alignVideo(-1.5)).toBe("setpts=PTS-STARTPTS,trim=start=1.5,setpts=PTS-STARTPTS");
		expect(alignVideo(0)).toBe("setpts=PTS-STARTPTS");
		expect(alignAudio(0.5)).toBe("asetpts=PTS-STARTPTS,adelay=delays=500:all=1");
		expect(alignAudio(-1.149)).toBe("asetpts=PTS-STARTPTS,atrim=start=1.149,asetpts=PTS-STARTPTS");
	});
});

/** Time (s) of the first video frame brighter than mid-grey, sampled at `fps`. */
async function firstFlash(path: string, fps: number): Promise<number> {
	const proc = Bun.spawn(["ffmpeg", "-loglevel", "error", "-i", path, "-vf", `fps=${fps},scale=1:1,format=gray`, "-f", "rawvideo", "-"]);
	const bytes = new Uint8Array(await new Response(proc.stdout).arrayBuffer());
	return bytes.findIndex((b) => b > 128) / fps;
}

/** Time (s) of the first loud sample in a 16 kHz mono WAV, and its length. */
async function firstBeep(path: string): Promise<{ t: number; length: number }> {
	const proc = Bun.spawn(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-"]);
	const samples = new Int16Array(await new Response(proc.stdout).arrayBuffer());
	return { t: samples.findIndex((s) => Math.abs(s) > 3000) / 16000, length: samples.length / 16000 };
}

test("finalize moves a late wall-clock video and an early declared mic onto the session clock", async () => {
	const dir = mkdtempSync(join(tmpdir(), "finalize-"));
	// Video: a flash 1.0 s into the file, whose pts say it started 0.5 s after t0 → flash at 1.5 s.
	await run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=160x120:r=20:d=4,drawbox=c=white:t=fill:enable='between(t,1,1.3)'",
		"-c:v", "libx264", "-output_ts_offset", "1000.5", join(dir, "screen.mkv")]);
	// Mic: a beep 1.0 s into the file, declared to start 0.4 s before t0 → beep at 0.6 s.
	await run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "aevalsrc='if(between(t,1,1.2),0.5*sin(2*PI*1000*t),0)':s=48000:d=4",
		join(dir, "mic.wav")]);
	await Bun.write(join(dir, "session.json"), JSON.stringify({
		schema: 1, id: "t", started_at: "2026-10-26T00:00:00Z", t0_unix: 1000, duration: 3, game: "g", build: null, tester: null, profile: null,
		capture: { video: "screen.mkv", audio: "mic.wav", audio_start: -0.4 },
	}));

	await finalize(dir);

	expect(await firstFlash(join(dir, "video.mp4"), 20)).toBeCloseTo(1.5, 1);
	expect(await firstBeep(join(dir, "mic16k.wav"))).toEqual({ t: expect.closeTo(0.6, 2), length: 3 });
	// The muxed AAC track carries the same beep, aligned the same way.
	await run(["ffmpeg", "-loglevel", "error", "-i", join(dir, "video.mp4"), "-vn", "-ac", "1", "-ar", "16000", join(dir, "muxed.wav")]);
	expect((await firstBeep(join(dir, "muxed.wav"))).t).toBeCloseTo(0.6, 1);
});

test("finalize trims an early declared video and pads a late wall-clock mic", async () => {
	const dir = mkdtempSync(join(tmpdir(), "finalize-"));
	// Video: flash 1.0 s into the file, declared to start 0.5 s before t0 → flash at 0.5 s.
	await run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=160x120:r=20:d=4,drawbox=c=white:t=fill:enable='between(t,1,1.3)'",
		"-c:v", "libx264", join(dir, "screen.mkv")]);
	// Mic: beep 1.0 s into the file, whose pts say it started 0.25 s after t0 → beep at 1.25 s.
	await run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "aevalsrc='if(between(t,1,1.2),0.5*sin(2*PI*1000*t),0)':s=48000:d=4",
		"-c:a", "flac", "-output_ts_offset", "1000.25", join(dir, "mic.mka")]);
	await Bun.write(join(dir, "session.json"), JSON.stringify({
		schema: 1, id: "t", started_at: "2026-10-26T00:00:00Z", t0_unix: 1000, duration: 3, game: "g", build: null, tester: null, profile: null,
		capture: { video: "screen.mkv", video_start: -0.5, audio: "mic.mka" },
	}));

	await finalize(dir);

	expect(await firstFlash(join(dir, "video.mp4"), 20)).toBeCloseTo(0.5, 1);
	expect(await firstBeep(join(dir, "mic16k.wav"))).toEqual({ t: expect.closeTo(1.25, 2), length: 3 });
});
