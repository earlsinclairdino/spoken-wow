-- The game's own sound channels, by the party's rules: a computer that does not play the music
-- (the effects, the ambience, the NPCs' dialog) has that channel switched off while in the party.
--
-- Only the Sound_Enable switches are touched, never a volume, and the player's value is saved
-- before the first switch, so it comes back exactly: when the party ends or the rule changes, at
-- logout and /reload, and, should the client have stopped with a channel off, at the next login.

local _, PartySync = ...

local Peers = PartySync.Peers

local Channels = {}
PartySync.Channels = Channels

-- The game's name for each channel: its switch is Sound_Enable<name>, and Spoken calls it the same.
local GAME_NAMES = { music = "Music", effects = "SFX", ambience = "Ambience", dialog = "Dialog" }
Channels.CVARS = {}
for channel, name in pairs(GAME_NAMES) do Channels.CVARS[channel] = "Sound_Enable" .. name end

-- channel -> the player's value, while this file has the channel off. Saved with the account,
-- as the switches are.
local function Saved()
	local db = PartySync:DB()
	db.cvarCache = db.cvarCache or {}
	return db.cvarCache
end

-- Spoken switches Dialog off around its own lines and on again after: a channel off for that
-- reason is on as far as the player is concerned.
local function PlayersValue(channel)
	local env = rawget(_G, "SpokenEnv")
	local sound = env and env.SoundUtils
	if sound and sound.IsMutedByPlayer and sound:IsMutedByPlayer(GAME_NAMES[channel]) then
		return "1"
	end
	return tostring(GetCVar(Channels.CVARS[channel]) or "1")
end

function Channels:Restore(channel)
	local saved = Saved()
	local value = saved[channel]
	if value == nil then return end
	saved[channel] = nil
	SetCVar(self.CVARS[channel], value)
	PartySync:Trace("room", "%s back as the player had it (%s)", channel, value)
end

--- Each channel off or back as the rules say. Run on every change and once a second, so a switch
--- turned back on meanwhile, as Spoken's Dialog is after its line, is off again at once.
function Channels:Apply()
	local saved = Saved()
	local inParty = Peers:InParty()
	for channel, cvar in pairs(self.CVARS) do
		if inParty and not PartySync.Room:Plays(channel) then
			if saved[channel] == nil then
				saved[channel] = PlayersValue(channel)
				PartySync:Trace("room", "%s off here, for the party (was %s)", channel, saved[channel])
			end
			if tostring(GetCVar(cvar)) ~= "0" then SetCVar(cvar, 0) end
		elseif saved[channel] ~= nil then
			self:Restore(channel)
		end
	end
end

--- Spoken switches Dialog back on as its queue empties, the moment QUEUE_EMPTY fires: a channel
--- the party keeps off goes off again then, not at the next second.
function Channels:Setup()
	local Spoken = _G.Spoken
	if self.ready or not (Spoken and Spoken.RegisterCallback) then return end
	self.ready = true
	Spoken:RegisterCallback("QUEUE_EMPTY", function() Channels:Apply() end)
end

--- Every channel this file switched off, back: at logout and /reload, before the client saves the
--- switches, and at login after a session that ended without one.
function Channels:RestoreAll()
	for channel in pairs(self.CVARS) do
		self:Restore(channel)
	end
end
