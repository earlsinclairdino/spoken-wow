-- Spoken Party Sync's wire: Forever's names, the message format, captions in pieces, the
-- pacing inside instances, and the client's "No player named" read as offline. Run with
-- `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)

local LOOKUP = { ["101-accept"] = 2 }
local ns = P.Boot(stub, LOOKUP)

---------------------------------------------------------------- names
-- Forever has no realms: "First Last", whispered bare. The beta still reports a backend realm,
-- which must never end up in an address (2026-10-05: "No player named 'X-ClassicBetaPvE2'").
Expect("a bare two-part name is whispered as it is", ns:WhisperName("Lala Throwaway"), "Lala Throwaway")
Expect("...our own backend realm is dropped", ns:WhisperName("Lala Throwaway-ClassicBetaPvE2"), "Lala Throwaway")
Expect("...however it is spaced", ns:WhisperName("Lala Throwaway-Classic Beta PvE 2"), "Lala Throwaway")
Expect("a foreign realm is kept", ns:WhisperName("Bob-Elsewhere"), "Bob-Elsewhere")
Expect("names compare without case", ns:NameKey("LALA throwaway"), ns:NameKey("Lala Throwaway"))
Expect("typed quotes are not part of the name", ns:CleanName('"lala throwaway"'), "Lala Throwaway")
Expect("this character in its whole name is itself", ns:IsSelf("Tata Throwaway"), true)
Expect("...and by its first name, as UnitName gives it", ns:IsSelf("Tata"), true)
Expect("...and with the backend realm a sender may carry", ns:IsSelf("Tata Throwaway-ClassicBetaPvE2"), true)
Expect("the other character is not", ns:IsSelf("Lala Throwaway"), false)
Expect("this character cannot invite itself", (ns.Peers:Invite("tata throwaway")), false)

---------------------------------------------------------------- the 0.1 companion
_G.SpokenPartySyncDB = { companion = '"lala throwaway"', windowShown = true }
_G.SpokenPartySyncCharDB = nil
ns:InitDB()
Expect("a companion saved by 0.1 goes on the auto-form list", ns.Autoform:Entry("Lala Throwaway") ~= nil, true)
Expect("...under its cleaned name", ns.Autoform:Entry("Lala Throwaway").name, "Lala Throwaway")
Expect("...and the old field goes", ns:DB().companion, nil)
Expect("a window left open by 0.1 stays shown", ns:DB().window.show, "always")
Expect("the other settings get their defaults", ns:DB().rules.controls, "anyone")

---------------------------------------------------------------- text in fields
local awkward = "Line one\nTabbed\there, a pipe | and a backslash \\ -- naïve"
Expect("escaped text has no tab or line break", ns.Comm.Escape(awkward):find("[\t\n|]"), nil)
Expect("...and comes back the same", ns.Comm.Unescape(ns.Comm.Escape(awkward)), awkward)
local long = string.rep("Wolves gather near the border. ", 40) .. "Ölf\n"
local pieces = ns.Comm.Chunk(long, 100)
local joined = table.concat(pieces)
Expect("a long text is cut into pieces no longer than asked", #pieces[1] <= 100 and #pieces[#pieces] <= 100, true)
Expect("...which join and unescape back to the text, cuts through characters included",
	ns.Comm.Unescape(joined), long)

---------------------------------------------------------------- a line's description
local d = { id = "101-accept", src = "quests", event = 1, questID = 101, npcID = 1234, length = 2.5,
	low = false, name = "Marshal\tMcBride", title = "A Threat Within" }
local fields = ns.Lines:Encode(d, 3)
local back = ns.Lines:Decode(unpack(fields))
Expect("an announcement decodes to the line it describes", back.id, "101-accept")
Expect("...its source", back.src, "quests")
Expect("...quest and speaker as numbers", back.questID == 101 and back.npcID == 1234, true)
Expect("...its length", back.length, 2.5)
Expect("...how many pieces of text follow", back.textParts, 3)
Expect("...and the names, tabs and all", back.name, "Marshal\tMcBride")
local huge = { id = "g:" .. string.rep("f", 32), src = "quests", event = 5, name = string.rep("N", 200),
	title = string.rep("T", 300), low = true }
local message = "LN\t" .. table.concat(ns.Lines:Encode(huge, 0), "\t")
Expect("an announcement with overlong names still fits in a message", #message <= 255, true)
Expect("...and says it is gossip", ns.Lines:Decode(unpack(ns.Lines:Encode(huge, 0))).low, true)
Expect("a quest line's id drops the player's gender", ns.Lines:IdFor("quests", "f-101-accept"), "101-accept")
Expect("...a zone's does not change", ns.Lines:IdFor("zones", "s:1429:northshire valley"), "s:1429:northshire valley")

---------------------------------------------------------------- sending
P.Clear()
ns.Comm:Whisper("Lala Throwaway-ClassicBetaPvE2", "PI", "t1")
Expect("a whisper goes to the bare name", P.Last("PI").target, "Lala Throwaway")
Expect("...on the addon's prefix", P.Last("PI").prefix, "SpokenPartySync")
local sent, answer = ns.Comm:Whisper("Lala Throwaway", "TX", string.rep("x", 300))
Expect("a message over 255 bytes is refused, not cut", sent, false)

-- Whispers outside an instance are not limited: 30 arrived at once on the beta.
P.Clear()
for i = 1, 20 do ns.Comm:Whisper("Lala Throwaway", "BU", i) end
Expect("outside an instance twenty whispers go at once", #P.Sent("BU"), 20)
P.client.inInstance = true
P.Clear()
stub.Advance(10)
for i = 1, 14 do ns.Comm:Whisper("Lala Throwaway", "BU", i) end
Expect("inside one, the client's allowance of ten goes at once", #P.Sent("BU"), 10)
stub.Advance(1.05)
Expect("...and one more each second", #P.Sent("BU"), 11)
stub.Advance(3.1)
Expect("...until the rest are out, in order", #P.Sent("BU") == 14 and P.Last("BU").fields[2] == "14", true)
P.client.inInstance = false

---------------------------------------------------------------- offline
P.Party(stub, ns)
Expect("a member's hello puts them online", ns.Peers.list["lala throwaway"].state, "online")
ns.Comm:Whisper("Lala Throwaway", "PI", "t2")
stub.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Lala Throwaway' is currently playing.")
Expect("the client's \"No player named\" after our whisper marks them offline", ns.Peers.list["lala throwaway"].state, "offline")
Expect("...and a party of two is over with one gone", ns.Peers:InParty(), false)
stub.Advance(5)
P.Receive(stub, "Lala Throwaway", "HI", "0.2.0", 1, "auto", "")
stub.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Lala Throwaway' is currently playing.")
Expect("...but not the same message long after any whisper", ns.Peers.list["lala throwaway"].state, "online")

---------------------------------------------------------------- invitations
local Fields = P.Fields
local ns2 = P.Boot(stub, LOOKUP)
P.Receive(stub, "Lala Throwaway", "IV", "0.4.0", "lala throwaway-9")
local popup = stub.popups[#stub.popups]
Expect("an invitation asks the player", popup and popup.key, "SPOKENPARTYSYNC_INVITE")
Expect("...naming who asks", popup.args[1], "Lala Throwaway")
popup.dialog.OnAccept(nil, popup.args[3])
Expect("accepting makes them a member", ns2.Peers:IsMember("Lala Throwaway"), true)
Expect("...and says so to them, naming the party", P.Last("IA") and P.Last("IA").target .. "|" .. P.Last("IA").fields[2], "Lala Throwaway|lala throwaway-9")
Expect("...whose leader they are", ns2.Peers:Leader(), "lala throwaway")
P.Clear()
P.Receive(stub, "Lala Throwaway", "IV", "0.4.0", "lala throwaway-9")
Expect("a member asking again is answered without a question", P.Last("IA") ~= nil, true)
P.Receive(stub, "Bob Stranger", "IV", "0.4.0", "bob stranger-1")
Expect("another party's invitation is declined while in one", P.Last("ID") and P.Last("ID").target, "Bob Stranger")
Expect("...and this party stands", ns2.Peers:IsMember("Lala Throwaway"), true)
P.Receive(stub, "Lala Throwaway", "ID", "lala throwaway-9")
Expect("the leader removing this character ends the party here", ns2.Peers:InParty(), false)
P.Receive(stub, "Bob Stranger", "IA", "x")
Expect("an acceptance nobody asked for is ignored", ns2.Peers:IsMember("Bob Stranger"), false)
P.Clear()
Expect("inviting starts a party led here", (ns2.Peers:Invite("Bob Stranger")) and ns2.Peers:AmLeader(), true)
local id = P.Last("IV", "Bob Stranger").fields[3]
P.Receive(stub, "Bob Stranger", "IA", id)
Expect("...and one that answers our invitation joins it", ns2.Peers:IsMember("Bob Stranger"), true)
Expect("...and is sent the roster", Fields(P.Last("RO", "Bob Stranger")), id .. "|tata throwaway|Tata Throwaway;Bob Stranger")
Expect("...and the rules", Fields(P.Last("PS", "Bob Stranger")), "anyone|none|1111|anyone|music=none;effects=none;ambience=none;dialog=none")

---------------------------------------------------------------- the portrait menu
local entries = {}
local root = {
	CreateDivider = function() end,
	CreateTitle = function() end,
	CreateButton = function(_, text, fn) table.insert(entries, { text = text, fn = fn }) end,
}
Expect("the party's right-click menu is extended", P.menus.MENU_UNIT_PARTY ~= nil, true)
P.client.units.party1 = "Lala Throwaway"
P.menus.MENU_UNIT_PARTY(nil, root, { unit = "party1" })
Expect("a player who is not a member can be invited", entries[1] and entries[1].text, ns2.L.MENU_INVITE)
P.Clear()
entries[1].fn()
Expect("...which sends the invitation", P.Last("IV") and P.Last("IV").target, "Lala Throwaway")
entries = {}
P.menus.MENU_UNIT_PARTY(nil, root, { unit = "npc" })
Expect("an NPC gets no entry", entries[1], nil)

---------------------------------------------------------------- the party is the character's
-- The members know this character by its name, so another character on this computer cannot
-- speak for its party: each character keeps its own (2026-10-08, Tata logged out, Williams in,
-- and Lala's computer refused every line Williams sent).
local ACCOUNT_030 = { members = { ["lala throwaway"] = { name = "Lala Throwaway", added = 0 } },
	lead = "lala throwaway", roomSpeaker = "me", controls = "anyone", sync = { quests = true, gossip = false, zones = true, books = true } }
local ns3 = P.Boot(stub, LOOKUP, { account = ACCOUNT_030 })
Expect("a party 0.3 kept with the account becomes this character's auto-form list", ns3.Autoform:Entry("Lala Throwaway") ~= nil, true)
Expect("...accepted without asking, as a member was", ns3.Autoform:Accepts("Lala Throwaway"), true)
Expect("...with who led", ns3.Autoform:List().leader, "lala throwaway")
Expect("...and which computer played the sound", ns3.Autoform:List().rules.room, "tata throwaway")
Expect("...and leaves the account", ACCOUNT_030.members == nil and ACCOUNT_030.lead == nil
	and ACCOUNT_030.roomSpeaker == nil and ACCOUNT_030.controls == nil and ACCOUNT_030.sync == nil, true)
Expect("...whose controls and kinds become this computer's rules", ns3:DB().rules.controls .. "|" .. tostring(ns3:DB().rules.sync.gossip), "anyone|false")
Expect("...and it is in no party", ns3.Peers:InParty(), false)

ns3 = P.Boot(stub, LOOKUP)
ns3.Autoform:Add("Lala Throwaway")
local account, character = _G.SpokenPartySyncDB, _G.SpokenPartySyncCharDB
Expect("the auto-form list is saved with the character", character.list.members["lala throwaway"] ~= nil, true)
Expect("...and not with the account", account.list, nil)
-- Another character: the same account file, a character file of its own.
ns3 = P.Boot(stub, LOOKUP, { account = account })
Expect("another character on this computer has its own, empty list", ns3.Autoform:Keys()[1], nil)
ns3 = P.Boot(stub, LOOKUP, { account = account, character = character })
Expect("the first character logging back in has its list again", ns3.Autoform:Entry("Lala Throwaway") ~= nil, true)

---------------------------------------------------------------- the group channel
-- 2026-10-11: whispers between two players took 110 s each way all evening while the party
-- channel took under a second, so a member in the group is sent its messages there, addressed.
ns = P.Boot(stub, LOOKUP)
local connected = true
_G.UnitIsConnected = function() return connected end
local function FromGroup(sender, ...)
	stub.FireEvent("CHAT_MSG_ADDON", "SpokenPartySync", table.concat({ ... }, "\t"), "PARTY", sender)
end
P.Party(stub, ns)
P.client.units.party1 = "Lala Throwaway"
P.Clear()
ns.Comm:Whisper("Lala Throwaway", "PI", "g1")
Expect("a member whose hello does not say it reads addressed messages is whispered, grouped or not",
	P.Last("PI") and P.Last("PI").channel, "WHISPER")
ns.Peers:Greet("Lala Throwaway", true)
Expect("this version's hello says it reads them, in its last field", P.Last("HI").fields[8], "to")
P.Receive(stub, P.LALA, "HI", "0.5.1", 1, P.SESSION, 0, "v", "", "to")
P.Clear()
ns.Comm:Whisper("Lala Throwaway", "PI", "g2")
local addressed = P.Last("TO")
Expect("once it does, and she is in the group, it goes on the group channel",
	addressed and addressed.channel, "PARTY")
Expect("...addressed to her", P.Fields(addressed), "lala throwaway|PI|g2")
Expect("...and is not whispered", P.Last("PI"), nil)
P.client.units.party1 = nil
P.Clear()
ns.Comm:Whisper("Lala Throwaway", "PI", "g3")
Expect("out of the group she is whispered", P.Last("PI") and P.Last("PI").channel, "WHISPER")
P.client.units.party1 = "Lala Throwaway"
connected = false
P.Clear()
ns.Comm:Whisper("Lala Throwaway", "PI", "g4")
Expect("...and offline in it, so the client can say she is gone", P.Last("PI") and P.Last("PI").channel, "WHISPER")
connected = true
P.Clear()
ns.Comm:Whisper("Lala Throwaway", "TX", string.rep("x", 240))
Expect("a message with no room for the address is whispered", P.Last("TX") and P.Last("TX").channel, "WHISPER")
P.Clear()
ns.Comm:Whisper("Lala Throwaway", "LL", "t", 1, "a line")
Expect("a log's lines are whispered: hundreds would hold the party's messages back", P.Last("TO"), nil)

P.Clear()
FromGroup(P.LALA, "TO", "tata throwaway", "PI", "g5")
Expect("a message addressed here is handled", P.Fields(P.Last("TO")), "lala throwaway|PO|g5")
P.Clear()
FromGroup(P.LALA, "TO", "mira throwaway", "PI", "g6")
Expect("one addressed to someone else in the group is dropped", #P.sent, 0)
FromGroup(P.LALA, "TO", "*", "PI", "g7")
Expect("one for the whole party is handled when it comes from a member", P.Fields(P.Last("TO")), "lala throwaway|PO|g7")
P.Clear()
FromGroup("Bob Stranger", "TO", "*", "PI", "g8")
Expect("...and dropped from anyone else", #P.sent, 0)

-- Lala's ping is answered on the group channel and timed: her pong measures the way used.
ns.Peers:Ping("Lala Throwaway", true)
local token = P.Fields(P.Last("TO")):match("PI|(.+)$")
stub.Advance(0.4)
FromGroup(P.LALA, "TO", "tata throwaway", "PO", token)
Expect("a pong addressed on the group channel times the party's messages", math.floor(ns.Peers:Rtt("lala throwaway") / 100 + 0.5), 4)
P.Receive(stub, P.LALA, "PO", "1000-1")
Expect("a whisper still on its way from before she was addressed does not make her late", ns.Peers:Delay("lala throwaway"), nil)

-- Two members in the group: what is for both goes once.
ns:Party().session.members["mira throwaway"] = "Mira Throwaway"
P.client.units.party2 = "Mira Throwaway"
P.Receive(stub, "Mira Throwaway", "HI", "0.5.1", 1, P.SESSION, 0, "v", "", "to")
P.Clear()
ns.Comm:WhisperEach({ "Lala Throwaway", "Mira Throwaway" }, "SK", "101-accept")
Expect("a message for two members in the group is sent once, to the party", #P.Sent("TO"), 1)
Expect("...addressed to all of it", P.Fields(P.Last("TO")), "*|SK|101-accept")
Expect("in a group a line's text goes in at most eight pieces, so its start is not held back", ns.Comm:TextBudget(), 8)

-- At login, a member in the group not yet heard from is greeted with the group's hello: a
-- whispered one can arrive minutes later and say a party that is over.
ns = P.Boot(stub, LOOKUP)
ns:Party().session = { id = P.SESSION, leader = ns:NameKey(P.LALA), rules = ns.Rules(),
	members = { [ns:MyKey()] = P.ME, [ns:NameKey(P.LALA)] = P.LALA, ["mira throwaway"] = "Mira Throwaway" } }
P.client.units.party1, P.client.units.party2 = "Lala Throwaway", "Mira Throwaway"
P.Clear()
ns.Peers:HelloMembers()
Expect("members in the group are greeted by the group's hello, not whispered", P.Last("HI") and P.Last("HI").channel, "PARTY")
Expect("...once for both", #P.Sent("HI"), 1)
_G.UnitIsConnected = nil

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync wire tests passed")
