import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { previewOf } from "./ContributeForm";

// There is no component-test setup in this repo (no @testing-library/*, and
// vitest.config.ts only collects src/**/*.test.ts, not .tsx) — so this exercises previewOf
// as the plain function it is, the same way BookList.test.ts exercises bookRuns.
const envelope = readFileSync(
  new URL("../../../../tests/fixtures/contributions/quests-accept.txt", import.meta.url),
  "utf8",
);

describe("previewOf", () => {
  it("shows what will be sent, field by field", () => {
    const preview = previewOf(envelope);
    expect(preview.ok).toBe(true);
    if (!preview.ok) return;
    expect(preview.rows).toContainEqual({ label: "Quest", value: "9123" });
    expect(preview.text).toContain("Убей шестерых.");
  });

  it("explains a bad paste in the reader's terms, not the parser's", () => {
    const preview = previewOf(envelope.slice(0, 80));
    expect(preview.ok).toBe(false);
    if (preview.ok) return;
    expect(preview.message).toMatch(/copied|whole/i);
  });

  it("says nothing at all about an empty box", () => {
    expect(previewOf("")).toEqual({ ok: false, message: "" });
  });
});
