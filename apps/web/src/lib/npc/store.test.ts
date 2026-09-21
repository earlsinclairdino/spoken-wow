/**
 * The store, against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied:
 *   deploy/web/bin/migrate.sh "$PWD/apps/web"
 */
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

import { getResolution, listUnconfirmed, upsertResolution } from "./store";

// A bucket no other run shares: these ids are the primary key, so a fixed one would collide
// between concurrent runs against the shared dev database.
let npcId: number;

beforeEach(() => {
  npcId = 900_000_000 + Math.floor(Math.random() * 90_000_000);
});

afterEach(async () => {
  await db().query(`delete from "npc_resolution" where "npcId" = $1`, [npcId]);
});

afterAll(async () => {
  await closeDb();
});

function resolution(overrides: Record<string, unknown> = {}) {
  return {
    npcKind: "creature" as const,
    npcId,
    npcName: "Boarton Shadetotem",
    race: "tauren",
    gender: "male",
    flavor: "standard",
    provenance: "client" as const,
    confirmed: false,
    modelFileId: 122055,
    sex: 2,
    creatureType: "Humanoid",
    build: "1.60.1/69913",
    note: null,
    resolvedBy: null,
    ...overrides,
  };
}

describe("upsertResolution", () => {
  it("stores one and reads it back", async () => {
    await upsertResolution(resolution());
    const row = await getResolution("creature", npcId);
    expect(row?.race).toBe("tauren");
    expect(row?.provenance).toBe("client");
    expect(row?.confirmed).toBe(false);
  });

  it("replaces an earlier answer for the same npc", async () => {
    await upsertResolution(resolution());
    await upsertResolution(
      resolution({ race: "highmountaintauren", provenance: "moderator", confirmed: true }),
    );
    const row = await getResolution("creature", npcId);
    expect(row?.race).toBe("highmountaintauren");
    expect(row?.confirmed).toBe(true);
  });

  // The reason the key is a pair: the same number in the other space is a different thing.
  it("keeps a gameobject with the same id as its own row", async () => {
    await upsertResolution(resolution());
    await upsertResolution(resolution({ npcKind: "gameobject", race: null, npcName: "A Sign" }));
    expect((await getResolution("creature", npcId))?.race).toBe("tauren");
    expect((await getResolution("gameobject", npcId))?.race).toBe(null);
    await db().query(`delete from "npc_resolution" where "npcId" = $1`, [npcId]);
  });

  it("answers null for an npc nobody has resolved", async () => {
    expect(await getResolution("creature", npcId)).toBe(null);
  });
});

describe("listUnconfirmed", () => {
  it("lists the guesses and not the confirmed ones", async () => {
    await upsertResolution(resolution());
    expect((await listUnconfirmed()).some((r) => r.npcId === npcId)).toBe(true);
    await upsertResolution(resolution({ provenance: "moderator", confirmed: true }));
    expect((await listUnconfirmed()).some((r) => r.npcId === npcId)).toBe(false);
  });
});

describe("upsertResolution provenance precedence", () => {
  it("lets a client write over a client row update", async () => {
    await upsertResolution(resolution({ race: "tauren" }));
    const result = await upsertResolution(resolution({ race: "orc" }));
    expect(result.race).toBe("orc");
    expect((await getResolution("creature", npcId))?.race).toBe("orc");
  });

  it("leaves a moderator row untouched by a later client write, and returns the moderator row", async () => {
    await upsertResolution(
      resolution({ race: "highmountaintauren", provenance: "moderator", confirmed: true }),
    );
    const result = await upsertResolution(resolution({ race: "orc", provenance: "client" }));
    expect(result.race).toBe("highmountaintauren");
    expect(result.provenance).toBe("moderator");
    expect(result.confirmed).toBe(true);
    const row = await getResolution("creature", npcId);
    expect(row?.race).toBe("highmountaintauren");
    expect(row?.provenance).toBe("moderator");
  });

  it("lets a moderator write over a moderator row update", async () => {
    await upsertResolution(
      resolution({ race: "highmountaintauren", provenance: "moderator", confirmed: true }),
    );
    const result = await upsertResolution(
      resolution({ race: "tauren", provenance: "moderator", confirmed: true }),
    );
    expect(result.race).toBe("tauren");
    expect((await getResolution("creature", npcId))?.race).toBe("tauren");
  });

  // The concrete failure the rank was built for: an older addon that sends no model at all
  // resolves to "none", and must not wipe out the race a mapped model id already gave us.
  it("does not let a bare 'none' write wipe a client row's race", async () => {
    await upsertResolution(resolution({ race: "tauren", provenance: "client" }));
    const result = await upsertResolution(
      resolution({ race: null, gender: null, flavor: null, provenance: "none" }),
    );
    expect(result.race).toBe("tauren");
    expect(result.provenance).toBe("client");
    const row = await getResolution("creature", npcId);
    expect(row?.race).toBe("tauren");
    expect(row?.provenance).toBe("client");
  });

  // The other shape of the same bug: a model-id guess is not license to overwrite the corpus's
  // exact answer, which carries a flavor nothing else can supply.
  it("does not let a client write overwrite a corpus row", async () => {
    await upsertResolution(
      resolution({ race: "tauren", flavor: "grizzled", provenance: "corpus" }),
    );
    const result = await upsertResolution(
      resolution({ race: "orc", flavor: "standard", provenance: "client" }),
    );
    expect(result.race).toBe("tauren");
    expect(result.flavor).toBe("grizzled");
    expect(result.provenance).toBe("corpus");
    const row = await getResolution("creature", npcId);
    expect(row?.race).toBe("tauren");
    expect(row?.provenance).toBe("corpus");
  });

  it("lets a corpus write over a client row update", async () => {
    await upsertResolution(resolution({ race: "orc", provenance: "client" }));
    const result = await upsertResolution(
      resolution({ race: "tauren", flavor: "grizzled", provenance: "corpus" }),
    );
    expect(result.race).toBe("tauren");
    expect((await getResolution("creature", npcId))?.provenance).toBe("corpus");
  });

  // Equal rank still updates: a fresh corpus read refreshing a name is not a downgrade.
  it("lets a corpus write over a corpus row update", async () => {
    await upsertResolution(
      resolution({ npcName: "Boarton Shadetotem", provenance: "corpus" }),
    );
    const result = await upsertResolution(
      resolution({ npcName: "Boarton the Elder", provenance: "corpus" }),
    );
    expect(result.npcName).toBe("Boarton the Elder");
    expect((await getResolution("creature", npcId))?.npcName).toBe("Boarton the Elder");
  });
});

describe("npc_resolution invariants", () => {
  it("rejects a client row marked confirmed", async () => {
    await expect(
      db().query(
        `insert into "npc_resolution"
           ("npcKind", "npcId", "provenance", "confirmed")
         values ($1, $2, 'client', true)`,
        ["creature", npcId],
      ),
    ).rejects.toThrow(/npc_resolution_confirmed_provenance_check/);
  });

  it("rejects a 'none' row carrying a race", async () => {
    await expect(
      db().query(
        `insert into "npc_resolution"
           ("npcKind", "npcId", "provenance", "race")
         values ($1, $2, 'none', 'tauren')`,
        ["creature", npcId],
      ),
    ).rejects.toThrow(/npc_resolution_none_is_empty_check/);
  });
});
