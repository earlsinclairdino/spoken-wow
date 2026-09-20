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
-- Addon:OnInitialize the same way ReportButton's popup is, and kept in sync by the repeating
-- timer it schedules there -- Advance() is what lets a test observe that without waiting on
-- the real client's clock.
dofile(QUESTS .. "UI/ContributeButton.lua")
VoiceOver.Addon:OnInitialize()
-- Wait out the deferred data module load OnInitialize schedules, as the other quests tests do.
stub.Advance(2)

world.questID = 9123
world.title = "A Rough Start"
world.questText = "Kill six of them.\nThen come back."
stub.ShowPanel("QuestFrameDetailPanel")
stub.Advance(0.3)
Expect("the button appears on the quest detail panel when there is a gap",
    VoiceOver.ContributeButton.button:IsShown(), true)

-- A pack picks up the line: the gap closes, and the button goes with it.
VoiceOver.DataModules:Register("TestPack", {
    SoundLengthLookupByFileName = { ["9123-accept"] = 1 },
})
stub.Advance(0.3)
Expect("...and disappears once a data module has the line", VoiceOver.ContributeButton.button:IsShown(), false)

stub.HidePanels()
stub.Advance(0.3)
Expect("...and stays hidden once the panel closes", VoiceOver.ContributeButton.button:IsShown(), false)

-- Gossip, on the client generations whose GossipFrame this addon can actually anchor to (see
-- GossipGoodbyeButton's comment): no quest panel, so PositionOnQuestPanel never runs, and the
-- button is placed beside GossipFrame.GreetingPanel.GoodbyeButton instead.
stub.ShowGossip("We stand ready.")
stub.Advance(0.3)
Expect("the button appears on gossip too, once a Goodbye button can be found",
    VoiceOver.ContributeButton.button:IsShown(), true)

os.exit(Failures() == 0 and 0 or 1)
