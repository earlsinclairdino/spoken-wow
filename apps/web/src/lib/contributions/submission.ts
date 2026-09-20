/**
 * What an envelope becomes once it is accepted for storage.
 *
 * `key` is a triage key and never a frozen line id. `q:33:accept`, `b:{pageTextID}` and
 * `z:{mapID}` name lines that exist; a contribution is about one that does not, which is why a
 * page is keyed on the checksum its client computed. An id is assigned only if triage accepts
 * the row and the pipeline mints one.
 *
 * Server-side only: the hash below reaches for node:crypto, and the browser half of this lives
 * in contributions.ts.
 */
import { createHash } from "node:crypto";

import { normaliseText } from "@books-tools/lib/text.mjs";

import { checkEnvelope, type Submission } from "./contributions";
import type { Envelope } from "./envelope";

export function submissionFrom(envelope: Envelope, raw: string): Submission | null {
  // The key/text rules live in contributions.ts's checkEnvelope, not here, so the paste-box
  // preview can run the same check and refuse before Send rather than after a 400 -- see
  // ContributeForm.tsx's previewOf.
  const check = checkEnvelope(envelope);
  if (!check.ok) return null;

  const { locale = "enUS", build = "", ...meta } = envelope.fields;
  const text = envelope.text ? normaliseText(envelope.text) : null;

  const dedup = createHash("sha256")
    .update([envelope.source, check.key, locale, text ?? ""].join("\u0000"))
    .digest("hex");

  return { source: envelope.source, key: check.key, locale, build, text, meta, raw, dedup };
}
