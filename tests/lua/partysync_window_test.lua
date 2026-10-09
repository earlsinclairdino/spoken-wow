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
_G.UISpecialFrames = _G.UISpecialFrames or {}

local LALA = P.LALA
local LOOKUP = { ["101-accept"] = 10, ["102-accept"] = 10, ["103-accept"] = 2 }

local Fields = P.Fields

local QuestLine = P.QuestLine

local Entry = P.Entry
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
-- A member who is fine can be silent for two heartbeats and a round trip: pinged only at a
-- heartbeat that finds it silent for one.
stub.Advance(41)
ns:RefreshWindow()
Expect("a member silent for two heartbeats is not said to be silent", ns.Peers:Quiet("lala throwaway"), nil)
stub.Advance(9)
ns:RefreshWindow()
local quiet = ns.Peers:Quiet("lala throwaway")
Expect("a member silent past that shows it first, and for how long",
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

---------------------------------------------------------------- the audio menu, in layers
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:ShowWindow(true)
audio = ns:WindowAudioMenu()
local first = {}
for _, entry in ipairs(audio) do table.insert(first, entry.title or entry.text) end
Expect("the first layer is the plain choices, Advanced and Follow the Party", table.concat(first, "|"),
	table.concat({ ns.L.MENU_WHO_PLAYS, format(ns.L.ALL_ON_FMT, ns.L.ROOM_NOBODY), format(ns.L.ALL_ON_FMT, ns.L.ROOM_ME),
		format(ns.L.ALL_ON_FMT, format(ns.L.ROOM_MEMBER_FMT, LALA)), ns.L.MENU_ADVANCED,
		format(ns.L.MENU_FOLLOW_FMT, ns.L.FOLLOW_YES) }, "|"))
Expect("...the one in force ticked", audio[2].radio, true)
local advanced = Entry(audio, ns.L.MENU_ADVANCED)
local layered = #advanced.children == #ns.Room.CHANNELS
for i, channel in ipairs(ns.Room.CHANNELS) do
	local entry = advanced.children[i]
	layered = layered and entry.children ~= nil
		and entry.text == format(ns.L.AUDIO_RULE_FMT, ns.Room:Name(channel), ns.L.ROOM_NOBODY)
end
Expect("Advanced holds each kind of sound with its owner, each opening the owners", layered, true)
local follow = audio[#audio]
local answers = {}
for _, entry in ipairs(follow.children) do table.insert(answers, entry.title or entry.text) end
Expect("Follow the Party opens its answers, then Advanced", table.concat(answers, "|"),
	table.concat({ ns.L.OPT_FOLLOW, ns.L.FOLLOW_YES, ns.L.FOLLOW_PLAYS, ns.L.FOLLOW_MUTED, ns.L.MENU_ADVANCED }, "|"))
Expect("...whose Advanced holds each kind of sound decided here", #follow.children[5].children, #ns.Room.CHANNELS)
P.Clear()
Entry(audio, format(ns.L.ALL_ON_FMT, ns.L.ROOM_ME)).onClick()
Expect("All on My Computer puts every kind of sound on it", ns.Room:Summary(), ns:MyKey())
Expect("...for the whole party", Fields(P.Last("PS", LALA)):find("music=" .. ns:MyKey(), 1, true) ~= nil, true)
Entry(ns:WindowAudioMenu(), ns.L.FOLLOW_MUTED).onClick()
Expect("an answer to Follow the Party is this computer's", ns.Room:OwnSummary(), "muted")
Expect("...which the entry then reads", ns:WindowAudioMenu()[#audio].text, format(ns.L.MENU_FOLLOW_FMT, ns.L.FOLLOW_MUTED))
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
audio = ns:WindowAudioMenu()
Expect("for a member, the plain choices are the leader's", audio[2].reason, ns.L.OPT_RULES_LEADER)
Expect("...while following the party or not is theirs", Entry(audio, ns.L.FOLLOW_PLAYS).reason, nil)

---------------------------------------------------------------- Follow the Party, in the header
_G.SpokenPartySyncWindow:Hide()
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
Expect("out of a party there is no Follow the Party button", window.follow.shown, false)
Expect("...nor Share Everyone's Quests", window.share.shown, false)
P.Party(stub, ns)
ns:ShowWindow(true)
Expect("in one, it says this computer follows the party", window.follow.shown and window.follow.state, "follow")
Expect("...in its tooltip", window.follow.tip.title, ns.L.FOLLOW_ON_TITLE)
-- The glyph as a file this addon carries: the game's own icons drew nothing on Forever.
local function Shipped(texture)
	local file = texture and texture:match("^Interface\\AddOns\\SpokenPartySync\\(.+)$")
	local handle = file and io.open(here .. "/../../addons/SpokenPartySync/" .. file:gsub("\\", "/") .. ".tga", "rb")
	if handle then handle:close() end
	return handle ~= nil
end
Expect("...with a linked chain", window.follow.glyph.texture:find("GlyphLinked", 1, true) ~= nil, true)
Expect("...a file the addon carries", Shipped(window.follow.glyph.texture), true)
Expect("...shown through the cell its glyph is drawn in, as Stop's is",
	table.concat(window.follow.glyph.texCoord, ","), table.concat({ 0, 93 / 128, 0, 93 / 128 }, ","))
Expect("...and in the window's text", ns:WindowText():find(ns.L.FOLLOW_ON_WORD, 1, true) ~= nil, true)
window.follow:Click()
Expect("a click plays this computer's own sound, every kind of it", ns.Room:OwnSummary(), "plays")
Expect("...which the button then says", window.follow.state .. "|" .. window.follow.tip.title, "own|" .. ns.L.FOLLOW_OFF_TITLE)
Expect("...with what that does", window.follow.tip.body, ns.L.FOLLOW_OFF_TIP_PLAYS)
Expect("...and the chain broken", window.follow.glyph.texture:find("GlyphUnlinked", 1, true) ~= nil, true)
Expect("...the addon carries too", Shipped(window.follow.glyph.texture), true)
window.follow:Click()
Expect("a second click follows the party again", ns.Room:IsOwn(), false)
ns.Room:SetOwnChannel("music", "muted")
Expect("one kind of sound decided here is its own sound too", window.follow.state, "own")
Expect("...partly", window.follow.tip.body, ns.L.FOLLOW_OFF_TIP_PARTLY)
ns.Room:SetOwnChannel("music", "")

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
local text = ns:WindowText()
Expect("...by its title", text:find("Quest 101", 1, true) ~= nil, true)
Expect("...and not the lines behind it", text:find("Quest 102", 1, true), nil)
Expect("...only how many wait", text:find(format(ns.L.WINDOW_MORE_FMT, 2), 1, true) ~= nil, true)
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
ns.Sync.lines["alone"] = { id = "alone", role = "driver", state = "finished", peers = {}, at = GetTime(),
	startedAt = GetTime() + 1, endedAt = GetTime() + 2 }
Expect("a line nobody else was told of is no line played in sync", ns.Sync:Health(), "missed")
ns.Sync.lines["alone"] = nil
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
ns:Problem("answer:lala throwaway", "Lala Throwaway did not answer.", { kind = "silent", who = "lala throwaway" })
ns.windowModel.problems[1].actions[2].run()
Expect("Remove takes her out of the party", ns.Peers:IsMember(LALA), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:ShowWindow(true)
ns:Problem("answer:lala throwaway", "Lala Throwaway did not answer.", { kind = "silent", who = "lala throwaway" })
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

---------------------------------------------------------------- Stop and Replay, compact, closing it
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
-- What the game does on Escape and as its panels open or close: hide every frame it lists there.
local listed = false
for _, name in ipairs(_G.UISpecialFrames) do
	if name == "SpokenPartySyncWindow" then listed = true end
end
Expect("Escape and the game's panels leave it be: it is not among the frames they close", listed, false)
Expect("...nor would a hide by anything else count as closing it", window:GetScript("OnHide"), nil)
window.close:Click()
ns:RefreshWindow()
Expect("its X closes it, and it stays closed whatever the setting", window.shown, false)
ns:Problem("test", "Something is wrong")
Expect("...until something goes wrong", window.shown, true)
ns:ShowWindow(false)
ns:RefreshWindow()
Expect("closed again with that problem still there, it stays closed", window.shown, false)
ns:Problem("other", "Something else is wrong")
Expect("...until another one comes", window.shown, true)
ns:Resolve("other")
ns:ShowWindow(false)
ns:Resolve("test")
ns:Problem("test", "Something is wrong again")
Expect("...or the same one, gone and back", window.shown, true)
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
made = {}
window:GetScript("OnMouseUp")(window, "RightButton")
Expect("a right-click anywhere in the window opens the title's menu", Made(ns.L.MENU_WINDOW_SETTINGS) ~= nil, true)
made = {}
window:GetScript("OnMouseUp")(window, "LeftButton")
Expect("...a left click does not: it drags", Made(ns.L.MENU_WINDOW_SETTINGS), nil)
window.health:GetScript("OnMouseUp")(window.health, "RightButton")
Expect("...nor does the sync word keep a right-click to itself", Made(ns.L.MENU_WINDOW_SETTINGS) ~= nil, true)
_G.MenuUtil = nil

---------------------------------------------------------------- the header
_G.SpokenPartySyncWindow:Hide()
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
Expect("out of a party there is no Stop", window.pause.shown, false)
Expect("the title's arrow is the game's menu arrow", window.title.arrow.texture:find("ChatFrameExpandArrow", 1, true) ~= nil, true)
Expect("the close button is the small grey cross", window.close.icon.texture:find("ClearBroadcastIcon", 1, true) ~= nil, true)
Expect("...which says what it does", window.close.tip.title, ns.L.WINDOW_CLOSE)
window.close:Click()
Expect("...and closes", window.shown, false)
P.Party(stub, ns)
ns:ShowWindow(true)
Expect("in a party, Stop is there", window.pause.shown, true)
Expect("the round button is even-sized round an even glyph, so the glyph sits centred",
	window.pause.width % 2 == 0 and window.pause.glyph.width % 2 == 0, true)
local function Top(region) return -region.anchor.y end
Expect("chips too wide for one row go on the next", Top(window.chips.quests) > Top(window.chips.audio), true)
Expect("...the ones that fit stay beside each other", Top(window.chips.playback), Top(window.chips.audio))
Expect("...and the divider comes below the last row", Top(window.dividers[1]) >= Top(window.chips.quests) + 16, true)

---------------------------------------------------------------- the settings page leaves the window up
local opened = false
local realOpen = _G.Settings.OpenToCategory
_G.Settings.OpenToCategory = function() opened = true; return true end
Entry(ns:WindowTitleMenu(), ns.L.MENU_WINDOW_SETTINGS).onClick()
_G.Settings.OpenToCategory = realOpen
Expect("Settings opens the page", opened, true)
Expect("...and the window stays", window.shown, true)

---------------------------------------------------------------- invitations and their answers
local MIRA = "Mira Throwaway"
local MIRA_KEY = "mira throwaway"
local function InviteProblem()
	for _, item in ipairs(ns.windowModel.problems) do
		if item.key == "invite:" .. MIRA_KEY then return item end
	end
end
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
ns.Peers:Invite(MIRA)
local invite = ns.windowModel.invited[1]
Expect("someone invited is in the window while the answer is awaited", invite and invite.name, MIRA)
Expect("...on a row of their own, with how long", window.rows[3].tag.text:find(format(ns.L.STATE_INVITED_FMT, 0), 1, true) ~= nil, true)
Expect("...and no member's menu", window.rows[3].key, nil)
_G.MenuUtil = { CreateContextMenu = function(owner, generate)
	made = {}
	generate(owner, NewDescription("root"))
end }
made = {}
window.rows[3]:GetScript("OnClick")(window.rows[3], "RightButton")
Expect("...a click on it opens a menu of its own", Made(ns.L.MENU_CANCEL_INVITE) ~= nil and Made(ns.L.MENU_INVITE_AGAIN) ~= nil, true)
Expect("...not the window's", Made(ns.L.OPT_LEAVE), nil)
made = {}
window.rows[1]:GetScript("OnClick")(window.rows[1], "RightButton")
Expect("this character's own row offers Leave Party", Made(ns.L.OPT_LEAVE) ~= nil, true)
Expect("...and not Remove from Party", Made(ns.L.MENU_REMOVE_MEMBER), nil)
made = {}
window.rows[2]:GetScript("OnClick")(window.rows[2], "RightButton")
Expect("another member's row offers Remove from Party", Made(ns.L.MENU_REMOVE_MEMBER) ~= nil, true)
Expect("...and not Leave Party", Made(ns.L.OPT_LEAVE), nil)
_G.MenuUtil = nil
Expect("...in the window's text too", ns:WindowText():find(MIRA .. "  " .. format(ns.L.STATE_INVITED_FMT, 0), 1, true) ~= nil, true)
stub.Advance(60)
ns.Peers:CheckInvitations()
ns:RefreshWindow()
Expect("...still awaited a minute on", ns.windowModel.invited[1] and ns.windowModel.invited[1].seconds, 60)
stub.Advance(66)
stub.chat = {}
ns.Peers:CheckInvitations()
local failed = InviteProblem()
Expect("unanswered for as long as the popup lasts, it is a problem", failed and failed.text, format(ns.L.PROBLEM_NO_INVITE_ANSWER_FMT, MIRA))
Expect("...which offers to send it again", failed and Labels(failed), ns.L.ACTION_REINVITE)
Expect("...said in chat too", stub.chat[#stub.chat] and stub.chat[#stub.chat]:find(failed.text, 1, true) ~= nil, true)
Expect("...and she is no longer listed as invited", #ns.windowModel.invited, 0)
P.Clear()
failed.actions[1].run()
Expect("Re-invite invites her again, by her name", Fields(P.Last("IV", MIRA)), ns.version .. "|" .. P.SESSION .. "|0")
Expect("...listed as invited again", ns.windowModel.invited[1] and ns.windowModel.invited[1].seconds, 0)
Expect("...the problem gone", InviteProblem(), nil)
P.Receive(stub, MIRA, "ID", P.SESSION)
local declined = InviteProblem()
Expect("declining is shown", declined and declined.text, format(ns.L.PROBLEM_DECLINED_FMT, MIRA))
Expect("...hers to decide: it can only be dismissed", declined and Labels(declined), ns.L.ACTION_DISMISS)
Expect("...and she is no longer invited", #ns.windowModel.invited, 0)
ns.Peers:Invite(MIRA)
Expect("a new invitation clears the old answer", InviteProblem(), nil)
ns.Peers:MarkOffline(MIRA)
local offline = InviteProblem()
Expect("someone not online is said so at once", offline and offline.text, format(ns.L.PROBLEM_OFFLINE_FMT, MIRA))
Expect("...with Re-invite beside it", offline and Labels(offline), ns.L.ACTION_REINVITE)
Expect("...and is not left waiting", #ns.windowModel.invited, 0)
ns.Peers:Invite(MIRA)
P.Receive(stub, MIRA, "IA", P.SESSION)
Expect("accepted, she is a member", ns.Peers:IsMember(MIRA_KEY), true)
Expect("...and nothing is left of the invitation", InviteProblem() == nil and #ns.windowModel.invited, 0)
local BOB, BOB_KEY = "Bob Stranger", "bob stranger"
ns.Peers:Invite(BOB)
P.Clear()
Entry(ns:WindowInvitedMenu(BOB_KEY), ns.L.MENU_INVITE_AGAIN).onClick()
Expect("Invite Again sends the invitation again", P.Last("IV", BOB) ~= nil, true)
Entry(ns:WindowInvitedMenu(BOB_KEY), ns.L.MENU_CANCEL_INVITE).onClick()
Expect("Cancel Invitation tells them, for their popup to close", Fields(P.Last("ID", BOB)), P.SESSION)
Expect("...and they are no longer invited", #ns.windowModel.invited, 0)
P.Clear()
P.Receive(stub, BOB, "IA", P.SESSION)
Expect("an acceptance on its way meanwhile is answered by sending them away", Fields(P.Last("ID", BOB)), P.SESSION)
Expect("...not by a place in the party", ns.Peers:IsMember(BOB_KEY), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns.Peers:Invite(MIRA)
Expect("an invitation from no party starts one", ns.Peers:InParty(), true)
ns.Peers:CancelInvite(MIRA_KEY)
Expect("...which goes when it is withdrawn and nobody else is asked", ns.Peers:InParty(), false)

-- The other side: the popup closes when its invitation is withdrawn.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
local hidden = {}
_G.StaticPopup_Hide = function(which) table.insert(hidden, which) end
P.Receive(stub, LALA, "IV", "0.5.0", "lala throwaway-7", 0)
Expect("an invitation shows its popup", stub.popups[#stub.popups].key, "SPOKENPARTYSYNC_INVITE")
stub.chat = {}
P.Receive(stub, LALA, "ID", "lala throwaway-7")
Expect("withdrawn, the popup closes", hidden[1], "SPOKENPARTYSYNC_INVITE")
Expect("...saying so", stub.chat[#stub.chat] and stub.chat[#stub.chat]:find(format(ns.L.INVITE_WITHDRAWN_FMT, LALA), 1, true) ~= nil, true)
hidden = {}
P.Receive(stub, LALA, "ID", "lala throwaway-7")
Expect("...once", hidden[1], nil)
P.Receive(stub, LALA, "IV", "0.5.0", "lala throwaway-8", 0)
stub.popups[#stub.popups].dialog.OnCancel(nil, stub.popups[#stub.popups].args[3], "clicked")
P.Receive(stub, LALA, "ID", "lala throwaway-8")
Expect("a popup already answered is not closed again", hidden[1], nil)
_G.StaticPopup_Hide = function() end

-- "When Something Is Wrong": an invitation sent is when its answer is looked for.
_G.SpokenPartySyncWindow:Hide()
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:DB().window.show = "problems"
ns:RefreshWindow()
Expect("with nothing wrong, the window is not up", _G.SpokenPartySyncWindow == nil or not _G.SpokenPartySyncWindow.shown, true)
ns.Peers:Invite(MIRA)
window = _G.SpokenPartySyncWindow
Expect("an invitation sent brings it up", window and window.shown, true)
P.Receive(stub, MIRA, "IA", P.SESSION)
stub.Advance(9)
ns:RefreshWindow()
Expect("...until a while after the answer", window.shown, false)

---------------------------------------------------------------- a member whose module cannot rebuild the line
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
VO.Player:Enqueue(QuestLine(VO, 101))
P.Receive(stub, LALA, "AK", "101-accept", "old")
local function ProblemFor(prefix)
	for _, item in ipairs(ns.windowModel and ns.windowModel.problems or {}) do
		if item.key:sub(1, #prefix) == prefix then return item end
	end
end
ns:ShowWindow(true)
local old = ProblemFor("old:")
Expect("a member whose Spoken Quests cannot rebuild a line is said so, not \"no voice file\"", old and old.text,
	format(ns.L.PROBLEM_PEER_OLD_FMT, LALA, "Spoken Quests"))
Expect("...with nothing to offer but dismissing it: Mute There would not help", old and Labels(old), ns.L.ACTION_DISMISS)
Expect("...and no missing-file problem", ProblemFor("missing:"), nil)
Expect("...her line under it says why", ns.windowModel.line.progress[1] and ns.windowModel.line.progress[1].text, ns.L.PEER_OLD)

---------------------------------------------------------------- what each computer runs
local realMeta, realLoaded = _G.GetAddOnMetadata, _G.IsAddOnLoaded
local RUNNING = { Spoken = "3.1.0", Spoken_Quests = "3.1.0", SpokenPartySync = "0.5.0" }
_G.IsAddOnLoaded = function(folder) return RUNNING[folder] ~= nil end
_G.GetAddOnMetadata = function(folder, key)
	if key == "Version" and RUNNING[folder] then return RUNNING[folder] end
	return realMeta(folder, key)
end
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
Expect("this computer says what it runs, a + for a module that rebuilds the party's lines",
	ns.Diagnostics:Modules(), "S=3.1.0;Q=3.1.0+")
P.Clear()
ns.Peers:Greet(LALA)
Expect("...in its hello", P.Last("HI", LALA).fields[7], "S=3.1.0;Q=3.1.0+")
local function VersionLines(key)
	local lines = {}
	for _, entry in ipairs(Entry(ns:WindowMemberMenu(key), ns.L.MENU_VERSIONS).children) do table.insert(lines, entry.text) end
	return lines
end
Expect("a member's menu says what their computer runs, before she says anything", VersionLines("lala throwaway")[2],
	ns.L.VERSIONS_NOT_SENT)
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "vmead", "S=3.1.0;Q=3.1.0;D=0.1.0")
local lala = VersionLines("lala throwaway")
Expect("...and what her hello says", lala[1], format(ns.L.VERSION_FMT, ns.L.TITLE, "0.5.0"))
Expect("...with each module's version", lala[2], format(ns.L.VERSION_FMT, "Spoken", "3.1.0"))
Expect("...a module without the Party Sync rebuild said so", lala[3],
	format(ns.L.VERSION_FMT, "Spoken Quests", "3.1.0") .. ns.L.VERSION_NO_PARTY_LINES)
Expect("...and one not running", lala[4], format(ns.L.VERSION_NOT_RUNNING_FMT, "Spoken Zones"))
Expect("this character's own row says the same of this computer", VersionLines(ns:MyKey())[3],
	format(ns.L.VERSION_FMT, "Spoken Quests", "3.1.0") .. ns.L.VERSION_PARTY_LINES)
Expect("...and the diagnostics too", table.concat(ns.Diagnostics:Lines(), "\n"):find("runs S=3.1.0;Q=3.1.0;D=0.1.0", 1, true) ~= nil, true)

-- The handshake: each computer held against the leader's. She leads, with the store's Spoken Quests.
local function Mismatches()
	local count = 0
	for _, line in ipairs(stub.chat) do
		if line:find("does not run what the leader runs", 1, true) then count = count + 1 end
	end
	return count
end
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
local differs = format(ns.L.VERSION_DIFFERS_FMT, "Spoken Quests", "3.1.0", "3.1.0 " .. ns.L.VERSION_STORE)
Expect("this computer, not running what the leader runs, is said to differ", Member(ns:MyKey()).differs
	and Member(ns:MyKey()).differs[1], differs)
Expect("...the leader never does", Member("lala throwaway").differs, nil)
Expect("...an alert after the name on its row", window.rows[1].alert.shown, true)
Expect("...none on hers", window.rows[2].alert.shown, false)
Expect("...the tooltip saying what differs", window.rows[1].tip.reason:find(differs, 1, true) ~= nil, true)
Expect("...as does the Versions menu", Entry(ns:WindowMemberMenu(ns:MyKey()), ns.L.MENU_VERSIONS).children[#Entry(ns:WindowMemberMenu(ns:MyKey()), ns.L.MENU_VERSIONS).children].text:find(differs, 1, true) ~= nil, true)
stub.chat = {}
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "vmead", "S=3.1.0;Q=3.1.0")
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "vmead", "S=3.1.0;Q=3.1.0")
Expect("...said in chat once, not at every hello", Mismatches(), 0)
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "vmead", "S=3.1.0;Q=3.1.0+")
ns:RefreshWindow()
Expect("the leader on the same build: no difference left", Member(ns:MyKey()).differs, nil)
Expect("...and no alert", window.rows[1].alert.shown, false)
P.Receive(stub, LALA, "HI", "0.5.1", 1, P.SESSION, 0, "vmead", "S=3.1.0;Q=3.1.0+")
Expect("Spoken Party Sync's own version counts too", Member(ns:MyKey()).differs
	and Member(ns:MyKey()).differs[1], format(ns.L.VERSION_DIFFERS_FMT, ns.L.TITLE, "0.5.0", "0.5.1"))
Expect("...said in chat when it comes up", Mismatches(), 1)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "vmead", "S=3.1.0")
ns:ShowWindow(true)
window = _G.SpokenPartySyncWindow
Expect("leading, a member without Spoken Quests is said to differ", Member("lala throwaway").differs
	and Member("lala throwaway").differs[1], format(ns.L.VERSION_DIFFERS_FMT, "Spoken Quests", ns.L.VERSION_NONE, "3.1.0"))
Expect("...the alert on her row", window.rows[2].alert.shown, true)
P.Receive(stub, LALA, "HI", "0.4.0", 1, P.SESSION, 0)
Expect("a member on a Party Sync that says nothing of its modules", Member("lala throwaway").differs
	and table.concat(Member("lala throwaway").differs, "|"),
	format(ns.L.VERSION_DIFFERS_FMT, ns.L.TITLE, "0.4.0", "0.5.0") .. "|" .. ns.L.VERSION_UNSAID)
_G.GetAddOnMetadata, _G.IsAddOnLoaded = realMeta, realLoaded

---------------------------------------------------------------- the page
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.optionsPanel:Show()
ns:RefreshOptions()
local function PageRow(label) return P.PageRow(ns, label) end
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
