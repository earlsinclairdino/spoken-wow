-- The debug log: what this client did and saw, kept for finding out afterwards why two
-- computers disagreed about a line.
--
-- Every client keeps its own, in SpokenPartySyncDB.log, so it survives a /reload and can be
-- read straight out of the saved variables file. It records the sync's own steps (a line
-- announced, rebuilt, held, started, acknowledged), every addon message in and out, and the
-- Spoken player's queue as the player reports it (queued, started, stopped, dropped, and why).
--
-- Any member can ask the others for theirs (`/sps logs pull`): each sends its last lines back,
-- paced, with its own clock reading, and the asker keeps them in SpokenPartySyncDB.collected
-- with the offset that maps that clock onto its own. `/sps logs` then shows every log merged
-- on one timeline, in a box to copy from.
--
--   LQ  token, count                ask for the last `count` lines
--   LH  token, total, now, version  the answer's header: how many lines follow, the sender's
--                                   GetTime() as it sent this, its addon version
--   LL  token, seq, line            one line, escaped

local _, PartySync = ...

local Comm, Peers = PartySync.Comm, PartySync.Peers

local LogBook = {}
PartySync.LogBook = LogBook

-- Kept lines. A busy evening of questing is a few hundred lines of sync, so this is hours.
local MAX_LINES = 2000
-- How many lines a member sends when asked, unless the asker says otherwise.
local DEFAULT_PULL = 400
-- One message line at most this long once escaped, so it fits a message with its header.
local LINE_BYTES = 220
-- A whole log arrives over a few seconds: this many messages, then a pause.
local PACE_BATCH, PACE_SECONDS = 8, 0.5
local PULL_TIMEOUT = 120

local function Store()
	local db = PartySync:DB()
	db.log = db.log or {}
	return db.log
end

--- Record one line: `category` is a short word to filter by (sync, msg, player, room, ...).
function LogBook:Add(category, message, ...)
	local ok, text = true, message
	if select("#", ...) > 0 then
		ok, text = pcall(format, message, ...)
		if not ok then text = tostring(message) end
	end
	local line = format("%.3f %s %s", GetTime(), category, tostring(text))
	local log = Store()
	log[#log + 1] = line
	-- Trimmed in a batch rather than one by one: removing from the front moves every line.
	if #log > MAX_LINES + 200 then
		local keep = {}
		for i = #log - MAX_LINES + 1, #log do keep[#keep + 1] = log[i] end
		PartySync:DB().log = keep
	end
end

--- The start of a session, with what a reader needs to place it: who, which client, and the
--- wall clock that goes with this GetTime(), so two computers' logs can be laid side by side.
function LogBook:Session()
	local _, build = GetBuildInfo()
	self:Add("session", "start: %s, Spoken Party Sync %s, client build %s, wall clock %s at GetTime %.3f",
		tostring(PartySync:UnitChatName("player")), PartySync.version, tostring(build),
		date and date("%Y-%m-%d %H:%M:%S") or "?", GetTime())
end

function LogBook:Clear()
	PartySync:DB().log = {}
	PartySync:DB().collected = {}
end

--------------------------------------------------------------------------------
-- The player's queue, as the player reports it
--------------------------------------------------------------------------------

local function Describe(clip)
	if type(clip) ~= "table" then return tostring(clip) end
	local source = clip.source and clip.source.key or "?"
	local sync = clip.partySync
	local role = sync and (" " .. sync.role .. "/" .. tostring(sync.state)) or ""
	return format("%s [%s%s]", tostring(clip.key), source, role)
end
LogBook.Describe = Describe

function LogBook:WatchPlayer()
	local Spoken = _G.Spoken
	if self.watching or not (Spoken and Spoken.RegisterCallback) then return end
	self.watching = true
	Spoken:RegisterCallback("CLIP_QUEUED", function(clip)
		local held = Spoken:GetHeldReason(clip)
		LogBook:Add("player", "queued %s, %d in queue%s", Describe(clip), Spoken:GetQueueSize(),
			held and (", held: " .. tostring(held)) or "")
	end)
	Spoken:RegisterCallback("CLIP_STARTED", function(clip)
		LogBook:Add("player", "started %s, length %s%s", Describe(clip), tostring(clip.length),
			Spoken.IsCaptionsOnly and Spoken:IsCaptionsOnly() and ", captions only" or "")
	end)
	Spoken:RegisterCallback("CLIP_STOPPED", function(clip, finished)
		LogBook:Add("player", "%s %s", finished and "finished" or "stopped", Describe(clip))
	end)
	Spoken:RegisterCallback("CLIP_DROPPED", function(clip, reason)
		LogBook:Add("player", "dropped %s: %s", Describe(clip), tostring(reason))
	end)
	local paused
	Spoken:RegisterCallback("AUDIO_CHANGED", function()
		local now = Spoken:IsPaused()
		if now ~= paused then
			if paused ~= nil then LogBook:Add("player", now and "paused" or "resumed") end
			paused = now
		end
	end)
end

--------------------------------------------------------------------------------
-- Pulling the others' logs
--------------------------------------------------------------------------------

local counter = 0
local pulls = {}   -- token -> { key, name, sentAt, total, lines, now, at }

local function Collected()
	local db = PartySync:DB()
	db.collected = db.collected or {}
	return db.collected
end

--- Ask every member online for their last `count` lines.
function LogBook:Pull(count)
	count = math.max(1, math.min(MAX_LINES, tonumber(count) or DEFAULT_PULL))
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
	self:Add("logs", "asked %d member(s) for %d lines", #members, count)
	PartySync:Print("asked %d member%s for their log; it takes a few seconds", #members, #members == 1 and "" or "s")
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
	self:Add("logs", "%s's log: %d of %s lines%s, offset %s s", pull.name, received, tostring(pull.total),
		timedOut and " (gave up waiting)" or "", pull.offset and format("%.3f", pull.offset) or "?")
	PartySync:Print("%s's log: %d line%s%s. /sps logs shows them with yours", PartySync:ShortName(pull.name), received,
		received == 1 and "" or "s", timedOut and format(", %d never arrived", (pull.total or 0) - received) or "")
end

Comm:On("LQ", function(sender, channel, token, count)
	-- Only to the party: a log names the characters played with and what was said.
	if not Peers:IsMember(sender) then return end
	LogBook:Add("logs", "%s asked for %s lines", PartySync:ShortName(sender), tostring(count))
	local log = Store()
	count = math.max(1, math.min(#log, tonumber(count) or DEFAULT_PULL))
	local first = #log - count + 1
	local lines = {}
	for i = math.max(1, first), #log do
		local escaped = Comm.Escape(log[i])
		if #escaped > LINE_BYTES then escaped = escaped:sub(1, LINE_BYTES):gsub("\\$", "") end
		lines[#lines + 1] = escaped
	end
	Comm:Whisper(sender, "LH", token, #lines, format("%.3f", GetTime()), PartySync.version)
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

Comm:On("LH", function(sender, channel, token, total, now, version)
	local pull = token and pulls[token]
	if not pull then return end
	pull.total = tonumber(total) or 0
	pull.version = version
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
-- One timeline
--------------------------------------------------------------------------------

--- This client's log and every collected one, on this client's clock, oldest first, each line
--- headed by whose it is. `count` limits it to the newest lines.
function LogBook:Merged(count)
	local rows = {}
	local function AddAll(lines, who, offset)
		for _, line in ipairs(lines) do
			local t, rest = line:match("^(%-?[%d%.]+) (.*)$")
			t = tonumber(t)
			if t then
				rows[#rows + 1] = { t = t + (offset or 0), who = who, text = rest }
			end
		end
	end
	AddAll(Store(), PartySync:ShortName(PartySync:UnitChatName("player")), 0)
	for _, log in pairs(Collected()) do
		AddAll(log.lines or {}, PartySync:ShortName(log.name), log.offset or 0)
	end
	table.sort(rows, function(a, b) return a.t < b.t end)
	local first = count and math.max(1, #rows - count + 1) or 1
	local out = {}
	for i = first, #rows do
		local row = rows[i]
		out[#out + 1] = format("%10.3f  %-16s %s", row.t, row.who, row.text)
	end
	return out
end

--------------------------------------------------------------------------------
-- A box to copy from
--------------------------------------------------------------------------------

local box

local function Box()
	if box then return box end
	box = CreateFrame("Frame", "SpokenPartySyncLogWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	box:SetSize(760, 460)
	box:SetPoint("CENTER")
	box:SetFrameStrata("DIALOG")
	box:SetMovable(true)
	box:EnableMouse(true)
	box:RegisterForDrag("LeftButton")
	box:SetScript("OnDragStart", function(self) self:StartMoving() end)
	box:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	if box.SetBackdrop then
		box:SetBackdrop({ bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
			edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	end
	local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("Spoken Party Sync log -- Ctrl+A, Ctrl+C to copy")
	local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	local scroll = CreateFrame("ScrollFrame", "SpokenPartySyncLogScroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
	edit:SetWidth(700)
	edit:SetAutoFocus(false)
	edit:SetScript("OnEscapePressed", function() box:Hide() end)
	scroll:SetScrollChild(edit)
	box.edit = edit
	if UISpecialFrames then table.insert(UISpecialFrames, "SpokenPartySyncLogWindow") end
	return box
end

function LogBook:Show(count)
	local lines = self:Merged(count)
	local frame = Box()
	frame.edit:SetText(table.concat(lines, "\n"))
	frame:Show()
	frame.edit:SetFocus()
	frame.edit:HighlightText()
	return #lines
end

function LogBook:Setup()
	self:Session()
	self:WatchPlayer()
end
