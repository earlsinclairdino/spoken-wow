setfenv(1, SpokenEnv)

-- A frame holding one envelope, ready to copy.
--
-- Not a StaticPopup, which is what every other copy box in this project is (ReportButton.lua
-- here, UI/CopyLink.lua in books and zones): `hasEditBox` gives one line sized for a character
-- name, and an envelope is a few kilobytes over many lines. So this is a frame of its own with
-- a scrolling, multi-line edit box, and it is the only one -- three addons share it, which is
-- also why it lives in the player.
--
-- The text is selected on show. Making the player select it first is the difference between a
-- payload people send and a payload people look at, and a partial selection is the failure the
-- envelope's checksum exists to catch on the far end.

local WIDTH, HEIGHT = 500, 340

local box

local function Build()
    -- "BackdropTemplate" is what carries SetBackdrop on the modern clients, where the mixin
    -- moved out of the base frame; it is simply an unknown template name on the legacy ones,
    -- which still answer SetBackdrop themselves. UI/PlayerFrame.lua and the zones lore window
    -- both pass it for the same reason.
    local frame = CreateFrame("Frame", "SpokenContributeBox", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetHeight(HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    -- Without this the envelope draws straight onto the world: white text over grass, which is
    -- what the first player to see this frame reported. The same dialog art the zones lore
    -- window uses, so the two read as one addon.
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    frame:Hide()

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("Spoken")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Said once, above the box, because the box itself is a wall of key=value lines and a
    -- player who does not know what to do with it will do nothing with it.
    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -34)
    hint:SetText("Press Ctrl+C, then paste it at:")

    local scroll = CreateFrame("ScrollFrame", "SpokenContributeBoxScroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -56)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 56)

    local editBox = CreateFrame("EditBox", "SpokenContributeBoxEdit", scroll)
    editBox:SetMultiLine(true)
    -- The default is 255 bytes, which would truncate every envelope this frame exists for.
    editBox:SetMaxBytes(0)
    editBox:SetWidth(WIDTH - 60)
    editBox:SetAutoFocus(false)
    if editBox.SetFontObject then
        editBox:SetFontObject(ChatFontNormal)
    end
    scroll:SetScrollChild(editBox)

    local address = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    address:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 20)

    -- Read-only in effect rather than in fact: a box that refuses input cannot be selected
    -- with the mouse. Accept the keystroke and undo it, as the report popup does.
    editBox:SetScript("OnTextChanged", function(self)
        self = self or this
        if box and box.payload and self:GetText() ~= box.payload then
            self:SetText(box.payload)
            self:HighlightText()
        end
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        (self or this):GetParent():GetParent():Hide()
    end)

    return { frame = frame, editBox = editBox, address = address, title = title, hint = hint }
end

--- Show an envelope, ready to copy, with the address to paste it into.
---@return boolean shown  False when there is nothing to show, so a caller can stay quiet.
function Spoken:ShowContribution(envelope, address)
    if type(envelope) ~= "string" or envelope == "" then
        return false
    end

    box = box or Build()
    Spoken.ContributeBox = box

    box.payload = envelope
    box.editBox:SetText(envelope)
    box.editBox:HighlightText()
    box.editBox:SetFocus()
    box.address:SetText(address or "")
    box.frame:Show()
    return true
end
