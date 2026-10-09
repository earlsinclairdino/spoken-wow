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

Channels.CVARS = { music = "Sound_EnableMusic", effects = "Sound_EnableSFX", ambience = "Sound_EnableAmbience",
	dialog = "Sound_EnableDialog" }
-- Spoken's names for the same channels, to ask whether it has one off for a line of its own.
local SPOKEN_NAMES = { music = "Music", effects = "SFX", ambience = "Ambience", dialog = "Dialog" }

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
	if sound and sound.IsMutedByPlayer and sound:IsMutedByPlayer(SPOKEN_NAMES[channel]) then
		return "1"
	end
	return tostring(GetCVar(Channels.CVARS[channel]) or "1")
end

--- Whether this file has `channel` off.
function Channels:IsOff(channel)
	return Saved()[channel] ~= nil
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
--- turned back on meanwhile -- Spoken's Dialog, after its line -- is off again at once.
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

--- Every channel this file switched off, back: at logout and /reload, before the client saves the
--- switches, and at login after a session that ended without one.
function Channels:RestoreAll()
	for channel in pairs(self.CVARS) do
		self:Restore(channel)
	end
end
