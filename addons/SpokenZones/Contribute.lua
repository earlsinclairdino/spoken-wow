-- A place this addon has no lore for, as something that can be reported with coordinates.
--
-- No text, unlike the quests and books envelopes: zone lore is wiki-sourced rather than
-- client-sourced, so the client has nothing to hand over. What this sends is enough to find
-- the place again -- the map, the zone, the subzone and where the player was standing -- and
-- the count on the far side is what makes it a priority rather than a note.
--
-- It travels the same format for one reason: one triage queue for three addons.

local ADDON_NAME, SpokenZones = ...

-- The merged domain, not SpokenZones.SITE_URL ("https://lore.rusty.one", ReportButton.lua's
-- own report domain): the contribute page is new and exists only on the site all three
-- sections share. Kept as a local of its own for the reason SpokenQuests/Contribute.lua gives
-- for the same split -- a report link that moved would be a report link that breaks for
-- everyone still running the shipped addon.
local SITE_URL = "https://spoken.rusty.one"

-- The player's normalised position on their own current map, or nil, nil off it. Nothing in
-- this addon already asks this -- Audio.lua and Autoplay.lua only ever need which map the
-- player is on, never where on it -- so this is the one genuinely new lookup here, not a
-- second copy of an existing one.
local function PlayerPosition(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then
        return nil, nil
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        return nil, nil
    end
    return pos:GetXY()
end

--- The envelope for the place the player is standing in, or nil off any map.
function SpokenZones:CaptureContribution()
    local map = self:GetPlayerMapID()
    if not map then
        return nil
    end

    local x, y = PlayerPosition(map)
    local fields =
    {
        -- SpokenZones.VERSION does not exist -- Core.lua computes the real .toc version into
        -- the lowercase SpokenZones.version, the same GetAddOnMetadata read DataModules-style
        -- lookups elsewhere in this project use; "dev" is what a source checkout with no .toc
        -- metadata at all reads back as.
        { "addon", format("SpokenZones/%s", self.version or "dev") },
        { "build", format("%s/%s", (GetBuildInfo and select(1, GetBuildInfo())) or "?",
                                   (GetBuildInfo and select(2, GetBuildInfo())) or "?") },
        { "locale", (GetLocale and GetLocale()) or "enUS" },
        { "map", map },
        { "zone", (GetRealZoneText and GetRealZoneText()) or "" },
        { "subzone", (GetSubZoneText and GetSubZoneText()) or "" },
    }

    -- Omitted, not sent empty, when GetPlayerMapPosition has nothing -- an indoor map, an
    -- instance, a map this client generation cannot place the player on. `x=` is a field the
    -- site's reader would have to have an opinion about (empty string? zero? malformed?); a
    -- key that is simply not there is a question it never has to ask. Matches how the quests
    -- envelope already drops its own optional "quest" field rather than sending it blank --
    -- see SpokenQuests/Contribute.lua's Capture.
    if x and y then
        fields[#fields + 1] = { "x", format("%.2f", x) }
        fields[#fields + 1] = { "y", format("%.2f", y) }
    end

    return Spoken.Contribute:Envelope("zones", fields, nil)
end

--- The lore entry for where the player is standing, or nil for a genuine gap. Resolves the
--- same way UI/LoreWindow.lua's CurrentZoneID and Autoplay.lua's NarrateUnheard already do --
--- GetPlayerMapID walked up through GetLoreWithFallback to a mapID this corpus actually keys
--- entries by, subzone lore preferred over the zone's when the player is standing in one --
--- rather than a second lookup path of its own.
function SpokenZones:LoreForCurrentPlace()
    local _, mapID = self:GetLoreWithFallback(self:GetPlayerMapID())
    if not mapID then
        return nil
    end

    local subZone = GetSubZoneText and GetSubZoneText() or ""
    if subZone ~= "" then
        local entry = self:GetSubzoneLore(mapID, subZone)
        if entry and not self:IsPending(entry) then
            return entry
        end
    end

    local entry = self:GetLore(mapID)
    if entry and not self:IsPending(entry) then
        return entry
    end
    return nil
end

--- Whether the contribute button belongs on screen: nowhere with lore, and somewhere to send.
function SpokenZones:HasContributionGap()
    if not (_G.Spoken and Spoken.Contribute and Spoken.ShowContribution) then
        return false
    end
    if self:LoreForCurrentPlace() then
        return false
    end
    return self:CaptureContribution() ~= nil
end

-- Compression belongs here, not in CaptureContribution or HasContributionGap: Autoplay and the
-- lore window ask the gap question far more often than a player ever presses the button, and
-- paying deflate's cost there would be work spent on every place walked through, not just the
-- ones actually reported. This runs once, on the click.
function SpokenZones:ShowContribution()
    local envelope = self:CaptureContribution()
    if not envelope then
        return
    end
    local address = format("%s/contribute", SITE_URL)
    -- Encode is absent on an older SpokenPlayer a legacy-client zip can still bundle; Link
    -- returns nil for that or for an oversized result, and the two-copy fallback still works.
    local link = Spoken.Contribute.Encode and Spoken.Contribute:Link(address, envelope)
    if link then
        Spoken:ShowContribution(link, address, true)
    else
        Spoken:ShowContribution(envelope, address)
    end
end
