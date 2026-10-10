-- Computers in one room: each kind of sound is played by one of them, or by all but some, so the
-- room hears it once.
--
-- Each channel's owner is one of the party's rules, the leader's to set: "none" (every
-- computer), a member's key (that computer alone, or every computer while it is offline), or
-- "-<key>,<key>" (every computer but those). The voice alone may be "trigger": the computer that
-- triggered a line plays it, the others show its captions (Sync marks their copy of the clip
-- captions only); the game's channels have no trigger. A computer may decide a channel for
-- itself instead (Play My Own Sound): "" (as the party decides), "plays" or "muted". The voice
-- is Spoken's lines: a computer that does not play it shows them as captions, through the
-- player's session override (Spoken:SetCaptionsOnlyOverride), never its saved setting, so the
-- sound comes back the moment the party or the owner goes. The game's own channels are switched
-- in Channels.lua.
--
-- The voice's rule and own choice live in `rules.room` and `soundOwn` ("sound"/"captions"),
-- where the PS message and saved settings carry them.

local _, PartySync = ...

local Peers, L = PartySync.Peers, PartySync.L

local Room = {}
PartySync.Room = Room

Room.CHANNELS = PartySync.CHANNELS
-- Each channel's letter in a hello's list of what a computer plays, its name and what it is.
local INFO = {
	voice = { "v", L.CHANNEL_VOICE, L.CHANNEL_VOICE_TIP },
	music = { "m", L.CHANNEL_MUSIC, L.CHANNEL_MUSIC_TIP },
	effects = { "e", L.CHANNEL_EFFECTS, L.CHANNEL_EFFECTS_TIP },
	ambience = { "a", L.CHANNEL_AMBIENCE, L.CHANNEL_AMBIENCE_TIP },
	dialog = { "d", L.CHANNEL_DIALOG, L.CHANNEL_DIALOG_TIP },
}
local FROM_VOICE = { sound = "plays", captions = "muted" }
local TO_VOICE = { plays = "sound", muted = "captions" }

local applied = nil

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
	return INFO[channel] and INFO[channel][2] or tostring(channel)
end

function Room:Tip(channel)
	return INFO[channel] and INFO[channel][3]
end

--- The party's rule for `channel`: "none", a member's key, or "-<key>,<key>".
function Room:Owner(channel)
	local rules = Peers:Rules()
	if channel == "voice" then return rules.room or "none" end
	return rules.audio and rules.audio[channel] or "none"
end

--- `read(channel)` for every channel of `list` when they all agree, else "mixed".
local function Same(read, list)
	list = list or Room.CHANNELS
	local first = read(list[1])
	for _, channel in ipairs(list) do
		if read(channel) ~= first then return "mixed" end
	end
	return first
end

--- Whether the voice goes to whoever triggers a line.
function Room:Triggered()
	return self:Owner("voice") == "trigger"
end

--- One owner for every channel, or "mixed". The voice on its trigger is set apart: the summary
--- is then the game's channels'.
function Room:Summary()
	return Same(function(channel) return self:Owner(channel) end, self:Triggered() and PartySync.GAME_CHANNELS or nil)
end

local function RulePlays(channel, key, me)
	if not Peers:InParty() then return true end
	local owner = Room:Owner(channel)
	if owner == "none" or owner == "trigger" then return true end
	local excluded = Excluded(owner)
	if excluded then return not excluded[key] end
	if owner == key then return true end
	-- The owner gone, every computer plays again.
	return owner ~= me and not Online(owner)
end

--- This computer's own choice for `channel`: "" (as the party decides), "plays" or "muted".
function Room:OwnValue(channel)
	local db = PartySync:DB()
	if channel == "voice" then
		local own = db.soundOwn or ""
		return FROM_VOICE[own] or own
	end
	return db.audioOwn and db.audioOwn[channel] or ""
end

--- Whether `key`'s computer (this one without a key) plays `channel`: this one by its own
--- choice or the rule, another by what its hello said, or by the rule where it said nothing.
function Room:Plays(channel, key)
	local me = PartySync:MyKey()
	key = key or me
	if key == me then
		local own = self:OwnValue(channel)
		if own ~= "" then return own == "plays" end
		return RulePlays(channel, key, me)
	end
	local peer = Peers.list[key]
	if peer and peer.plays then
		return peer.plays:find(INFO[channel][1], 1, true) ~= nil
	end
	return RulePlays(channel, key, me)
end

--- What this computer plays, as a hello carries it: a letter a channel, "-" for none.
function Room:PlaysLetters()
	local letters = {}
	for _, channel in ipairs(self.CHANNELS) do
		if self:Plays(channel) then table.insert(letters, INFO[channel][1]) end
	end
	return letters[1] and table.concat(letters) or "-"
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

--- Whether `key`'s computer decides a channel by itself, as far as this one knows.
function Room:Decides(key)
	if key == PartySync:MyKey() then return self:IsOwn() end
	local peer = Peers.list[key]
	return peer ~= nil and peer.own == true
end

--- Whether `key`'s computer is one that plays the voice where not every computer does: what the
--- "voice" beside a name says.
function Room:Voices(key)
	local owner = self:Owner("voice")
	return owner ~= "none" and owner ~= "trigger" and self:Plays("voice", key)
end

--- Whether a line another computer drives is captions only here: the voice goes to its trigger
--- and this computer has not decided its voice for itself.
function Room:CaptionsHere()
	return self:Triggered() and self:OwnValue("voice") == ""
end

--- Keep the player, the game's channels and the party in step with the rules: called on every
--- change, cheap when nothing moved.
function Room:Update()
	if PartySync.Channels then PartySync.Channels:Apply() end
	Peers:AnnounceIfChanged()
	local Spoken = _G.Spoken
	if not (PartySync:PlayerAvailable() and Spoken.SetCaptionsOnlyOverride) then
		return
	end
	local silent = self:IsSilent()
	if silent ~= applied then
		local was = applied
		local voiceHere = self:OwnValue("voice") ~= ""
		PartySync:Trace("room", "captions only here: %s (voice on %s%s)", tostring(silent),
			self:Describe(self:Owner("voice")), voiceHere and ", decided here" or "")
		-- Set first: the override fires the player's AUDIO_CHANGED, which comes back here.
		applied = silent
		Spoken:SetCaptionsOnlyOverride(silent)
		if silent then
			PartySync:Print("same room: %s, this computer shows the captions", voiceHere
				and "captions only here by choice" or format("%s plays the voice", self:Describe(self:Owner("voice"))))
		elseif was then
			PartySync:Print("same room: this computer plays the voice again")
		end
	end
end

--- The owners a channel's rule offers: every computer, whoever triggers it for the voice, then
--- each member's, this one first, and `current` where it is one the list would not offer
--- ("mixed", every computer but some).
function Room:Choices(current, channel)
	local list = { "none" }
	if channel == "voice" then table.insert(list, "trigger") end
	for _, key in ipairs(Peers:MemberKeys()) do table.insert(list, key) end
	local me = PartySync:MyKey()
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
	if owner == "trigger" then return L.ROOM_TRIGGER end
	local excluded = Excluded(owner)
	if excluded then return format(L.ROOM_ALL_BUT_FMT, Names(excluded)) end
	if owner == PartySync:MyKey() or owner == "me" then return L.ROOM_ME end
	return format(L.ROOM_MEMBER_FMT, Peers:MemberName(owner))
end

--- The same, as short as a chip allows: "Lala", "All but Lala".
function Room:Short(owner)
	local excluded = Excluded(owner)
	if excluded then return format(L.ROOM_ALL_BUT_SHORT_FMT, Names(excluded, true)) end
	if owner == "trigger" then return L.ROOM_TRIGGER_SHORT end
	if owner and owner ~= "none" and owner ~= "mixed" and owner ~= "me" and owner ~= "" and owner ~= PartySync:MyKey() then
		return PartySync:FirstName(Peers:MemberName(owner))
	end
	return self:Describe(owner)
end

local function Normal(owner)
	if owner == nil or owner == "" then return "none" end
	if owner == "me" then return PartySync:MyKey() end
	return owner
end

--- Who plays `channel`, a rule for the party: the leader's to set; outside a party, this
--- computer's own for the next.
function Room:Set(channel, owner)
	owner = Normal(owner)
	if owner == "trigger" and channel ~= "voice" then return false, L.TRIGGER_VOICE_ONLY end
	return Peers:SetRule("audio", channel, owner)
end

--- Who plays the voice.
function Room:Choose(choice)
	return self:Set("voice", choice)
end

--- The voice to whoever triggers a line, or back to every computer.
function Room:SetTriggered(on)
	return self:Set("voice", on and "trigger" or "none")
end

--- Every channel on one owner.
function Room:SetAll(owner)
	owner = Normal(owner)
	if owner == "trigger" then return false, L.TRIGGER_VOICE_ONLY end
	return Peers:EditRules(function(rules)
		rules.room = owner
		rules.audio = rules.audio or {}
		for _, channel in ipairs(PartySync.GAME_CHANNELS) do rules.audio[channel] = owner end
		PartySync:TraceSetting("all sound", owner)
	end)
end

--- Whether Exclude would take `key`'s computer off `channel` and change nothing else: the rule is
--- every computer, or every computer but some, and does not leave it out already.
function Room:CanExclude(channel, key)
	local owner = self:Owner(channel)
	if owner == "none" then return true end
	local excluded = Excluded(owner)
	return excluded ~= nil and not excluded[key]
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

--- What this computer may choose for a channel by itself.
function Room:OwnChoices()
	return { "", "plays", "muted" }
end

local OWN_WORDS = { [""] = L.SOUND_OWN_PARTY, plays = L.OWN_PLAYS, muted = L.OWN_MUTED, mixed = L.MIXED }
local VOICE_WORDS = { plays = L.SOUND_OWN_SOUND, muted = L.SOUND_OWN_CAPTIONS }

function Room:DescribeOwn(value, channel)
	value = value or ""
	return (channel == "voice" and VOICE_WORDS[value]) or OWN_WORDS[value] or tostring(value)
end

local FOLLOW_WORDS = { [""] = L.FOLLOW_YES, plays = L.FOLLOW_PLAYS, muted = L.FOLLOW_MUTED, mixed = L.FOLLOW_PARTLY }

--- Whether this computer follows the party, in answer to "Follow the Party": an own summary.
function Room:DescribeFollow(summary)
	return FOLLOW_WORDS[summary or ""] or tostring(summary)
end

--- This computer's own choice for every channel, when it is the same, else "mixed".
function Room:OwnSummary()
	return Same(function(channel) return self:OwnValue(channel) end)
end

local function StoreOwn(channel, value)
	local db = PartySync:DB()
	if channel == "voice" then
		db.soundOwn = TO_VOICE[value] or value
	else
		db.audioOwn = db.audioOwn or {}
		db.audioOwn[channel] = value
	end
end

--- This computer's own choice for `channel`: "" (as the party decides), "plays" or "muted".
function Room:SetOwnChannel(channel, value)
	value = FROM_VOICE[value] or value or ""
	StoreOwn(channel, value)
	PartySync:TraceSetting(channel .. " here", value ~= "" and value or "as the party decides")
	PartySync:Changed()
end

--- This computer's voice, in its saved words: "", "sound" or "captions".
function Room:SetOwn(value)
	self:SetOwnChannel("voice", value)
end

--- Every channel's own choice at once.
function Room:SetOwnAll(value)
	value = value or ""
	for _, channel in ipairs(self.CHANNELS) do StoreOwn(channel, value) end
	PartySync:TraceSetting("all sound here", value ~= "" and value or "as the party decides")
	PartySync:Changed()
end
