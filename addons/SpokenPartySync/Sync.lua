-- The engine: a line queued on one computer is played on every computer in the party, and
-- starts on all of them at once.
--
-- Whoever's client queues a line drives it. The others follow: they rebuild it from its
-- description (Lines.lua) and queue it, held, until the driver says go.
--
--   1. The driver's client queues a line. At CLIP_QUEUED it is announced -- LN, then its words
--      in TX pieces -- to every member online, and held by this addon's gate.
--   2. Each follower rebuilds it, queues it held, and acknowledges (AK queued, or missing when
--      it has no file and shows the words alone).
--   3. When the line reaches the front of the driver's queue, GO goes out to each member with
--      how long to wait, and the driver waits for the slowest: half the slowest member's round
--      trip, which is when that member receives the GO. The others wait the difference. So all
--      of them start within the jitter of one message, about 0.1 s on the beta.
--   4. Each acknowledges when it starts (with how late, if another line was still speaking
--      there), when it finishes, or if it dropped the line.
--
--   GO  id, startInMs       start it in this many ms.
--   AK  id, state, ms       queued | missing | started | finished | dropped | yielded
--   SK  id                  this line was skipped or stopped: remove it here too.
--   PZ / RS                 stop / replay (Spoken:Pause / Resume).
--
-- A line waiting to start together holds everything queued behind it, so both queues keep
-- the same order: the player's own rule that a held line is stepped over would otherwise let
-- the next one jump ahead on one computer and not the other.
--
-- Two of the party starting the same line at once -- both talked to the quest giver -- is
-- settled the same way on every client: the leader's copy wins, else the lower name's. The
-- loser's copy becomes a follower of the winner's. A local line already played together a
-- moment ago is refused at the door: the quest giver's line Lala hears again by talking to
-- the giver after Tata did, and the accept line a shared quest would read once more.

local _, PartySync = ...

local Comm, Peers, Lines, L = PartySync.Comm, PartySync.Peers, PartySync.Lines, PartySync.L

local Sync = {
	-- id -> entry: { id, role = "driver"|"follower", driver, clip, desc, state, peers, ... }
	-- state: waiting (held), go (start planned), released, playing, finished, stopped,
	--        dropped, missing (no clip here), text (waiting for the words to build a stand-in)
	lines = {},
	recent = {},     -- id -> when a follower copy last started or ended
	expected = {},   -- questID -> until when a shared quest's accept line is refused here
}
PartySync.Sync = Sync

-- The longest the driver holds its own start for the slowest member: past this a round trip
-- is not latency but a member in trouble, and the line should not wait on them.
local MAX_START_DELAY_MS = 1500
-- How long a follower copy at the front of the queue waits for its start before playing alone.
local GO_TIMEOUT = 15
-- How long after a follower copy ends the same line from this client is refused.
local RECENT_SECONDS = 20
-- Past a member's round trip, how long before a line they never answered counts as unanswered.
local ANSWER_GRACE = 2
-- How long a line that is over is kept for `/sps sync`.
local KEEP_SECONDS = 60
-- How long a follower's start waits for the words still on their way. They are sent before
-- the start, but messages arriving in one frame are not always handled in the order sent, and
-- the captions read a line's words once, as it starts (2026-10-05, "Mirror Lake").
local TEXT_WAIT = 2

local applyingRemote = false
local lastPaused

local function Spoken()
	return _G.Spoken
end

local function Trace(message, ...)
	PartySync:Trace("sync", message, ...)
end

local function MyKey()
	return PartySync:MyKey()
end

local function Short(key)
	return PartySync:ShortName(Peers:MemberName(key))
end

local function LabelOf(entry)
	local clip, d = entry.clip, entry.desc
	local present = clip and clip.present
	return (present and (present.label ~= "" and present.label or present.header))
		or (d and (d.title ~= "" and d.title or d.name)) or entry.id
end
Sync.LabelOf = LabelOf

--- The line a Stop or Replay acts on, for the log: its id and title, or the player's own key
--- for a line not played together.
local function Describe(clip)
	if not clip then return "nothing queued" end
	local entry = clip.partySync
	if entry then return format("%s (%s)", entry.id, tostring(LabelOf(entry))) end
	local ok, id = pcall(Lines.Id, Lines, clip)
	return format("%s, not played together", tostring(ok and id or clip.key))
end

local function Head()
	local S = Spoken()
	return S:GetCurrent() or S:GetQueue()[1]
end

local function InQueue(clip)
	if not clip then return false end
	for _, queued in ipairs(Spoken():GetQueue()) do
		if queued == clip then return true end
	end
	return false
end

local function Waiting(entry)
	return entry.state == "waiting" or entry.state == "go"
end

local function RecheckGates()
	local S = Spoken()
	if S.RecheckGates then
		S:RecheckGates()
		return
	end
	-- A player from before Spoken:RecheckGates: what it does, through the queue itself.
	local env = rawget(_G, "SpokenEnv")
	if env and env.SoundQueue and env.SoundQueue.Advance then
		env.SoundQueue:Advance()
	end
end

local function Send(key, kind, ...)
	return Comm:Whisper(Peers:MemberName(key), kind, ...)
end

local function SendAll(kind, ...)
	for _, key in ipairs(Peers:OnlineMembers()) do
		Send(key, kind, ...)
	end
end

local function Ack(entry, state, ms)
	if entry.role == "follower" and entry.driver then
		Send(entry.driver, "AK", entry.id, state, ms and math.floor(ms + 0.5) or "")
	end
end

function Sync:Live()
	return self.ready == true and Peers:AnyOnline()
end

function Sync:Available()
	return PartySync:PlayerAvailable()
end

--- Whether `kind` of line is played together, per the settings.
function Sync:Syncs(kind)
	local sync = PartySync:DB().sync
	return kind ~= nil and sync[kind] ~= false
end

--------------------------------------------------------------------------------
-- Entries
--------------------------------------------------------------------------------

-- `gen` moves on whenever the entry changes hands, so a start timer set before is ignored.
local function NewEntry(id, role, driver, clip)
	local entry = { id = id, role = role, driver = driver, clip = clip, state = "waiting", peers = {}, at = GetTime(), gen = 0 }
	Sync.lines[id] = entry
	if clip then clip.partySync = entry end
	return entry
end

local function Forget()
	local now = GetTime()
	for id, entry in pairs(Sync.lines) do
		if not Waiting(entry) and entry.state ~= "playing" and entry.state ~= "released"
			and entry.state ~= "text" and now - (entry.endedAt or entry.at) > KEEP_SECONDS then
			Sync.lines[id] = nil
		end
	end
end

--- Every line this session knows of, newest first, for `/sps sync`.
function Sync:Entries()
	Forget()
	local list = {}
	for _, entry in pairs(self.lines) do table.insert(list, entry) end
	table.sort(list, function(a, b) return a.at > b.at end)
	return list
end

local function Ended(entry, state)
	entry.state = state
	entry.endedAt = GetTime()
	if entry.role == "follower" then
		Sync.recent[entry.id] = GetTime()
	end
end

--- Whether a local line with this id has just been played together here, or is queued to be.
function Sync:PlayedTogether(id)
	local entry = id and self.lines[id]
	if entry and entry.role == "follower" and entry.clip and (Waiting(entry) or entry.state == "released"
		or entry.state == "playing") then
		return true
	end
	local at = id and self.recent[id]
	return at ~= nil and GetTime() - at <= RECENT_SECONDS
end

--- A quest shared by a member is being accepted here: its accept line has just been played
--- together, and the dialog the share opened would read it once more.
function Sync:ExpectShared(questID)
	if questID then
		self.expected[questID] = GetTime() + 15
	end
end

--------------------------------------------------------------------------------
-- Holding and starting
--------------------------------------------------------------------------------

local function Gate(clip)
	local entry = clip.partySync
	if entry then
		if Waiting(entry) then
			if entry.role == "driver" then
				return L.HOLD_SYNCING
			end
			return format(L.HOLD_WAITING_FMT, Short(entry.driver))
		end
		return nil
	end
	-- Behind a line waiting to start together: kept in order, as the other queues are.
	for _, queued in ipairs(Spoken():GetQueue()) do
		if queued == clip then
			return nil
		end
		local ahead = queued.partySync
		if ahead and Waiting(ahead) then
			return L.HOLD_BEHIND
		end
	end
	return nil
end

local function TextPending(entry)
	return entry.role == "follower" and entry.parts ~= nil and entry.desc and (entry.desc.textParts or 0) > 0
end

function Sync:Release(entry, gen)
	if not Waiting(entry) or (gen and gen ~= entry.gen) then
		return
	end
	if TextPending(entry) then
		entry.textWaitFrom = entry.textWaitFrom or GetTime()
		if GetTime() - entry.textWaitFrom < TEXT_WAIT then
			if not entry.textWaitLogged then
				entry.textWaitLogged = true
				Trace("hold %s: its words are not all here yet", entry.id)
			end
			local current = entry.gen
			C_Timer.After(0.05, function() Sync:Release(entry, current) end)
			return
		end
		Trace("release %s without all its words: waited %d s", entry.id, TEXT_WAIT)
	end
	entry.state = "released"
	entry.releasedAt = GetTime()
	Trace("release %s (%s), planned start %s", entry.id, entry.role,
		entry.goAt and format("%+d ms", (GetTime() - entry.goAt) * 1000) or "none")
	RecheckGates()
	PartySync:Changed()
end

--- The driver's line is next: tell everyone when to start, and start after the slowest.
function Sync:Go(entry)
	local members = Peers:OnlineMembers()
	local delay = 0
	for _, key in ipairs(members) do
		delay = math.max(delay, Peers:Rtt(key) / 2)
	end
	delay = math.min(delay, MAX_START_DELAY_MS)
	for _, key in ipairs(members) do
		Send(key, "GO", entry.id, math.max(0, math.floor(delay - Peers:Rtt(key) / 2)))
	end
	entry.goAt = GetTime() + delay / 1000
	local told = {}
	for _, key in ipairs(members) do
		told[#told + 1] = format("%s %d ms (rtt %d)", key, math.max(0, math.floor(delay - Peers:Rtt(key) / 2)), Peers:Rtt(key))
	end
	Trace("go %s (%s): start here in %d ms; told %s", entry.id, tostring(LabelOf(entry)), delay, table.concat(told, ", "))
	if delay <= 0 then
		self:Release(entry)
		return
	end
	entry.state = "go"
	local gen = entry.gen
	C_Timer.After(delay / 1000, function() Sync:Release(entry, gen) end)
end

--- A follower's copy is next and its GO has not come: wait for it, but not for ever.
function Sync:AwaitGo(entry)
	if entry.awaiting then
		return
	end
	entry.awaiting = GetTime()
	Trace("next: %s, waiting for %s to say go", entry.id, tostring(entry.driver))
	local gen = entry.gen
	C_Timer.After(GO_TIMEOUT, function()
		if entry.state == "waiting" and entry.gen == gen then
			Trace("no go for %s from %s after %d s: playing alone", entry.id, tostring(entry.driver), GO_TIMEOUT)
			PartySync:Problem("go:" .. entry.id, format(L.PROBLEM_NO_GO_FMT, Short(entry.driver), LabelOf(entry)))
			Sync:Release(entry)
		end
	end)
end

--- Find the line that is next to start, and start it if it is waiting on this addon.
local ticking, tickAgain = false, false
function Sync:Tick()
	if ticking then
		tickAgain = true
		return
	end
	ticking = true
	for _ = 1, 3 do
		tickAgain = false
		local S = Spoken()
		if S:IsPaused() then break end
		for _, clip in ipairs(S:GetQueue()) do
			if S:IsPlaying(clip) then break end
			local entry = clip.partySync
			if entry then
				if entry.state == "waiting" then
					if entry.role == "driver" then
						if Peers:AnyOnline() then self:Go(entry) else self:Release(entry) end
					else
						self:AwaitGo(entry)
					end
				end
				break
			end
			-- A line no gate holds plays before anything behind it; one another gate holds
			-- (combat, a cinematic) is stepped over, as the player does.
			if not S:GetHeldReason(clip) then break end
		end
		if not tickAgain then break end
	end
	ticking = false
end

--- Members came or went. A line waiting on someone who is gone plays here alone.
function Sync:PresenceChanged()
	if not self.ready then return end
	local live = Peers:AnyOnline()
	local released = false
	for _, entry in pairs(self.lines) do
		if Waiting(entry) then
			local orphan = entry.role == "follower" and not (Peers.list[entry.driver]
				and Peers.list[entry.driver].state == "online")
			if orphan or (entry.role == "driver" and not live) then
				Trace("release %s: %s", entry.id, orphan and "its driver is gone" or "nobody online")
				entry.state = "released"
				released = true
			end
		end
	end
	if released then
		RecheckGates()
	end
end

--------------------------------------------------------------------------------
-- Driving: a line queued here
--------------------------------------------------------------------------------

local function Announce(entry, d)
	local parts = {}
	if d.text and d.text ~= "" then
		parts = Comm.Chunk(d.text, Comm.MAX_LENGTH - (#"TX" + #d.id + 12))
		local budget = Comm:TextBudget()
		-- Inside an instance a long text would use up the allowance and arrive after the line
		-- started; the others then read their own copy of it, where they have one.
		if budget and #parts > budget then parts = {} end
	end
	local fields = Lines:Encode(d, #parts)
	Trace("drive %s (%s): announced to %s, %d text piece(s)", d.id, LabelOf(entry),
		table.concat(Peers:OnlineMembers(), ", "), #parts)
	for _, key in ipairs(Peers:OnlineMembers()) do
		Send(key, "LN", unpack(fields))
		for i, part in ipairs(parts) do
			Send(key, "TX", d.id, i, #parts, part)
		end
		entry.peers[key] = { state = "sent", at = GetTime() }
		C_Timer.After(Peers:Rtt(key) / 1000 + ANSWER_GRACE, function()
			local peer = entry.peers[key]
			if peer and peer.state == "sent" then
				peer.state = "noanswer"
				PartySync:Problem("answer:" .. key, format(L.PROBLEM_NO_ANSWER_FMT, Short(key), LabelOf(entry)))
			end
		end)
	end
end

local function OnQueued(clip)
	if clip.partySync or not Sync:Live() then
		return
	end
	local kind = Lines:Kind(clip)
	if not Sync:Syncs(kind) then
		return
	end
	local d = Lines:Describe(clip)
	if not (d and d.id) then
		return
	end
	local entry = NewEntry(d.id, "driver", MyKey(), clip)
	entry.desc = d
	Announce(entry, d)
	PartySync:Changed()
end

--------------------------------------------------------------------------------
-- Following: a line queued elsewhere
--------------------------------------------------------------------------------

--- Who keeps driving when two start the same line: the leader, else the lower name.
function Sync:Wins(a, b)
	local leader = Peers:Leader()
	if leader == a then return true end
	if leader == b then return false end
	return a < b
end

local function Yield(entry, driver)
	Trace("yield %s to %s (was %s)", entry.id, tostring(driver), entry.state)
	entry.gen = entry.gen + 1
	entry.role = "follower"
	entry.driver = driver
	entry.state = "waiting"
	entry.peers = {}
	entry.awaiting = nil
	Ack(entry, "yielded")
end

local function Enqueue(entry, clip, source, why)
	clip.partySync = entry
	entry.clip = clip
	local added, reason = source:Enqueue(clip)
	Trace("follow %s from %s: %s%s", entry.id, tostring(entry.driver), added and ("queued as " .. tostring(clip.key)) or
		("not queued: " .. tostring(reason)), why == "missing" and " (no file here: captions over silence)" or "")
	if not added then
		Ended(entry, "dropped")
		Ack(entry, "dropped")
		return
	end
	Ack(entry, why == "missing" and "missing" or "queued")
end

local function Build(entry)
	local d = entry.desc
	local clip, why, source = Lines:Rebuild(d)
	if clip then
		Enqueue(entry, clip, source, why)
		return
	end
	-- No file here, but the words are on their way: build the stand-in once they are in.
	if why == "missing" and d.src == "quests" and (d.textParts or 0) > 0 and not d.text then
		entry.state = "text"
		return
	end
	Trace("follow %s from %s: cannot play it here (%s)", entry.id, tostring(entry.driver), tostring(why))
	Ended(entry, "missing")
	Ack(entry, "missing")
	if why == "old" then
		PartySync:Problem("old:" .. d.src, format(L.PROBLEM_OLD_MODULE_FMT, d.src))
	end
end

-- Messages about a line that arrive before the line itself. Whispers handled in one frame are
-- not always handled in the order they were sent: on 2026-10-05 a line's words and its start
-- came before its announcement and were thrown away, so the line waited for a start that had
-- already come, and for words it had already been sent. Kept a few seconds, by line and
-- sender, and applied when the announcement arrives.
local EARLY_SECONDS = 5
local early = {}

local function Early(id, key)
	local now = GetTime()
	for k, pending in pairs(early) do
		if now - pending.at > EARLY_SECONDS then early[k] = nil end
	end
	local k = id .. "|" .. key
	early[k] = early[k] or { at = now, parts = {} }
	return early[k]
end

local function TakeEarly(id, key)
	local k = id .. "|" .. key
	local pending = early[k]
	early[k] = nil
	if pending and GetTime() - pending.at <= EARLY_SECONDS then
		return pending
	end
	return nil
end

--- A piece of a line's words, and what follows once the last one is in.
local function AddText(entry, seq, total, piece)
	if seq then entry.parts[seq] = piece or "" end
	if not total then return end
	for i = 1, total do
		if not entry.parts[i] then return end
	end
	local text = Comm.Unescape(table.concat(entry.parts, "", 1, total))
	entry.parts = nil
	entry.desc.text = text
	Trace("words for %s: %d pieces, %d characters (%s)", entry.id, total, #text, entry.state)
	if entry.state == "text" then
		entry.state = "waiting"
		Build(entry)
	else
		Lines:SetText(entry.clip, text)
		-- Too late for the captions to have read them as the line started: they read again.
		if entry.clip and entry.state == "playing" then
			Lines:RefreshCaption(entry.clip)
		end
		if entry.clip and Spoken():GetCurrent() == entry.clip and Spoken().RefreshPlayer then
			Spoken():RefreshPlayer()
		end
		-- A start held for these words goes now, if its time has come.
		if entry.textWaitFrom and Waiting(entry) and (not entry.goAt or GetTime() >= entry.goAt) then
			Sync:Release(entry, entry.gen)
		end
	end
	PartySync:Changed()
end

--- The driver's start, received at `receivedAt`: whatever of the wait has passed is not waited.
local function ApplyGo(entry, key, startIn, receivedAt)
	local delay = math.max(0, (tonumber(startIn) or 0) / 1000 - (GetTime() - (receivedAt or GetTime())))
	entry.goAt = GetTime() + delay
	Trace("go %s from %s: start in %d ms (was %s)", entry.id, key, delay * 1000, entry.state)
	PartySync:Resolve("go:" .. entry.id)
	if delay <= 0 then
		Sync:Release(entry)
		return
	end
	entry.state = "go"
	local gen = entry.gen
	C_Timer.After(delay, function() Sync:Release(entry, gen) end)
end

Comm:On("LN", function(sender, channel, ...)
	if not (Sync.ready and Peers:IsMember(sender)) then
		return
	end
	Peers:Seen(sender)
	local key = PartySync:NameKey(sender)
	local d = Lines:Decode(...)
	if not d then
		return
	end
	if not Sync:Syncs(Lines:DescribedKind(d)) then
		Send(key, "AK", d.id, "dropped", "")
		return
	end
	local entry = Sync.lines[d.id]
	if entry and entry.role == "driver" and InQueue(entry.clip) then
		-- Both started this line. Settled the same way on both sides, so one of them yields.
		if Waiting(entry) and Sync:Wins(key, MyKey()) then
			Yield(entry, key)
			PartySync:Changed()
		end
		return
	end
	-- Already here as a copy, waiting or playing: announced again because it was started again
	-- over there. A second copy would be refused as a duplicate, and nothing is gained by trying.
	if entry and entry.role == "follower" and entry.clip and InQueue(entry.clip) then
		Trace("line %s from %s: already here (%s), announced again", d.id, key, entry.state)
		return
	end
	entry = NewEntry(d.id, "follower", key, nil)
	entry.desc = d
	entry.parts = {}
	local pending = TakeEarly(d.id, key)
	if pending then
		for seq, piece in pairs(pending.parts) do entry.parts[seq] = piece end
		Trace("line %s from %s: its words (%d piece(s))%s came before it", d.id, key, (function()
			local n = 0
			for _ in pairs(pending.parts) do n = n + 1 end
			return n
		end)(), pending.startIn and " and its start" or "")
	end
	-- The same line already queued here and not announced -- queued before the party was
	-- online, say: that copy follows, rather than a second one being refused as a duplicate.
	local adopted = false
	for _, clip in ipairs(Spoken():GetQueue()) do
		if not clip.partySync and Lines:Id(clip) == d.id then
			if Spoken():IsPlaying(clip) then
				Trace("line %s from %s: already playing here, not queued again", d.id, key)
				Ended(entry, "dropped")
				Ack(entry, "dropped")
				return
			end
			Trace("follow %s from %s: the copy already queued here follows", d.id, key)
			clip.partySync = entry
			entry.clip = clip
			Ack(entry, "queued")
			adopted = true
			break
		end
	end
	if not adopted then
		Build(entry)
	end
	if pending and pending.total and entry.parts then
		AddText(entry, nil, pending.total)
	end
	if pending and pending.startIn and Waiting(entry) then
		ApplyGo(entry, key, pending.startIn, pending.goAt)
	end
	PartySync:Changed()
end)

Comm:On("TX", function(sender, channel, id, seq, total, piece)
	if not (id and Peers:IsMember(sender)) then
		return
	end
	local entry = Sync.lines[id]
	local key = PartySync:NameKey(sender)
	seq, total = tonumber(seq), tonumber(total)
	if not (seq and total) then return end
	if entry and entry.role == "follower" and entry.driver == key then
		if entry.parts then
			AddText(entry, seq, total, piece)
			return
		end
		-- Words this copy already has: the line was announced again.
		if entry.clip and InQueue(entry.clip) then
			return
		end
	end
	-- Before its announcement, or for a line that will be announced again: kept for it.
	local pending = Early(id, key)
	pending.parts[seq] = piece or ""
	pending.total = total
end)

Comm:On("GO", function(sender, channel, id, startIn)
	if not (id and Peers:IsMember(sender)) then
		return
	end
	local entry = Sync.lines[id]
	local key = PartySync:NameKey(sender)
	if entry and entry.role == "driver" and InQueue(entry.clip) then
		-- Both started this line and their GO overtook their LN: settled as the LN would be.
		if not (Waiting(entry) and Sync:Wins(key, MyKey())) then return end
		Yield(entry, key)
	end
	if entry and entry.role == "follower" and entry.driver == key and entry.clip and InQueue(entry.clip) then
		if Waiting(entry) then
			ApplyGo(entry, key, startIn, GetTime())
		end
		-- Otherwise it is already playing here: a start for the same line started again.
		return
	end
	-- Before its announcement: kept, with when it came, so the wait it asks for counts from then.
	Trace("go %s from %s before its announcement: kept for it", id, key)
	local pending = Early(id, key)
	pending.startIn, pending.goAt = startIn, GetTime()
end)

Comm:On("AK", function(sender, channel, id, state, ms)
	local entry = id and Sync.lines[id]
	local key = PartySync:NameKey(sender)
	if not (entry and entry.role == "driver") then
		return
	end
	entry.peers[key] = { state = state, ms = tonumber(ms), at = GetTime() }
	Trace("ack %s from %s: %s%s", entry.id, key, tostring(state), ms and ms ~= "" and (" " .. ms .. " ms") or "")
	PartySync:Resolve("answer:" .. key)
	if state == "missing" then
		PartySync:Problem("missing:" .. key, format(L.PROBLEM_MISSING_FMT, Short(key), LabelOf(entry)))
	end
	PartySync:Changed()
end)

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

--- Whether this client's Stop, Replay, Skip and Stop All go to the others.
function Sync:CanControl()
	local policy = PartySync:DB().controls
	if policy == "anyone" then return true end
	if policy == "leader" then return Peers:AmLeader() end
	return false
end

--- Why this client's Stop, Replay or Skip stays here, or nil when it goes to the party; false
--- when there is no party to tell, which is not worth a line in the log.
function Sync:WhyKept()
	if not self:Live() then
		return next(PartySync:DB().members) ~= nil and "nobody in the party online" or false
	end
	local policy = PartySync:DB().controls
	if policy == "anyone" then return nil end
	if policy == "leader" then
		if Peers:AmLeader() then return nil end
		return format("the controls are the leader's, %s's", tostring(Peers:Leader()))
	end
	return "the controls are not shared"
end

--- Why `sender`'s do nothing here, or nil when they do.
function Sync:WhyRefused(sender)
	if not Peers:IsMember(sender) then return "not in the party" end
	local policy = PartySync:DB().controls
	if policy == "anyone" then return nil end
	if policy == "leader" then
		local leader = Peers:Leader()
		if leader == PartySync:NameKey(sender) then return nil end
		return format("the controls are the leader's, %s's", tostring(leader))
	end
	return "the controls are not shared here"
end

--- Whether `sender`'s do here.
function Sync:AcceptsControl(sender)
	return self:WhyRefused(sender) == nil
end

local function Remotely(fn)
	applyingRemote = true
	local ok, err = pcall(fn)
	applyingRemote = false
	if not ok then PartySync:Print("|cffff6060%s|r", tostring(err)) end
end

-- Each control received says in the log who sent it, what it did here, or why it did nothing.
Comm:On("SK", function(sender, channel, id)
	local key = PartySync:NameKey(sender)
	local entry = id and Sync.lines[id]
	-- A line's own driver ends it whatever the controls: its copy there never played.
	local own = entry and entry.role == "follower" and entry.driver == key
	local why = not own and Sync:WhyRefused(sender)
	if why then
		Trace("skip %s from %s ignored: %s", tostring(id), tostring(key), why)
		return
	end
	local clip = entry and entry.clip
	if clip and clip.source and InQueue(clip) then
		Trace("skip from %s: removing %s (%s, %s)", key, id, tostring(LabelOf(entry)), tostring(entry.state))
		Remotely(function() clip.source:Remove(clip) end)
	elseif entry then
		Trace("skip from %s: %s is not queued here (%s)", key, tostring(id), tostring(entry.state))
	else
		Trace("skip from %s: %s is not here", tostring(key), tostring(id))
	end
end)

Comm:On("PZ", function(sender)
	local key = PartySync:NameKey(sender)
	local why = Sync:WhyRefused(sender)
	if why then
		Trace("stop from %s ignored: %s", tostring(key), why)
	elseif Spoken():IsPaused() then
		Trace("stop from %s: already stopped here", key)
	else
		Trace("stop from %s: stopping %s", key, Describe(Head()))
		Remotely(function() Spoken():Pause() end)
	end
end)

Comm:On("RS", function(sender)
	local key = PartySync:NameKey(sender)
	local why = Sync:WhyRefused(sender)
	if why then
		Trace("replay from %s ignored: %s", tostring(key), why)
	elseif not Spoken():IsPaused() then
		Trace("replay from %s: not stopped here", key)
	else
		Trace("replay from %s: replaying %s", key, Describe(Head()))
		Remotely(function() Spoken():Resume() end)
	end
end)

--------------------------------------------------------------------------------
-- The player's callbacks
--------------------------------------------------------------------------------

local function OnStarted(clip)
	local entry = clip.partySync
	if not entry then return end
	entry.state = "playing"
	entry.startedAt = GetTime()
	Trace("playing %s (%s, %s), %s", entry.id, tostring(LabelOf(entry)), entry.role,
		entry.goAt and format("%+d ms from the planned start", (GetTime() - entry.goAt) * 1000) or "no planned start")
	if entry.role == "follower" then
		Sync.recent[entry.id] = GetTime()
		local late = entry.goAt and math.max(0, (GetTime() - entry.goAt) * 1000) or nil
		Ack(entry, "started", late)
	end
	PartySync:Changed()
end

local function OnStopped(clip, finished)
	local entry = clip.partySync
	if not entry then return end
	if finished then
		Ended(entry, "finished")
		Ack(entry, "finished")
	else
		-- Stopped and kept -- a gate closed on it, or Play was pressed on another line -- it
		-- plays again from the start later. Only a line that left the queue was skipped.
		if InQueue(clip) then return end
		Ended(entry, "stopped")
		Ack(entry, "dropped")
		if not applyingRemote then
			local kept = Sync:WhyKept()
			if kept == nil then
				Trace("skip %s (%s) here: told %s", entry.id, tostring(LabelOf(entry)), table.concat(Peers:OnlineMembers(), ", "))
				SendAll("SK", entry.id)
			elseif kept then
				Trace("skip %s (%s) here: kept here, %s", entry.id, tostring(LabelOf(entry)), kept)
			end
		end
	end
	PartySync:Changed()
end

local function OnDropped(clip, reason)
	local entry = clip.partySync
	if not entry then return end
	Ended(entry, "dropped")
	if entry.role == "follower" then
		Ack(entry, "dropped")
	elseif not applyingRemote and Sync:Live() then
		-- The driver's own copy never played. A file this client refused may well play
		-- elsewhere, so the others start; anything else -- trimmed, outranked -- ends the line.
		Trace("dropped %s here (%s): told %s to %s", entry.id, tostring(reason), table.concat(Peers:OnlineMembers(), ", "),
			reason == "missing" and "start without it" or "skip it")
		if reason == "missing" then SendAll("GO", entry.id, 0) else SendAll("SK", entry.id) end
	end
	PartySync:Changed()
end

local function OnAudioChanged()
	local paused = Spoken():IsPaused()
	if lastPaused ~= nil and paused ~= lastPaused and not applyingRemote then
		local kept = Sync:WhyKept()
		local what = paused and "stop" or "replay"
		if kept == nil then
			Trace("%s here (%s): told %s", what, Describe(Head()), table.concat(Peers:OnlineMembers(), ", "))
			SendAll(paused and "PZ" or "RS")
		elseif kept then
			Trace("%s here (%s): kept here, %s", what, Describe(Head()), kept)
		end
	end
	lastPaused = paused
	Sync:Tick()
	PartySync:Changed()
end

--------------------------------------------------------------------------------
-- Joining the player
--------------------------------------------------------------------------------

-- A local line the party has just played together, or is about to, is refused at the door.
-- Wrapped around whatever admit the source had, which still has the last word.
local function Wrap(key, source)
	if not source or source.partySyncWrapped then return end
	source.partySyncWrapped = true
	local previous = source.admit
	source.admit = function(clip, queue)
		if not clip.partySync then
			local id = Lines:IdFor(key, clip.key)
			if Sync:PlayedTogether(id) then
				Trace("refused %s from this client: just played together", tostring(id))
				return false, L.ADMIT_PLAYED_TOGETHER
			end
			local questID = key == "quests" and tonumber(clip.event) == 1 and tonumber(clip.questID)
			local until_ = questID and Sync.expected[questID]
			if until_ and GetTime() <= until_ then
				Sync.expected[questID] = nil
				Trace("refused quest %d's accept line: the shared quest's line was just played", questID)
				return false, L.ADMIT_PLAYED_TOGETHER
			end
		end
		if previous then
			return previous(clip, queue)
		end
		return true
	end
end

function Sync:Setup()
	if self.ready then
		return true
	end
	if not PartySync:PlayerAvailable() then
		return false
	end
	local S = Spoken()
	S:AddGate(function(clip)
		local ok, reason = pcall(Gate, clip)
		return ok and reason or nil
	end)
	for key, source in S:IterateSources() do
		Wrap(key, source)
	end
	S:RegisterCallback("SOURCE_REGISTERED", function(source) Wrap(source.key, source) end)
	S:RegisterCallback("CLIP_QUEUED", OnQueued)
	S:RegisterCallback("CLIP_STARTED", OnStarted)
	S:RegisterCallback("CLIP_STOPPED", OnStopped)
	S:RegisterCallback("CLIP_DROPPED", OnDropped)
	S:RegisterCallback("AUDIO_CHANGED", OnAudioChanged)
	lastPaused = S:IsPaused()
	self.ready = true
	return true
end

--- `/sps test <questID>`: a quest's accept line queued here as if its giver had been spoken
--- to, so the sync can be tried without one.
function Sync:TestLine(questID)
	local S = Spoken()
	local source = S and S.GetSource and S:GetSource("quests")
	if not (source and source.rebuild) then
		PartySync:Print("Spoken Quests is missing, or too old to rebuild a line")
		return
	end
	local clip = source.rebuild({ key = format("%d-accept", questID), event = 1, questID = questID })
	if not clip then
		PartySync:Print("no voice pack here has quest %d's accept line", questID)
		return
	end
	local added, reason = source:Enqueue(clip)
	PartySync:Print("quest %d: %s", questID, added and "queued" or ("not queued: " .. tostring(reason)))
end
