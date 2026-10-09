-- Spoken Party Sync's party as a session: started by an invitation, led by whoever invited,
-- kept in step by the leader's roster, over when fewer than two are left, rejoined after a
-- /reload; and the auto-form list that starts it again. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)

local LALA = P.LALA
local BOB = "Bob Stranger"
local LOOKUP = { ["101-accept"] = 2 }

local function Fields(message) return message and table.concat(message.fields, "|", 2) or nil end

local function QuestLine(VO, questID)
	return { event = VO.Enums.SoundEvent.QuestAccept, questID = questID, name = "Giver", title = "Quest " .. questID,
		text = "Go.", unitGUID = "Creature-0-0-0-0-1234-0" }
end

---------------------------------------------------------------- a party of three, led from here
local ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
Expect("alone, there is no party", ns.Peers:InParty(), false)
Expect("...and no leader", ns.Peers:Leader(), nil)
ns.Peers:Invite(LALA)
local id = P.Last("IV", LALA).fields[3]
Expect("an invitation starts a party led here", ns.Peers:AmLeader(), true)
Expect("...of one, so far", ns.Peers:Count(), 1)
Expect("...which the hello names", P.Last("HI"), nil)
P.Receive(stub, LALA, "IA", id)
Expect("her acceptance makes two", ns.Peers:Count(), 2)
Expect("...and she is sent the roster", Fields(P.Last("RO", LALA)), id .. "|tata throwaway|Tata Throwaway;Lala Throwaway")
P.Clear()
ns.Peers:Invite(BOB)
P.Receive(stub, BOB, "IA", id)
Expect("a third joins the same party", ns.Peers:Count(), 3)
Expect("...and everyone gets the roster", Fields(P.Last("RO", LALA)), id .. "|tata throwaway|Tata Throwaway;Bob Stranger;Lala Throwaway")
Expect("...the newcomer the rules too", Fields(P.Last("PS", BOB)), "anyone|none|1111|anyone|music=none;effects=none;ambience=none;dialog=none")
P.Clear()
ns.Peers:SetRule("controls", "nobody")
Expect("a rule set by the leader reaches both", #P.Sent("PS"), 2)
P.Receive(stub, BOB, "PS", "anyone", "none", "1111")
Expect("...but a member's rules are ignored", ns.Peers:Rules().controls, "nobody")
P.Clear()
P.Receive(stub, BOB, "ID", id)
Expect("a member leaving is dropped", ns.Peers:IsMember(BOB), false)
Expect("...and the roster goes out again", Fields(P.Last("RO", LALA)), id .. "|tata throwaway|Tata Throwaway;Lala Throwaway")
P.Clear()
Expect("the leader may remove a member", (ns.Peers:RemoveMember(LALA)), true)
Expect("...who is told", Fields(P.Last("ID", LALA)), id)
Expect("...and with one left the party is over", ns.Peers:InParty(), false)

-- Hellos name the party, and a member in no party any more is dropped by its hello.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.Clear()
ns.Peers:Hello()
P.Receive(stub, LALA, "HI", "0.4.0", 0, P.SESSION, 0)
Expect("the hello back names the party", P.Last("HI", LALA) and P.Last("HI", LALA).fields[4], P.SESSION)
stub.Advance(11)
P.Receive(stub, LALA, "HI", "0.4.0", 1, "", 0)
Expect("a member whose hello says no party is gone", ns.Peers:IsMember(LALA), false)
Expect("...and so is the party", ns.Peers:InParty(), false)

---------------------------------------------------------------- the leader gone
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.Peers:Invite(BOB)
Expect("a member cannot invite", (ns.Peers:Invite(BOB)), false)
ns:Party().session.members["bob stranger"] = BOB
P.Receive(stub, BOB, "HI", "0.4.0", 1, P.SESSION, 0)
Expect("three in the party, she leads", ns.Peers:Leader(), "lala throwaway")
-- The heartbeat's ticker is not in the harness: ticked by hand. Bob is heard from meanwhile.
stub.Advance(50)
P.Receive(stub, BOB, "HI", "0.4.0", 1, P.SESSION, 0)
stub.Advance(20)
ns.Peers:Tick()
Expect("lost for three heartbeats, she is dropped", ns.Peers:IsMember(LALA), false)
Expect("...and Bob, heard from, stays", ns.Peers:IsMember(BOB), true)
Expect("...and the first by name of those left stands in: Bob", ns.Peers:Leader(), "bob stranger")
P.Receive(stub, BOB, "RO", P.SESSION, BOB, "Bob Stranger;Tata Throwaway")
Expect("...whose roster confirms it", ns.Peers:Leader() .. "|" .. ns.Peers:Count(), "bob stranger|2")

local ZED = "Zed Zulu"
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns:Party().session.members["bob stranger"] = BOB
ns:Party().session.members["zed zulu"] = ZED
P.Receive(stub, BOB, "HI", "0.4.0", 1, P.SESSION, 0)
P.Receive(stub, ZED, "HI", "0.4.0", 1, P.SESSION, 0)
P.Clear()
ns.Peers:MarkOffline(BOB)
Expect("a member the client says is offline is dropped at once", ns.Peers:IsMember(BOB), false)
ns.Peers:MarkOffline(LALA)
Expect("the leader going offline, this character, first by name of those left, takes the lead", ns.Peers:AmLeader(), true)
Expect("...and tells the other", Fields(P.Last("RO", ZED)), P.SESSION .. "|tata throwaway|Tata Throwaway;Zed Zulu")
ns.Peers:MarkOffline(ZED)
Expect("...and alone, the party ends", ns.Peers:InParty(), false)

---------------------------------------------------------------- a /reload rejoins the party
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
local account, character = _G.SpokenPartySyncDB, _G.SpokenPartySyncCharDB
Expect("the party is saved with the character", character.session and character.session.id, P.SESSION)
ns, VO, env, Spoken = P.Boot(stub, LOOKUP, { account = account, character = character })
Expect("logged in again, the party is still there", ns.Peers:InParty(), true)
Expect("...with her leading", ns.Peers:Leader(), "lala throwaway")
Expect("...and the members have until the first missed heartbeats to answer", ns.Peers.resumedAt ~= nil, true)
ns.Peers:Resume()
Expect("...the hello to them naming the party", P.Last("HI", LALA) and P.Last("HI", LALA).fields[4], P.SESSION)
P.Receive(stub, LALA, "HI", "0.4.0", 1, P.SESSION, 0)
Expect("her answer keeps the party", ns.Peers:IsMember(LALA) and ns.Peers.list["lala throwaway"].state, "online")
ns, VO, env, Spoken = P.Boot(stub, LOOKUP, { account = account, character = character })
stub.Advance(70)
ns.Peers:Tick()
Expect("a member who never answers since login is dropped", ns.Peers:InParty(), false)

---------------------------------------------------------------- the controls, greyed
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me", { controls = "nobody" })
VO.Player:Enqueue(QuestLine(VO, 101))
stub.Advance(0.55)
Expect("with the controls off, the leader's own Stop is greyed too", Spoken:WhyNoControl(), ns.L.GATE_NOBODY)
Expect("...and does nothing", Spoken:Pause() == false and Spoken:IsPaused() == false, true)
-- What the player shows (2026-10-08: the Subtitles player's Stop and Skip stayed lit).
local Subtitle = env.Subtitle
if not Subtitle.frame then Subtitle:Build() end
Subtitle:UpdatePause()
Expect("...the subtitle's Stop is greyed", Subtitle.pause:IsEnabled(), false)
Expect("...and its Skip", Subtitle.skip:IsEnabled(), false)
ns:ShowWindow(true)
local windowStop = _G.SpokenPartySyncWindow.pause
Expect("...and the party window's Stop", windowStop:IsEnabled(), false)
Expect("...saying why", windowStop.tip.reason, ns.L.GATE_NOBODY)
ns.Peers:SetRule("controls", "leader")
Expect("under the leader's controls the leader may stop", Spoken:WhyNoControl(), nil)
Subtitle:UpdatePause()
ns:RefreshWindow()
Expect("...its subtitle buttons live again", Subtitle.pause:IsEnabled() and Subtitle.skip:IsEnabled(), true)
Expect("...and the window's Stop", windowStop:IsEnabled() and windowStop.tip.reason == nil and windowStop.tip.title, ns.L.WINDOW_STOP)
ns:ShowWindow(false)
Expect("...and it reaches the party", Spoken:Pause() and P.Last("PZ", LALA) ~= nil, true)
Spoken:Resume()
VO.Player:Enqueue(QuestLine(VO, 102))
local alone = Spoken:GetQueue()[2]
Spoken:Skip()
Expect("a line played here alone keeps its buttons whatever the rule", Spoken:GetCurrent() == alone and Spoken:WhyNoControl(), nil)

---------------------------------------------------------------- the auto-form list
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Clear()
Expect("remembering outside a party does nothing", ns.Autoform:Remember(), nil)
ns.Autoform:Add(LALA)
Expect("adding her to the list tells her", P.Last("RM", LALA) ~= nil, true)
Expect("...with her invitations accepted without asking", ns.Autoform:Accepts(LALA), true)
P.Clear()
ns.Autoform:Tick()
Expect("each heartbeat greets whoever on the list is not here", P.Last("HI", LALA) and P.Last("HI", LALA).fields[4], "")
P.Receive(stub, LALA, "HI", "0.4.0", 1, "", 0)
P.Clear()
ns.Autoform:Tick()
Expect("she is online and in no party: the first by name invites, and that is her", P.Last("IV"), nil)
Expect("...so this side waits", ns.Peers:InParty(), false)
P.Receive(stub, LALA, "IV", "0.4.0", "lala throwaway-5")
Expect("her invitation is accepted without the popup", stub.popups[#stub.popups] == nil
	or stub.popups[#stub.popups].key ~= "SPOKENPARTYSYNC_INVITE", true)
Expect("...and the party stands", ns.Peers:IsMember(LALA) and ns.Peers:Leader(), "lala throwaway")

-- The saved leader forms the party, with the saved rules; a third is invited when they come.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns.Autoform:Add(LALA)
ns.Autoform:Add(BOB)
ns.Autoform:List().leader = ns:MyKey()
ns.Autoform:List().rules = { controls = "anyone", room = "lala throwaway", sync = { quests = true, gossip = true, zones = true, books = true } }
P.Clear()
P.Receive(stub, LALA, "HI", "0.4.0", 1, "", 0)
ns.Autoform:Tick()
Expect("the saved leader invites a listed character who is online and free", P.Last("IV", LALA) ~= nil, true)
Expect("...with the saved rules", ns.Peers:Rules().controls .. "|" .. ns.Peers:Rules().room, "anyone|lala throwaway")
Expect("...and only once in a while", #P.Sent("IV", LALA), 1)
ns.Autoform:Tick()
Expect("...not again at the next heartbeat", #P.Sent("IV", LALA), 1)
local sid = P.Last("IV", LALA).fields[3]
P.Receive(stub, LALA, "IA", sid)
P.Clear()
P.Receive(stub, BOB, "HI", "0.4.0", 1, "", 0)
ns.Autoform:Tick()
Expect("the third, coming online later, is invited by the leader", P.Last("IV", BOB) and P.Last("IV", BOB).fields[3], sid)
P.Receive(stub, BOB, "IA", sid)
Expect("...and joins", ns.Peers:Count(), 3)
P.Clear()
P.Receive(stub, BOB, "HI", "0.4.0", 1, "elsewhere-1", 0)
stub.Advance(11)
P.Receive(stub, BOB, "HI", "0.4.0", 1, "elsewhere-1", 0)
Expect("a listed character in another party is left alone", ns.Peers:IsMember(BOB), false)
ns.Autoform:Tick()
Expect("...and not invited", P.Last("IV", BOB), nil)

-- Two of a list inviting each other at once: the lower name's party wins.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns.Autoform:Add(LALA)
P.Receive(stub, LALA, "HI", "0.4.0", 1, "", 0)
ns.Autoform:List().leader = ns:MyKey()
P.Clear()
ns.Autoform:Tick()
Expect("this side, the saved leader, invites her", P.Last("IV", LALA) ~= nil, true)
P.Receive(stub, LALA, "IV", "0.4.0", "lala throwaway-7")
Expect("her invitation crossing it wins, her name coming first", ns.Peers:Leader(), "lala throwaway")
Expect("...and is accepted", P.Last("IA", LALA) and P.Last("IA", LALA).fields[2], "lala throwaway-7")
P.Receive(stub, LALA, "ID", sid)
Expect("her declining the old invitation changes nothing", ns.Peers:IsMember(LALA), true)

-- Being remembered asks whether to accept without the popup.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Receive(stub, LALA, "RM")
local asked = stub.popups[#stub.popups]
Expect("being added to her list asks", asked and asked.key, "SPOKENPARTYSYNC_REMEMBERED")
asked.dialog.OnCancel(nil, asked.args[3], "clicked")
Expect("...no puts her on this list, asked each time", ns.Autoform:Entry(LALA) ~= nil and not ns.Autoform:Accepts(LALA), true)
P.Receive(stub, LALA, "IV", "0.4.0", "lala throwaway-8")
Expect("...so her invitation shows the popup", stub.popups[#stub.popups].key, "SPOKENPARTYSYNC_INVITE")
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Receive(stub, LALA, "RM")
stub.popups[#stub.popups].dialog.OnAccept(nil, stub.popups[#stub.popups].args[3])
Expect("...yes puts her on it, accepted without asking", ns.Autoform:Accepts(LALA), true)
P.Receive(stub, LALA, "RM")
Expect("already on the list, she is not asked about again", stub.popups[#stub.popups].key, "SPOKENPARTYSYNC_REMEMBERED")

-- Remembering the party, by hand and automatically.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, nil, { controls = "anyone" })
P.Clear()
Expect("remembering the party puts her on the list", ns.Autoform:Remember(), 1)
Expect("...with who leads", ns.Autoform:List().leader, "lala throwaway")
Expect("...and the rules", ns.Autoform:List().rules.controls, "anyone")
Expect("...and tells her", P.Last("RM", LALA) ~= nil, true)
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().remember = true
P.Party(stub, ns)
P.Receive(stub, LALA, "RO", P.SESSION, LALA, "Lala Throwaway;Tata Throwaway;Bob Stranger")
Expect("with Remember Parties Automatically, a roster change remembers everyone", ns.Autoform:Entry(BOB) ~= nil and ns.Autoform:Entry(LALA) ~= nil, true)
P.Receive(stub, LALA, "PS", "nobody", "none", "1111")
ns.Autoform:AutoRemember()
Expect("...and the rules as they change", ns.Autoform:List().rules.controls, "nobody")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync session tests passed")
