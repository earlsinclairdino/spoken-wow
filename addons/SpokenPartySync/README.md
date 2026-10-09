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
4. Press **Remember This Party** (on the settings page, or in the window's title menu), or
   **Remember** when the window offers it as the party ends: next time you are both online, the
   party forms by itself.

Grouping is not needed: the party is the addon's own, kept by name, and survives leaving the
group, joining a raid, or questing apart.

## What it does

- **A party, like the game's.** It begins with an invitation and lasts until fewer than two
  are left. Whoever invites first is the leader: only the leader invites, removes, passes the
  lead (**Make Leader** on a member's row in the window, **Lead** on the page, the portrait menu,
  `/sps lead <name>`) and sets the party's rules. Everyone sees the same party, in the window and in `/sps members`. A
  `/reload` or a short disconnect does not end it; should the leader vanish, the first by name
  of those still online takes over. Another character on the same computer is in no party
  until it invites or is invited.
- **The party's rules**, the leader's to set, applied on every computer: **Who Controls Playback**
  (Anyone, the default; The Leader; or Nobody: with Nobody the lines play through and the
  player's buttons are greyed for everyone, the leader included; with The Leader they are
  greyed for the others, with the reason on hover), **Who Plays What**: each kind of sound (below),
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
  its line being read again. Each computer can switch either off for itself (Auto-share Quests
  I Accept, Auto-accept Shared Quests). **Share Everyone's Quests** (the window's title menu,
  `/sps quests`) has every member share every quest the game lets it share, one every two
  seconds; a member's row asks that member alone (**Ask ... to Share Quests**, **Share My
  Quests** on your own). Anyone may ask; the rule still decides who shares, and the game shares
  only with members in its own group.
- **Same room.** The leader chooses which computer plays each kind of sound: the voice
  (Spoken's lines), the music, the effects, the ambience and the NPCs' dialog. Each is played
  by every computer, by one (while it is online), or by every computer but some. **Play All
  Sound On** (the page), **Play Sound Here** (a member's row in the window), **Sound** (the
  page's party block) and the window's Audio menu put them all on one computer; each channel
  apart is under **Advanced** (a submenu in the window, rows that open on the page, shown anyway
  while the channels differ). A computer
  that does not play the voice shows Spoken's lines as captions, without changing Spoken's own
  setting; one that does not play a game channel has its switch (`Sound_EnableMusic`,
  `Sound_EnableSFX`, `Sound_EnableAmbience`, `Sound_EnableDialog`) off while in the party. The
  player's value is kept first and put back when the party ends or the rule changes, at logout
  and `/reload`, and at the next login after a crash; volumes are never touched. A member who
  would rather decide for itself answers **Follow the Party** with No, Play My Own Sound or No,
  Mute My Own Sound (or each channel apart, under Advanced), on the page (My Computer), in the
  window's Audio menu, or with the round button beside Stop, whoever leads; the party sees
  "own audio" beside its name. A "no voice file" problem in the window offers
  **Mute There**: every computer but that one plays the voice.
- **The usual party.** Who to form a party with as soon as you are both online, per
  character. **Remember This Party** puts the party's members on it, with who led and the
  rules. When a party ends that lasted ten minutes or more, played at least one line together,
  lost nobody on the way and whose people are not on the list yet, the window asks once:
  "Play with Lala again?" **Remember** or **Not now** (never asked again for the same people).
  Each member added is told, and asked whether to accept your invitations without the popup (**Auto-accept**,
  which they can change in their own list). While a listed character is not in the party, it
  is greeted every heartbeat; when it answers from no party, whoever led the remembered party,
  if online, else the first by name among those online, invites the others, with the
  remembered rules; a party already running has its leader invite the newcomer.
- **The window** ("Spoken Party"). Its title, or a right-click anywhere in it that is not a
  button, opens a menu (Settings, Remember This Party, Compact, Leave Party); beside it, how
  the last line played together went (in sync, late, missed), Share Everyone's Quests (the
  quest mark in a circle of arrows), Follow the Party (a linked chain; broken while this computer
  plays its own sound) and the player's Stop/Replay (all three in a party only), and a small
  close cross. Under the title, the rules as chips (Audio, Playback,
  Quests; on a second row when they do not fit), the leader's to change, with this computer's
  own sound in the Audio menu for everyone. Then a row per member with one tag (no answer for
  how long, voice, leads, own audio; the rest on hover) and a menu on click (Make Leader, Play
  Sound Here, Remove from Party, Whisper, and Versions: what that computer runs, module by
  module, and whether its modules can play the party's lines; on your own row Leave Party
  instead of Remove and Whisper). Each hello is also a handshake: every computer, this one
  included, is held against the leader's (Spoken Party Sync, Spoken, Quests, Zones, Books, and
  whether each can play the party's lines); one that differs gets an alert after its name, the
  differences in its tooltip and under Versions, and one chat line when it is found,
  and a row for each invitation still waiting ("invited 12 s"), whose menu has Invite Again,
  Cancel Invitation (their popup closes; an acceptance already on its way is answered by
  being sent away) and Whisper; the line that matters, with only the members behind on it under it and
  how many more are queued; and what went wrong, each with its fix beside it (Re-invite,
  Remove, Mute There, Dismiss). An invitation's outcome is one of those: declined, not
  online, or no answer within the popup's two minutes (most often Spoken Party Sync is not
  installed there), the last two with Re-invite. Re-invite asks back someone dropped from the
  party in the last ten minutes (into a new party with the old one's rules, if it ended), and
  they rejoin without a popup. Compact keeps the members and the line. By default it only
  appears when something is wrong or an invitation is waiting; Spoken's minimap menu (Open
  Party Window) and `/sps window` open it; only its X (or `/sps window`) closes it: Escape and
  the game's panels opening or closing leave it be. Nothing in it is protected, so it works in combat.

Settings: **Options > AddOns > Spoken > Party Sync**, or `/sps settings`.

## Commands

| Command | |
|---|---|
| `/sps invite <name>` | invite a character (starts a party, led here, when in none); `/sps remove <name>`, `/sps leave` |
| `/sps members` | the party, who is online, who leads, which computer has the sound |
| `/sps lead [<name>]` | who leads; with a name, pass the lead (the leader's to do) |
| `/sps audio [voice\|music\|effects\|ambience\|dialog\|all] [none\|me\|<name>]` | who plays a channel (all of them without one), a rule of the party's; `/sps room` is the voice's |
| `/sps controls [anyone\|leader\|nobody]` | who controls playback (Stop, Replay, Skip) everywhere, a rule of the party's |
| `/sps share [anyone\|leader\|nobody]` | whose accepted quests are shared with the party, a rule of the party's |
| `/sps sound [<channel>\|all] [party\|plays\|muted]` | this computer's own choice (the voice without a channel; `sound`/`captions` still work) |
| `/sps quests [me\|<name>]` | everyone shares every quest now; `me` here alone, a name asks that member |
| `/sps remember` | the party into your usual party, or the one that just ended, as the window offers |
| `/sps list [add <name> \| remove <name> \| auto <name> on\|off]` | your usual party |
| `/sps sync` | the lines played together this session, and each member's state |
| `/sps test <questID>` | queue a quest's accept line here, to try the sync without its NPC |
| `/sps window`, `/sps compact [on\|off]`, `/sps settings` | the window, its compact size, the settings |
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
| `HI` | version, reply, session, own, plays, modules | hello: at login, when the group changes, to the usual party each heartbeat, and when what it plays changes; names the party this client is in, whether it decides any channel itself, the channels it plays (`v m e a d`, `-` for none; missing before 0.5: the rules decide), and the Spoken modules it runs (`S=3.1.0;Q=3.1.0+;...`: Spoken, Quests, Zones, Books, Developer, DialogueUI, a `+` after a source that can rebuild the party's lines; the store's build and Party Sync's share a version number) |
| `IV` / `IA` / `ID` | session (`IV`: version, session, rejoin) | invite to the party, accepted, declined or left or removed (one naming another party is stale; from the inviter while its popup is up, the invitation withdrawn; answering an `IA` for an invitation withdrawn, leave); `rejoin` 1 asks back someone who was in a party with the inviter within ten minutes, who accepts without a popup |
| `RO` | session, leader, members | the roster, from the leader, whenever it changes; a member not in it is out |
| `PS` | controls, room, sync, share, audio | the rules, from the leader: whose controls, who plays the voice, four flags for the kinds played together, whose accepted quests are shared (missing from a 0.4.0 leader: anyone), and who plays each game channel (`music=<owner>;effects=...;ambience=...;dialog=...`, missing before 0.5: every computer). An owner is `none` (every computer), a member's key, or `-<key>,<key>` (every computer but those) |
| `RM` | | "I added you to my usual party": the other side is asked whether to auto-accept |
| `SQ` / `SA` | `SA`: count, why | "share every quest you can"; the answer: how many, or none and why (`rule`, `group`, `none`) |
| `LN` | id, src, event, questID, npcID, length, flags, textParts, name, title | a line queued; `src` is q, z or b |
| `TX` | id, seq, total, text | its words, in pieces |
| `GO` | id, startInMs | start it |
| `AK` | id, state, ms | queued, missing (no voice file: captions there), old (that module cannot rebuild a line: not the Party Sync build), absent (no such module), started (and how late), finished, dropped, yielded |
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
and the usual party per character, in `SpokenPartySyncCharDB`.

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
  the rules received, the leader and why each time it changes, invitations, the usual party's
  doings, settings changed on the page;
- `room`: whether this computer plays the sound.

Spoken's own lines for the queue (queued, started, stopped, dropped, and why) are beside them.
The module keeps the last 2000 lines in its saved variables, written at a reload, so they are in
`WTF\Account\<account>\SavedVariables\Spoken_Developer.lua`; Report > **Write the Debug Log for an
AI Agent** reloads for that. `scripts/developer/read-log.py` reads it with the collected logs.

`Diagnostics.lua` adds a **Spoken Party Sync** block to `/spoken diagnostics` and to every
snapshot the log takes (`/sps status` prints it): the party and its id, the leader and why,
the rules, which computer plays the sound, this computer's own sound, each member's state,
round trip, version and last message, the usual party, how the last line played together
went, and in the detailed snapshot the lines played together lately, the open problems and the
collected logs.

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
| `Core.lua` | the addon table, saved settings (the computer's in `SpokenPartySyncDB`, the character's party and usual party in `SpokenPartySyncCharDB`), problems |
| `Names.lua` | Forever's names and whisper addresses |
| `Comm.lua` | addon messages: escaping, pieces, pacing, "No player named" |
| `Peers.lua` | the party: the session, its roster and rules, invitations, presence, round trips, the leader, the connection tests |
| `Autoform.lua` | the usual party: remembering a party, greeting and inviting its members |
| `Log.lua` | the party's debug logs: pulling the members' into Spoken's log as a source, clearing them all |
| `Lines.lua` | a line's description and its rebuild |
| `Sync.lua` | announcing, holding, starting together, acknowledgements, controls and their gate |
| `Accept.lua` | quests shared and accepted |
| `Room.lua` | who plays each channel: the party's rule, or this computer's own choice |
| `Channels.lua` | the game's sound switches, off where the rule says, and back as the player had them |
| `Diagnostics.lua` | the party's state as lines, for `/sps status` and Spoken's diagnostics |
| `UI/Window.lua`, `UI/Options.lua`, `UI/UnitMenu.lua` | the window, the settings page, the portrait menu |
| `UI/Layout.lua` | byte-identical in every Spoken addon |
| `Events.lua`, `Commands.lua` | wiring, `/sps` |

Tests: `tests/lua/partysync_*_test.lua`, run by `make test-player`.
