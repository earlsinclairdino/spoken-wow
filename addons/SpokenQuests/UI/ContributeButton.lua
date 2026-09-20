setfenv(1, VoiceOver)

-- The Contribute button, on the Blizzard quest frame itself.
--
-- Modeled on SpokenBooks/UI/PlayButton.lua, the closest precedent in this repo for a button
-- the game's own frame has to host because ours cannot. There the reason is that the book
-- addon has no player frame of its own at all; here the reason is narrower but just as final:
-- this button's whole precondition, Contribute:HasGap(), is true exactly when nothing was
-- ever queued (see Contribute.lua's HasSoundForCurrent), so the Spoken player frame -- whose
-- action row is where ReportButton's own button lives, registered by Player.lua -- is hidden
-- the entire time this button needs to be shown (UI/PlayerFrame.lua in the player addon:
-- `if not clip then self:Hide(); return end`). There is no clip to decorate, so there is no
-- player-frame action row to add a second action to. What is left, and what already carries
-- ReportButton's own copy-link popup for exactly this reason, is the game's own frame.
--
-- A TEXT button, not an icon, for PlayButton.lua's reason, unchanged: an icon path cannot be
-- verified without launching the client, and a texture missing on a private-server client
-- draws nothing at all -- an invisible button is a worse failure than a plain one.
--
-- Hidden rather than disabled when there is nothing to send, for PlayButton.lua's reason,
-- unchanged: a greyed-out button on every quest and every NPC this client has no line for is
-- a permanent invitation to wonder what's broken; an absent one says there is nothing to do.

local BUTTON_HEIGHT = 22
local GAP = 8

ContributeButton = {}

-- A copy of VoiceOver.lua's helper of the same name, which is a local there and so not
-- reachable from this file -- the same reason ReportButton.lua and Player.lua each carry
-- their own copy rather than sharing one.
local function IsFrameVisible(frame)
    if not frame then
        return false
    elseif frame.IsVisible then
        return frame:IsVisible()
    end
    return frame:IsShown()
end

-- The two buttons flanking the row this button shares, per quest panel. Read out of
-- Vanilla/QuestFrame.xml, TBC/QuestFrame.xml and Mainline/QuestFrame.xml
-- (github.com/Gethe/wow-ui-source): all three declare these six as true globals, one
-- BOTTOMLEFT and one BOTTOMRIGHT of QuestFrame, on every one of the three panels. Everything
-- else about the row -- QuestFrame's own width, each button's exact padding, and whether a
-- right-hand button exists at all (the modern Mainline Reward panel ships no Cancel button)
-- -- differs by client generation, which is why this button is never anchored to a raw pixel
-- offset: it is anchored to whichever of these the running client actually drew, so a padding
-- change or a missing button on one generation cannot misplace it on another.
local function RowButtonsFor(panel)
    if panel == QuestFrameDetailPanel then
        return QuestFrameAcceptButton, QuestFrameDeclineButton
    elseif panel == QuestFrameProgressPanel then
        return QuestFrameCompleteButton, QuestFrameGoodbyeButton
    elseif panel == QuestFrameRewardPanel then
        return QuestFrameCompleteQuestButton, QuestFrameCancelButton
    end
end

--- Which of the three NPC quest panels is on screen, the same priority Contribute:Capture
--- and ReportButton:CurrentTarget both use.
local function QuestPanelOnScreen()
    if IsFrameVisible(QuestFrameRewardPanel) then
        return QuestFrameRewardPanel
    elseif IsFrameVisible(QuestFrameProgressPanel) then
        return QuestFrameProgressPanel
    elseif IsFrameVisible(QuestFrameDetailPanel) then
        return QuestFrameDetailPanel
    end
end

-- The gossip frame's Goodbye button, under whichever of the two names it is reachable by.
--
-- github.com/Gethe/wow-ui-source's "Classic" module (what Classic Era, Anniversary and every
-- client sharing that Gossip frame build load) and its "Mainline" module (Forever, and
-- current retail) both place a lone GoodbyeButton at GossipFrame's bottom-right with nothing
-- else on that row -- reached as GossipFrame.GreetingPanel.GoodbyeButton, a parentKey rather
-- than a separate global. The three original 1.12/2.4.3/3.3.5 clients predate that source
-- tree; whether their own gossip frame exposes an equivalent global (older Blizzard UIs often
-- named this kind of button directly, e.g. GossipGreetingGoodbyeButton) is not something this
-- change could verify against a real client. Both are tried, and if neither resolves, the
-- button simply does not appear on gossip there -- Capture() still works from `/spq` or
-- whatever else reaches it; nothing forces a guess at a frame this could not confirm.
local function GossipGoodbyeButton()
    local frame = _G.GossipFrame
    if frame and frame.GreetingPanel and frame.GreetingPanel.GoodbyeButton then
        return frame.GreetingPanel.GoodbyeButton
    end
    return _G.GossipGreetingGoodbyeButton
end

--- Anchor the button into the free gap on `panel`'s own button row. False when this panel
--- carries no left-hand button to anchor from at all, which no client this file was checked
--- against actually does, but a client that surprises us here should get no button rather
--- than one anchored to nothing.
function ContributeButton:PositionOnQuestPanel(panel)
    local left, right = RowButtonsFor(panel)
    if not left then
        return false
    end

    local button = self.button
    button:ClearAllPoints()
    -- LEFT alone would need a guessed width; LEFT and RIGHT together make the button exactly
    -- as wide as the gap actually is on this client, so a snug fit narrows the label rather
    -- than spilling over the button beside it.
    button:SetPoint("LEFT", left, "RIGHT", GAP, 0)
    if right then
        button:SetPoint("RIGHT", right, "LEFT", -GAP, 0)
    else
        button:SetWidth(180)
    end
    return true
end

--- Anchor the button to the left of the gossip frame's Goodbye button. False when this
--- client's gossip frame does not resolve one -- see GossipGoodbyeButton's comment.
function ContributeButton:PositionOnGossip()
    local goodbye = GossipGoodbyeButton()
    if not goodbye then
        return false
    end

    local button = self.button
    button:ClearAllPoints()
    button:SetPoint("RIGHT", goodbye, "LEFT", -GAP, 0)
    button:SetWidth(180)
    return true
end

--- Show, hide and place the button for whatever is on screen now. Parented to UIParent, not
--- to QuestFrame or GossipFrame: whichever of those two is relevant is the one hidden while
--- the other is up, and a child cannot be visible while its ancestor is not. Positioning
--- still tracks the right one, through SetPoint's relativeTo, which does not require a shared
--- parent.
function ContributeButton:Refresh()
    local button = self.button
    if not button then
        return
    end

    if not Contribute:HasGap() then
        button:Hide()
        return
    end

    local panel = QuestPanelOnScreen()
    local placed
    if panel then
        placed = self:PositionOnQuestPanel(panel)
    else
        placed = self:PositionOnGossip()
    end
    if placed then
        button:Show()
    else
        button:Hide()
    end
end

--- Build the button, once, parented to UIParent so its own visibility never depends on
--- QuestFrame's or GossipFrame's.
function ContributeButton:Setup()
    if self.button then
        return self.button
    end
    if not CreateFrame then
        return nil
    end

    local button = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
    button:SetHeight(BUTTON_HEIGHT)
    button:SetText("No voice \226\128\148 contribute")
    if button.SetFrameStrata then
        -- Above QuestFrame and GossipFrame, both of which draw at "HIGH": this button reads
        -- as part of whichever one is open, not as a stray control behind it.
        button:SetFrameStrata("DIALOG")
    end
    button:Hide()

    button:SetScript("OnClick", function()
        Contribute:Show()
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("No line for this")
        GameTooltip:AddLine("Send your own client's text so it can be added.", 1, 0.8, 0.2, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    self.button = button
    return button
end
