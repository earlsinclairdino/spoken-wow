-- The books addon speaking through the player. Checksum.lua and Core.lua are loaded for
-- real against a hand-built SpokenBooks table; the queue, frame and callbacks are the real
-- Spoken ones. Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/Spoken/"
local BOOKS = here .. "/../../addons/Spoken_Books/"
local Expect, Failures = H.Expecter(print)

local function LoadBooks()
    local SpokenBooks = {}
    for _, file in ipairs({ "Locale/enUS", "Checksum", "Core", "Language" }) do
        local chunk = assert(loadfile(BOOKS .. file .. ".lua"))
        chunk("Spoken_Books", SpokenBooks)
    end
    return SpokenBooks
end

local function Boot()
    stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers()
    _G.SpokenBooksSettings = nil
    local env = stub.LoadSpoken(SPOKEN)
    env.Addon:Enable()
    local B = LoadBooks()
    B:InitDB()
    B:SetupSource()
    return env, B
end

---------------------------------------------------------------- wired up by the client
-- Boot() above calls InitDB and SetupSource by hand, which is how an addon that called
-- neither passed this whole file while being mute in game: no login event reached them, so
-- no source was ever claimed and every page lookup returned 0 against a nil source. This
-- section boots a copy the way the client does -- load the files, then fire the events --
-- and runs first, so it is the only books copy alive while it fires them.
--
-- Its own loader, because LoadBooks above is deliberately the two files this file's other
-- sections need: Events.lua is what creates the frame the events arrive at, and without it
-- firing them reaches nothing and the test passes for the wrong reason.
stub.SetClient("11509"); stub.ResetSound(); stub.ResetTimers()
_G.SpokenBooksSettings = nil
local bootEnv = stub.LoadSpoken(SPOKEN)
bootEnv.Addon:Enable()
local B0 = {}
for _, file in ipairs({ "Locale/enUS", "Checksum", "Core", "Language", "Reader", "Audio", "Playlist", "Events", "Commands" }) do
    assert(loadfile(BOOKS .. file .. ".lua"))("Spoken_Books", B0)
end

stub.FireEvent("ADDON_LOADED", "SomebodyElse")
Expect("another addon's load leaves the saved variables alone", SpokenBooksSettings, nil)

stub.FireEvent("ADDON_LOADED", "Spoken_Books")
Expect("the addon's own ADDON_LOADED writes the defaults", SpokenBooksSettings.autoplay, true)
Expect("...and claims no source yet, because the player may not have loaded", B0.source, nil)

stub.FireEvent("PLAYER_ENTERING_WORLD")
Expect("entering the world claims the source", _G.Spoken:GetSource("books"), B0.source)
local claimed = B0.source
stub.FireEvent("PLAYER_ENTERING_WORLD")
Expect("...and a second loading screen does not replace it", B0.source, claimed)

local env, B = Boot()
local Spoken = _G.Spoken

---------------------------------------------------------------- registration
Expect("the books addon registers a source with the player", Spoken:GetSource("books"), B.source)
-- No cap: a book is a bounded sequence somebody opened, not a burst of discoveries. Capped,
-- the player trims the oldest waiting clip and a four-page book loses its middle.
Expect("...with no queue limit", B.source.queueLimit, nil)
Expect("...with its own gap", B.source.interClipGap, 0.35)
Expect("...and reports itself compatible", B.compatible, true)

-- Another client's page (Spoken Party Sync): the page id is the whole description, carried in
-- the key when nothing else is sent. ClipFor is Audio.lua's, not loaded here; what this checks
-- is that the description reaches it as a number.
local asked = {}
B.ClipFor = function(_, pageId) table.insert(asked, pageId); return { key = "b:" .. pageId } end
Expect("the source offers a rebuild", type(B.source.rebuild), "function")
Expect("a page is rebuilt from its key", B.source.rebuild({ key = "b:4242" }).key, "b:4242")
Expect("...asking for the page as a number", asked[1], 4242)
Expect("...or from its page id", B.source.rebuild({ key = "x", pageId = "77" }).key, "b:77")
Expect("a key that names no page rebuilds nothing", B.source.rebuild({ key = "z:1411" }), nil)
B.ClipFor = nil

---------------------------------------------------------------- saved variables
Expect("autoplay is on by default, because opening a book is already deliberate",
    SpokenBooksSettings.autoplay, true)
Expect("a whole book is read by default", SpokenBooksSettings.readWholeBook, true)

SpokenBooksSettings.autoplay = false
B:InitDB()
Expect("InitDB does not overwrite a choice already made", SpokenBooksSettings.autoplay, false)

---------------------------------------------------------------- the checksum
-- The numbers below come from pipelines/books/tools/lib/naming.mjs, which keys the
-- generated lookup on them. If these two disagree, every page lookup misses and the addon
-- narrates nothing at all -- silently, which is why they are asserted rather than trusted.
Expect("the checksum matches the exporter on ASCII", B:ChecksumOf("The rains have come."), 1482999072)
Expect("the checksum matches the exporter on UTF-8", B:ChecksumOf("Voil\195\160, l'\195\169p\195\169e."), 1603451486)
Expect("the checksum normalises CRLF the way the exporter does",
    B:ChecksumOf("One.\r\n\r\nTwo."), B:ChecksumOf("One.\n\nTwo."))
Expect("...and WoW's $B newline token", B:ChecksumOf("One.$B$BTwo."), B:ChecksumOf("One.\n\nTwo."))
Expect("...and trailing whitespace", B:ChecksumOf("One.   \nTwo."), B:ChecksumOf("One.\nTwo."))
Expect("a non-string is not an error", B:ChecksumOf(nil), 0)

---------------------------------------------------------------- the generated data
dofile(BOOKS .. "Data/Books.lua")
local data = B:Data()
Expect("the lookup loaded", type(data), "table")
Expect("...at the version this addon reads", data.version, 1)
local twilight = data.index["Decoded Twilight Text"]
local variants = 0
for _ in pairs(twilight[1]) do variants = variants + 1 end
Expect("seven books share a title and are told apart by checksum", variants, 7)

---------------------------------------------------------------- a player that is too old
local oldSpoken = _G.Spoken
_G.Spoken = { IsCompatible = function() return false end }
local B2 = LoadBooks()
Expect("an incompatible player leaves the addon loaded but quiet", B2:SetupSource(), nil)
Expect("...and says so", B2.compatible, false)
_G.Spoken = oldSpoken

print(Failures() == 0 and "All books source tests passed" or (Failures() .. " failed"))
os.exit(Failures() == 0 and 0 or 1)
