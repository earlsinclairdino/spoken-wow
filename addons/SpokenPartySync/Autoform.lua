-- The usual party (the auto-form list): who this character forms a party with as soon as they
-- are online, who led it, and the rules it had.
--
-- While a listed character is not in the party, it is whispered a hello every heartbeat (the
-- client's "No player named" stays hidden). When one answers from no party: with a party
-- already running, its leader invites them; with none, the list's saved leader, if online, else
-- the first by name among those online, invites the others, with the saved rules. Two members
-- of a list inviting each other at once is settled in Peers: the lower name's party wins.
--
-- Being added to someone's list is told: `RM` asks the other side whether to accept that
-- character's invitations without the popup, and puts them on its own list either way.
--
--   RM                      "I added you to my usual party"

local _, PartySync = ...

local Comm, Peers, L = PartySync.Comm, PartySync.Peers, PartySync.L

local Autoform = {}
PartySync.Autoform = Autoform

-- How long an invitation from the list is left unanswered before another is sent.
local INVITE_RETRY = 90
local POPUP = "SPOKENPARTYSYNC_REMEMBERED"

local invitedAt = {}

function Autoform:List()
	return PartySync:Party().list
end

--- The entry for `name` (or a key), or nil.
function Autoform:Entry(name)
	local key = PartySync:NameKey(name)
	return key and self:List().members[key] or nil
end

function Autoform:Keys()
	local keys = {}
	for key in pairs(self:List().members) do table.insert(keys, key) end
	table.sort(keys)
	return keys
end

--- Whether `name`'s invitations are accepted without asking.
function Autoform:Accepts(name)
	local entry = self:Entry(name)
	return entry ~= nil and entry.autoAccept == true
end

--- Put `name` on the list. New to it, they are told. Returns whether they are on it, and
--- whether they were new.
function Autoform:Add(name, autoAccept)
	name = PartySync:CleanName(name)
	local key = PartySync:NameKey(name)
	if not key or PartySync:IsSelf(name) then
		return false
	end
	local members = self:List().members
	local isNew = members[key] == nil
	if isNew then
		members[key] = { name = PartySync:WhisperName(name), autoAccept = autoAccept ~= false, added = time and time() or 0 }
		PartySync:Trace("party", "%s added to the usual party%s", key, members[key].autoAccept and "" or ", asked each time")
		Comm:Whisper(name, "RM")
	elseif autoAccept ~= nil then
		members[key].autoAccept = autoAccept and true or false
	end
	PartySync:Changed()
	return true, isNew
end

function Autoform:Remove(name)
	local key = PartySync:NameKey(name)
	local members = self:List().members
	if not (key and members[key]) then
		return false
	end
	members[key] = nil
	if self:List().leader == key then self:List().leader = nil end
	PartySync:Trace("party", "%s removed from the usual party", key)
	PartySync:Changed()
	return true
end

function Autoform:SetAutoAccept(name, on)
	local entry = self:Entry(name)
	if not entry then return false end
	entry.autoAccept = on and true or false
	PartySync:Trace("party", "%s's invitations: %s", PartySync:NameKey(name), on and "accepted without asking" or "asked each time")
	PartySync:Changed()
	return true
end

--- The party as it stands, into the list: its members, its leader and its rules. Returns how
--- many members were new to the list, or nil without a party.
function Autoform:Remember()
	local session = Peers:Session()
	if not session then
		return nil
	end
	local added = 0
	for key, name in Peers:Members() do
		local _, isNew = self:Add(name, nil)
		if isNew then added = added + 1 end
	end
	local list = self:List()
	list.leader = session.leader
	list.rules = PartySync.Copy(session.rules)
	PartySync:Trace("party", "usual party remembers the party: %s leads, %d new; %s", session.leader, added,
		Peers.DescribeRules(list.rules))
	PartySync:Changed()
	return added
end

--- Whether everyone in this character's party is in its usual party already.
function Autoform:Remembered()
	if not Peers:InParty() then
		return false
	end
	local members = self:List().members
	for key in Peers:Members() do
		if not members[key] then
			return false
		end
	end
	return true
end

--- The party changed: remembered, where the setting says so.
function Autoform:AutoRemember()
	if PartySync:DB().remember and Peers:Count() >= 2 then
		self:Remember()
	end
end

--------------------------------------------------------------------------------
-- Forming
--------------------------------------------------------------------------------

local function InParty(peer)
	return peer.session ~= nil and peer.session ~= ""
end

--- The listed characters online and in no party, by key.
local function Free()
	local free = {}
	for _, key in ipairs(Autoform:Keys()) do
		local peer = Peers.list[key]
		if peer and peer.state == "online" and not InParty(peer) and not Peers:IsMember(key) then
			table.insert(free, key)
		end
	end
	return free
end

local function InviteOnce(key)
	local at = invitedAt[key]
	if at and GetTime() - at < INVITE_RETRY then
		return
	end
	invitedAt[key] = GetTime()
	local list = Autoform:List()
	local sent, answer = Peers:Invite(list.members[key].name, list.rules)
	PartySync:Trace("party", "usual party invites %s: %s", key, sent and "sent" or tostring(answer))
end

--- Invite whoever on the list is online and free, when it is this character's to do.
function Autoform:Form()
	local free = Free()
	if not free[1] then
		return
	end
	local me = PartySync:MyKey()
	local session = Peers:Session()
	if session then
		if session.leader == me then
			for _, key in ipairs(free) do InviteOnce(key) end
		end
		return
	end
	-- No party yet: the saved leader forms it, if here, else the first by name.
	local list = self:List()
	local keys = { me }
	for _, key in ipairs(free) do table.insert(keys, key) end
	table.sort(keys)
	local former = keys[1]
	if list.leader == me or (list.leader and list.members[list.leader] and Peers.list[list.leader]
		and Peers.list[list.leader].state == "online" and not InParty(Peers.list[list.leader])) then
		former = list.leader
	end
	if former ~= me then
		return
	end
	for _, key in ipairs(free) do InviteOnce(key) end
end

--- Each heartbeat: greet the listed characters not in the party, and form it with those who
--- answered.
function Autoform:Tick()
	local list = self:List()
	if next(list.members) == nil then
		return
	end
	for key, entry in pairs(list.members) do
		if not Peers:IsMember(key) then
			local peer = Peers.list[key]
			if not (peer and peer.state == "online") then
				Peers:Greet(entry.name)
			end
		end
	end
	self:Form()
end

--------------------------------------------------------------------------------
-- Being remembered
--------------------------------------------------------------------------------

local function DefinePopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then
		return
	end
	StaticPopupDialogs[POPUP] = {
		text = L.REMEMBERED_POPUP,
		button1 = L.REMEMBERED_YES,
		button2 = L.REMEMBERED_NO,
		OnAccept = function(_, data) Autoform:Add(data, true) end,
		OnCancel = function(_, data, reason)
			if reason == "clicked" then Autoform:Add(data, false) end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

Comm:On("RM", function(sender)
	Peers:Seen(sender)
	if Autoform:Entry(sender) then
		return
	end
	PartySync:Trace("party", "%s added this character to their usual party", PartySync:NameKey(sender))
	DefinePopup()
	if StaticPopup_Show then
		StaticPopup_Show(POPUP, PartySync:ShortName(sender), nil, PartySync:WhisperName(sender))
	end
end)

function Autoform:Setup()
	DefinePopup()
end
