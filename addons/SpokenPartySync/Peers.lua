-- The party: a session with a leader, who is in it and online, how far away they are, and the
-- rules the leader sets for everyone.
--
-- A party begins with an invitation and lasts until fewer than two are left. Whoever invites
-- first leads: only the leader invites, removes, passes the lead and sets the rules, and the
-- leader owns the roster, which every change is sent out from, so every member sees the same
-- party. A member keeps the session in its saved variables, so a /reload rejoins it. Should
-- the leader vanish, the first by name among those still online stands in and says so.
--
-- Messages:
--
--   HI  version, reply, session, own, plays
--                           hello. Whispered to every member at login and when the group
--                           changes, broadcast to the group so others running the addon can
--                           be told about it; answered by whisper. reply=1 marks the answer,
--                           which is never answered. `session` is the party this client is
--                           in, or empty; `own` is 1 while it decides a channel by itself;
--                           `plays` the channels it plays, a letter each (v voice, m music,
--                           e effects, a ambience, d dialog), "-" for none.
--   IV  version, session, rejoin
--                           an invitation to the party `session`. Asked of the player in a
--                           popup, unless the usual party accepts it, or rejoin=1 asks back
--                           someone who was in a party with the inviter within REJOIN_SECONDS.
--   IA  session             accepted: the leader adds them and sends the roster.
--   ID  session             declined, left, or removed. One about another party is stale.
--   RO  session, leader, members
--                           the roster, from the leader: who leads and who is in, names
--                           separated by semicolons. A member not in it has been removed.
--   PS  controls, room, sync, share, audio
--                           the rules, from the leader: whose controls act everywhere, which
--                           computer plays the voice, which kinds of line are played together
--                           (four flags: quests, gossip, zones, books), whose accepted quests
--                           are shared with the party, and who plays the game's channels
--                           ("music=<owner>;effects=...;ambience=...;dialog=..."). An owner is
--                           "none" (every computer), a key, or "-<key>,<key>" (all but those).
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
-- How long an invitation stands, as long as its popup.
local INVITE_SECONDS = 125
-- A member in the party this long is dropped when its hello names another party or none. A
-- hello sent just before it accepted may arrive after.
local JOIN_GRACE = 10
-- Silent past one heartbeat and the answer to its ping: the window says "no answer" and for how
-- long, which tells whether to wait or to re-invite, until LOST_SECONDS drops them.
local QUIET_SECONDS = HEARTBEAT_SECONDS + 5
-- Someone dropped from a party this recently is asked back into it without the popup: a lost
-- connection is not a new decision to join.
local REJOIN_SECONDS = 600
-- A member dropped for going silent: the party did not go well, and is not offered to remember.
-- Logging out (offline) is how a party usually ends.
local TROUBLE = { lost = true }

local SYNC_KINDS = { "quests", "gossip", "zones", "books" }

-- key -> { name, version, lastSeen, rtt, rtts = { whisper = ms, group = ms }, state, session, own }
-- state: "online" | "lost" | "offline" (the client said there is no such player online)
Peers.list = {}

local function Autoform()
	return PartySync.Autoform
end

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
			PartySync:Problem("presence:" .. key, format(L.PROBLEM_OFFLINE_FMT, peer.name), { kind = "silent", who = key })
		end
		self:Gone(key, "offline")
		Changed()
	end
	self:InviteeOffline(key, peer.name)
end

--- How long a message takes to reach `key` and come back, in ms: the running average of the
--- whisper pings, or the beta's typical figure until one has been measured.
function Peers:Rtt(key)
	local peer = self.list[key]
	return peer and peer.rtt or DEFAULT_RTT
end

--- How many seconds `key` has been silent, once that is past a heartbeat; nil while it answers.
function Peers:Quiet(key)
	local peer = self.list[key]
	if not (peer and peer.state == "online" and peer.lastSeen) then
		return nil
	end
	local silent = GetTime() - peer.lastSeen
	return silent > QUIET_SECONDS and math.floor(silent) or nil
end

--------------------------------------------------------------------------------
-- The session
--------------------------------------------------------------------------------

-- key -> when they joined this session, for JOIN_GRACE. Not saved: after a /reload everyone
-- has been in for long enough.
local joinedAt = {}
-- key -> { at, id, name, expired }: invitations this client sent and has had no answer to.
-- One past INVITE_SECONDS is kept, expired: a late acceptance still joins.
local invited = {}
-- key -> { at, id }: members who left a party here, by wall clock, for REJOIN_SECONDS.
local left = {}

--- The party this character is in, or nil.
function Peers:Session()
	return PartySync:Party().session
end

function Peers:InParty()
	return self:Session() ~= nil
end

function Peers:SessionId()
	local session = self:Session()
	return session and session.id or ""
end

--- How many are in the party, this character included.
function Peers:Count()
	local session = self:Session()
	local n = 0
	if session then
		for _ in pairs(session.members) do n = n + 1 end
	end
	return n
end

local function MyName()
	return PartySync:ShortName(PartySync:UnitChatName("player"))
end

local function Now()
	return time and time() or math.floor(GetTime())
end

local function NewSession(rules)
	local me = PartySync:MyKey()
	local session = {
		id = format("%s-%d", me, Now()),
		leader = me,
		members = { [me] = MyName() },
		rules = PartySync.Copy(rules or PartySync:DB().rules),
		started = Now(),
		played = 0,
	}
	PartySync:Party().session = session
	PartySync:Trace("party", "party %s started here, with the rules controls %s, room %s", session.id,
		tostring(session.rules.controls), tostring(session.rules.room))
	return session
end

--- The party is over, or this character is out of it.
function Peers:EndSession(why, quiet)
	local session = self:Session()
	if not session then return end
	PartySync:Trace("party", "party %s ended here: %s", session.id, tostring(why))
	local me = PartySync:MyKey()
	local members = {}
	for key, name in pairs(session.members) do
		if key ~= me then members[key] = name end
	end
	-- Kept with the character: who was in it, for a re-invite to ask them back after a /reload.
	local last = { id = session.id, leader = session.leader, rules = PartySync.Copy(session.rules), members = members,
		started = session.started, played = session.played or 0, troubled = session.troubled, endedAt = Now() }
	PartySync:Party().lastSession = last
	PartySync:Party().session = nil
	joinedAt = {}
	if not quiet then
		PartySync:Print("%s", why)
	end
	if Autoform() then Autoform():OfferRemember(last) end
	Changed()
end

--- A line played together started: the party had something to remember it by.
function Peers:Played()
	local session = self:Session()
	if session then session.played = (session.played or 0) + 1 end
end

--- The party `key` was in here within REJOIN_SECONDS, by its id, or nil.
function Peers:WasIn(key)
	local mark = left[key]
	if mark and Now() - mark.at <= REJOIN_SECONDS then
		return mark.id
	end
	local last = PartySync:Party().lastSession
	if last and last.members and last.members[key] and Now() - (last.endedAt or 0) <= REJOIN_SECONDS then
		return last.id
	end
	return nil
end

--------------------------------------------------------------------------------
-- Members
--------------------------------------------------------------------------------

--- Whether `name` is another member of this character's party.
function Peers:IsMember(name)
	local key = PartySync:NameKey(name)
	local session = self:Session()
	return key ~= nil and session ~= nil and session.members[key] ~= nil and key ~= PartySync:MyKey()
end

--- Iterates `key, name` over the party, this character excluded.
function Peers:Members()
	local session = self:Session()
	local members = session and session.members or {}
	local me = PartySync:MyKey()
	local key, name
	return function()
		repeat
			key, name = next(members, key)
		until key == nil or key ~= me
		return key, name
	end
end

--- Every member's key, this character first, then the others by name.
function Peers:MemberKeys()
	local keys = {}
	for key in self:Members() do table.insert(keys, key) end
	table.sort(keys)
	local me = PartySync:MyKey()
	if me and self:Session() then table.insert(keys, 1, me) end
	return keys
end

function Peers:MemberName(key)
	local session = self:Session()
	local peer = self.list[key]
	local list = Autoform() and Autoform():Entry(key)
	local invite = invited[key]
	return (session and session.members[key]) or (peer and peer.name) or (list and list.name)
		or (invite and invite.name) or key
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

local function SessionWord()
	return Peers:SessionId()
end

--- Whether this character leads its party, or may start one.
function Peers:MayInvite()
	local session = self:Session()
	return session == nil or session.leader == PartySync:MyKey()
end

--- Tell every member the roster: who leads and who is in. The leader's to send.
function Peers:SendRoster()
	local session = self:Session()
	if not session then return end
	local names = {}
	for key, name in pairs(session.members) do
		if key ~= PartySync:MyKey() then table.insert(names, name) end
	end
	table.sort(names)
	table.insert(names, 1, MyName())
	local joined = table.concat(names, ";")
	for key in self:Members() do
		Comm:Whisper(self:MemberName(key), "RO", session.id, session.leader, joined)
	end
end

local AUDIO_CHANNELS = PartySync.GAME_CHANNELS

local function AudioField(rules)
	local parts = {}
	for _, channel in ipairs(AUDIO_CHANNELS) do
		table.insert(parts, channel .. "=" .. (rules.audio and rules.audio[channel] or "none"))
	end
	return table.concat(parts, ";")
end

local function SyncFlags(rules)
	local flags = {}
	for i, kind in ipairs(SYNC_KINDS) do
		flags[i] = (rules.sync == nil or rules.sync[kind] ~= false) and "1" or "0"
	end
	return table.concat(flags)
end

--- Tell `key`, or every member, the rules. The leader's to send.
function Peers:SendRules(key)
	local session = self:Session()
	if not session then return end
	local rules = session.rules
	local targets = key and { key } or self:OnlineMembers()
	for _, target in ipairs(targets) do
		Comm:Whisper(self:MemberName(target), "PS", rules.controls or "anyone", rules.room or "none", SyncFlags(rules),
			rules.share or "anyone", AudioField(rules))
	end
end

local function Join(key, name)
	local session = Peers:Session()
	session.members[key] = name
	joinedAt[key] = GetTime()
	PartySync:Trace("party", "%s joined the party", key)
	Peers:Seen(name)
	PartySync:Print("%s is in your Spoken party", PartySync:ShortName(name))
	Peers:SendRoster()
	Peers:SendRules(key)
	Changed()
end

--- `key` is no longer in the party: left, removed, offline or lost. The leader tells the rest;
--- a member only drops them, and takes the lead when the leader is the one gone.
function Peers:Gone(key, why)
	local session = self:Session()
	if not (session and session.members[key]) or key == PartySync:MyKey() then
		return
	end
	local name = session.members[key]
	joinedAt[key] = nil
	left[key] = { at = Now(), id = session.id }
	if TROUBLE[why] then session.troubled = true end
	PartySync:Trace("party", "%s left the party (%s)", key, tostring(why))
	PartySync:Resolve("presence:" .. key)
	-- Ended with them still in it, so what is kept of the party has them.
	if self:Count() <= 2 then
		self:EndSession(format("The Spoken party ended: %s is gone.", PartySync:ShortName(name)))
		return
	end
	session.members[key] = nil
	local me = PartySync:MyKey()
	if session.leader == key then
		local standIn = self:Leader()
		if standIn == me then
			session.leader = me
			PartySync:Trace("party", "leader: %s (stands in for %s, who is %s)", me, key, tostring(why))
			PartySync:Print("%s is gone: you lead the Spoken party now", PartySync:ShortName(name))
		end
	end
	if session.leader == me then
		self:SendRoster()
	end
	Changed()
end

--- Remove `name` from the party and tell them. The leader's to do.
function Peers:RemoveMember(name)
	local key = PartySync:NameKey(name)
	local session = self:Session()
	if not (key and session and session.members[key]) then
		return false, "not in the party"
	end
	if session.leader ~= PartySync:MyKey() then
		return false, L.ONLY_LEADER_REMOVES
	end
	local who = self:MemberName(key)
	PartySync:Trace("party", "%s removed from the party here", key)
	Comm:Whisper(who, "ID", session.id)
	self:Gone(key, "removed here")
	return true
end

--- Leave the party. A leader hands the lead to the first by name before going.
function Peers:Leave()
	local session = self:Session()
	if not session then
		return false
	end
	local me = PartySync:MyKey()
	local others = {}
	for key in self:Members() do table.insert(others, key) end
	table.sort(others)
	if session.leader == me and others[1] then
		-- The others carry on under the first by name; the party left here stays the one led here.
		local heir = others[1]
		PartySync:Trace("party", "leaving the party: lead passed to %s", heir)
		local names = {}
		for _, key in ipairs(others) do table.insert(names, session.members[key]) end
		for _, key in ipairs(others) do
			Comm:Whisper(self:MemberName(key), "RO", session.id, heir, table.concat(names, ";"))
		end
	else
		for _, key in ipairs(others) do
			Comm:Whisper(self:MemberName(key), "ID", session.id)
		end
	end
	self:EndSession("You left the Spoken party.")
	return true
end

--------------------------------------------------------------------------------
-- Hello
--------------------------------------------------------------------------------

-- What the others read in this computer's hello besides who it is: whether it decides a channel
-- itself, and what it plays.
local function HelloFields()
	return PartySync.Room:IsOwn() and 1 or 0, PartySync.Room:PlaysLetters()
end

--- To the group, for whoever runs the addon there.
function Peers:Hello()
	return Comm:Broadcast("HI", PartySync.version, 0, SessionWord(), HelloFields())
end

--- To `name`, by whisper: a member at login, or someone in the usual party who may be
--- online by now.
function Peers:Greet(name, reply)
	return Comm:Whisper(name, "HI", PartySync.version, reply and 1 or 0, SessionWord(), HelloFields())
end

--- To every member by name. One that is offline costs a "No player named" message, which
--- Comm keeps out of the chat window and reads as offline.
function Peers:HelloMembers(reply)
	for key in self:Members() do
		self:Greet(self:MemberName(key), reply)
	end
end

local announced = nil

--- Tell the members who are online when what this computer's hello says has changed: a rule or
--- its own choice moved what it plays.
function Peers:AnnounceIfChanged()
	local own, plays = HelloFields()
	local hello = own .. plays
	local changed = announced ~= nil and hello ~= announced
	announced = hello
	if changed and self:InParty() then self:Announce() end
end

--- Something the others read in the hello has changed: tell the members who are online.
function Peers:Announce()
	for _, key in ipairs(self:OnlineMembers()) do
		self:Greet(self:MemberName(key), true)
	end
	Changed()
end

--- Logged in with a party saved: say hello to its members, who have until the first missed
--- heartbeats to answer.
function Peers:Resume()
	local session = self:Session()
	if not session then return end
	self.resumedAt = GetTime()
	PartySync:Trace("party", "party %s resumed: %d member(s), %s leads", session.id, self:Count(), tostring(session.leader))
	self:HelloMembers()
end

local told = {}

Comm:On("HI", function(sender, channel, version, reply, sessionId, own, plays)
	local known = Peers:Get(sender)
	local wasOnline = known and known.state == "online"
	local peer = Peers:Seen(sender, version)
	if not peer then return end
	sessionId = sessionId or ""
	-- A hello from before 0.5 says nothing of what it plays: the rules are read for it instead.
	plays = (plays ~= nil and plays ~= "") and plays or nil
	local changed = peer.session ~= sessionId or peer.own ~= (own == "1") or peer.plays ~= plays
	peer.session, peer.own, peer.plays = sessionId, own == "1", plays
	local key = PartySync:NameKey(sender)
	if Peers:IsMember(sender) then
		if not wasOnline then
			PartySync:Print("%s is here (Spoken Party Sync %s)", PartySync:ShortName(sender), tostring(version))
		end
		-- In another party, or in none: gone from this one. A hello sent just before they
		-- accepted may arrive after, so a newcomer is given a moment.
		if sessionId ~= Peers:SessionId() and (not joinedAt[key] or GetTime() - joinedAt[key] > JOIN_GRACE) then
			Peers:Gone(key, sessionId == "" and "in no party now" or "in another party")
		end
	elseif not told[key] and not (Autoform() and Autoform():Entry(key)) then
		told[key] = true
		PartySync:Print("%s runs Spoken Party Sync too: /sps invite %s to play lines together",
			PartySync:ShortName(sender), PartySync:ShortName(sender))
	end
	if reply ~= "1" then
		Peers:Greet(sender, true)
	end
	if changed then
		Changed()
	end
end)

--------------------------------------------------------------------------------
-- Invitations
--------------------------------------------------------------------------------

local POPUP = "SPOKENPARTYSYNC_INVITE"

--- Invite `name`. Starts a party, with `rules`, when this character is in none; refused when
--- another member leads. `rejoin` asks them back into the party they were in, without a popup.
function Peers:Invite(name, rules, rejoin)
	name = PartySync:CleanName(name)
	local key = PartySync:NameKey(name)
	if not key then
		return false, "no name"
	end
	if PartySync:IsSelf(name) then
		return false, "that is this character"
	end
	local session = self:Session()
	if session and session.leader ~= PartySync:MyKey() then
		return false, L.ONLY_LEADER_INVITES
	end
	if session and session.members[key] then
		return false, "already in the party"
	end
	session = session or NewSession(rules)
	invited[key] = { at = GetTime(), id = session.id, name = PartySync:WhisperName(name) }
	PartySync:Resolve("invite:" .. key)
	local sent, answer = Comm:Whisper(name, "IV", PartySync.version, session.id, rejoin and 1 or 0)
	PartySync:Trace("party", "invited %s to %s%s: %s", key, session.id, rejoin and ", asked back" or "",
		sent and "sent" or tostring(answer))
	Changed()
	return sent, answer
end

function Peers:AcceptInvite(name, id)
	if not (name and id and id ~= "") then return end
	local key = PartySync:NameKey(name)
	Comm:Whisper(name, "IA", id)
	local session = {
		id = id,
		leader = key,
		members = { [PartySync:MyKey()] = MyName(), [key] = PartySync:WhisperName(name) },
		-- Until the leader's rules arrive.
		rules = PartySync.Rules(),
		started = Now(),
		played = 0,
	}
	PartySync:Party().session = session
	joinedAt[key] = GetTime()
	PartySync:Trace("party", "joined %s's party %s", key, id)
	Peers:Seen(name)
	PartySync:Print("You are in %s's Spoken party", PartySync:ShortName(name))
	Changed()
end

function Peers:DeclineInvite(name, id)
	if not name then return end
	Comm:Whisper(name, "ID", id or "")
end

--- The invitations to this party still waiting for an answer, by name: { key, name, seconds }.
function Peers:Invitations()
	local id, now, list = self:SessionId(), GetTime(), {}
	for key, pending in pairs(invited) do
		if pending.id == id and not pending.expired then
			table.insert(list, { key = key, name = pending.name or key, seconds = math.floor(now - pending.at + 0.5) })
		end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	return list
end

--- An invitation that will not be answered now, as a problem the window offers to send again.
local function InvitationFailed(key, text)
	PartySync:Trace("party", "invitation to %s: %s", key, text)
	PartySync:Print("%s", text)
	PartySync:Problem("invite:" .. key, text, { kind = "silent", who = key })
end

--- Each second: an invitation unanswered for as long as the other side's popup lasts has failed,
--- most often because Spoken Party Sync is not installed there.
function Peers:CheckInvitations()
	local now = GetTime()
	for key, pending in pairs(invited) do
		if not pending.expired and now - pending.at > INVITE_SECONDS then
			pending.expired = true
			InvitationFailed(key, format(L.PROBLEM_NO_INVITE_ANSWER_FMT, PartySync:ShortName(pending.name or key)))
		end
	end
end

--- The client said `key` is not online: an invitation just sent to them goes nowhere.
function Peers:InviteeOffline(key, name)
	local pending = invited[key]
	if not pending then return end
	invited[key] = nil
	InvitationFailed(key, format(L.PROBLEM_OFFLINE_FMT, PartySync:ShortName(pending.name or name or key)))
	Changed()
end

--- Withdraw an invitation still waiting: their popup closes. A party of one with nobody left to
--- wait for goes at once.
function Peers:CancelInvite(key)
	local pending = invited[key]
	if not pending then return false end
	invited[key] = nil
	Comm:Whisper(pending.name or key, "ID", pending.id)
	PartySync:Trace("party", "invitation to %s withdrawn", key)
	PartySync:Resolve("invite:" .. key)
	self:DropEmpty()
	Changed()
	return true
end

--- Why this character may not do what only the leader does, or nil when it leads or is in no
--- party.
function Peers:WhyNotLeader()
	if self:MayInvite() then return nil end
	return format(L.ONLY_LEADER_FMT, self:ShortName(self:Leader() or "?"))
end

function Peers:ShortName(key)
	return PartySync:ShortName(self:MemberName(key))
end

--- Ask `name` again. A member who stopped answering is greeted and, from the leader, invited to
--- the party it is in, which it answers as a member re-linking (the roster and the rules come
--- back). Someone dropped from this party lately, or from the one that just ended, is invited
--- (to a new party with the old one's rules, if this character is in none) and rejoins without
--- a popup. Never the old party under its old id: the others may still be in it, led by
--- someone else. Returns what Invite returns.
function Peers:Reinvite(name)
	local key = PartySync:NameKey(name)
	if not key then
		return false, "no name"
	end
	local who = self:MemberName(key)
	if not self:IsMember(key) then
		local id = self:WasIn(key)
		local session = self:Session()
		local rejoin = id ~= nil and (session == nil or session.id == id)
		local last = PartySync:Party().lastSession
		return self:Invite(who, not session and rejoin and last and last.rules or nil, rejoin)
	end
	self:Greet(who)
	local session = self:Session()
	if session.leader == PartySync:MyKey() then
		Comm:Whisper(who, "IV", PartySync.version, session.id)
	end
	PartySync:Trace("party", "%s asked again", key)
	return true
end

-- { key, id }: the invitation whose popup is up here, so its inviter can withdraw it.
local asked = nil

local function DefinePopup()
	if not StaticPopupDialogs or StaticPopupDialogs[POPUP] then
		return
	end
	StaticPopupDialogs[POPUP] = {
		text = L.INVITE_POPUP,
		button1 = ACCEPT or "Accept",
		button2 = DECLINE or "Decline",
		OnAccept = function(_, data)
			asked = nil
			Peers:AcceptInvite(data.name, data.id)
		end,
		OnCancel = function(_, data, reason)
			asked = nil
			-- Only a click is an answer; a popup that timed out or was replaced says nothing.
			if reason == "clicked" then Peers:DeclineInvite(data.name, data.id) end
		end,
		timeout = 120,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
end

--- Whether this character is in a party of one it has only just started: two members of an
--- usual party inviting each other at once each stand in one, and the lower name's wins.
local function Alone()
	local session = Peers:Session()
	return session ~= nil and Peers:Count() == 1
end

Comm:On("IV", function(sender, channel, version, sessionId, rejoin)
	Peers:Seen(sender, version)
	local key = PartySync:NameKey(sender)
	sessionId = sessionId or ""
	local session = Peers:Session()
	if session then
		if session.id == sessionId then
			-- Already a member: the other side lost its list (a new install, another computer), and
			-- asking again would be a question with one answer.
			Comm:Whisper(sender, "IA", sessionId)
			return
		end
		if Alone() and key < PartySync:MyKey() then
			PartySync:Trace("party", "%s's invitation crosses this party of one: theirs wins", key)
			invited = {}
			Peers:EndSession("their invitation came first", true)
		else
			PartySync:Trace("party", "%s's invitation to %s declined: already in a party", key, sessionId)
			PartySync:Print("%s invited you to a Spoken party, but you are in one already", PartySync:ShortName(sender))
			Comm:Whisper(sender, "ID", sessionId)
			return
		end
	end
	if rejoin == "1" and Peers:WasIn(key) then
		PartySync:Trace("party", "%s, in the last party here, asks this character back: joined %s", key, sessionId)
		Peers:AcceptInvite(sender, sessionId)
		return
	end
	if Autoform() and Autoform():Accepts(key) then
		PartySync:Trace("party", "%s's invitation accepted: in the usual party, auto-accept", key)
		Peers:AcceptInvite(sender, sessionId)
		return
	end
	DefinePopup()
	if StaticPopup_Show then
		asked = { key = key, id = sessionId }
		StaticPopup_Show(POPUP, PartySync:ShortName(sender), nil, { name = PartySync:WhisperName(sender), id = sessionId })
	end
end)

Comm:On("IA", function(sender, channel, sessionId)
	local key = PartySync:NameKey(sender)
	local session = Peers:Session()
	-- Only an answer to a question this client asked, for the party it leads.
	if not (session and session.leader == PartySync:MyKey() and (sessionId == "" or sessionId == session.id)) then
		return
	end
	if not (invited[key] or session.members[key]) then
		-- Accepted after the invitation was withdrawn: they joined a party that does not count
		-- them, and are told to leave it.
		PartySync:Trace("party", "%s accepted an invitation withdrawn: told to leave", key)
		Comm:Whisper(sender, "ID", session.id)
		return
	end
	invited[key] = nil
	PartySync:Resolve("invite:" .. key)
	if session.members[key] then
		-- A member re-linking: the roster again, in case theirs is stale.
		Peers:SendRoster()
		Peers:SendRules(key)
		return
	end
	Join(key, PartySync:WhisperName(sender))
end)

Comm:On("ID", function(sender, channel, sessionId)
	local key = PartySync:NameKey(sender)
	sessionId = sessionId or ""
	local session = Peers:Session()
	local pending = invited[key]
	if pending and (sessionId == "" or sessionId == pending.id) then
		invited[key] = nil
		PartySync:Trace("party", "%s declined the invitation", tostring(key))
		local text = format(L.PROBLEM_DECLINED_FMT, PartySync:ShortName(sender))
		PartySync:Print("%s", text)
		-- Theirs to decide: nothing to offer but dismissing it.
		PartySync:Problem("invite:" .. key, text)
		return
	end
	if asked and asked.key == key and (sessionId == "" or sessionId == asked.id) then
		asked = nil
		if StaticPopup_Hide then StaticPopup_Hide(POPUP) end
		PartySync:Trace("party", "%s withdrew the invitation", key)
		PartySync:Print("%s", format(L.INVITE_WITHDRAWN_FMT, PartySync:ShortName(sender)))
		return
	end
	-- About another party, or an invitation long gone: not this party's business.
	if not (session and session.members[key]) or (sessionId ~= "" and sessionId ~= session.id) then
		return
	end
	if session.leader == key then
		Peers:EndSession(format("%s removed you from the Spoken party.", PartySync:ShortName(sender)))
		return
	end
	PartySync:Print("%s left your Spoken party", PartySync:ShortName(sender))
	Peers:Gone(key, "left")
end)

--------------------------------------------------------------------------------
-- The roster and the rules
--------------------------------------------------------------------------------

Comm:On("RO", function(sender, channel, sessionId, leader, members)
	local key = PartySync:NameKey(sender)
	local session = Peers:Session()
	if not (session and session.id == sessionId and session.members[key]) then
		return
	end
	local me = PartySync:MyKey()
	local roster = {}
	for name in tostring(members or ""):gmatch("[^;]+") do
		local k = PartySync:NameKey(name)
		if k then roster[k] = PartySync:WhisperName(name) end
	end
	if not roster[me] then
		Peers:EndSession(format("%s removed you from the Spoken party.", PartySync:ShortName(sender)))
		return
	end
	local was = session.leader
	local newLeader = PartySync:NameKey(leader) or was
	-- Only the leader, or whoever stands in for a leader that is gone, speaks for the roster.
	if key ~= was and key ~= newLeader then
		PartySync:Trace("party", "roster from %s ignored: %s leads", key, tostring(was))
		return
	end
	-- Nobody else in it: ended as it was, so what is kept of the party has them.
	local size = 0
	for _ in pairs(roster) do size = size + 1 end
	if size < 2 then
		Peers:EndSession("The Spoken party ended: nobody else is left.")
		return
	end
	for k, name in pairs(roster) do
		if not session.members[k] then
			joinedAt[k] = GetTime()
			PartySync:Print("%s is in your Spoken party", PartySync:ShortName(name))
		end
	end
	for k in pairs(session.members) do
		if not roster[k] then
			PartySync:Resolve("presence:" .. k)
			joinedAt[k] = nil
		end
	end
	session.members = roster
	session.leader = newLeader
	PartySync:Trace("party", "roster from %s: %s leads, %d member(s)", key, newLeader, Peers:Count())
	if newLeader ~= was then
		PartySync:Print("%s leads the Spoken party now", newLeader == me and "You" or PartySync:ShortName(roster[newLeader] or leader))
	end
	Changed()
end)

--- The rules in force: the party's, or this computer's own for the party it would start.
function Peers:Rules()
	local session = self:Session()
	return session and session.rules or PartySync:DB().rules
end

local function DescribeRules(rules)
	local on = {}
	for _, kind in ipairs(SYNC_KINDS) do
		if rules.sync == nil or rules.sync[kind] ~= false then table.insert(on, kind) end
	end
	local audio = {}
	for _, channel in ipairs(AUDIO_CHANNELS) do
		local owner = rules.audio and rules.audio[channel] or "none"
		if owner ~= "none" then table.insert(audio, format(", %s %s", channel, owner)) end
	end
	return format("controls %s, sound %s, quests shared by %s, played together %s%s", tostring(rules.controls),
		tostring(rules.room), tostring(rules.share or "anyone"), on[1] and table.concat(on, ", ") or "nothing",
		table.concat(audio))
end
Peers.DescribeRules = DescribeRules

--- Whether a quest this character accepts is shared with the party, per the rule: anyone's,
--- the leader's only, or nobody's.
function Peers:MayShare()
	local share = self:Rules().share or "anyone"
	if share == "anyone" then return true end
	if share == "leader" then return self:AmLeader() end
	return false
end

--- Why a quest this character accepts is not shared, per the rule; nil when it is.
function Peers:WhyNoShare()
	if self:MayShare() then
		return nil
	end
	return (self:Rules().share or "anyone") == "leader" and L.SHARE_LEADER or L.SHARE_NOBODY
end

--- Change the rules with `change(rules)`. In a party, the leader's to do, and every member is
--- told; outside one, this computer's own for the next party it starts.
function Peers:EditRules(change)
	local session = self:Session()
	if session and session.leader ~= PartySync:MyKey() then
		return false, L.ONLY_LEADER_RULES
	end
	change(session and session.rules or PartySync:DB().rules)
	if session then
		self:SendRules()
	end
	Changed()
	return true
end

--- Set a rule: `controls` ("anyone", "leader", "nobody"), `room` (who plays the voice),
--- `share` ("anyone", "leader", "nobody"), `sync` with a kind and whether it is on, or `audio`
--- with a channel and its owner ("none", a member's key, or "-<key>,<key>").
function Peers:SetRule(name, value, on)
	return self:EditRules(function(rules)
		if name == "sync" then
			rules.sync = rules.sync or {}
			rules.sync[value] = on and true or false
			PartySync:TraceSetting("play together " .. tostring(value), rules.sync[value])
		elseif name == "audio" and value == "voice" then
			rules.room = on
			PartySync:TraceSetting("room", tostring(on))
		elseif name == "audio" then
			rules.audio = rules.audio or {}
			rules.audio[value] = on
			PartySync:TraceSetting(tostring(value) .. " on", tostring(on))
		else
			rules[name] = value
			PartySync:TraceSetting(name, tostring(value))
		end
	end)
end

Comm:On("PS", function(sender, channel, controls, room, flags, share, audio)
	local key = PartySync:NameKey(sender)
	local session = Peers:Session()
	if not (session and session.leader == key) then
		return
	end
	local rules = session.rules
	rules.controls = controls ~= "" and controls or "anyone"
	rules.room = room ~= "" and room or "none"
	-- A leader on 0.4.0 sends no `share`: the rule it never had is the default.
	rules.share = share ~= nil and share ~= "" and share or "anyone"
	rules.sync = rules.sync or {}
	flags = tostring(flags or "")
	for i, kind in ipairs(SYNC_KINDS) do
		local flag = flags:sub(i, i)
		if flag ~= "" then rules.sync[kind] = flag == "1" end
	end
	-- A leader before 0.5 sends no channels: every computer plays them.
	rules.audio = PartySync.Rules().audio
	for name, owner in tostring(audio or ""):gmatch("([^;=]+)=([^;]*)") do
		if rules.audio[name] and owner ~= "" then rules.audio[name] = owner end
	end
	PartySync:Trace("party", "rules from %s: %s", key, DescribeRules(rules))
	if PartySync.Room then PartySync.Room:Update() end
	Changed()
end)

--------------------------------------------------------------------------------
-- Who leads
--------------------------------------------------------------------------------

--- The leader's key and why, or nil without a party. A leader that is gone is stood in for by
--- the first by name of those still here, this character included, so every member agrees.
function Peers:Leader()
	local session = self:Session()
	local me = PartySync:MyKey()
	if not (session and me) then
		return nil, "no party"
	end
	local leader = session.leader
	local peer = self.list[leader]
	if leader == me or (peer and peer.state == "online") or (session.members[leader] and not peer
		and self.resumedAt and GetTime() - self.resumedAt <= LOST_SECONDS) then
		return leader, "leads the party"
	end
	local keys = self:OnlineMembers()
	table.insert(keys, me)
	table.sort(keys)
	return keys[1], format("stands in for %s", tostring(leader))
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

function Peers:IsLeader(key)
	return key ~= nil and self:Leader() == key
end

function Peers:AmLeader()
	return self:IsLeader(PartySync:MyKey())
end

--- Hand the lead to `name`, a member. The leader's to do.
function Peers:PassLead(name)
	local key = PartySync:NameKey(name)
	local session = self:Session()
	if not (key and session and session.members[key]) then
		return false, "not in the party"
	end
	if session.leader ~= PartySync:MyKey() then
		return false, L.ONLY_LEADER_PASSES
	end
	if key == session.leader then
		return false, "already leads"
	end
	session.leader = key
	PartySync:Trace("party", "lead passed to %s", key)
	self:SendRoster()
	Changed()
	return true
end

--- A party of one with no invitation standing is no party: it goes quietly.
function Peers:DropEmpty()
	if not Alone() then return end
	local now = GetTime()
	for key, pending in pairs(invited) do
		if now - pending.at <= INVITE_SECONDS then return end
		invited[key] = nil
	end
	self:EndSession("nobody joined", true)
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

--- Ping every member, keeping the round for PingSummary.
function Peers:PingMembers()
	local keys = {}
	for key in self:Members() do table.insert(keys, key) end
	table.sort(keys)
	if not keys[1] then
		self.pingRound = nil
		PartySync:Print("nobody in your Spoken party yet: /sps invite <name>")
		return
	end
	self.pingRound = { at = GetTime(), keys = keys, ms = {} }
	for _, key in ipairs(keys) do
		self:Ping(self:MemberName(key))
	end
	-- The members who never answered are only "no answer" once the wait is over.
	C_Timer.After(PING_TIMEOUT + 0.1, function() PartySync:Changed() end)
end

--- The last PingMembers, member by member ("Lala 1145 ms", "Mira no answer"); nil before one.
function Peers:PingSummary()
	local round = self.pingRound
	if not round then
		return nil
	end
	local over = GetTime() - round.at >= PING_TIMEOUT
	local parts = {}
	for _, key in ipairs(round.keys) do
		local ms = round.ms[key]
		table.insert(parts, format("%s %s", PartySync:FirstName(self:MemberName(key)),
			ms and format("%d ms", math.floor(ms + 0.5)) or (over and L.PING_NO_ANSWER or L.PING_WAITING)))
	end
	return table.concat(parts, PartySync.DOT)
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
	local round = Peers.pingRound
	if round and not ping.quiet and ping.sentAt >= round.at then
		round.ms[PartySync:NameKey(sender)] = ms
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
					PartySync:Problem("presence:" .. key, format(L.PROBLEM_LOST_FMT, peer.name), { kind = "silent", who = key })
					self:Gone(key, "lost")
				end
				Changed()
			elseif now - (peer.lastSeen or 0) >= HEARTBEAT_SECONDS - 1 then
				self:Ping(peer.name, true)
			end
		end
	end
	-- A member of a party resumed at login that never answered the hello.
	if self.resumedAt and now - self.resumedAt > LOST_SECONDS then
		for key, name in self:Members() do
			if not self.list[key] then
				PartySync:Trace("party", "%s never answered since login", key)
				PartySync:Problem("presence:" .. key, format(L.PROBLEM_LOST_FMT, name), { kind = "silent", who = key })
				self:Gone(key, "never answered since login")
			end
		end
		self.resumedAt = nil
	end
	self:CheckInvitations()
	self:DropEmpty()
	if Autoform() then Autoform():Tick() end
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
