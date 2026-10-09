-- Spoken Party Sync's sound channels: who plays the voice, the music, the effects, the ambience
-- and the NPCs' dialog is a party rule; this computer may decide each for itself; and the game's
-- own channels are switched off where the rule says, and back exactly as the player had them.
-- Run with `make test-player`.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/?.lua;" .. package.path
local stub = require("wow_client_stub")
local H = require("queue_helpers")
local P = require("partysync_helpers")
local print = stub.print
local Expect, Failures = H.Expecter(print)

local LALA = P.LALA
local LOOKUP = { ["101-accept"] = 10 }
local NONE = "music=none;effects=none;ambience=none;dialog=none"

local function Fields(message) return message and table.concat(message.fields, "|", 2) or nil end
local function CVar(name) return GetCVar(name) end

local ns, VO, env, Spoken

---------------------------------------------------------------- the rule, on the wire
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone",
	"music=lala throwaway;effects=none;ambience=-tata throwaway;dialog=none")
Expect("the leader's rules carry who plays each game channel", ns.Room:Owner("music") .. "|" .. ns.Room:Owner("ambience"),
	"lala throwaway|-tata throwaway")
Expect("...her computer alone plays the music", ns.Room:Plays("music"), false)
Expect("...every computer but this one the ambience", ns.Room:Plays("ambience"), false)
Expect("...and every computer the rest", ns.Room:Plays("effects") and ns.Room:Plays("voice"), true)
Expect("...so the channels differ", ns.Room:Summary(), "mixed")
ns:ShowWindow(true)
Expect("...which the audio chip says", ns.windowModel.chips.audio.text, format(ns.L.CHIP_AUDIO_FMT, ns.L.MIXED))
Expect("...and names in its tooltip", ns.windowModel.chips.audio.body:find(format(ns.L.ROOM_ALL_BUT_FMT, "Tata Throwaway"), 1, true) ~= nil, true)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone")
Expect("a leader before 0.5 sends no channels: every computer plays them", ns.Room:Owner("music"), "none")

---------------------------------------------------------------- what each computer says it plays
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 1, "m")
Expect("a member's hello says what it plays", ns.Room:Plays("music", "lala throwaway") and not ns.Room:Plays("voice", "lala throwaway"), true)
Expect("...shown on her row", ns.windowModel.members[2].plays, format(ns.L.ROW_PLAYS_FMT, "music"))
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "-")
Expect("...nothing, said with a dash", ns.windowModel.members[2].plays, ns.L.ROW_PLAYS_NONE)
P.Receive(stub, LALA, "HI", "0.4.0", 1, P.SESSION, 0)
Expect("a hello from before 0.5 leaves it to the rules", ns.Room:Plays("music", "lala throwaway"), true)
P.Clear()
ns.Room:SetOwnChannel("music", "muted")
local hello = P.Last("HI", LALA)
Expect("deciding a channel here tells the party", hello and hello.fields[5] .. "|" .. hello.fields[6], "1|vead")
P.Clear()
ns.Room:SetOwnChannel("music", "muted")
Expect("...once", P.Last("HI", LALA), nil)
ns.Room:SetOwnChannel("music", "")

---------------------------------------------------------------- the game's switches
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
stub.world.cvars.Sound_EnableAmbience = "0"
P.Party(stub, ns)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone",
	"music=lala throwaway;effects=none;ambience=lala throwaway;dialog=none")
Expect("a channel another computer plays is switched off here", CVar("Sound_EnableMusic"), "0")
Expect("...with the player's own value kept", ns:DB().cvarCache.music, "1")
Expect("...also one the player had off", ns:DB().cvarCache.ambience, "0")
Expect("...and the others left alone", CVar("Sound_EnableSFX") .. CVar("Sound_EnableDialog"), "11")
stub.world.cvars.Sound_EnableMusic = "1"
ns.Channels:Apply()
Expect("switched back on meanwhile, it is off again within the second", CVar("Sound_EnableMusic"), "0")
Expect("...the player's value still the first one", ns:DB().cvarCache.music, "1")
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone", NONE)
Expect("the rule back to every computer, the music comes back", CVar("Sound_EnableMusic"), "1")
Expect("...and the ambience as the player had it: off", CVar("Sound_EnableAmbience"), "0")
Expect("...with nothing kept", next(ns:DB().cvarCache), nil)

-- Spoken switches Dialog off around its lines: that is not the player's value.
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone", "music=none;effects=none;ambience=none;dialog=lala throwaway")
Expect("dialog another computer plays is off here", CVar("Sound_EnableDialog"), "0")
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone", NONE)
env.SoundUtils:MuteChannel("Dialog", true)
P.Receive(stub, LALA, "PS", "anyone", "none", "1111", "anyone", "music=none;effects=none;ambience=none;dialog=lala throwaway")
Expect("...taken over while Spoken has it off for a line, the player's value is on", ns:DB().cvarCache.dialog, "1")
env.SoundUtils:MuteChannel("Dialog", false)
Expect("...Spoken putting it back on", CVar("Sound_EnableDialog"), "1")
ns.Channels:Apply()
Expect("...is overruled at once", CVar("Sound_EnableDialog"), "0")

-- This computer's own choice wins over the rule, both ways.
ns.Room:SetOwnChannel("dialog", "plays")
Expect("this computer playing it by its own choice", CVar("Sound_EnableDialog"), "1")
ns.Room:SetOwnChannel("effects", "muted")
Expect("...or switching one off by its own", CVar("Sound_EnableSFX"), "0")
ns.Room:SetOwnAll("")

stub.FireEvent("PLAYER_LOGOUT")
Expect("at logout and /reload every channel goes back first", CVar("Sound_EnableDialog") .. "|" .. tostring(next(ns:DB().cvarCache)), "1|nil")

ns.Peers:Leave()
Expect("outside a party nothing is switched", CVar("Sound_EnableDialog"), "1")

-- A client that stopped with a channel off: the next login puts it back.
local account = { cvarCache = { music = "0" } }
ns, VO, env, Spoken = P.Boot(stub, LOOKUP, { account = account })
Expect("a login after a crash puts back a channel left off", CVar("Sound_EnableMusic"), "0")
Expect("...and forgets it", next(ns:DB().cvarCache), nil)

---------------------------------------------------------------- the leader's choices
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
P.Clear()
ns.Room:SetAll("lala throwaway")
Expect("all the sound on her computer is one rule for the party", Fields(P.Last("PS", LALA)),
	"anyone|lala throwaway|1111|anyone|music=lala throwaway;effects=lala throwaway;ambience=lala throwaway;dialog=lala throwaway")
Expect("...so this computer shows captions", Spoken:IsCaptionsOnly(), true)
Expect("...and keeps the game's channels off", CVar("Sound_EnableMusic") .. CVar("Sound_EnableSFX"), "00")
ns:ShowWindow(true)
Expect("...which the chip reads", ns.windowModel.chips.audio.text, format(ns.L.CHIP_AUDIO_FMT, "Lala"))
Expect("...her row says she has the voice", ns.windowModel.members[2].tag, ns.L.TAG_SOUND)
local play = nil
for _, entry in ipairs(ns:WindowMemberMenu("lala throwaway")) do
	if entry.text == ns.L.MENU_PLAY_HERE then play = entry end
end
Expect("...and her Play Sound Here that it is so", play.reason, format(ns.L.ALREADY_SOUND_FMT, "Lala Throwaway"))
ns.Room:SetAll("none")
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0, "vmead")
ns:Problem("missing:lala throwaway", "Lala Throwaway has no voice file.")
local mute = ns.windowModel.problems[1].actions[1]
Expect("a member with no voice file can be taken off the voice", mute.label, ns.L.ACTION_MUTE)
P.Clear()
P.Receive(stub, LALA, "HI", "0.5.0", 1, P.SESSION, 0)
mute.run()
Expect("...every computer but hers plays it, for the party", Fields(P.Last("PS", LALA)),
	"anyone|-lala throwaway|1111|anyone|" .. NONE)
Expect("...and the problem goes", ns.windowModel.problems[1], nil)
Expect("...this computer still plays the voice", ns.Room:Plays("voice"), true)
Expect("...the rule named in words", ns.Room:Describe(ns.Room:Owner("voice")), format(ns.L.ROOM_ALL_BUT_FMT, "Lala Throwaway"))
ns.Room:Exclude("voice", "bob stranger")
Expect("another left out joins the list", ns.Room:Owner("voice"), "-bob stranger,lala throwaway")

-- Hers is the "every computer but" side of it.
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns)
P.Receive(stub, LALA, "PS", "anyone", "-tata throwaway", "1111", "anyone", NONE)
Expect("taken off the voice by the leader, this computer shows captions", Spoken:IsCaptionsOnly(), true)
local entries = ns:WindowAudioMenu()
local voiceRule
for _, entry in ipairs(entries) do
	if entry.children and entry.text:find(ns.L.CHANNEL_VOICE, 1, true) and not voiceRule then voiceRule = entry end
end
local offered = {}
for _, child in ipairs(voiceRule.children) do table.insert(offered, child.text) end
Expect("the audio menu shows the rule it has, among the choices", offered[#offered], format(ns.L.ROOM_ALL_BUT_FMT, "Tata Throwaway"))
Expect("...greyed for a member", voiceRule.children[1].reason, ns.L.OPT_RULES_LEADER)

---------------------------------------------------------------- commands and the page
ns, VO, env, Spoken = P.Boot(stub, LOOKUP)
P.Party(stub, ns, nil, "me")
SlashCmdList["SPOKENPARTYSYNC"]("audio music lala throwaway")
Expect("/sps audio <channel> <name> sets that channel", ns.Room:Owner("music"), "lala throwaway")
SlashCmdList["SPOKENPARTYSYNC"]("audio me")
Expect("/sps audio <name> sets them all", ns.Room:Summary(), ns:MyKey())
SlashCmdList["SPOKENPARTYSYNC"]("sound music muted")
Expect("/sps sound <channel> decides one here", ns.Room:OwnValue("music"), "muted")
SlashCmdList["SPOKENPARTYSYNC"]("sound captions")
Expect("/sps sound alone is still the voice", ns:DB().soundOwn, "captions")
ns.optionsPanel:Show()
ns:RefreshOptions()
local layout = ns.optionsLayout
local function PageRow(label)
	for _, entry in ipairs(layout.entries) do
		if entry.label == label then return entry.frame end
	end
end
Expect("the page's Play All Sound On reads each channel's owner", PageRow(ns.L.OPT_ALL_SOUND).layoutRead(), ns:MyKey())
ns.Room:Set("music", "lala throwaway")
Expect("...or Mixed", PageRow(ns.L.OPT_ALL_SOUND).layoutRead(), "mixed")
local values = PageRow(ns.L.OPT_ALL_SOUND).layoutValues()
Expect("...which it lists so the box can show it", values[#values], "mixed")
PageRow(ns.L.OPT_ALL_SOUND).layoutChoose("mixed")
Expect("...without making it a choice", ns.Room:Owner("music"), "lala throwaway")
Expect("This Computer's row reads Mixed too", PageRow(ns.L.OPT_SOUND_OWN).layoutRead(), "mixed")
PageRow(ns.L.OPT_SOUND_OWN).layoutChoose("")
Expect("...and puts every channel back with the party", ns.Room:IsOwn(), false)
ns.optionsPanel:Hide()

ns:DB().cvarCache = { music = "1" }
ns:ResetOptions()
Expect("Reset keeps what the channels go back to", ns:DB().cvarCache.music, "1")

if Failures() > 0 then print(string.format("\n%d failure(s)", Failures())); os.exit(1) end
print("\nAll party sync audio tests passed")
