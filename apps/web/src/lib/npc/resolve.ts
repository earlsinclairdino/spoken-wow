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
import { defaultFlavorFor, npcVoiceFromCorpus } from "@/lib/corpus";

import { raceForModel } from "./models";
import { getResolution, NPC_KINDS, upsertResolution, type NpcKind, type NpcResolution } from "./store";

// The three integer columns npc_resolution and contribution both ultimately feed from an
// unauthenticated envelope: an id this large is still "a digit run ending at a space" as far
// as checkEnvelope is concerned, but Postgres's `integer` tops out at 2147483647, and a value
// past that 500s every reader of the row (the triage page's Promise.all, the export's
// unnest($::int[])) rather than merely failing to resolve. Bounding it here, at the one place
// both consumers get npcId/modelFileId/sex from, means neither has to know this rule exists.
const INT32_MAX = 2147483647;

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

// npcId, modelFileId and sex all land in an `integer` column (migration 0030), and all three
// come straight from an unauthenticated envelope: checkEnvelope only requires a digit run, with
// no magnitude bound. Past 2147483647 Postgres rejects the insert, but that only protects the
// npc_resolution row -- the contribution itself already stored, permanently, with the
// oversized value in its meta. Bounding here, before either column is ever written, is what
// keeps a single out-of-range paste from turning into a row that 500s every reader of it: the
// triage page's Promise.all (page.tsx) and the export's unnest($::int[]) (export/route.ts) both
// go through this function to get there.
function digits(value: string | undefined): number | null {
  if (!value || !DIGITS.test(value)) return null;
  const n = Number(value);
  return Number.isSafeInteger(n) && n <= INT32_MAX ? n : null;
}

export function observedFrom(meta: Record<string, string>): Observed {
  // `npc` is "<id> <name>" -- the id, then whatever the client called them.
  const npc = meta.npc?.match(/^(\d+)(?:\s+(.*))?$/);
  const kind = (NPC_KINDS as readonly string[]).includes(meta.kind ?? "")
    ? (meta.kind as NpcKind)
    : null;
  // Through the same bound as modelFileId and sex, not a bare Number(): the regex only proves
  // digits, not that they fit in `integer`, and npcId is the one of the three that gets used as
  // a lookup key rather than merely stored, so an unbounded value here is the one that reaches
  // getResolution/upsertResolution at all.
  const npcId = digits(npc?.[1]);

  return {
    // No default for an absent `kind`: the pre-kind envelope came from `TargetForGUID`, which
    // resolves any GUID `CanHaveID` covers, including GameObject -- gameobject quest-givers
    // are real and reachable this way. Guessing "creature" would risk filing one under the
    // creature id space, exactly the collision npcKey's namespacing exists to prevent.
    npcKind: npc ? kind : null,
    npcId,
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
  // A flavor nobody has confirmed, derived the way tts_cli/flavors.py's fallback_flavors
  // derives its own: "standard" where the race-gender has it, otherwise its busiest flavor,
  // from the corpus rather than a constant. A constant would leave four race-genders
  // (dwarf-female, goblin-female, goblin-male, tauren-male) pointing at a voice that does not
  // exist -- this branch's own flagship case, model 122055/tauren-male, used to emit
  // "tauren-male-standard", which nothing can produce. defaultFlavorFor answers null for a race
  // the corpus has never carried a flavored line for at all, and null is left alone rather than
  // guessed at: the row is unconfirmed regardless, and a moderator or the pipeline can decide.
  const flavor = fromModel ? defaultFlavorFor(fromModel.race, fromModel.gender) : null;
  return upsertResolution({
    npcKind,
    npcId,
    npcName: observed.npcName,
    race: fromModel?.race ?? null,
    gender: fromModel?.gender ?? null,
    flavor,
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
