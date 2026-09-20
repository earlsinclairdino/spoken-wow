/**
 * The reader, against envelopes the addon's own writer produced.
 *
 * The fixtures come from tests/lua/contribute_envelope_test.lua via `make contribute-fixtures`.
 * Hand-written expectations here would test this file against itself; these test it against
 * the Lua.
 */
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { checksum, decodeFragment, parseEnvelope } from "./envelope";

const fixture = (name: string) =>
  readFileSync(new URL(`../../../../../tests/fixtures/contributions/${name}`, import.meta.url), "utf8");

describe("parseEnvelope", () => {
  it("reads a quests envelope the addon wrote", () => {
    const result = parseEnvelope(fixture("quests-accept.txt"));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.source).toBe("quests");
    expect(result.value.fields.quest).toBe("9123");
    expect(result.value.fields.event).toBe("accept");
    expect(result.value.fields.locale).toBe("ruRU");
    expect(result.value.text).toBe("Убей шестерых.\n\nПотом возвращайся.");
  });

  it("reads a zones envelope, which carries no text", () => {
    const result = parseEnvelope(fixture("zones-subzone.txt"));
    expect(result.ok && result.value.text).toBe(null);
    expect(result.ok && result.value.fields.subzone).toBe("A Nook With No Lore");
  });

  it("reads the open-part-of-a-zone envelope's subzone field as empty, not absent", () => {
    // The addon always writes the field (Contribute.lua never omits it the way it omits
    // x/y); this is the shape checkEnvelope's bare-map branch has to treat as "no subzone".
    const result = parseEnvelope(fixture("zones-zone.txt"));
    expect(result.ok && result.value.fields.subzone).toBe("");
  });

  it("unescapes a >> line inside the text", () => {
    const result = parseEnvelope(fixture("quests-fenced.txt"));
    expect(result.ok && result.value.text).toBe("before\n>>\nafter");
  });

  it("refuses a body that does not match its checksum", () => {
    const tampered = fixture("quests-accept.txt").replace("9123", "9124");
    expect(parseEnvelope(tampered)).toEqual({ ok: false, error: "checksum" });
  });

  it("refuses a truncated paste", () => {
    const half = fixture("books-page.txt").slice(0, 120);
    expect(parseEnvelope(half).ok).toBe(false);
  });

  it("refuses a version it does not know", () => {
    const future = fixture("books-page.txt").replace("!SPOKEN1", "!SPOKEN2");
    expect(parseEnvelope(future)).toEqual({ ok: false, error: "version" });
  });

  it("refuses a source it does not know", () => {
    const wrong = fixture("books-page.txt").replace("!SPOKEN1 books", "!SPOKEN1 mail");
    expect(parseEnvelope(wrong)).toEqual({ ok: false, error: "source" });
  });

  it("refuses an oversize paste before parsing it", () => {
    expect(parseEnvelope("!SPOKEN1 books\n" + "x".repeat(70_000))).toEqual({
      ok: false,
      error: "oversize",
    });
  });

  it("tolerates the whitespace a paste picks up", () => {
    expect(parseEnvelope(`\n  \n${fixture("books-page.txt")}\n\n`).ok).toBe(true);
  });

  it("parses a paste whose newlines came from a Windows client", () => {
    const crlf = fixture("quests-accept.txt").replace(/\n/g, "\r\n");
    const result = parseEnvelope(crlf);
    expect(result.ok).toBe(true);
    expect(result.ok && result.value.text).toBe("Убей шестерых.\n\nПотом возвращайся.");
  });
});

describe("decodeFragment", () => {
  it("decodes the fixture Contribute:Encode wrote into the byte-identical plaintext envelope", async () => {
    const encoded = fixture("books-page.e1.txt").trim();
    const result = await decodeFragment(encoded);
    expect(result).toEqual({ ok: true, text: fixture("books-page.txt") });
  });

  it("refuses an empty fragment", async () => {
    expect(await decodeFragment("")).toEqual({ ok: false, error: "malformed" });
  });

  it("refuses a fragment that is not valid base64url", async () => {
    expect(await decodeFragment("not valid base64url!!!")).toEqual({ ok: false, error: "corrupt" });
  });

  it("refuses a truncated fragment (valid base64url, broken deflate)", async () => {
    const encoded = fixture("books-page.e1.txt").trim();
    const result = await decodeFragment(encoded.slice(0, Math.floor(encoded.length / 2)));
    expect(result).toEqual({ ok: false, error: "corrupt" });
  });

  // Bite-check: an assertion that would still pass with DecompressionStream deleted is not
  // pinning anything -- this one only means something if the branch above it is provably live.
  it("reports 'unsupported' when DecompressionStream is missing (older Safari)", async () => {
    const real = globalThis.DecompressionStream;
    // @ts-expect-error -- simulating an engine that never defined it
    delete globalThis.DecompressionStream;
    try {
      expect(await decodeFragment("anything")).toEqual({ ok: false, error: "unsupported" });
    } finally {
      globalThis.DecompressionStream = real;
    }
  });
});

describe("checksum", () => {
  it("agrees with the Lua writer on a real envelope", () => {
    const raw = fixture("quests-accept.txt");
    const [, body, sum] = raw.match(/^([\s\S]*\n)sum=(\d+)\n$/)!;
    expect(checksum(body)).toBe(Number(sum));
  });
});
