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

import type { Submission } from "./contributions";
import type { Envelope } from "./envelope";

/**
 * The triage key per source, and null for an envelope that cannot make one.
 *
 * A gossip envelope has no quest, by design -- it is an NPC saying something the corpus has
 * never heard -- so it keys on the creature id alone.
 */
function keyFor(envelope: Envelope): string | null {
  const f = envelope.fields;
  if (envelope.source === "quests") {
    if (f.quest && f.event) return `${f.quest}:${f.event}`;
    const npc = f.npc?.match(/^(\d+)/)?.[1];
    return npc ? `npc:${npc}` : null;
  }
  if (envelope.source === "books") {
    return f.page ? f.page : null;
  }
  return f.map && f.subzone ? `${f.map}:${f.subzone}` : null;
}

export function submissionFrom(envelope: Envelope, raw: string): Submission | null {
  const key = keyFor(envelope);
  if (!key) return null;

  // Zones carries no text because the client has none to give. For the other two the text is
  // the entire reason the submission exists, so one without it is a report, not a contribution.
  const needsText = envelope.source !== "zones";
  if (needsText && !envelope.text) return null;

  const { locale = "enUS", build = "", ...meta } = envelope.fields;
  const text = envelope.text ? normaliseText(envelope.text) : null;

  const dedup = createHash("sha256")
    .update([envelope.source, key, locale, text ?? ""].join("\u0000"))
    .digest("hex");

  return { source: envelope.source, key, locale, build, text, meta, raw, dedup };
}
