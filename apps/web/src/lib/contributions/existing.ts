/**
 * Turning a triage key back into a corpus lookup.
 *
 * Read backwards from contributions.ts's checkEnvelope, which is the only other place that owns
 * this format. Only books and zones parse to something worth checking: their keys are a frozen
 * id and either a bare map or an (mapID, subzone) pair, both things a real corpus entry could
 * already answer to, so a row filed as "missing" might in fact be a corpus bug -- the case the
 * triage page exists to surface. Quests keys have no such target to resolve against, so there
 * is nothing to check.
 *
 * The subzone canonicalisation is not reimplemented here. It used to be a hand-rolled regex
 * chain in this file, and it silently disagreed with the pipeline on any subzone starting
 * with "The " -- "The Underbog" slugged to "the-underbog" here and "underbog" in the corpus,
 * so a row that was actually on file kept reading as missing. `normaliseKey`/`slugFor` come
 * from zones/tools.ts's bridge instead, the same module the corpus itself is built through,
 * so the two can't drift apart the way addons/SpokenBooks/Checksum.lua warns a duplicated
 * rule eventually does.
 */
import { normaliseKey, slugFor } from "@/lib/zones/tools";

const DIGITS = /^\d+$/;

export type CorpusLookup =
  | { source: "books"; pageId: number }
  | { source: "zones"; mapID: number; slug: string }
  | null;

export function corpusLookup(source: string, key: string): CorpusLookup {
  if (source === "books") {
    return DIGITS.test(key) ? { source: "books", pageId: Number(key) } : null;
  }

  if (source === "zones") {
    // "map" is digits-only by construction (contributions.ts's checkEnvelope), so the first
    // ":" always marks its end no matter what the subzone name itself contains.
    const sep = key.indexOf(":");
    if (sep < 0) {
      // No subzone: the player was standing in the open part of the zone, the main zones gap
      // (GetSubZoneText() returns "" there far more often than not). The zone's own lore is
      // the "no key" entry naming.mjs's filePathFor/lineId give every zone -- file "{mapID}/zone",
      // id "z:{mapID}" -- so it resolves the same way a subzone slug does, just against "zone".
      return DIGITS.test(key) ? { source: "zones", mapID: Number(key), slug: "zone" } : null;
    }
    const map = key.slice(0, sep);
    const subzone = key.slice(sep + 1);
    if (!DIGITS.test(map) || !subzone) return null;
    return { source: "zones", mapID: Number(map), slug: slugFor(normaliseKey(subzone)) };
  }

  return null;
}
