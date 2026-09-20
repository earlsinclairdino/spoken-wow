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

--- Which id space the unit's GUID belongs to.
---
--- Creature and gameobject ids overlap -- creature 68 is a Stormwind City Guard, gameobject 68
--- is a Wanted Poster -- so the site cannot key on the number alone. Enums.GUID already knows
--- the difference and ReportButton reads it the same way.
local function NPCKind()
    local guid = Utils:GetNPCGUID()
    if not guid or not Utils.GetGUIDType then
        return nil
    end
    local ok, guidType = pcall(Utils.GetGUIDType, Utils, guid)
    if not ok or not guidType then
        return nil
    end
    if guidType == Enums.GUID.GameObject then
        return "gameobject"
    end
    return Enums.GUID:IsCreature(guidType) and "creature" or nil
end

-- The frame itself, made once and kept, rather than one per capture: it is only ever handed
-- a different unit. What is NOT kept is it being shown -- a PlayerModel left shown keeps
-- driving a 3D scene draw for as long as the addon runs, and this client has hung its GPU on
-- model rendering before. UI/Portrait.lua's pooled-model Acquire/Release (Compat.lua, for the
-- clients that cannot show an arbitrary creature in a DressUpModel) is this repo's existing
-- answer to the same problem: show it, read it, then Hide/ClearModel the way Release does.
local modelProbe

local function ModelFileID()
    if not CreateFrame then
        return nil
    end
    if not modelProbe then
        local ok, frame = pcall(CreateFrame, "PlayerModel", nil, UIParent)
        if not ok or not frame then
            return nil
        end
        modelProbe = frame
        if modelProbe.SetSize then modelProbe:SetSize(64, 64) end
        if modelProbe.SetPoint then modelProbe:SetPoint("CENTER") end
        if modelProbe.SetAlpha then modelProbe:SetAlpha(0) end
    end

    if not modelProbe.SetUnit or not modelProbe.GetModelFileID then
        return nil
    end
    -- Shown only for this read: GetModelFileID must be asked of a frame that is shown (task
    -- 1's probing of a live client), but nothing says it has to stay shown between reads.
    if modelProbe.Show then modelProbe:Show() end
    pcall(modelProbe.SetUnit, modelProbe, "npc")
    local ok, id = pcall(modelProbe.GetModelFileID, modelProbe)
    if modelProbe.ClearModel then modelProbe:ClearModel() end
    if modelProbe.Hide then modelProbe:Hide() end
    -- Absent rather than zero: the site reads a missing model as "race unknown", and 0 is a
    -- file id that would mean something. This is also what a model that has not finished
    -- loading yet reads back as -- see the comment on Observations for what that costs.
    if not ok or type(id) ~= "number" or id <= 0 then
        return nil
    end
    return id
end

--- What the client can see about who is speaking. The site decides what it means.
---
--- Only ever called from Capture when an envelope is actually going to be built -- never from
--- HasGap, which runs on every quest and gossip event and must not touch the model probe just
--- to answer a yes/no question. Showing the probe and reading it back synchronously, as
--- ModelFileID does, is also why a model the client has not finished loading yet reads as
--- absent rather than blocking or retrying: this addon has no test bench against a live
--- client, so whether that ever loses a model a longer-lived probe would have caught is an
--- open question, not a settled one -- flagged rather than papered over with a retry timer.
local function Observations(fields)
    local function add(key, value)
        if value ~= nil and value ~= "" then
            fields[#fields + 1] = { key, value }
        end
    end
    add("kind", NPCKind())
    add("model", ModelFileID())
    add("sex", UnitSex and UnitSex("npc") or nil)
    add("creature", UnitCreatureType and UnitCreatureType("npc") or nil)
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
        Observations(fields)
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
        Observations(fields)
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

--- Whether Capture would build an envelope, without paying to build one.
---
--- The same two conditions Capture returns on, repeated rather than reused, because reuse
--- here would mean calling Capture and throwing the envelope away -- and Capture is where
--- Observations runs, which is exactly the model-probe cost HasGap must not pay on every
--- quest and gossip event just to answer a yes/no question.
local function HasSomethingToSend()
    local event, text = EventOnScreen()
    if event and text and text ~= "" then
        return true
    end
    local gossip = GetGossipText and GetGossipText()
    return gossip and gossip ~= "" and NPCID() ~= nil
end

--- Whether the contribute button belongs on screen: something to send, and nothing to play.
function Contribute:HasGap()
    if not (_G.Spoken and Spoken.Contribute and Spoken.ShowContribution) then
        return false
    end
    return HasSomethingToSend() and not HasSoundForCurrent()
end

-- Compression happens here and nowhere upstream of a click: HasGap/Capture run on every quest
-- and gossip event to decide whether the button belongs on screen at all, and paying deflate's
-- cost on each of those would be work spent on every panel the player merely glances at, for a
-- result almost always thrown away unhandled. Show() runs once, when they have already decided
-- to send it.
function Contribute:Show()
    local envelope = self:Capture()
    if not envelope then
        return
    end
    local address = format("%s/contribute", SITE_URL)
    -- Encode is absent on an older SpokenPlayer a legacy-client zip can still bundle; Link
    -- returns nil for that or for an oversized result. Either way, the two-copy fallback still
    -- works, which is the whole point of shipping it alongside the link instead of replacing it.
    local link = Spoken.Contribute.Encode and Spoken.Contribute:Link(address, envelope)
    if link then
        Spoken:ShowContribution(link, address, true)
    else
        Spoken:ShowContribution(envelope, address)
    end
end
