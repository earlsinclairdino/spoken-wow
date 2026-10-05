-- A line as one client describes it and another rebuilds it.
--
-- The description is what each module put on its own clip -- a quest line's event, quest and
-- speaker, a zone's map and area, a book's page -- and the clip's key, which is the line id
-- the whole project freezes (`q:33:accept`'s file `33-accept`, `g:{md5}`, `z:{mapID}`,
-- `s:{mapID}:{key}`, `b:{pageTextID}`). The receiving client hands it to the same module's
-- `rebuild` (Spoken:RegisterSource), which resolves the file through its own packs and
-- languages and presents it as a local line. Nothing here knows how a module finds a file.
--
-- LN  id, src, event, questID, npcID, length, flags, textParts, name, title
--     src is q, z or b; flags has l for a gossip line (which yields to quest lines); textParts
--     is how many TX pieces of caption follow, 0 when the receiver has its own text.

local _, PartySync = ...

local Comm = PartySync.Comm

local Lines = {}
PartySync.Lines = Lines

local CODES = { quests = "q", zones = "z", books = "b" }
local SOURCES = { q = "quests", z = "zones", b = "books" }

-- Spoken_Quests' Enums.SoundEvent, which is private to it. Frozen: its sound packs' Module.lua
-- branch on the same numbers.
local EVENT = { accept = 1, progress = 2, complete = 3, greeting = 4, gossip = 5, followup = 6 }
local BULLETS = { [1] = "quest-accept", [2] = "quest-progress", [3] = "quest-complete", [4] = "gossip",
	[5] = "gossip", [6] = "quest-complete" }

local SILENCE = [[Interface\AddOns\Spoken\Sounds\silence.wav]]

function Lines:SourceKey(clip)
	return clip and clip.source and clip.source.key or nil
end

--- Which setting decides whether this line is played together: "quests", "gossip", "zones",
--- "books", or nil for a source this addon does not know.
function Lines:Kind(clip)
	local src = self:SourceKey(clip)
	if src == "quests" then
		local event = tonumber(clip.event)
		return (event == EVENT.greeting or event == EVENT.gossip) and "gossip" or "quests"
	end
	if src == "zones" or src == "books" then
		return src
	end
	return nil
end

--- The line's id: its key, without the player-gender prefix a quest line's file may carry --
--- Tata's `m-33-accept` and Lala's `f-33-accept` are one line read to two players.
function Lines:Id(clip)
	return self:IdFor(self:SourceKey(clip), clip and clip.key)
end

--- The same, for a clip not yet admitted: the player only sets `clip.source` once it is.
function Lines:IdFor(sourceKey, key)
	if type(key) ~= "string" then
		return nil
	end
	if sourceKey == "quests" then
		key = key:gsub("^[mf]%-", "")
	end
	return key
end

local function CreatureID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(id)
	end
	return nil
end

--- What another client needs to play `clip`, or nil for a source it could not rebuild.
function Lines:Describe(clip)
	local src = self:SourceKey(clip)
	if not CODES[src] then
		return nil
	end
	local present = clip.present or {}
	local d = {
		id = self:Id(clip),
		src = src,
		length = tonumber(clip.length),
		low = clip.priority == "low",
		name = present.header,
		title = present.label,
	}
	if src == "quests" then
		d.event = tonumber(clip.event)
		d.questID = tonumber(clip.questID)
		d.npcID = CreatureID(clip.unitGUID)
		d.name = clip.name or d.name
		d.title = clip.title or d.title
		-- A quest line's words are on the dialog that was open here, and on nobody else's
		-- screen: a class quest, a turn-in the others have not reached. Zones and books carry
		-- their own text in every client's data.
		d.text = clip.text
	end
	return d
end

local function Cut(text, bytes)
	if #text <= bytes then return text end
	text = text:sub(1, bytes)
	-- Never end on half a UTF-8 character, or half an escape.
	text = text:gsub("[\128-\255]+$", "")
	return (text:gsub("\\$", ""))
end

--- The LN fields for `d`, with `textParts` caption pieces to follow. Names are cut to fit the
--- 255 bytes a message may have.
function Lines:Encode(d, textParts)
	local flags = d.low and "l" or ""
	local fields = { d.id, CODES[d.src], d.event or "", d.questID or "", d.npcID or "",
		d.length and format("%.2f", d.length) or "", flags, textParts or 0 }
	local used = #"LN"
	for _, field in ipairs(fields) do used = used + 1 + #tostring(field) end
	local room = Comm.MAX_LENGTH - used - 2
	local name = Cut(Comm.Escape(d.name or ""), math.max(0, math.min(60, room)))
	local title = Cut(Comm.Escape(d.title or ""), math.max(0, room - #name))
	table.insert(fields, name)
	table.insert(fields, title)
	return fields
end

--- An LN message's fields, back as a description. Nil when they make no sense.
function Lines:Decode(id, src, event, questID, npcID, length, flags, textParts, name, title)
	local source = SOURCES[src or ""]
	if not (id and id ~= "" and source) then
		return nil
	end
	return {
		id = id,
		src = source,
		event = tonumber(event),
		questID = tonumber(questID),
		npcID = tonumber(npcID),
		length = tonumber(length),
		low = (flags or ""):find("l", 1, true) ~= nil,
		textParts = tonumber(textParts) or 0,
		name = Comm.Unescape(name or ""),
		title = Comm.Unescape(title or ""),
	}
end

--- Which setting decides a described line, as Kind does for a clip.
function Lines:DescribedKind(d)
	if d.src == "quests" then
		return (d.event == EVENT.greeting or d.event == EVENT.gossip) and "gossip" or "quests"
	end
	return d.src
end

-- A quest line this client has no file for, when the words came with it: the player opens,
-- the captions run for the line's length, and the silence is the player's own. Better than
-- nothing at all while the others hear it.
local function StandIn(d)
	local text = d.text or ""
	return {
		key = d.id,
		path = SILENCE,
		length = d.length or math.max(3, #text / 15),
		priority = d.low and "low" or "normal",
		event = d.event,
		questID = d.questID,
		name = d.name,
		title = d.title,
		text = text,
		present = {
			header = d.name or "",
			label = d.title or "",
			bullet = BULLETS[d.event or 0],
			tint = d.low and { 1, 1, 1 } or nil,
			portrait = d.npcID and { kind = "model", creatureID = d.npcID, animation = 60 } or { kind = "none" },
		},
	}
end

--- The clip for a described line on this client, and why not when there is none:
--- "no-source" (the module is not installed or switched off), "old" (it predates rebuild),
--- "missing" (no pack here has the line). A quest line with words but no file comes back as a
--- silent stand-in, with "missing" as its reason.
function Lines:Rebuild(d)
	local Spoken = _G.Spoken
	local source = Spoken and Spoken.GetSource and Spoken:GetSource(d.src)
	if not source then
		return nil, "no-source"
	end
	if not source.rebuild then
		return nil, "old"
	end
	local ok, clip = pcall(source.rebuild, {
		key = d.id, event = d.event, questID = d.questID, npcID = d.npcID,
		name = d.name, title = d.title, text = d.text,
	})
	if ok and type(clip) == "table" then
		return clip, nil, source
	end
	if d.src == "quests" and d.text and d.text ~= "" then
		return StandIn(d), "missing", source
	end
	return nil, "missing"
end

--- The captions of a line already speaking read its words again, keeping their place in time.
--- The player has no public call for this: it reads a line's words once, as it starts. Through
--- its environment, guarded, for the late case only (Sync waits for the words first).
function Lines:RefreshCaption(clip)
	local env = rawget(_G, "SpokenEnv")
	local transcript = env and rawget(env, "Transcript")
	if not (transcript and transcript.clip == clip and transcript.SetClip) then
		return false
	end
	local ok = pcall(function()
		local startedAt, elapsed, started = transcript.startedAt, transcript.elapsed, transcript.hasStarted
		transcript:SetClip(clip)
		transcript.startedAt, transcript.elapsed, transcript.hasStarted = startedAt, elapsed, started
		if transcript.Update then transcript:Update() end
	end)
	return ok
end

--- Words that arrived after the clip was built: a quest line's captions are the dialog's, not
--- whatever this client found in its own quest log.
function Lines:SetText(clip, text)
	if not (clip and text and text ~= "") then
		return
	end
	if clip.present and clip.present.transcript then
		return
	end
	clip.text = text
end
