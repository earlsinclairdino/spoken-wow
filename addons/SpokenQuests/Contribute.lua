setfenv(1, VoiceOver)

-- What this addon sends when it has no line for what is on screen.
--
-- The corpus is built from a 1.12 world database, so three kinds of gap cannot be closed from
-- our end: content that postdates vanilla, locales that database does not carry, and whatever
-- a private server has invented. In all three the client in front of the player is holding the
-- only copy of the text, and a report that says "nothing played" is worth less than the same
-- report carrying it.
--
-- Read from the client, never from soundData, for the reason ReportButton.lua gives: when the
-- data module failed to load there is no soundData at all, and that is the case most worth
-- sending.

-- The merged domain, not the frozen voiceover.rusty.one that ReportButton.lua points at: the
-- contribute page is new and exists only on the site the three sections share. That file's
-- SITE_URL is a local of its own and deliberately stays where it is -- a report link that moved
-- would be a report link that breaks for everyone still running the shipped addon.
local SITE_URL = "https://spoken.rusty.one"

local EVENT_PATHS =
{
    [Enums.SoundEvent.QuestAccept] = "accept",
    [Enums.SoundEvent.QuestProgress] = "progress",
    [Enums.SoundEvent.QuestComplete] = "complete",
}

Contribute = {}

local function NPCID()
    local guid = Utils:GetNPCGUID()
    if not guid or not Utils.GetIDFromGUID then
        return nil
    end
    local ok, read = pcall(Utils.GetIDFromGUID, Utils, guid)
    return ok and read or nil
end

local function NPCField()
    local id = NPCID()
    local name = UnitName and UnitName("npc") or nil
    if id and name then
        return format("%d %s", id, name)
    end
    return id and tostring(id) or name
end

--- Which panel the player is looking at, as the event it would have played.
local function EventOnScreen()
    if QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() then
        return Enums.SoundEvent.QuestComplete, GetRewardText and GetRewardText()
    elseif QuestFrameProgressPanel and QuestFrameProgressPanel:IsShown() then
        return Enums.SoundEvent.QuestProgress, GetProgressText and GetProgressText()
    elseif QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() then
        return Enums.SoundEvent.QuestAccept, GetQuestText and GetQuestText()
    end
    return nil, nil
end

--- The envelope for what is on screen, or nil when there is nothing to send.
function Contribute:Capture()
    local event, text = EventOnScreen()
    local fields =
    {
        -- VoiceOver.VERSION does not exist -- nothing in this addon ever assigns it. The
        -- addon's own .toc version, read the way DataModules.lua already reads every sound
        -- pack's (GetAddOnMetadata, compat-shimmed onto C_AddOns.GetAddOnMetadata in
        -- Compatibility.lua for clients that moved it there), is the real mechanism to reuse
        -- rather than inventing a second one; "dev" is what a source checkout with no .toc
        -- metadata at all reads back as.
        { "addon", format("SpokenQuests/%s", (GetAddOnMetadata and GetAddOnMetadata(AddonFolder, "Version")) or "dev") },
        { "build", format("%s/%s", (GetBuildInfo and select(1, GetBuildInfo())) or "?",
                                   (GetBuildInfo and select(2, GetBuildInfo())) or "?") },
        { "locale", (GetLocale and GetLocale()) or "enUS" },
    }

    if event and text and text ~= "" then
        local questID = GetQuestID and GetQuestID() or 0
        if questID and questID > 0 then
            fields[#fields + 1] = { "quest", questID }
        end
        fields[#fields + 1] = { "event", EVENT_PATHS[event] }
        fields[#fields + 1] = { "npc", NPCField() }
        fields[#fields + 1] = { "title", GetTitleText and GetTitleText() or "" }
        return Spoken.Contribute:Envelope("quests", fields, text)
    end

    -- Gossip: no quest and no event, but an NPC saying something this corpus has never heard.
    --
    -- The creature id is required rather than merely included. A gossip contribution is keyed on
    -- it and nothing else -- there is no quest id to fall back on -- so an envelope without one
    -- is refused on arrival, and offering a button that leads to a refusal is worse than
    -- offering none. Two ways to arrive here without an id: the frame closing under us, where
    -- the words are still readable and the unit is already gone, and the 1.12 client, which has
    -- no UnitGUID and so can never name the creature.
    local gossip = GetGossipText and GetGossipText()
    if gossip and gossip ~= "" and NPCID() then
        fields[#fields + 1] = { "npc", NPCField() }
        return Spoken.Contribute:Envelope("quests", fields, gossip)
    end

    return nil
end

--- Whether this client's data module has a line for what is on screen.
---
--- Neither VoiceOver.lua nor Player.lua expose a lookup by that name: what actually decides
--- there is nothing to enqueue is DataModules:PrepareSound, called from Player:Enqueue. Run
--- against a throwaway table rather than a soundData already headed for playback -- PrepareSound
--- mutates whatever it is given (fileName, filePath, length, module), and a table built only to
--- ask the question must not be mistaken afterwards for a clip that plays.
local function HasSoundForCurrent()
    local event, text = EventOnScreen()
    if event and text and text ~= "" then
        return DataModules:PrepareSound({ event = event, questID = GetQuestID and GetQuestID() or 0 })
    end

    local gossip = GetGossipText and GetGossipText()
    local guid = Utils:GetNPCGUID()
    local name = Utils:GetNPCName()
    -- Both absent is the case Addon:GOSSIP_SHOW guards with the same test and the comment
    -- "the player interacted with an NPC while having main menu or options opened". It also
    -- happens on the way out: CloseGossip fires GOSSIP_CLOSED, which refreshes this button
    -- while GetGossipText still answers. DataModules keys gossip on the name when there is no
    -- GUID, and hands that name to string.gsub, so a nil one is an error thrown at a player
    -- who only walked away from a conversation.
    if gossip and gossip ~= "" and (guid or name) then
        return DataModules:PrepareSound({
            event = Enums.SoundEvent.Gossip,
            unitGUID = guid,
            name = name,
            unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
            text = gossip,
        })
    end

    return false
end

--- Whether the contribute button belongs on screen: something to send, and nothing to play.
function Contribute:HasGap()
    if not (_G.Spoken and Spoken.Contribute and Spoken.ShowContribution) then
        return false
    end
    return self:Capture() ~= nil and not HasSoundForCurrent()
end

function Contribute:Show()
    local envelope = self:Capture()
    if envelope then
        Spoken:ShowContribution(envelope, format("%s/contribute", SITE_URL))
    end
end
