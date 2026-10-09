-- Spoken Party Sync's window and the page's newer rows: a member's one tag, the rules on chips,
-- the line that matters and who is behind on it, problems with their fixes beside them, the
-- compact window, and the round trips beside Ping the Party. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)

local LALA = P.LALA
local LOOKUP = { ["101-accept"] = 10, ["102-accept"] = 10, ["103-accept"] = 2 }

local function Fields(message) return message and table.concat(message.fields, "|", 2) or nil end

local function QuestLine(VO, questID)
	return { event = VO.Enums.SoundEvent.QuestAccept, questID = questID, name = "Giver", title = "Quest " .. questID,
		text = "Go.", unitGUID = "Creature-0-0-0-0-1234-0" }
end

local function Entry(entries, text)
	for _, entry in ipairs(entries) do
		if entry.text == text then return entry end
		local found = entry.children and Entry(entry.children, text)
		if found then return found end
	end
end
local ALL_FIVE = "voice, music, effects, ambience, npc dialog"
local GAME_FOUR = "music, effects, ambience, npc dialog"

local ns, VO, env, Spoken
local function Member(key)
	for _, member in ipairs(ns.windowModel.members or {}) do
		if member.key == key then return member end
	end
end
local function Labels(problem)
	local labels = {}
	for _, action in ipairs(problem.actions) do table.insert(labels, action.label) end
	return table.concat(labels, "|")
end

---------------------------------------------------------------- one tag a member
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:ShowWindow(true)
local me = ns:MyKey()
Expect("a member who leads is tagged so", Member("lala throwaway").tag, ns.L.TAG_LEAD)
Expect("...this character, with nothing to say, has no tag", Member(me).tag, nil)
P.Receive(stub, LALA, "PS", "anyone", "lala throwaway", "1111", "anyone")
Expect("the voice comes before the lead: one tag only", Member("lala throwaway").tag, ns.L.TAG_SOUND)
Expect("...both in the tooltip", table.concat(Member("lala throwaway").tags, ","), "leads,voice")
Expect("...which says what her computer plays", Member("lala throwaway").plays, format(ns.L.ROW_PLAYS_FMT, ALL_FIVE))
Expect("...and what this one does", Member(me).plays, format(ns.L.ROW_PLAYS_FMT, GAME_FOUR))
ns.Room:SetOwn("captions")
Expect("this computer deciding its own sound says so", Member(me).tag, ns.L.TAG_OWN_SOUND)
Expect("...and still plays no voice", Member(me).plays, format(ns.L.ROW_PLAYS_FMT, GAME_FOUR))
ns.Room:SetOwn("sound")
Expect("...playing it after all, the voice is what it says", Member(me).tag, ns.L.TAG_SOUND)
Expect("...its own choice in the tooltip", table.concat(Member(me).tags, ","), "voice,own audio")
ns.Room:SetOwn("")
stub.Advance(30)
ns:RefreshWindow()
local quiet = ns.Peers:Quiet("lala throwaway")
Expect("a member silent past a heartbeat shows that first, and for how long",
	quiet ~= nil and Member("lala throwaway").tag, quiet and format(ns.L.STATE_QUIET_FMT, quiet))
Expect("...with a yellow dot", Member("lala throwaway").dot, "quiet")
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0)
ns:RefreshWindow()
Expect("her answer puts the voice back", Member("lala throwaway").tag, ns.L.TAG_SOUND)
Expect("the window's rows carry the same", ns.windowRows[2].tag.text:find(ns.L.TAG_SOUND, 1, true) ~= nil, true)

---------------------------------------------------------------- the chips
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:ShowWindow(true)
local window = _G.SpokenPartySyncWindow
local chips = ns.windowModel.chips
Expect("the chips read the party's rules", chips.audio.text .. "|" .. chips.playback.text .. "|" .. chips.quests.text,
	"Audio: Every Computer|Playback: Anyone|Quests: Auto-share")
Expect("...the playback rule is the leader's", chips.playback.reason, ns.L.OPT_RULES_LEADER)
Expect("...greyed on the window", window.chips.playback:IsEnabled(), false)
Expect("...saying why on hover", window.chips.playback.tip.reason, ns.L.OPT_RULES_LEADER)
Expect("the audio chip stays live: this computer's own sound is in it", window.chips.audio:IsEnabled(), true)
local audio = ns:WindowAudioMenu()
Expect("...where the party's rule is greyed for a member", Entry(audio, ns.L.ROOM_NOBODY).reason, ns.L.OPT_RULES_LEADER)
Entry(audio, ns.L.SOUND_OWN_CAPTIONS).onClick()
Expect("...and this computer's own choice is not", ns:DB().soundOwn, "captions")
Expect("...which the audio chip's tooltip tells", ns.windowModel.chips.audio.body:find(ns.L.SOUND_OWN_CAPTIONS:lower(), 1, true) ~= nil, true)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "leader")
Expect("with only the leader sharing quests, a member's Quests chip is greyed", ns.windowModel.chips.quests.reason, ns.L.SHARE_LEADER)
Expect("...and reads Manual", ns.windowModel.chips.quests.text, ns.L.CHIP_QUESTS_OFF)
P.Receive(stub, LALA, "RO", P.SESSION, "Tata Throwaway", "Lala Throwaway;Tata Throwaway")
Expect("leading, the playback chip is live", ns.windowModel.chips.playback.reason, nil)
Expect("...and the share chip too", ns.windowModel.chips.quests.text, ns.L.CHIP_QUESTS_ON)
P.Clear()
Entry(ns:WindowPlaybackMenu(), ns.L.CONTROLS_NOBODY).onClick()
Expect("the playback menu sets the rule for the party", Fields(P.Last("PS", LALA)), "nobody|none|1111|leader|music=none;effects=none;ambience=none;dialog=none")
Expect("...which the chip then reads", ns.windowModel.chips.playback.text, "Playback: Nobody")
window.chips.quests:Click()
Expect("the quests chip switches this computer's sharing", ns:DB().autoShare, false)
Expect("...and reads Manual", ns.windowModel.chips.quests.text, ns.L.CHIP_QUESTS_OFF)

---------------------------------------------------------------- the line, who is behind, and how it went
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
for questID = 101, 103 do
	VO.Player:Enqueue(QuestLine(VO, questID))
	P.Receive(stub, LALA, "AK", questID .. "-accept", "queued")
end
stub.Advance(0.55)
ns:ShowWindow(true)
local line = ns.windowModel.line
Expect("the window shows the line playing", line.state, ns.L.LINE_PLAYING)
Expect("...by its title", ns.windowBody:find("Quest 101", 1, true) ~= nil, true)
Expect("...and not the lines behind it", ns.windowBody:find("Quest 102", 1, true), nil)
Expect("...only how many wait", ns.windowBody:find(format(ns.L.WINDOW_MORE_FMT, 2), 1, true) ~= nil, true)
Expect("a member on time adds nothing under it", #line.progress, 0)
P.Receive(stub, LALA, "AK", "101-accept", "started", 230)
line = ns.windowModel.line
Expect("a member who started late is shown under it", line.progress[1] and line.progress[1].text, format(ns.L.PEER_LATE_FMT, 230))
Expect("...and the sync reads late", ns.windowModel.health and ns.windowModel.health.kind, "late")
P.Receive(stub, LALA, "AK", "101-accept", "finished")
Expect("...still late once she finished it", ns.windowModel.health.kind, "late")
Spoken:Skip()
P.Receive(stub, LALA, "AK", "101-accept", "dropped")
Expect("a line skipped together is no miss", ns.windowModel.health.kind, "late")
stub.Advance(2.5)
P.Receive(stub, LALA, "AK", "102-accept", "missing")
ns:RefreshWindow()
Expect("a member with no voice file for the next one is shown under it", ns.windowModel.line.progress[1]
	and ns.windowModel.line.progress[1].text, ns.L.PEER_MISSING)
Expect("...and the sync reads missed", ns.windowModel.health.kind, "missed")
Expect("...with the problem below, and its fix: her computer off the voice", Labels(ns.windowModel.problems[1]), ns.L.ACTION_MUTE)

-- A line started elsewhere: its progress is the other computer's to show.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 0, "Giver", "Quest 102")
P.Receive(stub, LALA, "GO", "102-accept", 0)
stub.Advance(0.1)
ns:ShowWindow(true)
Expect("a line started elsewhere lists nobody's progress here", #ns.windowModel.line.progress, 0)
Expect("...and started on time, it reads in sync", ns.windowModel.health and ns.windowModel.health.kind, "sync")

---------------------------------------------------------------- problems and their fixes
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
VO.Player:Enqueue(QuestLine(VO, 101))
stub.Advance(3.5)
ns:ShowWindow(true)
local problem = ns.windowModel.problems[1]
Expect("a member who did not answer about a line is a problem", problem and problem.key, "answer:lala throwaway")
Expect("...with Re-invite and Remove beside it", Labels(problem), ns.L.ACTION_REINVITE .. "|" .. ns.L.ACTION_REMOVE)
Expect("...drawn as chips on its row", window.problems[1].chips[1].label.text, ns.L.ACTION_REINVITE)
Expect("...and her line says so", ns.windowModel.line.progress[1] and ns.windowModel.line.progress[1].text, ns.L.PEER_NO_ANSWER)
P.Clear()
window.problems[1].chips[1]:Click()
Expect("Re-invite from the leader invites her into the party she is in", Fields(P.Last("IV", LALA)), ns.version .. "|" .. P.SESSION)
Expect("...and greets her", P.Last("HI", LALA) ~= nil, true)
Expect("...and the problem goes", ns.windowModel.problems[1], nil)
ns:Problem("answer:lala throwaway", "Lala Throwaway did not answer.")
ns.windowModel.problems[1].actions[2].run()
Expect("Remove takes her out of the party", ns.Peers:IsMember(LALA), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:ShowWindow(true)
ns:Problem("answer:lala throwaway", "Lala Throwaway did not answer.")
problem = ns.windowModel.problems[1]
Expect("for a member, Remove is the leader's", problem.actions[2].reason, format(ns.L.ONLY_LEADER_FMT, "Lala Throwaway"))
Expect("...while Re-invite is not", problem.actions[1].reason, nil)
P.Clear()
problem.actions[1].run()
Expect("...and only greets her", P.Last("HI", LALA) ~= nil and P.Last("IV", LALA) == nil, true)
ns:Problem("test", "Something is wrong")
local dismiss
for _, item in ipairs(ns.windowModel.problems) do
	if item.key == "test" then dismiss = item end
end
Expect("any other problem can be dismissed", dismiss and Labels(dismiss), ns.L.ACTION_DISMISS)
dismiss.actions[1].run()
ns:RefreshWindow()
local still = false
for _, item in ipairs(ns.windowModel.problems) do
	if item.key == "test" then still = true end
end
Expect("...and goes", still, false)

---------------------------------------------------------------- Stop and Replay, compact, Escape
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
Expect("with nothing playing, Stop is greyed", window.pause:IsEnabled(), false)
Expect("...and says why", window.pause.tip.reason, ns.L.WINDOW_NOTHING_PLAYING)
VO.Player:Enqueue(QuestLine(VO, 101))
P.Receive(stub, LALA, "AK", "101-accept", "queued")
stub.Advance(0.55)
ns:RefreshWindow()
Expect("a line playing can be stopped", window.pause:IsEnabled() and window.pause.state, "stop")
window.pause:Click()
ns:RefreshWindow()
Expect("...and once stopped, replayed", window.pause.state, "replay")
Expect("...the tooltip saying so", window.pause.tip.title, ns.L.WINDOW_REPLAY)
Expect("the window is full width", window.width, 320)
Entry(ns:WindowTitleMenu(), ns.L.MENU_WINDOW_COMPACT).onClick()
Expect("Compact narrows it", window.width, 220)
Expect("...and leaves the chips out", window.chips.audio.shown, false)
Expect("...and the title menu ticks it", Entry(ns:WindowTitleMenu(), ns.L.MENU_WINDOW_COMPACT).checked, true)
Entry(ns:WindowTitleMenu(), ns.L.MENU_WINDOW_COMPACT).onClick()
Expect("...until it is unticked", window.width, 320)
ns:DB().window.show = "always"
window:GetScript("OnHide")()
ns:RefreshWindow()
Expect("closed with Escape, it stays closed whatever the setting", window.shown, false)
ns:Problem("test", "Something is wrong")
Expect("...until something goes wrong", window.shown, true)
ns:Resolve("test")

-- The window frame outlives a test's client, as a named frame does; hidden, it shows whether this one draws it.
_G.SpokenPartySyncWindow:Hide()
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().window.show = "always"
ns:RefreshWindow()
Expect("\"Always\" shows nothing without a party", _G.SpokenPartySyncWindow == nil or not _G.SpokenPartySyncWindow.shown, true)
Expect("...whose title menu greys what needs one", Entry(ns:WindowTitleMenu(), ns.L.OPT_LEAVE).reason, ns.L.OPT_IN_PARTY)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP, { account = { window = { show = "problems", scale = 0.7 } } })
Expect("a window size saved below 90% comes back at 90%", ns:DB().window.scale, 0.9)

---------------------------------------------------------------- the game's menu
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
local made = {}
-- The game's menu as its generator sees it: every entry recorded, submenus included.
local Add
local function NewDescription(kind, text, a, b)
	local description = { kind = kind, text = text, a = a, b = b }
	function description:SetTooltip(fn) self.tooltip = fn end
	description.CreateTitle, description.CreateButton = Add("title"), Add("button")
	description.CreateRadio, description.CreateCheckbox = Add("radio"), Add("checkbox")
	table.insert(made, description)
	return description
end
Add = function(kind)
	return function(_, text, a, b) return NewDescription(kind, text, a, b) end
end
_G.MenuUtil = { CreateContextMenu = function(owner, generate)
	made = {}
	generate(owner, NewDescription("root"))
end }
local function Made(text)
	for _, description in ipairs(made) do
		local plain = description.text and description.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		if plain == text then return description end
	end
end
window.chips.audio:Click()
local every = Made(ns.L.ROOM_NOBODY)
Expect("the audio chip opens the game's menu", every and every.kind, "radio")
Expect("...a member's rule entries greyed", every.text:find("|cff909090", 1, true) ~= nil, true)
stub.chat = {}
every.b()
Expect("...and clicking one says why instead", stub.chat[#stub.chat] and stub.chat[#stub.chat]:find(ns.L.OPT_RULES_LEADER, 1, true) ~= nil, true)
Made(ns.L.SOUND_OWN_CAPTIONS).b()
Expect("...while this computer's own entries work", ns:DB().soundOwn, "captions")
window.title:Click()
Expect("the title opens its menu", Made(ns.L.MENU_WINDOW_SETTINGS) ~= nil and Made(ns.L.MENU_WINDOW_COMPACT).kind, "checkbox")
window.rows[2]:Click()
Expect("a member's row opens theirs", Made(ns.L.MENU_WHISPER) ~= nil and Made(ns.L.MENU_MAKE_LEADER) ~= nil, true)
Expect("...each greyed entry with its reason on hover", Made(ns.L.MENU_MAKE_LEADER).tooltip ~= nil, true)
_G.MenuUtil = nil

---------------------------------------------------------------- the page
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.optionsPanel:Show()
ns:RefreshOptions()
local layout = ns.optionsLayout
local function PageRow(label)
	for _, entry in ipairs(layout.entries) do
		if entry.label == label then return entry.frame end
	end
end
P.Clear()
PageRow(ns.L.OPT_PING):Click()
local ping = P.Last("PI", LALA)
Expect("Ping the Party pings her", ping ~= nil, true)
Expect("...and says beside the button that it waits", ns.pingResult.text, "Lala " .. ns.L.PING_WAITING)
stub.Advance(0.2)
P.Receive(stub, LALA, "PO", ping.fields[2])
Expect("...then shows her round trip", ns.pingResult.text:match("^Lala %d+ ms$") ~= nil, true)
PageRow(ns.L.OPT_PING):Click()
stub.Advance(5.2)
Expect("...or that she did not answer", ns.pingResult.text, "Lala " .. ns.L.PING_NO_ANSWER)
Expect("Remember This Party is live for a party not yet remembered", PageRow(ns.L.OPT_REMEMBER).layoutReason, nil)
ns.Autoform:Remember()
ns:RefreshOptions()
Expect("...and greyed once it is", PageRow(ns.L.OPT_REMEMBER).layoutReason, ns.L.REMEMBERED_ALREADY)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "leader")
Expect("Auto-share is greyed for a member when only the leader shares", PageRow(ns.L.OPT_AUTO_SHARE).layoutReason, ns.L.SHARE_LEADER)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "nobody")
Expect("...and when nobody does", PageRow(ns.L.OPT_AUTO_SHARE).layoutReason, ns.L.SHARE_NOBODY)
ns.optionsPanel:Hide()

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync window tests passed")
