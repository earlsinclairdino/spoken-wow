-- What the zones addon sends for a place it has no lore for. Run with `make test-player`.
--
-- No text: zone lore is wiki-sourced, so the client has nothing to give and this envelope is a
-- vote that the gap exists, carrying enough to find the place again.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local ZONES = here .. "/../../addons/SpokenZones/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
local env = stub.LoadSpoken(SPOKEN)

-- The addon's own .toc Version, deliberately unlike "dev" so the assertion below cannot pass
-- by coincidence -- it is pinning that CaptureContribution reads a real version, not
-- confirming a particular one. See addons/SpokenQuests/Contribute.lua's Contribute:Capture
-- for the same pattern; SpokenZones.VERSION does not exist, only the lowercase
-- SpokenZones.version Core.lua already computes from the .toc.
stub.SetAddOns({ { folder = "SpokenZones", meta = { Version = "9.9.9" } } })

local Z = H.LoadZones(ZONES)   -- the loader that loads Core.lua for real, unlike stub.LoadZones

stub.SetZone({ map = 1537, zone = "Ironforge", subzone = "A Nook With No Lore", x = 0.55, y = 0.47 })

Expect("a place with no lore is a gap", Z:HasContributionGap(), true)
local envelope = Z:CaptureContribution()
Expect("the source is zones", envelope:match("^!SPOKEN1 zones\n") ~= nil, true)
Expect("the map is carried", envelope:match("\nmap=1537\n") ~= nil, true)
Expect("the zone is carried", envelope:match("\nzone=Ironforge\n") ~= nil, true)
Expect("the subzone is carried", envelope:match("\nsubzone=A Nook With No Lore\n") ~= nil, true)
Expect("the position is carried", envelope:match("\nx=0%.55\n") ~= nil, true)
Expect("there is no text block", envelope:match("text<<") == nil, true)
Expect("the addon field carries the real .toc version, not the \"dev\" fallback",
    envelope:match("\naddon=SpokenZones/9%.9%.9\n") ~= nil, true)

-- Off any map C_Map.GetPlayerMapPosition can place the player on -- an indoor area, an
-- instance, or just a client generation that cannot answer -- PlayerPosition returns nil, nil,
-- and the field is left out of the envelope entirely rather than sent as x=. An empty value is
-- a field the site's reader has to have an opinion about; an absent key is not.
stub.SetZone({ map = 1539, zone = "Somewhere Unplaceable" })
local noPosition = Z:CaptureContribution()
Expect("no position is carried as an omitted field, not an empty one",
    noPosition:match("\nx=\n") == nil, true)
Expect("...neither key is sent", noPosition:match("\nx=") == nil and noPosition:match("\ny=") == nil, true)
Expect("...the rest of the envelope is still sent", noPosition:match("\nmap=1539\n") ~= nil, true)

-- A place that does have lore is not a gap. A fresh map with no subzone, so this does not
-- also exercise ResolveAreaKey's alias table -- Language.lua populates that, and this loader
-- deliberately does not load it (Contribute.lua never reads an alias, only a plain zone key).
stub.SetZone({ map = 1538, zone = "Somewhere Else" })
Z.Zones[1538] = { full = "There is lore here." }
Expect("a place with lore is not a gap", Z:HasContributionGap(), false)

------------------------------------------------------------------------------- Show()
-- Compression must run on the click alone -- Autoplay and the lore window ask the gap question
-- on nearly every zone change, and this spies on Encode rather than trusting the comment, so a
-- future edit that moved the call earlier would fail here rather than merely cost more.
stub.SetZone({ map = 1537, zone = "Ironforge", subzone = "A Nook With No Lore", x = 0.55, y = 0.47 })
local encodeCalls = 0
local realEncode = env.Spoken.Contribute.Encode
env.Spoken.Contribute.Encode = function(...)
    encodeCalls = encodeCalls + 1
    return realEncode(...)
end
Z:HasContributionGap()
Z:CaptureContribution()
Expect("HasContributionGap/CaptureContribution never encode", encodeCalls, 0)

Z:ShowContribution()
Expect("...only Show() does", encodeCalls, 1)
local box = env.Spoken.ContributeBox
Expect("Show() puts a link in the box, not the raw envelope",
    box.editBox:GetText():match("^https://spoken%.rusty%.one/contribute#e1=") ~= nil, true)
Expect("...with the link hint", box.hint:GetText(), "Copy this and open it in your browser:")
env.Spoken.Contribute.Encode = realEncode

-- The fallback an older bundled SpokenPlayer still gets: no Encode at all.
env.Spoken.Contribute.Encode = nil
Z:ShowContribution()
Expect("...falls back to the raw envelope when Encode is absent",
    box.editBox:GetText():match("^!SPOKEN1 zones\n") ~= nil, true)
Expect("...with the old two-copy hint", box.hint:GetText(), "Press Ctrl+C, then paste it at:")
Expect("...and the address shown again", box.address:GetText(), "https://spoken.rusty.one/contribute")
env.Spoken.Contribute.Encode = realEncode

os.exit(Failures() == 0 and 0 or 1)
