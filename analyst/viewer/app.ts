/// <reference lib="dom" />
import type { ViewerSession } from "../src/commands/serve.ts";
import type { Category, Finding } from "../src/schema.ts";

type Span = { t0: number; t1: number };

const { meta, events, report, patches, transcript } = (await (await fetch("session.json")).json()) as ViewerSession;
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

type Child = Node | string | null | false | undefined;
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
const span = (s: Span) => ({ left: pct(s.t0), width: `calc(${pct(Math.max(s.t1 - s.t0, duration / 400))} - 3px)` });
const accent = (c: Category) => `var(--${c})`;
const label = (c: Category) => (c === "ui" ? "UI" : c[0]!.toUpperCase() + c.slice(1));
/** Hover text: a time line in small mono, then the words. */
const tip = (time: string, text: string) => ({ "data-time": time, "data-tip": text });

const ICONS = {
	fall: "M8 2v11M3.5 8.5 8 13l4.5-4.5",
	enemy: "M8 1.5c-3.3 0-5.5 2.3-5.5 5.3 0 1.9.9 3.2 2 3.9V13a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1v-2.3c1.1-.7 2-2 2-3.9 0-3-2.2-5.3-5.5-5.3ZM6 6.2a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8ZM10 6.2a1.4 1.4 0 1 0 0 2.8 1.4 1.4 0 0 0 0-2.8ZM7.1 11.6h.7v2.4h-.7ZM8.6 11.6h.7v2.4h-.7Z",
	sound: "M2.5 6H5l3.5-3v10L5 10H2.5ZM11 5.5a3.5 3.5 0 0 1 0 5M12.8 3.5a6.2 6.2 0 0 1 0 9",
	muted: "M2.5 6H5l3.5-3v10L5 10H2.5ZM11 6l3.5 4M14.5 6 11 10",
	death: "M4 4l8 8M12 4l-8 8",
	prev: "M10 3.5 5.5 8l4.5 4.5",
	next: "M6 3.5 10.5 8 6 12.5",
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
video.onerror = () => ($("#no-video").hidden = false);
const seek = (t: number, play = true) => {
	video.currentTime = Math.min(Math.max(t, 0), duration);
	if (play) video.play();
};
/** A finding the user picked. It stays open while the playhead is inside it, even when
 * another finding overlaps or starts at the same time. */
let pinned: Finding | undefined;
const open = (f: Finding) => ((pinned = f), seek(f.t_start));
/** Enter opens a focused timeline marker, as a click does. */
const onEnter = (f: Finding) => (e: KeyboardEvent) => e.key === "Enter" && e.target === e.currentTarget && open(f);
const toggle = () => (video.paused ? video.play() : video.pause());
video.onclick = toggle;
$("#play").onclick = toggle;
$("#mute").append(icon("sound"), icon("muted"));
$("#mute").onclick = () => (video.muted = !video.muted);
/** The previous or next finding from the one open, wrapping round. */
const step = (by: number) => findings.length > 0 && open(findings[(findings.indexOf(shown!) + by + findings.length) % findings.length]!);
$("#prev").append(icon("prev"));
$("#prev").onclick = () => step(-1);
$("#next").append(icon("next"));
$("#next").onclick = () => step(1);
document.addEventListener("keydown", (e) => {
	if ((e.target as HTMLElement).closest("button, summary")) return;
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
const stat = (name: string, value: string) => h("div", {}, h("dt", {}, name), h("dd", {}, value));
$("#usage").append(
	stat("Model", report.model),
	stat("Tokens", `${((usage.input_tokens + usage.output_tokens) / 1000).toFixed(1)}k`),
	stat("Took", `${Math.round(usage.latency_s)} s`),
	stat("Cost", `$${usage.cost_usd.toFixed(2)}`),
);
const { comparison } = report;
if (comparison) {
	const { counts } = comparison;
	const count = (n: number, name: string) => h("span", { class: name }, h("b", {}, String(n)), name);
	$("#compare summary").append(count(counts.resolved, "resolved"), count(counts.new, "new"), count(counts.persisting, "persisting"));
	$("#compare summary").title = `Compared with the previous build, session ${comparison.previous_session}`;
	// The previous build's findings this session no longer shows, so a fully fixed build reads as a result.
	$("#compare .resolved-list").append(
		h("h3", {}, `Resolved since ${comparison.previous_session}`),
		...comparison.resolved.map((r) => h("p", { title: `${comparison.previous_session} ${r.id}` }, h("i", { class: "dot", style: { "--accent": accent(r.category) } }), r.summary)),
		...(comparison.resolved.length === 0 ? [h("p", {}, "Nothing yet.")] : []),
	);
	$("#compare").hidden = false;
}

// --- Timeline ---------------------------------------------------------------

const ticks: HTMLElement[] = [];
const tickStep = duration > 900 ? 120 : duration > 300 ? 60 : 30;
for (let t = 0; t <= duration; t += tickStep) ticks.push(h("span", { class: "tick", style: { left: pct(t) } }, clock(t)));

const zoneBands = zones.map((z, i) =>
	h("div", { class: `zone ${i % 2 ? "odd" : ""}`, style: span(z), ...tip(`${clock(z.t0)}–${clock(z.t1)}`, z.zone) }, (z.t1 - z.t0) / duration > 0.035 && z.zone),
);

const ROW = 30;
const markers = new Map<Finding, HTMLElement>();
for (const [i, f] of findings.entries()) {
	const el = h(
		"div",
		{
			class: "mark",
			style: { ...span({ t0: f.t_start, t1: f.t_end }), top: `${rows.get(f)! * ROW}px`, "--accent": accent(f.category) },
			...tip(`${clock(f.t_start)}–${clock(f.t_end)} · ${label(f.category)}`, f.summary),
			tabindex: 0,
			role: "button",
			"aria-label": `${label(f.category)} finding at ${clock(f.t_start)}: ${f.summary}`,
			onpointerdown: (e: Event) => (e.stopPropagation(), open(f)),
			onkeydown: onEnter(f),
		},
		String(i + 1),
	);
	markers.set(f, el);
}

const causeIcon = (cause: string) => icon(cause === "fall" || cause === "enemy" ? cause : "death");
const died = (cause: string) => (cause === "fall" ? "Died: fell" : cause === "enemy" ? "Died: enemy" : `Died: ${cause}`);
const moments = [
	...idles.map((s) => h("i", { class: "moment idle", style: { left: pct(s.t0), width: pct(s.t1 - s.t0) }, ...tip(clock(s.t0), `No input for ${(s.t1 - s.t0).toFixed(1)} s`) })),
	...transcript.map((l) => h("i", { class: "moment said", style: { left: pct(l.start) }, ...tip(clock(l.start), `“${l.text}”`) })),
	...objectives.map((e) => h("i", { class: "moment objective", style: { left: pct(e.t) }, ...tip(clock(e.t), `New objective: ${e.data.text ?? ""}`) })),
	...deaths.map((e) => {
		const cause = String(e.data.cause ?? "unknown");
		return h("i", { class: "moment death", style: { left: pct(e.t) }, ...tip(clock(e.t), died(cause)) }, causeIcon(cause));
	}),
];

const playhead = h("div", { class: "playhead" });
const lanes = h(
	"div",
	{ class: "lanes" },
	h("div", { class: "lane" }, ...ticks),
	h("div", { class: "lane" }, ...zoneBands),
	h("div", { class: "lane" }, ...markers.values()),
	h("div", { class: "lane" }, ...moments),
	playhead,
);
const timeline = $("#timeline");
timeline.style.setProperty("--findings-height", `${Math.max(rowEnds.length, 1) * ROW - 4}px`);
const trackLabel = (row: number, name: string) => h("span", { class: "label", style: { "grid-row": String(row) } }, name);
timeline.append(trackLabel(2, "Areas"), trackLabel(3, "Findings"), trackLabel(4, "Moments"), lanes);

const categories = [...new Set(findings.map((f) => f.category))];
const causes = [...new Set(deaths.map((e) => String(e.data.cause ?? "unknown")))];
const key = (marker: Node, text: string) => h("span", {}, marker, text);
$("#legend").append(
	...[
		...categories.map((c) => key(h("i", { class: "dot", style: { "--accent": accent(c) } }), label(c))),
		h("span", { class: "gap" }),
		...causes.map((c) => key(h("i", { class: "moment death" }, causeIcon(c)), died(c))),
		transcript.length > 0 && key(h("i", { class: "moment said" }), "Player spoke (hover to read)"),
		objectives.length > 0 && key(h("i", { class: "moment objective" }), "New objective"),
		idles.length > 0 && key(h("i", { class: "moment idle" }), "No input"),
	].filter((c) => !!c),
);

const scrub = (e: PointerEvent) => {
	const r = lanes.getBoundingClientRect();
	seek(((e.clientX - r.left) / r.width) * duration, false);
};
lanes.addEventListener("pointerdown", (e) => (lanes.setPointerCapture(e.pointerId), scrub(e)));
lanes.addEventListener("pointermove", (e) => lanes.hasPointerCapture(e.pointerId) && scrub(e));

const tipBox = $("#tip");
document.addEventListener("mouseover", (e) => {
	const el = (e.target as HTMLElement).closest<HTMLElement>("[data-tip]");
	if (!el) return;
	tipBox.replaceChildren(h("b", {}, el.dataset.time!), el.dataset.tip!);
	const r = el.getBoundingClientRect();
	tipBox.style.left = `${Math.min(innerWidth - 170, Math.max(170, r.left + r.width / 2))}px`;
	tipBox.style.top = `${r.top - 8}px`;
	tipBox.style.opacity = "1";
});
document.addEventListener("mouseout", (e) => (e.target as HTMLElement).closest("[data-tip]") && (tipBox.style.opacity = "0"));

// --- Inspector --------------------------------------------------------------

/** Relative URLs, so the viewer works from `serve` and from a static copy made by `export`. */
const frameSrc = (f: Finding) => (f.annotated_frame ? `files/${f.annotated_frame}` : `frames/${f.highlight?.t ?? f.t_start}.jpg`);

/** The changed lines of a unified diff, without its file header. */
function diffLines(diff: string) {
	return diff
		.split("\n")
		.filter((l) => /^[-+@]/.test(l) && !/^(---|\+\+\+) /.test(l))
		.map((l) => h("div", { class: l[0] === "+" ? "add" : l[0] === "-" ? "del" : "hunk" }, l));
}

function detail(f: Finding) {
	const stamp = (t: number) => h("button", { class: "stamp", onclick: () => seek(t) }, clock(t));
	// The phrasing SAM matched, else the model's first.
	const phrase = f.highlight && (f.annotated_prompt ?? f.highlight.prompts[0]!);
	const patch = patches.find((p) => p.finding_id === f.id);
	// Compare mode: whether the previous build had this finding too.
	const build =
		comparison &&
		(f.previous_id
			? h("span", { class: "chip persisting", title: `${comparison.previous_session} ${f.previous_id}` }, "persisting")
			: h("span", { class: "chip new" }, "new"));
	return [
		h(
			"figure",
			{ class: "frame" },
			h("img", { src: frameSrc(f), alt: phrase || "key frame" }),
			h(
				"figcaption",
				{},
				phrase ? h("span", { class: "prompt" }, `“${phrase}”`) : h("span", { hidden: "" }),
				h("span", { class: "source" }, `${f.annotated_frame ? "Outlined by SAM 3.1" : "Key frame"} · ${clock(f.annotated_t ?? f.highlight?.t ?? f.t_start)}`),
			),
		),
		h(
			"div",
			{ class: "chips" },
			h("span", { class: "chip category" }, h("i", { class: "dot" }), label(f.category)),
			f.reaction && h("span", { class: "chip" }, f.reaction),
			h("span", { class: `chip ${f.severity}` }, `${f.severity} severity`),
			build,
		),
		h("div", { class: "where" }, h("span", { class: "range" }, `${clock(f.t_start)} – ${clock(f.t_end)}`), f.zone && h("span", {}, `in ${f.zone}`)),
		h("p", { class: "summary" }, f.summary),
		h("h3", {}, "Suggested fix"),
		h("div", { class: "fix" }, f.suggested_fix),
		patch && h("div", { class: "diff" }, h("div", { class: "file" }, patch.file), ...diffLines(patch.diff)),
		patch && h("p", { class: "note" }, "Apply it from the Playtest dock in Godot."),
		f.evidence.quotes.length > 0 && h("h3", {}, "What the player said"),
		...f.evidence.quotes.map((q) => h("blockquote", {}, stamp(q.t), `“${q.text}”`)),
		f.evidence.telemetry.length > 0 && h("h3", {}, "What the game recorded"),
		f.evidence.telemetry.length > 0 && h("ul", { class: "log" }, ...f.evidence.telemetry.map((t) => h("li", {}, t))),
		f.evidence.visual && h("h3", {}, "What the video shows"),
		f.evidence.visual && h("p", { class: "visual" }, f.evidence.visual),
	];
}

const ambient = $<HTMLImageElement>("#ambient");
const inspector = $("#detail");
/** The finding in the inspector. The first one before playback reaches any, and afterwards the
 * last one the playhead was in, so it can still be read between findings. */
let shown: Finding | undefined;
function show(f: Finding) {
	if (shown) markers.get(shown)!.classList.remove("active");
	shown = f;
	markers.get(f)!.classList.add("active");
	inspector.style.setProperty("--accent", accent(f.category));
	inspector.replaceChildren(...detail(f).filter((c): c is HTMLElement => !!c));
	inspector.scrollTop = 0;
	ambient.src = frameSrc(f);
	const position = `${findings.indexOf(f) + 1} of ${findings.length}`;
	$("#count").textContent = position;
	$("#position").textContent = position;
}
if (findings[0]) show(findings[0]);
else inspector.append(h("p", { class: "empty" }, "No findings: the player got through without a struggle worth reporting."));

// --- Playback state ---------------------------------------------------------

/** The finding under the playhead, shown in the transport bar. */
let live: Finding | undefined;
function frame() {
	const t = video.currentTime;
	playhead.style.left = pct(t);
	$("#clock").replaceChildren(clock(t), h("span", {}, ` / ${clock(duration)}`));
	document.body.classList.toggle("playing", !video.paused);
	document.body.classList.toggle("muted", video.muted);
	if (pinned && (t < pinned.t_start || t > pinned.t_end)) pinned = undefined;
	const active = pinned ?? findingAt(t);
	if (active && active !== shown) show(active);
	if (active !== live) {
		live = active;
		for (const [f, el] of markers) el.classList.toggle("live", f === active);
		$("#now").replaceChildren(...(active ? [h("i", { class: "dot", style: { "--accent": accent(active.category) } }), h("b", {}, label(active.category)), h("span", {}, active.summary)] : []));
	}
	requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
