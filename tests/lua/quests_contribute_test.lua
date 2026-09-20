-- What the quests addon offers to send when it has no line. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local world = stub.world
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local QUESTS = here .. "/../../addons/SpokenQuests/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
-- The loader quest_dispatch_test.lua and quest_overlay_test.lua use: it boots the player
-- itself, so there is no separate stub.LoadSpoken call here.
local VoiceOver = stub.LoadQuests(QUESTS, SPOKEN)

-- The addon's own .toc Version, as GetAddOnMetadata(AddonFolder, "Version") reads it -- picked
-- deliberately unlike anything in the real .toc, so the assertion below cannot pass by
-- coincidentally matching it; it is pinning that Contribute:Capture reads a real version, not
-- confirming a particular one. TestPack stays alongside it: OnInitialize's EnumerateAddons has
-- to see TestPack in this same list, or the DataModules:Register call further down (which
-- asserts a module was detected during enumeration) fails.
stub.SetAddOns({
    { folder = "SpokenQuests", meta = { Version = "9.9.9" } },
    { folder = "TestPack", meta = { ["X-VoiceOver-DataModule-Version"] = "1", Version = "1.2.1", Title = "TestPack" } },
})

world.questID = 9123
world.title = "A Rough Start"
world.questText = "Kill six of them.\nThen come back."
world.npcName = "Deathguard Linnea"
world.npcGUID = "Creature-0-0-0-0-12345-0"
stub.ShowPanel("QuestFrameDetailPanel")

local envelope = VoiceOver.Contribute:Capture()
Expect("the source is quests", envelope:match("^!SPOKEN1 quests\n") ~= nil, true)
Expect("the quest id is carried", envelope:match("\nquest=9123\n") ~= nil, true)
Expect("the event is the panel on screen", envelope:match("\nevent=accept\n") ~= nil, true)
Expect("the npc is carried", envelope:match("\nnpc=12345 Deathguard Linnea\n") ~= nil, true)
Expect("the title is carried", envelope:match("\ntitle=A Rough Start\n") ~= nil, true)
Expect("the text is the client's", envelope:match("\nKill six of them%.\nThen come back%.\n") ~= nil, true)
Expect("the locale is carried", envelope:match("\nlocale=%a+\n") ~= nil, true)
Expect("the build is carried", envelope:match("\nbuild=") ~= nil, true)
Expect("no character name is carried", envelope:match(world.playerName or "Tester") == nil, true)
Expect("the addon field carries the real .toc version, not the \"dev\" fallback",
    envelope:match("\naddon=SpokenQuests/9%.9%.9\n") ~= nil, true)

-- Gossip: no quest, but an NPC and their words are worth having.
stub.HidePanels()
stub.ShowGossip("We stand ready.")
local gossip = VoiceOver.Contribute:Capture()
Expect("gossip carries the npc and no quest", gossip:match("\nquest=") == nil, true)
Expect("...and the gossip text", gossip:match("\nWe stand ready%.\n") ~= nil, true)

stub.HidePanels()
Expect("nothing on screen contributes nothing", VoiceOver.Contribute:Capture(), nil)

-- The button: on the Blizzard quest frame, not stubbed out of LoadQuests the way
-- QuestOverlayUI and Options are, since this test is specifically about it. Built by
-- Addon:OnInitialize the same way ReportButton's popup is, and kept in sync by its own event
-- frame (registered in Setup, not a timer) -- stub.FireEvent is what lets a test trigger a
-- refresh the way the real events VoiceOver.lua already registers would.
dofile(QUESTS .. "UI/ContributeButton.lua")
VoiceOver.Addon:OnInitialize()
-- Wait out the deferred data module load OnInitialize schedules, as the other quests tests do.
stub.Advance(2)

world.questID = 9123
world.title = "A Rough Start"
world.questText = "Kill six of them.\nThen come back."
stub.ShowPanel("QuestFrameDetailPanel")
stub.FireEvent("QUEST_DETAIL")
Expect("the button appears on the quest detail panel when there is a gap",
    VoiceOver.ContributeButton.button:IsShown(), true)

-- A pack picks up the line: the gap closes, and the button goes with it on the next event.
VoiceOver.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = { ["9123-accept"] = 1 },
})
stub.FireEvent("QUEST_DETAIL")
Expect("...and disappears once a data module has the line", VoiceOver.ContributeButton.button:IsShown(), false)

stub.HidePanels()
stub.FireEvent("QUEST_FINISHED")
Expect("...and stays hidden once the panel closes", VoiceOver.ContributeButton.button:IsShown(), false)

-- The Reward panel on a modern client ships no Cancel button at all (RowButtonsFor's
-- comment): faked here by removing the global, since the stub otherwise creates all six quest
-- buttons regardless of client. The button must still place itself off the one button that
-- exists.
_G.QuestFrameCancelButton = nil
world.rewardText = "Here is your reward."
stub.ShowPanel("QuestFrameRewardPanel")
stub.FireEvent("QUEST_COMPLETE")
Expect("the button still shows beside CompleteQuestButton when there is no Cancel button",
    VoiceOver.ContributeButton.button:IsShown(), true)
-- Pinning the branch, not just surviving it: only the fixed-width fallback calls SetWidth(CONTRIBUTE_WIDTH)
-- at all, so a regression that instead tried (and silently mis-anchored) a two-point SetPoint
-- against the missing right-hand button would leave the button at its untouched default width
-- rather than the fallback width, and this would catch it even though IsShown() above would not.
Expect("...at the fixed fallback width, not a stretched two-point anchor",
    VoiceOver.ContributeButton.button:GetWidth(), 110)
stub.HidePanels()

-- Gossip, on the client generations whose GossipFrame this addon can actually anchor to (see
-- GossipGoodbyeButton's comment): no quest panel, so PositionOnQuestPanel never runs, and the
-- button is placed beside GossipFrame.GreetingPanel.GoodbyeButton instead.
stub.ShowGossip("We stand ready.")
stub.FireEvent("GOSSIP_SHOW")
Expect("the button appears on gossip too, once a Goodbye button can be found",
    VoiceOver.ContributeButton.button:IsShown(), true)

-- The legacy fallback: no GreetingPanel.GoodbyeButton (as the three original 1.12/2.4.3/3.3.5
-- clients might not have -- see GossipGoodbyeButton's comment), but a flat, older-style global
-- in its place. The field is removed outright rather than through stub.absentAPI: absentAPI
-- only changes what the Widget metatable answers when a lookup falls through to it, and
-- GreetingPanel is a real field this stub assigns once at load (not something the metatable
-- was ever asked about), so absentAPI has no effect on it -- setting it, as an earlier version
-- of this test did, left the real GreetingPanel.GoodbyeButton in place and passed without ever
-- reaching the fallback. Saved and restored so later code in this file still sees the real one.
local savedGreetingPanel = _G.GossipFrame.GreetingPanel
_G.GossipFrame.GreetingPanel = nil
_G.GossipGreetingGoodbyeButton = stub.Widget("Button", "GossipGreetingGoodbyeButton")
stub.ShowGossip("Legacy words.")
stub.FireEvent("GOSSIP_SHOW")
Expect("the legacy global is used when the parentKey path is absent",
    VoiceOver.ContributeButton.button:IsShown(), true)
_G.GossipFrame.GreetingPanel = savedGreetingPanel

---------------------------------------------------------------- the closing gossip frame
-- CloseGossip fires GOSSIP_CLOSED, which refreshes the button, and on a real client the
-- gossip text is still readable for that instant while the unit behind it is already gone.
-- VoiceOver.lua's own GOSSIP_SHOW guards the same case -- "the player interacted with an NPC
-- while having main menu or options opened" -- because DataModules keys gossip on the NPC's
-- name when there is no GUID, and a nil name reaches string.gsub as nil.
stub.HidePanels()
stub.ShowGossip("Words with nobody left to say them.")
local savedName, savedGUID = world.npcName, world.npcGUID
world.npcName, world.npcGUID = nil, nil

local askedGap, gapAnswer = pcall(function() return VoiceOver.Contribute:HasGap() end)
Expect("a gossip frame closing under us does not error", askedGap, true)
Expect("...and offers nothing, having no NPC to attribute the words to", gapAnswer, false)

local askedCapture, captured = pcall(function() return VoiceOver.Contribute:Capture() end)
Expect("capturing the same moment does not error", askedCapture, true)
Expect("...and sends nothing, since the server keys gossip on the creature id", captured, nil)

world.npcName, world.npcGUID = savedName, savedGUID

------------------------------------------------------------------------------- Show()
-- Compression must run on the click alone -- HasGap fires on every quest and gossip event --
-- and this spies on Encode rather than trusting the comment, so a future edit that moved the
-- call into Capture/HasGap would fail here rather than merely cost more.
world.title = "A Rough Start"
world.questText = "Kill six of them.\nThen come back."
stub.ShowPanel("QuestFrameDetailPanel")
local encodeCalls = 0
local realEncode = Spoken.Contribute.Encode
Spoken.Contribute.Encode = function(...)
    encodeCalls = encodeCalls + 1
    return realEncode(...)
end
VoiceOver.Contribute:HasGap()
VoiceOver.Contribute:Capture()
Expect("HasGap/Capture never encode", encodeCalls, 0)

VoiceOver.Contribute:Show()
Expect("...only Show() does", encodeCalls, 1)
local box = Spoken.ContributeBox
Expect("Show() puts a link in the box, not the raw envelope",
    box.editBox:GetText():match("^https://spoken%.rusty%.one/contribute#e1=") ~= nil, true)
Expect("...with the link hint", box.hint:GetText(), "Copy this and open it in your browser:")
Spoken.Contribute.Encode = realEncode

-- The fallback an older bundled SpokenPlayer still gets: no Encode at all.
Spoken.Contribute.Encode = nil
VoiceOver.Contribute:Show()
Expect("...falls back to the raw envelope when Encode is absent",
    box.editBox:GetText():match("^!SPOKEN1 quests\n") ~= nil, true)
Expect("...with the old two-copy hint", box.hint:GetText(), "Press Ctrl+C, then paste it at:")
Expect("...and the address shown again", box.address:GetText(), "https://spoken.rusty.one/contribute")
Spoken.Contribute.Encode = realEncode

---------------------------------------------------------------- what the client saw
-- The site works out the race from the model file id; the addon only reports it. PlayerModel
-- loads asynchronously -- probed against a live client, SetUnit followed immediately by
-- GetModelFileID answers nothing, and the same read a moment later answers the real file id
-- -- so the model is never read on the click. HasGap pre-warms it into a cache keyed by NPC
-- guid while the panel is still on screen (a player reads a quest for seconds), and Capture
-- only ever looks the guid up.
--
-- OnModelLoaded is a fast path here, not a requirement: whether a real client ever calls it
-- for a PlayerModel built this way has not been confirmed. Every guid below resolves either
-- through it firing (stub.FinishModelLoad) or through the fallback that reads the
-- still-shown probe directly on a later refresh (stub.modelCallbackDisabled) -- the same
-- outcome either way, which is the point.
stub.HidePanels()
world.questID = 9401
world.title = "Nothing Heard Yet"
world.questText = "Words with no line in the corpus."
world.npcName = "Deathguard Linnea"
-- Guids not reused anywhere else in this file: the model cache is keyed by guid and never
-- reset between scenarios, so a guid this test has seen before would already be cached (or
-- mid-load) from earlier in the run, and these tests would not be testing what they say.
world.npcGUID = "Creature-0-0-0-0-90001-0"
world.modelFileID = 122055
world.unitSex = 2
world.creatureType = "Humanoid"
stub.ShowPanel("QuestFrameDetailPanel")

local setUnitBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
Expect("there is a gap to prime the model for", VoiceOver.Contribute:HasGap(), true)
Expect("priming a fresh NPC calls SetUnit once",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitBefore + 1)

local beforeLoad = VoiceOver.Contribute:Capture()
Expect("nothing cached yet is omitted, not sent as 0", beforeLoad:match("\nmodel=") == nil, true)
Expect("...and the envelope is still sent", beforeLoad:match("^!SPOKEN1 quests\n") ~= nil, true)

-- OnModelLoaded firing (the fast path) resolves the guid without waiting for another refresh.
stub.FinishModelLoad()

local seen = VoiceOver.Contribute:Capture()
Expect("the model file id is reported once the load has fired", seen:match("\nmodel=122055\n") ~= nil, true)
Expect("the sex the client reports is carried too", seen:match("\nsex=2\n") ~= nil, true)
Expect("the creature type is carried", seen:match("\ncreature=Humanoid\n") ~= nil, true)
Expect("a creature guid is reported as a creature", seen:match("\nkind=creature\n") ~= nil, true)
Expect("no race is decided here", seen:match("\nrace=") == nil, true)

-- Once cached, a further refresh for the same NPC must not ask again.
Expect("still a gap once cached", VoiceOver.Contribute:HasGap(), true)
Expect("...and no further SetUnit once the guid is cached",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitBefore + 1)

-- A different NPC is a different guid, and is worth asking about once of its own.
world.npcGUID = "Creature-0-0-0-0-90002-0"
world.npcName = "Someone Else"
Expect("a different NPC is still a gap", VoiceOver.Contribute:HasGap(), true)
Expect("...and does call SetUnit once, for the new guid",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitBefore + 2)

---------------------------------------------------------- when OnModelLoaded never fires
-- Correctness must not depend on this script actually firing: pcall(SetScript, ...)
-- succeeding only proves it was registered, not that the client will ever call it.
stub.modelCallbackDisabled = true

-- A guid whose model does load, just with nothing ever announcing it: the second refresh,
-- still mid-load, must not call SetUnit again, and reading the still-shown probe directly
-- resolves it anyway.
world.npcGUID = "Creature-0-0-0-0-90003-0"
world.npcName = "Never Announces"
world.modelFileID = 987654
local pollSetUnitBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
Expect("priming this NPC is still a gap", VoiceOver.Contribute:HasGap(), true)
Expect("priming calls SetUnit once",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), pollSetUnitBefore + 1)
local stillLoading = VoiceOver.Contribute:Capture()
Expect("nothing cached on the priming refresh itself", stillLoading:match("\nmodel=") == nil, true)

Expect("a second refresh, with no callback ever firing, is still a gap",
    VoiceOver.Contribute:HasGap(), true)
Expect("...and does not call SetUnit again while still loading",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), pollSetUnitBefore + 1)
local polled = VoiceOver.Contribute:Capture()
Expect("the callback never firing still resolves the model by the second refresh",
    polled:match("\nmodel=987654\n") ~= nil, true)

-- A guid whose model never loads at all: polling gives up after a couple of refreshes rather
-- than leaving the probe shown (and loading) forever.
world.npcGUID = "Creature-0-0-0-0-90004-0"
world.npcName = "Never Loads"
world.modelFileID = nil
local giveUpSetUnitBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
Expect("priming this NPC is a gap too", VoiceOver.Contribute:HasGap(), true)
Expect("the probe is shown while its load is pending",
    stub.playerModel and stub.playerModel.shown, true)
Expect("one refresh in, still trying", VoiceOver.Contribute:HasGap(), true)
Expect("a second refresh gives up on this guid", VoiceOver.Contribute:HasGap(), true)
Expect("...and the probe is put away rather than left shown",
    stub.playerModel and stub.playerModel.shown, false)
Expect("...having called SetUnit only the original once",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), giveUpSetUnitBefore + 1)
local gaveUp = VoiceOver.Contribute:Capture()
Expect("a guid that gave up is omitted, not sent as 0", gaveUp:match("\nmodel=") == nil, true)

stub.modelCallbackDisabled = false

-- The model frame is built at most once, and never merely because the button refreshed --
-- and once a guid has resolved (as this one now has, with a cached miss), asking again must
-- not even touch the probe.
local framesBefore = stub.FrameCount and stub.FrameCount() or 0
local setUnitCallsBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
VoiceOver.Contribute:HasGap()
Expect("asking again for an already-resolved NPC builds no model frame",
    (stub.FrameCount and stub.FrameCount() or 0), framesBefore)
Expect("...and calls SetUnit no further times",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitCallsBefore)

-- With nothing on screen at all, HasGap must not reach the model probe even to look.
stub.HidePanels()
local idleSetUnitBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
VoiceOver.Contribute:HasGap()
Expect("asking whether there is a gap with nothing on screen never touches the model probe",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), idleSetUnitBefore)

os.exit(Failures() == 0 and 0 or 1)
