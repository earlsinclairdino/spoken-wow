import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";

import ContributionTable, { type ContributionRow, type NpcSummary } from "@/components/ContributionTable";
import { auth } from "@/lib/auth";
import { pageById } from "@/lib/books/catalogue";
import { corpusLookup } from "@/lib/contributions/existing";
import { isStatus, type ContributionStatus } from "@/lib/contributions/contributions";
import { listContributions, type Contribution } from "@/lib/contributions/store";
import { observedFrom } from "@/lib/npc/resolve";
import { isProvenance, getResolutions, resolutionKey, type NpcKind, type Provenance } from "@/lib/npc/store";
import { canRegenerate } from "@/lib/permissions";
import { lineByPath } from "@/lib/zones/catalogue";

export const metadata: Metadata = { title: "Contributions · Spoken" };

// A triage queue read against a database that other people are also resolving rows in.
export const dynamic = "force-dynamic";

/**
 * The corpus text a contribution's key already resolves to, or undefined where it does not.
 *
 * Only books and zones have a key corpusLookup can resolve (see existing.ts); a quests row is
 * left out of the map entirely rather than looked up and always missing, so the table can
 * tell "not checked" apart from "checked and the corpus has nothing".
 */
async function existingTextFor(contributions: Contribution[]): Promise<Record<number, string>> {
  const found: Record<number, string> = {};

  await Promise.all(
    contributions.map(async (row) => {
      const lookup = corpusLookup(row.source, row.key);
      if (!lookup) return;

      if (lookup.source === "books") {
        const page = await pageById(lookup.pageId);
        if (page) found[row.id] = page.text;
      } else {
        const line = await lineByPath(lookup.mapID, lookup.slug);
        if (line) found[row.id] = line.full;
      }
    }),
  );

  return found;
}

/**
 * Who the corpus, the client or a moderator believes each row's NPC to be.
 *
 * Keyed on the contribution id, not the (kind, id) pair, because that is what the table already
 * indexes rows by; the underlying resolution is still shared across every contribution that
 * names the same NPC, which is the whole point of resolveNpc writing through to it.
 *
 * A row present with `npc` set but every field null is meaningful, not absent: it says a
 * moderator or the resolver looked and found no race to assign (a narrator, say). Absent
 * entirely means the envelope never named an NPC at all -- zones and books never do, and a
 * quests envelope keyed on quest+event rather than npc doesn't either.
 */
async function npcFor(contributions: Contribution[]): Promise<Record<number, NpcSummary>> {
  const found: Record<number, NpcSummary> = {};

  // build is its own column on a stored contribution, not part of `meta` (submissionFrom
  // strips it out at intake) -- put back for observedFrom the way the intake route and the
  // export do, even though this function only reads npcKind/npcId off the result.
  const observed = contributions.map((row) => ({
    row,
    observed: observedFrom({ ...row.meta, build: row.build }),
  }));

  // One query for every row's NPC, not one per row -- getResolutions is exactly what the
  // export already uses to do this, and a per-row getResolution here used to mean the whole
  // moderator queue issued one round trip per contribution (and, worse, that any single
  // poisoned npcId -- see resolve.ts's digits() -- would throw inside this Promise.all and
  // 500 the entire page).
  const keys: { npcKind: NpcKind; npcId: number }[] = [];
  for (const { observed: o } of observed) {
    if (o.npcKind !== null && o.npcId !== null) keys.push({ npcKind: o.npcKind, npcId: o.npcId });
  }
  const resolutions = await getResolutions(keys);

  for (const { row, observed: o } of observed) {
    if (!o.npcKind || o.npcId === null) continue;

    // No resolution row yet -- an older contribution, or a best-effort resolve at intake that
    // failed -- is still an NPC a moderator can answer for, so the kind/id survive into the
    // summary even when there is nothing else to show yet.
    const resolution = resolutions.get(resolutionKey(o.npcKind, o.npcId));
    found[row.id] = {
      npcKind: o.npcKind,
      npcId: o.npcId,
      race: resolution?.race ?? null,
      gender: resolution?.gender ?? null,
      flavor: resolution?.flavor ?? null,
      provenance: resolution?.provenance ?? "none",
      confirmed: resolution?.confirmed ?? false,
    };
  }

  return found;
}

/** /contributions's second filter dimension: whether the row's NPC is a settled answer. */
export type ConfirmedFilter = "confirmed" | "unconfirmed" | "all";

function isConfirmedFilter(value: unknown): value is "confirmed" | "unconfirmed" {
  return value === "confirmed" || value === "unconfirmed";
}

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; provenance?: string; confirmed?: string }>;
}) {
  const session = await auth.api.getSession({ headers: await headers() });

  // 404, matching /reports: a member has no business learning the page exists, and these
  // rows hold text and identifying details a stranger pasted in.
  if (!session || !canRegenerate(session.user.role)) notFound();

  const { status: rawStatus, provenance: rawProvenance, confirmed: rawConfirmed } = await searchParams;
  const status: ContributionStatus | "all" = isStatus(rawStatus)
    ? rawStatus
    : rawStatus === "all"
      ? "all"
      : "new";
  // Both default to "all": these are what makes an unconfirmed NPC revisitable later (the
  // feature the spec asked for and this branch had left unbuilt -- see finding 5), not a
  // narrowing anyone needs applied before they ask for it.
  const provenance: Provenance | "all" = isProvenance(rawProvenance) ? rawProvenance : "all";
  const confirmed: ConfirmedFilter = isConfirmedFilter(rawConfirmed) ? rawConfirmed : "all";

  const contributions = await listContributions(status);
  const existing = await existingTextFor(contributions);
  const npcs = await npcFor(contributions);

  // ContributionTable is a client component: whatever shape crosses in `initial` lands in the
  // RSC flight payload and is readable in devtools, so the full row -- name, email, raw, the
  // ip listContributions doesn't even select -- never leaves this server function. `body` is
  // the one identifying-adjacent field that does cross, deliberately: see finding 4/the
  // table's own docstring for why a player's complaint belongs where triage can read it.
  const rows: ContributionRow[] = contributions
    .map((row) => ({
      id: row.id,
      source: row.source,
      key: row.key,
      locale: row.locale,
      count: row.count,
      text: row.text,
      status: row.status,
      createdAt: row.createdAt,
      body: row.body,
      npc: npcs[row.id] ?? null,
    }))
    // A row with no npc at all has nothing for either filter to match -- neither filter is
    // "which rows never named an NPC", so it drops out the moment either one narrows anything,
    // rather than showing up under an "unconfirmed" or a specific-provenance view it was never
    // part of.
    .filter((row) => {
      if (provenance === "all" && confirmed === "all") return true;
      if (!row.npc) return false;
      if (provenance !== "all" && row.npc.provenance !== provenance) return false;
      if (confirmed !== "all" && row.npc.confirmed !== (confirmed === "confirmed")) return false;
      return true;
    });

  return (
    <main className="mx-auto max-w-6xl px-5 pt-6 pb-24">
      <h1 className="text-xl font-semibold">Contributions</h1>
      <p className="text-muted-foreground mt-1 mb-5 text-sm">
        Envelopes players pasted in for text this corpus has no audio for. Accepting a row does
        not queue anything -- it only marks the row for the next export, which the pipelines
        pull on their own schedule.
      </p>

      <ContributionTable
        initial={rows}
        status={status}
        provenance={provenance}
        confirmed={confirmed}
        existing={existing}
      />
    </main>
  );
}
