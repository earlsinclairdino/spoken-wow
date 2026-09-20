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
-- in its place. stub.absentAPI is what makes a Widget answer a capitalised lookup with nil
-- rather than the generic no-op every other method gets -- GreetingPanel reads as data here,
-- not a method call, so it has to disappear rather than resolve to a callable stand-in.
stub.absentAPI.GreetingPanel = true
_G.GossipGreetingGoodbyeButton = stub.Widget("Button", "GossipGreetingGoodbyeButton")
stub.ShowGossip("Legacy words.")
stub.FireEvent("GOSSIP_SHOW")
Expect("the legacy global is used when the parentKey path is absent",
    VoiceOver.ContributeButton.button:IsShown(), true)
stub.absentAPI.GreetingPanel = nil

os.exit(Failures() == 0 and 0 or 1)
