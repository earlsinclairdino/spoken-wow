-- Addon messages: the only wire an addon has.
--
-- Addons cannot open sockets, so everything between two clients rides
-- C_ChatInfo.SendAddonMessage and arrives as CHAT_MSG_ADDON on the other side. Nothing here
-- shows in chat: an addon whisper opens no whisper tab and prints nothing to either player.
--
-- WHISPER to each member is the main link, not a fallback. It works grouped, ungrouped and in
-- a raid, and it does not send every raid member messages their client has to discard. The
-- group channels are only for reaching players whose names we do not know yet: the hello.
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

local SEP = "\t"
local C = C_ChatInfo

local handlers = {}

-- Not logged one by one: a log being sent is hundreds of these, and a burst test is a test.
local QUIET = { LL = true, BU = true }

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
		SendNow(entry.channel, entry.target, entry.message, entry.kind)
	end
	if backlog[1] and not drainScheduled then
		drainScheduled = true
		C_Timer.After(1, Drain)
	end
end

SendNow = function(channel, target, message, kind)
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
		local detail = message:sub(#kind + 2, #kind + 61):gsub("\t", " ")
		PartySync:Log("-> %s%s %s %s [%s, %s]", channel, target and format(" %q", target) or "",
			kind, detail, answer, Comm:Context())
	end
	if channel == "WHISPER" and not sent and tostring(answer):find("TargetOffline", 1, true) and PartySync.Peers then
		-- Clients from 11.1 on answer TargetOffline up front instead of printing a message.
		PartySync.Peers:MarkOffline(target)
	end
	return sent, answer
end

--- Send `kind` and its fields. Returns whether the client accepted it (or queued it, where
--- the client's allowance is spent), and its answer in words. Accepted is not delivered: only
--- a reply says that.
function Comm:Send(channel, target, kind, ...)
	if not self:Register() then
		return false, "prefix not registered: " .. tostring(self.registerResult)
	end
	local fields = { kind }
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		table.insert(fields, value == nil and "" or tostring(value))
	end
	local message = table.concat(fields, SEP)
	if #message > self.MAX_LENGTH then
		return false, format("message is %d bytes, the limit is %d", #message, self.MAX_LENGTH)
	end
	if Throttled(channel) then
		Refill()
		if backlog[1] or tokens < 1 then
			table.insert(backlog, { channel = channel, target = target, message = message, kind = kind })
			if not drainScheduled then
				drainScheduled = true
				C_Timer.After(1, Drain)
			end
			return true, "queued"
		end
		tokens = tokens - 1
	end
	return SendNow(channel, target, message, kind)
end

function Comm:Whisper(target, kind, ...)
	local to = PartySync:WhisperName(target)
	if not to then
		return false, "no name"
	end
	return self:Send("WHISPER", to, kind, ...)
end

--- To the group, or false when there is none.
function Comm:Broadcast(kind, ...)
	local channel = self:GroupChannel()
	if not channel then
		return false, "not in a group"
	end
	return self:Send(channel, nil, kind, ...)
end

--- How many caption pieces a line may send: unlimited where whispers are, eight inside an
--- instance, where a line's announcement, its text and its start have ten messages between
--- them before the client makes the rest wait a second each.
function Comm:TextBudget()
	return self:InInstance() and 8 or nil
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
	if not QUIET[kind] then
		PartySync:Log("<- %s %q %s %s", channel, sender, kind, (text:sub(#kind + 2, #kind + 61):gsub("\t", " ")))
	end
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(handler, sender, channel, unpack(fields, 2))
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
