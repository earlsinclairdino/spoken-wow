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
   The other accepts the popup. Whoever invites leads the party.
3. Talk to an NPC. The line opens on both screens and starts on both together.
4. Press **Remember This Party** (on the settings page, or in the window): next time you are
   both online, the party forms by itself.

Grouping is not needed: the party is the addon's own, kept by name, and survives leaving the
group, joining a raid, or questing apart.

## What it does

- **A party, like the game's.** It begins with an invitation and lasts until fewer than two
  are left. Whoever invites first is the leader: only the leader invites, removes, passes the
  lead (**Lead** in the window or on the page, the portrait menu, `/sps lead <name>`) and sets
  the party's rules. Everyone sees the same party, in the window and in `/sps members`. A
  `/reload` or a short disconnect does not end it; should the leader vanish, the first by name
  of those still online takes over. Another character on the same computer is in no party
  until it invites or is invited.
- **The party's rules**, the leader's to set, applied on every computer: **Stop, Replay and Skip
  Follow** (anyone's, only the leader's, or nobody's: with Nobody the lines play through and
  the player's buttons are greyed for everyone, the leader included; with Only the Leader
  they are greyed for the others, with the reason on hover), **Who Plays the Sound** (below),
  **Quests Are Shared By** (anyone, the default; only the leader; or nobody), and which kinds of
  line are **Played Together**. The others see the rules greyed on their page.
- **Lines played together.** A quest line, greeting or gossip, zone lore or book page queued
  on one computer is announced to the others. They rebuild it from their own voice packs and
  hold it. When it reaches the front of the queue, the computer that queued it says when to
  start: after half the slowest member's round trip, when that member hears it. On the Forever
  beta that is about half a second, and the computers start within about 0.1 s of each other.
- **Lines only one of you can trigger.** A class quest or a turn-in the others have not
  reached plays for everyone, with its words. A computer with no file for it shows the player
  and the captions without sound.
- **Never twice.** Talking to the same NPC right after the other did does not replay the line.
  When two of you start the same line at once, the leader's copy is played.
- **Quests.** A member shares a quest it accepts from an NPC with the party, as Quests Are
  Shared By allows (anyone, by default); a quest a member shares is accepted for you, without
  its line being read again. Each computer can switch either off for itself (Share Quests I
  Accept, Accept Quests the Party Shares).
- **Same room.** The leader chooses which computer plays the sound (**Sound**, wherever Lead
  is). The others switch Spoken to captions only for as long as that computer is online,
  without changing Spoken's own setting. A member who would rather decide for itself sets
  **This Computer's Sound** (plays the sound, or captions only); the party sees "own sound"
  beside its name.
- **The auto-form list.** Who to form a party with as soon as you are both online, per
  character. **Remember This Party** puts the party's members on it, with who led and the
  rules; **Remember Parties Automatically** does that as the party changes. Each member added
  is told, and asked whether to accept your invitations without the popup (**Auto-accept**,
  which they can change in their own list). While a listed character is not in the party, it
  is greeted every heartbeat; when it answers from no party, whoever led the remembered party,
  if online, else the first by name among those online, invites the others, with the
  remembered rules; a party already running has its leader invite the newcomer.
- **The window.** The party, a row per member with Lead and Sound (the leader's to press),
  every queued line and how far each computer got with it, and what went wrong; the gear
  opens the settings, Remember the list. By default it only appears when something is wrong;
  Spoken's minimap menu (Open Party Window) and `/sps window` open it.

Settings: **Options > AddOns > Spoken > Party Sync**, or `/sps settings`.

## Commands

| Command | |
|---|---|
| `/sps invite <name>` | invite a character (starts a party, led here, when in none); `/sps remove <name>`, `/sps leave` |
| `/sps members` | the party, who is online, who leads, which computer has the sound |
| `/sps lead [<name>]` | who leads; with a name, pass the lead (the leader's to do) |
| `/sps room [none\|me\|<name>]` | which computer plays the sound, a rule of the party's |
| `/sps controls [anyone\|leader\|nobody]` | whose Stop, Replay and Skip act everywhere, a rule of the party's |
| `/sps share [anyone\|leader\|nobody]` | whose accepted quests are shared with the party, a rule of the party's |
| `/sps sound [party\|sound\|captions]` | this computer's sound: as the party decides, or its own |
| `/sps remember [on\|off]` | the party onto the auto-form list; `on`/`off`: remember parties automatically |
| `/sps list [add <name> \| remove <name> \| auto <name> on\|off]` | the auto-form list |
| `/sps sync` | the lines played together this session, and each member's state |
| `/sps test <questID>` | queue a quest's accept line here, to try the sync without its NPC |
| `/sps window`, `/sps settings` | the window, the settings |
| `/sps logs [count]` | Spoken's debug log, this computer's and the party's collected ones on one timeline, to copy |
| `/sps logs pull [count]` | ask every member online for their last lines (400 by default) |
| `/sps logs clear` | empty this computer's log and the collected ones; a new session starts |
| `/sps logs clear all` | the same, and every member online clears theirs: one new session for the party |
| `/sps status` | the party, the debug log, the leader, the rules, the sound, and each member; the same lines `/spoken diagnostics` shows |
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
| `HI` | version, reply, session, own | hello: at login, when the group changes, to the auto-form list each heartbeat; names the party this client is in, and whether it decides its own sound |
| `IV` / `IA` / `ID` | session | invite to the party, accepted, declined or left or removed (one naming another party is stale) |
| `RO` | session, leader, members | the roster, from the leader, whenever it changes; a member not in it is out |
| `PS` | controls, room, sync, share | the rules, from the leader: whose controls, which computer plays the sound, four flags for the kinds played together, whose accepted quests are shared (missing from a 0.4.0 leader: anyone) |
| `RM` | | "I added you to my auto-form list": the other side is asked whether to auto-accept |
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
source's own, `Spoken:SetCaptionsOnlyOverride` for the room, and `Spoken:SetControlGate` for
the rules: the player's skins ask it before enabling Stop, Replay and Skip, and show its reason
in their tooltip.

Saved: the computer's own settings and the collected logs in `SpokenPartySyncDB`; the party
and the auto-form list per character, in `SpokenPartySyncCharDB`.

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
- `party`: the party started, joined, resumed and ended, members in and out, the roster and
  the rules received, the leader and why each time it changes, invitations, the auto-form
  list's doings, settings changed on the page;
- `room`: whether this computer plays the sound.

Spoken's own lines for the queue (queued, started, stopped, dropped, and why) are beside them.
The module keeps the last 2000 lines in its saved variables, written at a reload, so they are in
`WTF\Account\<account>\SavedVariables\Spoken_Developer.lua`; Report > **Write the Debug Log for an
AI Agent** reloads for that. `scripts/developer/read-log.py` reads it with the collected logs.

`Diagnostics.lua` adds a **Spoken Party Sync** block to `/spoken diagnostics` and to every
snapshot the log takes (`/sps status` prints it): the party and its id, the leader and why,
the rules, which computer plays the sound, this computer's own sound, each member's state,
round trip, version and last message, the auto-form list, and in the detailed snapshot the
lines played together lately, the open problems and the collected logs.

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
| `Core.lua` | the addon table, saved settings (the computer's in `SpokenPartySyncDB`, the character's party and auto-form list in `SpokenPartySyncCharDB`), problems |
| `Names.lua` | Forever's names and whisper addresses |
| `Comm.lua` | addon messages: escaping, pieces, pacing, "No player named" |
| `Peers.lua` | the party: the session, its roster and rules, invitations, presence, round trips, the leader, the connection tests |
| `Autoform.lua` | the auto-form list: remembering a party, greeting and inviting its members |
| `Log.lua` | the party's debug logs: pulling the members' into Spoken's log as a source, clearing them all |
| `Lines.lua` | a line's description and its rebuild |
| `Sync.lua` | announcing, holding, starting together, acknowledgements, controls and their gate |
| `Accept.lua` | quests shared and accepted |
| `Room.lua` | one computer plays the sound, or this one decides for itself |
| `Diagnostics.lua` | the party's state as lines, for `/sps status` and Spoken's diagnostics |
| `UI/Window.lua`, `UI/Options.lua`, `UI/UnitMenu.lua` | the window, the settings page, the portrait menu |
| `UI/Layout.lua` | byte-identical in every Spoken addon |
| `Events.lua`, `Commands.lua` | wiring, `/sps` |

Tests: `tests/lua/partysync_*_test.lua`, run by `make test-player`.
