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
     returning ${COLUMNS}`,
    [
      input.npcKind, input.npcId, input.npcName, input.race, input.gender, input.flavor,
      input.provenance, input.confirmed, input.modelFileId, input.sex, input.creatureType,
      input.build, input.note, input.resolvedBy,
    ],
  );
  return rows[0];
}

export async function listUnconfirmed(): Promise<NpcResolution[]> {
  const { rows } = await db().query<NpcResolution>(
    `select ${COLUMNS} from "npc_resolution"
      where "confirmed" = false
      order by "updatedAt" desc`,
  );
  return rows;
}
