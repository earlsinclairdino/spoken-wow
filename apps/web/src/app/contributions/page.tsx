import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";

import ContributionTable, { type ContributionRow } from "@/components/ContributionTable";
import { auth } from "@/lib/auth";
import { pageById } from "@/lib/books/catalogue";
import { corpusLookup } from "@/lib/contributions/existing";
import { isStatus, type ContributionStatus } from "@/lib/contributions/contributions";
import { listContributions, type Contribution } from "@/lib/contributions/store";
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

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const session = await auth.api.getSession({ headers: await headers() });

  // 404, matching /reports: a member has no business learning the page exists, and these
  // rows hold text and identifying details a stranger pasted in.
  if (!session || !canRegenerate(session.user.role)) notFound();

  const { status: rawStatus } = await searchParams;
  const status: ContributionStatus | "all" = isStatus(rawStatus)
    ? rawStatus
    : rawStatus === "all"
      ? "all"
      : "new";

  const contributions = await listContributions(status);
  const existing = await existingTextFor(contributions);

  // ContributionTable is a client component: whatever shape crosses in `initial` lands in the
  // RSC flight payload and is readable in devtools, so the full row -- name, email, raw, the
  // ip listContributions doesn't even select -- never leaves this server function. `body` is
  // the one identifying-adjacent field that does cross, deliberately: see finding 4/the
  // table's own docstring for why a player's complaint belongs where triage can read it.
  const rows: ContributionRow[] = contributions.map((row) => ({
    id: row.id,
    source: row.source,
    key: row.key,
    locale: row.locale,
    count: row.count,
    text: row.text,
    status: row.status,
    createdAt: row.createdAt,
    body: row.body,
  }));

  return (
    <main className="mx-auto max-w-6xl px-5 pt-6 pb-24">
      <h1 className="text-xl font-semibold">Contributions</h1>
      <p className="text-muted-foreground mt-1 mb-5 text-sm">
        Envelopes players pasted in for text this corpus has no audio for. Accepting a row does
        not queue anything -- it only marks the row for the next export, which the pipelines
        pull on their own schedule.
      </p>

      <ContributionTable initial={rows} status={status} existing={existing} />
    </main>
  );
}
