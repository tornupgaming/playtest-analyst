// What comes from outside the program: JSON files and the API key. Failures here are the
// user's to fix, so they are UserErrors, which the CLI prints as one line with no stack trace.
import { existsSync } from "node:fs";
import { z } from "zod";

export class UserError extends Error {}

/** `text` parsed as JSON against `schema`. `where` (a path, or a path and line) starts the error. */
export function parseJson<T>(text: string, schema: z.ZodType<T>, where: string): T {
	let json: unknown;
	try {
		json = JSON.parse(text);
	} catch (err) {
		throw new UserError(`${where}: not JSON: ${(err as Error).message}`);
	}
	const parsed = schema.safeParse(json);
	if (!parsed.success) throw new UserError(`${where}: ${parsed.error.issues.map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`).join("; ")}`);
	return parsed.data;
}

export async function readJson<T>(path: string, schema: z.ZodType<T>): Promise<T> {
	if (!existsSync(path)) throw new UserError(`${path}: not found`);
	return parseJson(await Bun.file(path).text(), schema, path);
}

/** Commands that call the API check this first, so a missing key fails before any encoding. */
export function apiKey(): string {
	const key = process.env.META_MODEL_API_KEY;
	if (!key) throw new UserError("META_MODEL_API_KEY is not set. Put your Meta Model API key in it and run again.");
	return key;
}
