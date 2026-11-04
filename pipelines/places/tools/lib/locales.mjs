// The places half of the language list: which sound-pack folder a language ships in.
// What a language is -- its code, name, script and ElevenLabs code -- is shared with the
// site and the other pipelines, and lives in pipelines/lib/locales.mjs.
//
// Must stay in step with SpokenPlaces.LOCALES in addons/Spoken_Places/Language.lua;
// tools/validate.mjs fails the build if the two lists drift, the same way it
// already guards NormaliseAreaKey.

import { BASE_LOCALE, CODES, isClientLocale, LOCALES } from "../../../lib/locales.mjs";

// What the places tools import from here; anything else about a language, from the source.
export { BASE_LOCALE, CODES, isClientLocale, LOCALES };
