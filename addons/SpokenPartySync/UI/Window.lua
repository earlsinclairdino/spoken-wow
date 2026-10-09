-- The party window: who is in the party, the line playing, and anything gone wrong with a way
-- to put it right. Small and plain, and by default only on screen when something is wrong: the
-- player already shows what is speaking, and this is for when two computers disagree.
--
-- What it shows is worked out first as a plain table (WindowModel) and then drawn, so a test
-- reads what the window says without a client. Its menus are lists of entries built the same
-- way and handed to the game's context menu. Nothing in it is a secure frame, so every click
-- works in combat.

local _, PartySync = ...

local Peers, Sync, Room, Autoform, L = PartySync.Peers, PartySync.Sync, PartySync.Room, PartySync.Autoform, PartySync.L

local FULL = { width = 320, pad = 10, top = 8, header = 20, row = 18, round = 18, glyph = 9, dot = 12, gap = 6,
	titleFont = "GameFontNormal", nameFont = "GameFontHighlight" }
local COMPACT = { width = 220, pad = 8, top = 6, header = 16, row = 16, round = 16, glyph = 8, dot = 10, gap = 4,
	titleFont = "GameFontNormalSmall", nameFont = "GameFontHighlightSmall" }
local CHIP_HEIGHT = 16
local LINE_HEIGHT = 16
local SUB_HEIGHT = 14
local SUB_INDENT = 20
local ICON_SIZE = 14
-- How long the window stays up after the last problem cleared, on "when something is wrong".
local LINGER_SECONDS = 8

local GREEN, YELLOW, RED, GREY = "|cff60ff60", "|cffffd060", "|cffff6060", "|cff909090"
local DOTS = {
	online = [[Interface\COMMON\Indicator-Green]],
	quiet = [[Interface\COMMON\Indicator-Yellow]],
	unknown = [[Interface\COMMON\Indicator-Gray]],
}
local WHITE8 = [[Interface\Buttons\WHITE8X8]]
local ALERT = [[Interface\DialogFrame\UI-Dialog-Icon-AlertNew]]
local MENU_ARROW = [[Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up]]

local CONTROLS = { leader = L.CONTROLS_LEADER, anyone = L.CONTROLS_ANYONE, nobody = L.CONTROLS_NOBODY }
local STATE_WORDS = { lost = L.STATE_LOST, offline = L.STATE_OFFLINE }

local frame
-- Opened by hand (/sps window, the page, the minimap menu): shown whatever the setting says,
-- until closed by hand.
local forced = false
local lastProblemAt = nil
-- Set around this file's own Hide, so only a close by the player (Escape) counts as one.
local hidingHere = false
-- Closed by hand: the problems (and the offer) on screen then, by key. It stays closed until
-- one not among them comes up.
local seenAtClose = nil

local function Attention(model)
	local keys = {}
	for _, problem in ipairs(model and model.problems or {}) do keys[problem.key] = true end
	if model and model.prompt then keys.prompt = true end
	return keys
end

local function Dismiss()
	forced = false
	seenAtClose = Attention(PartySync.windowModel)
end

local function DB()
	return PartySync:DB().window
end

local function RulesReason()
	return not Peers:MayInvite() and L.OPT_RULES_LEADER or nil
end

--------------------------------------------------------------------------------
-- What it says
--------------------------------------------------------------------------------

--- What `key`'s computer plays, as far as this one knows, in words for its tooltip.
local function PlaysText(key)
	local names = {}
	for _, channel in ipairs(Room.CHANNELS) do
		if Room:Plays(channel, key) then table.insert(names, Room:Name(channel):lower()) end
	end
	return names[1] and format(L.ROW_PLAYS_FMT, table.concat(names, ", ")) or L.ROW_PLAYS_NONE
end

--- One member: a dot, the name, and the one tag that most needs saying (a silence before the
--- voice, the voice before the lead), with everything else for the tooltip.
local function MemberModel(key, isMe, leader)
	local peer = not isMe and Peers.list[key] or nil
	local leads, voice, own = key == leader, Room:Voices(key), Room:Decides(key)
	local member = { key = key, isMe = isMe, dot = "online", rtt = peer and peer.rtt,
		name = isMe and PartySync:ShortName(PartySync:UnitChatName("player")) or Peers:ShortName(key) }
	if not isMe then
		local quiet = Peers:Quiet(key)
		if not (peer and peer.state == "online") then
			member.dot, member.state = "unknown", STATE_WORDS[peer and peer.state] or L.STATE_UNKNOWN
			member.tag, member.colour = member.state, GREY
		elseif quiet then
			member.dot, member.state = "quiet", format(L.STATE_QUIET_FMT, quiet)
			member.tag, member.colour = member.state, RED
		else
			member.state = L.STATE_ONLINE
		end
	end
	if not member.tag then
		if voice then
			member.tag, member.colour = L.TAG_SOUND, GREEN
		elseif leads then
			member.tag, member.colour = L.TAG_LEAD, YELLOW
		elseif own then
			member.tag, member.colour = L.TAG_OWN_SOUND, YELLOW
		end
	end
	member.tags = {}
	if leads then table.insert(member.tags, L.TAG_LEAD) end
	if voice then table.insert(member.tags, L.TAG_SOUND) end
	if own then table.insert(member.tags, L.TAG_OWN_SOUND) end
	member.plays = PlaysText(key)
	return member
end

local function LineState(clip)
	local Spoken = _G.Spoken
	if Spoken:IsPlaying(clip) then
		return L.LINE_PLAYING, GREEN
	end
	if Spoken:GetCurrent() == clip and Spoken:IsPaused() then
		return L.LINE_PAUSED, YELLOW
	end
	local held = Spoken:GetHeldReason(clip)
	if held then
		return held, YELLOW
	end
	return L.LINE_QUEUED, GREY
end

local TROUBLE_WORDS = {
	noanswer = { L.PEER_NO_ANSWER, RED }, unplayed = { L.PEER_NO_ANSWER, RED },
	missing = { L.PEER_MISSING, RED }, dropped = { L.PEER_DROPPED, GREY },
}

--- A member's progress with a line this computer drives, only where it is not as it should be.
local function Progress(entry, peer)
	local trouble, ms = Sync:PeerTrouble(entry, peer)
	if trouble == "late" then
		return format(L.PEER_LATE_FMT, ms), YELLOW
	end
	local words = TROUBLE_WORDS[trouble]
	if words then return words[1], words[2] end
	return nil
end

--- The line that matters (the one playing, else the first queued) and how many wait behind.
local function QueueModel()
	if not PartySync:PlayerAvailable() then
		return { empty = true }
	end
	local Spoken = _G.Spoken
	local queue = Spoken:GetQueue()
	local clip = queue[1]
	for _, queued in ipairs(queue) do
		if Spoken:IsPlaying(queued) then
			clip = queued
			break
		end
	end
	if not clip then
		return { empty = true }
	end
	local present = clip.present or {}
	local bullet = present.bullet and Spoken:GetBullet(present.bullet)
	local label = (present.label ~= nil and present.label ~= "" and present.label) or present.header or clip.key
	local state, colour = LineState(clip)
	local entry = clip.partySync
	local line = { icon = bullet and bullet.texture, label = tostring(label), state = state, colour = colour,
		here = entry == nil and Peers:AnyOnline(), progress = {}, more = #queue - 1 }
	-- Only the computer that started a line hears from everyone about it.
	if entry and entry.role == "driver" then
		for _, key in ipairs(Peers:OnlineMembers()) do
			local text, textColour = Progress(entry, entry.peers[key])
			if text then
				table.insert(line.progress, { name = Peers:ShortName(key), text = text, colour = textColour })
			end
		end
	end
	return line
end

--- A problem's fixes: asking a silent member again or removing them, taking the voice off a
--- computer that has no file for it, else dismissing it.
local function ProblemActions(problem)
	local key, who = problem.key, problem.who
	if problem.kind == "missing" and Peers:IsMember(who) and Room:Plays("voice", who) and Room:CanExclude("voice", who) then
		return { {
			label = L.ACTION_MUTE, tip = L.ACTION_MUTE_TIP, reason = Peers:WhyNotLeader(),
			run = function() Room:Exclude("voice", who); PartySync:Resolve(key) end,
		} }
	end
	if problem.kind ~= "silent" then
		return { { label = L.ACTION_DISMISS, tip = L.ACTION_DISMISS_TIP, run = function() PartySync:Resolve(key) end } }
	end
	-- A member is greeted again by anyone; someone out of the party, invited by its leader.
	local actions = { {
		label = L.ACTION_REINVITE, tip = L.ACTION_REINVITE_TIP,
		reason = not Peers:IsMember(who) and Peers:WhyNotLeader() or nil,
		run = function() Peers:Reinvite(who); PartySync:Resolve(key) end,
	} }
	if Peers:IsMember(who) then
		table.insert(actions, {
			label = L.ACTION_REMOVE, tip = format(L.ACTION_REMOVE_TIP_FMT, Peers:ShortName(who)), reason = Peers:WhyNotLeader(),
			run = function() Peers:RemoveMember(who); PartySync:Resolve(key) end,
		})
	end
	return actions
end

local function StopModel()
	local Spoken = _G.Spoken
	if not PartySync:PlayerAvailable() then
		return { state = "stop", title = L.WINDOW_STOP, body = L.WINDOW_STOP_TIP, reason = L.REASON_NO_PLAYER }
	end
	local stopped = Spoken:IsPaused() and Spoken:GetCurrent() ~= nil
	local stop = stopped and { state = "replay", title = L.WINDOW_REPLAY, body = L.WINDOW_REPLAY_TIP }
		or { state = "stop", title = L.WINDOW_STOP, body = L.WINDOW_STOP_TIP }
	stop.reason = (Spoken.WhyNoControl and Spoken:WhyNoControl())
		or (Spoken:GetNowPlaying() == nil and L.WINDOW_NOTHING_PLAYING) or nil
	return stop
end

local HEALTH = {
	sync = { L.HEALTH_SYNC, GREEN },
	late = { L.HEALTH_LATE, YELLOW },
	missed = { L.HEALTH_MISSED, RED },
}

--- Who plays what, a line a channel, or one line when every channel is on the same computer.
local function AudioLines()
	local lines = {}
	local summary = Room:Summary()
	if summary ~= "mixed" then
		table.insert(lines, format(L.AUDIO_RULE_FMT, L.MENU_ALL_SOUND, Room:Describe(summary)))
	else
		for _, channel in ipairs(Room.CHANNELS) do
			table.insert(lines, format(L.AUDIO_RULE_FMT, Room:Name(channel), Room:Describe(Room:Owner(channel))))
		end
	end
	local own = {}
	for _, channel in ipairs(Room.CHANNELS) do
		local value = Room:OwnValue(channel)
		if value ~= "" then table.insert(own, Room:Name(channel) .. " " .. Room:DescribeOwn(value, channel):lower()) end
	end
	if own[1] then table.insert(lines, format(L.AUDIO_OWN_FMT, table.concat(own, ", "))) end
	table.insert(lines, L.CHIP_AUDIO_TIP)
	return table.concat(lines, "\n")
end

local function ChipsModel()
	local rules = Peers:Rules()
	local shareReason = Peers:WhyNoShare()
	return {
		-- Live for everyone: whoever does not lead still decides this computer's own sound in it.
		audio = { text = format(L.CHIP_AUDIO_FMT, Room:Short(Room:Summary())), title = L.CHIP_AUDIO_TITLE,
			body = AudioLines() },
		playback = { text = format(L.CHIP_PLAYBACK_FMT, CONTROLS[rules.controls] or tostring(rules.controls)),
			title = L.OPT_CONTROLS, body = L.OPT_CONTROLS_TIP, reason = RulesReason() },
		quests = { text = (PartySync:DB().autoShare and not shareReason) and L.CHIP_QUESTS_ON or L.CHIP_QUESTS_OFF,
			title = L.OPT_AUTO_SHARE, body = L.CHIP_QUESTS_TIP, reason = shareReason },
	}
end

--- Everything the window shows, as data.
function PartySync:WindowModel()
	local model = { compact = DB().compact == true, inParty = Peers:InParty(), stop = StopModel(), problems = {} }
	if model.inParty then
		local health = Sync.ready and Sync:Health()
		model.health = health and { word = HEALTH[health][1], colour = HEALTH[health][2], kind = health }
		model.chips = ChipsModel()
		model.members = {}
		local me, leader = self:MyKey(), Peers:Leader()
		for _, key in ipairs(Peers:MemberKeys()) do
			table.insert(model.members, MemberModel(key, key == me, leader))
		end
		model.line = QueueModel()
	end
	-- Kept out of a party too: a member gone may end it, and that is when Re-invite is wanted.
	for _, problem in ipairs(self:Problems()) do
		table.insert(model.problems, { key = problem.key, text = problem.text, actions = ProblemActions(problem) })
	end
	local prompt = Autoform:Prompt()
	if prompt then
		model.prompt = { text = format(L.PROMPT_FMT, prompt.names), actions = {
			{ label = L.PROMPT_REMEMBER, tip = L.PROMPT_REMEMBER_TIP, run = function() Autoform:AcceptPrompt() end },
			{ label = L.PROMPT_NOT_NOW, tip = L.PROMPT_NOT_NOW_TIP, run = function() Autoform:DeclinePrompt() end },
		} }
	end
	return model
end

--- What the window says, as plain text, for /dump and the tests.
function PartySync:WindowText()
	local model = self:WindowModel()
	local out = { L.WINDOW_TITLE .. (model.health and ("  " .. model.health.word) or "") }
	if model.chips then
		table.insert(out, table.concat({ model.chips.audio.text, model.chips.playback.text, model.chips.quests.text }, "  "))
	end
	if not model.inParty then
		table.insert(out, L.WINDOW_NO_MEMBERS)
	end
	if model.prompt then
		table.insert(out, model.prompt.text .. "  [" .. L.PROMPT_REMEMBER .. "] [" .. L.PROMPT_NOT_NOW .. "]")
	end
	for _, member in ipairs(model.members or {}) do
		table.insert(out, member.name .. (member.isMe and (" (" .. L.TAG_YOU .. ")") or "")
			.. (member.tag and ("  " .. member.tag) or ""))
	end
	local line = model.line
	if line and line.empty then
		table.insert(out, L.WINDOW_QUEUE_EMPTY)
	elseif line then
		table.insert(out, line.label .. "  " .. line.state .. (line.here and ("  " .. L.LINE_LOCAL) or ""))
		for _, sub in ipairs(line.progress) do
			table.insert(out, "    " .. sub.name .. ": " .. sub.text)
		end
		if line.more > 0 then
			table.insert(out, "    " .. format(L.WINDOW_MORE_FMT, line.more))
		end
	end
	for _, problem in ipairs(model.problems) do
		local labels = {}
		for _, action in ipairs(problem.actions) do table.insert(labels, action.label) end
		table.insert(out, problem.text .. "  [" .. table.concat(labels, "] [") .. "]")
	end
	return table.concat(out, "\n")
end

--- One radio entry a value: `describe(value)` its words, `pick(value)` what a click does.
local function Radios(values, current, describe, pick, reason, tip)
	local entries = {}
	for _, value in ipairs(values) do
		table.insert(entries, { text = describe(value), radio = value == current, reason = reason, tip = tip,
			onClick = function() pick(value) end })
	end
	return entries
end

local function DescribeOwner(owner)
	return Room:Describe(owner)
end

--------------------------------------------------------------------------------
-- Menus: lists of { text, onClick, radio | checked, tip, reason, children } or { title }
--------------------------------------------------------------------------------
--
-- An entry with a reason is greyed and does nothing but say why, on hover and when clicked.

local function Whisper(name)
	local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
	if tell then
		tell(name)
	elseif ChatFrame_OpenChat then
		ChatFrame_OpenChat("/w " .. name .. " ")
	end
end

function PartySync:WindowTitleMenu()
	local inParty = Peers:InParty()
	return {
		{ text = L.MENU_WINDOW_SETTINGS, onClick = function() PartySync:OpenOptions() end },
		{ text = L.OPT_REMEMBER, tip = L.OPT_REMEMBER_TIP,
			reason = (not inParty and L.OPT_IN_PARTY) or (Autoform:Remembered() and L.REMEMBERED_ALREADY) or nil,
			onClick = function() Autoform:Remember() end },
		{ text = L.MENU_WINDOW_COMPACT, checked = DB().compact == true,
			onClick = function() PartySync:SetWindowCompact(not DB().compact) end },
		{ text = L.OPT_LEAVE, tip = L.OPT_LEAVE_TIP, reason = not inParty and L.OPT_IN_PARTY or nil,
			onClick = function() Peers:Leave() end },
	}
end

function PartySync:WindowMemberMenu(key)
	local isMe = key == self:MyKey()
	local name = isMe and PartySync:ShortName(self:UnitChatName("player")) or Peers:ShortName(key)
	local only = Peers:WhyNotLeader()
	local entries = {
		{ text = L.MENU_MAKE_LEADER, tip = L.OPT_LEAD_BTN_TIP,
			reason = only or (Peers:IsLeader(key) and format(L.ALREADY_LEADS_FMT, name)) or nil,
			onClick = function() Peers:PassLead(key) end },
		{ text = L.MENU_PLAY_HERE, tip = L.OPT_SOUND_BTN_TIP,
			reason = only or (Room:Summary() == key and format(L.ALREADY_SOUND_FMT, name)) or nil,
			onClick = function() Room:SetAll(key) end },
	}
	if not isMe then
		table.insert(entries, { text = L.MENU_REMOVE_MEMBER, tip = format(L.ACTION_REMOVE_TIP_FMT, name), reason = only,
			onClick = function() Peers:RemoveMember(key) end })
		table.insert(entries, { text = L.MENU_WHISPER, onClick = function() Whisper(Peers:MemberName(key)) end })
	end
	return entries
end

--- The party's rule for each channel (the leader's), a shortcut putting all of them on one
--- computer, then this computer's own choices, which are everyone's.
function PartySync:WindowAudioMenu()
	local reason = RulesReason()
	local entries = { { title = L.MENU_WHO_PLAYS } }
	for _, channel in ipairs(Room.CHANNELS) do
		local current = Room:Owner(channel)
		table.insert(entries, { text = format(L.AUDIO_RULE_FMT, Room:Name(channel), Room:Short(current)),
			tip = Room:Tip(channel), children = Radios(Room:Choices(current), current, DescribeOwner,
				function(owner) Room:Set(channel, owner) end, reason) })
	end
	for _, owner in ipairs(Room:Choices()) do
		table.insert(entries, { text = format(L.ALL_ON_FMT, Room:Short(owner)), reason = reason, tip = L.OPT_ALL_SOUND_TIP,
			onClick = function() Room:SetAll(owner) end })
	end
	table.insert(entries, { title = L.MENU_THIS_COMPUTER })
	local summary = Room:OwnSummary()
	table.insert(entries, { text = format(L.AUDIO_RULE_FMT, L.MENU_ALL_SOUND, Room:DescribeOwn(summary)),
		tip = L.OPT_SOUND_OWN_TIP, children = Radios(Room:OwnChoices(), summary,
			function(value) return Room:DescribeOwn(value) end, function(value) Room:SetOwnAll(value) end) })
	for _, channel in ipairs(Room.CHANNELS) do
		local own = Room:OwnValue(channel)
		table.insert(entries, { text = format(L.AUDIO_RULE_FMT, Room:Name(channel), Room:DescribeOwn(own, channel)),
			tip = Room:Tip(channel), children = Radios(Room:OwnChoices(), own,
				function(value) return Room:DescribeOwn(value, channel) end,
				function(value) Room:SetOwnChannel(channel, value) end) })
	end
	return entries
end

function PartySync:WindowPlaybackMenu()
	local entries = Radios({ "leader", "anyone", "nobody" }, Peers:Rules().controls,
		function(value) return CONTROLS[value] end, function(value) Peers:SetRule("controls", value) end,
		RulesReason(), L.OPT_CONTROLS_TIP)
	table.insert(entries, 1, { title = L.OPT_CONTROLS })
	return entries
end

--- A gold title, the body in white, the reason in red, a hint in grey: every tooltip here.
local function FillTip(tooltip, title, body, reason, hint)
	tooltip:SetText(title, 1, 0.82, 0)
	if body and body ~= "" then tooltip:AddLine(body, 1, 1, 1, true) end
	if reason then tooltip:AddLine(reason, 1, 0.5, 0.5, true) end
	if hint then tooltip:AddLine(hint, 0.6, 0.6, 0.6, true) end
end

local function EntryTooltip(entry)
	return function(tooltip) FillTip(tooltip, entry.text, entry.tip, entry.reason) end
end

--- One entry into the game's menu, its children as a submenu. Greyed by its text's colour rather
--- than disabled, so its tooltip still says why and a click says it again in chat.
local AddEntry
AddEntry = function(root, entry)
	if entry.title then
		root:CreateTitle(entry.title)
		return
	end
	local text = entry.reason and (GREY .. entry.text .. "|r") or entry.text
	local function Run()
		if entry.reason then
			PartySync:Print("%s", entry.reason)
		elseif entry.onClick then
			entry.onClick()
		end
	end
	local description
	if entry.children then
		description = root:CreateButton(text)
		for _, child in ipairs(entry.children) do
			AddEntry(description, child)
		end
	elseif entry.radio ~= nil then
		description = root:CreateRadio(text, function() return entry.radio end, Run)
	elseif entry.checked ~= nil then
		description = root:CreateCheckbox(text, function() return entry.checked end, Run)
	else
		description = root:CreateButton(text, Run)
	end
	if description and description.SetTooltip and (entry.tip or entry.reason) then
		description:SetTooltip(EntryTooltip(entry))
	end
end

local function OpenMenu(owner, title, entries)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		PartySync:Print("this client has no menus here: /sps lists the same choices")
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if title then root:CreateTitle(title) end
		for _, entry in ipairs(entries) do
			AddEntry(root, entry)
		end
	end)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- `owner.tip` as the game's tooltip.
local function ShowTip(owner)
	local tip = owner.tip
	if not (tip and tip.title) then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	FillTip(GameTooltip, tip.title, tip.body, tip.reason, tip.hint)
	GameTooltip:Show()
end

local function Tipped(region)
	region:HookScript("OnEnter", ShowTip)
	region:HookScript("OnLeave", function() GameTooltip_Hide() end)
	if region.SetMotionScriptsWhileDisabled then region:SetMotionScriptsWhileDisabled(true) end
end

local function Put(region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint()
	DB().point = { point, relativePoint, x, y }
end

local function StartMoving() frame:StartMoving() end
local function StopMoving()
	frame:StopMovingOrSizing()
	SavePosition()
end

local function PaintChip(chip, hover)
	local live = chip:IsEnabled()
	if chip.SetBackdropColor then
		chip:SetBackdropColor(0.08, 0.07, 0.05, 0.95)
		if hover and live then
			chip:SetBackdropBorderColor(0.54, 0.42, 0.18, 1)
		else
			chip:SetBackdropBorderColor(0.35, 0.29, 0.19, 1)
		end
	end
	if not live then
		chip.label:SetTextColor(0.5, 0.5, 0.5)
	elseif hover then
		chip.label:SetTextColor(1, 1, 1)
	else
		chip.label:SetTextColor(1, 0.82, 0)
	end
end

local function NewChip(parent)
	local chip = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	chip:SetHeight(CHIP_HEIGHT)
	-- Drawn 16 tall, clicked anywhere in 20.
	chip:SetHitRectInsets(0, 0, -2, -2)
	if chip.SetBackdrop then
		chip:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	end
	chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	chip.label:SetPoint("CENTER", 0, 0)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	Tipped(chip)
	chip:HookScript("OnEnter", function(self) PaintChip(self, true) end)
	chip:HookScript("OnLeave", function(self) PaintChip(self, false) end)
	return chip
end

local function SetChip(chip, model, onClick)
	chip.label:SetText(model.text)
	chip:SetWidth(math.floor((chip.label:GetStringWidth() or 0) + 12.5))
	if model.reason then chip:Disable() else chip:Enable() end
	chip.tip = { title = model.title or model.label, body = model.body or model.tip, reason = model.reason }
	chip:SetScript("OnClick", onClick)
	PaintChip(chip, false)
	chip:Show()
end

local function Pooled(list, make)
	return function(i)
		if not list[i] then list[i] = make(i) end
		return list[i]
	end
end

local function HideFrom(list, first)
	for i = first, #list do list[i]:Hide() end
end

local function NewRow()
	local row = CreateFrame("Button", nil, frame)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 0.82, 0, 0.08)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.label:SetJustifyH("LEFT")
	if row.label.SetWordWrap then row.label:SetWordWrap(false) end
	row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.tag:SetJustifyH("RIGHT")
	row:SetScript("OnClick", function(self)
		if self.key then OpenMenu(self, self.name, PartySync:WindowMemberMenu(self.key)) end
	end)
	Tipped(row)
	return row
end

local function NewDivider()
	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.23, 0.19, 0.14, 1)
	line:SetHeight(1)
	return line
end

local function NewSub()
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	text:SetJustifyH("LEFT")
	return text
end

local function SetAlertGlyph(texture)
	local atlas = "services-icon-warning"
	if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(ALERT)
	end
end

local function Height(fontString, least)
	return math.max(math.floor((fontString:GetStringHeight() or 0) + 0.5), least or 0)
end

-- A line of words with its actions as chips at the right: a problem (an alert glyph, in red) or
-- the offer to remember a party.
local function NewActionRow(alert)
	local row = CreateFrame("Frame", nil, frame)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.text:SetJustifyH("LEFT")
	if alert then
		row.glyph = row:CreateTexture(nil, "ARTWORK")
		row.glyph:SetSize(12, 12)
		row.glyph:SetPoint("TOPLEFT", 0, -1)
		SetAlertGlyph(row.glyph)
		row.text:SetTextColor(1, 0.38, 0.38)
		row.text:SetPoint("TOPLEFT", 18, -1)
	else
		row.text:SetTextColor(1, 1, 1)
		row.text:SetPoint("TOPLEFT", 0, -1)
	end
	row.chips = {}
	return row
end

local function NewProblem()
	return NewActionRow(true)
end

--- `row` filled with `text` and a chip for each of `actions`; returns its height.
local function FillActionRow(row, text, actions, inner, y, metrics)
	local right = 0
	for c, action in ipairs(actions) do
		local chip = row.chips[c] or NewChip(row)
		row.chips[c] = chip
		SetChip(chip, { text = action.label, title = action.label, body = action.tip, reason = action.reason },
			function() action.run(); PartySync:RefreshWindow() end)
		chip:ClearAllPoints()
		chip:SetPoint("TOPRIGHT", row, "TOPRIGHT", -right, 0)
		right = right + chip:GetWidth() + 4
	end
	HideFrom(row.chips, #actions + 1)
	local indent = row.glyph and 18 or 0
	row.text:SetWidth(inner - indent - right - 2)
	row.text:SetText(text)
	local height = math.max(Height(row.text, 12) + 2, CHIP_HEIGHT)
	row:SetSize(inner, height)
	Put(row, metrics.pad, y)
	row:Show()
	return height
end

local function Create()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "SpokenPartySyncWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(FULL.width, 80)
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
	frame:SetScript("OnDragStart", StartMoving)
	frame:SetScript("OnDragStop", StopMoving)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
			edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0.03, 0.03, 0.06, 0.94)
		frame:SetBackdropBorderColor(0.44, 0.33, 0.15, 1)
	end
	-- Escape closes it, and a close by the player keeps it closed until something new goes wrong.
	if UISpecialFrames then table.insert(UISpecialFrames, "SpokenPartySyncWindow") end
	frame:SetScript("OnHide", function()
		if not hidingHere then Dismiss() end
	end)

	local title = CreateFrame("Button", nil, frame)
	title.label = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title.label:SetPoint("LEFT", 0, 0)
	title.label:SetText(L.WINDOW_TITLE)
	title.arrow = title:CreateTexture(nil, "ARTWORK")
	title.arrow:SetTexture(MENU_ARROW)
	title.arrow:SetPoint("LEFT", title.label, "RIGHT", 2, 0)
	title:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	title:RegisterForDrag("LeftButton")
	title:SetScript("OnDragStart", StartMoving)
	title:SetScript("OnDragStop", StopMoving)
	title:SetScript("OnClick", function(self) OpenMenu(self, L.WINDOW_TITLE, PartySync:WindowTitleMenu()) end)
	title.tip = { title = L.WINDOW_TITLE, body = L.WINDOW_TITLE_TIP }
	Tipped(title)
	frame.title = title

	local health = CreateFrame("Frame", nil, frame)
	health:EnableMouse(true)
	health.label = health:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	health.label:SetPoint("LEFT", 0, 0)
	health:SetPoint("LEFT", title, "RIGHT", 6, 0)
	health.tip = { title = L.HEALTH_TITLE, body = L.HEALTH_TIP }
	Tipped(health)
	frame.health = health

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetScript("OnClick", function() PartySync:ShowWindow(false) end)
	frame.close = close

	-- The player's own round button: Stop while a line speaks, Replay once it is stopped.
	local Spoken = _G.Spoken
	if Spoken and Spoken.CreateRoundButton then
		local pause = Spoken:CreateRoundButton(frame, "play")
		pause:SetScript("OnClick", function() _G.Spoken:TogglePause() end)
		Tipped(pause)
		frame.pause = pause
	end

	frame.chips = {}
	for _, name in ipairs({ "audio", "playback", "quests" }) do
		frame.chips[name] = NewChip(frame)
	end
	frame.dividers, frame.rows, frame.subs, frame.problems = {}, {}, {}, {}
	frame.Divider = Pooled(frame.dividers, NewDivider)
	frame.Row = Pooled(frame.rows, NewRow)
	frame.Sub = Pooled(frame.subs, NewSub)
	frame.Problem = Pooled(frame.problems, NewProblem)
	PartySync.windowRows = frame.rows

	frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.note:SetJustifyH("LEFT")
	frame.line = CreateFrame("Frame", nil, frame)
	frame.line.icon = frame.line:CreateTexture(nil, "ARTWORK")
	frame.line.icon:SetSize(ICON_SIZE, ICON_SIZE)
	frame.line.icon:SetPoint("LEFT", 0, 0)
	frame.line.label = frame.line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.line.label:SetJustifyH("LEFT")
	if frame.line.label.SetWordWrap then frame.line.label:SetWordWrap(false) end
	frame.line.state = frame.line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.line.state:SetPoint("RIGHT", 0, 0)
	frame.line.state:SetJustifyH("RIGHT")
	frame.more = NewSub()
	return frame
end

local function DrawHeader(model, metrics)
	local title = frame.title
	title.label:SetFontObject(metrics.titleFont)
	title.arrow:SetSize(metrics.header - 6, metrics.header - 6)
	title:SetSize(math.floor((title.label:GetStringWidth() or 0) + metrics.header - 2), metrics.header)
	Put(title, metrics.pad, metrics.top)

	local health = frame.health
	if model.health and not model.compact then
		health.label:SetText(model.health.colour .. model.health.word .. "|r")
		health:SetSize(math.floor((health.label:GetStringWidth() or 0) + 1), metrics.header)
		health:Show()
	else
		health:Hide()
	end

	local close = frame.close
	close:SetSize(metrics.header + 4, metrics.header + 4)
	close:ClearAllPoints()
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(metrics.pad - 6), -(metrics.top - 2))

	local pause = frame.pause
	if pause then
		pause:SetSize(metrics.round, metrics.round)
		pause.glyph:SetSize(metrics.glyph, metrics.glyph)
		pause:ClearAllPoints()
		pause:SetPoint("RIGHT", close, "LEFT", -4, 0)
		pause:SetState(model.stop.state)
		if model.stop.reason then pause:Disable() else pause:Enable() end
		pause.tip = { title = model.stop.title, body = model.stop.body, reason = model.stop.reason }
	end
	return metrics.top + metrics.header
end

local function DrawChips(model, y, metrics)
	if not model.chips or model.compact then
		for _, chip in pairs(frame.chips) do chip:Hide() end
		return y
	end
	local chips = frame.chips
	SetChip(chips.audio, model.chips.audio, function(self) OpenMenu(self, nil, PartySync:WindowAudioMenu()) end)
	SetChip(chips.playback, model.chips.playback, function(self) OpenMenu(self, nil, PartySync:WindowPlaybackMenu()) end)
	SetChip(chips.quests, model.chips.quests, function()
		local db = PartySync:DB()
		db.autoShare = not db.autoShare
		PartySync:TraceSetting("auto share", db.autoShare)
		PartySync:RefreshWindow()
	end)
	y = y + 2
	local x = metrics.pad
	for _, name in ipairs({ "audio", "playback", "quests" }) do
		Put(chips[name], x, y)
		x = x + chips[name]:GetWidth() + 4
	end
	return y + CHIP_HEIGHT
end

local function DrawMembers(model, y, metrics, inner)
	local count = 0
	for i, member in ipairs(model.members or {}) do
		count = i
		local row = frame.Row(i)
		row.key, row.name = member.key, member.name
		row:SetSize(inner, metrics.row)
		Put(row, metrics.pad, y)
		row.dot:SetTexture(DOTS[member.dot])
		row.dot:SetSize(metrics.dot, metrics.dot)
		row.dot:ClearAllPoints()
		row.dot:SetPoint("LEFT", 0, 0)
		row.tag:SetText(member.tag and (member.colour .. member.tag .. "|r") or "")
		row.tag:ClearAllPoints()
		row.tag:SetPoint("RIGHT", 0, 0)
		row.label:SetFontObject(metrics.nameFont)
		row.label:SetText(member.name .. (member.isMe and (" " .. GREY .. "(" .. L.TAG_YOU .. ")|r") or ""))
		row.label:ClearAllPoints()
		row.label:SetPoint("LEFT", row.dot, "RIGHT", 4, 0)
		row.label:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
		local facts = {}
		if member.state then
			table.insert(facts, member.state .. (member.rtt and format(" %s%d ms", PartySync.DOT, math.floor(member.rtt + 0.5)) or ""))
		end
		if member.tags[1] then table.insert(facts, table.concat(member.tags, PartySync.DOT)) end
		table.insert(facts, member.plays)
		row.tip = { title = row.label:GetText(), body = table.concat(facts, "\n"), hint = L.ROW_HINT }
		row:Show()
		y = y + metrics.row
	end
	HideFrom(frame.rows, count + 1)
	return y
end

-- Grey words where there is nothing else to show: no party, nothing queued.
local function Note(text, y, metrics, inner)
	frame.note:SetWidth(inner)
	frame.note:SetText(text)
	Put(frame.note, metrics.pad, y)
	frame.note:Show()
	return y + Height(frame.note, SUB_HEIGHT)
end

local function DrawLine(model, y, metrics, inner)
	local line, subs = model.line, 0
	frame.line:Hide()
	frame.more:Hide()
	if not line or line.empty then
		HideFrom(frame.subs, 1)
		return line and Note(L.WINDOW_QUEUE_EMPTY, y, metrics, inner) or y
	end
	local row = frame.line
	row:SetSize(inner, LINE_HEIGHT)
	Put(row, metrics.pad, y)
	row.icon:SetShown(line.icon ~= nil)
	if line.icon then row.icon:SetTexture(line.icon) end
	local state = line.colour .. line.state .. "|r"
	if line.here then state = state .. GREY .. PartySync.DOT .. L.LINE_LOCAL .. "|r" end
	if model.compact and line.more > 0 then state = state .. " " .. GREY .. "+" .. line.more .. "|r" end
	row.state:SetText(state)
	row.label:SetText(line.label)
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", line.icon and (ICON_SIZE + 4) or 0, 0)
	row.label:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
	row:Show()
	y = y + LINE_HEIGHT
	if not model.compact then
		for i, sub in ipairs(line.progress) do
			subs = i
			local text = frame.Sub(i)
			text:SetText(GREY .. sub.name .. ":|r " .. sub.colour .. sub.text .. "|r")
			Put(text, metrics.pad + SUB_INDENT, y)
			text:Show()
			y = y + SUB_HEIGHT
		end
		if line.more > 0 then
			frame.more:SetText(GREY .. format(L.WINDOW_MORE_FMT, line.more) .. "|r")
			Put(frame.more, metrics.pad + SUB_INDENT, y)
			frame.more:Show()
			y = y + SUB_HEIGHT
		end
	end
	HideFrom(frame.subs, subs + 1)
	return y
end

local function DrawProblems(model, y, metrics, inner)
	local count = 0
	if not model.compact then
		for i, problem in ipairs(model.problems) do
			count = i
			y = y + FillActionRow(frame.Problem(i), problem.text, problem.actions, inner, y, metrics) + 2
		end
	end
	HideFrom(frame.problems, count + 1)
	return y
end

local function Draw(model)
	local metrics = model.compact and COMPACT or FULL
	local inner = metrics.width - 2 * metrics.pad
	frame:SetWidth(metrics.width)
	local dividers = 0
	local function Divider(y)
		dividers = dividers + 1
		local line = frame.Divider(dividers)
		line:SetWidth(inner)
		Put(line, metrics.pad, y + metrics.gap)
		line:Show()
		return y + 2 * metrics.gap + 1
	end

	local y = DrawHeader(model, metrics)
	y = DrawChips(model, y, metrics)
	y = Divider(y)
	frame.note:Hide()
	if not model.inParty then
		y = Note(L.WINDOW_NO_MEMBERS, y, metrics, inner)
	end
	if model.prompt then
		frame.prompt = frame.prompt or NewActionRow(false)
		y = y + 4 + FillActionRow(frame.prompt, model.prompt.text, model.prompt.actions, inner, y + 4, metrics)
	elseif frame.prompt then
		frame.prompt:Hide()
	end
	y = DrawMembers(model, y, metrics, inner)
	if model.line then
		y = Divider(y)
	end
	y = DrawLine(model, y, metrics, inner)
	if model.problems[1] and not model.compact then
		y = Divider(y)
	end
	y = DrawProblems(model, y, metrics, inner)
	HideFrom(frame.dividers, dividers + 1)
	frame:SetHeight(y + metrics.top)
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
	if show == "always" then return Peers:InParty() or hasProblems end
	if show == "never" then return false end
	if show == "syncing" then return Syncing() or hasProblems end
	-- "problems"
	if hasProblems then
		lastProblemAt = GetTime()
		return true
	end
	return lastProblemAt ~= nil and GetTime() - lastProblemAt < LINGER_SECONDS
end

local function HideHere()
	if frame and frame:IsShown() then
		hidingHere = true
		frame:Hide()
		hidingHere = false
	end
end

function PartySync:RefreshWindow()
	if not self.windowReady then return end
	local model = self:WindowModel()
	-- Kept for /dump, the tests, and what a close by hand has seen.
	self.windowModel = model
	-- The offer to remember a party is worth the window, as a problem is.
	local attention = Attention(model)
	local fresh = false
	for key in pairs(attention) do
		if not (seenAtClose and seenAtClose[key]) then fresh = true end
	end
	if seenAtClose then
		-- Gone since: should it come back, it is new.
		for key in pairs(seenAtClose) do
			if not attention[key] then seenAtClose[key] = nil end
		end
	end
	local want = Wanted(next(attention) ~= nil)
	if want and seenAtClose and not forced and not fresh then
		want = false
	end
	if not want then
		HideHere()
		return
	end
	seenAtClose = nil
	Create()
	Draw(model)
	frame:Show()
end

function PartySync:ShowWindow(shown)
	if shown then
		forced, seenAtClose = true, nil
	else
		Dismiss()
		HideHere()
	end
	self:RefreshWindow()
end

function PartySync:WindowShown()
	return frame ~= nil and frame:IsShown()
end

function PartySync:ToggleWindow()
	self:ShowWindow(not (frame and frame:IsShown()))
end

function PartySync:SetWindowScale(scale)
	DB().scale = scale
	if frame then frame:SetScale(scale) end
end

function PartySync:SetWindowCompact(on)
	DB().compact = on and true or false
	self:TraceSetting("compact window", DB().compact)
	self:RefreshWindow()
end

--- Once the saved variables are in.
function PartySync:SetupWindow()
	if self.windowReady then return end
	self.windowReady = true
	self:RefreshWindow()
end
