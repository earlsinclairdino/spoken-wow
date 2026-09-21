/**
 * The only module that knows the npc_resolution table's column names, as
 * lib/contributions/store.ts is for contributions.
 *
 * Every read and write takes the kind as well as the id. The pair is the key, because the two
 * id spaces overlap and a bare id would merge a Stormwind City Guard with a Wanted Poster.
 */
import { db } from "@/lib/db";

export type NpcKind = "creature" | "gameobject";

// A tuple, not a bare type alias, so the union is enumerable at runtime -- the rank test below
// walks PROVENANCES rather than listing the four values by hand, which is what makes a fifth
// value added here without a matching rank in provenanceRank fail loudly instead of silently
// sorting as the lowest rank. Follows lib/contributions/contributions.ts's STATUSES pattern.
export const PROVENANCES = ["corpus", "client", "moderator", "none"] as const;
export type Provenance = (typeof PROVENANCES)[number];

export type NpcResolution = {
  npcKind: NpcKind;
  npcId: number;
  npcName: string | null;
  race: string | null;
  gender: string | null;
  flavor: string | null;
  provenance: Provenance;
  confirmed: boolean;
  modelFileId: number | null;
  sex: number | null;
  creatureType: string | null;
  build: string | null;
  note: string | null;
  resolvedBy: string | null;
  updatedAt: string;
};

const COLUMNS = `"npcKind", "npcId", "npcName", "race", "gender", "flavor", "provenance",
                 "confirmed", "modelFileId", "sex", "creatureType", "build", "note",
                 "resolvedBy", "updatedAt"::text`;

export async function getResolution(kind: NpcKind, npcId: number): Promise<NpcResolution | null> {
  const { rows } = await db().query<NpcResolution>(
    `select ${COLUMNS} from "npc_resolution" where "npcKind" = $1 and "npcId" = $2`,
    [kind, npcId],
  );
  return rows[0] ?? null;
}

// Provenance is a rank, not a set of equally-trusted labels: a submission carrying less
// information must never erase one carrying more. `moderator` outranks everything because a
// person decided; `corpus` outranks `client` because it is exact, including a flavor nothing
// else can supply; `client` outranks `none` because a mapped model id is still an observation
// where a bare envelope is none at all. This CASE is inlined into the upsert's `where` twice
// (once for the stored row, once for the incoming one) so the comparison lives in the one
// place both sides of a write pass through, rather than in whichever caller happens to be last.
//
// This list and the npc_resolution_provenance_check constraint in the migration must change
// together: a provenance added to one and not the other either can never be written (rejected
// by the constraint) or falls through to `else` here. The `else` is -1, one below `none`'s own
// 0, on purpose -- an unranked value must not tie `none`, or it would silently win every write
// over an unresolved row while still losing every write to anything already resolved, and only
// the second half of that would ever be noticed. Ranked strictly below everything, a forgotten
// rank can never land at all, so store.test.ts's PROVENANCES-driven test (every real provenance
// must beat a `none` row) goes red immediately, naming the value, instead of shipping quietly.
function provenanceRank(column: string): string {
  return `case ${column}
    when 'moderator' then 3
    when 'corpus' then 2
    when 'client' then 1
    when 'none' then 0
    else -1
  end`;
}

export async function upsertResolution(
  input: Omit<NpcResolution, "updatedAt">,
): Promise<NpcResolution> {
  // The `where` compares ranks rather than special-casing `moderator`: without it, a `none`
  // write from an older addon that sends no model at all would wipe a `client` or `corpus`
  // row's race back to null, and `client` would freely overwrite `corpus`'s exact answer.
  // Equal rank still updates (`>=`), so a fresh corpus read can refresh a name and a second
  // moderator edit still lands. A skipped update returns no row -- `do update ... where` makes
  // the row a no-op, not a match failure -- so the read-back below is what keeps this
  // function's return type honest in that case.
  const { rows } = await db().query<NpcResolution>(
    `insert into "npc_resolution"
       ("npcKind", "npcId", "npcName", "race", "gender", "flavor", "provenance", "confirmed",
        "modelFileId", "sex", "creatureType", "build", "note", "resolvedBy")
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
     on conflict ("npcKind", "npcId") do update
       set "npcName" = excluded."npcName",
           "race" = excluded."race",
           "gender" = excluded."gender",
           "flavor" = excluded."flavor",
           "provenance" = excluded."provenance",
           "confirmed" = excluded."confirmed",
           "modelFileId" = excluded."modelFileId",
           "sex" = excluded."sex",
           "creatureType" = excluded."creatureType",
           "build" = excluded."build",
           "note" = excluded."note",
           "resolvedBy" = excluded."resolvedBy",
           "updatedAt" = now()
       where ${provenanceRank(`"npc_resolution"."provenance"`)}
             <= ${provenanceRank(`excluded."provenance"`)}
     returning ${COLUMNS}`,
    [
      input.npcKind, input.npcId, input.npcName, input.race, input.gender, input.flavor,
      input.provenance, input.confirmed, input.modelFileId, input.sex, input.creatureType,
      input.build, input.note, input.resolvedBy,
    ],
  );
  if (rows[0]) return rows[0];

  // The `where` above turned the write into a no-op, which means the row on disk already
  // outranks this submission -- hand that back rather than undefined, so a caller that ignores
  // the possibility still gets a real NpcResolution.
  const existing = await getResolution(input.npcKind, input.npcId);
  if (!existing) {
    throw new Error(`upsertResolution: no-op update left no row for ${input.npcKind}/${input.npcId}`);
  }
  return existing;
}

/** The map key getResolutions returns rows under -- the same pair getResolution takes, joined. */
export function resolutionKey(npcKind: NpcKind, npcId: number): string {
  return `${npcKind}:${npcId}`;
}

/**
 * getResolution, batched.
 *
 * The export walks every accepted row and each one may name an NPC, so a caller that looked
 * each one up individually would issue one round trip per row rather than one for the whole
 * export. The parallel-unnest join is what buys that: two arrays in, matched pairwise against
 * the table's own two-column key, in a single query.
 */
export async function getResolutions(
  keys: { npcKind: NpcKind; npcId: number }[],
): Promise<Map<string, NpcResolution>> {
  if (keys.length === 0) return new Map();

  const { rows } = await db().query<NpcResolution>(
    `select ${COLUMNS} from "npc_resolution" r
      where exists (
        select 1 from unnest($1::text[], $2::int[]) as pairs("npcKind", "npcId")
         where r."npcKind" = pairs."npcKind" and r."npcId" = pairs."npcId"
      )`,
    [keys.map((key) => key.npcKind), keys.map((key) => key.npcId)],
  );
  return new Map(rows.map((row) => [resolutionKey(row.npcKind, row.npcId), row]));
}

export async function listUnconfirmed(): Promise<NpcResolution[]> {
  const { rows } = await db().query<NpcResolution>(
    `select ${COLUMNS} from "npc_resolution"
      where "confirmed" = false
      order by "updatedAt" desc`,
  );
  return rows;
}
