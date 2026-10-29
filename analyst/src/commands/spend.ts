// `playtest spend`: the Meta API spend so far, read from the spend ledger (src/meta.ts).
import { spentUsd } from "../meta.ts";

export const description = "Show Meta API spend so far against the cap";

export async function run() {
	const cap = Number(process.env.PLAYTEST_SPEND_CAP_USD ?? 20);
	console.log(`$${spentUsd().toFixed(2)} of $${cap.toFixed(2)}`);
}
