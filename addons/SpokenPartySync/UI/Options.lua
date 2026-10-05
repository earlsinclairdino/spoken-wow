-- The settings page: Spoken > Party Sync.
--
-- Nested under Spoken's own entry, after Quests, Books and Zones, through
-- Spoken:AddSettingsPage, and laid out by the UI/Layout.lua every Spoken addon carries a copy of,
-- so it reads like the others. A top-level entry of its own where the player cannot nest pages.
-- Every setting here also has a slash command.

local _, PartySync = ...

local Peers, Room, L = PartySync.Peers, PartySync.Room, PartySync.L

-- The game's settings list sets its rows 25 in from the canvas's left.
local INDENT = 25
local ICON = [[Interface\Icons\INV_Misc_GroupNeedMore]]
-- The party block: a row per member, then the name box and Invite. Two or three members is the
-- case this is for; past four the window and /sps members list them all.
local MEMBER_ROWS = 4
local ROW_HEIGHT = 22
local MEMBERS_HEIGHT = MEMBER_ROWS * ROW_HEIGHT + 34

local panel, layout, membersBlock, category

local function DB()
	return PartySync:DB()
end

--------------------------------------------------------------------------------
-- The party block
--------------------------------------------------------------------------------

local STATE_WORDS = { online = L.STATE_ONLINE, lost = L.STATE_LOST, offline = L.STATE_OFFLINE }

local function UpdateMembers()
	if not membersBlock then return end
	local keys = {}
	for key in Peers:Members() do table.insert(keys, key) end
	table.sort(keys)
	membersBlock.none:SetShown(keys[1] == nil)
	for i, row in ipairs(membersBlock.rows) do
		local key = keys[i]
		if key then
			local peer = Peers.list[key]
			local state = peer and peer.state
			row.key = key
			row.label:SetText(format("%s  |cff909090%s|r", Peers:MemberName(key), STATE_WORDS[state] or L.STATE_UNKNOWN))
			row.label:Show()
			row.remove:Show()
		else
			row.key = nil
			row.label:Hide()
			row.remove:Hide()
		end
	end
end

local function MembersBlock(parent)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(520, MEMBERS_HEIGHT)

	block.none = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	block.none:SetPoint("TOPLEFT", 12, -4)
	block.none:SetWidth(480)
	block.none:SetJustifyH("LEFT")
	block.none:SetText(L.OPT_MEMBERS_NONE)

	block.rows = {}
	for i = 1, MEMBER_ROWS do
		local row = {}
		row.label = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("TOPLEFT", 12, -4 - (i - 1) * ROW_HEIGHT)
		row.remove = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
		row.remove:SetSize(90, 20)
		row.remove:SetPoint("TOPLEFT", 300, -(i - 1) * ROW_HEIGHT)
		row.remove:SetText(L.OPT_REMOVE)
		row.remove:SetScript("OnClick", function()
			if row.key then
				local name = Peers:MemberName(row.key)
				Peers:RemoveMember(row.key)
				PartySync:Print("%s left your Spoken party", PartySync:ShortName(name))
				UpdateMembers()
			end
		end)
		block.rows[i] = row
	end

	local box = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
	box:SetSize(200, 20)
	box:SetPoint("TOPLEFT", 18, -(MEMBER_ROWS * ROW_HEIGHT) - 6)
	box:SetAutoFocus(false)
	if box.SetMaxLetters then box:SetMaxLetters(60) end
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.OPT_NAME_TIP, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", GameTooltip_Hide)

	local invite = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
	invite:SetSize(90, 22)
	invite:SetPoint("LEFT", box, "RIGHT", 12, 0)
	invite:SetText(L.OPT_INVITE)
	local function Send()
		local name = box:GetText()
		if not name or name:gsub("%s", "") == "" then return end
		local sent, answer = Peers:Invite(name)
		PartySync:Print("invitation to %s: %s", PartySync:ShortName(name), sent and "sent" or tostring(answer))
		box:SetText("")
		box:ClearFocus()
	end
	invite:SetScript("OnClick", Send)
	box:SetScript("OnEnterPressed", Send)
	invite:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.OPT_INVITE_TIP, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	invite:SetScript("OnLeave", GameTooltip_Hide)
	block.box, block.invite = box, invite
	return block
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local LEAD = { auto = L.LEAD_AUTO, me = L.LEAD_ME, follow = L.LEAD_FOLLOW }
local CONTROLS = { leader = L.CONTROLS_LEADER, anyone = L.CONTROLS_ANYONE, nobody = L.CONTROLS_NOBODY }
local SHOW = { always = L.SHOW_ALWAYS, syncing = L.SHOW_SYNCING, problems = L.SHOW_PROBLEMS, never = L.SHOW_NEVER }

local function SyncBox(kind, label, tooltip)
	layout:Checkbox(label, tooltip,
		function() return DB().sync[kind] ~= false end,
		function(value) DB().sync[kind] = value and true or false end)
end

function PartySync:SetupOptions()
	if panel then
		return
	end
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		self:Print("|cffffcc00Settings API missing; settings page unavailable (use /sps)|r")
		return
	end
	if not SpokenLayout then
		-- Carried, not shared, so this can only be a broken install.
		self:Print("|cffffcc00UI/Layout.lua did not load; settings page unavailable (use /sps)|r")
		return
	end

	panel = CreateFrame("Frame")
	panel.name = L.TITLE
	-- Laid out in the scroller's content frame: the settings canvas neither scrolls nor clips.
	local scroller = SpokenLayout.Scroll(panel)
	local content = scroller.child
	layout = SpokenLayout.New(content, INDENT, -16)
	layout:Header(L.PAGE_TITLE, L.OPT_NOTE, nil, ICON)
	local Spoken = _G.Spoken
	if Spoken and Spoken.SettingsStyle and Spoken:SettingsStyle() == "pages" then
		layout:HideHeader()
		layout:Intro(ICON, L.PAGE_TITLE)
	end
	local refresh = function() layout:Refresh() end

	layout:Section(L.OPT_SECTION_MEMBERS)
	membersBlock = MembersBlock(content)
	layout:Custom(membersBlock, MEMBERS_HEIGHT)
	layout:Dropdown(L.OPT_LEAD, L.OPT_LEAD_TIP, { "auto", "me", "follow" },
		function() return DB().lead end,
		function(value) DB().lead = value; Peers:Announce() end, refresh,
		function(value) return LEAD[value] or value end)

	layout:Section(L.OPT_SECTION_SYNC)
	SyncBox("quests", L.OPT_SYNC_QUESTS, L.OPT_SYNC_QUESTS_TIP)
	SyncBox("gossip", L.OPT_SYNC_GOSSIP, L.OPT_SYNC_GOSSIP_TIP)
	SyncBox("zones", L.OPT_SYNC_ZONES, L.OPT_SYNC_ZONES_TIP)
	SyncBox("books", L.OPT_SYNC_BOOKS, L.OPT_SYNC_BOOKS_TIP)

	layout:Section(L.OPT_SECTION_QUESTS)
	layout:Checkbox(L.OPT_AUTO_SHARE, L.OPT_AUTO_SHARE_TIP,
		function() return DB().autoShare end, function(value) DB().autoShare = value and true or false end)
	layout:Checkbox(L.OPT_AUTO_ACCEPT, L.OPT_AUTO_ACCEPT_TIP,
		function() return DB().autoAccept end, function(value) DB().autoAccept = value and true or false end)

	layout:Section(L.OPT_SECTION_CONTROLS)
	layout:Dropdown(L.OPT_CONTROLS, L.OPT_CONTROLS_TIP, { "leader", "anyone", "nobody" },
		function() return DB().controls end, function(value) DB().controls = value end, refresh,
		function(value) return CONTROLS[value] or value end)

	layout:Section(L.OPT_SECTION_ROOM)
	layout:Dropdown(L.OPT_ROOM, L.OPT_ROOM_TIP, function() return Room:Choices() end,
		function() return DB().roomSpeaker or "" end, function(value) Room:Set(value) end, refresh,
		function(value) return Room:Describe(value) end)

	layout:Section(L.OPT_SECTION_WINDOW)
	layout:Dropdown(L.OPT_WINDOW_SHOW, L.OPT_WINDOW_SHOW_TIP, { "always", "syncing", "problems", "never" },
		function() return DB().window.show end,
		function(value) DB().window.show = value; PartySync:RefreshWindow() end, refresh,
		function(value) return SHOW[value] or value end)
	layout:Slider(L.OPT_WINDOW_SCALE, 0.7, 1.5, 0.05,
		function() return DB().window.scale or 1 end,
		function(value) PartySync:SetWindowScale(value) end, nil, SpokenLayout.Percent)
	layout:Button(L.OPT_WINDOW_OPEN, nil, function() PartySync:ShowWindow(true) end)

	layout:Section(L.OPT_SECTION_DIAGNOSTICS)
	layout:Button(L.OPT_PING, nil, function() Peers:PingMembers() end, L.OPT_PING_TIP)
	layout:Button(L.OPT_LOGS_PULL, nil, function() PartySync.LogBook:Pull() end, L.OPT_LOGS_PULL_TIP)
	layout:Button(L.OPT_LOGS_SHOW, nil, function() PartySync.LogBook:Show() end, L.OPT_LOGS_SHOW_TIP)
	layout:Button(L.OPT_LOGS_CLEAR, nil, function()
		PartySync.LogBook:Clear()
		PartySync:Print("debug log cleared here; a new session starts")
	end, L.OPT_LOGS_CLEAR_TIP)
	layout:Button(L.OPT_LOGS_CLEAR_ALL, nil, function()
		local asked = PartySync.LogBook:ClearParty()
		PartySync:Print("debug log cleared here; asked %d member%s online to clear theirs", asked, asked == 1 and "" or "s")
	end, L.OPT_LOGS_CLEAR_ALL_TIP)
	layout:Checkbox(L.OPT_LOG, L.OPT_LOG_TIP,
		function() return DB().logTraffic end, function(value) DB().logTraffic = value and true or false end)
	layout:Note(L.OPT_COMMANDS)

	layout:StartOver(L.OPT_SECTION_START_OVER, L.OPT_RESET_PAGE, function()
		SpokenLayout.Confirm(L.OPT_RESET_CONFIRM, L.OPT_RESET, L.OPT_CANCEL, function()
			PartySync:ResetOptions()
			Peers:Announce()
			layout:Refresh()
		end)
	end, L.OPT_RESET_PAGE_TIP)

	-- Without the player there is nothing to sync, and every switch says so rather than looking
	-- live and doing nothing.
	if layout.RequiresAll then
		layout:RequiresAll(function() return PartySync:PlayerAvailable() end, L.REASON_NO_PLAYER)
	end
	UpdateMembers()
	layout:Refresh()
	content:SetScript("OnShow", function() UpdateMembers(); refresh() end)
	scroller:SetContentHeight(layout:Height() + 40)

	local page = Spoken and Spoken.AddSettingsPage and Spoken:AddSettingsPage(panel, L.PAGE_TITLE, 4, layout, scroller)
	if page then
		self.optionsPage = page
	else
		category = Settings.RegisterCanvasLayoutCategory(panel, L.TITLE)
		Settings.RegisterAddOnCategory(category)
	end
	self.optionsPanel = panel
end

--- Redraw what may have changed: who is in the party and online. Only while the page shows.
function PartySync:RefreshOptions()
	if not (panel and panel.IsVisible and panel:IsVisible()) then
		return
	end
	UpdateMembers()
	if layout then layout:Refresh() end
end

function PartySync:OpenOptions()
	if self.optionsPage and self.optionsPage.Open and self.optionsPage.Open() then return end
	local target = category or (self.optionsPage and self.optionsPage.category)
	if not (SpokenLayout and SpokenLayout.OpenCategory(target)) then
		self:Print("open Game Menu -> Options -> AddOns -> Spoken -> Party Sync")
	end
end
