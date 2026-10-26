/// <reference lib="dom" />
import type { Report, SessionMeta, TelemetryEvent } from "../src/schema.ts";

type Session = { meta: SessionMeta; events: TelemetryEvent[]; report: Report };

const session = (await (await fetch("/api/session")).json()) as Session;
const video = document.querySelector<HTMLVideoElement>("#video")!;
video.src = "/media/video.mp4";
const list = document.querySelector<HTMLOListElement>("#findings")!;

const clock = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

for (const f of session.report.findings.toSorted((a, b) => a.t_start - b.t_start)) {
	const li = document.createElement("li");
	li.className = `severity-${f.severity}`;
	li.innerHTML = `<time></time> <b></b> <span></span>`;
	li.querySelector("time")!.textContent = `${clock(f.t_start)}–${clock(f.t_end)}`;
	li.querySelector("b")!.textContent = `${f.severity} · ${f.category}`;
	li.querySelector("span")!.textContent = f.summary;
	li.onclick = () => {
		video.currentTime = f.t_start;
		video.play();
	};
	list.append(li);
}
