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
ns:DB().lead = "me"
P.Party(stub, ns)
P.client.units.party1 = LALA
world.questID = 101
stub.FireEvent("QUEST_DETAIL")
stub.FireEvent("QUEST_ACCEPTED", 101)
Expect("the leader's accepted quest is not shared at once", P.Called("QuestLogPushQuest"), false)
stub.Advance(0.55)
Expect("...but a moment later", P.Called("QuestLogPushQuest 1"), true)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().lead = "me"
P.Party(stub, ns)
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 3, 102)
stub.Advance(0.55)
Expect("Classic's index-then-quest arguments share the quest", P.Called("QuestLogPushQuest 2"), true)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().lead = "me"
P.Party(stub, ns)
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 999)
stub.Advance(0.55)
Expect("a quest the game will not share is not", P.Called("QuestLogPushQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.units.party1 = LALA
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("a member who does not lead shares nothing", P.Called("QuestLogPushQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().lead = "me"
P.Party(stub, ns)
stub.FireEvent("QUEST_ACCEPTED", 101)
stub.Advance(0.55)
Expect("nor does the leader when no member is in the group", P.Called("QuestLogPushQuest"), false)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().lead = "me"
P.Party(stub, ns)
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

---------------------------------------------------------------- the debug log
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
VO.Player:Enqueue({ event = 1, questID = 101, name = "Giver", title = "Quest 101", unitGUID = "Creature-0-0-0-0-1234-0" })
stub.Advance(0.6)
local function Logged(pattern)
	for _, line in ipairs(ns:DB().log) do
		if line:find(pattern, 1, true) then return true end
	end
	return false
end
Expect("the log starts each session", Logged("session start: Tata Throwaway"), true)
Expect("...records a line driven from here", Logged("sync drive 101-accept"), true)
Expect("...when it was told to start", Logged("sync go 101-accept"), true)
Expect("...the player's own view of it", Logged("player started 101-accept [quests driver/"), true)
Expect("...and the messages sent", Logged("msg -> WHISPER \"Lala Throwaway\" LN 101-accept"), true)
Expect("each line carries the time", ns:DB().log[#ns:DB().log]:match("^%d+%.%d%d%d ") ~= nil, true)

-- A member asks for this client's log: it goes back in pieces, paced, with this clock's reading.
local total = #ns:DB().log
P.Clear()
P.Receive(stub, LALA, "LQ", "t1", 5)
local header = P.Last("LH", LALA)
Expect("asked for a log, the last lines are offered", header and header.fields[3], "5")
Expect("...with this client's clock", tonumber(header.fields[4]) ~= nil, true)
stub.Advance(3)
local pieces = P.Sent("LL", LALA)
Expect("...and all of them arrive", #pieces, 5)
Expect("...the newest last, as written", ns.Comm.Unescape(pieces[5].fields[4]):find("^%d+%.%d+ ") ~= nil, true)
P.Clear()
P.Receive(stub, "Bob Stranger", "LQ", "t2", 5)
Expect("someone outside the party gets nothing", P.Last("LH"), nil)

-- This client asks: her lines come back and are laid on this client's clock.
P.Clear()
Expect("pulling asks every member online", ns.LogBook:Pull(50), 1)
local ask = P.Last("LQ", LALA)
Expect("...for the lines asked", ask and ask.fields[3], "50")
local token = ask.fields[2]
local now = stub.world.time
P.Receive(stub, LALA, "LH", token, 2, string.format("%.3f", now - 100), "0.2.0")
P.Receive(stub, LALA, "LL", token, 1, ns.Comm.Escape(string.format("%.3f sync go 101-accept from tata throwaway: start in 0 ms", now - 101)))
P.Receive(stub, LALA, "LL", token, 2, ns.Comm.Escape(string.format("%.3f player started 101-accept", now - 100.5)))
local hers = ns:DB().collected["lala throwaway"]
Expect("her log is kept", hers and #hers.lines, 2)
-- Her clock is 100 s behind; her header took half the default round trip to come.
Expect("...with the offset onto this clock", hers and string.format("%.1f", hers.offset), "99.5")
local merged = ns.LogBook:Merged()
local found
for _, line in ipairs(merged) do if line:find("Lala Throwaway", 1, true) and line:find("player started", 1, true) then found = line end end
Expect("the merged log has her lines, named", found ~= nil, true)
Expect("...on this client's clock", found and tonumber(found:match("^%s*([%d%.]+)")) ~= nil
	and math.abs(tonumber(found:match("^%s*([%d%.]+)")) - (now - 1)) < 0.01, true)
Expect("the logs open in a box to copy from", ns.LogBook:Show() > 0, true)
ns.LogBook:Clear()
Expect("clearing empties the collected logs", next(ns:DB().collected) == nil, true)
Expect("...and starts the log again with a session line", #ns:DB().log == 1 and ns:DB().log[1]:find("session cleared:", 1, true) ~= nil, true)

-- Clearing for the party: this log, and every member online asked to clear theirs.
P.Clear()
Expect("clearing the party's logs asks each member online", ns.LogBook:ClearParty(), 1)
Expect("...by whisper", P.Last("LC", LALA) ~= nil, true)
Expect("...and clears this one, starting it again", ns:DB().log[1]:find("session cleared, with the party's:", 1, true) ~= nil, true)
P.Receive(stub, LALA, "LK")
Expect("her answer is noted in the new log", ns:DB().log[#ns:DB().log]:find("cleared their log", 1, true) ~= nil, true)
ns.LogBook:Add("sync", "something from before")
P.Clear()
P.Receive(stub, LALA, "LC")
Expect("asked by a member, this client clears its log", Logged("something from before"), false)
Expect("...saying who asked", ns:DB().log[1]:find("cleared at Lala Throwaway's request", 1, true) ~= nil, true)
Expect("...and answers", P.Last("LK", LALA) ~= nil, true)
ns.LogBook:Add("sync", "kept")
P.Receive(stub, "Bob Stranger", "LC")
Expect("someone outside the party cannot clear it", Logged("sync kept"), true)

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

for _, command in ipairs({ "", "api", "members", "status", "sync", "lead", "room", "room me", "room auto",
	"test 101", "test 31337", "ping", "log", "log", "window", "window", "invite", "remove Nobody",
	"logs", "logs 20", "logs pull 30", "logs clear", "logs clear all", "logs clearall" }) do
	local ok, err = pcall(SlashCmdList.SPOKENPARTYSYNC, command)
	Expect("/sps " .. command .. " runs", ok and true or tostring(err), true)
end

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync party tests passed")
