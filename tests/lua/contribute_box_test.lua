-- The frame a contribution is copied out of. Run with `make test-player`.
--
-- A StaticPopup edit box cannot hold this: hasEditBox is one line sized for a character name,
-- and an envelope is a few kilobytes over many lines.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local print = stub.print
local SPOKEN = here .. "/../../addons/SpokenPlayer/"
local Expect, Failures = H.Expecter(print)

stub.SetClient("11509")
local env = stub.LoadSpoken(SPOKEN)
local Spoken = env.Spoken

local envelope = Spoken.Contribute:Envelope("quests", { { "quest", "9123" } }, "Words.")

Expect("a nil envelope shows nothing", Spoken:ShowContribution(nil, "https://x"), false)
Expect("an envelope is shown", Spoken:ShowContribution(envelope, "https://x"), true)

local box = Spoken.ContributeBox
Expect("the box holds the whole envelope", box.editBox:GetText(), envelope)
Expect("...with no byte limit", box.editBox:GetMaxBytes(), 0)
Expect("...selected, so Ctrl+C is the only keystroke", box.editBox.highlighted, true)
Expect("...and is multi-line", box.editBox.multiLine, true)
Expect("the address is shown beside it", box.address:GetText(), "https://x")

-- Typing into it would destroy the payload before the player copied it.
box.editBox:SetText("nonsense")
box.editBox.handlers.OnTextChanged(box.editBox)
Expect("a keystroke restores the envelope", box.editBox:GetText(), envelope)

os.exit(Failures() == 0 and 0 or 1)
