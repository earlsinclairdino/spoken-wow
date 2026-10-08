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

The party is the character's. Another character on the same computer is in no party until it
invites or is invited: the others know a member by its name, and take nothing from a name they
did not invite. Back on the first character, its party is there again.

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
- **The leader.** One member leads: whoever was chosen with **Lead** (in the window, on the
  settings page, on their portrait's menu, or `/sps lead <name>`), else whoever leads the
  group, else the first name. A choice is made for the whole party: every member online is
  told and saves the same, so the last one made is everyone's. The leader's Stop, Replay, Skip and Stop All reach
  everyone (or everyone's, or nobody's: a setting). When two of you start the same line at
  once, the leader's copy is played.
- **Quests.** The leader shares a quest it accepts from an NPC with the party; a quest a member
  shares is accepted for you, without its line being read again. Both are settings.
- **Same room.** Choose which computer plays the sound (**Sound**, wherever Lead is), for the
  whole party. The others switch Spoken to captions only for as long as that computer is
  online, without changing Spoken's own setting.
- **The window.** The party, a row per member with Lead and Sound, every queued line and how
  far each computer got with it, and what went wrong; the gear opens the settings. By default
  it only appears when something is wrong; Spoken's minimap menu (Open Party Window) and
  `/sps window` open it.

Settings: **Options > AddOns > Spoken > Party Sync**, or `/sps settings`.

## Commands

| Command | |
|---|---|
| `/sps invite <name>` | invite a character; `/sps remove <name>` to leave |
| `/sps members` | the party, who is online, who leads, which computer has the sound |
| `/sps lead auto\|me\|follow\|<name>` | who leads, for the whole party (`follow`, never this character, only here) |
| `/sps room auto\|me\|none\|<name>` | which computer plays the sound, for the whole party (`auto`, as chosen elsewhere, only here) |
| `/sps sync` | the lines played together this session, and each member's state |
| `/sps test <questID>` | queue a quest's accept line here, to try the sync without its NPC |
| `/sps window`, `/sps settings` | the window, the settings |
| `/sps logs [count]` | Spoken's debug log, this computer's and the party's collected ones on one timeline, to copy |
| `/sps logs pull [count]` | ask every member online for their last lines (400 by default) |
| `/sps logs clear` | empty this computer's log and the collected ones; a new session starts |
| `/sps logs clear all` | the same, and every member online clears theirs: one new session for the party |
| `/sps status` | the group, the debug log, the leader and why, the controls, the sound, what is played together, and each member; the same lines `/spoken diagnostics` shows |
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
| `CH` | kind, value | a choice for the whole party: `lead` (a member, or `auto`) or `room` (a member, or `none`); a member's own key becomes its `me` |
| `IV` / `IA` / `ID` | | invite, accepted, declined or removed |
| `LN` | id, src, event, questID, npcID, length, flags, textParts, name, title | a line queued; `src` is q, z or b |
| `TX` | id, seq, total, text | its words, in pieces |
| `GO` | id, startInMs | start it |
| `AK` | id, state, ms | queued, missing, started (and how late), finished, dropped, yielded |
| `SK` | id | skipped or stopped: remove it |
| `PZ` / `RS` | | stop, replay (`Spoken:Pause`, `Resume`) |
| `LQ` | token, count | ask a member for their debug log |
| `LH` / `LL` | token, total, now, version / token, seq, line | the log's header (with the sender's clock) and its lines, paced |
| `LC` / `LK` | | clear your log / cleared |
| `PI` / `PO`, `BU` / `BR`, `PQ` / `PA` | | ping, burst and probe tests |

Inside instances the client allows ten messages per prefix and one more each second; messages
are paced to fit, and a long text is left to each client's own copy rather than sent.

The addon uses only Spoken's public API: `Spoken:GetSource(key).rebuild`, a player-wide gate
that holds a line until its start (and whatever is behind it, so every queue keeps the same
order), `Spoken:RecheckGates` when it opens, the clip callbacks, an `admit` wrapped around each
source's own, and `Spoken:SetCaptionsOnlyOverride` for the room.

## Debug log

The log is Spoken's, kept by the Spoken Developer module (`Spoken:Log`; without the module
Party Sync keeps none, and `/sps logs` says so). It is on once the module is installed; **Enable
Debug Log Recording** in Spoken > Developer (or `/spoken log on|off`) switches it, on each
computer. Party Sync writes into it, each line stamped with `GetTime()`:

- `sync`: the sync's steps (announced, held, go, started, acknowledged, released), and every
  control: who stopped, replayed or skipped which line, sent (`stop here (<line>): told <members>`)
  or kept here and why (`kept here, the controls are the leader's, <name>'s`), received
  (`skip from <name>: removing <line>`) or ignored and why (`stop from <name> ignored: ...`);
- `msg`: every message in and out;
- `party`: members online, lost and offline, the leader and why each time it changes,
  invitations, the lead and room told to the others, settings changed on the page;
- `room`: whether this computer plays the sound.

Spoken's own lines for the queue (queued, started, stopped, dropped, and why) are beside them.
The module keeps the last 2000 lines in its saved variables, written at a reload, so they are in
`WTF\Account\<account>\SavedVariables\Spoken_Developer.lua`; Report > **Write the Debug Log for an
AI Agent** reloads for that. `scripts/developer/read-log.py` reads it with the collected logs.

`Diagnostics.lua` adds a **Spoken Party Sync** block to `/spoken diagnostics` and to every
snapshot the log takes (`/sps status` prints it): the group, the leader and why, the controls,
which computer plays the sound, what is played together, each member's state, round trip,
version and last message, and in the detailed snapshot the lines played together lately, the
open problems and the collected logs.

`/sps logs pull` (or **Collect the Party's Logs**, in Party Sync's section of the Developer
page) asks every member online for theirs. Each answers with its clock reading, whether its log
is on, and its lines, a few a second; the asker keeps them in `SpokenPartySyncDB.collected` with
the offset that maps the other clock onto its own (less half the measured round trip), and
hands them to Spoken as a log source. `/sps logs` (or Spoken's **Show the Log**) shows all of
them merged on one timeline in a box to copy from, each line headed by whose it is.
`/sps logs clear all` (**Clear the Party's Logs**) starts one new session for everyone.

## Files

| File | |
|---|---|
| `Core.lua` | the addon table, saved settings (the computer's in `SpokenPartySyncDB`, the character's party in `SpokenPartySyncCharDB`), problems |
| `Names.lua` | Forever's names and whisper addresses |
| `Comm.lua` | addon messages: escaping, pieces, pacing, "No player named" |
| `Peers.lua` | members, invitations, presence, round trips, the leader, the connection tests |
| `Log.lua` | the party's debug logs: pulling the members' into Spoken's log as a source, clearing them all |
| `Lines.lua` | a line's description and its rebuild |
| `Sync.lua` | announcing, holding, starting together, acknowledgements, controls |
| `Accept.lua` | quests shared and accepted |
| `Room.lua` | one computer plays the sound |
| `Diagnostics.lua` | the party's state as lines, for `/sps status` and Spoken's diagnostics |
| `UI/Window.lua`, `UI/Options.lua`, `UI/UnitMenu.lua` | the window, the settings page, the portrait menu |
| `UI/Layout.lua` | byte-identical in every Spoken addon |
| `Events.lua`, `Commands.lua` | wiring, `/sps` |

Tests: `tests/lua/partysync_*_test.lua`, run by `make test-player`.
