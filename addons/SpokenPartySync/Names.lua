-- Names: who is who, and how to address a whisper.
--
-- Forever has no realms: names are "First Last", unique in the whole region, and chat shows
-- them without a suffix. An addon whisper to "Tata Throwaway-ClassicBetaPvE2" was answered
-- "No player named..." while that player stood in the same party (2026-10-05); the bare
-- "Tata Throwaway" and "Tata-Throwaway" both arrived. So a whisper goes to the bare name
-- whenever the realm is ours, and names are compared in that same form, lower-cased.
-- Elsewhere CHAT_MSG_ADDON names its sender Name-Realm, and that still works.

local _, PartySync = ...

local function Trim(name)
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	-- The command takes the rest of the line, so the quotes a player types out of habit around
	-- a name with a space in it are not part of the name.
	name = name:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
	return name
end

--- Name and realm, split at the last hyphen; the realm is nil when there is none.
local function SplitRealm(name)
	local short, realm = name:match("^(.-)%-([^%-]+)$")
	if short and short ~= "" then
		return short, realm
	end
	return name, nil
end

-- Realms are written with spaces by GetRealmName and without by GetNormalizedRealmName and
-- in senders; compared without, either way round.
local function SameRealm(realm)
	local own = GetNormalizedRealmName and GetNormalizedRealmName()
	if not realm or not own then
		return true
	end
	return realm:gsub("%s", ""):lower() == own:gsub("%s", ""):lower()
end

--- The form a whisper is addressed to: the bare name on our realm, Name-Realm elsewhere.
function PartySync:WhisperName(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local short, realm = SplitRealm(Trim(name))
	if short == "" then
		return nil
	end
	if realm and not SameRealm(realm) then
		return short .. "-" .. realm
	end
	return short
end

--- The form names are compared and stored in.
function PartySync:NameKey(name)
	local target = self:WhisperName(name)
	return target and target:lower() or nil
end

function PartySync:ShortName(name)
	return self:WhisperName(name) or "?"
end

--- "Lala" for "Lala Throwaway", where a whole name would not fit.
function PartySync:FirstName(name)
	local short = self:ShortName(name)
	return short:match("^(%S+)") or short
end

--- The whole name the client uses for `unit` in chat: "First Last" on Forever, "Name" or
--- "Name-Realm" elsewhere.
---
--- Forever's two-part names come back from the tuple APIs the way a realm does on Retail:
--- UnitName and UnitFullName return the first name, then the surname. So the first value
--- alone is half a name, and appending GetNormalizedRealmName -- which on the beta still
--- answers a backend realm, "ClassicBetaPvE2" -- builds an address nobody has.
function PartySync:UnitChatName(unit)
	local whole = GetUnitName and GetUnitName(unit, true)
	-- The Midnight engine hands addons some unit facts as secret values in restricted places;
	-- one cannot be compared or cut, so it counts as no name.
	if whole ~= nil and issecretvalue and issecretvalue(whole) then
		return nil
	end
	if whole and whole ~= "" then
		return whole
	end
	local first = UnitName(unit)
	if first ~= nil and issecretvalue and issecretvalue(first) then
		return nil
	end
	return first
end

function PartySync:MyKey()
	return self:NameKey(self:UnitChatName("player"))
end

function PartySync:IsSelf(name)
	local key = self:NameKey(name)
	if not key then
		return false
	end
	local first, second = UnitName("player")
	-- Every way this client might write its own name, since which of them a sender name or a
	-- typed member matches depends on the client. On Retail the joined form is "Name Realm",
	-- which no sender is called, so it costs nothing there.
	local own = { first, self:UnitChatName("player"),
		second and second ~= "" and (first .. " " .. second) or nil }
	for _, candidate in pairs(own) do
		if key == self:NameKey(candidate) then
			return true
		end
	end
	return false
end

--- Every way of writing `name` a whisper might be addressed to, for `/sps probe`. The client's
--- own spelling is included when the player is in the group, since that is the form it
--- resolves for its own chat.
function PartySync:NameForms(name)
	local forms, seen = {}, {}
	local function Add(form)
		if form and form ~= "" and not seen[form:lower()] then
			seen[form:lower()] = true
			table.insert(forms, form)
		end
	end
	local typed = Trim(name or "")
	local short = SplitRealm(typed)
	Add(typed)
	Add(short)
	local normalized = GetNormalizedRealmName and GetNormalizedRealmName()
	local raw = GetRealmName and GetRealmName()
	Add(normalized and (short .. "-" .. normalized))
	Add(raw and (short .. "-" .. raw))
	for _, unit in ipairs(self:GroupUnits()) do
		local whole = self:UnitChatName(unit)
		if whole and self:NameKey(whole) == self:NameKey(short) then
			Add(whole)
			-- The tuple joined with a hyphen: the Retail address shape, with the surname where
			-- the realm would be.
			if UnitFullName then
				local n, r = UnitFullName(unit)
				Add(n and r and r ~= "" and (n .. "-" .. r) or nil)
			end
		end
	end
	Add((short:gsub("%s", "")))
	return forms
end

--- The unit tokens of everyone else in the group.
function PartySync:GroupUnits()
	local units = {}
	if IsInRaid and IsInRaid() then
		for i = 1, 40 do
			local unit = "raid" .. i
			if UnitExists(unit) and not UnitIsUnit(unit, "player") then table.insert(units, unit) end
		end
	else
		for i = 1, 4 do
			local unit = "party" .. i
			if UnitExists(unit) then table.insert(units, unit) end
		end
	end
	return units
end

--- The group unit `name` is, or nil when they are not in the group.
function PartySync:UnitFor(name)
	local key = self:NameKey(name)
	if not key then return nil end
	for _, unit in ipairs(self:GroupUnits()) do
		if self:NameKey(self:UnitChatName(unit)) == key then
			return unit
		end
	end
	return nil
end

--- A typed name as it is stored and shown: trimmed, unquoted, each word capitalised the way
--- the client prints names.
function PartySync:CleanName(name)
	if type(name) ~= "string" then
		return ""
	end
	name = Trim(name):gsub("(%S)(%S*)", function(first, rest) return first:upper() .. rest end)
	return name
end
