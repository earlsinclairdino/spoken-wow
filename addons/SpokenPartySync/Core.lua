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
--   Sync.lua    the engine: announce, hold, start together, acknowledge, skip and pause.
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

local function Defaults()
	return {
		-- NameKey -> { name, added }. Whoever is in here plays lines with this character; anyone
		-- else running the addon is told about at most once. Kept by name, not by group: the
		-- players this is for are always the same characters, and a name survives leaving the
		-- group, joining a raid, or not grouping at all.
		members = {},
		-- "auto" (whoever leads the group, else the first name), "me", or "follow" (never me).
		lead = "auto",
		-- Which kinds of line are played together. Each one off still plays here, alone.
		sync = { quests = true, gossip = true, zones = true, books = true },
		autoShare = true,
		autoAccept = true,
		-- Whose Pause, Skip and Stop act everywhere: "leader", "anyone" or "nobody".
		controls = "leader",
		-- Two computers in one room: "" follows what the others chose, "me" plays the sound here,
		-- "none" plays it everywhere, a member's NameKey plays it there and only captions here.
		roomSpeaker = "",
		window = { show = "problems", scale = 1 },
		-- Every message in and out, in chat. For finding out why something did not arrive.
		logTraffic = false,
	}
end
PartySync.Defaults = Defaults

local function Fill(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		elseif type(value) == "table" and type(target[key]) == "table" then
			Fill(target[key], value)
		end
	end
end

function PartySync:InitDB()
	SpokenPartySyncDB = SpokenPartySyncDB or {}
	local db = SpokenPartySyncDB
	Fill(db, Defaults())
	-- 0.1.0 kept one companion by name, sometimes with the quotes it was typed with. Saved
	-- variables do come back on Forever, so it outlived that version: it becomes a member.
	if type(db.companion) == "string" then
		local name = self:CleanName(db.companion)
		if name ~= "" and not self:IsSelf(name) then
			db.members[self:NameKey(name)] = { name = name, added = time and time() or 0 }
		end
		db.companion = nil
	end
	if db.windowShown ~= nil then
		if db.windowShown then db.window.show = "always" end
		db.windowShown = nil
	end
	return db
end

--- Everything back to its defaults but the party itself.
function PartySync:ResetOptions()
	local db = SpokenPartySyncDB
	if not db then return end
	local members, log, collected = db.members, db.log, db.collected
	for key in pairs(db) do db[key] = nil end
	Fill(db, Defaults())
	db.members, db.log, db.collected = members or {}, log, collected
	self:Changed()
end

local fallback = Defaults()
function PartySync:DB()
	return SpokenPartySyncDB or fallback
end

function PartySync:Print(message, ...)
	local text = select("#", ...) > 0 and format(message, ...) or message
	DEFAULT_CHAT_FRAME:AddMessage("|cff80c0ffSpoken Party Sync|r: " .. text)
end

--- One line in the debug log (Log.lua), under `category`.
function PartySync:Trace(category, message, ...)
	if self.LogBook then
		self.LogBook:Add(category, message, ...)
	end
end

--- A message in or out: always in the debug log, and in chat while traffic logging is on.
function PartySync:Log(message, ...)
	self:Trace("msg", message, ...)
	if self:DB().logTraffic then
		self:Print("|cff999999" .. message .. "|r", ...)
	end
end

function PartySync:PlayerAvailable()
	return _G.Spoken ~= nil and Spoken.IsCompatible ~= nil and Spoken:IsCompatible(REQUIRED_API)
end

--- Something the window, the room and the settings show has changed: who is online, who
--- leads, a line's state. Cheap; each listener redraws from scratch.
function PartySync:Changed()
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
--- half a minute, or until Resolve(key).
function PartySync:Problem(key, text)
	local now = GetTime()
	for _, problem in ipairs(self.problems) do
		if problem.key == key then
			problem.text, problem.at = text, now
			self:Changed()
			return
		end
	end
	table.insert(self.problems, { key = key, text = text, at = now })
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
