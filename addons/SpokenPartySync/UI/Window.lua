-- The sync window: the party, every queued line and how far each computer got with it, and
-- what has gone wrong. Small and plain, and by default only on screen when something is wrong:
-- the player already shows what is speaking, and this is for when two computers disagree.
--
-- One block of text, rebuilt from scratch on every change, rather than rows to keep in step:
-- it is a handful of lines, and the queue it describes changes shape all the time.

local _, PartySync = ...

local Peers, Sync, Lines, L = PartySync.Peers, PartySync.Sync, PartySync.Lines, PartySync.L

local WIDTH = 320
local PAD = 10
local MAX_LINES = 8
-- How long the window stays up after the last problem cleared, on "when something is wrong".
local LINGER_SECONDS = 8

local frame, text
-- Opened by hand (/sps window, the settings button): shown whatever the setting says, until
-- closed by hand.
local forced = false
local lastProblemAt = nil

local GREEN, YELLOW, RED, GREY = "|cff60ff60", "|cffffd060", "|cffff6060", "|cff909090"
local DOTS = {
	online = [[|TInterface\COMMON\Indicator-Green:12|t]],
	lost = [[|TInterface\COMMON\Indicator-Yellow:12|t]],
	offline = [[|TInterface\COMMON\Indicator-Gray:12|t]],
}

local function DB()
	return PartySync:DB().window
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint()
	DB().point = { point, relativePoint, x, y }
end

local function Create()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "SpokenPartySyncWindow", UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(WIDTH, 80)
	local point = DB().point
	if point then
		frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -220)
	end
	frame:SetScale(DB().scale or 1)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
			edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.75)
		frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
	else
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.7)
	end

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText(L.TITLE)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		forced = false
		frame:Hide()
		frame.dismissed = true
	end)

	-- The player's own round buttons, where it offers them: the same Skip and Pause.
	local Spoken = _G.Spoken
	if Spoken and Spoken.CreateRoundButton then
		local pause = Spoken:CreateRoundButton(frame, "play")
		pause:SetSize(18, 18)
		pause:SetPoint("RIGHT", close, "LEFT", -2, 0)
		pause:SetScript("OnClick", function() Spoken:TogglePause() end)
		pause.tooltip = L.WINDOW_PAUSE
		frame.pause = pause
	end

	text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", PAD, -PAD - 16)
	text:SetWidth(WIDTH - 2 * PAD)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	if text.SetSpacing then text:SetSpacing(2) end
	return frame
end

--------------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------------

local function Ms(value)
	return value and format("%d ms", math.floor(value + 0.5)) or nil
end

local function MemberLine(key, isMe)
	local parts = {}
	local peer = Peers.list[key]
	local state = isMe and "online" or (peer and peer.state) or nil
	local name = isMe and (PartySync:ShortName(PartySync:UnitChatName("player")) .. " (" .. L.TAG_YOU .. ")")
		or PartySync:ShortName(Peers:MemberName(key))
	table.insert(parts, (DOTS[state] or DOTS.offline) .. " " .. name)
	if not isMe then
		local words = { online = L.STATE_ONLINE, lost = L.STATE_LOST, offline = L.STATE_OFFLINE }
		table.insert(parts, GREY .. (words[state] or L.STATE_UNKNOWN) .. "|r")
		if state == "online" and peer.rtt then table.insert(parts, GREY .. Ms(peer.rtt) .. "|r") end
	end
	if Peers:IsLeader(key) then table.insert(parts, YELLOW .. L.TAG_LEAD .. "|r") end
	if PartySync.Room and PartySync.Room:Speaker() == key then table.insert(parts, GREEN .. L.TAG_SOUND .. "|r") end
	return table.concat(parts, "  ")
end

local PEER_WORDS = {
	sent = L.PEER_WAITING, queued = L.PEER_QUEUED, started = L.PEER_STARTED, finished = L.PEER_FINISHED,
	missing = L.PEER_MISSING, dropped = L.PEER_DROPPED, yielded = L.PEER_YIELDED, noanswer = L.PEER_NO_ANSWER,
}
local PEER_COLOURS = { missing = RED, dropped = GREY, noanswer = RED, finished = GREEN, started = GREEN }

local function LineState(clip, entry)
	local Spoken = _G.Spoken
	if Spoken:IsPlaying(clip) then
		return GREEN .. L.LINE_PLAYING .. "|r"
	end
	if Spoken:GetCurrent() == clip and Spoken:IsPaused() then
		return YELLOW .. L.LINE_PAUSED .. "|r"
	end
	local held = Spoken:GetHeldReason(clip)
	if held then
		return YELLOW .. held .. "|r"
	end
	return GREY .. L.LINE_QUEUED .. "|r"
end

local function QueueLine(clip)
	local entry = clip.partySync
	local present = clip.present or {}
	local bullet = present.bullet and _G.Spoken:GetBullet(present.bullet)
	local icon = bullet and bullet.texture and format("|T%s:12|t ", bullet.texture) or ""
	local label = present.label ~= nil and present.label ~= "" and present.label or present.header or clip.key
	local line = icon .. tostring(label) .. "  " .. LineState(clip, entry)
	if not entry then
		if Peers:AnyOnline() then line = line .. "  " .. GREY .. L.LINE_LOCAL .. "|r" end
		return line
	end
	if entry.role == "follower" then
		return line
	end
	local peers = {}
	for _, key in ipairs(Peers:OnlineMembers()) do
		local peer = entry.peers[key]
		if peer then
			local word = PEER_WORDS[peer.state] or peer.state
			if peer.state == "started" and peer.ms and peer.ms >= 50 then
				word = format(L.PEER_LATE_FMT, peer.ms)
			end
			table.insert(peers, (PEER_COLOURS[peer.state] or GREY) .. PartySync:ShortName(Peers:MemberName(key)) .. ": " .. word .. "|r")
		end
	end
	if peers[1] then
		line = line .. "\n      " .. table.concat(peers, ", ")
	end
	return line
end

local function Build()
	local out = {}
	local me = PartySync:MyKey()
	local anyMember = false
	for _ in Peers:Members() do anyMember = true break end
	if not anyMember then
		table.insert(out, GREY .. L.WINDOW_NO_MEMBERS .. "|r")
	else
		if me then table.insert(out, MemberLine(me, true)) end
		local keys = {}
		for key in Peers:Members() do table.insert(keys, key) end
		table.sort(keys)
		for _, key in ipairs(keys) do table.insert(out, MemberLine(key, false)) end
	end
	table.insert(out, " ")
	local Spoken = _G.Spoken
	local queue = PartySync:PlayerAvailable() and Spoken:GetQueue() or {}
	if not queue[1] then
		table.insert(out, GREY .. L.WINDOW_QUEUE_EMPTY .. "|r")
	end
	for i, clip in ipairs(queue) do
		if i > MAX_LINES then
			table.insert(out, GREY .. format("+%d", #queue - MAX_LINES) .. "|r")
			break
		end
		table.insert(out, QueueLine(clip))
	end
	local problems = PartySync:Problems()
	if problems[1] then
		table.insert(out, " ")
		for _, problem in ipairs(problems) do
			table.insert(out, RED .. problem.text .. "|r")
		end
	end
	return table.concat(out, "\n"), problems[1] ~= nil
end

--------------------------------------------------------------------------------
-- When it shows
--------------------------------------------------------------------------------

local function Syncing()
	if not Sync:Live() then return false end
	for _, entry in pairs(Sync.lines) do
		if entry.state == "waiting" or entry.state == "go" or entry.state == "released" or entry.state == "playing" then
			return true
		end
	end
	return false
end

local function Wanted(hasProblems)
	if forced then return true end
	local show = DB().show
	if show == "always" then return true end
	if show == "never" then return false end
	if show == "syncing" then return Syncing() or hasProblems end
	-- "problems"
	if hasProblems then
		lastProblemAt = GetTime()
		return true
	end
	return lastProblemAt ~= nil and GetTime() - lastProblemAt < LINGER_SECONDS
end

function PartySync:RefreshWindow()
	if not self.windowReady then return end
	local body, hasProblems = Build()
	-- Kept for /dump and the tests: what the window says, whether or not it is up.
	self.windowBody = body
	local want = Wanted(hasProblems)
	if want and frame and frame.dismissed and not forced and not hasProblems then
		-- Closed by hand: stays closed until something new goes wrong.
		want = false
	end
	if not want then
		if frame then frame:Hide() end
		return
	end
	Create()
	if hasProblems then frame.dismissed = nil end
	text:SetText(body)
	frame:SetHeight((text:GetStringHeight() or 0) + 2 * PAD + 20)
	if frame.pause and frame.pause.SetPlaying then
		frame.pause:SetPlaying(_G.Spoken:GetNowPlaying() ~= nil and not _G.Spoken:IsPaused())
	end
	frame:Show()
end

function PartySync:ShowWindow(shown)
	forced = shown and true or false
	if frame then frame.dismissed = not shown or nil end
	if not shown and frame then frame:Hide() end
	self:RefreshWindow()
end

function PartySync:ToggleWindow()
	self:ShowWindow(not (frame and frame:IsShown()))
end

function PartySync:SetWindowScale(scale)
	DB().scale = scale
	if frame then frame:SetScale(scale) end
end

--- Once the saved variables are in. A once-a-second check keeps the problems and the round
--- trips current and lets the window go once the last problem has lingered long enough.
function PartySync:SetupWindow()
	if self.windowReady then return end
	self.windowReady = true
	local elapsed = 0
	local ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed >= 1 then
			elapsed = 0
			PartySync:RefreshWindow()
		end
	end)
	self:RefreshWindow()
end
