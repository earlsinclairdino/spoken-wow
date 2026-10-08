-- Quests for the whole party: a member shares what it accepts, as the party's Quests Are
-- Shared By rule allows (anyone, by default), and the others accept what a member shares.
--
-- The sharer's accept line has just played on every computer, so the share it sends is
-- accepted without the dialog being read a second time: Sync refuses the accept line the
-- shared dialog would queue (Sync:ExpectShared). Only quests the game lets you share are
-- shared, and only with a member in the group, since the game shares with the group alone.
--
-- Acceptance waits a moment after the dialog opens, so Spoken Quests has read the dialog's
-- text first, as it does for any addon that accepts quests for the player.

local _, PartySync = ...

local Peers, Sync = PartySync.Peers, PartySync.Sync

local Accept = {}
PartySync.Accept = Accept

local SHARE_DELAY = 0.5
local ACCEPT_DELAY = 0.3

-- The last quest dialog: which quest, and whether a player rather than an NPC offered it.
local lastDetail = {}

--- Who is offering the quest on screen, and whether they are a player sharing it.
local function Offerer()
	for _, unit in ipairs({ "questnpc", "npc" }) do
		local ok, exists = pcall(UnitExists, unit)
		if ok and exists then
			return UnitIsPlayer(unit) and true or false, PartySync:UnitChatName(unit)
		end
	end
	return false, nil
end

local function QuestTitle(questID)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local title = C_QuestLog.GetTitleForQuestID(questID)
		if title then return title end
	end
	return GetTitleText and GetTitleText() or tostring(questID)
end

function Accept:QUEST_DETAIL()
	local questID = GetQuestID and GetQuestID() or 0
	local fromPlayer, offerer = Offerer()
	lastDetail = { questID = questID, fromPlayer = fromPlayer, at = GetTime() }
	PartySync:Trace("quests", "dialog for quest %s, offered by %s%s", tostring(questID), tostring(offerer),
		fromPlayer and " (a player)" or "")
	if not (fromPlayer and PartySync:DB().autoAccept and Peers:IsMember(offerer)) then
		return
	end
	if questID and questID ~= 0 then
		Sync:ExpectShared(questID)
	end
	local title = GetTitleText and GetTitleText() or ""
	C_Timer.After(ACCEPT_DELAY, function()
		-- The dialog moved on or closed meanwhile: that was the player's own answer.
		if (GetQuestID and GetQuestID() or 0) ~= questID then
			return
		end
		PartySync:Trace("quests", "accepting quest %s, shared by %s", tostring(questID), tostring(offerer))
		if QuestGetAutoAccept and QuestGetAutoAccept() and AcknowledgeAutoAcceptQuest then
			AcknowledgeAutoAcceptQuest()
		else
			AcceptQuest()
		end
		PartySync:Print("accepted %s, shared by %s", title ~= "" and title or tostring(questID), PartySync:ShortName(offerer))
	end)
end

--- An escort or event quest a member started: the game asks everyone nearby to join.
function Accept:QUEST_ACCEPT_CONFIRM(name, questTitle)
	if not (PartySync:DB().autoAccept and name and Peers:IsMember(name)) then
		return
	end
	if ConfirmAcceptQuest then
		ConfirmAcceptQuest()
		if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT") end
		PartySync:Print("joined %s, started by %s", tostring(questTitle), PartySync:ShortName(name))
	end
end

local function MemberInGroup()
	for _, key in ipairs(Peers:OnlineMembers()) do
		if PartySync:UnitFor(Peers:MemberName(key)) then
			return true
		end
	end
	return false
end

--- Classic sends the quest log index first and the quest second; Retail the quest alone.
function Accept:QUEST_ACCEPTED(first, second)
	local questID = tonumber(second or first)
	if not questID then
		return
	end
	if not (PartySync:DB().autoShare and Peers:MayShare() and MemberInGroup()) then
		return
	end
	-- Shared with this character in the first place: sharing it back would be noise.
	if lastDetail.fromPlayer and lastDetail.questID == questID then
		return
	end
	C_Timer.After(SHARE_DELAY, function() Accept:Share(questID) end)
end

function Accept:Share(questID)
	local index
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		index = C_QuestLog.GetLogIndexForQuestID(questID)
	elseif GetQuestLogIndexByID then
		index = GetQuestLogIndexByID(questID)
	end
	if not index or index == 0 then
		return false
	end
	local pushable
	if C_QuestLog and C_QuestLog.IsPushableQuest then
		pushable = C_QuestLog.IsPushableQuest(questID)
	end
	-- The older API shares whichever quest the log has selected, and says of that one.
	if SelectQuestLogEntry then
		SelectQuestLogEntry(index)
	end
	if pushable == nil and GetQuestLogPushable then
		pushable = GetQuestLogPushable()
	end
	if not pushable or not QuestLogPushQuest then
		return false
	end
	if C_QuestLog and C_QuestLog.SetSelectedQuest then
		C_QuestLog.SetSelectedQuest(questID)
	end
	PartySync:Trace("quests", "sharing quest %d (log index %d)", questID, index)
	QuestLogPushQuest(index)
	PartySync:Print("shared %s with the party", QuestTitle(questID))
	return true
end
