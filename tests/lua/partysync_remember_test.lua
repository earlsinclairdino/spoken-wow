-- Spoken Party Sync's offer to remember a party that ended, and asking back someone dropped from
-- a party: once, only for a party worth keeping, never again for people declined; and a member
-- re-invited within ten minutes rejoins without the popup. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)

local LALA = P.LALA
local BOB = "Bob Stranger"
local LOOKUP = { ["101-accept"] = 10 }

local Fields = P.Fields

local QuestLine = P.QuestLine

local ns, VO, env, Spoken

--- A party led here with Lala, long enough and with a line played, `setup` changing it, then left.
local function OfferAfter(setup)
	ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
	P.Party(stub, ns, nil, "me")
	local session = ns:Party().session
	session.started, session.played = time() - 700, 1
	if setup then setup(session) end
	ns.Peers:Leave()
	return ns.Autoform:Prompt()
end

---------------------------------------------------------------- offered once
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
VO.Player:Enqueue(QuestLine(VO, 101))
P.Receive(stub, LALA, "AK", "101-accept", "queued")
stub.Advance(0.55)
Expect("a line played together counts for the party", ns:Party().session.played, 1)
ns:Party().session.started = time() - 700
ns.Peers:Leave()
Expect("a party that went well, not remembered, is offered when it ends",
	ns.windowModel.prompt and ns.windowModel.prompt.text, format(ns.L.PROMPT_FMT, "Lala"))
Expect("...in the window, which shows itself for it", _G.SpokenPartySyncWindow.shown, true)
Expect("...with Remember and Not now", ns:WindowText():find("[" .. ns.L.PROMPT_REMEMBER .. "] [" .. ns.L.PROMPT_NOT_NOW .. "]", 1, true) ~= nil, true)
P.Clear()
ns.windowModel.prompt.actions[1].run()
Expect("Remember puts her in the usual party", ns.Autoform:Entry(LALA) ~= nil, true)
Expect("...with who led", ns.Autoform:List().leader, ns:MyKey())
Expect("...and the rules", ns.Autoform:List().rules and ns.Autoform:List().rules.controls, "anyone")
Expect("...and tells her", P.Last("RM", LALA) ~= nil, true)
ns:RefreshWindow()
Expect("...and the offer goes", ns.windowModel.prompt, nil)

Expect("a short party is not offered", OfferAfter(function(session) session.started = time() - 60 end), nil)
Expect("...nor one where nothing played together", OfferAfter(function(session) session.played = 0 end), nil)
Expect("...nor one where someone was lost", OfferAfter(function(session) session.troubled = true end), nil)
Expect("...nor one whose people are remembered already", OfferAfter(function() ns.Autoform:Add(LALA) end), nil)
Expect("the offer does not stand for ever", OfferAfter() ~= nil, true)
stub.Advance(121)
Expect("...two minutes", ns.Autoform:Prompt(), nil)

-- Ended by her going: offered with her in it, unless she was lost.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:Party().session.started, ns:Party().session.played = time() - 700, 2
P.Receive(stub, LALA, "ID", P.SESSION)
Expect("a party ended by a member leaving is offered with them in it", ns.Autoform:Prompt() and ns.Autoform:Prompt().names, "Lala")
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:Party().session.started, ns:Party().session.played = time() - 700, 2
ns.Peers:Gone("lala throwaway", "lost")
Expect("...but not one ended by a member lost", ns.Autoform:Prompt(), nil)
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns:Party().session.started, ns:Party().session.played = time() - 700, 2
ns.Peers:MarkOffline(LALA)
Expect("...while one ended by her logging out is", ns.Autoform:Prompt() and ns.Autoform:Prompt().names, "Lala")
ns:ShowWindow(false)
ns:RefreshWindow()
Expect("closed by hand, the offer does not bring the window back", _G.SpokenPartySyncWindow.shown, false)
ns:Problem("test", "Something is wrong")
Expect("...something new going wrong does", _G.SpokenPartySyncWindow.shown, true)
ns:Resolve("test")

-- Not now: never again for the same people.
OfferAfter()
ns.windowModel.prompt.actions[2].run()
local account, character = _G.SpokenPartySyncDB, _G.SpokenPartySyncCharDB
Expect("Not now is kept with the character", character.declined["lala throwaway"] ~= nil, true)
ns, VO, env, Spoken = P.Boot(stub, LOOKUP, { account = account, character = character })
P.Party(stub, ns, nil, "me")
ns:Party().session.started, ns:Party().session.played = time() - 700, 1
ns.Peers:Leave()
Expect("...so the same people are not offered again", ns.Autoform:Prompt(), nil)
P.Party(stub, ns, nil, "me")
ns:Party().session.members["bob stranger"] = BOB
ns:Party().session.started, ns:Party().session.played = time() - 700, 1
ns.Peers:Leave()
Expect("...while others are", ns.Autoform:Prompt() and ns.Autoform:Prompt().names, "Bob, Lala")
SlashCmdList["SPOKENPARTYSYNC"]("remember")
Expect("/sps remember takes the offer too", ns.Autoform:Entry(BOB) ~= nil, true)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
ns:DB().window.show = "never"
stub.chat = {}
OfferAfter(function() ns:DB().window.show = "never"; stub.chat = {} end)
local said = false
for _, line in ipairs(stub.chat) do
	if line:find("play with Lala again", 1, true) then said = true end
end
Expect("with the window never shown, the offer is made in chat", said, true)
ns:DB().window.show = "problems"

---------------------------------------------------------------- asked back
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.Peers:Gone("lala throwaway", "lost")
Expect("dropped from her party, this character is in none", ns.Peers:InParty(), false)
local popups = #stub.popups
P.Clear()
P.Receive(stub, LALA, "IV", "0.5.0", P.SESSION, 1)
Expect("asked back into that party, it rejoins", ns.Peers:InParty() and Fields(P.Last("IA", LALA)), P.SESSION)
Expect("...without the popup", #stub.popups, popups)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.Peers:Gone("lala throwaway", "lost")
stub.Advance(601, 1)
P.Receive(stub, LALA, "IV", "0.5.0", P.SESSION, 1)
Expect("ten minutes on, it is a new question", stub.popups[#stub.popups].key, "SPOKENPARTYSYNC_INVITE")
Expect("...not yet answered", ns.Peers:InParty(), false)
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
ns.Peers:Gone("lala throwaway", "lost")
popups = #stub.popups
P.Receive(stub, BOB, "IV", "0.5.0", "bob stranger-9", 1)
Expect("someone who was not in that party asking is a new question too", #stub.popups, popups + 1)

ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
ns.Peers:Gone("lala throwaway", "lost")
P.Clear()
ns:Party().lastSession.rules.controls = "nobody"
ns.Peers:Reinvite(LALA)
local asked = P.Last("IV", LALA)
Expect("Re-invite after the party ended asks her back", asked and asked.fields[4], "1")
Expect("...into a party of its own, never the old one under its id: others may still be in it",
	asked.fields[3] ~= P.SESSION and ns.Peers:SessionId() == asked.fields[3], true)
Expect("...with the old party's rules", ns.Peers:Rules().controls, "nobody")
P.Receive(stub, LALA, "IA", asked.fields[3])
Expect("...and she is in it", ns.Peers:IsMember(LALA), true)
local current = ns.Peers:SessionId()
ns:Party().session.members["bob stranger"] = BOB
ns.Peers:Gone("bob stranger", "lost")
P.Clear()
ns.Peers:Reinvite(BOB)
Expect("a member dropped from a party still going is asked back into it", Fields(P.Last("IV", BOB)),
	ns.version .. "|" .. current .. "|1")
P.Clear()
ns.Peers:Reinvite("Zed Unknown")
Expect("someone never in it is simply invited", P.Last("IV", "Zed Unknown") and P.Last("IV", "Zed Unknown").fields[4], "0")

---------------------------------------------------------------- the setting that went
ns, VO, env, Spoken = P.Boot(stub, LOOKUP, { account = { remember = true } })
Expect("Remember Parties Automatically is gone from the saved settings", ns:DB().remember, nil)
local labels = {}
for _, entry in ipairs(ns.optionsLayout.entries) do labels[entry.label] = true end
Expect("...and from the page", labels["Remember Parties Automatically"], nil)
P.Party(stub, ns)
P.Receive(stub, LALA, "RO", P.SESSION, LALA, "Lala Throwaway;Tata Throwaway;Bob Stranger")
Expect("...so a roster change remembers nobody", ns.Autoform:Entry(BOB), nil)

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync remember tests passed")
