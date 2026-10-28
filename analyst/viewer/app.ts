/// <reference lib="dom" />
import type { Category, Finding, Report, SessionMeta, TelemetryEvent } from "../src/schema.ts";

type Session = { meta: SessionMeta; events: TelemetryEvent[]; report: Report };
type Span = { t0: number; t1: number };

const { meta, events, report } = (await (await fetch("session.json")).json()) as Session;
const findings = report.findings.toSorted((a, b) => a.t_start - b.t_start);
const duration = meta.duration;

// --- Derived telemetry ------------------------------------------------------

const zones: (Span & { zone: string })[] = [];
for (const e of events) {
	const zone = String(e.data.zone ?? "");
	if (e.type === "zone_enter") zones.push({ zone, t0: e.t, t1: duration });
	if (e.type === "zone_exit") {
		const open = zones.findLast((z) => z.zone === zone && z.t1 === duration);
		if (open) open.t1 = e.t;
	}
}
const idles = events.filter((e) => e.type === "input_idle").map((e) => ({ t0: e.t, t1: e.t + Number(e.data.duration ?? 0) }));
const deaths = events.filter((e) => e.type === "death");
const objectives = events.filter((e) => e.type === "objective_update");

/** Rows for the findings lane, so overlapping findings don't hide each other. */
const rows = new Map<Finding, number>();
const rowEnds: number[] = [];
for (const f of findings) {
	let row = rowEnds.findIndex((end) => end <= f.t_start);
	if (row === -1) row = rowEnds.length;
	rowEnds[row] = f.t_end;
	rows.set(f, row);
}

/** The finding under the playhead; the latest-starting one when they overlap. */
const findingAt = (t: number) => findings.findLast((f) => f.t_start <= t && t <= f.t_end);

// --- DOM helpers ------------------------------------------------------------

type Child = Node | string | null | false;
function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: Record<string, unknown> = {}, ...children: Child[]) {
	const el = document.createElement(tag);
	for (const [k, v] of Object.entries(props)) {
		if (k === "style") for (const [prop, value] of Object.entries(v as object)) el.style.setProperty(prop, value);
		else if (k.startsWith("on")) el.addEventListener(k.slice(2), v as EventListener);
		else el.setAttribute(k, String(v));
	}
	el.append(...children.filter((c): c is Node | string => !!c));
	return el;
}
const $ = <T extends HTMLElement>(sel: string) => document.querySelector<T>(sel)!;
const clock = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
const pct = (t: number) => `${(100 * Math.min(Math.max(t, 0), duration)) / duration}%`;
const span = (s: Span) => ({ left: pct(s.t0), width: pct(Math.max(s.t1 - s.t0, duration / 400)) });
const accent = (c: Category) => `var(--${c})`;
const label = (c: Category) => (c === "ui" ? "UI" : c[0]!.toUpperCase() + c.slice(1));

const ICONS = {
	fall: "M8 2v11M3.5 8.5 8 13l4.5-4.5",
	enemy: "M8 1.5c-3.3 0-5.5 2.3-5.5 5.3 0 1.9.9 3.2 2 3.9V13a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1v-2.3c1.1-.7 2-2 2-3.9 0-3-2.2-5.3-5.5-5.3ZM6 6.2a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8ZM10 6.2a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8ZM7.1 11.6h.7v2.4h-.7ZM8.6 11.6h.7v2.4h-.7Z",
	sound: "M2.5 6H5l3.5-3v10L5 10H2.5ZM11 5.5a3.5 3.5 0 0 1 0 5M12.8 3.5a6.2 6.2 0 0 1 0 9",
	muted: "M2.5 6H5l3.5-3v10L5 10H2.5ZM11 6l3.5 4M14.5 6 11 10",
	death: "M4 4l8 8M12 4l-8 8",
	quote: "M3 4h10v6H7l-3 3v-3H3z",
	telemetry: "M2 12h2l2-6 3 8 2-5 1 3h2",
	visual: "M1.5 8S4 3.5 8 3.5 14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8ZM8 10a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z",
	fix: "M10.5 2.5a3 3 0 0 0-3.9 3.9L2.5 10.5v3h3l4.1-4.1a3 3 0 0 0 3.9-3.9l-2 2-2-2 2-2Z",
};
function icon(name: keyof typeof ICONS) {
	const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
	svg.setAttribute("viewBox", "0 0 16 16");
	svg.setAttribute("class", `icon icon-${name}`);
	svg.innerHTML = `<path d="${ICONS[name]}"/>`;
	return svg;
}

// --- Video and transport ----------------------------------------------------

const video = $<HTMLVideoElement>("#video");
video.src = "video.mp4";
const seek = (t: number, play = true) => {
	video.currentTime = Math.min(Math.max(t, 0), duration);
	if (play) video.play();
};
/** A finding the user clicked. It stays open while the playhead is inside it, even when
 * another finding overlaps or starts at the same time. */
let pinned: Finding | undefined;
const open = (f: Finding) => ((pinned = f), seek(f.t_start));
const toggle = () => (video.paused ? video.play() : video.pause());
video.onclick = toggle;
$("#play").onclick = toggle;
$("#mute").append(icon("sound"), icon("muted"));
$("#mute").onclick = () => (video.muted = !video.muted);
document.addEventListener("keydown", (e) => {
	if (e.key === " ") (e.preventDefault(), toggle());
	if (e.key === "ArrowLeft") seek(video.currentTime - 5, !video.paused);
	if (e.key === "ArrowRight") seek(video.currentTime + 5, !video.paused);
});

// --- Header -----------------------------------------------------------------

const { usage } = report;
$("#session").append(
	h("strong", {}, meta.game),
	h("span", {}, meta.id),
	...(meta.profile ? [h("span", {}, meta.profile)] : []),
	h("span", {}, clock(duration)),
);
const stat = (label: string, value: string) => [h("dt", {}, label), h("dd", {}, value)];
$("#usage").append(
	...stat("model", report.model),
	...stat("tokens", `${((usage.input_tokens + usage.output_tokens) / 1000).toFixed(1)}k`),
	...stat("latency", `${Math.round(usage.latency_s)} s`),
	...stat("cost", `$${usage.cost_usd.toFixed(2)}`),
);
$("#count").textContent = String(findings.length);
const { comparison } = report;
if (comparison) {
	const { counts } = comparison;
	const count = (n: number, name: string) => h("span", { class: name }, h("b", {}, String(n)), ` ${name}`);
	$("#compare").append(count(counts.resolved, "resolved"), count(counts.new, "new"), count(counts.persisting, "persisting"));
	$("#compare").title = `Compared with the previous build, session ${comparison.previous_session}`;
	$("#compare").hidden = false;
}
/** Compare mode: whether the previous build had this finding too. */
const build = (f: Finding): Child =>
	!!comparison &&
	(f.previous_id
		? h("span", { class: "build persisting", title: `${comparison.previous_session} ${f.previous_id}` }, "persisting")
		: h("span", { class: "build new" }, "new"));

// --- Timeline ---------------------------------------------------------------

const categories = [...new Set(findings.map((f) => f.category))];
$("#legend").append(...categories.map((c) => h("span", { class: "chip", style: { "--accent": accent(c) } }, label(c))));

const ticks: HTMLElement[] = [];
const step = duration > 900 ? 120 : duration > 300 ? 60 : 30;
for (let t = 0; t <= duration; t += step) ticks.push(h("span", { class: "tick", style: { left: pct(t) } }, clock(t)));

const zoneBands = zones.map((z, i) =>
	h("div", { class: `zone ${i % 2 ? "odd" : ""}`, style: span(z), title: `${z.zone} ${clock(z.t0)}–${clock(z.t1)}` }, (z.t1 - z.t0) / duration > 0.035 && z.zone),
);

const ROW = 26;
const markers = new Map<Finding, HTMLElement>();
for (const f of findings) {
	const el = h("div", {
		class: "mark",
		style: { ...span({ t0: f.t_start, t1: f.t_end }), top: `${rows.get(f)! * ROW + 5}px`, "--accent": accent(f.category) },
		title: `${label(f.category)} · ${f.summary}`,
		onpointerdown: (e: Event) => (e.stopPropagation(), open(f)),
	});
	markers.set(f, el);
}

const deathIcon = (cause: string) => icon(cause === "fall" || cause === "enemy" ? cause : "death");
const telemetry = [
	...idles.map((s) => h("div", { class: "idle", style: span(s), title: `input idle ${(s.t1 - s.t0).toFixed(1)} s` })),
	...objectives.map((e) => h("div", { class: "objective", style: { left: pct(e.t) }, title: `objective: ${e.data.text ?? ""}` })),
	...deaths.map((e) => {
		const cause = String(e.data.cause ?? "unknown");
		return h("div", { class: "death", style: { left: pct(e.t) }, title: `death (${cause}) at ${clock(e.t)}` }, deathIcon(cause));
	}),
];
const causes = [...new Set(deaths.map((e) => String(e.data.cause ?? "unknown")))];

const playhead = h("div", { class: "playhead" });
const overlay = h("div", { class: "overlay" }, playhead);
const lane = (name: string, cls: string, children: Node[], style = {}) => [h("span", { class: "label" }, name), h("div", { class: `lane ${cls}`, style }, ...children)];
$("#timeline").append(
	...lane("", "axis", ticks),
	...lane("zones", "zones", zoneBands),
	...lane("findings", "marks", [...markers.values()], { height: `${Math.max(rowEnds.length, 1) * ROW + 4}px` }),
	...lane("telemetry", "telemetry", telemetry),
	overlay,
	h("span"),
	h(
		"div",
		{ class: "key" },
		...causes.map((c) => h("span", {}, h("i", { class: "death" }, deathIcon(c)), `death · ${c}`)),
		idles.length > 0 && h("span", {}, h("i", { class: "idle" }), "input idle"),
		objectives.length > 0 && h("span", {}, h("i", { class: "objective" }), "objective update"),
	),
);
const scrub = (e: PointerEvent) => {
	const r = overlay.getBoundingClientRect();
	seek(((e.clientX - r.left) / r.width) * duration, false);
};
const timeline = $("#timeline");
timeline.addEventListener("pointerdown", (e) => {
	if (e.clientX < overlay.getBoundingClientRect().left) return;
	timeline.setPointerCapture(e.pointerId);
	scrub(e);
});
timeline.addEventListener("pointermove", (e) => timeline.hasPointerCapture(e.pointerId) && scrub(e));

// --- Finding cards ----------------------------------------------------------

const cards = new Map<Finding, HTMLElement>();
for (const f of findings) {
	const stamp = (t: number) => h("button", { class: "stamp", onclick: (e: Event) => (e.stopPropagation(), seek(t)) }, clock(t));
	// Relative URLs, so the viewer works from `serve` and from a static copy made by `export`.
	const frameSrc = f.annotated_frame ? `files/${f.annotated_frame}` : `frames/${f.highlight?.t ?? f.t_start}.jpg`;
	// The phrasing SAM matched, else the model's first.
	const phrase = f.highlight && (f.annotated_prompt ?? f.highlight.prompts[0]!);
	const evidence = (name: "telemetry" | "visual", items: string[]) =>
		items.length > 0 && h("div", { class: "evidence" }, icon(name), h("ul", {}, ...items.map((t) => h("li", {}, t))));

	const card = h(
		"li",
		{ class: "card", style: { "--accent": accent(f.category) }, onclick: () => open(f) },
		h(
			"div",
			{ class: "card-head" },
			h("span", { class: "category" }, label(f.category)),
			f.reaction && h("span", { class: "reaction" }, f.reaction),
			h("span", { class: `severity ${f.severity}`, title: `${f.severity} severity` }, h("i"), h("i"), h("i"), f.severity),
			build(f),
			f.zone && h("span", { class: "zone-name" }, f.zone),
			h("span", { class: "range" }, `${clock(f.t_start)}–${clock(f.t_end)}`),
		),
		h("p", { class: "summary" }, f.summary),
		h(
			"div",
			{ class: "detail" },
			h(
				"figure",
				{ class: "frame" },
				h("img", { src: frameSrc, alt: phrase || "key frame" }),
				h(
					"figcaption",
					{},
					phrase && h("span", { class: "prompt" }, `“${phrase}”`),
					h("span", { class: "source" }, `${f.annotated_frame ? "SAM 3.1" : "key frame"} ${clock(f.annotated_t ?? f.highlight?.t ?? f.t_start)}`),
				),
			),
			...f.evidence.quotes.map((q) => h("blockquote", {}, stamp(q.t), h("span", {}, `“${q.text}”`))),
			evidence("telemetry", f.evidence.telemetry),
			evidence("visual", f.evidence.visual ? [f.evidence.visual] : []),
			h("div", { class: "fix" }, h("h3", {}, icon("fix"), "Suggested fix"), h("p", {}, f.suggested_fix)),
		),
	);
	cards.set(f, card);
	$("#findings").append(card);
}

// Compare mode: the previous build's findings this session no longer shows, so a fully fixed
// build reads as a result rather than an empty list.
if (comparison && comparison.resolved.length > 0) {
	$("#findings").append(
		h("li", { class: "resolved-head" }, `Resolved since ${comparison.previous_session}`),
		...comparison.resolved.map((r) =>
			h(
				"li",
				{ class: "card resolved", style: { "--accent": accent(r.category) }, title: `${comparison.previous_session} ${r.id}` },
				h("div", { class: "card-head" }, h("span", { class: "category" }, label(r.category)), h("span", { class: "build resolved" }, "resolved")),
				h("p", { class: "summary" }, r.summary),
			),
		),
	);
}

// --- Playback state ---------------------------------------------------------

let shown: Finding | undefined;
function frame() {
	const t = video.currentTime;
	playhead.style.left = pct(t);
	$("#clock").textContent = `${clock(t)} / ${clock(duration)}`;
	document.body.classList.toggle("playing", !video.paused);
	document.body.classList.toggle("muted", video.muted);
	if (pinned && (t < pinned.t_start || t > pinned.t_end)) pinned = undefined;
	const active = pinned ?? findingAt(t);
	// Keep the last finding open between findings, so it can still be read.
	if (active && active !== shown) {
		if (shown) (cards.get(shown)!.classList.remove("active"), markers.get(shown)!.classList.remove("active"));
		shown = active;
		cards.get(shown)!.classList.add("active");
		markers.get(shown)!.classList.add("active");
		cards.get(shown)!.scrollIntoView({ block: "nearest", behavior: "smooth" });
	}
	for (const [f, el] of markers) el.classList.toggle("live", f === active);
	requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
