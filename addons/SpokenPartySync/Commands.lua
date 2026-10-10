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

local Diagnostics = PartySync.Diagnostics

local function Members()
	local lines = Diagnostics:MemberLines()
	for _, line in ipairs(lines) do PartySync:Print("  %s", line) end
	if not lines[1] then
		PartySync:Print("  nobody yet: /sps invite <name>, or right-click their portrait")
	end
	local leader, why = Peers:Leader()
	PartySync:Print("  leader: %s (%s); voice: %s", leader and Peers:ShortName(leader) or "?",
		tostring(why), Room:Describe(Room:Owner("voice")))
end

--- What /spoken diagnostics and the debug log's snapshots hold for the party, in chat.
local function Status()
	for _, line in ipairs(Diagnostics:Lines(false)) do PartySync:Print("%s", line) end
end

local function Lines()
	local lines = Diagnostics:EntryLines()
	if not lines[1] then
		PartySync:Print("no line played together this session yet")
		return
	end
	for _, line in ipairs(lines) do PartySync:Print("  %s", line) end
end

local ROOM_WORDS = { me = "me", here = "me", none = "none", every = "none", all = "none", off = "none",
	trigger = "trigger", whoever = "trigger" }
local CHANNEL_WORDS = { voice = "voice", music = "music", effects = "effects", sfx = "effects", ambience = "ambience",
	dialog = "dialog", all = "all" }
-- What /sps sound takes, the voice's words (sound, captions) included.
local OWN_WORDS = { party = "", plays = "plays", sound = "plays", muted = "muted", captions = "muted" }

--- "<channel> <rest>" or just "<rest>": the channel named first, if one is.
local function ChannelAndRest(rest)
	local first, second = rest:match("^(%S*)%s*(.-)$")
	local channel = CHANNEL_WORDS[(first or ""):lower()]
	if channel then return channel, second or "" end
	return nil, rest
end
local CONTROL_WORDS = { anyone = true, leader = true, nobody = true }

--- Who plays `channel` ("all": every channel), set to `who` where given; then each channel's rule.
local function Audio(channel, who)
	if who ~= "" then
		local owner = ROOM_WORDS[who:lower()] or (Peers:IsMember(who) and PartySync:NameKey(who)) or nil
		if not owner then
			PartySync:Print("%s is not in your Spoken party", who)
			return
		end
		local ok, why
		if channel == "all" then ok, why = Room:SetAll(owner) else ok, why = Room:Set(channel, owner) end
		if not ok then PartySync:Print("%s", tostring(why)) end
	end
	for _, each in ipairs(Room.CHANNELS) do
		PartySync:Print("  %s: %s", Room:Name(each), Room:Describe(Room:Owner(each)))
	end
end

local function Help()
	PartySync:Print("party: /sps invite <name> | remove <name> | leave | members | lead [<name>] (pass the lead) | controls [anyone|leader|nobody] | share [anyone|leader|nobody]")
	PartySync:Print("sound: /sps audio [voice|music|effects|ambience|dialog|all] [none|me|trigger|<name>] (who plays it, the party's rule; trigger: the voice only, whoever triggers a line) | room [none|me|trigger|<name>] (the voice) | sound [<channel>|all] [party|plays|muted] (this computer's)")
	PartySync:Print("quests: /sps quests (everyone shares every quest now) | quests me | quests <name> (ask one member)")
	PartySync:Print("usual party: /sps remember (the party you are in, or the one that just ended) | list [add <name> | remove <name> | auto <name> on|off]")
	PartySync:Print("lines: /sps sync (what played together) | test <questID> (queue a quest's accept line here)")
	PartySync:Print("window and settings: /sps window | compact [on|off] | settings")
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
		local ok, why = Peers:RemoveMember(rest)
		if ok then
			PartySync:Print("%s is out of your Spoken party", PartySync:ShortName(rest))
		else
			PartySync:Print("%s: %s", rest ~= "" and rest or "/sps remove <name>", tostring(why))
		end
	elseif cmd == "leave" then
		if not Peers:Leave() then
			PartySync:Print("you are in no Spoken party")
		end
	elseif cmd == "members" then
		Members()
	elseif cmd == "lead" then
		if rest ~= "" then
			local ok, why = Peers:PassLead(rest)
			if not ok then PartySync:Print("%s: %s", rest, tostring(why)) end
		end
		local leader, why = Peers:Leader()
		PartySync:Print("leader: %s (%s)", leader and PartySync:ShortName(Peers:MemberName(leader)) or "nobody", tostring(why))
	elseif cmd == "room" then
		Audio("voice", rest)
	elseif cmd == "audio" then
		local channel, who = ChannelAndRest(rest)
		Audio(channel or "all", who)
	elseif cmd == "sound" then
		local channel, word = ChannelAndRest(rest)
		channel = channel or "voice"
		word = word:lower()
		if word ~= "" then
			local value = OWN_WORDS[word]
			if value == nil then
				PartySync:Print("/sps sound [voice|music|effects|ambience|dialog|all] party|plays|muted")
				return
			end
			if channel == "all" then Room:SetOwnAll(value) else Room:SetOwnChannel(channel, value) end
		end
		for _, each in ipairs(Room.CHANNELS) do
			PartySync:Print("  this computer's %s: %s", Room:Name(each):lower(), Room:DescribeOwn(Room:OwnValue(each), each))
		end
	elseif cmd == "controls" then
		local value = rest:lower()
		if value ~= "" then
			if not CONTROL_WORDS[value] then
				PartySync:Print("/sps controls anyone|leader|nobody")
				return
			end
			local ok, why = Peers:SetRule("controls", value)
			if not ok then PartySync:Print("%s", tostring(why)) end
		end
		PartySync:Print("controls: %s", tostring(Peers:Rules().controls))
	elseif cmd == "share" then
		local value = rest:lower()
		if value ~= "" then
			if not CONTROL_WORDS[value] then
				PartySync:Print("/sps share anyone|leader|nobody")
				return
			end
			local ok, why = Peers:SetRule("share", value)
			if not ok then PartySync:Print("%s", tostring(why)) end
		end
		PartySync:Print("quests are shared by: %s", tostring(Peers:Rules().share or "anyone"))
	elseif cmd == "list" then
		local Autoform = PartySync.Autoform
		local action, name = rest:match("^(%S*)%s*(.-)$")
		action, name = (action or ""):lower(), name or ""
		if action == "add" and name ~= "" then
			PartySync:Print("%s %s", PartySync:ShortName(name), Autoform:Add(name) and "is in your usual party" or "cannot be added")
		elseif action == "remove" and name ~= "" then
			PartySync:Print("%s %s", PartySync:ShortName(name), Autoform:Remove(name) and "is out of your usual party" or "is not in it")
		elseif action == "auto" and name ~= "" then
			local onOff = name:match("%s(%S+)$")
			local who = onOff and name:sub(1, #name - #onOff - 1) or nil
			if not (who and (onOff == "on" or onOff == "off")) then
				PartySync:Print("/sps list auto <name> on|off")
				return
			end
			PartySync:Print("%s's invitations: %s", PartySync:ShortName(who), Autoform:SetAutoAccept(who, onOff == "on")
				and (onOff == "on" and "accepted without asking" or "asked each time") or "they are not on the list")
		else
			local list = Autoform:List()
			local keys = Autoform:Keys()
			if not keys[1] then
				PartySync:Print("your usual party is empty: /sps remember in a party, or /sps list add <name>")
				return
			end
			for _, key in ipairs(keys) do
				local entry = list.members[key]
				PartySync:Print("  %s%s: %s", entry.name, list.leader == key and " (leads)" or "",
					entry.autoAccept and "invitations accepted without asking" or "asked each time")
			end
			if list.rules then PartySync:Print("  rules: %s", Peers.DescribeRules(list.rules)) end
		end
	elseif cmd == "quests" then
		local Accept = PartySync.Accept
		if rest == "" then
			Accept:AskAll()
		elseif rest:lower() == "me" then
			Accept:Ask(PartySync:MyKey())
		else
			local key = PartySync:NameKey(rest)
			if key and Peers:IsMember(key) then
				Accept:Ask(key)
			else
				PartySync:Print("%s is not in your Spoken party", rest)
			end
		end
	elseif cmd == "remember" then
		if not (PartySync.Autoform:Remember() or PartySync.Autoform:AcceptPrompt()) then
			PartySync:Print("you are in no Spoken party to remember")
		end
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
	elseif cmd == "compact" then
		local value = rest:lower()
		PartySync:SetWindowCompact(value == "on" or (value ~= "off" and not PartySync:DB().window.compact))
		PartySync:Print("compact window: %s", PartySync:DB().window.compact and "on" or "off")
	elseif cmd == "settings" or cmd == "options" then
		PartySync:OpenOptions()
	else
		Help()
	end
end
