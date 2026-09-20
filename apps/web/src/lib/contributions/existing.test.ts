import { describe, expect, it } from "vitest";

import { corpusLookup, zoneSlug } from "./existing";

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
});

describe("zoneSlug", () => {
  it("lower-cases, strips apostrophes and spaces to hyphens", () => {
    expect(zoneSlug("Sen'jin Village")).toBe("senjin-village");
  });
});
