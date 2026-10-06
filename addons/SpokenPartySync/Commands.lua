-- /spokenpartysync and /sps, beside /spoken, /spq, /spz and /spb.
--
-- The connection tests stay: they are what someone with a connection problem runs to find out
-- which half of it is broken.

local _, PartySync = ...

local Comm, Peers, Sync, Room, L = PartySync.Comm, PartySync.Peers, PartySync.Sync, PartySync.Room, PartySync.L

local function Yes(value)
	return value and "|cff60ff60yes|r" or "|cffff6060no|r"
end

--- What the client has, of everything this addon relies on.
local function Api()
	local version, build, _, interface = GetBuildInfo()
	PartySync:Print("client %s (%s), interface %s, addon %s", tostring(version), tostring(build),
		tostring(interface), PartySync.version)
	for _, entry in ipairs(Comm:Probe()) do
		PartySync:Print("  %s: %s", entry[1], Yes(entry[2]))
	end
	local registered, answer = Comm:Register()
	PartySync:Print("  prefix %q registered: %s (%s)", Comm.PREFIX, Yes(registered), tostring(answer))
	if #PartySync.missingEvents > 0 then
		PartySync:Print("  |cffff6060events this client does not have: %s|r", table.concat(PartySync.missingEvents, ", "))
	else
		PartySync:Print("  events: %s", Yes(true))
	end
	PartySync:Print("  group channel: %s; now: %s", tostring(Comm:GroupChannel() or "none"), Comm:Context())
	local first, second = UnitName("player")
	PartySync:Print("  you: UnitName %q + %q, chat name %q", tostring(first), tostring(second),
		tostring(PartySync:UnitChatName("player")))
	local Spoken = _G.Spoken
	PartySync:Print("  Spoken player: %s; captions-only override: %s", Yes(PartySync:PlayerAvailable()),
		Yes(Spoken and Spoken.SetCaptionsOnlyOverride ~= nil))
	if Spoken and Spoken.GetSource then
		for _, key in ipairs({ "quests", "zones", "books" }) do
			local source = Spoken:GetSource(key)
			PartySync:Print("  %s: %s%s", key, source and "installed" or "|cff909090not installed|r",
				source and (source.rebuild and ", can play the party's lines" or " |cffff6060but too old to play the party's lines|r") or "")
		end
	end
	PartySync:Print("  portrait menu: %s%s", Yes(PartySync.UnitMenu.ready),
		PartySync.UnitMenu.hooked[1] and (" (" .. table.concat(PartySync.UnitMenu.hooked, ", ") .. ")") or "")
	PartySync:Print("  quest sharing: %s", Yes(QuestLogPushQuest ~= nil
		and ((C_QuestLog and C_QuestLog.IsPushableQuest) or GetQuestLogPushable) ~= nil))
end

local function Members()
	local any = false
	local leader = Peers:Leader()
	for key in Peers:Members() do
		any = true
		local peer = Peers.list[key]
		PartySync:Print("  %s: %s%s%s%s", Peers:MemberName(key), peer and peer.state or "not heard from",
			peer and peer.rtt and format(", %d ms", math.floor(peer.rtt + 0.5)) or "",
			peer and peer.version and (", v" .. peer.version) or "",
			key == leader and ", leads" or "")
	end
	if not any then
		PartySync:Print("  nobody yet: /sps invite <name>, or right-click their portrait")
	end
	PartySync:Print("  leader: %s; sound: %s", leader and PartySync:ShortName(Peers:MemberName(leader)) or "?",
		Room:Speaker() and PartySync:ShortName(Peers:MemberName(Room:Speaker())) or "every computer")
end

local function Status()
	PartySync:Print("group: %s; %s", tostring(Comm:GroupChannel() or "none"), Comm:Context())
	PartySync:Print("debug log: %s", not PartySync.LogBook:Available() and "no Spoken Developer module"
		or PartySync.LogBook:IsOn() and "on" or "off (Spoken > Developer, or /spoken log on)")
	Members()
	local others = false
	for key, peer in pairs(Peers.list) do
		if not Peers:IsMember(key) then
			if not others then PartySync:Print("others running the addon:") end
			others = true
			PartySync:Print("  %s: %s", peer.name or key, tostring(peer.state))
		end
	end
end

local function Lines()
	local list = Sync:Entries()
	if not list[1] then
		PartySync:Print("no line played together this session yet")
		return
	end
	for i, entry in ipairs(list) do
		if i > 10 then break end
		local peers = {}
		for key, peer in pairs(entry.peers) do
			table.insert(peers, format("%s %s%s", PartySync:ShortName(Peers:MemberName(key)), tostring(peer.state),
				peer.ms and format(" +%d ms", peer.ms) or ""))
		end
		PartySync:Print("  %s (%s, %s%s): %s%s", Sync.LabelOf(entry), entry.id, entry.role,
			entry.role == "follower" and (" of " .. PartySync:ShortName(Peers:MemberName(entry.driver))) or "",
			entry.state, peers[1] and (" -- " .. table.concat(peers, ", ")) or "")
	end
end

local ROOM_WORDS = { auto = "", me = "me", none = "none", off = "none" }

local function Help()
	PartySync:Print("party: /sps invite <name> | remove <name> | members | lead [auto|me|follow] | room [auto|me|none|<name>]")
	PartySync:Print("lines: /sps sync (what played together) | test <questID> (queue a quest's accept line here)")
	PartySync:Print("window and settings: /sps window | settings")
	PartySync:Print("debug log (Spoken's, on in Spoken > Developer): /sps logs [count] (yours and the party's, to copy) | logs pull [count] | logs clear (yours) | logs clear all (the party's too)")
	PartySync:Print("connection tests: /sps api | ping [name|group] | latency [name] | probe [name] | hello | burst [count] [name] | status")
end

--- The member a command means: the name typed, or the only member there is.
local function Target(rest)
	if rest ~= "" then
		return rest
	end
	local only, count = nil, 0
	for key in Peers:Members() do
		only, count = Peers:MemberName(key), count + 1
	end
	return count == 1 and only or nil
end

local GROUP_WORDS = { party = true, raid = true, group = true, instance = true }

_G.SLASH_SPOKENPARTYSYNC1 = "/spokenpartysync"
_G.SLASH_SPOKENPARTYSYNC2 = "/sps"
SlashCmdList["SPOKENPARTYSYNC"] = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	rest = rest or ""

	if cmd == "api" then
		Api()
	elseif cmd == "invite" or cmd == "companion" then
		if rest == "" then
			PartySync:Print("/sps invite <full name>")
			return
		end
		local sent, answer = Peers:Invite(rest)
		PartySync:Print("invitation to %s: %s", PartySync:ShortName(rest), sent and "sent" or tostring(answer))
	elseif cmd == "remove" then
		if Peers:RemoveMember(rest) then
			PartySync:Print("%s left your Spoken party", PartySync:ShortName(rest))
		else
			PartySync:Print("%s is not in your Spoken party", rest)
		end
	elseif cmd == "members" then
		Members()
	elseif cmd == "lead" then
		local value = rest:lower()
		if value == "auto" or value == "me" or value == "follow" then
			PartySync:DB().lead = value
			Peers:Announce()
		end
		local leader = Peers:Leader()
		PartySync:Print("lead: %s; the leader now is %s", PartySync:DB().lead,
			leader and PartySync:ShortName(Peers:MemberName(leader)) or "?")
	elseif cmd == "room" then
		if rest ~= "" then
			local word = ROOM_WORDS[rest:lower()]
			if word then
				Room:Set(word)
			elseif Peers:IsMember(rest) then
				Room:Set(PartySync:NameKey(rest))
			else
				PartySync:Print("%s is not in your Spoken party", rest)
				return
			end
		end
		PartySync:Print("same room: %s", Room:Describe(PartySync:DB().roomSpeaker))
	elseif cmd == "sync" then
		Lines()
	elseif cmd == "test" then
		local questID = tonumber(rest)
		if not questID then
			PartySync:Print("/sps test <questID> -- for instance 783, A Threat Within, in Northshire")
			return
		end
		Sync:TestLine(questID)
	elseif cmd == "ping" then
		if GROUP_WORDS[rest:lower()] then
			Peers:Ping(nil)
		elseif rest ~= "" then
			Peers:Ping(rest)
		else
			Peers:PingMembers()
		end
	elseif cmd == "latency" or cmd == "probe" or cmd == "burst" then
		local count, name = rest:match("^(%d*)%s*(.-)$")
		if cmd ~= "burst" then count, name = nil, rest end
		name = Target(name or "")
		if not name then
			PartySync:Print("/sps %s %s<name>", cmd, cmd == "burst" and "[count] " or "")
			return
		end
		if cmd == "latency" then
			Peers:Latency(name)
		elseif cmd == "probe" then
			Peers:Probe(name)
		else
			Peers:Burst(name, tonumber(count))
		end
	elseif cmd == "hello" then
		local sent, answer = Peers:Hello()
		Peers:HelloMembers()
		PartySync:Print("hello to the members, and to %s: %s (%s)", tostring(Comm:GroupChannel() or "no group"),
			sent and "sent" or "NOT sent", tostring(answer))
	elseif cmd == "logs" and not PartySync.LogBook:Available() then
		PartySync:Print("the debug log comes with the Spoken Developer module, which is not installed")
	elseif cmd == "logs" then
		local action, more = rest:match("^(%S*)%s*(.-)$")
		action, more = (action or ""):lower(), (more or ""):lower()
		local count = more:match("^(%d+)$")
		if action == "pull" then
			PartySync.LogBook:Pull(tonumber(count))
		elseif (action == "clear" and (more == "all" or more == "party")) or action == "clearall" then
			local asked = PartySync.LogBook:ClearParty()
			PartySync:Print("debug log cleared here; asked %d member%s online to clear theirs", asked, asked == 1 and "" or "s")
		elseif action == "clear" then
			PartySync.LogBook:Clear()
			PartySync:Print("debug log cleared here, with the party's logs collected here; a new session starts")
		else
			local shown = PartySync.LogBook:Show(tonumber(count) or tonumber(action))
			PartySync:Print("%d log lines shown; yours are also in WTF\\...\\SavedVariables\\Spoken.lua after a /reload%s",
				shown or 0, PartySync.LogBook:IsOn() and "" or " (your log is off: /spoken log on)")
		end
	elseif cmd == "status" then
		Status()
	elseif cmd == "window" then
		PartySync:ToggleWindow()
	elseif cmd == "settings" or cmd == "options" then
		PartySync:OpenOptions()
	else
		Help()
	end
end
