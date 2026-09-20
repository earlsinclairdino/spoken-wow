import { describe, expect, it } from "vitest";

import { submissionFrom } from "./submission";
import type { Envelope } from "./envelope";

const quests: Envelope = {
  source: "quests",
  fields: { quest: "9123", event: "accept", locale: "ruRU", build: "1.12.1/5875", npc: "12345 X" },
  text: "Убей шестерых.",
};

describe("submissionFrom", () => {
  it("keys a quest on its id and event", () => {
    expect(submissionFrom(quests, "raw")?.key).toBe("9123:accept");
  });

  it("keys gossip on the npc, which is all a gossip envelope has", () => {
    const gossip: Envelope = { source: "quests", fields: { npc: "12345 X", locale: "enUS" }, text: "Hail." };
    expect(submissionFrom(gossip, "raw")?.key).toBe("npc:12345");
  });

  it("keys a page on the client-side checksum", () => {
    const books: Envelope = {
      source: "books",
      fields: { page: "1839201", book: "Ledger", number: "2", locale: "enUS" },
      text: "Words.",
    };
    expect(submissionFrom(books, "raw")?.key).toBe("1839201");
  });

  it("keys a place on its map and subzone", () => {
    const zones: Envelope = {
      source: "zones",
      fields: { map: "1537", subzone: "A Nook", zone: "Ironforge", locale: "enUS" },
      text: null,
    };
    const made = submissionFrom(zones, "raw");
    expect(made?.key).toBe("1537:A Nook");
    expect(made?.text).toBe(null);
  });

  it("refuses an envelope missing a key its source needs", () => {
    expect(submissionFrom({ source: "books", fields: { locale: "enUS" }, text: "x" }, "raw")).toBe(null);
  });

  it("refuses a quests or books envelope with no text, which is the whole payload", () => {
    expect(
      submissionFrom({ source: "quests", fields: { quest: "1", event: "accept" }, text: null }, "raw"),
    ).toBe(null);
  });

  it("dedups on the normalised text, so trailing whitespace is not a second row", () => {
    const spaced: Envelope = { ...quests, text: "Убей шестерых.   \n\n\n" };
    expect(submissionFrom(spaced, "raw")?.dedup).toBe(submissionFrom(quests, "raw")?.dedup);
  });

  it("does not dedup across locales", () => {
    const other: Envelope = { ...quests, fields: { ...quests.fields, locale: "enUS" } };
    expect(submissionFrom(other, "raw")?.dedup).not.toBe(submissionFrom(quests, "raw")?.dedup);
  });

  it("keeps the remaining fields as meta and defaults a missing locale", () => {
    const made = submissionFrom({ ...quests, fields: { quest: "1", event: "accept", npc: "7 Y" } }, "raw");
    expect(made?.locale).toBe("enUS");
    expect(made?.meta.npc).toBe("7 Y");
  });
});
