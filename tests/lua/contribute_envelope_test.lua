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

-- An empty string is deliberately folded into "no text", the same as nil: a fence around
-- nothing would tell the reader nothing the fields don't already say.
local emptyText = C:Envelope("books", { { "page", "1" } }, "")
Expect("an empty string text has no fence, like nil", emptyText:match("text<<") == nil, true)

------------------------------------------------------------------------------- the fence, exactly
-- A line only *starting* with ">>" is not the fence and must survive untouched -- escaping it
-- would corrupt a contributed line like ">>see attached", and the reader's exact-match
-- unescape (only a line that IS "\+>>" loses one backslash) would never undo it.
local trailer = C:Envelope("books", { { "page", "1" } }, "before\n>>trailer\nafter")
Expect("a line only starting with >> is not escaped", trailer:match("\n>>trailer\n") ~= nil, true)
Expect("...and gains no backslash", trailer:match("\\>>trailer") == nil, true)

-- A line that was already "\>>" in the player's own text must come back out as "\>>": the
-- reader strips exactly one backslash from a line matching ^\+>>$, so the writer adds exactly
-- one every time, however many backslashes were already there.
local already = C:Envelope("books", { { "page", "1" } }, "before\n" .. "\\>>" .. "\nafter")
Expect("an already-escaped \\>> line gains one more backslash", already:match("\n\\\\>>\n") ~= nil, true)

local doubled = C:Envelope("books", { { "page", "1" } }, "before\n" .. "\\\\>>" .. "\nafter")
Expect("two backslashes before >> become three", doubled:match("\n\\\\\\>>\n") ~= nil, true)

-- CRLF normalises to \n before a line is tested against the fence pattern, same as Flatten.
local crlf = C:Envelope("books", { { "page", "1" } }, "line1\r\n>>\r\nline2")
Expect("a \\r\\n-terminated >> line is still recognised and escaped",
    crlf:match("\nline1\n\\>>\nline2\n>>\nsum=") ~= nil, true)

-- No trailing newline in the text closes the fence directly under the last line; a trailing
-- newline in the text is data and survives as a blank line before the fence.
local noTrailing = C:Envelope("books", { { "page", "1" } }, "a\nb")
Expect("no trailing newline in the text: the fence follows the last line directly",
    noTrailing:match("\na\nb\n>>\n") ~= nil, true)

local trailingNewline = C:Envelope("books", { { "page", "1" } }, "a\nb\n")
Expect("a trailing newline in the text becomes a blank line before the fence",
    trailingNewline:match("\na\nb\n\n>>\n") ~= nil, true)

os.exit(Failures() == 0 and 0 or 1)
