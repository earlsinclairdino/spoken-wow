-- SpokenZones -- the "Report" button shown beside a lore description.
--
-- A factory in the same shape as SpokenZones:CreateAudioButton: anchor the returned
-- button yourself, then call SetTarget whenever the panel's content changes.
-- Text rather than an icon, for the reason UI/AudioButton.lua gives.
--
-- Unlike the play button it does not care whether the line has audio. Play hides
-- with no clip because there is nothing to play; lore text can be wrong whether
-- or not anyone has read it aloud, and a report on a line with no voiceover is
-- one of the more useful kinds.

local ADDON_NAME, SpokenZones = ...

local BUTTON_WIDTH = 58
local BUTTON_HEIGHT = 20
local CONTRIBUTE_WIDTH = 132

local ReportButton = {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- nil areaKey means the zone itself. Passing a nil mapID parks the button: there
-- is nothing to report against, so it hides.
function ReportButton:SetTarget(mapID, areaKey)
	self.mapID = mapID
	self.areaKey = areaKey
	self:Refresh()
end

function ReportButton:Refresh()
	if self.mapID then
		self:Show()
	else
		self:Hide()
	end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function SpokenZones:CreateReportButton(parent)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	button:SetText("Report")
	button:Hide()

	button.SetTarget = ReportButton.SetTarget
	button.Refresh = ReportButton.Refresh

	button:SetScript("OnClick", function(self)
		local url = SpokenZones:ReportURL(self.mapID, self.areaKey)
		if not url then
			return
		end
		SpokenZones:ShowCopyLink(url, "Copy this address and open it in your browser to report a problem with this entry.")
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Report a problem")
		GameTooltip:AddLine("Wrong lore, a bad reading, a mispronounced name -- this gives you a link to say so.", 1, 0.8, 0.2, true)
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return button
end

--------------------------------------------------------------------------------
-- The "no lore here" button
--------------------------------------------------------------------------------

-- Report is only ever aimed at an entry that exists -- SetTarget above parks and hides it
-- otherwise, which is exactly right for reporting a problem with a line that is on screen.
-- This button's whole reason to exist is the opposite entry, the one that does not, and its
-- question is about the player's own location, not whatever a map panel or the lore window
-- happens to be displaying -- so it cannot share SetTarget/Refresh's plumbing.
--
-- It refreshes off SpokenZones:OnZoneChanged instead: the same funnel Autoplay.lua's login
-- greeting and NarrateUnheard already ride, fed by Core.lua's own ZONE_CHANGED/
-- ZONE_CHANGED_INDOORS/ZONE_CHANGED_NEW_AREA handler. That means no new event frame and no
-- timer of its own -- see the quests task's review, which rejected a 0.2s poll for precisely
-- this reason.
function SpokenZones:CreateContributeButton(parent)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(CONTRIBUTE_WIDTH, BUTTON_HEIGHT)
	button:SetText("No lore -- tell us")
	button:Hide()

	button:SetScript("OnClick", function()
		SpokenZones:ShowContribution()
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("No lore for here")
		GameTooltip:AddLine("Zone lore is written by hand from the wiki, not read out of the client -- this sends your location so the gap can be filled.", 1, 0.8, 0.2, true)
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local function Refresh()
		if SpokenZones:HasContributionGap() then
			button:Show()
		else
			button:Hide()
		end
	end
	SpokenZones:OnZoneChanged(Refresh)
	Refresh()

	return button
end
