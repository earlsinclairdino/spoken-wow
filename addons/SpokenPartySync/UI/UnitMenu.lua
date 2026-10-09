-- "Invite to Spoken Party" on a player's right-click menu: their portrait in the party frames,
-- the target and focus frames, a raid member, a friend.
--
-- Through the menu system the game has used since 11.0 (Menu.ModifyMenu), which Forever's
-- Mainline interface has. A client without it has no entry; /sps invite and the settings page
-- do the same.

local _, PartySync = ...

local Peers, Autoform, L = PartySync.Peers, PartySync.Autoform, PartySync.L

local UnitMenu = {}
PartySync.UnitMenu = UnitMenu

-- The menus a player's unit can be right-clicked in. One the client does not tag is skipped.
local TAGS = { "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_PLAYER", "MENU_UNIT_TARGET",
	"MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND", "MENU_UNIT_RAID" }

UnitMenu.hooked = {}

--- The whole name of whoever the menu is for, or nil when it is not another player.
local function NameFor(contextData)
	if type(contextData) ~= "table" then
		return nil
	end
	local unit = contextData.unit
	if unit and UnitExists(unit) then
		if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
			return nil
		end
		return PartySync:UnitChatName(unit)
	end
	-- A friend or a chat name: no unit, a name and perhaps a realm.
	local name = contextData.name
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if contextData.server and contextData.server ~= "" then
		name = name .. "-" .. contextData.server
	end
	if PartySync:IsSelf(name) then
		return nil
	end
	return name
end

local function Modify(_, rootDescription, contextData)
	local name = NameFor(contextData)
	if not name then
		return
	end
	rootDescription:CreateDivider()
	if rootDescription.CreateTitle then
		rootDescription:CreateTitle(L.MENU_TITLE)
	end
	local key = PartySync:NameKey(name)
	if Peers:IsMember(name) then
		-- The leader's: the lead, the sound and the roster. Offered unless it is already so.
		if Peers:AmLeader() then
			if not Peers:IsLeader(key) then
				rootDescription:CreateButton(L.MENU_LEAD, function() Peers:PassLead(key) end)
			end
			if PartySync.Room and PartySync.Room:Speaker() ~= key then
				rootDescription:CreateButton(L.MENU_SOUND, function() PartySync.Room:Choose(key) end)
			end
			rootDescription:CreateButton(L.MENU_REMOVE, function()
				if Peers:RemoveMember(name) then
					PartySync:Print("%s is out of your Spoken party", PartySync:ShortName(name))
				end
			end)
		end
	elseif Peers:MayInvite() then
		rootDescription:CreateButton(L.MENU_INVITE, function()
			local sent, answer = Peers:Invite(name)
			PartySync:Print("invitation to %s: %s", PartySync:ShortName(name), sent and "sent" or tostring(answer))
		end)
	end
	if not Autoform:Entry(key) then
		rootDescription:CreateButton(L.MENU_REMEMBER, function()
			if Autoform:Add(name) then
				PartySync:Print("%s is in your usual party", PartySync:ShortName(name))
			end
		end)
	end
end

function UnitMenu:Setup()
	if self.ready or not (Menu and Menu.ModifyMenu) then
		return
	end
	self.ready = true
	for _, tag in ipairs(TAGS) do
		if pcall(Menu.ModifyMenu, tag, function(...)
			local ok, err = pcall(Modify, ...)
			if not ok then PartySync:Log("menu: %s", tostring(err)) end
		end) then
			table.insert(self.hooked, tag)
		end
	end
end
