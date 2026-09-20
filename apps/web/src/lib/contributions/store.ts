/**
 * The only module that knows the contribution table's column names, as lib/reports/store.ts is
 * for reports.
 *
 * The insert is an upsert on "dedup", which is where "count" comes from: the same text from a
 * fourth player is not a fourth row to read, it is the number that says read this one first.
 *
 * countRecentContributions counts in Postgres for the reason its report-side twin gives -- a
 * limit held in process memory is a limit that resets at the moment a flood would get through.
 * It is a separate count from the reports one: a person filing ten reports and pasting ten
 * envelopes has done two different things, and neither should silence the other.
 */
import { db } from "@/lib/db";

import type { ContributionStatus, Submission } from "./contributions";
import type { EnvelopeSource } from "./envelope";

const COLUMNS = `"id", "source", "key", "locale", "build", "text", "meta", "raw", "count",
                 "status", "body", "name", "email", "userId", "createdAt"::text,
                 "updatedAt"::text, "resolvedBy"`;

export type Contribution = {
  id: number;
  source: EnvelopeSource;
  key: string;
  locale: string;
  build: string;
  text: string | null;
  meta: Record<string, string>;
  raw: string;
  count: number;
  status: ContributionStatus;
  body: string | null;
  name: string | null;
  email: string | null;
  userId: string | null;
  createdAt: string;
  updatedAt: string;
  resolvedBy: string | null;
};

export async function createContribution(
  input: Submission & {
    body: string | null;
    name: string | null;
    email: string | null;
    userId: string | null;
    ip: string | null;
  },
): Promise<void> {
  // Returns nothing, as createReport does: the sender cannot read their submission back.
  await db().query(
    `insert into "contribution"
       ("source", "key", "locale", "build", "text", "meta", "raw", "dedup",
        "body", "name", "email", "userId", "ip")
     values ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, $10, $11, $12, $13)
     on conflict ("dedup") do update
       set "count" = "contribution"."count" + 1,
           "updatedAt" = now()`,
    [
      input.source,
      input.key,
      input.locale,
      input.build,
      input.text,
      JSON.stringify(input.meta),
      input.raw,
      input.dedup,
      input.body,
      input.name,
      input.email,
      input.userId,
      input.ip,
    ],
  );
}

export async function recordContributionHit(ip: string | null): Promise<void> {
  await db().query(`insert into "contribution_hit" ("ip") values ($1)`, [ip]);
}

export async function countRecentContributions(ip: string, withinMs: number): Promise<number> {
  // Counts hits, not rows: the upsert above collapses identical text, and a person who pasted
  // the same envelope ten times has still pasted ten times.
  const { rows } = await db().query<{ count: string }>(
    `select count(*)::text as count
       from "contribution_hit"
      where "ip" = $1
        and "createdAt" > now() - ($2::bigint * interval '1 millisecond')`,
    [ip, withinMs],
  );
  return Number(rows[0]?.count ?? 0);
}

export async function listContributions(
  status: ContributionStatus | "all",
): Promise<Contribution[]> {
  const { rows } = await db().query<Contribution>(
    `select ${COLUMNS} from "contribution"
      where ($1 = 'all' or "status" = $1)
      order by "count" desc, "createdAt" desc`,
    [status],
  );
  return rows;
}

export async function setContributionStatus(
  id: number,
  status: ContributionStatus,
  userId: string,
): Promise<Contribution | null> {
  const { rows } = await db().query<Contribution>(
    `update "contribution"
        set "status" = $2, "resolvedBy" = $3, "updatedAt" = now()
      where "id" = $1
      returning ${COLUMNS}`,
    [id, status, userId],
  );
  return rows[0] ?? null;
}

export async function acceptedContributions(): Promise<Contribution[]> {
  const { rows } = await db().query<Contribution>(
    `select ${COLUMNS} from "contribution"
      where "status" = 'accepted'
      order by "source", "key"`,
  );
  return rows;
}
