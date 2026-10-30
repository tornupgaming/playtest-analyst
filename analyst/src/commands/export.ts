// `playtest export`: the report viewer, report and a smaller video as a folder any static host can serve.
import { copyFile, mkdir, readdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { UserError } from "../boundary.ts";
import { extract, viewerSession } from "./serve.ts";

export const description = "Write the report viewer for a session as a static website";

/** Writes the same paths `serve` answers (session.json, video.mp4, files/…, frames/<t>.jpg), so
 * any static host can serve the folder. Nothing else from the bundle is copied: no audio, no
 * request dumps from analysis/, no local paths. */
export async function run(argv: string[]) {
	const { positionals } = parseArgs({ args: argv, allowPositionals: true });
	if (positionals.length !== 2) {
		console.error("Usage: playtest export <session dir> <out dir>");
		return 2;
	}
	const [dir, out] = positionals.map((p) => resolve(p)) as [string, string];
	const session = await viewerSession(dir);
	const { report } = session;
	const video = join(dir, "video.mp4");
	if (!(await Bun.file(video).exists())) throw new UserError(`No video.mp4 in ${dir}; run \`playtest finalize\` first.`);

	// Never delete: a mistyped out dir could be the session itself.
	if ((await readdir(out).catch(() => [])).length > 0) throw new UserError(`${out} is not empty; pick a new folder.`);
	const build = await Bun.build({ entrypoints: [join(import.meta.dir, "../../viewer/index.html")], outdir: out, minify: true });
	if (!build.success) throw new AggregateError(build.logs, "viewer build failed");
	await Bun.write(join(out, "session.json"), JSON.stringify(session));

	for (const f of report.findings) {
		if (f.annotated_frame) {
			await mkdir(dirname(join(out, "files", f.annotated_frame)), { recursive: true });
			await copyFile(join(dir, f.annotated_frame), join(out, "files", f.annotated_frame));
		} else {
			// The same time the viewer asks for.
			const t = f.highlight?.t ?? f.t_start;
			await Bun.write(join(out, "frames", `${t}.jpg`), await extract(video, t));
		}
	}

	// 720p H.264 at CRF 34 keeps on-screen text readable at about a quarter of the recording's
	// size; faststart puts the index first, so the player starts before the download ends.
	const ffmpeg = Bun.spawn(
		["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", video, "-vf", "scale=-2:'min(720,ih)'", "-c:v", "libx264", "-preset", "slow", "-crf", "34", "-c:a", "aac", "-b:a", "48k", "-ac", "1", "-movflags", "+faststart", join(out, "video.mp4")],
		{ stdout: "inherit", stderr: "inherit" },
	);
	if ((await ffmpeg.exited) !== 0) throw new UserError("ffmpeg could not re-encode video.mp4");
	console.log(`Static viewer: ${out}`);
}
