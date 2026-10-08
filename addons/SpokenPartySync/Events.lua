-- The login that wires the addon up, and the events it listens to.
--
-- ADDON_LOADED is where SpokenPartySyncDB and SpokenPartySyncCharDB become readable.
-- PLAYER_ENTERING_WORLD is where the rest is set up: late, as the other Spoken addons do,
-- because the Settings API, the player's API and the modules' sources are all there by then.
-- A source registered later still is found through the player's SOURCE_REGISTERED.

local ADDON_NAME, PartySync = ...

local Comm, Peers, Sync, Accept, Room = PartySync.Comm, PartySync.Peers, PartySync.Sync, PartySync.Accept, PartySync.Room

local frame = CreateFrame("Frame")
PartySync.eventFrame = frame

-- On Forever, registering an event the client does not define throws and aborts the whole
-- file. Each one is registered on its own, and a failure is kept for `/sps api` to report
-- rather than taking the rest of the wiring down with it.
PartySync.missingEvents = {}
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
	"CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "QUEST_DETAIL", "QUEST_ACCEPTED", "QUEST_ACCEPT_CONFIRM" }) do
	if not pcall(frame.RegisterEvent, frame, event) then
		table.insert(PartySync.missingEvents, event)
	end
end

-- GROUP_ROSTER_UPDATE fires several times for one join, and again for every change to anyone's
-- role or subgroup. One hello per burst is enough.
local HELLO_DELAY = 2
local helloQueued = false
local lastGroup
local lastRoster = {}

local function QueueHello()
	if helloQueued then
		return
	end
	helloQueued = true
	C_Timer.After(HELLO_DELAY, function()
		helloQueued = false
		local group = Comm:GroupChannel()
		-- On joining, or on the group becoming a raid: not for every roster change.
		if group and group ~= lastGroup then
			Peers:Hello()
		end
		lastGroup = group
		-- A member who has just joined the group gets a hello by name: they may have logged in
		-- before this client did, and so never heard its own.
		local roster = {}
		for _, unit in ipairs(PartySync:GroupUnits()) do
			local key = PartySync:NameKey(PartySync:UnitChatName(unit))
			if key then
				roster[key] = true
				if not lastRoster[key] and Peers:IsMember(key) then
					Peers:Greet(Peers:MemberName(key))
				end
			end
		end
		lastRoster = roster
		PartySync:Changed()
	end)
end

local started = false

local function Start()
	PartySync.LogBook:Setup()
	PartySync.Diagnostics:Setup()
	Comm:Register()
	Comm:FilterChat()
	Peers:Setup()
	PartySync.Autoform:Setup()
	if not Sync:Setup() then
		PartySync:Print("|cffffcc00Spoken is missing or too old: there is nothing to play together.|r")
	end
	PartySync:SetupOptions()
	PartySync:SetupMinimapEntries()
	PartySync.UnitMenu:Setup()
	PartySync:SetupWindow()
	Room:Update()
	Peers:Resume()
	PartySync.Autoform:Tick()
	started = true
end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		Comm:Receive(...)
	elseif event == "CHAT_MSG_SYSTEM" then
		local name = Comm:ReadSystemMessage((...))
		if name and not Peers:IsProbing() then
			Peers:MarkOffline(name)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		QueueHello()
	elseif event == "PARTY_LEADER_CHANGED" then
		-- Changed() writes the new leader in the debug log, where it moved.
		PartySync:Changed()
	elseif event == "QUEST_DETAIL" then
		Accept:QUEST_DETAIL(...)
	elseif event == "QUEST_ACCEPTED" then
		Accept:QUEST_ACCEPTED(...)
	elseif event == "QUEST_ACCEPT_CONFIRM" then
		Accept:QUEST_ACCEPT_CONFIRM(...)
	elseif event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			PartySync:InitDB()
			frame:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Fires again on every loading screen; the setup only once.
		if not started then
			Start()
		end
		-- A /reload inside a group: say hello again, since whoever was listening lost track.
		lastGroup = nil
		QueueHello()
	end
end)
