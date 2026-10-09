-- The settings page: Spoken > Party Sync.
--
-- Nested under Spoken's own entry, after Quests, Books and Zones, through
-- Spoken:AddSettingsPage, and laid out by the UI/Layout.lua every Spoken addon carries a copy of,
-- so it reads like the others. A top-level entry of its own where the player cannot nest pages.
-- Every setting here also has a slash command.
--
-- The party block and the usual party block are custom frames: a row per character with its
-- own buttons, which the layout's rows of one control each cannot draw.

local _, PartySync = ...

local Peers, Room, Autoform, L = PartySync.Peers, PartySync.Room, PartySync.Autoform, PartySync.L

-- The game's settings list sets its rows 25 in from the canvas's left.
local INDENT = 25
local ICON = [[Interface\Icons\INV_Misc_GroupNeedMore]]
-- The party block: this character's row, a row per member, then the name box and Invite. Two or
-- three members is the case this is for; past four the window and /sps members list them all.
local MEMBER_ROWS = 4
local ROWS = MEMBER_ROWS + 1
local ROW_HEIGHT = 22
local MEMBERS_HEIGHT = ROWS * ROW_HEIGHT + 34
-- The usual party block: a row per listed character, then the name box and Add.
local LIST_ROWS = 5
local LIST_HEIGHT = LIST_ROWS * ROW_HEIGHT + 34

local panel, layout, membersBlock, listBlock, category

local function DB()
	return PartySync:DB()
end

local STATE_WORDS = { online = L.STATE_ONLINE, lost = L.STATE_LOST, offline = L.STATE_OFFLINE }

local function SetEnabled(button, enabled)
	if enabled then button:Enable() else button:Disable() end
end

local function Tooltip(frame, text)
	frame:SetScript("OnEnter", function(self)
		local tip = text
		if type(tip) == "function" then tip = tip() end
		if type(tip) ~= "string" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tip, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	if frame.SetMotionScriptsWhileDisabled then frame:SetMotionScriptsWhileDisabled(true) end
end

local function RowButton(block, row, i, x, width, label, tooltip, onClick)
	local button = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
	button:SetSize(width, 20)
	button:SetPoint("TOPLEFT", x, -(i - 1) * ROW_HEIGHT)
	button:SetText(label)
	button:SetScript("OnClick", function() if row.key then onClick(row) end end)
	Tooltip(button, function() return row.key and (type(tooltip) == "function" and tooltip(row) or tooltip) or nil end)
	return button
end

local function NameBox(block, y, tooltip, buttonLabel, buttonTooltip, onSend)
	local box = CreateFrame("EditBox", nil, block, "InputBoxTemplate")
	box:SetSize(200, 20)
	box:SetPoint("TOPLEFT", 18, y)
	box:SetAutoFocus(false)
	if box.SetMaxLetters then box:SetMaxLetters(60) end
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	Tooltip(box, tooltip)
	local button = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
	button:SetSize(90, 22)
	button:SetPoint("LEFT", box, "RIGHT", 12, 0)
	button:SetText(buttonLabel)
	local function Send()
		local name = box:GetText()
		if not name or name:gsub("%s", "") == "" then return end
		onSend(name)
		box:SetText("")
		box:ClearFocus()
	end
	button:SetScript("OnClick", Send)
	box:SetScript("OnEnterPressed", Send)
	Tooltip(button, buttonTooltip)
	return box, button
end

--------------------------------------------------------------------------------
-- The party block
--------------------------------------------------------------------------------

local function UpdateMembers()
	if not membersBlock then return end
	local keys = Peers:MemberKeys()
	membersBlock.none:SetShown(keys[1] == nil)
	local me = PartySync:MyKey()
	local summary = Room:Summary()
	local leads = Peers:AmLeader()
	for i, row in ipairs(membersBlock.rows) do
		local key = keys[i]
		if key then
			local isMe = key == me
			local peer = Peers.list[key]
			local state = peer and peer.state
			row.key, row.isMe = key, isMe
			local tags = {}
			if Peers:IsLeader(key) then table.insert(tags, L.TAG_LEAD) end
			if Room:Voices(key) then table.insert(tags, L.TAG_SOUND) end
			if Room:Decides(key) then table.insert(tags, L.TAG_OWN_SOUND) end
			local tagText = tags[1] and ("  |cffffd060" .. table.concat(tags, ", ") .. "|r") or ""
			if isMe then
				row.label:SetText(format("%s  |cff909090(%s)|r%s", PartySync:ShortName(PartySync:UnitChatName("player")), L.TAG_YOU, tagText))
			else
				row.label:SetText(format("%s  |cff909090%s|r%s", Peers:MemberName(key), STATE_WORDS[state] or L.STATE_UNKNOWN, tagText))
			end
			row.label:Show()
			row.lead:Show()
			row.sound:Show()
			-- The leader's to press, and nothing to choose where it is already so.
			SetEnabled(row.lead, leads and not Peers:IsLeader(key))
			SetEnabled(row.sound, leads and summary ~= key)
			row.remove:SetShown(not isMe)
			SetEnabled(row.remove, leads)
		else
			row.key, row.isMe = nil, nil
			row.label:Hide()
			row.lead:Hide()
			row.sound:Hide()
			row.remove:Hide()
		end
	end
	SetEnabled(membersBlock.invite, Peers:MayInvite())
	SetEnabled(membersBlock.box, Peers:MayInvite())
end

local function MembersBlock(parent)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(520, MEMBERS_HEIGHT)

	block.none = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	block.none:SetPoint("TOPLEFT", 12, -4)
	block.none:SetWidth(480)
	block.none:SetJustifyH("LEFT")
	block.none:SetText(L.OPT_MEMBERS_NONE)

	local function LeaderOr(text)
		return function() return Peers:WhyNotLeader() or text end
	end
	block.rows = {}
	for i = 1, ROWS do
		local row = {}
		row.label = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("TOPLEFT", 12, -4 - (i - 1) * ROW_HEIGHT)
		row.lead = RowButton(block, row, i, 280, 70, L.OPT_LEAD_BTN, LeaderOr(L.OPT_LEAD_BTN_TIP), function(r)
			local ok, why = Peers:PassLead(r.key)
			if not ok then PartySync:Print("%s", tostring(why)) end
		end)
		row.sound = RowButton(block, row, i, 354, 70, L.OPT_SOUND_BTN, LeaderOr(L.OPT_SOUND_BTN_TIP), function(r)
			local ok, why = Room:SetAll(r.key)
			if not ok then PartySync:Print("%s", tostring(why)) end
		end)
		row.remove = RowButton(block, row, i, 428, 90, L.OPT_REMOVE, LeaderOr(nil), function(r)
			local name = Peers:MemberName(r.key)
			local ok, why = Peers:RemoveMember(r.key)
			PartySync:Print(ok and "%s is out of your Spoken party" or "%s: %s", PartySync:ShortName(name), tostring(why))
			UpdateMembers()
		end)
		block.rows[i] = row
	end

	block.box, block.invite = NameBox(block, -(ROWS * ROW_HEIGHT) - 6, L.OPT_NAME_TIP, L.OPT_INVITE,
		function() return Peers:WhyNotLeader() or L.OPT_INVITE_TIP end, function(name)
			local sent, answer = Peers:Invite(name)
			PartySync:Print("invitation to %s: %s", PartySync:ShortName(name), sent and "sent" or tostring(answer))
		end)
	return block
end

--------------------------------------------------------------------------------
-- The usual party block
--------------------------------------------------------------------------------

local function UpdateList()
	if not listBlock then return end
	local list = Autoform:List()
	local keys = Autoform:Keys()
	listBlock.none:SetShown(keys[1] == nil)
	for i, row in ipairs(listBlock.rows) do
		local key = keys[i]
		local entry = key and list.members[key]
		if entry then
			local peer = Peers.list[key]
			local state = peer and peer.state
			row.key = key
			row.label:SetText(format("%s  |cff909090%s|r%s", entry.name or key, STATE_WORDS[state] or L.STATE_UNKNOWN,
				list.leader == key and ("  |cffffd060" .. L.TAG_LEAD .. "|r") or ""))
			row.label:Show()
			row.auto:SetChecked(entry.autoAccept and true or false)
			row.auto:Show()
			row.autoLabel:Show()
			row.remove:Show()
		else
			row.key = nil
			row.label:Hide()
			row.auto:Hide()
			row.autoLabel:Hide()
			row.remove:Hide()
		end
	end
	-- +N, where the list is longer than the block; /sps list has them all.
	listBlock.more:SetText(#keys > LIST_ROWS and format("+%d", #keys - LIST_ROWS) or "")
end

local function ListBlock(parent)
	local block = CreateFrame("Frame", nil, parent)
	block:SetSize(520, LIST_HEIGHT)

	block.none = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	block.none:SetPoint("TOPLEFT", 12, -4)
	block.none:SetWidth(480)
	block.none:SetJustifyH("LEFT")
	block.none:SetText(L.OPT_LIST_NONE)
	block.more = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	block.more:SetPoint("TOPLEFT", 12, -4 - LIST_ROWS * ROW_HEIGHT)

	block.rows = {}
	for i = 1, LIST_ROWS do
		local row = {}
		row.label = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("TOPLEFT", 12, -4 - (i - 1) * ROW_HEIGHT)
		row.auto = CreateFrame("CheckButton", nil, block, "UICheckButtonTemplate")
		row.auto:SetSize(22, 22)
		row.auto:SetPoint("TOPLEFT", 300, -(i - 1) * ROW_HEIGHT + 1)
		row.auto:SetScript("OnClick", function(self)
			if row.key then Autoform:SetAutoAccept(row.key, self:GetChecked() and true or false) end
		end)
		Tooltip(row.auto, L.OPT_LIST_AUTO_TIP)
		row.autoLabel = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.autoLabel:SetPoint("LEFT", row.auto, "RIGHT", 2, 0)
		row.autoLabel:SetText(L.OPT_LIST_AUTO)
		row.remove = RowButton(block, row, i, 428, 90, L.OPT_REMOVE, nil, function(r)
			local name = Autoform:Entry(r.key) and Autoform:Entry(r.key).name or r.key
			if Autoform:Remove(r.key) then
				PartySync:Print("%s is out of your usual party", PartySync:ShortName(name))
			end
			UpdateList()
		end)
		block.rows[i] = row
	end

	block.box, block.add = NameBox(block, -(LIST_ROWS * ROW_HEIGHT) - 6, L.OPT_NAME_TIP, L.OPT_LIST_ADD,
		L.OPT_LIST_ADD_TIP, function(name)
			if Autoform:Add(name) then
				PartySync:Print("%s is in your usual party", PartySync:ShortName(name))
			end
			UpdateList()
		end)
	return block
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local CONTROLS = { leader = L.CONTROLS_LEADER, anyone = L.CONTROLS_ANYONE, nobody = L.CONTROLS_NOBODY }
local SHARE = { anyone = L.SHARE_ANYONE, leader = L.CONTROLS_LEADER, nobody = L.CONTROLS_NOBODY }
local SHOW = { always = L.SHOW_ALWAYS, syncing = L.SHOW_SYNCING, problems = L.SHOW_PROBLEMS, never = L.SHOW_NEVER }

--- A rule's row: read from the rules in force, written through Peers (the leader's in a party),
--- greyed for a member who does not lead.
local function RuleRow(row)
	layout:Requires(row, function() return Peers:MayInvite() end, L.OPT_RULES_LEADER)
	return row
end

-- The game's plus and minus before "Advanced", as its own lists show what opens and closes.
local PLUS = [[|TInterface\Buttons\UI-PlusButton-Up:14:14|t ]]
local MINUS = [[|TInterface\Buttons\UI-MinusButton-Up:14:14|t ]]

--- An Advanced button and the rows `build()` adds under it, shown only while it is open. While
--- `differs()`, the setting above reads Mixed: they show whatever the button says, so Mixed is
--- never left unexplained, and the button is greyed.
local function Accordion(tip, differs, build)
	local open = false
	local function Shown() return open or differs() end
	local button = layout:Button(L.OPT_ADVANCED, nil, function()
		open = not open
		layout:Refresh()
	end, tip)
	layout:Requires(button, function() return not differs() end, L.OPT_ADVANCED_MIXED)
	-- Labelled after Button sized and indexed it by the plain word, which search finds.
	local function Label() button:SetText((Shown() and MINUS or PLUS) .. L.OPT_ADVANCED) end
	layout:OnRefresh(Label)
	Label()
	layout:Indent()
	for _, row in ipairs(build()) do layout:ShowWhen(row, Shown) end
	layout:Outdent()
	return button
end

local function SyncBox(kind, label, tooltip)
	RuleRow(layout:Checkbox(label, tooltip,
		function() return (Peers:Rules().sync or {})[kind] ~= false end,
		function(value) Peers:SetRule("sync", kind, value and true or false) end))
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
	-- Reachable from /dump and the tests.
	self.memberRows = membersBlock.rows
	layout:Custom(membersBlock, MEMBERS_HEIGHT)
	layout:Requires(layout:Button(L.OPT_LEAVE, nil, function()
		if not Peers:Leave() then PartySync:Print("you are in no Spoken party") end
		UpdateMembers()
	end, L.OPT_LEAVE_TIP), function() return Peers:InParty() end, L.OPT_IN_PARTY)

	layout:Section(L.OPT_SECTION_WINDOW)
	layout:Dropdown(L.OPT_WINDOW_SHOW, L.OPT_WINDOW_SHOW_TIP, { "always", "syncing", "problems", "never" },
		function() return DB().window.show end,
		function(value) DB().window.show = value; PartySync:RefreshWindow() end, refresh,
		function(value) return SHOW[value] or value end)
	layout:Slider(L.OPT_WINDOW_SCALE, PartySync.MIN_WINDOW_SCALE, 1.5, 0.05,
		function() return DB().window.scale or 1 end,
		function(value) PartySync:SetWindowScale(value) end, nil, SpokenLayout.Percent)
	layout:Button(L.OPT_WINDOW_OPEN, nil, function() PartySync:ShowWindow(true) end)

	layout:Section(L.OPT_SECTION_RULES)
	layout:Note(L.OPT_RULES_NOTE)
	RuleRow(layout:Dropdown(L.OPT_CONTROLS, L.OPT_CONTROLS_TIP, { "leader", "anyone", "nobody" },
		function() return Peers:Rules().controls or "anyone" end,
		function(value) Peers:SetRule("controls", value) end, refresh,
		function(value) return CONTROLS[value] or value end))
	RuleRow(layout:Dropdown(L.OPT_SHARE, L.OPT_SHARE_TIP, { "anyone", "leader", "nobody" },
		function() return Peers:Rules().share or "anyone" end,
		function(value) Peers:SetRule("share", value) end, refresh,
		function(value) return SHARE[value] or value end))
	layout:Note(L.OPT_WHO_NOTE)
	-- Every channel at once, then each. "Mixed" and "every computer but ..." are listed only while
	-- they are the value, for the box to show it; choosing "Mixed" changes nothing.
	RuleRow(layout:Dropdown(L.OPT_ALL_SOUND, L.OPT_ALL_SOUND_TIP,
		function() return Room:Choices(Room:Summary()) end,
		function() return Room:Summary() end, function(value) if value ~= "mixed" then Room:SetAll(value) end end, refresh,
		function(value) return Room:Describe(value) end))
	self.rulesAdvanced = Accordion(L.OPT_ADVANCED_RULE_TIP, function() return Room:Summary() == "mixed" end, function()
		local rows = {}
		for _, channel in ipairs(Room.CHANNELS) do
			table.insert(rows, RuleRow(layout:Dropdown(Room:Name(channel), Room:Tip(channel),
				function() return Room:Choices(Room:Owner(channel)) end,
				function() return Room:Owner(channel) end, function(value) Room:Set(channel, value) end, refresh,
				function(value) return Room:Describe(value) end)))
		end
		return rows
	end)
	layout:Note(L.OPT_SYNC_NOTE)
	layout:Indent()
	SyncBox("quests", L.OPT_SYNC_QUESTS, L.OPT_SYNC_QUESTS_TIP)
	SyncBox("gossip", L.OPT_SYNC_GOSSIP, L.OPT_SYNC_GOSSIP_TIP)
	SyncBox("zones", L.OPT_SYNC_ZONES, L.OPT_SYNC_ZONES_TIP)
	SyncBox("books", L.OPT_SYNC_BOOKS, L.OPT_SYNC_BOOKS_TIP)
	layout:Outdent()

	layout:Section(L.OPT_SECTION_SOUND)
	layout:Dropdown(L.OPT_FOLLOW, L.OPT_FOLLOW_TIP, function()
			local choices = Room:OwnChoices()
			if Room:OwnSummary() == "mixed" then table.insert(choices, "mixed") end
			return choices
		end,
		function() return Room:OwnSummary() end, function(value) if value ~= "mixed" then Room:SetOwnAll(value) end end,
		refresh, function(value) return Room:DescribeFollow(value) end)
	self.ownAdvanced = Accordion(L.OPT_ADVANCED_OWN_TIP, function() return Room:OwnSummary() == "mixed" end, function()
		local rows = {}
		for _, channel in ipairs(Room.CHANNELS) do
			table.insert(rows, layout:Dropdown(Room:Name(channel), Room:Tip(channel), Room:OwnChoices(),
				function() return Room:OwnValue(channel) end, function(value) Room:SetOwnChannel(channel, value) end, refresh,
				function(value) return Room:DescribeOwn(value, channel) end))
		end
		return rows
	end)

	layout:Section(L.OPT_SECTION_LIST)
	layout:Note(L.OPT_LIST_NOTE)
	listBlock = ListBlock(content)
	self.listRows = listBlock.rows
	layout:Custom(listBlock, LIST_HEIGHT)
	local remember = layout:Button(L.OPT_REMEMBER, nil, function()
		Autoform:Remember()
		UpdateList()
		refresh()
	end, L.OPT_REMEMBER_TIP)
	layout:Requires(remember, function() return Peers:InParty() end, L.OPT_IN_PARTY)
	layout:Requires(remember, function() return not Autoform:Remembered() end, L.REMEMBERED_ALREADY)
	layout:Note(L.OPT_REMEMBER_HINT)

	layout:Section(L.OPT_SECTION_QUESTS)
	local share = layout:Checkbox(L.OPT_AUTO_SHARE, L.OPT_AUTO_SHARE_TIP,
		function() return DB().autoShare end,
		function(value) PartySync:SetAutoShare(value) end)
	layout:Requires(share, function() return (Peers:Rules().share or "anyone") ~= "nobody" end, L.SHARE_NOBODY)
	layout:Requires(share, function() return Peers:MayShare() end, L.SHARE_LEADER)
	layout:Checkbox(L.OPT_AUTO_ACCEPT, L.OPT_AUTO_ACCEPT_TIP,
		function() return DB().autoAccept end,
		function(value) DB().autoAccept = value and true or false; PartySync:TraceSetting("auto accept", DB().autoAccept) end)

	layout:Section(L.OPT_SECTION_DIAGNOSTICS)
	local ping = layout:Button(L.OPT_PING, nil, function() Peers:PingMembers(); refresh() end, L.OPT_PING_TIP)
	layout:Requires(ping, function() return Peers:InParty() end, L.OPT_IN_PARTY)
	-- The round trips beside the button, as they come in, not only in chat.
	local pingResult = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pingResult:SetPoint("LEFT", ping, "RIGHT", 10, 0)
	self.pingResult = pingResult
	layout:OnRefresh(function() pingResult:SetText(Peers:InParty() and Peers:PingSummary() or "") end)
	layout:Note(L.OPT_COMMANDS)

	local resetDone
	local reset = layout:StartOver(L.OPT_SECTION_START_OVER, L.OPT_RESET_PAGE, function()
		SpokenLayout.Confirm(L.OPT_RESET_CONFIRM, L.OPT_RESET, L.OPT_CANCEL, function()
			PartySync:ResetOptions()
			Peers:Announce()
			layout:Refresh()
			resetDone:SetText(L.OPT_RESET_DONE)
			C_Timer.After(3, function() resetDone:SetText("") end)
		end)
	end, L.OPT_RESET_PAGE_TIP)
	-- "Reset." for a moment beside whichever button it was: the header's Defaults, or the page's own.
	resetDone = reset:GetParent():CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	if reset == layout.defaults then
		resetDone:SetPoint("RIGHT", reset, "LEFT", -8, 0)
	else
		resetDone:SetPoint("LEFT", reset, "RIGHT", 10, 0)
	end

	-- Without the player there is nothing to sync, and every switch says so rather than looking
	-- live and doing nothing.
	if layout.RequiresAll then
		layout:RequiresAll(function() return PartySync:PlayerAvailable() end, L.REASON_NO_PLAYER)
	end
	UpdateMembers()
	UpdateList()
	layout:Refresh()
	content:SetScript("OnShow", function() UpdateMembers(); UpdateList(); refresh() end)
	scroller:SetContentHeight(layout:Height() + 40)

	local page = Spoken and Spoken.AddSettingsPage and Spoken:AddSettingsPage(panel, L.PAGE_TITLE, 4, layout, scroller)
	if page then
		self.optionsPage = page
	else
		category = Settings.RegisterCanvasLayoutCategory(panel, L.TITLE)
		Settings.RegisterAddOnCategory(category)
	end
	self.optionsPanel = panel
	self.optionsLayout = layout
	self:SetupDeveloperRows()
end

--- The party's logs, on Spoken's Developer page under Spoken's own debug log: collecting the
--- members' logs to read beside this one, and clearing them all at once. Where Spoken has the
--- page and the log.
function PartySync:SetupDeveloperRows()
	local Spoken = _G.Spoken
	if self.developerRows or not (Spoken and Spoken.AddDeveloperSettings and PartySync.LogBook:Available()) then
		return
	end
	self.developerRows = true
	Spoken:AddDeveloperSettings(function(page)
		page:Section(L.TITLE)
		page:Button(L.OPT_LOGS_PULL, nil, function() PartySync.LogBook:Pull() end, L.OPT_LOGS_PULL_TIP)
		page:Button(L.OPT_LOGS_CLEAR_ALL, nil, function()
			local asked = PartySync.LogBook:ClearParty()
			PartySync:Print("debug log cleared here; asked %d member%s online to clear theirs", asked, asked == 1 and "" or "s")
		end, L.OPT_LOGS_CLEAR_ALL_TIP)
		page:Note(L.OPT_LOGS_NOTE)
	end)
end

--- Under Spoken's minimap button, a section of its own: the window and this page.
function PartySync:SetupMinimapEntries()
	local Spoken = _G.Spoken
	local menu = Spoken and Spoken.Minimap
	if self.minimapEntries or not (menu and menu.AddSection and menu.AddEntry) then
		return
	end
	self.minimapEntries = true
	menu:AddSection("partysync", L.TITLE, 10)
	menu:AddEntry("partysync", { id = "window", text = L.MENU_OPEN_WINDOW, order = 1,
		onClick = function() PartySync:ShowWindow(true) end })
	menu:AddEntry("partysync", { id = "settings", text = L.MENU_SETTINGS, order = 2,
		onClick = function() PartySync:OpenOptions() end })
end

--- Redraw what may have changed: who is in the party and online, who leads, the list. Only
--- while the page shows.
function PartySync:RefreshOptions()
	if not (panel and panel.IsVisible and panel:IsVisible()) then
		return
	end
	UpdateMembers()
	UpdateList()
	if layout then layout:Refresh() end
end

function PartySync:OpenOptions()
	if self.optionsPage and self.optionsPage.Open and self.optionsPage.Open() then return end
	local target = category or (self.optionsPage and self.optionsPage.category)
	if not (SpokenLayout and SpokenLayout.OpenCategory(target)) then
		self:Print("open Game Menu -> Options -> AddOns -> Spoken -> Party Sync")
	end
end
