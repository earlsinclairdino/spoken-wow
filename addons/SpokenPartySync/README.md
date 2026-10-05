# Spoken Party Sync

Plays Spoken's lines together for players who quest together. Whoever talks to the NPC, the
line starts on every computer at once, skips on every computer at once, and in one room is
heard from one speaker while every screen shows the captions.

It needs Spoken 3.0 or later. It syncs whichever of Spoken Quests, Spoken Zones and Spoken
Books are installed, as long as they can rebuild a line from another client's description
(the source's `rebuild`, added with this addon).

## Getting started

1. Both characters install Spoken and Spoken Party Sync.
2. One of them invites the other: right-click their portrait and choose
   **Invite to Spoken Party**, or type `/sps invite Lala Throwaway` with their full name.
   The other accepts the popup.
3. Talk to an NPC. The line opens on both screens and starts on both together.

Grouping is not needed. The party is kept by name, so it survives leaving the group, joining a
raid, or questing apart.

## What it does

- **Lines played together.** A quest line, greeting or gossip, zone lore or book page queued
  on one computer is announced to the others. They rebuild it from their own voice packs and
  hold it. When it reaches the front of the queue, the computer that queued it says when to
  start: after half the slowest member's round trip, when that member hears it. On the Forever
  beta that is about half a second, and the computers start within about 0.1 s of each other.
- **Lines only one of you can trigger.** A class quest or a turn-in the others have not
  reached plays for everyone, with its words. A computer with no file for it shows the player
  and the captions without sound.
- **Never twice.** Talking to the same NPC right after the other did does not replay the line.
- **The leader.** One member leads: whoever leads the group, or whoever chose to in the
  settings, or else the first name. The leader's Pause, Skip and Stop reach everyone (or
  everyone's, or nobody's: a setting). When two of you start the same line at once, the
  leader's copy is played.
- **Quests.** The leader shares a quest it accepts from an NPC with the party; a quest a member
  shares is accepted for you, without its line being read again. Both are settings.
- **Same room.** Choose which computer plays the sound. The others switch Spoken to captions
  only for as long as that computer is online, without changing Spoken's own setting.
- **The window.** The party, every queued line and how far each computer got with it, and what
  went wrong. By default it only appears when something is wrong; `/sps window` opens it.

Settings: **Options > AddOns > Spoken > Party Sync**, or `/sps settings`.

## Commands

| Command | |
|---|---|
| `/sps invite <name>` | invite a character; `/sps remove <name>` to leave |
| `/sps members` | the party, who is online, who leads, which computer has the sound |
| `/sps lead auto\|me\|follow` | who leads |
| `/sps room auto\|me\|none\|<name>` | which computer plays the sound |
| `/sps sync` | the lines played together this session, and each member's state |
| `/sps test <questID>` | queue a quest's accept line here, to try the sync without its NPC |
| `/sps window`, `/sps settings`, `/sps log` | the window, the settings, every message in chat |
| `/sps logs [count]` | the debug log, this computer's and the party's collected ones on one timeline, to copy |
| `/sps logs pull [count]` | ask every member online for their last lines (400 by default) |
| `/sps logs clear` | empty this computer's log and the collected ones |
| `/sps api` | what this client supports, and which modules can play the party's lines |
| `/sps ping [name\|group]`, `/sps latency [name]` | round trips, by whisper and by party |
| `/sps probe [name]` | which way of writing a name a whisper reaches (grouped) |
| `/sps burst [count] [name]` | full-size messages sent at once, counted at the other end |

## How it works

Everything goes over addon messages, whispered to each member by name. On Forever names have
two parts and no realm: a whisper goes to the bare "First Last". The prefix is
`SpokenPartySync`, and a message is a two-letter kind and tab-separated fields:

| Kind | Fields | |
|---|---|---|
| `HI` | version, reply, lead, room | hello: at login, when the group changes, and when a setting the others read changes |
| `IV` / `IA` / `ID` | | invite, accepted, declined or removed |
| `LN` | id, src, event, questID, npcID, length, flags, textParts, name, title | a line queued; `src` is q, z or b |
| `TX` | id, seq, total, text | its words, in pieces |
| `GO` | id, startInMs | start it |
| `AK` | id, state, ms | queued, missing, started (and how late), finished, dropped, yielded |
| `SK` | id | skipped or stopped: remove it |
| `PZ` / `RS` | | pause, resume |
| `LQ` | token, count | ask a member for their debug log |
| `LH` / `LL` | token, total, now, version / token, seq, line | the log's header (with the sender's clock) and its lines, paced |
| `PI` / `PO`, `BU` / `BR`, `PQ` / `PA` | | ping, burst and probe tests |

Inside instances the client allows ten messages per prefix and one more each second; messages
are paced to fit, and a long text is left to each client's own copy rather than sent.

The addon uses only Spoken's public API: `Spoken:GetSource(key).rebuild`, a player-wide gate
that holds a line until its start (and whatever is behind it, so every queue keeps the same
order), `Spoken:RecheckGates` when it opens, the clip callbacks, an `admit` wrapped around each
source's own, and `Spoken:SetCaptionsOnlyOverride` for the room.

## Debug log

Every client keeps a log of the sync's steps, every message in and out, and the Spoken player's
queue as the player reports it (queued, started, stopped, dropped, and why), each line stamped
with `GetTime()`. It is kept in `SpokenPartySyncDB.log` (the last 2000 lines), so after a
`/reload` it is in `WTF\Account\<account>\SavedVariables\SpokenPartySync.lua`.

`/sps logs pull` (or **Collect the Party's Logs** in the settings) asks every member online for
theirs. Each answers with its clock reading and its lines, a few a second; the asker keeps them
in `SpokenPartySyncDB.collected` with the offset that maps the other clock onto its own (less
half the measured round trip). `/sps logs` shows all of them merged on one timeline in a box to
copy from, each line headed by whose it is.

## Files

| File | |
|---|---|
| `Core.lua` | the addon table, saved settings, problems |
| `Names.lua` | Forever's names and whisper addresses |
| `Comm.lua` | addon messages: escaping, pieces, pacing, "No player named" |
| `Peers.lua` | members, invitations, presence, round trips, the leader, the connection tests |
| `Log.lua` | the debug log, the player's queue events, pulling the party's logs, the copy box |
| `Lines.lua` | a line's description and its rebuild |
| `Sync.lua` | announcing, holding, starting together, acknowledgements, controls |
| `Accept.lua` | quests shared and accepted |
| `Room.lua` | one computer plays the sound |
| `UI/Window.lua`, `UI/Options.lua`, `UI/UnitMenu.lua` | the window, the settings page, the portrait menu |
| `UI/Layout.lua` | byte-identical in every Spoken addon |
| `Events.lua`, `Commands.lua` | wiring, `/sps` |

Tests: `tests/lua/partysync_*_test.lua`, run by `make test-player`.
