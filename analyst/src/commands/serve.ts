import { join, resolve, sep } from "node:path";
import { parseArgs } from "node:util";
import viewer from "../../viewer/index.html";
import { readSession } from "../bundle.ts";
import { Report } from "../schema.ts";

export const description = "Serve the report viewer for a session bundle";

export async function run(argv: string[]) {
	const { values, positionals } = parseArgs({
		args: argv,
		options: { port: { type: "string", default: "4173" } },
		allowPositionals: true,
	});
	if (positionals.length !== 1) {
		console.error("Usage: playtest serve <session dir> [--port N]");
		return 2;
	}
	const dir = resolve(positionals[0]!);
	const { meta, events } = await readSession(dir);
	const report = Report.parse(await Bun.file(join(dir, "report.json")).json());
	const video = join(dir, "video.mp4");
	if (!(await Bun.file(video).exists())) console.warn(`No video.mp4 in ${dir}; run \`playtest finalize\` first.`);

	const server = Bun.serve({
		hostname: "localhost",
		port: Number(values.port),
		development: false,
		// Fail if the port is taken, rather than share it with a stale viewer.
		reusePort: false,
		routes: {
			"/": viewer,
			"/api/session": Response.json({ meta, events, report }),
			// A file response: Bun answers Range requests, so the player can seek.
			"/media/video.mp4": new Response(Bun.file(video)),
			"/files/*": (req) => file(dir, decodeURIComponent(new URL(req.url).pathname.slice("/files/".length))),
			"/frame": (req) => frame(video, Number(new URL(req.url).searchParams.get("t"))),
		},
	});
	console.log(`Viewer: ${server.url}`);
	return new Promise<never>(() => {});
}

/** A file inside the bundle, such as an annotated frame. (`{ dir }` routes need `development: true` in Bun 1.4.) */
async function file(dir: string, rel: string): Promise<Response> {
	const path = resolve(dir, rel);
	const f = Bun.file(path);
	if (!path.startsWith(dir + sep) || !(await f.exists())) return new Response("Not found", { status: 404 });
	return new Response(f);
}

const frames = new Map<number, Promise<Uint8Array<ArrayBuffer>>>();

/** The key frame at session time `t` as a JPEG, for findings without an annotated frame. */
async function frame(video: string, t: number): Promise<Response> {
	if (!Number.isFinite(t) || t < 0) return new Response("t must be a time in seconds", { status: 400 });
	if (!frames.has(t)) frames.set(t, extract(video, t));
	try {
		const jpeg = await frames.get(t)!;
		return new Response(jpeg, { headers: { "Content-Type": "image/jpeg", "Cache-Control": "max-age=3600" } });
	} catch (err) {
		frames.delete(t);
		return new Response(String(err), { status: 500 });
	}
}

async function extract(video: string, t: number): Promise<Uint8Array<ArrayBuffer>> {
	const proc = Bun.spawn(
		["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", String(t), "-i", video, "-frames:v", "1", "-q:v", "3", "-f", "image2pipe", "-c:v", "mjpeg", "-"],
		{ stdout: "pipe", stderr: "pipe" },
	);
	const [jpeg, err, code] = await Promise.all([new Response(proc.stdout).bytes(), new Response(proc.stderr).text(), proc.exited]);
	if (code !== 0 || jpeg.length === 0) throw new Error(`ffmpeg: ${err || "no frame"}`);
	return jpeg;
}
