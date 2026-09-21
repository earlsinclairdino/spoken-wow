/**
 * A moderator's answer about who is speaking.
 *
 * Modelled on api/contributions/resolve/route.test.ts: same auth mock, same seeded user.
 *
 * Needs DATABASE_URL and migrations applied.
 */
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";

import { closeDb, db } from "@/lib/db";
import { getResolution, upsertResolution } from "@/lib/npc/store";

/** resolvedBy has a foreign key, so resolving needs a user that exists. */
const RESOLVER = "test-contributions-npc-route";

vi.mock("@/lib/generation/authz", () => ({
  requireRegenerate: async () => ({ session: { user: { id: RESOLVER } }, denied: null }),
}));

import { POST } from "./route";

/** A bucket no other run shares, so a concurrent run's cleanup can't race this one's rows. */
const npcId = 900_000_000 + Math.floor(Math.random() * 99_999_999);

beforeAll(async () => {
  await db().query(
    `insert into "user" ("id", "name", "email", "emailVerified")
     values ($1, 'Test Resolver', $2, false)
     on conflict ("id") do nothing`,
    [RESOLVER, `${RESOLVER}@example.invalid`],
  );
});

afterEach(async () => {
  await db().query(`delete from "npc_resolution" where "npcId" in ($1, 0)`, [npcId]);
});

afterAll(async () => {
  await db().query(`delete from "user" where "id" = $1`, [RESOLVER]);
  await closeDb();
});

function post(body: unknown): Request {
  return new Request("https://example.com/api/contributions/npc", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/contributions/npc", () => {
  it("records a moderator's answer and marks it confirmed", async () => {
    const response = await POST(
      post({
        npcKind: "creature",
        npcId,
        race: "tauren",
        gender: "male",
        flavor: "grim",
        note: "Wowhead lists the grim set for this model.",
      }),
    );
    expect(response.status).toBe(200);
    const row = await getResolution("creature", npcId);
    expect(row).toMatchObject({ flavor: "grim", provenance: "moderator", confirmed: true });
    expect(row?.resolvedBy).toBe(RESOLVER);
  });

  it("refuses a kind it does not know", async () => {
    expect((await POST(post({ npcKind: "item", npcId, race: "tauren" }))).status).toBe(400);
  });

  it("refuses a negative id", async () => {
    expect((await POST(post({ npcKind: "creature", npcId: -1 }))).status).toBe(400);
  });

  it("accepts id 0, a real npc id resolve.ts's own observedFrom treats as one", async () => {
    // A route that rejected 0 as "not positive" would silently make an NPC the intake path can
    // resolve automatically one a moderator could never correct by hand -- exactly the id-0
    // truthiness class of bug this branch already fixed once in resolve.ts/store.ts.
    const response = await POST(post({ npcKind: "creature", npcId: 0, race: "tauren" }));
    expect(response.status).toBe(200);
    const row = await getResolution("creature", 0);
    expect(row).toMatchObject({ race: "tauren", provenance: "moderator", confirmed: true });
  });

  it("keeps what the client reported when a moderator overrules the race", async () => {
    // A client-provenance row already carries evidence from the addon: the model file id it
    // guessed the race from, plus sex/creatureType/build. Overruling the race must not throw
    // that evidence away -- the next person to look may want to know what the guess was based
    // on, and there is no other route that ever writes these columns.
    await upsertResolution({
      npcKind: "creature",
      npcId,
      npcName: "Some Guard",
      race: "human",
      gender: "male",
      flavor: "standard",
      provenance: "client",
      confirmed: false,
      modelFileId: 12345,
      sex: 0,
      creatureType: "Humanoid",
      build: "1.12.1.5875",
      note: null,
      resolvedBy: null,
    });

    const response = await POST(post({ npcKind: "creature", npcId, race: "tauren", gender: "male", flavor: "grim" }));
    expect(response.status).toBe(200);

    const row = await getResolution("creature", npcId);
    expect(row).toMatchObject({
      race: "tauren",
      provenance: "moderator",
      confirmed: true,
      modelFileId: 12345,
      sex: 0,
      creatureType: "Humanoid",
      build: "1.12.1.5875",
    });
  });

  it("lets a moderator clear every field without a constraint violation", async () => {
    await POST(post({ npcKind: "creature", npcId, race: "tauren", gender: "male", flavor: "grim" }));

    // Clearing every field is a moderator's answer too -- "this NPC has no race", the same
    // normal outcome resolve.ts's own docstring describes for a corpus miss. It stays
    // "moderator"/confirmed so nothing lower-ranked overwrites it, and both invariants in
    // 0031 allow a moderator row to carry nulls: the "none is empty" check only constrains
    // provenance "none", and the "confirmed implies corpus or moderator" check is satisfied
    // by "moderator" regardless of confirmed.
    const response = await POST(post({ npcKind: "creature", npcId, race: "", gender: "", flavor: "" }));
    expect(response.status).toBe(200);

    const row = await getResolution("creature", npcId);
    expect(row).toMatchObject({
      race: null,
      gender: null,
      flavor: null,
      provenance: "moderator",
      confirmed: true,
    });
  });
});
