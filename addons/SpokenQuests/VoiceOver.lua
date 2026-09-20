setfenv(1, VoiceOver)

---@class Addon : AceAddon, AceAddon-3.0, AceEvent-3.0, AceTimer-3.0
---@field db VoiceOverConfig|AceDBObject-3.0
local AceAddon = LibStub("AceAddon-3.0")

-- Every player of this lineage, oldest first: the AceAddon name it registers under, and the
-- folder it installs into. Upstream's, and this fork's own two names before the rename -- a
-- rename uninstalls nothing, so a former name is as much of a duplicate as upstream's. Names
-- are only ever added to this list.
local SUPERSEDED_PLAYERS = {
    { name = "VoiceOver", folder = "AI_VoiceOver" },
    { name = "VoiceOverContinued", folder = "AI_VoiceOver_Continued" },
    { name = "VoiceOverRedux", folder = "VoiceOverRedux" },
}

-- The folders of the players that actually registered. Two players handle the same events and
-- queue the same line, so each is stopped here for this session and its folder disabled for
-- the next login further down; loading two also used to cause a duplicate AceAddon error.
--
-- Registering is what makes a folder a duplicate, rather than merely existing. A folder that
-- registered nothing is either an old install already switched off, or the TOC-only tombstone
-- this release ships under the old name -- which holds no code at all and exists only to keep
-- the old SavedVariables file loading for AdoptSavedVariables below. On a fresh install that
-- tombstone arrives inside this addon's own zip, so treating an installed folder as a
-- duplicate opened every first login with a dialog about an addon nobody installed.
local supersededFolders = {}
for _, player in ipairs(SUPERSEDED_PLAYERS) do
    local supersededAddon = AceAddon:GetAddon(player.name, true)
    if supersededAddon then
        if supersededAddon.Disable then
            supersededAddon:Disable()
        end
        table.insert(supersededFolders, player.folder)
    end
end
Addon = AceAddon:NewAddon("SpokenQuests", "AceEvent-3.0", "AceTimer-3.0")

Addon.OnAddonLoad = {}
local AUTO_POLL_INTERVAL = 0.1

-- Store original function before EQL3 (Extended Quest Log 3) overrides it and starts prepending quest level
local GetTitleText = GetTitleText

local function IsFrameVisible(frame)
    if not frame then
        return false
    elseif frame.IsVisible then
        return frame:IsVisible()
    end
    return frame:IsShown()
end

-- The last quest event the client fired, and the only way to tell an offer from a turn-in
-- when Blizzard's quest panels never appear. An addon that replaces the quest frame -
-- DialogueUI calls QuestFrame:UnregisterAllEvents() - leaves every panel hidden while the
-- player is in a dialog, so classifying by panel alone read every interaction as an offer.
-- The client still fires the events themselves; only Blizzard's frame stopped listening.
local lastQuestEvent

-- The quest globals as they stood when the client fired a quest event. An addon that
-- accepts or turns in the quest from its own handler - Leatrix Plus, and the auto-turn-in
-- addons beside it - closes the dialog in the same frame the event arrived in, so GetQuestID
-- is back to 0 by the time the 10 Hz watcher first polls and the interaction would never be
-- read at all. The watcher still owns dispatch: it replays this record only once the dialog
-- has closed with nothing dispatched for it.
local questSnapshot

-- Set while a handler is being replayed from a snapshot, so it reads that instead of globals
-- the client has already cleared.
local questSnapshotInUse

local questSnapshotText = {
    QUEST_DETAIL = function() return GetQuestText and GetQuestText() or "" end,
    QUEST_PROGRESS = function() return GetProgressText and GetProgressText() or "" end,
    QUEST_COMPLETE = function() return GetRewardText and GetRewardText() or "" end,
}

local function CaptureQuestSnapshot(event)
    local readText = questSnapshotText[event]
    if not readText then
        return
    end
    local questID = GetQuestID and GetQuestID() or 0
    local questTitle = GetTitleText and GetTitleText() or ""
    -- Nothing to replay, and nothing to identify a quest by either.
    if (not questID or questID == 0) and questTitle == "" then
        return
    end
    questSnapshot = {
        event = event,
        questID = questID,
        title = questTitle,
        text = readText(),
        guid = Utils:GetNPCGUID(),
        targetName = Utils:GetNPCName(),
        isObjectOrItem = Utils:IsNPCObjectOrItem(),
    }
end

-- Where a quest handler's fields come from: the live globals, or the snapshot being replayed.
local function ReadQuestFields(readText)
    local snapshot = questSnapshotInUse
    if snapshot then
        return snapshot.questID, snapshot.title, snapshot.text, snapshot.guid, snapshot.targetName,
            snapshot.isObjectOrItem
    end
    return GetQuestID(), GetTitleText(), readText(), Utils:GetNPCGUID(), Utils:GetNPCName(),
        Utils:IsNPCObjectOrItem()
end

local function GetVisibleQuestEvent()
    -- Completion and progress take priority over detail. IsVisible accounts
    -- for hidden parents; IsShown can remain true on an inactive child panel.
    if IsFrameVisible(QuestFrameRewardPanel) then
        return "QUEST_COMPLETE"
    elseif IsFrameVisible(QuestFrameProgressPanel) then
        return "QUEST_PROGRESS"
    elseif IsFrameVisible(QuestFrameDetailPanel) then
        return "QUEST_DETAIL"
    elseif IsFrameVisible(QuestFrameGreetingPanel) then
        return "QUEST_GREETING"
    end

    local questID = GetQuestID and GetQuestID()
    if not questID or questID == 0 then
        return
    end

    -- Quest-log detail views do not use the NPC QuestFrame panels, but GetQuestID is
    -- authoritative while they are visible, and they only ever show the offer text.
    if IsFrameVisible(QuestLogDetailFrame) or IsFrameVisible(QuestMapDetailsFrame) then
        return "QUEST_DETAIL"
    end

    -- No panel of either kind: trust the last event instead of assuming an offer. It is
    -- cleared by QUEST_FINISHED, so a quest ID the client keeps reporting after the dialog
    -- closed no longer replays anything.
    return lastQuestEvent
end

function Addon:ShowMissingDataModulePopup()
    if DataModules:HasRegisteredModules() then
        return
    end

    local loadDetails = {}
    for _, module in DataModules:GetPresentModules() do
        local reason = DataModules:GetModuleLoadError(module.AddonName)
        if reason then
            table.insert(loadDetails, format("%s: %s", module.AddonName, reason))
        end
    end
    local details = next(loadDetails) and ("|n|nDetected but not loaded:|n" .. table.concat(loadDetails, "|n")) or ""
    StaticPopupDialogs["VOICEOVER_NO_REGISTERED_DATA_MODULES"] =
    {
        text = [[Spoken Quests|n|nNo usable sound packs were loaded.|n|nKeep a sound pack installed beside this addon - "Spoken Quests Audio", or the older "AI_VoiceOverData_Vanilla". Run "/spq diagnostics" for details.]] .. details,
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
    }
    StaticPopup_Show("VOICEOVER_NO_REGISTERED_DATA_MODULES")
end

function Addon:InvokeQuestHandler(event, source)
    local handler = self[event]
    if not handler then
        Debug:Record("handler-missing", format("No handler exists for %s", tostring(event)))
        return false
    end

    Debug:Record("quest-dispatch", format("Dispatching %s through %s", event, source or "manual reader"))
    local succeeded, errorMessage = pcall(handler, self, event)
    if not succeeded then
        Debug:Record("handler-error", format("%s failed: %s", event, tostring(errorMessage)))
        local errorHandler = geterrorhandler and geterrorhandler()
        if errorHandler then
            errorHandler(errorMessage)
        end
        return false
    end
    return true
end

function Addon:ReadVisibleQuest(source)
    local event = GetVisibleQuestEvent()
    if not event then
        Debug:Record("visible-panel-missing", "GetQuestID returned 0 and no Blizzard quest panel is visible")
        return false
    end
    return self:InvokeQuestHandler(event, source or "visible quest reader")
end

---@class VoiceOverConfig
local defaults = {
    profile = {
        -- The frame, the minimap button, the sound channel's legacy music-channel
        -- workaround and the paused flag are the Spoken player's settings now.
        Audio = {
            -- Once per NPC rather than once per quest NPC, which upstream defaulted to:
            -- that setting only silences a repeat where the NPC has a quest, so every
            -- innkeeper, vendor and flight master said the same line on every visit --
            -- the greeting a player hears most often is exactly the one it did not
            -- remember. A profile that stored a choice of its own keeps it.
            GossipFrequency = Enums.GossipFrequency.OncePerNPC,
            -- The sound channel and the muting of the client's own NPC dialogue used to
            -- live here. They describe how anything is played rather than what this addon
            -- reads, so they are the player's settings now; Spoken's Migrate lifts them.
            StopAudioOnDisengage = false,
            OGThrall = false,
        },
        DebugEnabled = false,
    },
    char = {
        hasSeenGossipForNPC = {},
        RecentQuestTitleToID = Version:IsBelowLegacyVersion(30300) and {},
    }
}

local lastGossipOptions
local selectedGossipOption
local currentQuestSoundData
local currentGossipSoundData

-- The addon was VoiceOverRedux, and the client names a SavedVariables file after the folder:
-- VoiceOverDB lives in VoiceOverRedux.lua, which only loads because a tombstone folder of
-- that name still declares it. Copied once into this addon's own file, before AceDB claims
-- it and before the tombstone is disabled for next login -- disabling first would mean the
-- old file never loads again and nothing to copy.
local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = DeepCopy(item) end
    return copy
end

local function AdoptSavedVariables()
    local old = rawget(_G, "VoiceOverDB")
    local new = rawget(_G, "SpokenQuestsDB")
    local adopted = type(new) == "table" and type(new.global) == "table" and new.global.migratedFrom
    if type(old) ~= "table" or adopted then
        return
    end
    new = DeepCopy(old)
    new.global = new.global or {}
    new.global.migratedFrom = "VoiceOverRedux"
    _G.SpokenQuestsDB = new
end

--------------------------------------------------------------------------------
-- The player, when it is installed but switched off
--------------------------------------------------------------------------------

-- The player is an optional dependency: without it this addon loads, says so, and reads
-- nothing. One case deserves more than a line in chat -- the player installed and
-- disabled -- because it is one click to fix and an addon manager that fetched the
-- dependency cannot see that the player then turned it off.
--
-- The two feature addons each carry a copy of this, because the code they would share
-- lives in the player, which is the addon that is not there. They coordinate through two
-- globals instead: one collects the names to say, the other makes sure only one dialog is
-- raised however many addons are waiting on it.
local PLAYER_FOLDER = "SpokenPlayer"
local PLAYER_DIALOG = "SPOKEN_PLAYER_REQUIRED"

--- Say that this addon needs the player. Called whether or not the player is there, since
--- the addon that raises the dialog may not be the one that noticed first.
local function RequirePlayer(title)
    local names = rawget(_G, "SpokenPlayerRequiredBy")
    if not names then
        names = {}
        _G.SpokenPlayerRequiredBy = names
    end
    for _, name in ipairs(names) do
        if name == title then
            return
        end
    end
    table.insert(names, title)
end

--- "A", "A and B", "A, B and C".
local function ListNames(names)
    local count = 0
    for _ in ipairs(names) do
        count = count + 1
    end
    local text = ""
    for index, name in ipairs(names) do
        if index == 1 then
            text = name
        elseif index == count then
            text = text .. " and " .. name
        else
            text = text .. ", " .. name
        end
    end
    return text
end

--- Raise the dialog, if the player is installed and disabled and nobody has raised it yet.
--- Returns whether this call was the one that raised it.
function Addon:PromptForPlayer()
    if rawget(_G, "Spoken") or rawget(_G, "SpokenPlayerPrompted") then
        return false
    end
    local names = rawget(_G, "SpokenPlayerRequiredBy")
    if not names or not names[1] then
        return false
    end
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local enableAddOn = (C_AddOns and C_AddOns.EnableAddOn) or EnableAddOn
    if not (getInfo and enableAddOn and StaticPopupDialogs and StaticPopup_Show) then
        return false
    end
    -- Absent rather than disabled: there is nothing to enable, so there is nothing to
    -- click. The addon has already said in chat that the player is missing.
    local present, _, _, _, reason = getInfo(PLAYER_FOLDER)
    if not present or reason ~= "DISABLED" then
        return false
    end

    _G.SpokenPlayerPrompted = true
    StaticPopupDialogs[PLAYER_DIALOG] =
    {
        text = format("|cffffd200Spoken Player|r is required to use %s.", ListNames(names)),
        button1 = ENABLE or "Enable",
        button2 = CANCEL or "Cancel",
        timeout = 0,
        whileDead = 1,
        -- An addon is only loaded at login, so enabling it takes effect on the next one.
        OnAccept = function()
            enableAddOn(PLAYER_FOLDER)
            ReloadUI()
        end,
    }
    StaticPopup_Show(PLAYER_DIALOG)
    return true
end

function Addon:OnInitialize()
    AdoptSavedVariables()
    self.db = LibStub("AceDB-3.0"):New("SpokenQuestsDB", defaults)
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    StaticPopupDialogs["VOICEOVER_ERROR"] =
    {
        text = "Spoken Quests|n|n%s",
        button1 = OKAY,
        timeout = 0,
        whileDead = 1,
    }

    RequirePlayer("Spoken Quests")
    Player:Setup()
    -- The copy-link popup behind the Report button. Guarded because a failure to build a
    -- dialog must not stop playback initializing.
    local reportButtonReady, reportButtonError = pcall(ReportButton.Initialize, ReportButton)
    if not reportButtonReady then
        Debug:Record("report-button-error", tostring(reportButtonError))
    end

    -- The Contribute button, on the Blizzard quest/gossip frame rather than the Spoken player
    -- frame -- see UI/ContributeButton.lua's header for why the player frame will not do.
    -- Refreshed on a short repeating timer rather than from each quest/gossip event handler:
    -- one place to keep in sync with what's on screen, running the same on every client
    -- generation including the legacy ones the automatic quest watcher deliberately skips
    -- above. Guarded like ReportButton just above: a failed build here must not take
    -- playback down with it.
    local contributeButtonReady, contributeButtonError = pcall(function()
        if ContributeButton and ContributeButton.Setup then
            ContributeButton:Setup()
            self:ScheduleRepeatingTimer(function() ContributeButton:Refresh() end, 0.2)
        end
    end)
    if not contributeButtonReady then
        Debug:Record("contribute-button-error", tostring(contributeButtonError))
    end

    -- Discover data packs now, but load their multi-megabyte generated Lua
    -- tables after entering the world. Keeping LoadAddOn out of AceAddon's
    -- shared initialization/login stack avoids Hardcore's stricter script
    -- time budget being charged to AceAddon-3.0.
    DataModules:EnumerateAddons(false)
    self.dataModulesPending = not DataModules:HasRegisteredModules()
    local function LoadDeferredDataModules()
        if not self.dataModulesPending then
            return
        end
        local succeeded, loadError = pcall(DataModules.LoadPresentModules, DataModules)
        self.dataModulesPending = nil
        if not succeeded then
            self.dataModulesDeferredError = tostring(loadError)
            Debug:Record("data-load-error", self.dataModulesDeferredError)
        elseif DataModules:HasRegisteredModules() then
            Debug:Record("data-ready", "Deferred sound packs finished loading")
        end
        self:ShowMissingDataModulePopup()
    end
    local function ScheduleDeferredDataLoad()
        if C_Timer and C_Timer.After then
            C_Timer.After(1, LoadDeferredDataModules)
        else
            self:ScheduleTimer(LoadDeferredDataModules, 1)
        end
    end
    -- Always deferred, never raised here: on a /reload every addon's ADDON_LOADED has
    -- already fired by the time this runs, but on a fresh login the other addon that
    -- wants the player may not have loaded yet, and the dialog would name only this one.
    local prompt = CreateFrame("Frame")
    prompt:RegisterEvent("PLAYER_ENTERING_WORLD")
    prompt:SetScript("OnEvent", function(frame)
        frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        Addon:PromptForPlayer()
    end)
    if self.dataModulesPending then
        if IsLoggedIn and IsLoggedIn() then
            ScheduleDeferredDataLoad()
        else
            self.dataLoaderFrame = CreateFrame("Frame")
            self.dataLoaderFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            self.dataLoaderFrame:SetScript("OnEvent", function(frame)
                frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
                ScheduleDeferredDataLoad()
            end)
        end
    end
    local optionsSucceeded, optionsError = pcall(Options.Initialize, Options)
    if not optionsSucceeded then
        self.optionsInitializationError = tostring(optionsError)
        Debug:Record("options-ui-failed", self.optionsInitializationError)
    end

    -- Install this before all optional event registration. AceAddon deliberately
    -- safe-calls OnInitialize, so a later registration failure must not take
    -- automatic playback down with it.
    Debug:Record("options-ready", "Options and manual quest reader are registered")
    self.autoQuestState = {
        candidateAge = 0,
        retryDelay = 0,
        lastHandledAt = 0,
    }

    local function PollAutomaticQuest()
        local state = self.autoQuestState
        if self.dataModulesPending then
            return
        end
        local questCallSucceeded, questID = pcall(function()
            return GetQuestID and GetQuestID() or 0
        end)
        if not questCallSucceeded then
            error(questID)
        end
        if not questID or questID == 0 then
            -- The dialog is gone. If it closed with nothing dispatched for it, the event
            -- snapshot is the whole record of the interaction, so read that before the
            -- candidate state is cleared.
            local snapshot = questSnapshot
            questSnapshot = nil
            if snapshot and not snapshot.dispatched then
                local key = format("%s:%s:%s", snapshot.event, tostring(snapshot.questID), snapshot.title or "")
                if key ~= state.lastHandledKey or GetTime() - state.lastHandledAt >= 5 then
                    state.lastHandledKey = key
                    state.lastHandledAt = GetTime()
                    Debug:Record("auto-watcher-snapshot", format(
                        "Reading %s quest %s from its event snapshot: the dialog closed before it could stabilize",
                        snapshot.event, tostring(snapshot.questID)))
                    questSnapshotInUse = snapshot
                    self:InvokeQuestHandler(snapshot.event, "closed dialog event snapshot")
                    questSnapshotInUse = nil
                end
            end
            state.candidateKey = nil
            state.candidateAge = 0
            state.retryDelay = 0
            state.completedKey = nil
            return
        end

        local titleSucceeded, questTitle = pcall(function()
            return GetTitleText and GetTitleText() or ""
        end)
        if not titleSucceeded then
            error(questTitle)
        end
        local eventSucceeded, event = pcall(GetVisibleQuestEvent)
        if not eventSucceeded then
            error(event)
        end
        event = event or "QUEST_DETAIL"
        local key = format("%s:%s:%s", event, tostring(questID), questTitle or "")
        if key ~= state.candidateKey then
            state.candidateKey = key
            state.candidateAge = 0
            state.retryDelay = 0
            state.completedKey = nil
            Debug:Record("auto-watcher-stabilizing", format("Waiting for %s quest %s to finish populating", event,
                tostring(questID)))
            return
        end

        -- A synchronous Classic quest event can expose the previous quest's
        -- globals briefly while switching NPCs. Do not replay the most recent
        -- quest key during that transition; /spq read remains an explicit way
        -- to replay it.
        if key == state.lastHandledKey and GetTime() - state.lastHandledAt < 5 then
            state.completedKey = key
            return
        end

        state.candidateAge = state.candidateAge + AUTO_POLL_INTERVAL
        state.retryDelay = math.max(0, state.retryDelay - AUTO_POLL_INTERVAL)
        local expectedSoundEvent = event == "QUEST_DETAIL" and Enums.SoundEvent.QuestAccept or
            event == "QUEST_PROGRESS" and Enums.SoundEvent.QuestProgress or
            event == "QUEST_COMPLETE" and Enums.SoundEvent.QuestComplete
        for _, queuedSound in ipairs(Player:Queued()) do
            if queuedSound.questID == questID and queuedSound.event == expectedSoundEvent then
                state.completedKey = key
                state.lastHandledKey = key
                state.lastHandledAt = GetTime()
                if questSnapshot then
                    questSnapshot.dispatched = true
                end
                return
            end
        end

        if key ~= state.completedKey and state.candidateAge >= 0.4 and state.retryDelay <= 0 then
            state.retryDelay = 0.5
            Debug:Record("auto-watcher-dispatch", format("Automatically reading %s quest %s", event,
                tostring(questID)))
            self:ReadVisibleQuest("automatic GetQuestID timer")

            local stage = Debug.runtime and Debug.runtime.stage
            if stage == "queued" or stage == "queue-paused" or stage == "playing" or
               stage == "sound-disabled" or stage == "file-playback-failed" or stage == "playback-failed" or
               stage == "data-lookup-failed" then
                state.completedKey = key
                state.lastHandledKey = key
                state.lastHandledAt = GetTime()
                if questSnapshot then
                    questSnapshot.dispatched = true
                end
            end
        end
    end

    -- The watcher cannot work on a private-server client and must not be installed there.
    -- GetQuestID does not exist before 3.3.0, so Compatibility.lua substitutes one that
    -- resolves a quest fuzzily from text captured by the QUEST_DETAIL/PROGRESS/COMPLETE
    -- handlers - which the poll below is trying to decide whether to call. It would poll a
    -- zero forever. Those clients dispatch from the events directly instead; see directEvents.
    if Version.IsAnyLegacy then
        Debug:Record("auto-watcher-skipped", "Legacy client: quest events dispatch directly")
    else
        local tickerInstalled, tickerOrError = pcall(self.ScheduleRepeatingTimer, self, function()
            local succeeded, pollError = pcall(PollAutomaticQuest)
            if not succeeded then
                Debug:Record("auto-watcher-error", tostring(pollError))
            end
        end, AUTO_POLL_INTERVAL)
        if tickerInstalled then
            self.autoQuestTicker = tickerOrError
            Debug:Record("auto-watcher-ready", "AceTimer GetQuestID polling is active")
        else
            Debug:Record("auto-watcher-install-failed", tostring(tickerOrError))
        end
    end

    local slashInstalled, slashError = pcall(function()
        _G.SLASH_SPOKENQUESTSREAD1 = "/spqread"
        _G.SlashCmdList.SPOKENQUESTSREAD = function()
            self:ReadVisibleQuest("/spqread")
        end
    end)
    if not slashInstalled then
        Debug:Record("standalone-slash-failed", tostring(slashError))
    end

    self.eventBridgeErrors = {}
    local aceRegistered, aceError = pcall(self.RegisterEvent, self, "ADDON_LOADED")
    if not aceRegistered then
        table.insert(self.eventBridgeErrors, "AceEvent ADDON_LOADED: " .. tostring(aceError))
    end

    -- Quest detail/progress/completion are intentionally absent here on Blizzard's clients. On
    -- Classic Era those synchronous events can fire before GetQuestID and the text globals
    -- change, replaying the previous quest. The stabilized 10 Hz watcher above is their single
    -- automatic dispatcher.
    --
    -- On a private-server client the race does not exist, the watcher does not run, and these
    -- events are the only route to quest audio - they are also what sets the text
    -- Compatibility.lua's GetQuestID substitute reads, so nothing resolves until one fires.
    local directEvents = {
        "QUEST_GREETING",
        "QUEST_FINISHED",
        "GOSSIP_SHOW",
        "GOSSIP_CLOSED",
    }
    if Version.IsAnyLegacy then
        table.insert(directEvents, "QUEST_DETAIL")
        table.insert(directEvents, "QUEST_PROGRESS")
        table.insert(directEvents, "QUEST_COMPLETE")
    end
    -- Recording a quest event is not the same as dispatching it: on Blizzard's clients an
    -- event can fire before the quest globals change, which is why the watcher owns
    -- dispatch, but the event name itself is trustworthy the moment it arrives.
    -- QUEST_FINISHED is here to clear the record, so that a quest ID the client keeps
    -- reporting after the dialog closed cannot be read as a fresh interaction.
    self.questEventRecorderFrame = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED" }) do
        pcall(self.questEventRecorderFrame.RegisterEvent, self.questEventRecorderFrame, event)
    end
    self.questEventRecorderFrame:SetScript("OnEvent", function(_, event)
        if event == "QUEST_FINISHED" then
            lastQuestEvent = nil
        else
            lastQuestEvent = event
            -- Through pcall because a snapshot is a fallback, and a client that refuses one
            -- of these globals must not stop the event from being recorded.
            pcall(CaptureQuestSnapshot, event)
        end
    end)

    local directEventLookup = {}
    local lastDispatch = {}
    local dispatching = {}
    local function DispatchDirectEvent(event, source)
        local now = GetTime()
        if dispatching[event] or lastDispatch[event] and now - lastDispatch[event] < 0.5 then
            return
        end

        local handler = self[event]
        if handler then
            dispatching[event] = true
            Debug:Record("event-dispatch", format("Dispatching %s through %s", event, source))
            local succeeded, errorMessage = pcall(handler, self, event)
            dispatching[event] = nil

            if not succeeded then
                Debug:Record("handler-error", format("%s failed: %s", event, tostring(errorMessage)))
                local errorHandler = geterrorhandler and geterrorhandler()
                if errorHandler then
                    errorHandler(errorMessage)
                end
                return
            end

            -- Only suppress the panel/watcher fallback when this route
            -- actually reached the queue or playback stage. An early event
            -- with unpopulated quest globals must be allowed to retry.
            local stage = Debug.runtime and Debug.runtime.stage
            if stage == "queued" or stage == "queue-paused" or stage == "playing" then
                lastDispatch[event] = GetTime()
            else
                lastDispatch[event] = nil
            end
        end
    end
    self.DispatchDirectEvent = function(addon, event, source)
        return DispatchDirectEvent(event, source or "manual dispatch")
    end

    -- Greeting globals can have the same synchronous-event race. Coalesce the
    -- event/frame signals and read them on a later frame after Blizzard has
    -- populated the new NPC and text.
    local deferredSpeechEvents = {
        QUEST_GREETING = true,
        GOSSIP_SHOW = true,
    }
    local deferredEventGeneration = {}
    local function SignalDirectEvent(event, source)
        if event == "QUEST_FINISHED" then
            deferredEventGeneration.QUEST_GREETING = (deferredEventGeneration.QUEST_GREETING or 0) + 1
        elseif event == "GOSSIP_CLOSED" then
            deferredEventGeneration.GOSSIP_SHOW = (deferredEventGeneration.GOSSIP_SHOW or 0) + 1
        end
        if not deferredSpeechEvents[event] then
            DispatchDirectEvent(event, source)
            return
        end
        local generation = (deferredEventGeneration[event] or 0) + 1
        deferredEventGeneration[event] = generation
        self:ScheduleTimer(function()
            if deferredEventGeneration[event] == generation then
                DispatchDirectEvent(event, source .. " (deferred)")
            end
        end, 0.1)
    end

    self.directEventFrame = CreateFrame("Frame")
    for _, event in ipairs(directEvents) do
        local registered, registerError = pcall(self.directEventFrame.RegisterEvent, self.directEventFrame, event)
        if registered then
            directEventLookup[event] = true
        else
            table.insert(self.eventBridgeErrors, format("Direct %s: %s", event, tostring(registerError)))
        end
    end
    self.directEventFrame:SetScript("OnEvent", function(frame, event)
        SignalDirectEvent(event, "direct frame")
    end)

    -- Keep UI fallbacks only for NPC greetings. Quest narration is exclusively
    -- handled by the stabilized watcher.
    local panelEvents = {
        { frame = QuestFrameGreetingPanel, event = "QUEST_GREETING" },
        { frame = GossipFrame, event = "GOSSIP_SHOW" },
    }
    for _, binding in ipairs(panelEvents) do
        if binding.frame and binding.frame.HookScript then
            local event = binding.event
            local hooked, hookError = pcall(binding.frame.HookScript, binding.frame, "OnShow", function()
                    SignalDirectEvent(event, "panel OnShow")
                end)
            if not hooked then
                table.insert(self.eventBridgeErrors, format("Panel %s: %s", event, tostring(hookError)))
            end
        end
    end

    -- Hook the exact Blizzard dispatcher that updates the visible quest
    -- panels. This runs after Blizzard has populated GetQuestID/GetTitleText.
    --
    -- Blizzard's own function is what is hooked here, so the frame overrides that normalize
    -- handler arguments on the older clients do not apply: before 3.0.2 it takes no arguments
    -- and reads the global `event` instead.
    if QuestFrame_OnEvent and hooksecurefunc then
        local hooked, hookError = pcall(hooksecurefunc, "QuestFrame_OnEvent", function(frame, event)
                event = event or _G.event
                if directEventLookup[event] then
                    SignalDirectEvent(event, "QuestFrame_OnEvent hook")
                end
            end)
        if not hooked then
            table.insert(self.eventBridgeErrors, "QuestFrame_OnEvent: " .. tostring(hookError))
        end
    end

    if next(self.eventBridgeErrors) then
        Debug:Record("event-bridge-partial", format("Quest watcher is active; %d optional bridge component(s) failed",
            getn(self.eventBridgeErrors)))
    else
        Debug:Record("event-bridge-ready", "Stabilized quest watcher and deferred greeting bridge are registered")
    end

    -- The folders of the players that registered this session, stopped at the top of this
    -- file. Disabling one takes effect on the next login only, which is why it waits until
    -- here: the saved variables of the folder carrying this addon's own former name were
    -- adopted above, this login, so there is nothing left in it to lose.
    --
    -- Through pcall because current clients reserve enabling and disabling an addon for their
    -- own UI. A client that refuses raises its own "blocked from an action only available to
    -- the Blizzard UI" dialog and an error with it, and every quest hook below this still has
    -- to be installed. The duplicate is stopped for the session either way.
    local disabled = {}
    for _, folder in ipairs(supersededFolders) do
        pcall(DisableAddOn, folder)
        table.insert(disabled, format('"%s"', folder))
    end

    if next(disabled) and not self.db.profile.SeenDuplicatePlayerDialog then
        StaticPopupDialogs["VOICEOVER_REDUX_DUPLICATE_ADDON"] =
        {
            text = format([[Spoken Quests|n|n%s was also enabled. It has been disabled for the next login, and its event handler was stopped for this session.|n|nKeep your sound pack enabled - "Spoken Quests Audio" or the older "AI_VoiceOverData_Vanilla", either works. You can delete or leave the old player disabled, then /reload.]],
                table.concat(disabled, " and ")),
            button1 = OKAY,
            timeout = 0,
            whileDead = 1,
            OnAccept = function()
                self.db.profile.SeenDuplicatePlayerDialog = true
            end,
        }
        StaticPopup_Show("VOICEOVER_REDUX_DUPLICATE_ADDON")
    end

    local function MakeAbandonQuestHook(field, getFieldData)
        return function()
            local data = getFieldData()
            local soundsToRemove = {}
            for _, soundData in ipairs(Player:Queued()) do
                if Enums.SoundEvent:IsQuestEvent(soundData.event) and soundData[field] == data then
                    table.insert(soundsToRemove, soundData)
                end
            end

            for _, soundData in ipairs(soundsToRemove) do
                Player:Remove(soundData)
            end
        end
    end
    if C_QuestLog and C_QuestLog.AbandonQuest then
        hooksecurefunc(C_QuestLog, "AbandonQuest", MakeAbandonQuestHook("questID", function() return C_QuestLog.GetAbandonQuest() end))
    elseif AbandonQuest then
        hooksecurefunc("AbandonQuest", MakeAbandonQuestHook("questName", function() return GetAbandonQuestName() end))
    end

    if QuestLog_Update then
        hooksecurefunc("QuestLog_Update", function()
            QuestOverlayUI:Update()
        end)
    end

    if C_GossipInfo and C_GossipInfo.SelectOption then
        hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID)
            if lastGossipOptions then
                for _, info in ipairs(lastGossipOptions) do
                    if info.gossipOptionID == optionID then
                        selectedGossipOption = info.name
                        break
                    end
                end
                lastGossipOptions = nil
            end
        end)
    elseif SelectGossipOption then
        hooksecurefunc("SelectGossipOption", function(index)
            if lastGossipOptions then
                selectedGossipOption = lastGossipOptions[1 + (index - 1) * 2]
                lastGossipOptions = nil
            end
        end)
    end
end

function Addon:RefreshConfig()
    Player:RefreshConfig()
end

function Addon:ADDON_LOADED(event, addon)
    addon = addon or arg1 -- Thanks, Ace3v...
    local hook = self.OnAddonLoad[addon]
    if hook then
        hook()
    end
end

local function GossipSoundDataAdded(soundData)
    -- Save current gossip sound data for dialog/frame sync option
    currentGossipSoundData = soundData
end

local function QuestSoundDataAdded(soundData)
    -- Save current quest sound data for dialog/frame sync option
    currentQuestSoundData = soundData
end

local function ResolveQuestID(source, questID, questTitle, targetName, questText)
    if questID and questID ~= 0 then
        return questID
    end

    -- On current Classic clients GetQuestID can briefly return 0 while the
    -- QUEST_DETAIL frame is already populated. Resolve it through the loaded
    -- data module's title/NPC/text index instead of silently abandoning the
    -- event. This also handles ambiguous repeated quest titles.
    local fallbackID = DataModules:GetQuestID(source, questTitle or "", targetName or "", questText or "")
    if fallbackID then
        Debug:Record("quest-id-fallback", format("Resolved %q to quest ID %d", questTitle or "", fallbackID))
        return fallbackID
    end

    Debug:Record("quest-id-missing", format("The client returned quest ID 0 and the data module could not resolve %q",
        questTitle or ""))
end

function Addon:QUEST_DETAIL()
    local questID, questTitle, questText, guid, targetName, isObjectOrItem = ReadQuestFields(GetQuestText)

    Debug:Record("quest-detail", format("QUEST_DETAIL: raw ID %s, title %q, NPC %q",
        tostring(questID or "nil"), questTitle or "", targetName or ""))
    questID = ResolveQuestID("accept", questID, questTitle, targetName, questText)
    if not questID then
        return
    end

    if Addon.db.char.RecentQuestTitleToID and questID ~= 0 then
        Addon.db.char.RecentQuestTitleToID[questTitle] = questID
    end

    local type = guid and Utils:GetGUIDType(guid)
    if type == Enums.GUID.Item then
        -- Allow quests started from items to have VO, book icon will be displayed for them
    elseif not type or not Enums.GUID:CanHaveID(type) then
        -- If the quest is started by something that we cannot extract the ID of (e.g. Player, when sharing a quest) - try to fallback to a questgiver from a module's database
        local id
        type, id = DataModules:GetQuestLogQuestGiverTypeAndID(questID)
        guid = id and Enums.GUID:CanHaveID(type) and Utils:MakeGUID(type, id) or guid
        targetName = id and DataModules:GetObjectName(type, id) or targetName or "Unknown Name"
    end

    -- print("QUEST_DETAIL", questID, questTitle);
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestAccept,
        questID = questID,
        name = targetName,
        title = questTitle,
        text = questText,
        unitGUID = guid,
        unitIsObjectOrItem = isObjectOrItem,
        addedCallback = QuestSoundDataAdded,
    }
    Player:Enqueue(soundData)
end

function Addon:QUEST_PROGRESS()
    local questID, questTitle, questText, guid, targetName, isObjectOrItem = ReadQuestFields(GetProgressText)

    Debug:Record("quest-progress", format("QUEST_PROGRESS: raw ID %s, title %q, NPC %q",
        tostring(questID or "nil"), questTitle or "", targetName or ""))
    questID = ResolveQuestID("progress", questID, questTitle, targetName, questText)
    if not questID then
        return
    end

    if Addon.db.char.RecentQuestTitleToID then
        Addon.db.char.RecentQuestTitleToID[questTitle] = questID
    end

    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestProgress,
        questID = questID,
        name = targetName,
        title = questTitle,
        text = questText,
        unitGUID = guid,
        unitIsObjectOrItem = isObjectOrItem,
        addedCallback = QuestSoundDataAdded,
    }
    Player:Enqueue(soundData)
end

function Addon:QUEST_COMPLETE()
    local questID, questTitle, questText, guid, targetName, isObjectOrItem = ReadQuestFields(GetRewardText)

    Debug:Record("quest-complete", format("QUEST_COMPLETE: raw ID %s, title %q, NPC %q",
        tostring(questID or "nil"), questTitle or "", targetName or ""))
    questID = ResolveQuestID("complete", questID, questTitle, targetName, questText)
    if not questID then
        return
    end

    if Addon.db.char.RecentQuestTitleToID and questID ~= 0 then
        Addon.db.char.RecentQuestTitleToID[questTitle] = questID
    end

    -- print("QUEST_COMPLETE", questID, questTitle);
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestComplete,
        questID = questID,
        name = targetName,
        title = questTitle,
        text = questText,
        unitGUID = guid,
        unitIsObjectOrItem = isObjectOrItem,
        addedCallback = QuestSoundDataAdded,
    }
    Player:Enqueue(soundData)
end

function Addon:ShouldPlayGossip(guid, text)
    local npcKey = guid or "unknown"

    local gossipSeenForNPC = self.db.char.hasSeenGossipForNPC[npcKey]

    if self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.OncePerQuestNPC then
        local numActiveQuests = GetNumGossipActiveQuests()
        local numAvailableQuests = GetNumGossipAvailableQuests()
        local npcHasQuests = (numActiveQuests > 0 or numAvailableQuests > 0)
        if npcHasQuests and gossipSeenForNPC then
            return
        end
    elseif self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.OncePerNPC then
        if gossipSeenForNPC then
            return
        end
    elseif self.db.profile.Audio.GossipFrequency == Enums.GossipFrequency.Never then
        return
    end

    return true, npcKey
end

function Addon:QUEST_GREETING()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local greetingText = GetGreetingText()

    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        return
    end

    local play, npcKey = self:ShouldPlayGossip(guid, greetingText)
    if not play then
        return
    end

    -- Play the gossip sound
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.QuestGreeting,
        name = targetName,
        text = greetingText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = GossipSoundDataAdded,
        startCallback = function()
            self.db.char.hasSeenGossipForNPC[npcKey] = true
        end
    }
    Player:Enqueue(soundData)
end

function Addon:GOSSIP_SHOW()
    local guid = Utils:GetNPCGUID()
    local targetName = Utils:GetNPCName()
    local gossipText = GetGossipText()

    -- Can happen if the player interacted with an NPC while having main menu or options opened
    if not guid and not targetName then
        return
    end

    local play, npcKey = self:ShouldPlayGossip(guid, gossipText)
    if not play then
        return
    end

    -- Play the gossip sound
    ---@type SoundData
    local soundData = {
        event = Enums.SoundEvent.Gossip,
        name = targetName,
        title = selectedGossipOption and format([["%s"]], selectedGossipOption),
        text = gossipText,
        unitGUID = guid,
        unitIsObjectOrItem = Utils:IsNPCObjectOrItem(),
        addedCallback = GossipSoundDataAdded,
        startCallback = function()
            self.db.char.hasSeenGossipForNPC[npcKey] = true
        end
    }
    Player:Enqueue(soundData)

    selectedGossipOption = nil
    lastGossipOptions = nil
    if C_GossipInfo and C_GossipInfo.GetOptions then
        lastGossipOptions = C_GossipInfo.GetOptions()
    elseif GetGossipOptions then
        lastGossipOptions = { GetGossipOptions() }
    end
end

function Addon:QUEST_FINISHED()
    if Addon.db.profile.Audio.StopAudioOnDisengage and currentQuestSoundData then
        Player:Remove(currentQuestSoundData)
    end
    currentQuestSoundData = nil
end

function Addon:GOSSIP_CLOSED()
    if Addon.db.profile.Audio.StopAudioOnDisengage and currentGossipSoundData then
        Player:Remove(currentGossipSoundData)
    end
    currentGossipSoundData = nil

    selectedGossipOption = nil
end
