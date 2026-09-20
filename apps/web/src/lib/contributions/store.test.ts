/**
 * The store, against a real Postgres.
 *
 * Needs DATABASE_URL and migrations applied:
 *   docker compose up -d postgres && deploy/bin/migrate.sh "$PWD/web"
 */
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import { closeDb, db } from "@/lib/db";

import {
  acceptedContributions,
  countRecentContributions,
  createContribution,
  listContributions,
  recordContributionHit,
  setContributionStatus,
} from "./store";

/** resolvedBy has a foreign key, so resolving needs a user that exists (as in reports/store.test.ts). */
const RESOLVER = "test-contribution-resolver";

/** A bucket no other run shares, so tests can count rows for one IP safely (reports/store.test.ts:18). */
let ip: string;

/**
 * "dedup" is unique-indexed, so a literal shared with a concurrent run collides there too --
 * and worse than the ip case, a collision there doesn't fail loudly, it just bumps someone
 * else's count and shows up as a bogus number instead of an obvious assertion failure.
 */
let dedup: string;

/**
 * This run's triage key.
 *
 * The listing helpers take a status and nothing else, so an assertion that counts what comes
 * back counts every row in the table -- including the real ones a developer filed by hand while
 * testing the addon. Those are not pollution to be cleared; they are the data this feature
 * exists to collect, and a test that only passes against an empty database is a test that fails
 * the first time the feature is used.
 */
let key: string;

function ours<T extends { key: string }>(rows: T[]): T[] {
  return rows.filter((row) => row.key === key);
}

function submission(overrides: Record<string, unknown> = {}) {
  return {
    source: "quests" as const,
    key,
    locale: "ruRU",
    build: "1.12.1/5875",
    text: "Убей шестерых.",
    meta: { npc: "12345 X" },
    raw: "!SPOKEN1 quests\n",
    dedup: `${dedup}-one`,
    body: null,
    name: null,
    email: null,
    userId: null,
    ip,
    ...overrides,
  };
}

beforeEach(async () => {
  ip = `test-${Math.random().toString(36).slice(2, 10)}`;
  dedup = `test-${Math.random().toString(36).slice(2, 10)}`;
  key = `${Math.floor(Math.random() * 1e9)}:accept`;
  await db().query(
    `insert into "user" ("id", "name", "email", "emailVerified")
     values ($1, 'Test Resolver', $2, false)
     on conflict ("id") do nothing`,
    [RESOLVER, `${RESOLVER}@example.invalid`],
  );
});

afterEach(async () => {
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
  await db().query(`delete from "contribution_hit" where "ip" = $1`, [ip]);
});

afterAll(async () => {
  await db().query(`delete from "user" where "id" = $1`, [RESOLVER]);
  await closeDb();
});

describe("createContribution", () => {
  it("stores one", async () => {
    await createContribution(submission());
    const [row] = ours(await listContributions("new"));
    expect(row.key).toBe(key);
    expect(row.meta.npc).toBe("12345 X");
    expect(row.count).toBe(1);
  });

  it("bumps the count when the same text arrives again", async () => {
    await createContribution(submission());
    await createContribution(submission());
    const rows = ours(await listContributions("new"));
    expect(rows).toHaveLength(1);
    expect(rows[0].count).toBe(2);
  });

  it("keeps different text for the same key as its own row", async () => {
    await createContribution(submission());
    await createContribution(submission({ text: "Kill six.", dedup: `${dedup}-two` }));
    expect(ours(await listContributions("new"))).toHaveLength(2);
  });
});

describe("countRecentContributions", () => {
  it("counts inside the window and not outside it", async () => {
    await recordContributionHit(ip);
    expect(await countRecentContributions(ip, 60_000)).toBe(1);
    await db().query(
      `update "contribution_hit" set "createdAt" = now() - interval '2 hours' where "ip" = $1`,
      [ip],
    );
    expect(await countRecentContributions(ip, 60 * 60 * 1000)).toBe(0);
  });

  // The reason this table exists: ten identical pastes are one row and ten hits.
  it("counts a repeat paste that the dedup upsert collapsed into one row", async () => {
    for (let i = 0; i < 3; i++) {
      await createContribution(submission());
      await recordContributionHit(ip);
    }
    expect(ours(await listContributions("new"))).toHaveLength(1);
    expect(await countRecentContributions(ip, 60_000)).toBe(3);
  });
});

describe("setContributionStatus", () => {
  it("accepts a row and lists it for export", async () => {
    await createContribution(submission());
    const [row] = ours(await listContributions("new"));
    const updated = await setContributionStatus(row.id, "accepted", RESOLVER);
    expect(updated?.status).toBe("accepted");
    expect((await acceptedContributions()).map((r) => r.id)).toContain(row.id);
  });

  it("answers null for an id that is not there", async () => {
    expect(await setContributionStatus(999_999_999, "accepted", RESOLVER)).toBe(null);
  });
});
