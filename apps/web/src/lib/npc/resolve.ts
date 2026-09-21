/**
 * Who is speaking a contributed line.
 *
 * Three sources, in this order, and the order is the whole design:
 *
 *   1. A moderator's answer, if one exists. They may know something no data source does.
 *   2. The corpus, for an NPC it already carries. Exact, including the flavor, which is
 *      recovered from display data no client API exposes.
 *   3. What the client saw: a model file id, which names a race and a gender but says nothing
 *      about flavor, so the flavor is defaulted and the row is left unconfirmed.
 *
 * An NPC that answers to none of them resolves to no race, which is a normal outcome rather
 * than a failure: the corpus already carries `narrator-male` for things that are not a race.
 */
import { npcVoiceFromCorpus } from "@/lib/corpus";

import { raceForModel } from "./models";
import { getResolution, upsertResolution, type NpcKind, type NpcResolution } from "./store";

/** The flavor every race-gender has, and the one the pipeline itself falls back to. */
const DEFAULT_FLAVOR = "standard";

export type Observed = {
  npcKind: NpcKind | null;
  npcId: number | null;
  npcName: string | null;
  modelFileId: number | null;
  sex: number | null;
  creatureType: string | null;
  build: string | null;
};

const DIGITS = /^\d+$/;

function digits(value: string | undefined): number | null {
  return value && DIGITS.test(value) ? Number(value) : null;
}

export function observedFrom(meta: Record<string, string>): Observed {
  // `npc` is "<id> <name>" -- the id, then whatever the client called them.
  const npc = meta.npc?.match(/^(\d+)(?:\s+(.*))?$/);
  const kind = meta.kind === "gameobject" ? "gameobject" : meta.kind === "creature" ? "creature" : null;

  return {
    // No default for an absent `kind`: the pre-kind envelope came from `TargetForGUID`, which
    // resolves any GUID `CanHaveID` covers, including GameObject -- gameobject quest-givers
    // are real and reachable this way. Guessing "creature" would risk filing one under the
    // creature id space, exactly the collision npcKey's namespacing exists to prevent.
    npcKind: npc ? kind : null,
    npcId: npc ? Number(npc[1]) : null,
    npcName: npc?.[2]?.trim() || null,
    modelFileId: digits(meta.model),
    sex: digits(meta.sex),
    creatureType: meta.creature || null,
    build: meta.build || null,
  };
}

export async function resolveNpc(observed: Observed): Promise<NpcResolution | null> {
  const { npcKind, npcId } = observed;
  // `npcId === null`, not a truthiness check: id 0 is a real id and must not be mistaken for
  // "no npc at all". A kind-less envelope (see observedFrom) also fails here since npcKind is
  // null in that case -- an envelope old enough to lack `kind` also lacks `model`, so the best
  // row it could ever produce is `provenance: "none"` with no race, gender or flavor: a row
  // whose entire content is a name the contribution itself already carries. Not worth risking
  // a gameobject filed under a creature id. The player's next submission, after an addon
  // update, resolves properly.
  if (!npcKind || npcId === null) return null;

  const existing = await getResolution(npcKind, npcId);
  // The store's upsert already ranks provenance and would refuse a lower-ranked write on its
  // own, so this is not what keeps a moderator's answer safe -- it is here so a moderator-owned
  // NPC skips the corpus scan and the write entirely, rather than doing both to arrive back
  // where it started.
  if (existing?.provenance === "moderator") return existing;

  const corpus = npcVoiceFromCorpus(npcKind, npcId);
  if (corpus) {
    return upsertResolution({
      npcKind,
      npcId,
      npcName: corpus.npcName,
      race: corpus.race,
      gender: corpus.gender,
      flavor: corpus.flavor,
      provenance: "corpus",
      confirmed: true,
      modelFileId: observed.modelFileId,
      sex: observed.sex,
      creatureType: observed.creatureType,
      build: observed.build,
      note: null,
      resolvedBy: null,
    });
  }

  const fromModel = raceForModel(observed.modelFileId);
  return upsertResolution({
    npcKind,
    npcId,
    npcName: observed.npcName,
    race: fromModel?.race ?? null,
    gender: fromModel?.gender ?? null,
    // A flavor nobody has confirmed. The pipeline defaults the same way when the game data
    // does not answer, so this is the existing behaviour written down rather than a new guess.
    flavor: fromModel ? DEFAULT_FLAVOR : null,
    provenance: fromModel ? "client" : "none",
    confirmed: false,
    modelFileId: observed.modelFileId,
    sex: observed.sex,
    creatureType: observed.creatureType,
    build: observed.build,
    note: null,
    resolvedBy: null,
  });
}
