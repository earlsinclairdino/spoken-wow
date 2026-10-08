-- Two computers in one room: one plays the voice, the others show the player and its captions
-- without sound, so the room hears each line once.
--
-- Which computer is one of the party's rules, the leader's to set. The silent computers use
-- the player's captions-only mode through a session override (Spoken:SetCaptionsOnlyOverride),
-- never through its saved setting: the moment the computer that plays the sound goes offline,
-- or the party ends, the others make sound again, and nobody has to remember to switch
-- anything back. A member may decide its own sound instead, with This Computer's Sound.

local _, PartySync = ...

local Peers, L = PartySync.Peers, PartySync.L

local Room = {}
PartySync.Room = Room

local applied = nil

local function Online(key)
	local peer = Peers.list[key]
	return peer ~= nil and peer.state == "online" and Peers:IsMember(key)
end

--- The key of the computer that plays the sound, or nil when every computer does.
function Room:Speaker()
	local session = Peers:Session()
	if not session then
		return nil
	end
	local me = PartySync:MyKey()
	local choice = session.rules.room or "none"
	if choice == "none" then
		return nil
	end
	if choice == me then
		return me
	end
	return Online(choice) and choice or nil
end

--- Whether this computer is the silent one right now: by its own choice, or the party's.
function Room:IsSilent()
	local own = PartySync:DB().soundOwn
	if own == "captions" then
		return true
	end
	if own == "sound" then
		return false
	end
	local speaker = self:Speaker()
	return speaker ~= nil and speaker ~= PartySync:MyKey()
end

--- Whether this computer decides its sound by itself rather than with the party.
function Room:IsOwn()
	local own = PartySync:DB().soundOwn
	return own ~= nil and own ~= ""
end

function Room:Update()
	local Spoken = _G.Spoken
	if not (PartySync:PlayerAvailable() and Spoken.SetCaptionsOnlyOverride) then
		return
	end
	local silent = self:IsSilent()
	if silent ~= applied then
		local was = applied
		PartySync:Trace("room", "captions only here: %s (sound on %s%s)", tostring(silent),
			tostring(self:Speaker() or "every computer"), self:IsOwn() and ", decided here" or "")
		-- Set first: the override fires the player's AUDIO_CHANGED, which comes back here.
		applied = silent
		Spoken:SetCaptionsOnlyOverride(silent)
		if silent then
			PartySync:Print("same room: %s, this computer shows the captions", self:IsOwn() and "captions only here by choice"
				or format("%s plays the sound", PartySync:ShortName(Peers:MemberName(self:Speaker()))))
		elseif was then
			PartySync:Print("same room: this computer plays the sound again")
		end
	end
end

--- The choices the rule offers: every computer, then each member's, this one first.
function Room:Choices()
	local list = { "none" }
	for _, key in ipairs(Peers:MemberKeys()) do table.insert(list, key) end
	local me = PartySync:MyKey()
	if not Peers:InParty() and me then table.insert(list, me) end
	return list
end

function Room:Describe(choice)
	if choice == "none" or choice == nil or choice == "" then return L.ROOM_NOBODY end
	if choice == PartySync:MyKey() or choice == "me" then return L.ROOM_ME end
	return format(L.ROOM_MEMBER_FMT, Peers:MemberName(choice))
end

--- Which computer plays the sound, as a rule for the party: "none", or a member's key ("me"
--- for this one). The leader's to set; outside a party, this computer's own for the next.
function Room:Choose(choice)
	choice = choice or "none"
	if choice == "me" then choice = PartySync:MyKey() end
	if choice == "" then choice = "none" end
	local ok, why = Peers:SetRule("room", choice)
	if ok then self:Update() end
	return ok, why
end

local OWN_WORDS = { [""] = L.SOUND_OWN_PARTY, sound = L.SOUND_OWN_SOUND, captions = L.SOUND_OWN_CAPTIONS }

function Room:DescribeOwn(value)
	return OWN_WORDS[value or ""] or tostring(value)
end

--- This computer's sound, its own choice: "" (as the party decides), "sound" or "captions".
function Room:SetOwn(value)
	value = value or ""
	PartySync:DB().soundOwn = value
	PartySync:TraceSetting("sound here", value ~= "" and value or "as the party decides")
	Peers:Announce()
	self:Update()
end
