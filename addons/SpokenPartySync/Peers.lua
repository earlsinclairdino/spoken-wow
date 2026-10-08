-- The party: who plays lines with this character, whether they can hear us, how far away they
-- are, and who leads.
--
-- Messages:
--
--   HI  version, reply, lead, room
--                           hello. Whispered to every member at login and when the group
--                           changes, broadcast to the group so others running the addon can
--                           be told about it; answered by whisper. reply=1 marks the answer,
--                           which is never answered. `lead` and `room` are this client's
--                           settings, which the others need to agree on who leads and which
--                           computer plays the sound. Sent again as a reply when either changes.
--   CH  kind, value         a choice made for the whole party: `lead` (a member's key, or
--                           "auto") or `room` (a member's key, or "none": every computer).
--                           Each member saves the same, so the last choice is everyone's; a
--                           key that is the receiver's own becomes its "me". "Never this one"
--                           and "as chosen elsewhere" are one computer's and never sent.
--   IV  version             an invitation to the party. Asked of the player in a popup.
--   IA                      accepted: both sides keep the other as a member.
--   ID                      declined, or removed: both sides forget the other.
--   PI  token               ping. Answered by PO with the same token, on the channel it came in
--                           on, so `/sps latency` can time the two paths separately.
--   PO  token               pong. The round trip is timed on the sender's own clock, so the two
--                           clients' clocks never have to agree.
--   BU  id, seq, total, pad burst: `total` full-size messages in one go, to see how many arrive.
--   BR  id, received, total, ms
--   PQ  token               probe: which way of writing a name a whisper reaches.
--   PA  token, seenAs       its answer, on the group channel.

local _, PartySync = ...

local Comm = PartySync.Comm
local L = PartySync.L

local Peers = {}
PartySync.Peers = Peers

local PING_TIMEOUT = 5
local HEARTBEAT_SECONDS = 20
-- Three heartbeats missed. Long enough that a loading screen does not count as leaving.
local LOST_SECONDS = 65
local BURST_REPORT_SECONDS = 3
-- Until a round trip has been measured: about what the Forever beta takes (0.9 to 1.1 s).
local DEFAULT_RTT = 1000

-- key -> { name, version, lastSeen, rtt, rtts = { whisper = ms, group = ms }, state, lead, room }
-- state: "online" | "lost" | "offline" (the client said there is no such player online)
Peers.list = {}

local function Changed()
	PartySync:Changed()
	if PartySync.Sync and PartySync.Sync.PresenceChanged then
		PartySync.Sync:PresenceChanged()
	end
end

function Peers:Get(name)
	local key = PartySync:NameKey(name)
	return key and self.list[key] or nil
end

function Peers:Seen(sender, version)
	local key = PartySync:NameKey(sender)
	if not key then
		return nil
	end
	local peer = self.list[key]
	local isNew = not peer or peer.state ~= "online"
	if not peer then
		peer = {}
		self.list[key] = peer
	end
	peer.name = PartySync:WhisperName(sender)
	peer.lastSeen = GetTime()
	peer.state = "online"
	if version and version ~= "" then
		peer.version = version
	end
	if isNew then
		PartySync:Trace("party", "%s online", key)
		PartySync:Resolve("presence:" .. key)
		Changed()
	end
	return peer
end

function Peers:MarkOffline(name)
	local key = PartySync:NameKey(name)
	if not key then
		return
	end
	local peer = self.list[key] or { name = PartySync:WhisperName(name) }
	self.list[key] = peer
	local was = peer.state
	peer.state = "offline"
	if was ~= "offline" then PartySync:Trace("party", "%s offline (was %s)", key, tostring(was)) end
	if was ~= "offline" then
		if self:IsMember(key) and was == "online" then
			PartySync:Problem("presence:" .. key, format(L.PROBLEM_OFFLINE_FMT, peer.name))
		end
		Changed()
	end
end

--- How long a message takes to reach `key` and come back, in ms: the running average of the
--- whisper pings, or the beta's typical figure until one has been measured.
function Peers:Rtt(key)
	local peer = self.list[key]
	return peer and peer.rtt or DEFAULT_RTT
end

--------------------------------------------------------------------------------
-- Members
--------------------------------------------------------------------------------

function Peers:IsMember(name)
	local key = PartySync:NameKey(name)
	return key ~= nil and PartySync:DB().members[key] ~= nil
end

--- Iterates `key, member` over the party, this character excluded.
function Peers:Members()
	return pairs(PartySync:DB().members)
end

function Peers:MemberName(key)
	local member = PartySync:DB().members[key]
	local peer = self.list[key]
	return (member and member.name) or (peer and peer.name) or key
end

--- The members heard from and not lost since, by key.
function Peers:OnlineMembers()
	local list = {}
	for key in self:Members() do
		local peer = self.list[key]
		if peer and peer.state == "online" then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

function Peers:AnyOnline()
	return self:OnlineMembers()[1] ~= nil
end

--- Returns false, changing nothing, for this character's own name.
function Peers:AddMember(name)
	name = PartySync:CleanName(name)
	local key = PartySync:NameKey(name)
	if not key or PartySync:IsSelf(name) then
		return false
	end
	local members = PartySync:DB().members
	if not members[key] then
		members[key] = { name = PartySync:WhisperName(name), added = time and time() or 0 }
	end
	Changed()
	return true
end

--- Forget `name` and tell them, so their side forgets this one too.
function Peers:RemoveMember(name, quiet)
	local key = PartySync:NameKey(name)
	if not key or not PartySync:DB().members[key] then
		return false
	end
	local who = self:MemberName(key)
	PartySync:Trace("party", "%s left the party%s", key, quiet and ", by their choice" or ", removed here")
	PartySync:DB().members[key] = nil
	if not quiet then
		Comm:Whisper(who, "ID")
	end
	PartySync:Resolve("presence:" .. key)
	Changed()
	return true
end

--------------------------------------------------------------------------------
-- Hello
--------------------------------------------------------------------------------

--- This client's settings as the others need them: whether it asked to lead, and which
--- computer it says plays the sound.
local function Settings()
	local db = PartySync:DB()
	return db.lead or "auto", db.roomSpeaker or ""
end

--- To the group, for whoever runs the addon there.
function Peers:Hello()
	local lead, room = Settings()
	return Comm:Broadcast("HI", PartySync.version, 0, lead, room)
end

--- To every member by name. One that is offline costs a "No player named" message, which
--- Comm keeps out of the chat window and reads as offline.
function Peers:HelloMembers(reply)
	local lead, room = Settings()
	for key in self:Members() do
		Comm:Whisper(self:MemberName(key), "HI", PartySync.version, reply and 1 or 0, lead, room)
	end
end

--- A setting the others read has changed: tell the members who are online.
function Peers:Announce()
	local lead, room = Settings()
	PartySync:Trace("party", "lead %s, room %s: told %s", lead, room ~= "" and room or "as chosen elsewhere",
		self:OnlineMembers()[1] and table.concat(self:OnlineMembers(), ", ") or "nobody online")
	for _, key in ipairs(self:OnlineMembers()) do
		Comm:Whisper(self:MemberName(key), "HI", PartySync.version, 1, lead, room)
	end
	Changed()
end

local told = {}

Comm:On("HI", function(sender, channel, version, reply, lead, room)
	local known = Peers:Get(sender)
	local wasOnline = known and known.state == "online"
	local peer = Peers:Seen(sender, version)
	if not peer then return end
	local changed = peer.lead ~= (lead or "auto") or peer.room ~= (room or "")
	peer.lead, peer.room = lead or "auto", room or ""
	local key = PartySync:NameKey(sender)
	if Peers:IsMember(sender) then
		if not wasOnline then
			PartySync:Print("%s is here (Spoken Party Sync %s)", PartySync:ShortName(sender), tostring(version))
		end
	elseif not told[key] then
		told[key] = true
		PartySync:Print("%s runs Spoken Party Sync too: /sps invite %s to play lines together",
			PartySync:ShortName(sender), PartySync:ShortName(sender))
	end
	if reply ~= "1" then
		local myLead, myRoom = Settings()
		Comm:Whisper(sender, "HI", PartySync.version, 1, myLead, myRoom)
	end
	if changed then
		Changed()
	end
end)

--------------------------------------------------------------------------------
-- Invitations
--------------------------------------------------------------------------------

local POPUP = "SPOKENPARTYSYNC_INVITE"
local invited = {}   -- key -> when this client invited them

function Peers:Invite(name)
	name = PartySync:CleanName(name)
	local key = PartySync:NameKey(name)
	if not key then
		return false, "no name"
	end
	if PartySync:IsSelf(name) then
		return false, "that is this character"
	end
	invited[key] = GetTime()
	local sent, answer = Comm:Whisper(name, "IV", PartySync.version)
	PartySync:Trace("party", "invited %s: %s", key, sent and "sent" or tostring(answer))
	return sent, answer
end

local function Join(name)
	PartySync:Trace("party", "%s joined the party", tostring(PartySync:NameKey(name)))
	Peers:AddMember(name)
	Peers:Seen(name)
	PartySync:Print("%s is in your Spoken party", PartySync:ShortName(name))
	Peers:HelloMembers(true)
end

function Peers:AcceptInvite(name)
	if not name then return end
	Comm:Whisper(name, "IA")
	Join(name)
end

function Peers:DeclineInvite(name)
	if not name then return end
	Comm:Whisper(name, "ID")
end

local function DefinePopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then
		return
	end
	StaticPopupDialogs[POPUP] = {
		text = L.INVITE_POPUP,
		button1 = ACCEPT or "Accept",
		button2 = DECLINE or "Decline",
		OnAccept = function(_, data) Peers:AcceptInvite(data) end,
		OnCancel = function(_, data, reason)
			-- Only a click is an answer; a popup that timed out or was replaced says nothing.
			if reason == "clicked" then Peers:DeclineInvite(data) end
		end,
		timeout = 120,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

Comm:On("IV", function(sender, channel, version)
	Peers:Seen(sender, version)
	-- Already a member: the other side lost its list (a new install, another computer), and
	-- asking again would be a question with one answer.
	if Peers:IsMember(sender) then
		Comm:Whisper(sender, "IA")
		Peers:HelloMembers(true)
		return
	end
	DefinePopup()
	if StaticPopup_Show then
		StaticPopup_Show(POPUP, PartySync:ShortName(sender), nil, PartySync:WhisperName(sender))
	end
end)

Comm:On("IA", function(sender)
	local key = PartySync:NameKey(sender)
	-- Only an answer to a question this client asked, or a member re-linking.
	if not (invited[key] or Peers:IsMember(sender)) then
		return
	end
	invited[key] = nil
	Join(sender)
end)

Comm:On("ID", function(sender)
	local key = PartySync:NameKey(sender)
	if invited[key] then
		invited[key] = nil
		PartySync:Trace("party", "%s declined the invitation", tostring(key))
		PartySync:Print("%s declined", PartySync:ShortName(sender))
	end
	if Peers:IsMember(sender) then
		Peers:RemoveMember(sender, true)
		PartySync:Print("%s left your Spoken party", PartySync:ShortName(sender))
	end
end)

--------------------------------------------------------------------------------
-- Who leads
--------------------------------------------------------------------------------
--
-- Every client works this out for itself from the same facts -- each member's lead setting,
-- carried in its hello, and the group's leader -- so they agree without a vote. The leader's
-- Stop, Replay, Skip and Stop All reach everyone, it shares the quests it accepts, and when two
-- of the party start the same line at once, the leader's copy is the one played.

local function IsGroupLeader(key)
	if not UnitIsGroupLeader then
		return false
	end
	if key == PartySync:MyKey() then
		return UnitIsGroupLeader("player") and true or false
	end
	local unit = PartySync:UnitFor(Peers:MemberName(key))
	return unit ~= nil and UnitIsGroupLeader(unit) and true or false
end

--- The leader's key, this character's included, and why it leads; nil only before the name is
--- known.
function Peers:Leader()
	local me = PartySync:MyKey()
	if not me then
		return nil
	end
	local wishes = { [me] = PartySync:DB().lead or "auto" }
	for _, key in ipairs(self:OnlineMembers()) do
		wishes[key] = self.list[key].lead or "auto"
	end
	local keys = {}
	for key in pairs(wishes) do table.insert(keys, key) end
	table.sort(keys)
	-- A wish can name a member (chosen for the party with Lead): as good as their own "me".
	local named = {}
	for _, key in ipairs(keys) do
		local wish = wishes[key]
		if wishes[wish] ~= nil and not named[wish] then named[wish] = key end
	end
	for _, key in ipairs(keys) do
		if wishes[key] == "me" then return key, "asked to lead" end
		if named[key] then return key, named[key] == key and "asked to lead" or ("named by " .. named[key]) end
	end
	for _, key in ipairs(keys) do
		if wishes[key] ~= "follow" and IsGroupLeader(key) then return key, "leads the group" end
	end
	for _, key in ipairs(keys) do
		if wishes[key] ~= "follow" then return key, "first by name" end
	end
	return keys[1], "everyone follows: first by name"
end

local lastLeader

--- Writes the leader in the log whenever it changes, and why it is them.
function Peers:CheckLeader()
	local leader, why = self:Leader()
	if leader ~= lastLeader then
		PartySync:Trace("party", "leader: %s (%s), was %s", tostring(leader), tostring(why), tostring(lastLeader or "nobody"))
		lastLeader = leader
	end
end

--- The choices "Who Leads" offers: automatic, this character, never this one, each member.
function Peers:LeadChoices()
	local list = { "auto", "me", "follow" }
	local keys = {}
	for key in self:Members() do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do table.insert(list, key) end
	return list
end

function Peers:DescribeLead(choice)
	if choice == nil or choice == "auto" then return L.LEAD_AUTO end
	if choice == "me" then return L.LEAD_ME end
	if choice == "follow" then return L.LEAD_FOLLOW end
	return format(L.LEAD_MEMBER_FMT, self:MemberName(choice))
end

--- Tell every member online about a choice made here for the whole party (CH).
function Peers:SendChoice(kind, value)
	for _, key in ipairs(self:OnlineMembers()) do
		Comm:Whisper(self:MemberName(key), "CH", kind, value)
	end
end

--- Who leads, chosen here: "auto", "me", "follow" or a member's key. All but "follow", which
--- only says this character never leads, are chosen for the whole party: every member online
--- is told and saves the same.
function Peers:ChooseLead(choice)
	local me = PartySync:MyKey()
	if choice == nil or choice == "" then choice = "auto" end
	if choice == me then choice = "me" end
	PartySync:DB().lead = choice
	PartySync:TraceSetting("lead", choice)
	if choice ~= "follow" then
		self:SendChoice("lead", choice == "me" and me or choice)
	end
	self:Announce()
end

--- A choice another member made for the party, in this client's own terms: "me" for this
--- character's key, the key for another member, the word for a word. Nil for a name that is
--- not in this party.
local function Translate(sender, value, words)
	if value == nil or value == "" then return nil end
	if words[value] then return value end
	if value == PartySync:MyKey() then return "me" end
	if Peers:IsMember(value) then return value end
	return nil
end

local LEAD_WORDS, ROOM_WORDS = { auto = true }, { none = true }

Comm:On("CH", function(sender, channel, kind, value)
	if not Peers:IsMember(sender) then return end
	local who = PartySync:ShortName(sender)
	if kind == "lead" then
		local choice = Translate(sender, value, LEAD_WORDS)
		if not choice then
			PartySync:Trace("party", "%s chose %s to lead: not in this party, ignored", PartySync:NameKey(sender), tostring(value))
			return
		end
		PartySync:DB().lead = choice
		PartySync:Trace("party", "%s chose who leads: %s", PartySync:NameKey(sender), choice)
		Peers:Announce()
		PartySync:Print("%s chose who leads the party: %s", who, choice == "me" and "you"
			or Peers:DescribeLead(choice))
	elseif kind == "room" and PartySync.Room then
		local choice = Translate(sender, value, ROOM_WORDS)
		if not choice then
			PartySync:Trace("party", "%s chose %s to play the sound: not in this party, ignored", PartySync:NameKey(sender), tostring(value))
			return
		end
		PartySync:Trace("party", "%s chose who plays the sound: %s", PartySync:NameKey(sender), choice)
		PartySync.Room:Set(choice)
		PartySync:Print("%s chose who plays the sound: %s", who, PartySync.Room:Describe(choice))
	end
end)

function Peers:IsLeader(key)
	return key ~= nil and self:Leader() == key
end

function Peers:AmLeader()
	return self:IsLeader(PartySync:MyKey())
end

--------------------------------------------------------------------------------
-- Ping
--------------------------------------------------------------------------------

local pending = {}
local counter = 0

local function Token()
	counter = counter + 1
	-- Unique across a /reload, so a pong for a ping sent before it is not matched to one after.
	return format("%d-%d", math.floor(GetTime() * 1000) % 1000000, counter)
end

--- Ping `target` by whisper, or the group when `target` is nil. `quiet` pings (the heartbeat)
--- print nothing; `stats`, when given, collects the round trips for `/sps latency`. Returns
--- whether the client accepted the ping, and its answer in words.
function Peers:Ping(target, quiet, stats)
	local token = Token()
	local sent, answer
	if target then
		sent, answer = Comm:Whisper(target, "PI", token)
	else
		sent, answer = Comm:Broadcast("PI", token)
	end
	if not quiet then
		PartySync:Print("ping %s: %s (%s, %s)", target and PartySync:ShortName(target) or (Comm:GroupChannel() or "group"),
			sent and "sent" or "NOT sent", tostring(answer), Comm:Context())
	end
	if not sent then
		return sent, answer
	end

	local ping = { target = target, sentAt = GetTime(), answers = 0, quiet = quiet, stats = stats }
	pending[token] = ping
	C_Timer.After(PING_TIMEOUT, function()
		pending[token] = nil
		if ping.quiet then
			return
		end
		if target and ping.answers == 0 then
			PartySync:Print("|cffff6060no answer from %s within %d s|r", PartySync:ShortName(target), PING_TIMEOUT)
		elseif not target then
			PartySync:Print("%d player%s answered the group ping", ping.answers, ping.answers == 1 and "" or "s")
		end
	end)
	return sent, answer
end

function Peers:PingMembers()
	local any = false
	for key in self:Members() do
		any = true
		self:Ping(self:MemberName(key))
	end
	if not any then
		PartySync:Print("nobody in your Spoken party yet: /sps invite <name>")
	end
end

Comm:On("PI", function(sender, channel, token)
	Peers:Seen(sender)
	if channel == "WHISPER" then
		Comm:Whisper(sender, "PO", token)
	else
		Comm:Send(channel, nil, "PO", token)
	end
end)

local function PathOf(channel)
	return channel == "WHISPER" and "whisper" or "group"
end

Comm:On("PO", function(sender, channel, token)
	local peer = Peers:Seen(sender)
	local ping = token and pending[token]
	if not (peer and ping) then
		return
	end
	ping.answers = ping.answers + 1
	local ms = (GetTime() - ping.sentAt) * 1000
	peer.rtts = peer.rtts or {}
	peer.rtts[PathOf(channel)] = ms
	if channel == "WHISPER" then
		-- A running average: one slow round trip should move the start, not decide it.
		peer.rtt = peer.rtt and (peer.rtt * 0.7 + ms * 0.3) or ms
	end
	if ping.stats and PartySync:NameKey(sender) == ping.stats.peer then
		table.insert(ping.stats[PathOf(channel)], ms)
	end
	PartySync:Changed()
	if not ping.quiet then
		PartySync:Print("|cff60ff60pong from %s: %d ms round trip|r (by %s)", PartySync:ShortName(sender), math.floor(ms + 0.5), channel)
	end
end)

--------------------------------------------------------------------------------
-- Latency
--------------------------------------------------------------------------------
--
-- What the sync has to wait out: a line can only start on both clients at once if the one
-- that talked to the NPC holds its own start back by the time the message takes to arrive.

local LATENCY_SAMPLES = 5

local function Summarise(samples)
	if #samples == 0 then
		return "no answers"
	end
	table.sort(samples)
	local sum = 0
	for _, ms in ipairs(samples) do
		sum = sum + ms
	end
	return format("%d of %d answered, min %d / avg %d / max %d ms", #samples, LATENCY_SAMPLES,
		math.floor(samples[1] + 0.5), math.floor(sum / #samples + 0.5), math.floor(samples[#samples] + 0.5))
end

function Peers:Latency(target)
	local grouped = Comm:GroupChannel() ~= nil
	local stats = { peer = PartySync:NameKey(target), whisper = {}, group = {} }
	PartySync:Print("timing %d whisper%s round trips to %s, one a second...", LATENCY_SAMPLES,
		grouped and (" and " .. LATENCY_SAMPLES .. " " .. Comm:GroupChannel()) or "", PartySync:ShortName(target))
	for i = 0, LATENCY_SAMPLES - 1 do
		C_Timer.After(i, function()
			Peers:Ping(target, true, stats)
			if grouped then
				Peers:Ping(nil, true, stats)
			end
		end)
	end
	C_Timer.After(LATENCY_SAMPLES - 1 + PING_TIMEOUT, function()
		PartySync:Print("whisper: %s", Summarise(stats.whisper))
		if grouped then
			PartySync:Print("%s: %s", Comm:GroupChannel() or "group", Summarise(stats.group))
		end
		-- The client's own figure for its link to the server. Two of those, one per client, are
		-- what a round trip would cost if the server passed messages straight on; the rest is
		-- the server holding them.
		if GetNetStats then
			local _, _, home, world = GetNetStats()
			PartySync:Print("your connection: home %s ms, world %s ms", tostring(home), tostring(world))
		end
	end)
end

--------------------------------------------------------------------------------
-- Probe
--------------------------------------------------------------------------------
--
-- Which way of writing a name a whisper reaches. Each form gets one PQ; the receiver answers
-- PA on the group channel rather than by whisper, because the whisper back is the half that
-- may be broken. Needs a group for the answers to come back on.

local probes = {}

function Peers:Probe(name)
	if not Comm:GroupChannel() then
		PartySync:Print("group up first: the answers come back over the party channel")
		return
	end
	local batch = {}
	for _, form in ipairs(PartySync:NameForms(name)) do
		local token = Token()
		local probe = { form = form }
		probes[token] = probe
		table.insert(batch, probe)
		-- Sent as written: Comm:Whisper would rewrite the form this is trying out.
		local sent, answer = Comm:Send("WHISPER", form, "PQ", token)
		probe.sent, probe.answer = sent, answer
	end
	PartySync:Print("probing %d ways of writing %q...", #batch, name)
	-- The forms that miss make the client print "No player named" for a player another form
	-- reached; until the report, those say nothing about whether anyone is online.
	self.probingUntil = GetTime() + PING_TIMEOUT
	C_Timer.After(PING_TIMEOUT, function()
		for i, probe in ipairs(batch) do
			if probe.arrivedAs then
				PartySync:Print("|cff60ff60%d. %q arrived|r (they saw you as %q)", i, probe.form, probe.arrivedAs)
			elseif not probe.sent then
				PartySync:Print("|cffff6060%d. %q not sent: %s|r", i, probe.form, tostring(probe.answer))
			else
				PartySync:Print("|cffff6060%d. %q did not arrive|r", i, probe.form)
			end
		end
	end)
end

function Peers:IsProbing()
	return self.probingUntil ~= nil and GetTime() <= self.probingUntil
end

Comm:On("PQ", function(sender, channel, token)
	Comm:Broadcast("PA", token, sender)
end)

Comm:On("PA", function(sender, channel, token, seenAs)
	local probe = token and probes[token]
	if probe then
		probes[token] = nil
		probe.arrivedAs = seenAs or "?"
	end
end)

--------------------------------------------------------------------------------
-- Heartbeat
--------------------------------------------------------------------------------
--
-- Only players heard from this session are pinged. A member who logs in later says hello
-- themselves.

function Peers:Tick()
	local now = GetTime()
	for key, peer in pairs(self.list) do
		if peer.state == "online" then
			if now - (peer.lastSeen or 0) > LOST_SECONDS then
				peer.state = "lost"
				PartySync:Trace("party", "%s lost: not heard from for %d s", key, LOST_SECONDS)
				if self:IsMember(key) then
					PartySync:Problem("presence:" .. key, format(L.PROBLEM_LOST_FMT, peer.name))
				end
				Changed()
			elseif now - (peer.lastSeen or 0) >= HEARTBEAT_SECONDS - 1 then
				self:Ping(peer.name, true)
			end
		end
	end
end

function Peers:Setup()
	DefinePopup()
	if self.ticker or not C_Timer.NewTicker then
		return
	end
	self.ticker = C_Timer.NewTicker(HEARTBEAT_SECONDS, function() Peers:Tick() end)
end

--------------------------------------------------------------------------------
-- Burst
--------------------------------------------------------------------------------

local MAX_BURST = 50

--- Send `count` full-size messages to `target` in one go.
function Peers:Burst(target, count)
	count = math.max(1, math.min(MAX_BURST, count or 10))
	counter = counter + 1
	local id = tostring(counter)
	-- Padded to near the limit, because that is what a caption chunk is.
	local header = format("BU\t%s\t%d\t%d\t", id, count, count)
	local pad = string.rep("x", Comm.MAX_LENGTH - #header)
	local accepted, refused, lastAnswer = 0, 0, nil
	for seq = 1, count do
		local sent, answer = Comm:Whisper(target, "BU", id, seq, count, pad)
		if sent then
			accepted = accepted + 1
		else
			refused = refused + 1
			lastAnswer = answer
		end
	end
	PartySync:Print("burst to %s: %d of %d accepted by the client%s", PartySync:ShortName(target), accepted, count,
		refused > 0 and (" -- refused: " .. tostring(lastAnswer)) or "")
end

local bursts = {}

Comm:On("BU", function(sender, channel, id, seq, total)
	Peers:Seen(sender)
	local key = PartySync:NameKey(sender) .. ":" .. tostring(id)
	local burst = bursts[key]
	if not burst then
		burst = { received = 0, total = tonumber(total) or 0, first = GetTime(), last = GetTime() }
		bursts[key] = burst
		-- Reported on a timer rather than on the last message, because the last one may be
		-- exactly the one that did not arrive.
		C_Timer.After(BURST_REPORT_SECONDS, function()
			bursts[key] = nil
			Comm:Whisper(sender, "BR", id, burst.received, burst.total,
				math.floor((burst.last - burst.first) * 1000))
		end)
	end
	burst.received = burst.received + 1
	burst.last = GetTime()
end)

Comm:On("BR", function(sender, channel, id, received, total, ms)
	Peers:Seen(sender)
	local colour = received == total and "|cff60ff60" or "|cffff6060"
	PartySync:Print("%s%s received %s of %s burst messages, spread over %s ms|r", colour,
		PartySync:ShortName(sender), tostring(received), tostring(total), tostring(ms))
end)
