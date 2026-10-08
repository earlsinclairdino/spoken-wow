-- Spoken Party Sync around the lines: quests shared and accepted for the party, zone and book
-- lines rebuilt from their keys, the window, the settings page and the slash commands. Run
-- with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local world = stub.world
local Expect, Failures = H.Expecter(print)

local LALA = P.LALA
local LOOKUP = { ["101-accept"] = 2, ["102-accept"] = 2 }

---------------------------------------------------------------- accepting what a member shares
local ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.offererIsPlayer, P.client.offerer = true, LALA
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
Expect("a quest a member shares is not accepted at once", P.Called("AcceptQuest"), false)
stub.Advance(0.35)
Expect("...but a moment later, once the dialog was read", P.Called("AcceptQuest"), true)
Expect("...and its accept line, just played together, is not read again",
	VO.Player:Enqueue({ event = 1, questID = 101, name = "Giver", title = "Quest 101" }), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.offererIsPlayer, P.client.offerer = true, "Bob Stranger"
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
stub.Advance(0.5)
Expect("one shared by someone outside the party is left to the player", P.Called("AcceptQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.offererIsPlayer, P.client.offerer = true, LALA
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
world.questID = 0
stub.Advance(0.5)
Expect("a dialog closed meanwhile was the player's own answer", P.Called("AcceptQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:DB().autoAccept = false
P.client.offererIsPlayer, P.client.offerer = true, LALA
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
stub.Advance(0.5)
Expect("switched off, nothing is accepted", P.Called("AcceptQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
stub.FireEvent("QUEST_ACCEPT_CONFIRM", LALA, "The Escort")
Expect("an escort a member starts is joined", P.Called("ConfirmAcceptQuest"), true)

---------------------------------------------------------------- sharing what the leader accepts
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.client.units.party1 = LALA
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
stub.FireEvent("QUEST_ACCEPTED", 101)
Expect("the leader's accepted quest is not shared at once", P.Called("QuestLogPushQuest"), false)
stub.Advance(0.55)
Expect("...but a moment later", P.Called("QuestLogPushQuest 1"), true)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 3, 102)
stub.Advance(0.55)
Expect("Classic's index-then-quest arguments share the quest", P.Called("QuestLogPushQuest 2"), true)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 999)
stub.Advance(0.55)
Expect("a quest the game will not share is not", P.Called("QuestLogPushQuest"), false)

-- 2026-10-08: only the leader shared, so a quest the other member accepted never reached it.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("by default a member who does not lead shares too", P.Called("QuestLogPushQuest 1"), true)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, nil, { share = "leader" })
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("with Quests Are Shared By the leader, a member shares nothing", P.Called("QuestLogPushQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me", { share = "nobody" })
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("with nobody's, not even the leader shares", P.Called("QuestLogPushQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.units.party1 = LALA
ns:DB().autoShare = false
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("a computer that switched its own sharing off shares nothing", P.Called("QuestLogPushQuest"), false)
P.Receive(stub, LALA, "PS", "leader", "none", "1111", "leader")
Expect("the leader's rule reaches this computer", ns.Peers:Rules().share, "leader")
P.Receive(stub, LALA, "PS", "leader", "none", "1111")
Expect("...and a leader on 0.4.0, who sends none, means anyone", ns.Peers:Rules().share, "anyone")

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("nor does the leader when no member is in the group", P.Called("QuestLogPushQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.client.units.party1 = LALA
P.client.offererIsPlayer, P.client.offerer = true, LALA
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("a quest shared with the leader is not shared back", P.Called("QuestLogPushQuest"), false)

---------------------------------------------------------------- zones and books
-- Their lines are rebuilt from the key alone, by their own module.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
local asked
Spoken:RegisterSource("zones", { title = "Zones", addon = "Spoken_Zones", order = 2,
	rebuild = function(fields) asked = fields.key; return H.Clip({ key = fields.key }) end })
P.Receive(stub, LALA, "LN", "s:1429:northshire valley", "z", "", "", "", "35.00", "", 0, "Elwynn Forest", "Northshire Valley")
Expect("zone lore she announces is rebuilt by the zones module", asked, "s:1429:northshire valley")
Expect("...queued here and held for her", Spoken:GetCurrent() and Spoken:GetHeldReason(Spoken:GetCurrent()), "waiting for Lala Throwaway")
P.Receive(stub, LALA, "LN", "b:4242", "b", "", "", "", "20.00", "", 0, "A Book", "")
Expect("a book page needs the books module", P.Last("AK", LALA).fields[3], "missing")
local zone = Spoken:GetSource("zones")
P.Clear()
zone:Enqueue(H.Clip({ key = "z:1411" }))
Expect("zone lore queued here is announced", P.Last("LN", LALA) and P.Last("LN", LALA).fields[3], "z")
Expect("...without words, which every client has", P.Last("TX", LALA), nil)

---------------------------------------------------------------- the debug log, Spoken's
-- The log is Spoken's, kept by the Spoken Developer module where it is installed: Party Sync
-- writes into it and collects the party's. Without the module Party Sync has no log, and says so.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
VO.Player:Enqueue({ event = 1, questID = 101, name = "Giver", title = "Quest 101", unitGUID = "Creature-0-0-0-0-1234-0" })
stub.Advance(0.6)
Expect("Party Sync keeps no log of its own", ns:DB().log, nil)

if not (Spoken.HasLog and Spoken:HasLog()) then
	Expect("without Spoken's log, there is none to show", ns.LogBook:Available(), false)
	Expect("...and /sps logs says so", pcall(SlashCmdList.SPOKENPARTYSYNC, "logs"), true)
	P.Clear()
	P.Receive(stub, LALA, "LQ", "t1", 5)
	local header = P.Last("LH", LALA)
	Expect("a member asking for it gets no lines", header and header.fields[3], "0")
	Expect("...and hears it is off", header and header.fields[6], "0")
else
	-- Spoken Developer turns the log on as it is installed; Party Sync writes into it from the start.
	Expect("with Spoken Developer installed, Spoken's log is on from the start", Spoken:IsLogOn(), true)

	ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
	P.Party(stub, ns)
	-- Off and on again, so the session starts here.
	Spoken:SetLogOn(false)
	Spoken:SetLogOn(true)
	VO.Player:Enqueue({ event = 1, questID = 101, name = "Giver", title = "Quest 101", unitGUID = "Creature-0-0-0-0-1234-0" })
	stub.Advance(0.6)
	local function Logged(pattern)
		for _, line in ipairs(Spoken:LogLines()) do
			if line:find(pattern, 1, true) then return true end
		end
		return false
	end
	Expect("Spoken's log starts the session", Logged("session log on: Tata Throwaway"), true)
	Expect("...Party Sync writes a line driven from here", Logged("sync drive 101-accept"), true)
	Expect("...when it was told to start", Logged("sync go 101-accept"), true)
	Expect("...Spoken its own view of it", Logged("player started "), true)
	Expect("...and Party Sync the messages sent", Logged("msg -> WHISPER \"Lala Throwaway\" LN 101-accept"), true)
	Expect("each line carries the time", Spoken:LogLines(1)[1]:match("^%d+%.%d%d%d ") ~= nil, true)

	-- A member asks for this client's log: it goes back in pieces, paced, with this clock's reading.
	P.Clear()
	P.Receive(stub, LALA, "LQ", "t1", 5)
	local header = P.Last("LH", LALA)
	Expect("asked for a log, the last lines are offered", header and header.fields[3], "5")
	Expect("...with this client's clock", tonumber(header.fields[4]) ~= nil, true)
	Expect("...saying the log is on", header.fields[6], "1")
	stub.Advance(3)
	local pieces = P.Sent("LL", LALA)
	Expect("...and all of them arrive", #pieces, 5)
	Expect("...the newest last, as written", ns.Comm.Unescape(pieces[5].fields[4]):find("^%d+%.%d+ ") ~= nil, true)
	P.Clear()
	P.Receive(stub, "Bob Stranger", "LQ", "t2", 5)
	Expect("someone outside the party gets nothing", P.Last("LH"), nil)

	-- This client asks: her lines come back, are laid on this client's clock, and Spoken shows them.
	P.Clear()
	Expect("pulling asks every member online", ns.LogBook:Pull(50), 1)
	local ask = P.Last("LQ", LALA)
	Expect("...for the lines asked", ask and ask.fields[3], "50")
	local token = ask.fields[2]
	local now = stub.world.time
	P.Receive(stub, LALA, "LH", token, 2, string.format("%.3f", now - 100), "0.2.0", "1")
	P.Receive(stub, LALA, "LL", token, 1, ns.Comm.Escape(string.format("%.3f sync go 101-accept from tata throwaway: start in 0 ms", now - 101)))
	P.Receive(stub, LALA, "LL", token, 2, ns.Comm.Escape(string.format("%.3f player started 101-accept", now - 100.5)))
	local hers = ns:DB().collected["lala throwaway"]
	Expect("her log is kept", hers and #hers.lines, 2)
	-- Her clock is 100 s behind; her header took half the default round trip to come.
	Expect("...with the offset onto this clock", hers and string.format("%.1f", hers.offset), "99.5")
	local merged = P.developer.Log:Merged()
	local found
	for _, line in ipairs(merged) do if line:find("Lala Throwaway", 1, true) and line:find("player started", 1, true) then found = line end end
	Expect("Spoken's merged log has her lines, named", found ~= nil, true)
	Expect("...on this client's clock", found and tonumber(found:match("^%s*([%d%.]+)")) ~= nil
		and math.abs(tonumber(found:match("^%s*([%d%.]+)")) - (now - 1)) < 0.01, true)
	Expect("the logs open in Spoken's box", ns.LogBook:Show() > 0, true)
	ns.LogBook:Clear()
	Expect("clearing empties the collected logs", next(ns:DB().collected) == nil, true)
	Expect("...and starts Spoken's log again with a session line",
		#Spoken:LogLines() == 3 and Spoken:LogLines()[1]:find("session cleared:", 1, true) ~= nil, true)

	-- Clearing for the party: this log, and every member online asked to clear theirs.
	P.Clear()
	Expect("clearing the party's logs asks each member online", ns.LogBook:ClearParty(), 1)
	Expect("...by whisper", P.Last("LC", LALA) ~= nil, true)
	Expect("...and clears this one, starting it again", Spoken:LogLines()[1]:find("session cleared, with the party's:", 1, true) ~= nil, true)
	P.Receive(stub, LALA, "LK")
	Expect("her answer is noted in the new log", Spoken:LogLines(1)[1]:find("cleared their log", 1, true) ~= nil, true)
	Spoken:Log("sync", "something from before")
	P.Clear()
	P.Receive(stub, LALA, "LC")
	Expect("asked by a member, this client clears its log", Logged("something from before"), false)
	Expect("...saying who asked", Spoken:LogLines()[1]:find("cleared at Lala Throwaway's request", 1, true) ~= nil, true)
	Expect("...and answers", P.Last("LK", LALA) ~= nil, true)
	Spoken:Log("sync", "kept")
	P.Receive(stub, "Bob Stranger", "LC")
	Expect("someone outside the party cannot clear it", Logged("sync kept"), true)

	-- With the log off, a member asking is told so, and so is this client of hers.
	Spoken:SetLogOn(false)
	P.Clear()
	P.Receive(stub, LALA, "LQ", "t3", 5)
	header = P.Last("LH", LALA)
	Expect("a log that is off says so", header and header.fields[6], "0")
	P.Clear()
	ns.LogBook:Pull(10)
	ask = P.Last("LQ", LALA)
	P.Receive(stub, LALA, "LH", ask.fields[2], 0, string.format("%.3f", stub.world.time), "0.2.0", "0")
	Expect("...and hers being off is kept", ns:DB().collected["lala throwaway"] ~= nil, true)

	-- The party's buttons sit under Spoken's own on its Developer page.
	local devLabels = {}
	for _, text in ipairs(stub.LabelsUnder(_G.SpokenDeveloperOptionsPanel)) do devLabels[text] = true end
	Expect("Spoken's Developer page has the log", devLabels["Enable Debug Log Recording"], true)
	Expect("...and Party Sync's section", devLabels["Spoken Party Sync"], true)
	Expect("...collecting the party's logs", devLabels["Collect the Party's Logs"], true)
	Expect("...and clearing them", devLabels["Clear the Party's Logs"], true)
end

---------------------------------------------------------------- the window, the page, the commands
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
VO.Player:Enqueue({ event = 1, questID = 101, name = "Giver", title = "Quest 101", unitGUID = "Creature-0-0-0-0-1234-0" })
-- Answered, or her silence would be a problem of its own and keep the window up below.
P.Receive(stub, LALA, "AK", "101-accept", "queued")
ns:ShowWindow(true)
local window = _G.SpokenPartySyncWindow
Expect("the window opens by hand", window ~= nil and window.shown, true)
Expect("...listing the member", ns.windowBody:find("Lala Throwaway", 1, true) ~= nil, true)
Expect("...and the line, waiting to start together", ns.windowBody:find("Quest 101", 1, true) ~= nil, true)
ns:ShowWindow(false)
Expect("...and closes", window.shown, false)
ns:DB().window.show = "problems"
ns:Problem("test", "Something is wrong")
Expect("on \"when something is wrong\" a problem opens it", window.shown, true)
ns:Resolve("test")
stub.Advance(10)
ns:RefreshWindow()
Expect("...and it goes a little after the problem does", window.shown, false)

Expect("the settings page is built", ns.optionsPanel ~= nil, true)

---------------------------------------------------------------- diagnostics
local function Has(text, list)
	for _, line in ipairs(list) do
		if line:find(text, 1, true) then return true end
	end
	return false
end
local diag = ns.Diagnostics:Lines(true)
Expect("the party's diagnostics name the addon and the group", Has("Spoken Party Sync " .. ns.version .. "; group: ", diag), true)
Expect("...the debug log", Has("debug log: ", diag), true)
Expect("...the party", Has("party: " .. P.SESSION .. ", 2 member(s)", diag), true)
Expect("...who leads, and why", Has("leader: Lala Throwaway (leads the party); sound: every computer", diag), true)
Expect("...and the leader's rules", Has("rules (the leader's): controls leader, sound none, quests shared by anyone, played together quests, gossip, zones, books", diag), true)
Expect("...the member, online and leading", Has("Lala Throwaway: online", diag) and Has(", leads", diag), true)
Expect("...and, detailed, the lines played together", Has("101-accept, driver", diag), true)
Expect("...but not when brief", Has("101-accept, driver", ns.Diagnostics:Lines(false)), false)
if Spoken.Diagnostics and Spoken.HasLog and Spoken:HasLog() then
	local all = Spoken:Diagnostics(true)
	Expect("Spoken's diagnostics hold the party's", Has("Spoken Party Sync:", all), true)
	Expect("...with the member", Has("Lala Throwaway: online", all), true)
end

---------------------------------------------------------------- the leader, the rules
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
local LALA = P.LALA
local function Fields(message) return message and table.concat(message.fields, "|", 2) or nil end
Expect("whoever started the party leads it", ns.Peers:Leader(), "lala throwaway")
Expect("a member cannot pass the lead", (ns.Peers:PassLead(ns:MyKey())), false)
Expect("...nor set a rule", (ns.Peers:SetRule("controls", "anyone")), false)
Expect("...nor invite", (ns.Peers:Invite("Bob Stranger")), false)
Expect("...nor remove", (ns.Peers:RemoveMember(LALA)), false)
P.Clear()
P.Receive(stub, LALA, "PS", "anyone", "lala throwaway", "1011")
Expect("the leader's rules are saved here", ns.Peers:Rules().controls .. "|" .. ns.Peers:Rules().room, "anyone|lala throwaway")
Expect("...gossip off among them", ns.Sync:Syncs("gossip"), false)
Expect("...and her computer plays the sound", Spoken:IsCaptionsOnly(), true)
P.Receive(stub, "Bob Stranger", "PS", "nobody", "none", "1111")
Expect("a stranger's rules are ignored", ns.Peers:Rules().controls, "anyone")
P.Receive(stub, LALA, "RO", P.SESSION, "Tata Throwaway", "Lala Throwaway;Tata Throwaway")
Expect("the roster can hand this character the lead", ns.Peers:AmLeader(), true)
P.Clear()
ns.Peers:SetRule("controls", "leader")
Expect("leading, a rule set here goes to her", Fields(P.Last("PS", LALA)), "leader|lala throwaway|1011|anyone")
ns.Room:Choose("me")
Expect("...as does the sound", Fields(P.Last("PS", LALA)), "leader|tata throwaway|1011|anyone")
Expect("...which comes back here", Spoken:IsCaptionsOnly(), false)
P.Clear()
ns.Peers:PassLead(LALA)
Expect("passing the lead sends the roster with her leading", Fields(P.Last("RO", LALA)), P.SESSION .. "|lala throwaway|Tata Throwaway;Lala Throwaway")
Expect("...and she leads", ns.Peers:Leader(), "lala throwaway")

-- The window's rows are the leader's to press.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:ShowWindow(true)
local rows = ns.windowRows
Expect("the window has a row for this character, then one for her",
	rows and rows[1] and rows[2] and (rows[1].key .. "|" .. rows[2].key), "tata throwaway|lala throwaway")
Expect("...with her line on it", rows[2].label.text and rows[2].label.text:find("Lala Throwaway", 1, true) ~= nil, true)
Expect("...and its Lead greyed, as she leads", rows[2].lead:IsEnabled(), false)
Expect("...this character's too: the lead is hers to pass", rows[1].lead:IsEnabled(), false)
Expect("...saying so on hover", rows[1].lead.tooltip, format(ns.L.ONLY_LEADER_FMT, "Lala Throwaway"))
P.Receive(stub, LALA, "RO", P.SESSION, "Tata Throwaway", "Lala Throwaway;Tata Throwaway")
Expect("leading, her Lead is live", rows[2].lead:IsEnabled(), true)
P.Clear()
rows[2].sound:Click()
Expect("her Sound gives her computer the sound, for the party", Fields(P.Last("PS", LALA)), "leader|lala throwaway|1111|anyone")
Expect("...and then greys", rows[2].sound:IsEnabled(), false)
rows[2].lead:Click()
Expect("her Lead passes her the lead", Fields(P.Last("RO", LALA)), P.SESSION .. "|lala throwaway|Tata Throwaway;Lala Throwaway")
Expect("...and then greys", rows[2].lead:IsEnabled(), false)
Expect("the window opens the settings too", _G.SpokenPartySyncWindow.settings ~= nil, true)
Expect("...and remembers the party", _G.SpokenPartySyncWindow.remember ~= nil, true)
ns:ShowWindow(false)

-- And the settings page's Party block.
P.Receive(stub, LALA, "RO", P.SESSION, "Tata Throwaway", "Lala Throwaway;Tata Throwaway")
ns.optionsPanel:Show()
ns:RefreshOptions()
local memberRows = ns.memberRows
Expect("the page lists this character first, then her",
	memberRows and memberRows[1].key and (memberRows[1].key .. "|" .. tostring(memberRows[2].key)), "tata throwaway|lala throwaway")
Expect("...this character with no Remove", memberRows[1].remove:IsShown(), false)
P.Clear()
memberRows[2].lead:Click()
Expect("her Lead on the page passes her the lead", Fields(P.Last("RO", LALA)), P.SESSION .. "|lala throwaway|Tata Throwaway;Lala Throwaway")
Expect("...after which this character's buttons grey", memberRows[2].remove:IsEnabled(), false)
Expect("the auto-form block is there, empty", ns.listRows ~= nil and not ns.listRows[1].label:IsShown(), true)

-- Hovering every button on the page, with the client's tooltip, which takes text only
-- (2026-10-08: the list's Remove, which has no tooltip, raised "bad argument #1 to 'SetText'").
local setText = GameTooltip.SetText
GameTooltip.SetText = function(self, text, ...)
	assert(type(text) == "string", "bad argument #1 to 'SetText'")
	return setText(self, text, ...)
end
local function Hover(button)
	return (pcall(button:GetScript("OnEnter"), button))
end
ns.Autoform:Add("Bob Stranger")
ns:RefreshOptions()
Expect("hovering the list's Remove, which has no tooltip, raises nothing", Hover(ns.listRows[1].remove), true)
Expect("...nor its Auto-accept", Hover(ns.listRows[1].auto), true)
Expect("hovering a member's buttons raises nothing", Hover(memberRows[2].remove) and Hover(memberRows[2].lead), true)
P.Receive(stub, LALA, "RO", P.SESSION, "Tata Throwaway", "Lala Throwaway;Tata Throwaway")
ns:RefreshOptions()
Expect("...nor, leading, the Remove that has no tooltip for the leader", Hover(memberRows[2].remove), true)
GameTooltip.SetText = setText
P.Receive(stub, LALA, "RO", P.SESSION, "Lala Throwaway", "Lala Throwaway;Tata Throwaway")
ns.optionsPanel:Hide()

-- Her portrait's menu.
local offered = {}
local root = {
	CreateDivider = function() end,
	CreateTitle = function() end,
	CreateButton = function(_, label) table.insert(offered, label) end,
}
P.menus.MENU_UNIT_PARTY(nil, root, { name = LALA })
Expect("her portrait offers to remember her, and nothing of the leader's", table.concat(offered, "|"), "Remember for Spoken Parties")
P.Receive(stub, LALA, "RO", P.SESSION, "Tata Throwaway", "Lala Throwaway;Tata Throwaway")
ns.Room:Choose("none")
offered = {}
P.menus.MENU_UNIT_PARTY(nil, root, { name = LALA })
Expect("...and, leading, Lead, Sound and Remove", table.concat(offered, "|"),
	"Pass the Spoken Party Lead|Play the Sound for the Spoken Party|Remove from Spoken Party|Remember for Spoken Parties")

-- Spoken's minimap menu has a section for the party.
local entries = {}
for _, entry in ipairs(env.Minimap:BuildMenu()) do
	if entry.sourceTitle == "Spoken Party Sync" then table.insert(entries, entry.text) end
end
Expect("Spoken's minimap menu opens the party window and its settings", table.concat(entries, "|"),
	"Open Party Window|Party Sync Settings")

for _, command in ipairs({ "", "api", "members", "status", "sync", "lead", "room", "room me", "room none", "room auto",
	"controls", "controls anyone", "controls x", "share", "share leader", "share x", "share anyone", "sound", "sound captions", "sound x", "list", "list add Bob Stranger",
	"list auto Bob Stranger off", "list auto Bob", "list remove Bob Stranger", "remember", "remember on", "remember off",
	"test 101", "test 31337", "ping", "window", "window", "invite", "remove Nobody", "remove",
	"lead Lala Throwaway", "logs", "logs 20", "logs pull 30", "logs clear", "logs clear all", "logs clearall", "leave" }) do
	local ok, err = pcall(SlashCmdList.SPOKENPARTYSYNC, command)
	Expect("/sps " .. command .. " runs", ok and true or tostring(err), true)
end

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync party tests passed")
