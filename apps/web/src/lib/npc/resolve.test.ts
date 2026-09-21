import { describe, expect, it, vi } from "vitest";

import { observedFrom } from "./resolve";

describe("observedFrom", () => {
  it("reads what the addon reported", () => {
    expect(
      observedFrom({
        npc: "205729 Boarton Shadetotem",
        kind: "creature",
        model: "122055",
        sex: "2",
        creature: "Humanoid",
        build: "1.60.1/69913",
      }),
    ).toEqual({
      npcKind: "creature",
      npcId: 205729,
      npcName: "Boarton Shadetotem",
      modelFileId: 122055,
      sex: 2,
      creatureType: "Humanoid",
      build: "1.60.1/69913",
    });
  });

  // An older addon sends none of it -- no `kind` either, and a gameobject quest-giver is
  // reachable through this same kind-less envelope, so guessing "creature" is not safe.
  it("reads an envelope with no observations at all", () => {
    expect(observedFrom({ npc: "205729 Boarton Shadetotem" })).toEqual({
      npcKind: null,
      npcId: 205729,
      npcName: "Boarton Shadetotem",
      modelFileId: null,
      sex: null,
      creatureType: null,
      build: null,
    });
  });

  it("refuses a model id that is not digits, rather than guessing", () => {
    expect(observedFrom({ npc: "1 X", model: "12a055" }).modelFileId).toBe(null);
  });

  it("has no npc at all for a gossip envelope missing one", () => {
    expect(observedFrom({}).npcId).toBe(null);
  });

  // checkEnvelope only requires a digit run ending at a space, with no magnitude bound, so
  // npc=99999999999 Foo + kind=creature is a contribution checkEnvelope accepts. npcId,
  // modelFileId and sex are all `integer` columns (migration 0030) with the same exposure --
  // past 2147483647, an insert of any one of them 500s. Refused here rather than left to
  // Postgres to reject: getResolution/upsertResolution are never reached at all with a null
  // npcId (resolveNpc bails before either), so no npc_resolution row is ever attempted for an
  // id this large, and neither the triage page nor the export ever asks the database about it.
  it("refuses an npc id past Postgres's integer range, rather than store a poisoned row", () => {
    const observed = observedFrom({ npc: "99999999999 Foo", kind: "creature" });
    expect(observed.npcId).toBe(null);
    // npcKind still resolves -- only the id itself is out of range -- so a caller has to check
    // npcId specifically, which resolveNpc already does (`npcId === null`, not falsy).
    expect(observed.npcKind).toBe("creature");
  });

  it("accepts an npc id at exactly Postgres's integer ceiling", () => {
    expect(observedFrom({ npc: "2147483647 Foo", kind: "creature" }).npcId).toBe(2147483647);
  });

  it("refuses an out-of-range model file id the same way", () => {
    expect(observedFrom({ npc: "1 X", model: "99999999999" }).modelFileId).toBe(null);
  });

  it("refuses an out-of-range sex the same way", () => {
    expect(observedFrom({ npc: "1 X", sex: "99999999999" }).sex).toBe(null);
  });
});

vi.mock("@/lib/corpus", () => ({
  npcVoiceFromCorpus: vi.fn(),
  defaultFlavorFor: vi.fn(),
}));
vi.mock("./store", () => ({
  NPC_KINDS: ["creature", "gameobject"],
  getResolution: vi.fn(),
  upsertResolution: vi.fn(async (row) => ({ ...row, updatedAt: "now" })),
}));

import { defaultFlavorFor, npcVoiceFromCorpus } from "@/lib/corpus";

import { getResolution, upsertResolution } from "./store";
import { resolveNpc } from "./resolve";

const observed = {
  npcKind: "creature" as const,
  npcId: 205729,
  npcName: "Boarton Shadetotem",
  modelFileId: 122055,
  sex: 2,
  creatureType: "Humanoid",
  build: "1.60.1/69913",
};

describe("resolveNpc", () => {
  it("prefers a moderator's answer over everything", async () => {
    vi.mocked(getResolution).mockResolvedValue({
      ...observed, race: "highmountaintauren", gender: "male", flavor: "grim",
      provenance: "moderator", confirmed: true, note: null, resolvedBy: "u1", updatedAt: "now",
    });
    const row = await resolveNpc(observed);
    expect(row?.race).toBe("highmountaintauren");
    expect(upsertResolution).not.toHaveBeenCalled();
  });

  it("takes the corpus's answer, flavor and all, for an npc it already carries", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue({
      race: "tauren", gender: "male", flavor: "grim", npcName: "Boarton Shadetotem",
    });
    const row = await resolveNpc(observed);
    expect(row).toMatchObject({ race: "tauren", flavor: "grim", provenance: "corpus", confirmed: true });
  });

  it("falls back to the model the client reported, with a corpus-derived defaulted flavor", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue(null);
    // tauren-male has no "standard" voice at all (the branch's own flagship case, model
    // 122055) -- defaultFlavorFor is what decides that, not a constant, so this only proves
    // resolveNpc plumbs its answer through rather than proving the answer itself; corpus.test.ts
    // pins defaultFlavorFor's own behaviour against the real corpus.
    vi.mocked(defaultFlavorFor).mockReturnValue("warrior");
    const row = await resolveNpc(observed);
    expect(row).toMatchObject({
      race: "tauren", gender: "male", flavor: "warrior", provenance: "client", confirmed: false,
    });
    expect(defaultFlavorFor).toHaveBeenCalledWith("tauren", "male");
  });

  it("leaves the flavor null when the race-gender has no default to fall back on", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue(null);
    vi.mocked(defaultFlavorFor).mockReturnValue(null);
    const row = await resolveNpc(observed);
    expect(row).toMatchObject({ flavor: null, provenance: "client", confirmed: false });
  });

  it("resolves to no race for a creature model that is not a character", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue(null);
    vi.mocked(defaultFlavorFor).mockClear();
    const row = await resolveNpc({ ...observed, modelFileId: 1 });
    expect(row).toMatchObject({ race: null, provenance: "none", confirmed: false });
    // No race-gender to look a default up for -- raceForModel(1) answers null, so there is
    // nothing for defaultFlavorFor to be asked about at all.
    expect(defaultFlavorFor).not.toHaveBeenCalled();
  });

  it("does nothing at all for an envelope with no npc", async () => {
    expect(await resolveNpc({ ...observed, npcId: null })).toBe(null);
  });

  it("does not mistake npc id 0 for no npc at all", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue(null);
    const row = await resolveNpc({ ...observed, npcId: 0 });
    expect(row).not.toBe(null);
    expect(getResolution).toHaveBeenCalledWith(observed.npcKind, 0);
  });

  // A kind-less envelope can be a gameobject wearing the old creature-shaped envelope, so
  // resolving it (or writing a row for it) would risk merging the two id spaces.
  it("does nothing for a kind-less envelope, and touches neither the store nor the contribution", async () => {
    vi.mocked(getResolution).mockClear();
    vi.mocked(upsertResolution).mockClear();
    expect(await resolveNpc({ ...observed, npcKind: null })).toBe(null);
    expect(getResolution).not.toHaveBeenCalled();
    expect(upsertResolution).not.toHaveBeenCalled();
  });
});
