// The character models, as race and gender, for resolving what an addon reported.
//
// The input is the community listfile filtered to character/<race>/<sex>/*.m2 -- 81 files
// across 32 races, about 2 KB once reduced to what we use. Regenerating it is a deliberate
// act rather than a build step: the listfile is 152 MB, it is a community artifact rather
// than an API, and a race is added to WoW about once a year.
//
//   curl -sL <listfile release url> \
//     | grep -E '^[0-9]+;character/[a-z]+/(male|female)/[a-z]+(_hd)?\.m2$' \
//     | node scripts/character-models.mjs > apps/web/src/lib/npc/character-models.json
import { readFileSync, writeFileSync } from "node:fs";

const rows = readFileSync(0, "utf8")
  .split("\n")
  .map((line) => line.trim())
  .filter(Boolean)
  .map((line) => line.split(";"));

const models = {};
for (const [fileId, path] of rows) {
  const [, race, gender] = path.split("/");
  if (gender !== "male" && gender !== "female") continue;
  models[fileId] = { race, gender };
}

const sorted = Object.fromEntries(
  Object.entries(models).sort(([a], [b]) => Number(a) - Number(b)),
);

writeFileSync(1, JSON.stringify(sorted, null, 2) + "\n");
