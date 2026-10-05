-- Two computers in one room: one plays the voice, the others show the player and its captions
-- without sound, so the room hears each line once.
--
-- The silent computers use the player's captions-only mode through a session override
-- (Spoken:SetCaptionsOnlyOverride), never through its saved setting: the moment the computer
-- that plays the sound goes offline, the others make sound again, and nobody has to remember
-- to switch anything back.
--
-- Choosing on one computer is enough. Each client says in its hello what it chose, and a
-- client left on "as chosen elsewhere" follows a member that said "this computer" -- or that
-- named it.

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
	local me = PartySync:MyKey()
	local choice = PartySync:DB().roomSpeaker or ""
	if choice == "me" then
		return me
	end
	if choice == "none" then
		return nil
	end
	if choice ~= "" then
		return Online(choice) and choice or nil
	end
	for _, key in ipairs(Peers:OnlineMembers()) do
		local theirs = Peers.list[key].room
		if theirs == "me" then
			return key
		end
		if theirs ~= nil and theirs ~= "" and theirs == me then
			return me
		end
	end
	return nil
end

--- Whether this computer is the silent one right now.
function Room:IsSilent()
	local speaker = self:Speaker()
	return speaker ~= nil and speaker ~= PartySync:MyKey()
end

function Room:Update()
	local Spoken = _G.Spoken
	if not (PartySync:PlayerAvailable() and Spoken.SetCaptionsOnlyOverride) then
		return
	end
	local silent = self:IsSilent()
	if silent ~= applied then
		local was = applied
		PartySync:Trace("room", "captions only here: %s (sound on %s)", tostring(silent), tostring(self:Speaker() or "every computer"))
		-- Set first: the override fires the player's AUDIO_CHANGED, which comes back here.
		applied = silent
		Spoken:SetCaptionsOnlyOverride(silent)
		if silent then
			PartySync:Print("same room: %s plays the sound, this computer shows the captions",
				PartySync:ShortName(Peers:MemberName(self:Speaker())))
		elseif was then
			PartySync:Print("same room: this computer plays the sound again")
		end
	end
end

--- The choices the setting offers: as chosen elsewhere, this computer, every computer, and
--- each member's computer.
function Room:Choices()
	local list = { "", "me", "none" }
	local keys = {}
	for key in Peers:Members() do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do table.insert(list, key) end
	return list
end

function Room:Describe(choice)
	if choice == "" or choice == nil then return L.ROOM_AUTO end
	if choice == "me" then return L.ROOM_ME end
	if choice == "none" then return L.ROOM_NOBODY end
	return format(L.ROOM_MEMBER_FMT, Peers:MemberName(choice))
end

function Room:Set(choice)
	PartySync:DB().roomSpeaker = choice or ""
	Peers:Announce()
	self:Update()
end
