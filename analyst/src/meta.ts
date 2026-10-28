// The only way to call the Meta Model API. Every call is checked against the spend cap
// before it runs and written to the spend ledger after (DECISIONS.md §7).
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import OpenAI from "openai";
import { z } from "zod";
import { apiKey, UserError } from "./boundary.ts";

/** Override for tests: point it at a local fake. */
export const API_BASE = process.env.META_API_BASE ?? "https://api.meta.ai/v1";

/** $ per 1M tokens. https://dev.meta.ai/docs/pricing-rate-limits */
const PRICES: Record<string, { input: number; cached: number; output: number }> = {
	"muse-wonder-1.0": { input: 4.0, cached: 0.2, output: 20.0 },
	"muse-spark-1.3": { input: 1.25, cached: 0.15, output: 4.25 },
};

/** $ per image. SAM is billed per image, not per token; `usage.images_processed` counts them.
 * https://dev.meta.ai/docs/pricing-rate-limits */
const PRICE_PER_IMAGE: Record<string, number> = { "sam-3.1": 2.5 / 1000 };

const LEDGER =
	process.env.PLAYTEST_SPEND_LEDGER ??
	join(process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"), "playtest-analyst/spend.jsonl");
const CAP_USD = Number(process.env.PLAYTEST_SPEND_CAP_USD ?? 20);
/** Calls to models with no known price (ASR, …) can't count against CAP_USD, so they get their own cap. */
const UNPRICED_CALL_CAP = Number(process.env.PLAYTEST_UNPRICED_CALL_CAP ?? 200);

type LedgerEntry = {
	ts: string;
	model: string;
	endpoint: string;
	input_tokens: number;
	cached_tokens: number;
	output_tokens: number;
	cost_usd: number;
	/** True when the model has no price in PRICES, so cost_usd is 0 and the real cost is unknown. */
	unpriced: boolean;
	note?: string;
};

function ledger(): LedgerEntry[] {
	if (!existsSync(LEDGER)) return [];
	return readFileSync(LEDGER, "utf8")
		.split("\n")
		.filter(Boolean)
		.map((line) => JSON.parse(line) as LedgerEntry);
}

export function spentUsd(): number {
	return ledger().reduce((sum, e) => sum + e.cost_usd, 0);
}

/** Checked before each call, so calls running concurrently can overshoot the cap by their own cost. */
function assertBudget(): void {
	const entries = ledger();
	const spent = entries.reduce((sum, e) => sum + e.cost_usd, 0);
	if (spent >= CAP_USD) {
		throw new UserError(`Spend cap reached: $${spent.toFixed(2)} of $${CAP_USD} (ledger ${LEDGER}). Raise PLAYTEST_SPEND_CAP_USD to continue.`);
	}
	const unpriced = entries.filter((e) => e.unpriced).length;
	if (unpriced >= UNPRICED_CALL_CAP) {
		throw new UserError(`Unpriced call cap reached: ${unpriced} calls (ledger ${LEDGER}). Raise PLAYTEST_UNPRICED_CALL_CAP to continue.`);
	}
}

export function costUsd(model: string, input: number, cached: number, output: number): number | null {
	const p = PRICES[model];
	if (!p) return null;
	return ((input - cached) * p.input + cached * p.cached + output * p.output) / 1e6;
}

function charge(model: string, endpoint: string, tokens: { input: number; cached: number; output: number }, note?: string, images = 0): number {
	const cost = model in PRICE_PER_IMAGE ? images * PRICE_PER_IMAGE[model]! : costUsd(model, tokens.input, tokens.cached, tokens.output);
	const entry: LedgerEntry = {
		ts: new Date().toISOString(),
		model,
		endpoint,
		input_tokens: tokens.input,
		cached_tokens: tokens.cached,
		output_tokens: tokens.output,
		cost_usd: cost ?? 0,
		unpriced: cost === null,
		...(note ? { note } : {}),
	};
	mkdirSync(dirname(LEDGER), { recursive: true });
	appendFileSync(LEDGER, JSON.stringify(entry) + "\n");
	return entry.cost_usd;
}

let _client: OpenAI | undefined;
function client(): OpenAI {
	return (_client ??= new OpenAI({ baseURL: API_BASE, apiKey: apiKey() }));
}

export type Responded = { response: OpenAI.Responses.Response; costUsd: number; latencyS: number };

/** POST /v1/responses. `body` is loosely typed because Meta's `input_video` part isn't in the SDK's types. */
export async function respond(body: Record<string, unknown>, note?: string): Promise<Responded> {
	assertBudget();
	const started = performance.now();
	const response = (await client().responses.create(body as never)) as OpenAI.Responses.Response;
	const latencyS = (performance.now() - started) / 1000;
	const u = response.usage;
	const costUsd = charge(String(body.model), "responses", {
		input: u?.input_tokens ?? 0,
		cached: u?.input_tokens_details?.cached_tokens ?? 0,
		output: u?.output_tokens ?? 0,
	}, note, (u as { images_processed?: number } | undefined)?.images_processed);
	return { response, costUsd, latencyS };
}

/** POST /v1/files (purpose user_data). Uploads are free, so they aren't charged. */
export async function uploadFile(path: string, expiresAfterS = 86400): Promise<string> {
	const file = await client().files.create({
		file: Bun.file(path) as unknown as File,
		purpose: "user_data",
		expires_after: { anchor: "created_at", seconds: expiresAfterS },
	} as never);
	return file.id;
}

/** The response's output text parsed as JSON against `schema`, or an error saying why it can't be,
 * worded for the model so a caller can send it back in a retry. */
export function outputJson<T>(response: OpenAI.Responses.Response, schema: z.ZodType<T>): T {
	if (response.status === "incomplete") throw new Error(`The response is incomplete (${response.incomplete_details?.reason ?? "no reason given"}).`);
	const text = response.output.flatMap((o) => (o.type === "message" ? o.content : [])).find((c) => c.type === "output_text")?.text;
	if (text === undefined) throw new Error("The response has no output_text.");
	let json: unknown;
	try {
		json = JSON.parse(text);
	} catch (err) {
		throw new Error(`The output is not JSON: ${(err as Error).message}`);
	}
	const parsed = schema.safeParse(json);
	if (!parsed.success) throw new Error(z.prettifyError(parsed.error));
	return parsed.data;
}

/** Retries after a 429, a 5xx, a timeout or a network error, waiting RETRY_DELAY_MS, then double, … */
const RETRIES = 3;
const RETRY_DELAY_MS = Number(process.env.PLAYTEST_RETRY_DELAY_MS ?? 2000);
/** A 10-minute ASR chunk took 57 s (wiki: meta-asr). */
const TIMEOUT_MS = 180_000;

/** Any other endpoint (ASR, …) that the SDK doesn't cover. Retried on transient failures, as the
 * SDK does for the other calls. Each attempt is recorded as one call at the model's price (zero
 * tokens), which for a model missing from PRICES is an unpriced call. */
export async function metaFetch(path: string, init: RequestInit, model: string, note?: string): Promise<Response> {
	const headers = new Headers(init.headers);
	headers.set("Authorization", `Bearer ${apiKey()}`);
	for (let attempt = 0; ; attempt++) {
		assertBudget();
		const res = await fetch(`${API_BASE}${path}`, { ...init, headers, signal: AbortSignal.timeout(TIMEOUT_MS) }).catch((err: Error) => err);
		charge(model, path, { input: 0, cached: 0, output: 0 }, note);
		const failure = res instanceof Error ? res.message : res.status === 429 || res.status >= 500 ? `HTTP ${res.status}` : null;
		if (failure === null || attempt === RETRIES) {
			if (res instanceof Error) throw res;
			return res;
		}
		const delay = RETRY_DELAY_MS * 2 ** attempt;
		console.error(`${note ?? path}: ${failure}; retrying in ${delay / 1000} s`);
		await Bun.sleep(delay);
	}
}
