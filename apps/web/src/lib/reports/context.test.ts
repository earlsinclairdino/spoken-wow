import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { addonVersion, contextFacts, contextFrom, isOlder } from "./context";

const fixture = (name: string) =>
  readFileSync(new URL(`../../../../../tests/fixtures/contributions/${name}`, import.meta.url), "utf8");

describe("contextFrom", () => {
  it("reads the addon's envelope into fields and text", () => {
    const context = contextFrom(fixture("quests-observed.txt"), "quests");
    expect(context?.fields.quest).toBe("76156");
    expect(context?.text).toBe("We'll need to work on your stealth skills, druid.");
  });

  it("drops another section's envelope, a broken one and anything not a string", () => {
    expect(contextFrom(fixture("quests-observed.txt"), "readables")).toBeNull();
    expect(contextFrom(fixture("quests-observed.txt").replace("druid", "rogue"), "quests")).toBeNull();
    expect(contextFrom({ fields: {} }, "quests")).toBeNull();
  });
});

describe("addonVersion", () => {
  it("is the release after the addon's name, and nothing for a checkout", () => {
    expect(addonVersion({ fields: { addon: "SpokenQuests/3.4.0" }, text: null })).toBe("3.4.0");
    expect(addonVersion({ fields: { addon: "SpokenBooks/3.0.0-beta.2" }, text: null })).toBe("3.0.0-beta.2");
    expect(addonVersion({ fields: { addon: "SpokenZones/dev" }, text: null })).toBeNull();
  });
});

describe("isOlder", () => {
  it("compares by number, not by text", () => {
    expect(isOlder("3.4.0", "3.10.0")).toBe(true);
    expect(isOlder("3.10.0", "3.4.0")).toBe(false);
    expect(isOlder("3.4.0", "3.4.0")).toBe(false);
  });

  it("puts a beta before its release", () => {
    expect(isOlder("3.0.0-beta.3", "3.0.0")).toBe(true);
    expect(isOlder("3.0.0-beta.2", "3.0.0-beta.10")).toBe(true);
    expect(isOlder("3.0.0", "3.0.0-beta.3")).toBe(false);
  });
});

describe("contextFacts", () => {
  it("names the addon, the client, the NPC and the quest", () => {
    const context = contextFrom(fixture("quests-observed.txt"), "quests")!;
    expect(contextFacts(context)).toEqual([
      { label: "Addon", value: "SpokenQuests 2.0.4" },
      { label: "Client", value: "1.60.1/69913" },
      { label: "Language", value: "enUS" },
      { label: "NPC", value: "9123 Boarton Shadetotem" },
      { label: "Quest", value: "76156 progress Stalk With The Earthmother" },
      { label: "Seen", value: "creature, Humanoid, male" },
    ]);
  });
});
