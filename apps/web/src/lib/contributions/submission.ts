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

/** A bare digit string: the id fields below, never validated by the writer, must be this. */
const DIGITS = /^\d+$/;

/**
 * The triage key per source, and null for an envelope that cannot make one.
 *
 * A gossip envelope has no quest, by design -- it is an NPC saying something the corpus has
 * never heard -- so it keys on the creature id alone.
 *
 * This is a public, unauthenticated paste box, not a channel the addon controls: nothing stops
 * someone typing quest="npc" by hand, which -- unvalidated -- would produce "npc:12345" and
 * collide with a real gossip key for creature 12345. Every id component is therefore required
 * to be digits before it goes in the key; an envelope that fails this is malformed rather than
 * merely unlucky, so it is rejected outright rather than falling back to a different branch.
 *
 * `subzone` is free text from the client and can't be digit-checked, but that's safe here: once
 * `map` is digits-only it can never itself contain the ":" separator, so the first ":" in the
 * key always marks the exact end of `map` no matter what `subzone` contains (including more
 * colons). Two different (map, subzone) pairs can never produce the same key string.
 */
function keyFor(envelope: Envelope): string | null {
  const f = envelope.fields;
  if (envelope.source === "quests") {
    if (f.quest && f.event) return DIGITS.test(f.quest) ? `${f.quest}:${f.event}` : null;
    const npc = f.npc?.match(/^(\d+)/)?.[1];
    return npc ? `npc:${npc}` : null;
  }
  if (envelope.source === "books") {
    return f.page && DIGITS.test(f.page) ? f.page : null;
  }
  return f.map && DIGITS.test(f.map) && f.subzone ? `${f.map}:${f.subzone}` : null;
}

export function submissionFrom(envelope: Envelope, raw: string): Submission | null {
  const key = keyFor(envelope);
  if (!key) return null;

  if (envelope.source === "zones") {
    // Zones carries no text because the client has none to give; one that does wasn't written
    // by our addon, so it's rejected rather than silently kept under a key whose triage view
    // won't show it.
    if (envelope.text) return null;
  } else if (!envelope.text) {
    // For quests and books the text is the entire payload, so one without it is a report, not
    // a contribution.
    return null;
  }

  const { locale = "enUS", build = "", ...meta } = envelope.fields;
  const text = envelope.text ? normaliseText(envelope.text) : null;

  const dedup = createHash("sha256")
    .update([envelope.source, key, locale, text ?? ""].join("\u0000"))
    .digest("hex");

  return { source: envelope.source, key, locale, build, text, meta, raw, dedup };
}
