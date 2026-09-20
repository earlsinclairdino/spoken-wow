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
stub.HidePanels()
world.questID = 9401
world.title = "Nothing Heard Yet"
world.questText = "Words with no line in the corpus."
world.npcName = "Deathguard Linnea"
-- A guid not reused anywhere else in this file: the model cache is keyed by guid and never
-- reset between scenarios, so a guid this test has seen before would already be cached (or
-- mid-load) from earlier in the run, and "priming a fresh NPC" would not be testing what it
-- says it is.
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

-- A second refresh for the same NPC, still mid-load, must not ask again.
Expect("still a gap on the next refresh", VoiceOver.Contribute:HasGap(), true)
Expect("...and no second SetUnit for the same guid while it is loading",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitBefore + 1)

-- The load finishes the way a live client fires it -- not a timer this addon polls.
stub.FinishModelLoad()

local seen = VoiceOver.Contribute:Capture()
Expect("the model file id is reported once the load has fired", seen:match("\nmodel=122055\n") ~= nil, true)
Expect("the sex the client reports is carried too", seen:match("\nsex=2\n") ~= nil, true)
Expect("the creature type is carried", seen:match("\ncreature=Humanoid\n") ~= nil, true)
Expect("a creature guid is reported as a creature", seen:match("\nkind=creature\n") ~= nil, true)
Expect("no race is decided here", seen:match("\nrace=") == nil, true)

-- A third refresh for the same, now-cached NPC still must not ask again.
Expect("still a gap once cached", VoiceOver.Contribute:HasGap(), true)
Expect("...and no further SetUnit once the guid is cached",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitBefore + 1)

-- A different NPC is a different guid, and is worth asking about once of its own.
world.npcGUID = "Creature-0-0-0-0-90002-0"
world.npcName = "Someone Else"
Expect("a different NPC is still a gap", VoiceOver.Contribute:HasGap(), true)
Expect("...and does call SetUnit once, for the new guid",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitBefore + 2)

-- A model that resolves to nothing (this NPC's own load finishing with none) leaves the
-- field out rather than sending a zero: the site treats an absent model as "unknown race".
world.modelFileID = nil
stub.FinishModelLoad()
local blind = VoiceOver.Contribute:Capture()
Expect("an unavailable model is omitted, not sent as 0", blind:match("\nmodel=") == nil, true)
Expect("...and the envelope is still sent", blind:match("^!SPOKEN1 quests\n") ~= nil, true)

-- The model frame is built at most once, and never merely because the button refreshed --
-- and once a guid is cached (as this one now is), asking again must not even touch the probe.
local framesBefore = stub.FrameCount and stub.FrameCount() or 0
local setUnitCallsBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
VoiceOver.Contribute:HasGap()
Expect("asking again for an already-cached NPC builds no model frame",
    (stub.FrameCount and stub.FrameCount() or 0), framesBefore)
Expect("...and calls SetUnit no further times",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), setUnitCallsBefore)

-- With nothing on screen at all, HasGap must not reach the model probe even to look --
-- this is the case a previous version of this test only covered by accident, since the
-- guid it asked about happened to already be cached.
stub.HidePanels()
local idleSetUnitBefore = stub.SetUnitCount and stub.SetUnitCount() or 0
VoiceOver.Contribute:HasGap()
Expect("asking whether there is a gap with nothing on screen never touches the model probe",
    (stub.SetUnitCount and stub.SetUnitCount() or 0), idleSetUnitBefore)

os.exit(Failures() == 0 and 0 or 1)
