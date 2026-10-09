-- How the party stands, as lines: who is in it and online, who leads, which computer plays the
-- sound, which controls are shared, and with `detailed` the lines played together lately.
--
-- `/sps status`, `/sps members` and `/sps sync` print them. Where Spoken takes diagnostics
-- (Spoken:AddDiagnostics, with the Spoken Developer module), they are also in
-- `/spoken diagnostics` and in every snapshot the debug log takes, so a log read on another
-- computer says what the party looked like at that moment.

local _, PartySync = ...

local Comm, Peers, Sync, Room, L = PartySync.Comm, PartySync.Peers, PartySync.Sync, PartySync.Room, PartySync.L

local Diagnostics = {}
PartySync.Diagnostics = Diagnostics

--------------------------------------------------------------------------------
-- What each computer runs
--------------------------------------------------------------------------------

local GetAddOnMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded

-- The addons a hello names, a letter each; the sources among them by the key they register.
-- `shared`: what lines played together go through, so every computer should run the same.
local MODULES = {
	{ code = "S", folder = "Spoken", title = "Spoken", shared = true },
	{ code = "Q", folder = "Spoken_Quests", title = "Spoken Quests", source = "quests", shared = true },
	{ code = "Z", folder = "Spoken_Zones", title = "Spoken Zones", source = "zones", shared = true },
	{ code = "B", folder = "Spoken_Books", title = "Spoken Books", source = "books", shared = true },
	{ code = "D", folder = "Spoken_Developer", title = "Spoken Developer" },
	{ code = "U", folder = "DialogueUI", title = "DialogueUI" },
}

--- What this computer runs, as a hello carries it: "S=3.1.0;Q=3.1.0+;...", with "+" after a
--- module that can rebuild a line another computer started. The store's build and Party Sync's
--- share a version number; only that tells them apart. What is not loaded is left out.
function Diagnostics:Modules()
	local parts = {}
	local Spoken = _G.Spoken
	for _, module in ipairs(MODULES) do
		local ok, loaded = pcall(IsLoaded, module.folder)
		if ok and loaded then
			local version = (tostring(GetAddOnMeta and GetAddOnMeta(module.folder, "Version") or "?"):gsub("[;=\t]", ""))
			local source = module.source and Spoken and Spoken.GetSource and Spoken:GetSource(module.source)
			table.insert(parts, module.code .. "=" .. version .. ((source and source.rebuild) and "+" or ""))
		end
	end
	return table.concat(parts, ";")
end

local function Parse(modules)
	local found = {}
	for code, version in (modules or ""):gmatch("(%a)=([^;]*)") do found[code] = version end
	return found
end

--- One module's version as a hello gave it, in words for a comparison.
local function Word(module, version)
	if not version then return L.VERSION_NONE end
	local rebuilds = version:sub(-1) == "+"
	if rebuilds then version = version:sub(1, -2) end
	return (module.source and not rebuilds) and (version .. " " .. L.VERSION_STORE) or version
end

--- What `key`'s computer runs, as far as this one knows: Party Sync's version and the modules.
local function Runs(key)
	if key == PartySync:MyKey() then return PartySync.version, Diagnostics:Modules() end
	local peer = Peers.list[key]
	return peer and peer.version, peer and peer.modules
end

--- How `key`'s computer differs from the leader's in what lines played together go through, a
--- line each; nil when it runs the same, or when the leader is not heard from yet.
function Diagnostics:Differences(key)
	local leader = Peers:InParty() and Peers:Leader()
	if not leader or key == leader then return nil end
	local version, modules = Runs(key)
	local leaderVersion, leaderModules = Runs(leader)
	if not (version and leaderVersion) then return nil end
	local lines = {}
	if version ~= leaderVersion then
		table.insert(lines, format(L.VERSION_DIFFERS_FMT, L.TITLE, version, leaderVersion))
	end
	-- A leader before modules were said: only Party Sync's own version to go by.
	if leaderModules then
		if not modules then
			table.insert(lines, L.VERSION_UNSAID)
		else
			local mine, theirs = Parse(modules), Parse(leaderModules)
			for _, module in ipairs(MODULES) do
				if module.shared and mine[module.code] ~= theirs[module.code] then
					table.insert(lines, format(L.VERSION_DIFFERS_FMT, module.title,
						Word(module, mine[module.code]), Word(module, theirs[module.code])))
				end
			end
		end
	end
	return lines[1] and lines or nil
end

-- key -> the differences last said in chat, so each is said once.
local told = {}

--- The handshake: every member's computer, this one's included, held against the leader's each
--- time a hello says what one runs. A difference found is said once in chat; the window shows
--- it next to the name for as long as it lasts. True when any difference came or went.
function Diagnostics:CheckVersions()
	if not Peers:InParty() then return false end
	local moved = false
	for _, key in ipairs(Peers:MemberKeys()) do
		local differences = self:Differences(key)
		local said = differences and table.concat(differences, "; ") or nil
		if said ~= told[key] then
			moved = true
			if said then
				local who = key == PartySync:MyKey() and L.VERSION_YOUR_COMPUTER
					or format(L.VERSION_THEIR_COMPUTER_FMT, PartySync:ShortName(Peers:MemberName(key)))
				PartySync:Trace("party", "versions: %s differs from the leader's: %s", key, said)
				PartySync:Print(L.VERSION_MISMATCH_FMT, who, said)
			end
		end
		told[key] = said
	end
	return moved
end

--- `modules`, as Modules gives it, in words: a line for every module, running or not.
function Diagnostics:DescribeModules(modules)
	local found = Parse(modules)
	local lines = {}
	for _, module in ipairs(MODULES) do
		local version = found[module.code]
		if not version then
			table.insert(lines, format(L.VERSION_NOT_RUNNING_FMT, module.title))
		else
			local rebuilds = version:sub(-1) == "+"
			if rebuilds then version = version:sub(1, -2) end
			local note = module.source and (rebuilds and L.VERSION_PARTY_LINES or L.VERSION_NO_PARTY_LINES) or ""
			table.insert(lines, format(L.VERSION_FMT, module.title, version) .. note)
		end
	end
	return lines
end

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
		if peer.session and peer.session ~= "" and peer.session ~= Peers:SessionId() then
			table.insert(parts, "in another party")
		end
		if peer.own then table.insert(parts, "own audio") end
		if peer.plays then table.insert(parts, "plays " .. peer.plays) end
		if peer.modules then table.insert(parts, "runs " .. peer.modules) end
		local differences = self:Differences(key)
		if differences then table.insert(parts, "differs from the leader's: " .. table.concat(differences, "; ")) end
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
	local session = Peers:Session()
	local leader, why = Peers:Leader()
	Add("party: %s", session and format("%s, %d member(s)", session.id, Peers:Count()) or "none")
	Add("leader: %s (%s); voice: %s", Name(leader), tostring(why), Room:Describe(Room:Owner("voice")))
	Add("rules%s: %s", session and " (the leader's)" or " (this computer's, for a party it starts)",
		Peers.DescribeRules(Peers:Rules()))
	Add("this computer: %s, voice here %s%s, plays %s", tostring(PartySync:MyKey()),
		Room:DescribeOwn(Room:OwnValue("voice"), "voice"), Room:IsSilent() and ", captions only" or "", Room:PlaysLetters())
	Add("this computer runs %s (a + rebuilds the party's lines)", self:Modules())
	Add("auto share %s, auto accept %s", OnOff(db.autoShare), OnOff(db.autoAccept))
	local health = Sync.ready and Sync:Health()
	if session and health then Add("last line played together: %s", health == "sync" and "in sync" or health) end

	local members = self:MemberLines()
	if members[1] then
		Add("members:")
		for _, line in ipairs(members) do Add("  %s", line) end
	else
		Add("members: nobody")
	end
	for _, invite in ipairs(Peers:Invitations()) do
		Add("invited: %s (%d s, no answer yet)", invite.name, invite.seconds)
	end
	local Autoform = PartySync.Autoform
	local list = Autoform and Autoform:List()
	if list and next(list.members) then
		Add("usual party%s:", list.leader and format(" (%s leads)", Name(list.leader)) or "")
		for _, key in ipairs(Autoform:Keys()) do
			local entry = list.members[key]
			local peer = Peers.list[key]
			Add("  %s: %s, %s", entry.name or key, entry.autoAccept and "accepted without asking" or "asked each time",
				peer and peer.state or "not heard from")
		end
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
