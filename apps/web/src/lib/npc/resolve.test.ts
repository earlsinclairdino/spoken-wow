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

  // An older addon sends none of it, and that has to stay submittable.
  it("reads an envelope with no observations at all", () => {
    expect(observedFrom({ npc: "205729 Boarton Shadetotem" })).toEqual({
      npcKind: "creature",
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
});

vi.mock("@/lib/corpus", () => ({
  npcVoiceFromCorpus: vi.fn(),
}));
vi.mock("./store", () => ({
  getResolution: vi.fn(),
  upsertResolution: vi.fn(async (row) => ({ ...row, updatedAt: "now" })),
}));

import { npcVoiceFromCorpus } from "@/lib/corpus";

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

  it("falls back to the model the client reported, with a defaulted flavor", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue(null);
    const row = await resolveNpc(observed);
    expect(row).toMatchObject({
      race: "tauren", gender: "male", flavor: "standard", provenance: "client", confirmed: false,
    });
  });

  it("resolves to no race for a creature model that is not a character", async () => {
    vi.mocked(getResolution).mockResolvedValue(null);
    vi.mocked(npcVoiceFromCorpus).mockReturnValue(null);
    const row = await resolveNpc({ ...observed, modelFileId: 1 });
    expect(row).toMatchObject({ race: null, provenance: "none", confirmed: false });
  });

  it("does nothing at all for an envelope with no npc", async () => {
    expect(await resolveNpc({ ...observed, npcId: null })).toBe(null);
  });
});
