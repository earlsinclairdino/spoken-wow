# Third-party code and content

`LICENSE` is an MIT grant over the code this project wrote. It is not a grant over
anything on this page. Three different things are here for three different reasons,
and they are not interchangeable.

## Vendored Lua libraries

Every addon ships the libraries it loads, because a WoW addon has no package manager:
the client loads what is in the folder. They are unmodified copies, and are found under
`addons/<Addon>/Libs/` — plus `addons/<Addon>/<client>/Libs/` for the 1.12, 2.4.3 and
3.3.5 clients, which need their own build of Ace3.

| Library | Used by | License |
|---|---|---|
| LibStub | every addon | Public domain (stated in the file header) |
| CallbackHandler-1.0 | Ace3 consumers, LibDataBroker | [Ace3 license](https://www.wowace.com/projects/ace3) — BSD-style, free use with attribution |
| Ace3 (AceAddon, AceConsole, AceDB, AceDBOptions, AceEvent, AceTimer, AceGUI-3.0, AceConfig-3.0, AceCore-3.0) | SpokenQuests, SpokenPlayer | [Ace3 license](https://www.wowace.com/projects/ace3) |
| LibDataBroker-1.1 | SpokenPlayer, SpokenZones | Public domain / CC0, per its project page |
| LibDBIcon-1.0 | SpokenPlayer, SpokenZones | Public domain, by Rabbit |
| [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) 1.0.2-release | SpokenPlayer | zlib License (`Libs/LibDeflate/LICENSE.txt`) |

If you are vendoring a new library, put its upstream license text beside it rather than
only adding a row here.

## The addons' own lineage

**SpokenQuests** began as a fork of **AI VoiceOver** (`AI_VoiceOver_Continued`), an
addon by Mrthinger and its later maintainers, and still carries structure from it —
the sound queue and the data-module loader most visibly. The fork adapted the removed
global addon-management APIs to `C_AddOns` and the gossip APIs to `C_GossipInfo`, was
renamed `VoiceOverRedux`, and is `SpokenQuests` today. Its sound packs deliberately
stay loadable by upstream's player, and upstream's packs stay loadable by this one.

**SpokenPlayer**'s sound queue is a port of that same queue, generalised so that
several feature addons share one window.

## Game text, lore and artwork

None of this is the project's to license, and the MIT grant does not reach it.

- **Quest and gossip text, creature and zone names, and every id the corpus is keyed
  on** are © Blizzard Entertainment. They are extracted from a [vmangos](https://github.com/vmangos/core)
  world database, which is itself a community reconstruction of that content. The
  extraction lives in `pipelines/quests/`; the exported reference tables under
  `pipelines/quests/assets/sql/exported/` come from the same place.
- **Zone and subzone lore prose** in `addons/SpokenZones/Data/` is derived from
  [Warcraft Wiki](https://warcraft.wiki.gg), which publishes under
  **CC BY-SA 3.0**. Re-use of that text carries the same terms, including attribution
  and share-alike. `pipelines/zones/tools/scrape.mjs` is what fetches it and records
  which article each line came from.
- **Book, letter and in-world text** for SpokenBooks comes from the same vmangos
  extraction as the quest corpus, and is likewise Blizzard's.
- Text submitted through `/contribute` is game text as well: a player's client is showing it and
  they are sending a copy. It sits on the same footing as the corpus above, and the same terms
  apply to it.
- **Map images, portrait frames and icons** derived from game assets
  (`PortraitFrameAtlas`, the continent maps) are Blizzard's.
- **The generated audio** is synthesised by [ElevenLabs](https://elevenlabs.io) from the
  text above. It is distributed through the sound-pack addons and is not in this
  repository; the terms that apply are ElevenLabs' and Blizzard's, not this project's.

This project is a fan work. It is not affiliated with, endorsed by, or sponsored by
Blizzard Entertainment. World of Warcraft and Blizzard Entertainment are trademarks or
registered trademarks of Blizzard Entertainment, Inc.
