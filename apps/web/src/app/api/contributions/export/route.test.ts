/**
 * What the pipelines read, against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied.
 */
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";

import { closeDb, db } from "@/lib/db";
import { createContribution, setContributionStatus } from "@/lib/contributions/store";
import { upsertResolution } from "@/lib/npc/store";

vi.mock("@/lib/generation/authz", () => ({
  requireRegenerate: async () => ({ session: { user: { id: RESOLVER } }, denied: null }),
}));

import { GET } from "./route";

/** setContributionStatus's resolvedBy has a foreign key, so accepting a row needs a real user. */
const RESOLVER = "test-contributions-export-route";

/** A bucket no other run shares, so a concurrent run's cleanup can't race this one's rows. */
const ip = `test-${Math.random().toString(36).slice(2, 10)}`;
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
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
  await db().query(`delete from "npc_resolution" where "npcId" = $1`, [npcId]);
});

afterAll(async () => {
  await db().query(`delete from "user" where "id" = $1`, [RESOLVER]);
  await closeDb();
});

async function acceptedRow(key: string, meta: Record<string, string>) {
  await createContribution({
    source: "quests",
    key,
    locale: "enUS",
    build: "1.12.1.5875",
    text: "Some line of dialogue.",
    meta,
    raw: `raw:${key}`,
    dedup: `dedup:${key}:${ip}`,
    body: null,
    name: null,
    email: null,
    userId: null,
    ip,
  });
  const { rows } = await db().query<{ id: number }>(
    `select "id" from "contribution" where "dedup" = $1`,
    [`dedup:${key}:${ip}`],
  );
  await setContributionStatus(rows[0].id, "accepted", RESOLVER);
}

async function exported(): Promise<Array<Record<string, unknown>>> {
  const response = await GET();
  const text = await response.text();
  return text
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

describe("GET /api/contributions/export", () => {
  it("carries the resolved race, gender, flavor and provenance for a row with a known npc", async () => {
    await upsertResolution({
      npcKind: "creature",
      npcId,
      npcName: "Some Guard",
      race: "tauren",
      gender: "male",
      flavor: "grim",
      provenance: "moderator",
      confirmed: true,
      modelFileId: 122055,
      sex: 0,
      creatureType: "Humanoid",
      build: "1.12.1.5875",
      note: null,
      resolvedBy: RESOLVER,
    });

    await acceptedRow(`npc:${npcId}`, { kind: "creature", npc: `${npcId} Some Guard` });

    const rows = await exported();
    const row = rows.find((r) => r.key === `npc:${npcId}`);
    expect(row).toMatchObject({
      race: "tauren",
      gender: "male",
      flavor: "grim",
      npcProvenance: "moderator",
      npcConfirmed: true,
    });
  });

  it("leaves the npc fields null and unconfirmed for a row with no resolution", async () => {
    await acceptedRow(`plain:${npcId}`, { locale: "enUS" });

    const rows = await exported();
    const row = rows.find((r) => r.key === `plain:${npcId}`);
    expect(row).toMatchObject({
      race: null,
      gender: null,
      flavor: null,
      npcProvenance: null,
      npcConfirmed: false,
    });
  });

  // The whitelist discipline the route's own docstring calls out: nothing gained here may open
  // a hole in it.
  it("still excludes the fields the export deliberately never carries", async () => {
    await acceptedRow(`plain2:${npcId}`, { locale: "enUS" });

    const rows = await exported();
    const row = rows.find((r) => r.key === `plain2:${npcId}`);
    expect(row).toBeDefined();
    expect(row).not.toHaveProperty("ip");
    expect(row).not.toHaveProperty("raw");
    expect(row).not.toHaveProperty("userId");
    expect(row).not.toHaveProperty("body");
    expect(row).not.toHaveProperty("email");
    expect(row).not.toHaveProperty("name");
  });
});
