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
Expect("this character cannot be its own member", ns.Peers:AddMember("tata throwaway"), false)

---------------------------------------------------------------- the 0.1 companion
_G.SpokenPartySyncDB = { companion = '"lala throwaway"', windowShown = true }
ns:InitDB()
Expect("a companion saved by 0.1 becomes a member", ns.Peers:IsMember("Lala Throwaway"), true)
Expect("...under its cleaned name", ns:DB().members["lala throwaway"].name, "Lala Throwaway")
Expect("...and the old field goes", ns:DB().companion, nil)
Expect("a window left open by 0.1 stays shown", ns:DB().window.show, "always")
Expect("the other settings get their defaults", ns:DB().controls, "leader")

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
ns.Peers:AddMember("Lala Throwaway")
P.Receive(stub, "Lala Throwaway", "HI", "0.2.0", 1, "auto", "")
Expect("a member's hello puts them online", ns.Peers.list["lala throwaway"].state, "online")
ns.Comm:Whisper("Lala Throwaway", "PI", "t2")
stub.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Lala Throwaway' is currently playing.")
Expect("the client's \"No player named\" after our whisper marks them offline", ns.Peers.list["lala throwaway"].state, "offline")
stub.Advance(5)
P.Receive(stub, "Lala Throwaway", "HI", "0.2.0", 1, "auto", "")
stub.FireEvent("CHAT_MSG_SYSTEM", "No player named 'Lala Throwaway' is currently playing.")
Expect("...but not the same message long after any whisper", ns.Peers.list["lala throwaway"].state, "online")

---------------------------------------------------------------- invitations
local ns2 = P.Boot(stub, LOOKUP)
P.Receive(stub, "Lala Throwaway", "IV", "0.2.0")
local popup = stub.popups[#stub.popups]
Expect("an invitation asks the player", popup and popup.key, "SPOKENPARTYSYNC_INVITE")
Expect("...naming who asks", popup.args[1], "Lala Throwaway")
popup.dialog.OnAccept(nil, popup.args[3])
Expect("accepting makes them a member", ns2.Peers:IsMember("Lala Throwaway"), true)
Expect("...and says so to them", P.Last("IA") and P.Last("IA").target, "Lala Throwaway")
P.Clear()
P.Receive(stub, "Lala Throwaway", "IV", "0.2.0")
Expect("a member asking again is answered without a question", P.Last("IA") ~= nil, true)
P.Receive(stub, "Lala Throwaway", "ID")
Expect("a member leaving is forgotten", ns2.Peers:IsMember("Lala Throwaway"), false)
P.Receive(stub, "Bob Stranger", "IA")
Expect("an acceptance nobody asked for is ignored", ns2.Peers:IsMember("Bob Stranger"), false)
ns2.Peers:Invite("Bob Stranger")
P.Receive(stub, "Bob Stranger", "IA")
Expect("...and one that answers our invitation is not", ns2.Peers:IsMember("Bob Stranger"), true)

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

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync wire tests passed")
