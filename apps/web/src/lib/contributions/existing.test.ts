import { describe, expect, it } from "vitest";

import { corpusLookup } from "./existing";

describe("corpusLookup", () => {
  it("reads a books key as the page id it is", () => {
    expect(corpusLookup("books", "261")).toEqual({ source: "books", pageId: 261 });
  });

  it("refuses a books key that is not digits", () => {
    expect(corpusLookup("books", "b261")).toBe(null);
  });

  it("splits a zones key on its first colon, slugging the rest", () => {
    expect(corpusLookup("zones", "1537:A Nook With No Lore")).toEqual({
      source: "zones",
      mapID: 1537,
      slug: "a-nook-with-no-lore",
    });
  });

  it("keeps a colon inside the subzone name out of the split", () => {
    expect(corpusLookup("zones", "1537:North: The Nook")).toEqual({
      source: "zones",
      mapID: 1537,
      slug: "north-the-nook",
    });
  });

  it("refuses a zones key whose map half is not digits", () => {
    expect(corpusLookup("zones", "npc:12345")).toBe(null);
  });

  it("answers null for quests, which has no corpus target to resolve", () => {
    expect(corpusLookup("quests", "9123:accept")).toBe(null);
  });

  /**
   * The reviewer's exact case: a hand-rolled canonicaliser slugged "The Underbog" to
   * "the-underbog", disagreeing with the corpus's "underbog" and turning a real match into a
   * false "missing". If this ever gets re-inlined instead of going through zones/tools.ts's
   * `normaliseKey`/`slugFor` bridge, this is the assertion that should go red first.
   */
  it("drops a leading 'The' the way the corpus's own normaliseKey does", () => {
    expect(corpusLookup("zones", "1:The Underbog")).toEqual({
      source: "zones",
      mapID: 1,
      slug: "underbog",
    });
  });

  it("drops a leading 'The' from a multi-word subzone too", () => {
    expect(corpusLookup("zones", "1:The Cape of Stranglethorn")).toEqual({
      source: "zones",
      mapID: 1,
      slug: "cape-of-stranglethorn",
    });
  });
});
