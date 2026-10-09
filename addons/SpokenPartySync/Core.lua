-- SpokenPartySync -- plays Spoken's lines together for players who quest together.
--
-- The case it exists for: two players in one room, both running Spoken. Whoever talks to the
-- NPC, the line should start on both screens at once, skip on both at once, and be heard from
-- one speaker, with the captions on every screen. A quest line only one of them could trigger
-- -- a class quest, a progress text -- plays for both.
--
-- How it fits together:
--   Names.lua   who is who: Forever's two-part names, and how to address a whisper.
--   Comm.lua    addon messages, the only wire there is.
--   Peers.lua   the party: its members, who is online, how far away, who leads, invites.
--   Lines.lua   a line as a description another client can rebuild, and the rebuild.
--   Sync.lua    the engine: announce, hold, start together, acknowledge, skip, stop and replay.
--   Accept.lua  quests shared and accepted for the party.
--   Room.lua    two computers in one room: one plays the voice, the others show captions.
--   UI/         the settings page, the sync window and the portrait menu.
--
-- Everything goes through Spoken's public API (Spoken:GetSource, a source's rebuild, gates,
-- callbacks); the modules' internals are never read.

local ADDON_NAME, PartySync = ...

-- Reachable from /dump, for finding out in game why something did not sync.
_G.SpokenPartySync = PartySync

-- C_AddOns is the modern home of GetAddOnMetadata; the global is the older one.
local GetAddOnMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

PartySync.name = ADDON_NAME
PartySync.version = GetAddOnMeta and GetAddOnMeta(ADDON_NAME, "Version") or "dev"

-- The Spoken player API version this was written against.
local REQUIRED_API = 1

-- Below this the window's 10-pixel words cannot be read.
local MIN_WINDOW_SCALE = 0.9
PartySync.MIN_WINDOW_SCALE = MIN_WINDOW_SCALE

-- A middle dot between the parts of one line, as the game's own tooltips join them.
PartySync.DOT = " \194\183 "

-- The kinds of sound a party shares out: Spoken's voice, then the game's own channels.
PartySync.CHANNELS = { "voice", "music", "effects", "ambience", "dialog" }
PartySync.GAME_CHANNELS = { "music", "effects", "ambience", "dialog" }

local function PerGameChannel(value)
	local each = {}
	for _, channel in ipairs(PartySync.GAME_CHANNELS) do each[channel] = value end
	return each
end

-- This computer's settings, the same for every character on the account.
local function Rules()
	return {
		-- Whose Stop, Replay, Skip and Stop All act on every computer: "anyone", "leader" or
		-- "nobody" (the lines play through; nobody stops them, the leader included).
		controls = "anyone",
		-- Which computer plays the voice: "none" (every computer), a member's NameKey, or
		-- "-<key>,<key>" (every computer but those).
		room = "none",
		-- Who plays each of the game's own channels, in the same words.
		audio = PerGameChannel("none"),
		-- Whose accepted quests are shared with the party: "anyone", "leader" or "nobody".
		share = "anyone",
		-- Which kinds of line are played together. Each one off still plays here, alone.
		sync = { quests = true, gossip = true, zones = true, books = true },
	}
end
PartySync.Rules = Rules

local function Defaults()
	return {
		-- The rules a party started here begins with; in a party they are the leader's to set.
		rules = Rules(),
		autoShare = true,
		autoAccept = true,
		-- "" follows the party's rule for the voice; "sound" and "captions" decide it here.
		soundOwn = "",
		-- The same for the game's channels: "", "plays" or "muted".
		audioOwn = PerGameChannel(""),
		window = { show = "problems", scale = 1, compact = false },
	}
end
PartySync.Defaults = Defaults

-- The character's, saved per character: the others know this character by its name, so another
-- character on this computer is in no party until it is invited.
local function PartyDefaults()
	return {
		-- The party this character is in, or nil: { id, leader (a NameKey), members (NameKey ->
		-- name, this character included), rules }. It lasts until fewer than two are left, and
		-- a /reload rejoins it.
		session = nil,
		-- Who to form a party with as soon as they are online: NameKey -> { name, autoAccept,
		-- added }, who led it and the rules it had.
		list = { members = {}, leader = nil, rules = nil },
		-- The last party, once ended: who was in it, for a re-invite to ask them back.
		lastSession = nil,
		-- Sets of people ("key;key") whose party was not to be remembered: never offered again.
		declined = {},
	}
end

local function Fill(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		elseif type(value) == "table" and type(target[key]) == "table" then
			Fill(target[key], value)
		end
	end
end

local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in pairs(value) do copy[key] = Copy(item) end
	return copy
end
PartySync.Copy = Copy

--- The 0.3 party, kept by name as a list of members, lead and sound choices: it becomes the
--- usual party, with the choices as the rules it starts a party with.
local function MigrateMembers(db, party, me)
	if type(party.members) ~= "table" then return end
	for key, member in pairs(party.members) do
		if not party.list.members[key] then
			party.list.members[key] = { name = member.name, autoAccept = true, added = member.added }
		end
	end
	local lead = party.lead
	if type(lead) == "string" and party.list.members[lead] then
		party.list.leader = lead
	end
	local room = party.roomSpeaker
	if room == "me" then room = me end
	if type(room) == "string" and (room == "none" or room == me or party.list.members[room]) then
		party.list.rules = party.list.rules or Rules()
		party.list.rules.room = room
	end
	if type(db.controls) == "string" then
		db.rules = db.rules or Rules()
		db.rules.controls = db.controls
	end
	if type(db.sync) == "table" then
		db.rules = db.rules or Rules()
		db.rules.sync = db.sync
	end
	party.members, party.lead, party.roomSpeaker = nil, nil, nil
	db.controls, db.sync = nil, nil
end

function PartySync:InitDB()
	SpokenPartySyncDB = SpokenPartySyncDB or {}
	SpokenPartySyncCharDB = SpokenPartySyncCharDB or {}
	local db, party = SpokenPartySyncDB, SpokenPartySyncCharDB
	-- Up to 0.3.0 the party was kept with the account, so whichever character logged in spoke
	-- for it and the members refused it. The first character to log in since keeps that party.
	if type(db.members) == "table" and (type(party.members) ~= "table" or next(party.members) == nil) then
		party.members, party.lead, party.roomSpeaker = db.members, db.lead, db.roomSpeaker
	end
	db.members, db.lead, db.roomSpeaker = nil, nil, nil
	Fill(party, PartyDefaults())
	-- 0.1.0 kept one companion by name, sometimes with the quotes it was typed with. Saved
	-- variables do come back on Forever, so it outlived that version: it becomes a member.
	if type(db.companion) == "string" then
		local name = self:CleanName(db.companion)
		if name ~= "" and not self:IsSelf(name) then
			party.members = party.members or {}
			party.members[self:NameKey(name)] = { name = name, added = time and time() or 0 }
		end
		db.companion = nil
	end
	MigrateMembers(db, party, self:MyKey())
	Fill(db, Defaults())
	if db.windowShown ~= nil then
		if db.windowShown then db.window.show = "always" end
		db.windowShown = nil
	end
	db.window.scale = math.max(tonumber(db.window.scale) or 1, MIN_WINDOW_SCALE)
	-- No longer read: a party is offered to remember as it ends.
	db.remember = nil
	-- A session saved by a /reload: rejoined once the others answer (Peers:Resume).
	local session = party.session
	if session and not (type(session.id) == "string" and type(session.leader) == "string"
		and type(session.members) == "table") then
		party.session = nil
	end
	return db
end

--- Everything back to its defaults but the party, the usual party and the collected logs.
function PartySync:ResetOptions()
	local db = SpokenPartySyncDB
	if not db then return end
	local collected, cvarCache = db.collected, db.cvarCache
	-- Where the window was dragged to is not a setting on the page.
	local point = db.window and db.window.point
	for key in pairs(db) do db[key] = nil end
	Fill(db, Defaults())
	db.collected, db.cvarCache = collected, cvarCache
	db.window.point = point
	if self.SetWindowScale then self:SetWindowScale(db.window.scale) end
	self:Changed()
end

local fallback = Defaults()
function PartySync:DB()
	return SpokenPartySyncDB or fallback
end

local partyFallback = PartyDefaults()
--- This character's: its party (session) and its usual party (the list).
function PartySync:Party()
	return SpokenPartySyncCharDB or partyFallback
end

function PartySync:Print(message, ...)
	local text = select("#", ...) > 0 and format(message, ...) or message
	DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSpoken Party Sync|r: " .. text)
end

--- One line in Spoken's debug log, under `category`, while it is on. Formatted here: Spoken:Log
--- takes four arguments at most, and some lines here have more.
function PartySync:Trace(category, message, ...)
	local Spoken = _G.Spoken
	if not (Spoken and Spoken.Log and Spoken:IsLogOn()) then return end
	local text = message
	if select("#", ...) > 0 then
		local ok, formatted = pcall(format, message, ...)
		text = ok and formatted or tostring(message)
	end
	Spoken:Log(category, text)
end

--- A setting changed on the page, in the debug log: what the party does depends on them.
function PartySync:TraceSetting(name, value)
	self:Trace("party", "setting %s: %s", name, tostring(value))
end

function PartySync:SetAutoShare(on)
	self:DB().autoShare = on and true or false
	self:TraceSetting("auto share", self:DB().autoShare)
	self:Changed()
end

--- A message in or out, in the debug log.
function PartySync:Log(message, ...)
	self:Trace("msg", message, ...)
end

function PartySync:PlayerAvailable()
	return _G.Spoken ~= nil and Spoken.IsCompatible ~= nil and Spoken:IsCompatible(REQUIRED_API)
end

--- Something the window, the room and the settings show has changed: who is online, who
--- leads, a line's state. Cheap; each listener redraws from scratch.
function PartySync:Changed()
	if self.Peers and self.Peers.CheckLeader then self.Peers:CheckLeader() end
	if self.Room and self.Room.Update then self.Room:Update() end
	if self.RefreshWindow then self:RefreshWindow() end
	if self.RefreshOptions then self:RefreshOptions() end
end

--------------------------------------------------------------------------------
-- Problems: what the window lists until it is no longer true
--------------------------------------------------------------------------------

local PROBLEM_SECONDS = 30
PartySync.problems = {}

--- Say something went wrong, once per `key`: a member not answering, a missing file. Kept for
--- half a minute, or until Resolve(key). `about`, for the window to offer its fix: { kind =
--- "silent" (a member not answering) or "missing" (no voice file), who = the member's key }.
function PartySync:Problem(key, text, about)
	local now = GetTime()
	about = about or {}
	for _, problem in ipairs(self.problems) do
		if problem.key == key then
			problem.text, problem.at, problem.kind, problem.who = text, now, about.kind, about.who
			self:Changed()
			return
		end
	end
	table.insert(self.problems, { key = key, text = text, at = now, kind = about.kind, who = about.who })
	self:Trace("problem", "%s", text)
	self:Changed()
end

function PartySync:Resolve(key)
	for i = #self.problems, 1, -1 do
		if self.problems[i].key == key then
			table.remove(self.problems, i)
			self:Changed()
		end
	end
end

--- The problems still worth showing, newest first.
function PartySync:Problems()
	local now, list = GetTime(), {}
	for i = #self.problems, 1, -1 do
		local problem = self.problems[i]
		if now - problem.at > PROBLEM_SECONDS then
			table.remove(self.problems, i)
		else
			table.insert(list, problem)
		end
	end
	return list
end
