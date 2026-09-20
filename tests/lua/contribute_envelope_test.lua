-- The envelope a contribution travels in. Run with `make test-player`.
--
-- The reader is in TypeScript (apps/web/src/lib/contributions/envelope.ts) and the two must
-- agree exactly, which is why this file also writes the fixtures that one is tested against.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
local env = stub.LoadSpoken(SPOKEN)
local C = env.Spoken.Contribute

local fields = { { "addon", "SpokenQuests/1.4.2" }, { "locale", "enUS" }, { "quest", "9123" } }

local written = C:Envelope("quests", fields, "First line.\nSecond line.")

Expect("the first line names the version and the source",
    written:match("^!SPOKEN1 quests\n") ~= nil, true)
Expect("a field is one key=value line", written:match("\nquest=9123\n") ~= nil, true)
Expect("the text is fenced", written:match("\ntext<<\nFirst line%.\nSecond line%.\n>>\n") ~= nil, true)
Expect("the checksum closes it", written:match("\nsum=%d+\n$") ~= nil, true)

-- The checksum covers everything before its own line, so a tampered byte is visible.
local body, sum = written:match("^(.*\n)sum=(%d+)\n$")
Expect("the checksum is the checksum of the body", C:Checksum(body), tonumber(sum))

local tampered = body:gsub("9123", "9124")
Expect("...and does not match a changed body", C:Checksum(tampered) ~= tonumber(sum), true)

-- A page whose own words are ">>" would otherwise end the block early.
local fenced = C:Envelope("books", { { "page", "1" } }, "before\n>>\nafter")
Expect("a >> line in the text is escaped", fenced:match("\n\\>>\n") ~= nil, true)
Expect("...and the real fence still closes the block", fenced:match("\nafter\n>>\nsum=") ~= nil, true)

local none = C:Envelope("zones", { { "map", "1537" } }, nil)
Expect("an envelope with no text has no fence", none:match("text<<") == nil, true)

Expect("an unknown source is refused", C:Envelope("mail", { { "page", "1" } }, "x"), nil)
Expect("a field value never spans lines",
    C:Envelope("quests", { { "title", "A\nB" } }, nil):match("\ntitle=A B\n") ~= nil, true)

os.exit(Failures() == 0 and 0 or 1)
