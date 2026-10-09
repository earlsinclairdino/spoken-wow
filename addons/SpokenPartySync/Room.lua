-- Computers in one room: each kind of sound is played by one of them, or by all but some, so the
-- room hears it once.
--
-- Each channel's owner is one of the party's rules, the leader's to set: "none" (every
-- computer), a member's key (that computer alone, or every computer while it is offline), or
-- "-<key>,<key>" (every computer but those). A computer may decide a channel for itself instead
-- (This Computer). The voice is Spoken's lines: a computer that does not play it shows them as
-- captions, through the player's session override (Spoken:SetCaptionsOnlyOverride), never its
-- saved setting, so the sound comes back the moment the party or the owner goes. The game's own
-- channels are switched in Channels.lua.

local _, PartySync = ...

local Peers, L = PartySync.Peers, PartySync.L

local Room = {}
PartySync.Room = Room

Room.CHANNELS = { "voice", "music", "effects", "ambience", "dialog" }
-- Each channel's letter in a hello's list of what a computer plays.
local LETTERS = { voice = "v", music = "m", effects = "e", ambience = "a", dialog = "d" }
local NAMES = { voice = L.CHANNEL_VOICE, music = L.CHANNEL_MUSIC, effects = L.CHANNEL_EFFECTS,
	ambience = L.CHANNEL_AMBIENCE, dialog = L.CHANNEL_DIALOG }
local TIPS = { voice = L.CHANNEL_VOICE_TIP, music = L.CHANNEL_MUSIC_TIP, effects = L.CHANNEL_EFFECTS_TIP,
	ambience = L.CHANNEL_AMBIENCE_TIP, dialog = L.CHANNEL_DIALOG_TIP }
-- This computer's own choice: the voice keeps the words it always had, the others play or not.
local OWN_ON = { sound = true, plays = true }
local OWN_OFF = { captions = true, muted = true }

local applied = nil
local announced = nil

local function Me()
	return PartySync:MyKey()
end

local function Online(key)
	local peer = Peers.list[key]
	return peer ~= nil and peer.state == "online" and Peers:IsMember(key)
end

local function Excluded(owner)
	if type(owner) ~= "string" or owner:sub(1, 1) ~= "-" then return nil end
	local keys = {}
	for key in owner:sub(2):gmatch("[^,]+") do keys[key] = true end
	return keys
end

function Room:Name(channel)
	return NAMES[channel] or tostring(channel)
end

function Room:Tip(channel)
	return TIPS[channel]
end

--- The party's rule for `channel`: "none", a member's key, or "-<key>,<key>".
function Room:Owner(channel)
	local rules = Peers:Rules()
	if channel == "voice" then return rules.room or "none" end
	return rules.audio and rules.audio[channel] or "none"
end

--- One owner for every channel, or "mixed".
function Room:Summary()
	local first = self:Owner("voice")
	for _, channel in ipairs(self.CHANNELS) do
		if self:Owner(channel) ~= first then return "mixed" end
	end
	return first
end

local function RulePlays(channel, key)
	if not Peers:InParty() then return true end
	local owner = Room:Owner(channel)
	if owner == "none" then return true end
	local excluded = Excluded(owner)
	if excluded then return not excluded[key] end
	if owner == key then return true end
	-- The owner gone, every computer plays again.
	return owner ~= Me() and not Online(owner)
end

function Room:OwnValue(channel)
	local db = PartySync:DB()
	if channel == "voice" then return db.soundOwn or "" end
	return db.audioOwn and db.audioOwn[channel] or ""
end

--- Whether `key`'s computer (this one without a key) plays `channel`: this one by its own
--- choice or the rule, another by what its hello said, or by the rule where it said nothing.
function Room:Plays(channel, key)
	key = key or Me()
	if key == Me() then
		local own = self:OwnValue(channel)
		if OWN_ON[own] then return true end
		if OWN_OFF[own] then return false end
		return RulePlays(channel, key)
	end
	local peer = Peers.list[key]
	if peer and peer.plays then
		return peer.plays:find(LETTERS[channel], 1, true) ~= nil
	end
	return RulePlays(channel, key)
end

--- What this computer plays, as a hello carries it: a letter a channel, "-" for none.
function Room:PlaysLetters()
	local letters = {}
	for _, channel in ipairs(self.CHANNELS) do
		if self:Plays(channel) then table.insert(letters, LETTERS[channel]) end
	end
	return letters[1] and table.concat(letters) or "-"
end

--- The one computer that plays the voice, or nil when more than one does.
function Room:Speaker()
	if not Peers:InParty() then return nil end
	local owner = self:Owner("voice")
	if owner == "none" or Excluded(owner) then return nil end
	if owner == Me() then return owner end
	return Online(owner) and owner or nil
end

--- Whether this computer shows the voice as captions only right now.
function Room:IsSilent()
	return not self:Plays("voice")
end

--- Whether this computer decides any channel by itself rather than with the party.
function Room:IsOwn()
	for _, channel in ipairs(self.CHANNELS) do
		if self:OwnValue(channel) ~= "" then return true end
	end
	return false
end

--- Keep the player, the game's channels and the party in step with the rules: called on every
--- change, cheap when nothing moved.
function Room:Update()
	if PartySync.Channels then PartySync.Channels:Apply() end
	-- What the others read in this computer's hello: told when it changes.
	local hello = (self:IsOwn() and "1" or "0") .. self:PlaysLetters()
	if announced ~= nil and hello ~= announced and Peers:InParty() then
		announced = hello
		Peers:Announce()
	end
	announced = hello
	local Spoken = _G.Spoken
	if not (PartySync:PlayerAvailable() and Spoken.SetCaptionsOnlyOverride) then
		return
	end
	local silent = self:IsSilent()
	if silent ~= applied then
		local was = applied
		PartySync:Trace("room", "captions only here: %s (voice on %s%s)", tostring(silent),
			self:Describe(self:Owner("voice")), self:OwnValue("voice") ~= "" and ", decided here" or "")
		-- Set first: the override fires the player's AUDIO_CHANGED, which comes back here.
		applied = silent
		Spoken:SetCaptionsOnlyOverride(silent)
		if silent then
			PartySync:Print("same room: %s, this computer shows the captions", self:OwnValue("voice") ~= ""
				and "captions only here by choice" or format("%s plays the voice", self:Describe(self:Owner("voice"))))
		elseif was then
			PartySync:Print("same room: this computer plays the voice again")
		end
	end
end

--- The owners a channel's rule offers: every computer, then each member's, this one first, and
--- `current` where it is one the list would not offer ("mixed", every computer but some).
function Room:Choices(current)
	local list = { "none" }
	for _, key in ipairs(Peers:MemberKeys()) do table.insert(list, key) end
	local me = Me()
	if not Peers:InParty() and me then table.insert(list, me) end
	if current == "mixed" or Excluded(current) then table.insert(list, current) end
	return list
end

local function Names(keys, short)
	local names = {}
	for key in pairs(keys) do
		local name = Peers:MemberName(key)
		table.insert(names, short and PartySync:FirstName(name) or PartySync:ShortName(name))
	end
	table.sort(names)
	return table.concat(names, ", ")
end

function Room:Describe(owner)
	if owner == nil or owner == "" or owner == "none" then return L.ROOM_NOBODY end
	if owner == "mixed" then return L.MIXED end
	local excluded = Excluded(owner)
	if excluded then return format(L.ROOM_ALL_BUT_FMT, Names(excluded)) end
	if owner == Me() or owner == "me" then return L.ROOM_ME end
	return format(L.ROOM_MEMBER_FMT, Peers:MemberName(owner))
end

--- The same, as short as a chip allows: "Lala", "All but Lala".
function Room:Short(owner)
	local excluded = Excluded(owner)
	if excluded then return format(L.ROOM_ALL_BUT_SHORT_FMT, Names(excluded, true)) end
	if owner and owner ~= "none" and owner ~= "mixed" and owner ~= "me" and owner ~= "" and owner ~= Me() then
		return PartySync:FirstName(Peers:MemberName(owner))
	end
	return self:Describe(owner)
end

local function Normal(owner)
	if owner == nil or owner == "" then return "none" end
	if owner == "me" then return Me() end
	return owner
end

--- Who plays `channel`, a rule for the party: the leader's to set; outside a party, this
--- computer's own for the next.
function Room:Set(channel, owner)
	if owner == "mixed" then return true end
	return Peers:SetRule("audio", channel, Normal(owner))
end

--- Who plays the voice.
function Room:Choose(choice)
	return self:Set("voice", choice)
end

--- Every channel on one owner.
function Room:SetAll(owner)
	if owner == "mixed" then return true end
	owner = Normal(owner)
	return Peers:EditRules(function(rules)
		rules.room = owner
		rules.audio = rules.audio or {}
		for _, channel in ipairs(self.CHANNELS) do
			if channel ~= "voice" then rules.audio[channel] = owner end
		end
		PartySync:TraceSetting("all sound", owner)
	end)
end

--- Take `key`'s computer off `channel`: every computer but it, and but any already left out.
function Room:Exclude(channel, key)
	local excluded = Excluded(self:Owner(channel)) or {}
	excluded[key] = true
	local keys = {}
	for each in pairs(excluded) do table.insert(keys, each) end
	table.sort(keys)
	return self:Set(channel, "-" .. table.concat(keys, ","))
end

local OWN_WORDS = { [""] = L.SOUND_OWN_PARTY, sound = L.SOUND_OWN_SOUND, captions = L.SOUND_OWN_CAPTIONS,
	plays = L.OWN_PLAYS, muted = L.OWN_MUTED, mixed = L.MIXED }

function Room:DescribeOwn(value)
	return OWN_WORDS[value or ""] or tostring(value)
end

--- What this computer may choose for `channel` by itself.
function Room:OwnChoices(channel)
	if channel == "voice" then return { "", "sound", "captions" } end
	return { "", "plays", "muted" }
end

-- The words "all sound" uses for the voice's own choice.
local AS_ALL = { sound = "plays", captions = "muted" }
local AS_VOICE = { plays = "sound", muted = "captions" }

--- This computer's own choice for every channel, when it is the same, else "mixed".
function Room:OwnSummary()
	local first = AS_ALL[self:OwnValue("voice")] or self:OwnValue("voice")
	for _, channel in ipairs(self.CHANNELS) do
		local value = self:OwnValue(channel)
		if (AS_ALL[value] or value) ~= first then return "mixed" end
	end
	return first
end

--- This computer's own choice for `channel`: "" (as the party decides); for the voice "sound"
--- or "captions", for the others "plays" or "muted".
function Room:SetOwnChannel(channel, value)
	value = value or ""
	local db = PartySync:DB()
	if channel == "voice" then
		db.soundOwn = value
	else
		db.audioOwn = db.audioOwn or {}
		db.audioOwn[channel] = value
	end
	PartySync:TraceSetting(channel .. " here", value ~= "" and value or "as the party decides")
	PartySync:Changed()
end

--- This computer's voice: "" (as the party decides), "sound" or "captions".
function Room:SetOwn(value)
	self:SetOwnChannel("voice", value)
end

--- Every channel's own choice at once: "", "plays" or "muted".
function Room:SetOwnAll(value)
	if value == "mixed" then return end
	local db = PartySync:DB()
	for _, channel in ipairs(self.CHANNELS) do
		if channel == "voice" then
			db.soundOwn = AS_VOICE[value] or value or ""
		else
			db.audioOwn = db.audioOwn or {}
			db.audioOwn[channel] = value or ""
		end
	end
	PartySync:TraceSetting("all sound here", value ~= "" and value or "as the party decides")
	PartySync:Changed()
end
