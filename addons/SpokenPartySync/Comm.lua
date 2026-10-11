-- Addon messages: the only wire an addon has.
--
-- Addons cannot open sockets, so everything between two clients rides
-- C_ChatInfo.SendAddonMessage and arrives as CHAT_MSG_ADDON on the other side. Nothing here
-- shows in chat: an addon whisper opens no whisper tab and prints nothing to either player.
--
-- Each message is for one member, by name. A member outside the game's group is whispered. A
-- member in it is sent the message on the group channel, addressed to them (TO below), once
-- their hello says they read that: on 2026-10-11 addon whispers between two players took 110 s
-- each way for a whole evening while the party channel took under a second, and a party whose
-- every answer comes minutes late falls apart. The hello itself is broadcast to the group, for
-- players whose names we do not know yet.
--
--   TO  key, kind, fields   a message for `key` alone; every other client in the group drops it.
--
-- A message is a kind and its fields, tab-separated. The kind is two letters because the
-- whole message, kind included, has to fit in 255 bytes, and a caption chunk wants as many of
-- them as it can get.
--
-- Measured on the Forever beta, 2026-10-05: a whisper round trip takes 0.9 to 1.1 s, half of
-- it the connection and half the server; 30 full-size whispers sent at once outside an
-- instance all arrived, within 189 ms. The client's limit of 10 messages per prefix, refilled
-- at one a second, applies to the group channels and to whispers inside instances, so those
-- are paced here and never refused.

local _, PartySync = ...

local Comm = {}
PartySync.Comm = Comm

-- 15 of the 16 characters a prefix may have.
Comm.PREFIX = "SpokenPartySync"
Comm.MAX_LENGTH = 255
-- What a message's fields may take when the message may be addressed on the group channel: the
-- address goes in front.
Comm.ROOM = Comm.MAX_LENGTH - 48

local SEP = "\t"
local C = C_ChatInfo

local handlers = {}

-- Not logged one by one: a log being sent is hundreds of these, and a burst test is a test.
local QUIET = { LL = true, BU = true }
-- Always whispered. A log is hundreds of lines, which the group channel's allowance would
-- spread over minutes with every line of dialogue queued behind them; its header goes the same
-- way so it arrives first. A burst test measures whispers.
local WHISPERED = { LH = true, LL = true, BU = true, BR = true }
-- What a hello's last field says this version reads.
Comm.CAN = "to"

--- Every API the transport needs, by name, and whether the client has it. For `/sps api`.
function Comm:Probe()
	return {
		{ "C_ChatInfo", C ~= nil },
		{ "SendAddonMessage", C ~= nil and C.SendAddonMessage ~= nil },
		{ "RegisterAddonMessagePrefix", C ~= nil and C.RegisterAddonMessagePrefix ~= nil },
		{ "IsAddonMessagePrefixRegistered", C ~= nil and C.IsAddonMessagePrefixRegistered ~= nil },
		-- Midnight restricts addon messaging inside instances during encounters; Forever runs
		-- on that engine. Present means the restriction exists and can be asked about.
		{ "InChatMessagingLockdown", C ~= nil and C.InChatMessagingLockdown ~= nil },
		{ "Enum.SendAddonMessageResult", Enum ~= nil and Enum.SendAddonMessageResult ~= nil },
		{ "ERR_CHAT_PLAYER_NOT_FOUND_S", type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" },
		{ "chat message filters", (ChatFrame_AddMessageEventFilter
			or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)) ~= nil },
	}
end

function Comm:Available()
	return C ~= nil and C.SendAddonMessage ~= nil and C.RegisterAddonMessagePrefix ~= nil
end

--- A client's answer, in words. Older clients return a boolean, newer ones an Enum value,
--- and some return nothing at all.
local function Describe(enum, result)
	if result == nil then
		return "no result"
	end
	if type(result) == "boolean" then
		return result and "ok" or "refused"
	end
	if type(result) == "number" and enum then
		for name, value in pairs(enum) do
			if value == result then
				return format("%s (%d)", name, result)
			end
		end
	end
	return tostring(result)
end

local function Succeeded(result)
	-- nil counts: a client that does not say has not said no.
	return result == nil or result == true or result == 0
end

function Comm:Register()
	if self.registered then
		return self.registered, self.registerResult
	end
	if not self:Available() then
		self.registered, self.registerResult = false, "C_ChatInfo is missing"
		return self.registered, self.registerResult
	end
	local result = C.RegisterAddonMessagePrefix(self.PREFIX)
	self.registerResult = Describe(Enum and Enum.RegisterAddonMessagePrefixResult, result)
	self.registered = Succeeded(result)
	-- Registering twice answers DuplicatePrefix, which still leaves the prefix registered.
	if not self.registered and C.IsAddonMessagePrefixRegistered then
		self.registered = C.IsAddonMessagePrefixRegistered(self.PREFIX) and true or false
	end
	return self.registered, self.registerResult
end

--- `handler(sender, channel, ...fields)`, for messages of `kind`.
function Comm:On(kind, handler)
	handlers[kind] = handler
end

--- What the client is doing that could stop a message: in combat, in an instance, in
--- messaging lockdown. Logged with every send, so a failure in a dungeon says why.
function Comm:Context()
	local parts = {}
	if InCombatLockdown and InCombatLockdown() then
		table.insert(parts, "in combat")
	end
	if IsInInstance then
		local inInstance, instanceType = IsInInstance()
		if inInstance then
			table.insert(parts, "in " .. tostring(instanceType))
		end
	end
	if C and C.InChatMessagingLockdown then
		local ok, locked = pcall(C.InChatMessagingLockdown)
		if ok and locked then
			table.insert(parts, "messaging lockdown")
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or "open world"
end

function Comm:InInstance()
	return IsInInstance ~= nil and (IsInInstance()) and true or false
end

--- The group channel a broadcast goes out on, or nil when not grouped.
function Comm:GroupChannel()
	local home = LE_PARTY_CATEGORY_HOME
	if IsInRaid and IsInRaid(home) then
		return "RAID"
	end
	if IsInGroup and IsInGroup(home) then
		return "PARTY"
	end
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	end
	return nil
end

--------------------------------------------------------------------------------
-- Text in fields
--------------------------------------------------------------------------------
--
-- Fields are tab-separated, and a caption has line breaks; a pipe starts an escape sequence
-- the client may reject. So free text is escaped on the way out and back on the way in.

local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r", ["|"] = "\\p" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n", r = "\r", p = "|" }

function Comm.Escape(text)
	return (tostring(text or ""):gsub("[\\\t\n\r|]", ESCAPES))
end

function Comm.Unescape(text)
	return (tostring(text or ""):gsub("\\(.)", UNESCAPES))
end

--- `text`, escaped and cut into pieces of at most `size` bytes. Escaping comes first and the
--- pieces are joined before unescaping, so a cut through an escape or a UTF-8 character is
--- harmless.
function Comm.Chunk(text, size)
	local escaped = Comm.Escape(text)
	local chunks = {}
	for start = 1, #escaped, size do
		table.insert(chunks, escaped:sub(start, start + size - 1))
	end
	if #chunks == 0 then chunks[1] = "" end
	return chunks
end

--------------------------------------------------------------------------------
-- Sending
--------------------------------------------------------------------------------

-- The client's allowance where it applies: ten at once, one more each second.
local BUCKET_SIZE = 10
local tokens, refilledAt = BUCKET_SIZE, nil
local backlog = {}
local drainScheduled = false

local function Throttled(channel)
	return channel ~= "WHISPER" or Comm:InInstance()
end

local function Refill()
	local now = GetTime()
	refilledAt = refilledAt or now
	tokens = math.min(BUCKET_SIZE, tokens + (now - refilledAt))
	refilledAt = now
end

local SendNow

local function Drain()
	drainScheduled = false
	Refill()
	while backlog[1] and tokens >= 1 do
		local entry = table.remove(backlog, 1)
		tokens = tokens - 1
		SendNow(entry)
	end
	if backlog[1] and not drainScheduled then
		drainScheduled = true
		C_Timer.After(1, Drain)
	end
end

-- `entry`: the channel, the whisper's target, the message as sent and its kind. A message
-- addressed on the group channel also has `to`, who it is for, and `body`, itself without the
-- address, so the log reads the same either way.
SendNow = function(entry)
	local channel, target, message, kind = entry.channel, entry.target, entry.message, entry.kind
	-- pcall, because a restricted send can raise rather than return: a line in a dungeon
	-- should fail to sync, not stop the addon.
	local ok, result = pcall(C.SendAddonMessage, Comm.PREFIX, message, channel, target)
	local answer = ok and Describe(Enum and Enum.SendAddonMessageResult, result)
		or ("error: " .. tostring(result))
	local sent = ok and Succeeded(result)
	if channel == "WHISPER" and sent then
		Comm:WatchWhisper(target)
	end
	if not QUIET[kind] then
		-- The fields after the kind say which line a message was about; cut, they stay readable.
		local body = entry.body or message
		local detail = body:sub(#kind + 2, #kind + 61):gsub("\t", " ")
		local address = entry.to and format(" to %s", entry.to) or (target and format(" %q", target) or "")
		PartySync:Log("-> %s%s %s %s [%s, %s]", channel, address, kind, detail, answer, Comm:Context())
	end
	if channel == "WHISPER" and not sent and tostring(answer):find("TargetOffline", 1, true) and PartySync.Peers then
		-- Clients from 11.1 on answer TargetOffline up front instead of printing a message.
		PartySync.Peers:MarkOffline(target)
	end
	return sent, answer
end

local function Pack(kind, ...)
	local fields = { kind }
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		table.insert(fields, value == nil and "" or tostring(value))
	end
	return table.concat(fields, SEP)
end

local function Deliver(entry)
	if not Comm:Register() then
		return false, "prefix not registered: " .. tostring(Comm.registerResult)
	end
	if #entry.message > Comm.MAX_LENGTH then
		return false, format("message is %d bytes, the limit is %d", #entry.message, Comm.MAX_LENGTH)
	end
	if Throttled(entry.channel) then
		Refill()
		if backlog[1] or tokens < 1 then
			table.insert(backlog, entry)
			if not drainScheduled then
				drainScheduled = true
				C_Timer.After(1, Drain)
			end
			return true, "queued"
		end
		tokens = tokens - 1
	end
	return SendNow(entry)
end

--- Send `kind` and its fields. Returns whether the client accepted it (or queued it, where
--- the client's allowance is spent), and its answer in words. Accepted is not delivered: only
--- a reply says that.
function Comm:Send(channel, target, kind, ...)
	return Deliver({ channel = channel, target = target, kind = kind, message = Pack(kind, ...) })
end

--- Whether the group channel reaches `name`: in this character's group, and online.
function Comm:InGroup(name)
	local unit = self:GroupChannel() and PartySync:UnitFor(name)
	if not unit then
		return false
	end
	return not UnitIsConnected or (UnitIsConnected(unit) and true or false)
end

--- Whether `name` is sent its messages on the group channel: in the group, and running a
--- version whose hello says it reads them there.
function Comm:Addressable(name)
	local peer = PartySync.Peers and PartySync.Peers:Get(name)
	local can = peer and peer.can
	if not (can and ("," .. can .. ","):find("," .. self.CAN .. ",", 1, true)) then
		return false
	end
	return self:InGroup(name)
end

-- `body` addressed to `address` (a key, or "*" for the sender's whole party) on the group
-- channel, or nil when the address leaves it no room.
local function Addressed(address, kind, body, to)
	local wire = Pack("TO", address) .. SEP .. body
	if #wire > Comm.MAX_LENGTH then
		return nil
	end
	return { channel = Comm:GroupChannel(), kind = kind, message = wire, to = to, body = body }
end

--- `kind` to the player `target`: addressed on the group channel where that reaches them,
--- whispered otherwise.
function Comm:Whisper(target, kind, ...)
	local to = PartySync:WhisperName(target)
	if not to then
		return false, "no name"
	end
	local body = Pack(kind, ...)
	local entry = not WHISPERED[kind] and self:Addressable(to) and Addressed(PartySync:NameKey(to), kind, body, format("%q", to))
	return Deliver(entry or { channel = "WHISPER", target = to, kind = kind, message = body })
end

--- `kind` to each of `names`, members of this character's party: one message on the group
--- channel for all those it reaches, since the client lets a group channel carry one message
--- a second once ten have gone, and a whisper to each of the others.
function Comm:WhisperEach(names, kind, ...)
	local grouped, rest = {}, {}
	for _, name in ipairs(names) do
		if not WHISPERED[kind] and self:Addressable(name) then
			table.insert(grouped, name)
		else
			table.insert(rest, name)
		end
	end
	if #grouped > 1 then
		local entry = Addressed("*", kind, Pack(kind, ...), "the party")
		if entry then
			Deliver(entry)
			grouped = {}
		end
	end
	for _, name in ipairs(grouped) do self:Whisper(name, kind, ...) end
	for _, name in ipairs(rest) do self:Whisper(name, kind, ...) end
end

--- To the group, or false when there is none.
function Comm:Broadcast(kind, ...)
	local channel = self:GroupChannel()
	if not channel then
		return false, "not in a group"
	end
	return self:Send(channel, nil, kind, ...)
end

--- Answer the message being handled the way it came: by whisper, addressed, or to the group.
--- A ping's answer has to, for `/sps latency` to time each way on its own.
function Comm:Answer(sender, kind, ...)
	local road = self.road
	if road == "WHISPER" then
		return self:Send("WHISPER", PartySync:WhisperName(sender), kind, ...)
	elseif road == "TO" or not road then
		return self:Whisper(sender, kind, ...)
	end
	return self:Send(road, nil, kind, ...)
end

--- How many caption pieces a line may send: unlimited where whispers are, eight in a group
--- (where it goes on the group channel) or inside an instance (where whispers are paced too),
--- since a line's announcement, its text and its start have ten messages between them before
--- the client makes the rest wait a second each.
function Comm:TextBudget()
	return (self:InInstance() or self:GroupChannel()) and 8 or nil
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function Split(text)
	local fields, start = {}, 1
	while true do
		local stop = text:find(SEP, start, true)
		if not stop then
			table.insert(fields, text:sub(start))
			return fields
		end
		table.insert(fields, text:sub(start, stop - 1))
		start = stop + 1
	end
end

-- Whether a message addressed to `address` on the group channel is for this character.
local function ForMe(address, sender)
	if address == "*" then
		return PartySync.Peers ~= nil and PartySync.Peers:IsMember(sender)
	end
	return address == PartySync:MyKey()
end

--- CHAT_MSG_ADDON, from Events.lua.
function Comm:Receive(prefix, text, channel, sender)
	if prefix ~= self.PREFIX or not text or not sender then
		return
	end
	-- A group broadcast comes back to its sender too.
	if PartySync:IsSelf(sender) then
		return
	end
	local fields = Split(text)
	local kind = fields[1]
	local road, label = channel, channel
	if kind == "TO" then
		-- Another member's, in this group: dropped unread.
		if not ForMe(fields[2], sender) then
			return
		end
		text = text:sub(#fields[1] + #fields[2] + 3)
		table.remove(fields, 1)
		table.remove(fields, 1)
		kind = fields[1] or ""
		-- Handled as a whisper: the handlers ask only whether a message was for this
		-- character, not which road it took.
		road, label, channel = "TO", channel .. " to me", "WHISPER"
	end
	if not QUIET[kind] then
		PartySync:Log("<- %s %q %s %s", label, sender, kind, (text:sub(#kind + 2, #kind + 61):gsub("\t", " ")))
	end
	local handler = handlers[kind]
	if handler then
		self.road = road
		local ok, err = pcall(handler, sender, channel, unpack(fields, 2))
		self.road = nil
		if not ok then
			PartySync:Print("|cffff6060error handling %s from %s: %s|r", tostring(kind), tostring(sender), tostring(err))
		end
	end
	-- An unknown kind is a newer version talking; ignoring it is how the two stay compatible.
end

--------------------------------------------------------------------------------
-- "No player named X is currently playing."
--------------------------------------------------------------------------------
--
-- What the client prints when a whisper finds nobody, addon whispers included (2026-10-05).
-- It is the fastest way to learn a member is offline, so for a few seconds after each whisper
-- the system messages are read for it -- and kept out of the chat window, since the whisper
-- was the addon's, not the player's.

local WATCH_SECONDS = 3
local watching = {}
local notFoundPattern

local function NotFoundPattern()
	if notFoundPattern == nil then
		local text = ERR_CHAT_PLAYER_NOT_FOUND_S
		if type(text) == "string" then
			local escaped = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
			notFoundPattern = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
		else
			notFoundPattern = false
		end
	end
	return notFoundPattern
end

function Comm:WatchWhisper(target)
	local key = PartySync:NameKey(target)
	if key then
		watching[key] = GetTime() + WATCH_SECONDS
	end
end

--- The name in a "No player named" message about a player whispered in the last few seconds.
--- `consume` forgets the watch, so the message is acted on once.
function Comm:NotFoundName(text, consume)
	local pattern = NotFoundPattern()
	if not pattern or type(text) ~= "string" then
		return nil
	end
	local name = text:match(pattern)
	if not name then
		return nil
	end
	local key = PartySync:NameKey(name)
	local deadline = key and watching[key]
	if deadline and GetTime() <= deadline then
		if consume then watching[key] = nil end
		return name
	end
	return nil
end

--- CHAT_MSG_SYSTEM, from Events.lua. The watch is left to run out rather than consumed: the
--- chat window's filter below reads the same message, before or after this, and must still
--- recognise it.
function Comm:ReadSystemMessage(text)
	return self:NotFoundName(text, false)
end

--- Keep the client's "No player named" out of the chat window when the whisper was ours.
--- A probe shows them: there, which forms fail is the point.
function Comm:FilterChat()
	-- The global on most clients; newer ones keep it on ChatFrameUtil.
	local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if self.filtering or not AddFilter then
		return
	end
	self.filtering = true
	AddFilter("CHAT_MSG_SYSTEM", function(_, _, text, ...)
		if PartySync.Peers and PartySync.Peers:IsProbing() then
			return false
		end
		if Comm:NotFoundName(text, false) then
			return true
		end
		return false, text, ...
	end)
end
