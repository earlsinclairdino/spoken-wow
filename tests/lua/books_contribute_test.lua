-- What the books addon offers to send for a page the corpus does not carry.
-- Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local BOOKS = here .. "/../../addons/SpokenBooks/"
local Expect, Failures = H.Expecter(print)

local function LoadBooks()
    local SpokenBooks = {}
    for _, file in ipairs({ "Checksum", "Core", "Reader", "Contribute" }) do
        local chunk = assert(loadfile(BOOKS .. file .. ".lua"))
        chunk("SpokenBooks", SpokenBooks)
    end
    return SpokenBooks
end

stub.SetClient("11509")
local env = stub.LoadSpoken(SPOKEN)
local B = LoadBooks()
B:InitDB()
dofile(BOOKS .. "Data/Books.lua")

local UNKNOWN = "A page no corpus has ever held.\n\nWritten for this test alone."
stub.ShowPage({ title = "Ledger of Nothing", number = 2, text = UNKNOWN })

Expect("an unknown page is a gap", B:HasContributionGap(), true)
local envelope = B:CaptureContribution()
Expect("the source is books", envelope:match("^!SPOKEN1 books\n") ~= nil, true)
Expect("the key is the client-side checksum",
    envelope:match("\npage=" .. B:ChecksumOf(UNKNOWN) .. "\n") ~= nil, true)
Expect("the book title is carried", envelope:match("\nbook=Ledger of Nothing\n") ~= nil, true)
Expect("the page number is carried", envelope:match("\nnumber=2\n") ~= nil, true)
Expect("the text is carried", envelope:match("\nA page no corpus has ever held%.\n") ~= nil, true)

-- A page the corpus already has is not a gap: the complaint there is a report, not a payload.
local REGISTRY_1 = "Hillsbrad Town Registry\n\nWe the people of Hillsbrad do solemny swear our faith and devotion to the Alliance maintained by the great monarchs, King Magni Bronzebeard of Ironforge and King Anduin Wrynn of Stormwind.\n\nHerein lies the town registry for purposes of governing this fair city in the foothills of the great Alterac Mountains as well as serving as a record of those who have paid their taxes to their Kings and to the great almighty Alliance."
stub.ShowPage({ title = "Hillsbrad Town Registry", number = 1, text = REGISTRY_1 })
Expect("a page the corpus carries is not a gap", B:HasContributionGap(), false)

-- Mail is the player's own correspondence and never leaves their client.
stub.ShowPage({ title = "A letter", number = 1, text = UNKNOWN, creator = "Somebody" })
Expect("mail is never contributed", B:CaptureContribution(), nil)
Expect("...and offers no button", B:HasContributionGap(), false)

------------------------------------------------------------------------------- Show()
-- Compression must run on the click alone -- see the perf comment on ShowContribution -- so
-- this spies on Encode rather than merely trusting the comment: an assertion that only reads
-- the source would still pass if a future edit moved the call into CaptureContribution.
stub.ShowPage({ title = "Ledger of Nothing", number = 2, text = UNKNOWN })
local encodeCalls = 0
local realEncode = env.Spoken.Contribute.Encode
env.Spoken.Contribute.Encode = function(...)
    encodeCalls = encodeCalls + 1
    return realEncode(...)
end
B:HasContributionGap()
B:CaptureContribution()
Expect("HasContributionGap/CaptureContribution never encode", encodeCalls, 0)

B:ShowContribution()
Expect("...only Show() does", encodeCalls, 1)
local box = env.Spoken.ContributeBox
Expect("Show() puts a link in the box, not the raw envelope",
    box.editBox:GetText():match("^https://spoken%.rusty%.one/contribute#e1=") ~= nil, true)
Expect("...with the link hint", box.hint:GetText(), "Copy this and open it in your browser:")
env.Spoken.Contribute.Encode = realEncode

-- The fallback an older bundled SpokenPlayer still gets: no Encode at all.
env.Spoken.Contribute.Encode = nil
B:ShowContribution()
Expect("...falls back to the raw envelope when Encode is absent",
    box.editBox:GetText():match("^!SPOKEN1 books\n") ~= nil, true)
Expect("...with the old two-copy hint", box.hint:GetText(), "Press Ctrl+C, then paste it at:")
Expect("...and the address shown again", box.address:GetText(), "https://spoken.rusty.one/contribute")
env.Spoken.Contribute.Encode = realEncode

os.exit(Failures() == 0 and 0 or 1)
