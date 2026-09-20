/**
 * Turning a triage key back into a corpus lookup.
 *
 * Read backwards from submission.ts's keyFor, which is the only other place that owns this
 * format. Only books and zones parse to something worth checking: their keys are a frozen id
 * and an (mapID, subzone) pair, both things a real corpus entry could already answer to, so a
 * row filed as "missing" might in fact be a corpus bug -- the case the triage page exists to
 * surface. Quests keys have no such target to resolve against, so there is nothing to check.
 *
 * Pure and node-free so the parsing is testable without a database; the catalogue lookups
 * themselves are server-only and live in the page that calls this.
 */
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
    // "map" is digits-only by construction (submission.ts's keyFor), so the first ":" always
    // marks its end no matter what the subzone name itself contains.
    const sep = key.indexOf(":");
    if (sep < 0) return null;
    const map = key.slice(0, sep);
    const subzone = key.slice(sep + 1);
    if (!DIGITS.test(map) || !subzone) return null;
    return { source: "zones", mapID: Number(map), slug: zoneSlug(subzone) };
  }

  return null;
}

/**
 * The same canonicalisation naming.mjs's slugFor expects of its input -- lower-cased and
 * apostrophe-stripped -- applied here because the addon sends the raw display string
 * (GetSubZoneText()) and the corpus keys on that canonical form, not the display string
 * itself.
 */
export function zoneSlug(subzone: string): string {
  return subzone
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9-]/g, "");
}
