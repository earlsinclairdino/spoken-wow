/**
 * Reading the corpus: every voiceline the project knows how to produce.
 *
 * The corpus is written by Python (tts_cli/corpus.py) and committed. Everything here is
 * read-only - in particular `fileName` is computed by tts_cli/naming.py and never derived
 * on this side, because a filename that differs by one character addresses a file the
 * addon can never find, and it fails silently.
 */
import fs from "node:fs";
import zlib from "node:zlib";

import type { NpcType, Source } from "./line-fields";
import { CORPUS_PATH } from "./paths";

/** Mirrors the line schema built in tts_cli/corpus.py:build_corpus. */
export type CorpusLine = {
  lineId: string;
  source: Source;
  questId: number | null;
  questTitle: string | null;
  npcId: number;
  npcName: string;
  npcType: NpcType;
  race: string;
  gender: string;
  /** Which of the race-gender's NPC voice sets, e.g. "shaman". Null where the game has none. */
  flavor: string | null;
  voice: string;
  playerGender: "m" | "f" | null;
  text: string;
  originalText: string;
  fileName: string;
  generatable: boolean;
  skipReason: string | null;
};

export type Spawn = { map: number; x: number; y: number };

export type Corpus = {
  schemaVersion: number;
  generatedAt: string;
  lineCount: number;
  lines: CorpusLine[];
  spawns: Record<string, Spawn[]>;
};

/**
 * Namespaced NPC key.
 *
 * Creature and gameobject IDs are separate spaces that overlap - creature 68 is a
 * Stormwind City Guard, gameobject 68 is a Wanted Poster - so grouping on the bare ID
 * merges unrelated entities. Same rule as spawn_key in tts_cli/corpus.py.
 */
export function npcKey(line: Pick<CorpusLine, "npcType" | "npcId">): string {
  return `${line.npcType}:${line.npcId}`;
}

export function readCorpus(corpusPath: string = CORPUS_PATH): Corpus {
  const gz = fs.readFileSync(corpusPath);
  return JSON.parse(zlib.gunzipSync(gz).toString("utf8")) as Corpus;
}

// Memoised on globalThis rather than in a module variable: the dev server re-evaluates
// modules on hot reload, and re-reading and re-parsing 2 MB on every request is felt.
const cacheKey = Symbol.for("wow-voiceover.corpus");
type CacheHolder = { [cacheKey]?: Corpus };

export function loadCorpus(): Corpus {
  const holder = globalThis as CacheHolder;
  if (!holder[cacheKey]) {
    holder[cacheKey] = readCorpus();
  }
  return holder[cacheKey]!;
}

/**
 * lineId -> every corpus line carrying it.
 *
 * Not one-to-one. A gossip lineId is `g:{md5(text + race + gender)}`, which says nothing
 * about who speaks it, so one id can belong to dozens of NPCs sharing a line - and they all
 * resolve to the same mp3. Anything that acts on a line rather than displaying it needs the
 * whole group: the text and the voice are identical across it, but the NPC is not.
 */
export function buildLineIndex(corpus: Corpus): Map<string, CorpusLine[]> {
  const index = new Map<string, CorpusLine[]>();
  for (const line of corpus.lines) {
    const group = index.get(line.lineId);
    if (group) group.push(line);
    else index.set(line.lineId, [line]);
  }
  return index;
}

const indexKey = Symbol.for("wow-voiceover.line-index");
type IndexHolder = { [indexKey]?: Map<string, CorpusLine[]> };

export function lineIndex(): Map<string, CorpusLine[]> {
  const holder = globalThis as IndexHolder;
  if (!holder[indexKey]) holder[indexKey] = buildLineIndex(loadCorpus());
  return holder[indexKey]!;
}

/**
 * What the corpus already knows about an NPC, or null for one it has never carried.
 *
 * The corpus is the exact answer where it has one: it was built from the same display data the
 * game uses, including the flavor that no client API exposes.
 *
 * A linear scan, not a new memoised index: lineIndex groups by lineId, and one lineId is shared
 * by every NPC with the same gossip line, so it cannot answer "what does this one NPC carry"
 * without a second index carrying its own cache-invalidation story alongside it. This runs once
 * per contribution resolved, not per request, so the scan is the honest cost here.
 */
export function npcVoiceFromCorpus(
  npcType: string,
  npcId: number,
): { race: string; gender: string; flavor: string | null; npcName: string } | null {
  const wanted = `${npcType}:${npcId}`;
  for (const line of loadCorpus().lines) {
    if (npcKey(line) === wanted) {
      return { race: line.race, gender: line.gender, flavor: line.flavor, npcName: line.npcName };
    }
  }
  return null;
}

/**
 * The flavor to give a race-gender the game data does not answer for -- an NPC resolved only
 * from the model file id the addon reported, which names a race and a gender but never a
 * flavor.
 *
 * Mirrors pipelines/quests/tts_cli/flavors.py's fallback_flavors exactly: "standard" where
 * that race-gender has any corpus lines carrying it, otherwise its busiest flavor. Never a
 * constant -- four race-genders (dwarf-female, goblin-female, goblin-male, tauren-male) have
 * no standard voice in the game at all, so a constant would point at nothing for them, which
 * is the bug this replaces (resolve.ts used to hardcode "standard" for every race).
 *
 * A race-gender the corpus carries no flavored line for at all (not merely no "standard" one)
 * answers null, not a guess: there is nothing in the data to derive a busiest flavor from, and
 * the row this feeds is unconfirmed regardless, so a moderator or the pipeline is better placed
 * to decide than an invented default would be.
 */
export function defaultFlavorFor(race: string, gender: string): string | null {
  return flavorDefaults().get(`${race}-${gender}`) ?? null;
}

// Memoised alongside the corpus, not recomputed per contribution: unlike npcVoiceFromCorpus's
// per-lookup scan (justified there by running once per contribution resolved), this default is
// consulted on every model-only resolution and the corpus does not change under a running
// process, so there is nothing to gain by re-tallying it each time.
const flavorDefaultsKey = Symbol.for("wow-voiceover.default-flavors");
type FlavorDefaultsHolder = { [flavorDefaultsKey]?: Map<string, string> };

function flavorDefaults(): Map<string, string> {
  const holder = globalThis as FlavorDefaultsHolder;
  if (!holder[flavorDefaultsKey]) {
    const counts = new Map<string, Map<string, number>>();
    for (const line of loadCorpus().lines) {
      if (!line.flavor) continue;
      const raceGender = `${line.race}-${line.gender}`;
      const tally = counts.get(raceGender) ?? new Map<string, number>();
      tally.set(line.flavor, (tally.get(line.flavor) ?? 0) + 1);
      counts.set(raceGender, tally);
    }

    const defaults = new Map<string, string>();
    for (const [raceGender, tally] of counts) {
      if (tally.has("standard")) {
        defaults.set(raceGender, "standard");
        continue;
      }
      // Busiest first, then name, so a tie does not depend on Map iteration order --
      // fallback_flavors' own tie-break, kept identical so the two sides never disagree.
      const [flavor] = [...tally.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0];
      defaults.set(raceGender, flavor);
    }
    holder[flavorDefaultsKey] = defaults;
  }
  return holder[flavorDefaultsKey]!;
}
