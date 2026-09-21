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
