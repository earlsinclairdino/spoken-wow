-- SpokenZones -- the lore panel docked to the side of the world map.
--
-- Shows lore for the zone the map is displaying, or for a subzone the player
-- clicked (see UI/SubzoneClick.lua), with a link back to the zone.
--
-- Also the home for the contribute button (UI/ReportButton.lua's CreateContributeButton):
-- this panel is up, next to the map, for as long as a player might be standing somewhere with
-- no lore, which the lore window is not -- that one only opens on request. The button's own
-- visibility answers a different question than everything else on this panel (the player's
-- location, not what is displayed here), so it is not part of Refresh below.

local ADDON_NAME, SpokenZones = ...
local L = SpokenZones.L

local PADDING = 16
local INFO_LINE_HEIGHT = 16

-- Horizontal room kept clear on the header row for the play button, which sits in
-- the top-right corner. Wider than the button so a long zone name never crowds it.
local AUDIO_RESERVE = 66

-- The same idea on the footer row, for the report button. The credit line is short
-- and the button is a rare click, so they share a row rather than costing the body
-- another one.
local REPORT_RESERVE = 64

-- Room for the contribute button beside the report button, on the same footer row.
local CONTRIBUTE_RESERVE = 138

local panel, header, infoLine, body, footer, audioButton, reportButton, contributeButton

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function BuildPanel()
	local width = SpokenZones:Get("panelWidth")

	panel = CreateFrame("Frame", "SpokenZonesPanel", WorldMapFrame, "BackdropTemplate")
	panel:SetWidth(width)
	panel:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	panel:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10)
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})

	header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -PADDING)
	header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(PADDING + AUDIO_RESERVE), -PADDING)
	header:SetJustifyH("LEFT")
	header:SetWordWrap(true)

	audioButton = SpokenZones:CreateAudioButton(panel)
	audioButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, -(PADDING - 2))

	-- One fixed-height slot under the header, used either as a caption or as the
	-- "back to zone" link. Keeping it always present means the scroll frame below
	-- never has to be re-anchored as the content type changes.
	infoLine = CreateFrame("Button", nil, panel)
	infoLine:SetHeight(INFO_LINE_HEIGHT)
	infoLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
	infoLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
	infoLine.text = infoLine:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	infoLine.text:SetAllPoints()
	infoLine.text:SetJustifyH("LEFT")
	infoLine:SetScript("OnClick", function()
		SpokenZones:ClearSubzone()
	end)
	infoLine:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			self.text:SetTextColor(1, 1, 1)
		end
	end)
	infoLine:SetScript("OnLeave", function(self)
		if self:IsEnabled() then
			self.text:SetTextColor(0.4, 0.73, 1)
		end
	end)

	reportButton = SpokenZones:CreateReportButton(panel)
	reportButton:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PADDING, PADDING - 6)

	-- Left of Report rather than under it: unlike Report it does not depend on a selection,
	-- so it never competes for the same anchor and can sit on the footer row permanently.
	contributeButton = SpokenZones:CreateContributeButton(panel)
	contributeButton:SetPoint("BOTTOMRIGHT", reportButton, "BOTTOMLEFT", -6, 0)

	footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PADDING, PADDING - 4)
	footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(PADDING + REPORT_RESERVE + CONTRIBUTE_RESERVE), PADDING - 4)
	footer:SetJustifyH("LEFT")
	footer:SetText("Lore: warcraft.wiki.gg (CC BY-SA 4.0)")

	body = SpokenZones:CreateTextView(panel)
	body.frame:SetPoint("TOPLEFT", infoLine, "BOTTOMLEFT", 0, -6)
	-- Cleared against the button rather than the credit line: the button is the
	-- taller of the two, so it is the one that decides where the text has to stop.
	body.frame:SetPoint("BOTTOMRIGHT", reportButton, "TOPRIGHT", 0, 6)

	SpokenZones.panel = panel
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function ApplyAnchors()
	panel:ClearAllPoints()
	if SpokenZones:Get("panelSide") == "LEFT" then
		panel:SetPoint("TOPRIGHT", WorldMapFrame, "TOPLEFT", -2, 0)
		panel:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMLEFT", -2, 0)
	else
		panel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, 0)
		panel:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", 2, 0)
	end
end

local function SetBody(text)
	body:SetText(text)
end

-- Maximised, the map fills the screen and a side panel would sit off-screen, so
-- the panel only shows in windowed mode.
local function ShouldShow()
	if not SpokenZones:Get("showMapPanel") then
		return false
	end
	if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then
		return false
	end
	return true
end

local function SetCaption(text)
	infoLine:Disable()
	infoLine.text:SetTextColor(0.5, 0.5, 0.5)
	infoLine.text:SetText(text or "")
end

local function SetBackLink(zoneName)
	infoLine:Enable()
	infoLine.text:SetTextColor(0.4, 0.73, 1)
	infoLine.text:SetText(L.BACK_TO_ZONE:format(zoneName))
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

local function Refresh(mapID)
	if not panel then
		return
	end

	if not ShouldShow() then
		panel:Hide()
		return
	end

	mapID = mapID or SpokenZones:GetDisplayedMapID()
	if not mapID then
		panel:Hide()
		return
	end

	panel:Show()

	local zoneName = SpokenZones:GetMapName(mapID) or ("uiMapID " .. tostring(mapID))

	-- A selection only applies to the map it was made on; navigating elsewhere
	-- drops it. Checking here rather than on the map-changed callback keeps this
	-- independent of the order modules register their callbacks.
	local selected = SpokenZones.selected
	if selected and selected.mapID ~= mapID then
		SpokenZones.selected = nil
		selected = nil
	end

	if selected then
		-- Prefer the name the client reported, which is what the player sees on
		-- the map ("The Bulwark"), over the wiki page title ("Bulwark").
		header:SetText(selected.areaName or selected.entry.name or "")
		SetBackLink(zoneName)
		if SpokenZones:IsPending(selected.entry) then
			-- Named, listed, and honest about the rest. Both buttons are cleared: there is
			-- no clip to play and nothing written to report on.
			SetBody("|cff888888" .. L.LORE_NOT_WRITTEN:format(
				selected.areaName or selected.entry.name or "") .. "|r")
			audioButton:SetTarget(nil, nil)
			reportButton:SetTarget(nil, nil)
			return
		end
		SetBody(selected.entry.full or selected.entry.short or "")
		-- Audio and the report link are both keyed by the canonical form, not the
		-- name the client reported. Resolve, not Normalise: on a localized client
		-- the reported name reaches the corpus key only through the alias table,
		-- and normalising a non-Latin name yields nil -- which would silently
		-- retarget both buttons at the zone's lore.
		local key = SpokenZones:ResolveAreaKey(selected.areaName)
		audioButton:SetTarget(mapID, key)
		reportButton:SetTarget(mapID, key)
		return
	end

	header:SetText(zoneName)

	local entry, foundOn = SpokenZones:GetLoreWithFallback(mapID)
	if entry then
		-- Fallback hit an ancestor (a dungeon or micro-map inheriting its zone's
		-- lore); say so rather than silently mislabelling the text.
		if foundOn ~= mapID then
			SetCaption("lore for " .. (SpokenZones:GetMapName(foundOn) or "parent zone"))
		else
			local subzones = SpokenZones.Subzones[mapID]
			if subzones and next(subzones) then
				SetCaption("click a subzone on the map for more")
			else
				SetCaption("")
			end
		end
		if SpokenZones:IsPending(entry) then
			SetBody("|cff888888" .. L.LORE_NOT_WRITTEN:format(
				SpokenZones:GetMapName(foundOn) or zoneName) .. "|r")
			audioButton:SetTarget(nil, nil)
			reportButton:SetTarget(nil, nil)
			return
		end
		SetBody(entry.full or entry.short or "")
		-- foundOn, not mapID: a dungeon showing its parent zone's text should read
		-- that same parent zone's narration, and a report on it belongs to the line
		-- that text actually came from.
		audioButton:SetTarget(foundOn, nil)
		reportButton:SetTarget(foundOn, nil)
	else
		SetCaption("")
		SetBody("|cff888888" .. L.NO_LORE_FOR:format(zoneName) .. "|r")
		audioButton:SetTarget(nil, nil)
		reportButton:SetTarget(nil, nil)
	end
end

function SpokenZones:RefreshPanel()
	Refresh(SpokenZones:GetDisplayedMapID())
end

-- Re-apply width, side and font after an options change. TextView re-wraps itself
-- when the width actually changes, via its OnSizeChanged.
function SpokenZones:ApplyPanelOptions()
	if not panel then
		return
	end
	panel:SetWidth(SpokenZones:Get("panelWidth"))
	ApplyAnchors()
	Refresh(SpokenZones:GetDisplayedMapID())
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function SpokenZones:SetupMapPanel()
	if panel then
		return
	end

	BuildPanel()
	ApplyAnchors()

	-- Re-evaluate visibility whenever the map changes shape. Leatrix_Maps hooks
	-- this same set; these are the paths that resize or re-dock the map frame.
	local function Relayout()
		if not panel then
			return
		end
		ApplyAnchors()
		Refresh(SpokenZones:GetDisplayedMapID())
	end

	hooksecurefunc(WorldMapFrame, "Maximize", Relayout)
	hooksecurefunc(WorldMapFrame, "Minimize", Relayout)
	hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", Relayout)
	if WorldMapFrame.OnFrameSizeChanged then
		hooksecurefunc(WorldMapFrame, "OnFrameSizeChanged", Relayout)
	end

	SpokenZones:OnMapChanged(function(mapID)
		Refresh(mapID)
	end)

	Refresh(SpokenZones:GetDisplayedMapID())
end
