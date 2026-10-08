-- How the party stands, as lines: who is in it and online, who leads, which computer plays the
-- sound, which controls are shared, and with `detailed` the lines played together lately.
--
-- `/sps status`, `/sps members` and `/sps sync` print them. Where Spoken takes diagnostics
-- (Spoken:AddDiagnostics, with the Spoken Developer module), they are also in
-- `/spoken diagnostics` and in every snapshot the debug log takes, so a log read on another
-- computer says what the party looked like at that moment.

local _, PartySync = ...

local Comm, Peers, Sync, Room = PartySync.Comm, PartySync.Peers, PartySync.Sync, PartySync.Room

local Diagnostics = {}
PartySync.Diagnostics = Diagnostics

-- How many of the lines played together `detailed` lists, newest first.
local ENTRIES = 10

local function OnOff(value)
	return value and "on" or "off"
end

local function Name(key)
	return key and Peers:MemberName(key) or "?"
end

--- One member: their state, round trip, version, what they asked for, when last heard.
function Diagnostics:MemberLine(key, leader)
	local peer = Peers.list[key]
	local parts = { peer and peer.state or "not heard from" }
	if peer then
		if peer.rtt then table.insert(parts, format("%d ms", math.floor(peer.rtt + 0.5))) end
		if peer.version then table.insert(parts, "v" .. peer.version) end
		table.insert(parts, "lead " .. tostring(peer.lead or "?"))
		if peer.room and peer.room ~= "" then table.insert(parts, "room " .. peer.room) end
		if peer.lastSeen then
			table.insert(parts, format("last heard %d s ago", math.floor(GetTime() - peer.lastSeen + 0.5)))
		end
	end
	if key == leader then table.insert(parts, "leads") end
	return format("%s: %s", Name(key), table.concat(parts, ", "))
end

--- The members, sorted, one line each.
function Diagnostics:MemberLines()
	local keys = {}
	for key in Peers:Members() do table.insert(keys, key) end
	table.sort(keys)
	local leader = Peers:Leader()
	local lines = {}
	for _, key in ipairs(keys) do
		table.insert(lines, self:MemberLine(key, leader))
	end
	return lines
end

--- One line played together, as `/sps sync` shows it.
function Diagnostics:EntryLine(entry)
	local peers = {}
	for key, peer in pairs(entry.peers) do
		table.insert(peers, format("%s %s%s", Name(key), tostring(peer.state), peer.ms and format(" +%d ms", peer.ms) or ""))
	end
	table.sort(peers)
	return format("%s (%s, %s%s): %s%s", tostring(Sync.LabelOf(entry)), entry.id, entry.role,
		entry.role == "follower" and (" of " .. Name(entry.driver)) or "",
		tostring(entry.state), peers[1] and (" -- " .. table.concat(peers, ", ")) or "")
end

function Diagnostics:EntryLines()
	local lines = {}
	for i, entry in ipairs(Sync:Entries()) do
		if i > ENTRIES then break end
		table.insert(lines, self:EntryLine(entry))
	end
	return lines
end

function Diagnostics:Lines(detailed)
	local db = PartySync:DB()
	local lines = {}
	local function Add(text, ...)
		table.insert(lines, select("#", ...) > 0 and format(text, ...) or text)
	end

	Add("Spoken Party Sync %s; group: %s; %s", PartySync.version, tostring(Comm:GroupChannel() or "none"), Comm:Context())
	Add("debug log: %s", not PartySync.LogBook:Available() and "no Spoken Developer module"
		or PartySync.LogBook:IsOn() and "on" or "off")
	local leader, why = Peers:Leader()
	local speaker = Room:Speaker()
	Add("leader: %s (%s); controls: %s; sound: %s", Name(leader), tostring(why), tostring(db.controls),
		speaker and Name(speaker) or "every computer")
	local party = PartySync:Party()
	Add("this computer: %s, lead %s, room %s%s", tostring(PartySync:MyKey()), tostring(party.lead),
		Room:Describe(party.roomSpeaker), Room:IsSilent() and ", captions only" or "")
	Add("played together: quests %s, gossip %s, zones %s, books %s; auto share %s, auto accept %s",
		OnOff(db.sync.quests ~= false), OnOff(db.sync.gossip ~= false), OnOff(db.sync.zones ~= false),
		OnOff(db.sync.books ~= false), OnOff(db.autoShare), OnOff(db.autoAccept))

	local members = self:MemberLines()
	if members[1] then
		Add("members:")
		for _, line in ipairs(members) do Add("  %s", line) end
	else
		Add("members: nobody yet")
	end
	local others = {}
	for key, peer in pairs(Peers.list) do
		if not Peers:IsMember(key) then
			table.insert(others, format("%s (%s%s)", peer.name or key, tostring(peer.state), peer.version and (", v" .. peer.version) or ""))
		end
	end
	if others[1] then
		table.sort(others)
		Add("others running the addon: %s", table.concat(others, ", "))
	end

	if detailed then
		local entries = self:EntryLines()
		Add("lines played together lately: %s", entries[1] and "" or "none")
		for _, line in ipairs(entries) do Add("  %s", line) end
		for _, problem in ipairs(PartySync:Problems()) do
			Add("problem, %d s ago: %s", math.floor(GetTime() - problem.at + 0.5), problem.text)
		end
		for key, log in pairs(db.collected or {}) do
			Add("collected log: %s, %d lines%s, at %s", tostring(log.name or key), log.lines and #log.lines or 0,
				(log.missing or 0) > 0 and format(" (%d missing)", log.missing) or "", tostring(log.at))
		end
	end
	return lines
end

--- In Spoken's diagnostics, where it takes them.
function Diagnostics:Setup()
	local Spoken = _G.Spoken
	if self.ready or not (Spoken and Spoken.AddDiagnostics) then return end
	self.ready = true
	Spoken:AddDiagnostics("Spoken Party Sync", function(detailed) return Diagnostics:Lines(detailed) end)
end
