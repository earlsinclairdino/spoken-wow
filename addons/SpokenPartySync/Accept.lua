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

local Peers, Sync, Comm, L = PartySync.Peers, PartySync.Sync, PartySync.Comm, PartySync.L

local Accept = {}
PartySync.Accept = Accept

local SHARE_DELAY = 0.5
local ACCEPT_DELAY = 0.3
-- Between quests shared one after another: the game turns a share away while the member's
-- dialog for the last one is still open, and a member accepts after ACCEPT_DELAY.
local SHARE_GAP = 2

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

--- `quiet`: no chat line, for a run of shares that says how many once.
function Accept:Share(questID, quiet)
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
	if not quiet then PartySync:Print("shared %s with the party", QuestTitle(questID)) end
	return true
end

--------------------------------------------------------------------------------
-- Every quest at once, by request
--------------------------------------------------------------------------------

-- Bumped by each run, so a newer run stops what an older one has left to share.
local shareRun = 0

--- Every quest in this character's log the game lets it share.
local function ShareableQuests()
	local list = {}
	local log = C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then
		return list
	end
	for index = 1, log.GetNumQuestLogEntries() or 0 do
		local info = log.GetInfo(index)
		local questID = info and not info.isHeader and info.questID
		if questID and questID ~= 0 and (not log.IsPushableQuest or log.IsPushableQuest(questID)) then
			table.insert(list, questID)
		end
	end
	return list
end

--- Why this character would not share its quests now: "party", "rule", "group" or "none".
local function WhyNoShareAll(quests)
	if not Peers:InParty() then return "party" end
	if not Peers:MayShare() then return "rule" end
	if not MemberInGroup() then return "group" end
	if not quests[1] then return "none" end
	return nil
end

--- What a "why" says, on the side that reads it: the rule in its own words.
function Accept:Reason(why)
	if why == "rule" then
		return (Peers:Rules().share or "anyone") == "leader" and L.SHARE_LEADER or L.SHARE_NOBODY
	end
	return ({ party = L.OPT_IN_PARTY, group = L.SHARE_NO_GROUP, none = L.SHARE_NONE })[why] or tostring(why)
end

--- Share every quest the log can share, SHARE_GAP apart. Returns how many, or nil and why.
function Accept:ShareAll()
	local quests = ShareableQuests()
	local why = WhyNoShareAll(quests)
	if why then
		PartySync:Trace("quests", "not sharing every quest: %s", why)
		return nil, why
	end
	shareRun = shareRun + 1
	local run = shareRun
	for i, questID in ipairs(quests) do
		C_Timer.After((i - 1) * SHARE_GAP, function()
			if run == shareRun and Peers:InParty() then Accept:Share(questID, true) end
		end)
	end
	PartySync:Trace("quests", "sharing every quest: %d", #quests)
	return #quests
end

--- Why `key` would not share when asked, as far as this computer knows the rule, or nil.
function Accept:WhyNotAsk(key)
	if not Peers:InParty() then return L.OPT_IN_PARTY end
	local share = Peers:Rules().share or "anyone"
	if share == "nobody" then return L.SHARE_NOBODY end
	if share == "leader" and key ~= Peers:Leader() then return L.SHARE_LEADER end
	return nil
end

local function ShareHere()
	local count, why = Accept:ShareAll()
	if count then
		PartySync:Print("sharing your %d quest(s) with the party", count)
	else
		PartySync:Print("%s", Accept:Reason(why))
	end
	return count ~= nil
end

--- Ask `key` to share every quest it can; this character's own key shares here.
function Accept:Ask(key)
	local why = self:WhyNotAsk(key)
	if why then
		PartySync:Print("%s", why)
		return false
	end
	if key == PartySync:MyKey() then
		return ShareHere()
	end
	local name = Peers:MemberName(key)
	PartySync:Trace("quests", "asking %s to share every quest", key)
	Comm:Whisper(name, "SQ")
	PartySync:Print("asked %s to share their quests", PartySync:ShortName(name))
	return true
end

--- Everyone shares every quest: this character's here, and each member online who may share
--- is asked for theirs.
function Accept:AskAll()
	if not Peers:InParty() then
		PartySync:Print("%s", L.OPT_IN_PARTY)
		return false
	end
	local asked = {}
	for _, key in ipairs(Peers:OnlineMembers()) do
		if not self:WhyNotAsk(key) then
			Comm:Whisper(Peers:MemberName(key), "SQ")
			table.insert(asked, PartySync:ShortName(Peers:MemberName(key)))
		end
	end
	PartySync:Trace("quests", "asking everyone to share every quest: %s", table.concat(asked, ", "))
	if asked[1] then PartySync:Print("asked %s to share their quests", table.concat(asked, ", ")) end
	if not self:WhyNotAsk(PartySync:MyKey()) then
		ShareHere()
	elseif not asked[1] then
		PartySync:Print("%s", self:WhyNotAsk(PartySync:MyKey()))
	end
	return true
end

Comm:On("SQ", function(sender)
	if not Peers:IsMember(sender) then return end
	local count, why = Accept:ShareAll()
	local who = PartySync:ShortName(sender)
	if count then
		PartySync:Print("%s asked you to share your quests: sharing %d", who, count)
	else
		PartySync:Print("%s asked you to share your quests: %s", who, Accept:Reason(why))
	end
	Comm:Whisper(sender, "SA", count or 0, why or "")
end)

Comm:On("SA", function(sender, channel, count, why)
	if not Peers:IsMember(sender) then return end
	count = tonumber(count) or 0
	local who = PartySync:ShortName(sender)
	if count > 0 then
		PartySync:Print("%s is sharing %d quest(s) with the party", who, count)
	else
		PartySync:Print("%s shares no quest: %s", who, Accept:Reason(why ~= "" and why or "none"))
	end
end)
