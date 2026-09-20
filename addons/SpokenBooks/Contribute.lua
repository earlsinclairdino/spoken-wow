-- A page this corpus does not carry, as something that can be sent.
--
-- The gap is the same one Reader.lua's PageOnScreen answers with nil: a page whose checksum
-- no lookup holds. On a 1.12-derived corpus that is every post-vanilla book, every locale but
-- one, and whatever a private server wrote itself.
--
-- MAIL NEVER LEAVES THE CLIENT. IsMail is already how the reader refuses to narrate a letter,
-- and the reason is stronger here: a letter is a player's own words to another player, and
-- this is the one path in the addon that would put them on a server of ours.
--
-- `page` is the client-side checksum, not a pageTextID. The frozen id `b:{pageTextID}` names a
-- page the corpus has; a page it has never seen has no id to be named by, and gets one only if
-- triage accepts it.

local ADDON_NAME, SpokenBooks = ...

--- The envelope for the page on screen, or nil when there is nothing to send.
function SpokenBooks:CaptureContribution()
	if self:IsMail() then
		return nil
	end

	local text = ItemTextGetText and ItemTextGetText()
	if type(text) ~= "string" or text == "" then
		return nil
	end

	local fields =
	{
		{ "addon", format("SpokenBooks/%s", self.version or "dev") },
		{ "build", format("%s/%s", (GetBuildInfo and select(1, GetBuildInfo())) or "?",
		                           (GetBuildInfo and select(2, GetBuildInfo())) or "?") },
		{ "locale", (GetLocale and GetLocale()) or "enUS" },
		{ "page", self:ChecksumOf(text) },
		{ "book", (ItemTextGetItem and ItemTextGetItem()) or "" },
		{ "number", (ItemTextGetPage and ItemTextGetPage()) or 1 },
	}

	return Spoken.Contribute:Envelope("books", fields, text)
end

--- Whether the contribute button belongs on the page: text to send, and no page id for it.
function SpokenBooks:HasContributionGap()
	if not (_G.Spoken and Spoken.Contribute and Spoken.ShowContribution) then
		return false
	end
	if self:PageOnScreen() then
		return false
	end
	return self:CaptureContribution() ~= nil
end

-- Compression belongs here, not in CaptureContribution or HasContributionGap: those run on
-- every page turn to decide whether the button belongs on screen, and paying deflate's cost
-- there would tax every page the player merely reads, for a result thrown away unhandled on
-- every one that isn't a gap. This runs once, on the click.
function SpokenBooks:ShowContribution()
	local envelope = self:CaptureContribution()
	if not envelope then
		return
	end
	local address = format("%s/contribute", self.SITE_URL)
	-- Encode is absent on an older SpokenPlayer a legacy-client zip can still bundle; Link
	-- returns nil for that or for an oversized result, and the two-copy fallback still works.
	local link = Spoken.Contribute.Encode and Spoken.Contribute:Link(address, envelope)
	if link then
		Spoken:ShowContribution(link, address, true)
	else
		Spoken:ShowContribution(envelope, address)
	end
end
