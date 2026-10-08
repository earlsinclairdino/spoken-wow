-- Shared by the partysync_*_test.lua files: Spoken and Spoken Quests loaded for real, Spoken
-- Party Sync loaded the way the client loads it, and a scripted second client.
--
-- There is one client in a test, so the other member is played by the test itself: what this
-- client sends is read out of `sent`, and what the other would send is handed in with
-- Receive, as CHAT_MSG_ADDON. Tata Throwaway is this client; Lala Throwaway the other.
local M = {}

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".")
local SPOKEN = here .. "/../../addons/Spoken/"
local QUESTS = here .. "/../../addons/Spoken_Quests/"
local SYNC = here .. "/../../addons/SpokenPartySync/"
local DEVELOPER = here .. "/../../addons/Spoken_Developer/"

M.ME = "Tata Throwaway"
M.LALA = "Lala Throwaway"

-- What the client and its party look like. Each scenario sets what it needs.
M.client = { units = {}, leader = nil, inInstance = false, offererIsPlayer = false, offerer = nil }

local function ClientAPI(stub)
	local client = M.client
	M.sent = {}
	M.calls = {}
	_G.Enum = _G.Enum or {}
	_G.Enum.SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, NotInGroup = 5, TargetOffline = 12 }
	_G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function() return true end,
		IsAddonMessagePrefixRegistered = function() return true end,
		SendAddonMessage = function(prefix, text, channel, target)
			local fields = {}
			for field in (text .. "\t"):gmatch("(.-)\t") do table.insert(fields, field) end
			table.insert(M.sent, { prefix = prefix, text = text, channel = channel, target = target,
				kind = fields[1], fields = fields })
			return 0
		end,
	}
	_G.C_Timer.NewTicker = nil
	_G.GetUnitName = function(unit)
		if unit == "player" then return M.ME end
		if unit == "questnpc" or unit == "npc" then return client.offerer or stub.world.npcName end
		return client.units[unit]
	end
	_G.UnitName = function(unit)
		if unit == "player" then return "Tata", "Throwaway" end
		if unit == "questnpc" or unit == "npc" then return client.offerer or stub.world.npcName end
		local whole = client.units[unit]
		if whole then return whole:match("^(%S+)"), whole:match("%s(%S+)$") end
		return nil
	end
	_G.UnitExists = function(unit)
		if unit == "player" or unit == "npc" or unit == "questnpc" then return true end
		return client.units[unit] ~= nil
	end
	_G.UnitIsUnit = function(a, b) return a == b end
	_G.UnitIsPlayer = function(unit)
		if unit == "questnpc" or unit == "npc" then return client.offererIsPlayer end
		return unit == "player" or client.units[unit] ~= nil
	end
	_G.UnitIsGroupLeader = function(unit) return client.leader == unit end
	_G.IsInRaid = function() return false end
	_G.IsInGroup = function() return next(client.units) ~= nil end
	_G.IsInInstance = function() return client.inInstance, client.inInstance and "party" or "none" end
	_G.GetNormalizedRealmName = function() return "ClassicBetaPvE2" end
	_G.GetBuildInfo = function() return "1.60.1", "70205", "", 16001 end
	_G.LE_PARTY_CATEGORY_HOME = 1
	_G.InCombatLockdown = function() return false end
	_G.time = os.time
	_G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
	_G.ACCEPT, _G.DECLINE = "Accept", "Decline"
	_G.AcceptQuest = function() table.insert(M.calls, "AcceptQuest") end
	_G.ConfirmAcceptQuest = function() table.insert(M.calls, "ConfirmAcceptQuest") end
	_G.StaticPopup_Hide = function() end
	_G.QuestLogPushQuest = function(index) table.insert(M.calls, "QuestLogPushQuest " .. tostring(index)) end
	_G.C_QuestLog = {
		GetLogIndexForQuestID = function(questID) return questID % 100 end,
		IsPushableQuest = function(questID) return questID ~= 999 end,
		SetSelectedQuest = function() end,
		GetTitleForQuestID = function(questID) return "Quest " .. questID end,
	}
	M.menus = {}
	_G.Menu = { ModifyMenu = function(tag, fn) M.menus[tag] = fn end }
end

--- A fresh client: Spoken, Spoken Quests with a test pack, Spoken Party Sync, logged in.
--- `lookup` is the pack's file -> length table.
function M.Boot(stub, lookup)
	-- The last scenario's copy of the addon would hear this one's messages and answer too.
	if M.ns and M.ns.eventFrame then M.ns.eventFrame:UnregisterAllEvents() end
	stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers(); stub.ResetUIActions()
	stub.world.questID = 0; stub.ShowPanel(nil); stub.world.gossipText = nil; stub.world.greetingText = nil
	stub.world.unitSex = 2
	M.client.units, M.client.leader, M.client.inInstance = {}, nil, false
	M.client.offererIsPlayer, M.client.offerer = false, nil
	ClientAPI(stub)
	_G.SpokenPartySyncDB = nil
	local VO, env = stub.LoadQuests(QUESTS, SPOKEN)
	-- The Spoken Developer module, where the tree has it (it keeps the debug log Party Sync
	-- writes into); without it the log tests check that Party Sync does without.
	local developer = io.open(DEVELOPER .. "Spoken_Developer.toc")
	if developer and stub.LoadDeveloper then
		developer:close()
		M.developer = stub.LoadDeveloper(DEVELOPER)
	elseif developer then
		developer:close()
	end
	VO.Addon:OnInitialize()
	VO.DataModules:Register("TestPack", {
		SoundLengthLookupByFileName = lookup,
		GetSoundPath = function(_, fileName) return fileName .. ".ogg" end,
		GossipLookupByNPCID = {},
	})
	stub.Advance(2)
	stub.world.title = "Test Quest"; stub.world.questText = "Go."; stub.world.npcName = "Giver"
	stub.world.npcGUID = "Creature-0-0-0-0-1234-0"

	-- The client loads an addon's files in its TOC's order, each handed the name and one table.
	local ns = {}
	local toc = assert(io.open(SYNC .. "SpokenPartySync.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if line:match("%.lua$") and not line:match("^#") then
			local chunk = assert(loadfile(SYNC .. line:gsub("\\", "/")))
			chunk("SpokenPartySync", ns)
		end
	end
	-- The first-run welcome is the player's business, not these tests'.
	env.Addon.db.global.Welcomed = true
	_G.UISpecialFrames = _G.UISpecialFrames or {}
	stub.FireEvent("ADDON_LOADED", "SpokenPartySync")
	stub.FireEvent("PLAYER_ENTERING_WORLD")
	M.sent = {}
	-- What started, by key: the quests source plays every file once as it is queued, to learn
	-- that it exists, so what PlaySoundFile was given says nothing about when a line began.
	M.started = {}
	_G.Spoken:RegisterCallback("CLIP_STARTED", function(clip) table.insert(M.started, clip.key) end)
	M.ns = ns
	return ns, VO, env, _G.Spoken
end

--- What this client sent of `kind`, oldest first, optionally only to `target`.
function M.Sent(kind, target)
	local list = {}
	for _, message in ipairs(M.sent) do
		if message.kind == kind and (target == nil or message.target == target) then
			table.insert(list, message)
		end
	end
	return list
end

function M.Last(kind, target)
	local list = M.Sent(kind, target)
	return list[#list]
end

function M.Clear()
	M.sent = {}
	M.calls = {}
end

--- Another client's message arriving.
function M.Receive(stub, sender, kind, ...)
	local fields = { kind }
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		table.insert(fields, value == nil and "" or tostring(value))
	end
	stub.FireEvent("CHAT_MSG_ADDON", "SpokenPartySync", table.concat(fields, "\t"), "WHISPER", sender)
end

--- Lala in the party and online, as her hello makes her.
function M.Party(stub, ns, room, lead)
	ns.Peers:AddMember(M.LALA)
	M.Receive(stub, M.LALA, "HI", "0.2.0", 1, lead or "auto", room or "")
	M.Clear()
end

function M.Called(name)
	for _, call in ipairs(M.calls) do
		if call == name or call:sub(1, #name + 1) == name .. " " then return true end
	end
	return false
end

return M
