/**
 * What a report carries beside its address: the contribute envelope the addon put in the
 * report link's #e1= fragment, reduced to its fields and text.
 *
 * Client-safe, like envelope.ts: the report form reads the fragment in the browser, and the
 * triage rows render it there.
 */
import { parseEnvelope, type Envelope } from "@/lib/contributions/envelope";
import type { Source } from "@/lib/sections";

export type ReportContext = { fields: Record<string, string>; text: string | null };

/**
 * The context in a raw envelope, or null when it is not one of `source`'s.
 *
 * A context that fails its checks is dropped rather than refusing the report: the complaint is
 * the report, and the context only helps read it.
 */
export function contextFrom(raw: unknown, source: Source): ReportContext | null {
  const envelope = envelopeFor(raw, source);
  return envelope && { fields: envelope.fields, text: envelope.text };
}

/** The parsed envelope behind contextFrom, for a caller that needs more of it than the context. */
export function envelopeFor(raw: unknown, source: Source): Envelope | null {
  if (typeof raw !== "string" || !raw) return null;
  const parsed = parseEnvelope(raw);
  return parsed.ok && parsed.value.source === source ? parsed.value : null;
}

/**
 * The Spoken release this site was built from: the version in Spoken.toc, which a release PR
 * bumps on master, where the site deploys from. Null in a build that could not read it.
 */
export const LATEST_VERSION: string | null = process.env.NEXT_PUBLIC_SPOKEN_VERSION || null;

/** "SpokenQuests 3.4.0" from the addon field's "SpokenQuests/3.4.0". */
export function addonLabel(context: ReportContext): string | undefined {
  return context.fields.addon?.replace("/", " ");
}

/** "3.4.0" from "SpokenQuests/3.4.0", or null for a source checkout's "dev". */
export function addonVersion(context: ReportContext | null): string | null {
  const version = context?.fields.addon?.split("/")[1];
  return version && /^\d+(\.\d+)*(-[\w.]+)?$/.test(version) ? version : null;
}

/**
 * Whether `version` is older than `latest`, numerically by part. A pre-release (3.0.0-beta.2)
 * is older than its release, as the betas shipped before 3.0.0.
 */
export function isOlder(version: string, latest: string): boolean {
  const [core, pre] = version.split("-", 2);
  const [latestCore, latestPre] = latest.split("-", 2);
  const a = core.split(".").map(Number);
  const b = latestCore.split(".").map(Number);
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const diff = (a[i] ?? 0) - (b[i] ?? 0);
    if (diff) return diff < 0;
  }
  if (pre && !latestPre) return true;
  if (!pre || !latestPre) return false;
  return pre.localeCompare(latestPre, undefined, { numeric: true }) < 0;
}

/** The context's version when this site knows of a newer release, else null. */
export function outdatedVersion(context: ReportContext | null): string | null {
  const version = addonVersion(context);
  return version && LATEST_VERSION && isOlder(version, LATEST_VERSION) ? version : null;
}

/**
 * The context as short labelled facts, in the order a reader weighs them. The NPC field is
 * "<id> <name>" as the addon writes it.
 */
export function contextFacts(context: ReportContext): { label: string; value: string }[] {
  const f = context.fields;
  const facts: { label: string; value: string }[] = [];
  const add = (label: string, value: string | undefined) => {
    if (value) facts.push({ label, value });
  };
  add("Addon", addonLabel(context));
  add("Client", f.build);
  add("Language", f.locale && f.pack && f.pack !== f.locale ? `${f.locale}, hearing ${f.pack}` : f.locale);
  add("NPC", f.npc);
  add("Quest", f.quest && [f.quest, f.event, f.title].filter(Boolean).join(" "));
  add("Book", f.book && (f.number ? `${f.book}, page ${f.number}` : f.book));
  add("Place", [f.zone, f.key].filter(Boolean).join(" · ") || undefined);
  add("Seen", [f.kind, f.creature, f.sex && SEX[f.sex]].filter(Boolean).join(", ") || undefined);
  return facts;
}

/** UnitSex: 1 unknown, 2 male, 3 female. */
const SEX: Record<string, string> = { "1": "", "2": "male", "3": "female" };
