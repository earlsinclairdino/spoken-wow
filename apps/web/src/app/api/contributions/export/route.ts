/**
 * What the pipelines read.
 *
 * NDJSON rather than a write into a staging table, because there is no staging table to write
 * into: the quests corpus is built in pipelines/quests against vmangos, not in this database,
 * and the books corpus is built from the same world DB. A file the pipeline pulls is the
 * boundary those two already have.
 *
 * Collaborator-only, like /resolve: accepted text is still text somebody typed into a public
 * form, and the queue it came from is not public reading.
 */
import { requireRegenerate } from "@/lib/generation/authz";
import { acceptedContributions } from "@/lib/contributions/store";
import { observedFrom } from "@/lib/npc/resolve";
import { getResolutions, resolutionKey, type NpcKind } from "@/lib/npc/store";

export const dynamic = "force-dynamic";

export async function GET() {
  const { denied } = await requireRegenerate();
  if (denied) return denied;

  const rows = await acceptedContributions();

  // One query for every row's resolution, not one per row -- observedFrom is pure and cheap, so
  // it runs twice (once to build the keys, once below per row) rather than kept in a parallel
  // array the two loops would need to stay in lockstep with.
  const keys: { npcKind: NpcKind; npcId: number }[] = [];
  for (const row of rows) {
    const observed = observedFrom(row.meta);
    if (observed.npcKind !== null && observed.npcId !== null) {
      keys.push({ npcKind: observed.npcKind, npcId: observed.npcId });
    }
  }
  const resolutions = await getResolutions(keys);

  const body = rows
    .map((row) => {
      const observed = observedFrom(row.meta);
      const resolution =
        observed.npcKind !== null && observed.npcId !== null
          ? resolutions.get(resolutionKey(observed.npcKind, observed.npcId))
          : undefined;

      return JSON.stringify({
        id: row.id,
        source: row.source,
        key: row.key,
        locale: row.locale,
        build: row.build,
        text: row.text,
        meta: row.meta,
        count: row.count,
        // The pipelines decide for themselves whether an unconfirmed guess is good enough --
        // this route only says what was resolved and how sure the resolution is.
        race: resolution?.race ?? null,
        gender: resolution?.gender ?? null,
        flavor: resolution?.flavor ?? null,
        npcProvenance: resolution?.provenance ?? null,
        npcConfirmed: resolution?.confirmed ?? false,
      });
    })
    .join("\n");

  return new Response(body ? body + "\n" : "", {
    headers: { "content-type": "application/x-ndjson; charset=utf-8" },
  });
}
