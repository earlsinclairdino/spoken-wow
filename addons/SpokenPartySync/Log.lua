-- The party's debug logs. Each client's log is Spoken's own (Spoken > Developer, `/spoken log`),
-- which Party Sync writes its steps and every message into (PartySync:Trace); this file adds
-- what takes a party: finding out afterwards why two computers disagreed about a line means
-- reading both logs on one timeline. Without the Spoken Developer module, Spoken has no log and
-- Party Sync keeps none: nothing is written, the commands say so, and a member asking gets no
-- lines.
--
-- Any member can ask the others for theirs (`/sps logs pull`): each sends its last lines back,
-- paced, with its own clock reading, and the asker keeps them in SpokenPartySyncDB.collected
-- with the offset that maps that clock onto its own. They are handed to Spoken as a log source,
-- so Spoken's box (`/sps logs`, `/spoken log`) shows them merged with this client's.
--
--   LQ  token, count                    ask for the last `count` lines
--   LH  token, total, now, version, on  the answer's header: how many lines follow, the
--                                       sender's GetTime() as it sent this, its addon version,
--                                       and whether its log is on ("1") or off ("0")
--   LL  token, seq, line                one line, escaped
--   LC                                  clear your log: a new session starts for the whole party
--   LK                                  cleared

local _, PartySync = ...

local Comm, Peers = PartySync.Comm, PartySync.Peers

local LogBook = {}
PartySync.LogBook = LogBook

-- How many lines a member sends when asked, unless the asker says otherwise.
local DEFAULT_PULL = 400
-- At most what Spoken keeps.
local MAX_PULL = 2000
-- One message line at most this long once escaped, so it fits a message with its header.
local LINE_BYTES = 220
-- A whole log arrives over a few seconds: this many messages, then a pause.
local PACE_BATCH, PACE_SECONDS = 8, 0.5
local PULL_TIMEOUT = 120

--- Spoken, where it has the debug log: the Spoken Developer module installed (Spoken:HasLog).
--- Without it, or with a Spoken too old to ask, there is nothing to write into.
local function Spoken()
	local api = _G.Spoken
	return api and api.HasLog and api:HasLog() and api or nil
end

function LogBook:Available()
	return Spoken() ~= nil
end

function LogBook:IsOn()
	local api = Spoken()
	return api ~= nil and api:IsLogOn()
end

--------------------------------------------------------------------------------
-- Clearing, for the whole party
--------------------------------------------------------------------------------

--- Clear this log, and with it the logs collected here (the source's clear), starting it
--- again with a session line that says why.
function LogBook:Clear(how)
	local api = Spoken()
	if api then
		api:ClearLog(how)
	else
		PartySync:DB().collected = {}
	end
end

--- Clear this log and ask every member online to clear theirs: one new session for everyone.
--- Returns how many members were asked.
function LogBook:ClearParty()
	self:Clear("cleared, with the party's")
	local members = Peers:OnlineMembers()
	for _, key in ipairs(members) do
		Comm:Whisper(Peers:MemberName(key), "LC")
	end
	return #members
end

Comm:On("LC", function(sender)
	-- Only the party: a stranger has no business emptying anyone's log.
	if not Peers:IsMember(sender) then return end
	LogBook:Clear(format("cleared at %s's request", PartySync:ShortName(sender)))
	PartySync:Print("%s cleared the Party Sync debug logs: a new session starts", PartySync:ShortName(sender))
	Comm:Whisper(sender, "LK")
end)

Comm:On("LK", function(sender)
	if not Peers:IsMember(sender) then return end
	PartySync:Trace("logs", "%s cleared their log", PartySync:ShortName(sender))
	PartySync:Print("%s's debug log is cleared", PartySync:ShortName(sender))
end)

--------------------------------------------------------------------------------
-- Pulling the others' logs
--------------------------------------------------------------------------------

local counter = 0
local pulls = {}   -- token -> { key, name, sentAt, total, lines, offset, version, on }

local function Collected()
	local db = PartySync:DB()
	db.collected = db.collected or {}
	return db.collected
end

--- Ask every member online for their last `count` lines.
function LogBook:Pull(count)
	count = math.max(1, math.min(MAX_PULL, tonumber(count) or DEFAULT_PULL))
	local members = Peers:OnlineMembers()
	if not members[1] then
		PartySync:Print("nobody in your Spoken party is online to send a log")
		return 0
	end
	for _, key in ipairs(members) do
		counter = counter + 1
		local token = format("%d-%d", math.floor(GetTime() * 1000) % 1000000, counter)
		pulls[token] = { key = key, name = Peers:MemberName(key), sentAt = GetTime(), lines = {} }
		Comm:Whisper(Peers:MemberName(key), "LQ", token, count)
		C_Timer.After(PULL_TIMEOUT, function()
			local pull = pulls[token]
			if pull then
				pulls[token] = nil
				LogBook:Keep(pull, true)
			end
		end)
	end
	PartySync:Trace("logs", "asked %d member(s) for %d lines", #members, count)
	PartySync:Print("asked %d member%s for their log; it takes a few seconds", #members, #members == 1 and "" or "s")
	if not self:IsOn() then
		PartySync:Print("your own debug log is off: turn it on in Spoken > Developer, or with /spoken log on")
	end
	return #members
end

--- A pulled log, complete or given up on, kept with the offset onto this client's clock.
function LogBook:Keep(pull, timedOut)
	local received = 0
	local lines = {}
	for i = 1, pull.total or 0 do
		if pull.lines[i] then
			received = received + 1
			lines[#lines + 1] = pull.lines[i]
		end
	end
	Collected()[pull.key] = {
		name = pull.name,
		at = date and date("%Y-%m-%d %H:%M:%S") or "?",
		-- Their GetTime() plus this is ours: their clock read as they sent the header, ours when
		-- it arrived, less half a round trip for the way here.
		offset = pull.offset,
		version = pull.version,
		lines = lines,
		missing = (pull.total or 0) - received,
	}
	PartySync:Trace("logs", "%s's log: %d of %s lines%s, offset %s s%s", pull.name, received, tostring(pull.total),
		timedOut and " (gave up waiting)" or "", pull.offset and format("%.3f", pull.offset) or "?",
		pull.on == false and ", their log is off" or "")
	PartySync:Print("%s's log: %d line%s%s. /sps logs shows them with yours", PartySync:ShortName(pull.name), received,
		received == 1 and "" or "s", timedOut and format(", %d never arrived", (pull.total or 0) - received) or "")
	if pull.on == false then
		PartySync:Print("%s's debug log is off: they can turn it on in Spoken > Developer", PartySync:ShortName(pull.name))
	end
end

Comm:On("LQ", function(sender, channel, token, count)
	-- Only to the party: a log names the characters played with and what was said.
	if not Peers:IsMember(sender) then return end
	PartySync:Trace("logs", "%s asked for %s lines", PartySync:ShortName(sender), tostring(count))
	local api = Spoken()
	local log = api and api:LogLines() or {}
	count = math.max(1, math.min(#log, tonumber(count) or DEFAULT_PULL))
	local first = #log - count + 1
	local lines = {}
	for i = math.max(1, first), #log do
		local escaped = Comm.Escape(log[i])
		if #escaped > LINE_BYTES then escaped = escaped:sub(1, LINE_BYTES):gsub("\\$", "") end
		lines[#lines + 1] = escaped
	end
	Comm:Whisper(sender, "LH", token, #lines, format("%.3f", GetTime()), PartySync.version,
		LogBook:IsOn() and "1" or "0")
	-- Paced: a whisper burst of 30 arrived intact on the beta, but a whole log is hundreds.
	local seq = 0
	local function Batch()
		for _ = 1, PACE_BATCH do
			seq = seq + 1
			if seq > #lines then return end
			Comm:Whisper(sender, "LL", token, seq, lines[seq])
		end
		C_Timer.After(PACE_SECONDS, Batch)
	end
	Batch()
end)

Comm:On("LH", function(sender, channel, token, total, now, version, on)
	local pull = token and pulls[token]
	if not pull then return end
	pull.total = tonumber(total) or 0
	pull.version = version
	-- Absent from a version before the log moved into Spoken, whose log was always on.
	pull.on = on ~= "0"
	local theirs = tonumber(now)
	if theirs then
		local rtt = Peers:Rtt(pull.key) / 1000
		pull.offset = (GetTime() - rtt / 2) - theirs
	end
	if pull.total == 0 then
		pulls[token] = nil
		LogBook:Keep(pull)
	end
end)

Comm:On("LL", function(sender, channel, token, seq, line)
	local pull = token and pulls[token]
	seq = tonumber(seq)
	if not (pull and seq) then return end
	pull.lines[seq] = Comm.Unescape(line or "")
	if pull.total then
		for i = 1, pull.total do
			if not pull.lines[i] then return end
		end
		pulls[token] = nil
		LogBook:Keep(pull)
	end
end)

--------------------------------------------------------------------------------
-- Read beside this client's, in Spoken's box
--------------------------------------------------------------------------------

--- The collected logs, as Spoken's AddLogSource takes them.
function LogBook:Sources()
	local list = {}
	for _, log in pairs(Collected()) do
		list[#list + 1] = { name = log.name, lines = log.lines or {}, offset = log.offset or 0 }
	end
	table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
	return list
end

--- This client's log and the collected ones, merged by Spoken, in its box. Returns how many
--- lines it shows, or nil where Spoken has no log.
function LogBook:Show(count)
	local api = Spoken()
	return api and api:ShowLog(count) or nil
end

function LogBook:Setup()
	-- The log Party Sync kept itself, before Spoken had one: nothing reads it any more.
	PartySync:DB().log = nil
	local api = Spoken()
	if not api or self.ready then return end
	self.ready = true
	api:AddLogSource(function() return LogBook:Sources() end, function() PartySync:DB().collected = {} end)
	PartySync:Trace("party", "Spoken Party Sync %s", PartySync.version)
end
