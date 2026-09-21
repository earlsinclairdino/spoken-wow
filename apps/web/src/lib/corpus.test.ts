import { describe, expect, it } from "vitest";

import { buildLineIndex, defaultFlavorFor, lineIndex, loadCorpus, npcKey, npcVoiceFromCorpus } from "./corpus";

describe("corpus", () => {
  const corpus = loadCorpus();

  it("loads the committed corpus", () => {
    expect(corpus.schemaVersion).toBe(2);
    expect(corpus.lines).toHaveLength(corpus.lineCount);
    expect(corpus.lineCount).toBeGreaterThan(17000);
  });

  it("carries the fields the explorer searches on", () => {
    const line = corpus.lines.find((l) => l.lineId === "q:5:accept");
    expect(line).toBeDefined();
    expect(line!.npcName).toBe("Jitters");
    expect(line!.questTitle).toBe("Jitters' Growling Gut");
    expect(line!.fileName).toBe("5-accept");
    expect(line!.voice).toBe("human-male-standard");
  });

  it("namespaces npc keys by type", () => {
    // creature 68 is a Stormwind City Guard, gameobject 68 is a Wanted Poster
    expect(npcKey({ npcType: "creature", npcId: 68 })).not.toBe(
      npcKey({ npcType: "gameobject", npcId: 68 }),
    );
  });

  it("memoises, so repeated loads do not re-parse", () => {
    expect(loadCorpus()).toBe(corpus);
  });
});

describe("npcVoiceFromCorpus", () => {
  it("carries the exact race, gender and flavor for an npc the corpus knows", () => {
    // Jitters, npcId 288, from q:5:accept above -- real values, not just "not null", so a
    // swapped race/gender or a wrong key format fails this rather than shipping quietly.
    expect(npcVoiceFromCorpus("creature", 288)).toEqual({
      race: "human",
      gender: "male",
      flavor: "standard",
      npcName: "Jitters",
    });
  });

  it("is null for an npc the corpus has never carried", () => {
    expect(npcVoiceFromCorpus("creature", 999_999_999)).toBe(null);
  });
});

describe("defaultFlavorFor", () => {
  // Mirrors tts_cli/flavors.py's fallback_flavors -- pinned against the real, committed
  // corpus rather than a fixture, so a change to either side that breaks the mirror shows up
  // here. tauren-male is the branch's own flagship case (model 122055): it has no "standard"
  // voice in the game at all, only elder/shaman/warrior, so the busiest -- warrior -- is the
  // honest default, not a hardcoded name that would point at nothing.
  it("is the busiest flavor for a race-gender with no standard voice", () => {
    expect(defaultFlavorFor("tauren", "male")).toBe("warrior");
  });

  it("is the busiest flavor for another race-gender with no standard voice", () => {
    expect(defaultFlavorFor("goblin", "female")).toBe("zany");
  });

  // human-male's busiest flavor is "official" (1164 lines vs. standard's 845), and "standard"
  // still wins: fallback_flavors picks it whenever it exists at all, busiest or not.
  it("is 'standard' for a race-gender that has one, even when it is not the busiest", () => {
    expect(defaultFlavorFor("human", "male")).toBe("standard");
  });

  it("is null for a race-gender the corpus has never carried a flavored line for at all", () => {
    expect(defaultFlavorFor("murloc", "male")).toBe(null);
  });
});

// One lineId can belong to many lines. A gossip lineId is g:{md5(text + race + gender)}, so
// every dwarf man with the same greeting shares one id and one mp3 - which is what makes
// regeneration an operation on a file rather than on an NPC's line.
describe("lineIndex", () => {
  const index = lineIndex();

  it("indexes every line in the corpus", () => {
    const total = [...index.values()].reduce((sum, group) => sum + group.length, 0);
    expect(total).toBe(loadCorpus().lineCount);
  });

  it("finds a quest line under its id", () => {
    expect(index.get("q:5:accept")!.map((l) => l.npcName)).toContain("Jitters");
  });

  it("groups the NPCs that share a gossip line", () => {
    const shared = [...index.values()].filter(
      (group) => group.length > 1 && group[0].source === "gossip",
    );
    expect(shared.length).toBeGreaterThan(0);

    // Text, voice and filename are properties of the line; only the speaker varies.
    for (const group of shared.slice(0, 50)) {
      expect(new Set(group.map((l) => l.text)).size).toBe(1);
      expect(new Set(group.map((l) => l.voice)).size).toBe(1);
      expect(new Set(group.map((l) => l.fileName)).size).toBe(1);
    }
  });

  it("memoises", () => {
    expect(lineIndex()).toBe(index);
    expect(buildLineIndex(loadCorpus())).not.toBe(index);
  });
});
