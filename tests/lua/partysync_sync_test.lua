-- Spoken Party Sync's engine, against the real Spoken queue and the real Spoken Quests: a line
-- queued here is announced and started together; a line announced by the other member is
-- rebuilt, held and started on their word; the same line from both is settled one way; skips
-- and pauses follow the leader; one computer in the room plays the sound. Run with
-- `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local world = stub.world
local Expect, Failures = H.Expecter(print)

local LALA = P.LALA
local LOOKUP = {
	["101-accept"] = 2, ["102-accept"] = 2, ["103-accept"] = 2, ["105-complete"] = 3,
	-- One line recorded for each player gender.
	["m-104-accept"] = 2, ["f-104-accept"] = 2,
}

local function QuestLine(VO, questID, event, text)
	return { event = event or VO.Enums.SoundEvent.QuestAccept, questID = questID, name = "Giver",
		title = "Quest " .. questID, text = text or "Go and do the thing.",
		unitGUID = "Creature-0-0-0-0-1234-0" }
end

---------------------------------------------------------------- alone, nothing changes
local ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
VO.Player:Enqueue(QuestLine(VO, 101))
Expect("without anyone online, a line plays at once", P.started[1] ~= nil, true)
Expect("...and nothing is announced", P.Last("LN"), nil)

---------------------------------------------------------------- driving a line
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
VO.Player:Enqueue(QuestLine(VO, 101, nil, "Wolves.\nMany wolves."))
local clip = Spoken:GetCurrent()
local ln = P.Last("LN", LALA)
Expect("a line queued here is announced to the member", ln and ln.fields[2], "101-accept")
Expect("...as a quest line", ln.fields[3], "q")
Expect("...with its speaker", ln.fields[6], "1234")
Expect("...and its words, which follow", P.Last("TX", LALA) and ns.Comm.Unescape(P.Last("TX", LALA).fields[5]), "Wolves.\nMany wolves.")
Expect("at the front of the queue it is told to start", P.Last("GO", LALA) ~= nil, true)
-- One member at the default round trip of a second: she hears GO half a second from now and
-- starts on it, so this side waits that half second.
Expect("...at once, being the slowest", P.Last("GO", LALA).fields[3], "0")
Expect("...while this side holds it", Spoken:IsPlaying(clip), false)
Expect("...saying why", Spoken:GetHeldReason(clip), ns.L.HOLD_SYNCING)
stub.Advance(0.45)
Expect("...for half the round trip", P.started[1], nil)
stub.Advance(0.1)
Expect("...and then plays", world.played[1], "Interface\\AddOns\\TestPack\\101-accept.ogg")
P.Receive(stub, LALA, "AK", "101-accept", "started", 40)
Expect("her acknowledgement is kept", clip.partySync.peers["lala throwaway"].state, "started")
Expect("...with how late she was", clip.partySync.peers["lala throwaway"].ms, 40)

-- A measured round trip moves the start.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.Peers.list["lala throwaway"].rtt = 300
VO.Player:Enqueue(QuestLine(VO, 101))
stub.Advance(0.12)
Expect("a faster member is waited for less", P.started[1], nil)
stub.Advance(0.05)
Expect("...half her round trip", P.started[1] ~= nil, true)

-- A second line waits its turn, and goes out when it reaches the front.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
VO.Player:Enqueue(QuestLine(VO, 101))
VO.Player:Enqueue(QuestLine(VO, 102))
Expect("two lines queued are both announced", #P.Sent("LN", LALA), 2)
Expect("...but only the first is started", #P.Sent("GO", LALA), 1)
stub.Advance(0.55)
stub.Advance(2.6)
Expect("the second is started when the first is done", #P.Sent("GO", LALA), 2)
Expect("...as itself", P.Last("GO", LALA).fields[2], "102-accept")

-- A member who never answers is reported, and the line plays regardless.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
VO.Player:Enqueue(QuestLine(VO, 101))
stub.Advance(3.5)
Expect("a member who never answered is a problem", ns:Problems()[1] ~= nil, true)
Expect("...and the line played anyway", P.started[1] ~= nil, true)

---------------------------------------------------------------- following a line
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 1, "Giver", "Quest 102")
clip = Spoken:GetCurrent()
Expect("a line she announces is queued here", clip and clip.key, "102-accept")
Expect("...through Spoken Quests, as a line of its own", clip.source, Spoken:GetSource("quests"))
Expect("...held for her", Spoken:GetHeldReason(clip), "waiting for Lala Throwaway")
Expect("...and she is told it is queued", P.Last("AK", LALA) and P.Last("AK", LALA).fields[3], "queued")
P.Receive(stub, LALA, "TX", "102-accept", 1, 1, ns.Comm.Escape("Her words.\nAll of them."))
Expect("her words are the captions", clip.text, "Her words.\nAll of them.")
P.Receive(stub, LALA, "GO", "102-accept", 200)
stub.Advance(0.15)
Expect("it waits as long as she says", P.started[1], nil)
stub.Advance(0.1)
Expect("...then plays", world.played[1], "Interface\\AddOns\\TestPack\\102-accept.ogg")
Expect("...and says it started", P.Last("AK", LALA).fields[3], "started")
stub.Advance(3)
Expect("...and finished", P.Last("AK", LALA).fields[3], "finished")
-- Talking to the giver here after hearing her line: it is not read twice.
Expect("the same line from this client right after is refused", VO.Player:Enqueue(QuestLine(VO, 102)), false)
stub.Advance(25)
Expect("...but not much later", VO.Player:Enqueue(QuestLine(VO, 102)), true)

-- The words are the player's: male driver, female follower, each hears their own take.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
world.unitSex = 3
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "104-accept", "q", 1, 104, 1234, "2.00", "", 0, "Giver", "Quest 104")
Expect("a line read to her is played here in this player's take", Spoken:GetCurrent() and Spoken:GetCurrent().key, "f-104-accept")
world.unitSex = 2

-- A line no pack here has, with its words: the player opens and shows them, silently.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "777-accept", "q", 1, 777, 1234, "4.00", "", 1, "Giver", "A Class Quest")
Expect("a line no pack here holds waits for its words", Spoken:GetCurrent(), nil)
P.Receive(stub, LALA, "TX", "777-accept", 1, 1, "Only warriors hear this.")
clip = Spoken:GetCurrent()
Expect("...then shows them", clip and clip.text, "Only warriors hear this.")
Expect("...over silence", clip.path, [[Interface\AddOns\Spoken\Sounds\silence.wav]])
Expect("...for the line's length", clip.length, 4)
Expect("...and tells her there is no file here", P.Last("AK", LALA).fields[3], "missing")
P.Receive(stub, LALA, "LN", "888-accept", "q", 1, 888, 1234, "4.00", "", 0, "Giver", "No Words")
Expect("one with neither file nor words is only acknowledged", P.Last("AK", LALA).fields[3], "missing")

-- The same line already queued here, before the party was online: that copy follows.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns.Peers:AddMember(LALA)
VO.Player:Enqueue(QuestLine(VO, 101))
VO.Player:Enqueue(QuestLine(VO, 103))
local waiting = Spoken:GetQueue()[2]
P.Receive(stub, LALA, "HI", "0.2.0", 1, "auto", "")
P.Receive(stub, LALA, "LN", "103-accept", "q", 1, 103, 1234, "2.00", "", 0, "Giver", "Quest 103")
Expect("a line already waiting here follows hers rather than playing twice", waiting.partySync and waiting.partySync.role, "follower")
Expect("...and nothing else is queued", Spoken:GetQueueSize(), 2)

-- She goes offline before saying go: the line plays here alone.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 0, "Giver", "Quest 102")
ns.Peers:MarkOffline(LALA)
stub.Advance(1.1)
Expect("a line whose driver went offline plays here alone", P.started[1] ~= nil, true)

-- Her GO never comes: the line plays after a while, and that is a problem worth showing.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 0, "Giver", "Quest 102")
stub.Advance(10)
Expect("without a start signal it waits", P.started[1], nil)
stub.Advance(6)
Expect("...but not for ever", P.started[1] ~= nil, true)

---------------------------------------------------------------- order
-- A line waiting to start together keeps what is behind it behind it, as on her side.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 0, "Giver", "Quest 102")
local zones = Spoken:RegisterSource("testzones", { title = "Zones", addon = "Spoken_Zones", order = 2 })
local lore = H.Clip()
zones:Enqueue(lore)
stub.Advance(1.1)
Expect("a line queued behind one waiting for her does not jump ahead", P.started[1], nil)
Expect("...and says why", Spoken:GetHeldReason(lore), ns.L.HOLD_BEHIND)
P.Receive(stub, LALA, "GO", "102-accept", 0)
Expect("once hers starts, it is next", world.played[1], "Interface\\AddOns\\TestPack\\102-accept.ogg")

---------------------------------------------------------------- both start the same line
-- Lala's name comes first, and with nobody leading the group the first name leads.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.client.units.party1 = LALA
P.client.leader = "player"
Expect("the group's leader leads", ns.Peers:AmLeader(), true)
P.client.leader = nil
Expect("...and otherwise the first name", ns.Peers:Leader(), "lala throwaway")
VO.Player:Enqueue(QuestLine(VO, 103))
clip = Spoken:GetCurrent()
Expect("this side announced its copy", clip.partySync.role, "driver")
P.Receive(stub, LALA, "LN", "103-accept", "q", 1, 103, 1234, "2.00", "", 0, "Giver", "Quest 103")
Expect("hers crossing it, the leader's wins and this copy follows", clip.partySync.role, "follower")
Expect("...telling her so", P.Last("AK", LALA).fields[3], "yielded")
stub.Advance(1)
Expect("...and its own start, already planned, is called off", P.started[1], nil)
P.Receive(stub, LALA, "GO", "103-accept", 0)
Expect("her start starts it", P.started[1] ~= nil, true)

-- This side leading: hers yields, so this side ignores her announcement.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().lead = "me"
P.Party(stub, ns)
VO.Player:Enqueue(QuestLine(VO, 103))
clip = Spoken:GetCurrent()
P.Receive(stub, LALA, "LN", "103-accept", "q", 1, 103, 1234, "2.00", "", 0, "Giver", "Quest 103")
P.Receive(stub, LALA, "GO", "103-accept", 0)
Expect("leading, this copy keeps driving", clip.partySync.role, "driver")
stub.Advance(0.55)
Expect("...and plays on its own start", P.started[1] ~= nil, true)

---------------------------------------------------------------- controls
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().lead = "me"
P.Party(stub, ns)
VO.Player:Enqueue(QuestLine(VO, 101))
stub.Advance(0.55)
P.Clear()
Spoken:Skip()
Expect("the leader's skip of a line played together goes to her", P.Last("SK", LALA) and P.Last("SK", LALA).fields[2], "101-accept")
VO.Player:Enqueue(QuestLine(VO, 102))
stub.Advance(0.55)
P.Clear()
Spoken:Pause()
Expect("...and its pause", P.Last("PZ", LALA) ~= nil, true)
Spoken:Resume()
Expect("...and its resume", P.Last("RS", LALA) ~= nil, true)

-- Following, with the leader's controls: hers act here, this side's stay here.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 0, "Giver", "Quest 102")
P.Receive(stub, LALA, "GO", "102-accept", 0)
P.Clear()
P.Receive(stub, LALA, "PZ")
Expect("the leader's pause pauses here", Spoken:IsPaused(), true)
Expect("...without being sent back", P.Last("PZ"), nil)
P.Receive(stub, LALA, "RS")
Expect("...and her resume resumes", Spoken:IsPaused(), false)
P.Receive(stub, LALA, "SK", "102-accept")
Expect("her skip removes the line here", Spoken:GetCurrent(), nil)
Expect("...without being sent back", P.Last("SK"), nil)
P.Receive(stub, LALA, "LN", "103-accept", "q", 1, 103, 1234, "2.00", "", 0, "Giver", "Quest 103")
P.Receive(stub, LALA, "GO", "103-accept", 0)
P.Clear()
Spoken:Skip()
Expect("a follower's own skip stays here", P.Last("SK"), nil)
Expect("...but she hears it was dropped", P.Last("AK", LALA) and P.Last("AK", LALA).fields[3], "dropped")
ns:DB().controls = "nobody"
P.Receive(stub, LALA, "PZ")
Expect("with nobody's controls shared, hers do nothing here", Spoken:IsPaused(), false)

---------------------------------------------------------------- settings
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:DB().sync.quests = false
VO.Player:Enqueue(QuestLine(VO, 101))
Expect("quest lines switched off are not announced", P.Last("LN"), nil)
Expect("...and play here at once", P.started[1] ~= nil, true)
P.Receive(stub, LALA, "LN", "102-accept", "q", 1, 102, 1234, "2.00", "", 0, "Giver", "Quest 102")
Expect("...and hers are declined", P.Last("AK", LALA) and P.Last("AK", LALA).fields[3], "dropped")
P.Receive(stub, "Bob Stranger", "LN", "103-accept", "q", 1, 103, 1234, "2.00", "", 0, "Giver", "Quest 103")
Expect("a line from someone outside the party is ignored", Spoken:GetQueueSize(), 1)

---------------------------------------------------------------- the same room
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, "me")
Expect("the member who plays the sound makes this computer captions only", Spoken:IsCaptionsOnly(), true)
Expect("...without touching the player's own setting", env.Addon.db.profile.Audio.CaptionsOnly, false)
VO.Player:Enqueue(QuestLine(VO, 101))
local probed = #world.played
stub.Advance(0.55)
Expect("...so a line shows without a sound", #world.played, probed)
Expect("...but runs", Spoken:IsPlaying(Spoken:GetCurrent()), true)
ns.Peers:MarkOffline(LALA)
Expect("with her offline this computer plays again", Spoken:IsCaptionsOnly(), false)
P.Receive(stub, LALA, "HI", "0.2.0", 1, "auto", "")
Expect("...as when nobody chose", Spoken:IsCaptionsOnly(), false)
ns.Room:Set("me")
Expect("choosing this computer tells her", P.Last("HI", LALA) and P.Last("HI", LALA).fields[5], "me")
Expect("...and keeps the sound here", Spoken:IsCaptionsOnly(), false)
ns.Room:Set("lala throwaway")
Expect("naming her computer makes this one silent", Spoken:IsCaptionsOnly(), true)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync tests passed")
