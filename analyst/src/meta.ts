// The only way to call the Meta Model API. Every call is checked against the spend cap
// before it runs and written to the spend ledger after (DECISIONS.md §7).
import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import OpenAI from "openai";

/** Override for tests: point it at a local fake. */
export const API_BASE = process.env.META_API_BASE ?? "https://api.meta.ai/v1";

/** $ per 1M tokens. https://dev.meta.ai/docs/pricing-rate-limits */
const PRICES: Record<string, { input: number; cached: number; output: number }> = {
	"muse-wonder-1.0": { input: 4.0, cached: 0.2, output: 20.0 },
};

const LEDGER =
	process.env.PLAYTEST_SPEND_LEDGER ??
	join(process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state"), "playtest-analyst/spend.jsonl");
const CAP_USD = Number(process.env.PLAYTEST_SPEND_CAP_USD ?? 20);

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

export function spentUsd(): number {
	if (!existsSync(LEDGER)) return 0;
	return readFileSync(LEDGER, "utf8")
		.split("\n")
		.filter(Boolean)
		.reduce((sum, line) => sum + (JSON.parse(line) as LedgerEntry).cost_usd, 0);
}

function assertBudget(): void {
	const spent = spentUsd();
	if (spent >= CAP_USD) {
		throw new Error(`Spend cap reached: $${spent.toFixed(2)} of $${CAP_USD} (ledger ${LEDGER}). Raise PLAYTEST_SPEND_CAP_USD to continue.`);
	}
}

export function costUsd(model: string, input: number, cached: number, output: number): number | null {
	const p = PRICES[model];
	if (!p) return null;
	return ((input - cached) * p.input + cached * p.cached + output * p.output) / 1e6;
}

function charge(model: string, endpoint: string, tokens: { input: number; cached: number; output: number }, note?: string): number {
	const cost = costUsd(model, tokens.input, tokens.cached, tokens.output);
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
	const apiKey = process.env.META_MODEL_API_KEY;
	if (!apiKey) throw new Error("META_MODEL_API_KEY is not set");
	return (_client ??= new OpenAI({ baseURL: API_BASE, apiKey }));
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
	}, note);
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

/** Any other endpoint (ASR, …) that the SDK doesn't cover. Charged as one unpriced call
 * unless `tokens` is supplied by the caller from the response. */
export async function metaFetch(path: string, init: RequestInit, model: string, note?: string): Promise<Response> {
	assertBudget();
	const apiKey = process.env.META_MODEL_API_KEY;
	if (!apiKey) throw new Error("META_MODEL_API_KEY is not set");
	const res = await fetch(`${API_BASE}${path}`, {
		...init,
		headers: { Authorization: `Bearer ${apiKey}`, ...(init.headers ?? {}) },
	});
	charge(model, path, { input: 0, cached: 0, output: 0 }, note);
	return res;
}
