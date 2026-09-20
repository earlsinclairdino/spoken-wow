/**
 * The second public write path, against a real Postgres.
 *
 * Every defence here is only observable end to end, as the reports route's test says: a
 * honeypot that returned 400 would pass a unit test of the validator and still teach a script
 * to drop the field.
 *
 * Needs DATABASE_URL and migrations applied:
 *   docker compose up -d postgres && deploy/bin/migrate.sh "$PWD/web"
 */
import { readFileSync } from "node:fs";

import { afterAll, afterEach, describe, expect, it, vi } from "vitest";

import { closeDb, db } from "@/lib/db";

vi.mock("next/headers", () => ({ headers: async () => new Headers() }));
vi.mock("@/lib/auth", () => ({ auth: { api: { getSession: async () => null } } }));

import { POST } from "./route";

// A bucket no other run shares, so the rate-limit test can count one IP safely. The same
// reasoning as lib/reports/store.test.ts -- a fixed literal collides between concurrent runs
// against the shared dev database, and the collision shows up as a wrong count rather than an
// obvious failure.
const ip = `203.0.113.${Math.floor(Math.random() * 200) + 20}`;
const envelope = readFileSync(
  new URL("../../../../../../tests/fixtures/contributions/quests-accept.txt", import.meta.url),
  "utf8",
);

function post(body: unknown): Request {
  return new Request("https://example.com/api/contributions", {
    method: "POST",
    headers: { "content-type": "application/json", "x-real-ip": ip },
    body: JSON.stringify(body),
  });
}

afterEach(async () => {
  await db().query(`delete from "contribution" where "ip" = $1`, [ip]);
  await db().query(`delete from "contribution_hit" where "ip" = $1`, [ip]);
});

afterAll(async () => {
  await closeDb();
});

describe("POST /api/contributions", () => {
  it("stores a pasted envelope", async () => {
    expect((await POST(post({ envelope, body: "Nothing played." }))).status).toBe(200);
    const { rows } = await db().query<{ key: string; locale: string }>(
      `select "key", "locale" from "contribution" where "ip" = $1`,
      [ip],
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].key).toBe("9123:accept");
    expect(rows[0].locale).toBe("ruRU");
  });

  it("answers a filled honeypot with 200 and writes nothing", async () => {
    expect((await POST(post({ envelope, website: "http://spam.example" }))).status).toBe(200);
    const { rows } = await db().query(`select 1 from "contribution" where "ip" = $1`, [ip]);
    expect(rows).toHaveLength(0);
    // Not just the row: a bot that trips the honeypot must not be able to fill another
    // person's rate-limit bucket by sharing a NAT.
    const hits = await db().query(`select 1 from "contribution_hit" where "ip" = $1`, [ip]);
    expect(hits.rows).toHaveLength(0);
  });

  it("refuses a tampered envelope", async () => {
    const response = await POST(post({ envelope: envelope.replace("9123", "9124") }));
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("checksum");
  });

  it("refuses a body larger than the cap without parsing it", async () => {
    expect((await POST(post({ envelope: "x".repeat(200_000) }))).status).toBe(413);
  });

  it("reports a missing envelope as missing, not as a truncated paste", async () => {
    const response = await POST(post({}));
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("missing");
  });

  it("reports a non-string envelope as missing too", async () => {
    const response = await POST(post({ envelope: 12345 }));
    expect(response.status).toBe(400);
    expect((await response.json()).error).toBe("missing");
  });

  // Ten pastes of the same envelope are one row and ten hits; the limit is on the person.
  it("stops at the hourly limit", async () => {
    for (let i = 0; i < 10; i++) {
      expect((await POST(post({ envelope }))).status).toBe(200);
    }
    expect((await POST(post({ envelope }))).status).toBe(429);
  });

  it("never queues generation", async () => {
    const before = await db().query(`select count(*)::text as count from "regeneration_job"`);
    await POST(post({ envelope }));
    const after = await db().query(`select count(*)::text as count from "regeneration_job"`);
    // Counted rather than asserted empty: this database holds real jobs.
    expect(after.rows[0].count).toBe(before.rows[0].count);
  });
});
