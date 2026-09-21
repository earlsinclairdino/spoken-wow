/**
 * The only module that knows the npc_resolution table's column names, as
 * lib/contributions/store.ts is for contributions.
 *
 * Every read and write takes the kind as well as the id. The pair is the key, because the two
 * id spaces overlap and a bare id would merge a Stormwind City Guard with a Wanted Poster.
 */
import { db } from "@/lib/db";

export type NpcKind = "creature" | "gameobject";
export type Provenance = "corpus" | "client" | "moderator" | "none";

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

export async function upsertResolution(
  input: Omit<NpcResolution, "updatedAt">,
): Promise<NpcResolution> {
  // The `where` guards a moderator's answer against a later client guess: without it, the
  // stored row's provenance and confirmed flag are excluded.* like everything else, so a
  // contribution filed after a moderator has already confirmed an NPC would silently downgrade
  // it back to an unconfirmed guess. A skipped update returns no row -- `do update ... where`
  // makes the row a no-op, not a match failure -- so the read-back below is what keeps this
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
       where not ("npc_resolution"."provenance" = 'moderator'
                  and excluded."provenance" <> 'moderator')
     returning ${COLUMNS}`,
    [
      input.npcKind, input.npcId, input.npcName, input.race, input.gender, input.flavor,
      input.provenance, input.confirmed, input.modelFileId, input.sex, input.creatureType,
      input.build, input.note, input.resolvedBy,
    ],
  );
  if (rows[0]) return rows[0];

  // The `where` above turned the write into a no-op, which means the row on disk is the
  // moderator's answer this call was blocked from downgrading -- hand that back rather than
  // undefined, so a caller that ignores the possibility still gets a real NpcResolution.
  const existing = await getResolution(input.npcKind, input.npcId);
  if (!existing) {
    throw new Error(`upsertResolution: no-op update left no row for ${input.npcKind}/${input.npcId}`);
  }
  return existing;
}

export async function listUnconfirmed(): Promise<NpcResolution[]> {
  const { rows } = await db().query<NpcResolution>(
    `select ${COLUMNS} from "npc_resolution"
      where "confirmed" = false
      order by "updatedAt" desc`,
  );
  return rows;
}
