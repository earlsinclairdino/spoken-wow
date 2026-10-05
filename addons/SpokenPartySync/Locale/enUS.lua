local _, PartySync = ...

-- Interface strings for the settings page, the sync window, the invite and the unit menu. Chat
-- and test output stay English, as in the other Spoken addons.
--
-- FORMAT ARGUMENTS ARE POSITIONAL (%1$s, %2$d), as in the other Spoken addons: word order is
-- what a translator most often has to change. The invite popup is the exception: the game's
-- StaticPopup formats its text with a plain %s.

PartySync.L = PartySync.L or {}
local L = PartySync.L

L.TITLE = "Spoken Party Sync"
L.PAGE_TITLE = "Party Sync"
L.OPT_NOTE = "Plays Spoken's lines together for players who quest together: whoever talks to the NPC, the line starts on every screen at once."

L.OPT_SECTION_MEMBERS = "Party"
L.OPT_MEMBERS_NONE = "Nobody yet. Type the other character's full name and press Invite, or right-click their portrait."
L.OPT_NAME_TIP = "The other character's full name, as chat shows it. Press Invite: they are asked to join."
L.OPT_INVITE = "Invite"
L.OPT_INVITE_TIP = "Asks them to join. Both of you need Spoken Party Sync, and they have to be online."
L.OPT_REMOVE = "Remove"
L.OPT_LEAD = "Who Leads"
L.OPT_LEAD_TIP = "The leader's Pause, Skip and Stop reach everyone, it shares the quests it accepts, and its line wins when two of you start the same one at once. Automatic picks whoever leads the group."
L.LEAD_AUTO = "Automatic"
L.LEAD_ME = "This Character"
L.LEAD_FOLLOW = "Never This One"

L.OPT_SECTION_SYNC = "Played Together"
L.OPT_SYNC_QUESTS = "Quest Dialogue"
L.OPT_SYNC_QUESTS_TIP = "A quest line one of you hears plays for everyone, with its text, even a class quest the others do not have."
L.OPT_SYNC_GOSSIP = "Greetings and Gossip"
L.OPT_SYNC_GOSSIP_TIP = "What an NPC says when you talk to them."
L.OPT_SYNC_ZONES = "Zone Lore"
L.OPT_SYNC_ZONES_TIP = "Narration for a zone or area one of you enters."
L.OPT_SYNC_BOOKS = "Books"
L.OPT_SYNC_BOOKS_TIP = "Pages one of you reads. Everyone needs the same Spoken Books."

L.OPT_SECTION_QUESTS = "Quests"
L.OPT_AUTO_SHARE = "Share Quests I Accept"
L.OPT_AUTO_SHARE_TIP = "When this character leads, a quest it accepts from an NPC is shared with the party at once."
L.OPT_AUTO_ACCEPT = "Accept Quests the Party Shares"
L.OPT_AUTO_ACCEPT_TIP = "A quest shared by someone in your Spoken party is accepted for you. Its line has just played, so it is not read again."

L.OPT_SECTION_CONTROLS = "Controls"
L.OPT_CONTROLS = "Pause, Skip and Stop Follow"
L.OPT_CONTROLS_TIP = "Whose Pause, Skip and Stop act on every computer. Only lines played together are skipped or stopped."
L.CONTROLS_LEADER = "The Leader"
L.CONTROLS_ANYONE = "Anyone"
L.CONTROLS_NOBODY = "Nobody"

L.OPT_SECTION_ROOM = "Same Room"
L.OPT_ROOM = "Who Plays the Sound"
L.OPT_ROOM_TIP = "Two computers in one room: one plays the voice and the others show the player and its captions without sound, so there is no echo. Choosing on one computer is enough."
L.ROOM_AUTO = "As Chosen Elsewhere"
L.ROOM_ME = "This Computer"
L.ROOM_MEMBER_FMT = "%1$s's Computer"
L.ROOM_NOBODY = "Every Computer"

L.OPT_SECTION_WINDOW = "Window"
L.OPT_WINDOW_SHOW = "Show the Sync Window"
L.OPT_WINDOW_SHOW_TIP = "A small window with the party, every queued line and how far each computer got with it."
L.SHOW_ALWAYS = "Always"
L.SHOW_SYNCING = "While Playing Together"
L.SHOW_PROBLEMS = "When Something Is Wrong"
L.SHOW_NEVER = "Never"
L.OPT_WINDOW_OPEN = "Open It Now"
L.OPT_WINDOW_SCALE = "Window Size"

L.OPT_SECTION_DIAGNOSTICS = "Diagnostics"
L.OPT_PING = "Ping the Party"
L.OPT_PING_TIP = "Times one message to each member and back. The result is printed in chat."
L.OPT_LOG = "Log Every Message in Chat"
L.OPT_LOG_TIP = "Prints each message sent and received, with the client's answer and whether you were in combat or an instance."
L.OPT_COMMANDS = "/sps lists the commands, including the connection tests: api, ping, latency, probe and burst."

L.OPT_SECTION_START_OVER = "Start Over"
L.OPT_RESET_PAGE = "Reset These Settings"
L.OPT_RESET_PAGE_TIP = "Everything on this page back to how it was at first. The party is kept."
L.OPT_RESET_CONFIRM = "Reset every Party Sync setting? The party is kept."
L.OPT_RESET = "Reset"
L.OPT_CANCEL = "Cancel"
L.REASON_NO_PLAYER = "Spoken is not installed or too old."

L.WINDOW_NO_MEMBERS = "No party yet: /sps invite <name>, or right-click a portrait."
L.WINDOW_QUEUE_EMPTY = "Nothing queued."
L.WINDOW_SKIP = "Skip"
L.WINDOW_PAUSE = "Pause or play"
L.STATE_ONLINE = "online"
L.STATE_LOST = "no answer"
L.STATE_OFFLINE = "offline"
L.STATE_UNKNOWN = "not heard from"
L.TAG_LEAD = "leads"
L.TAG_SOUND = "sound"
L.TAG_YOU = "you"

L.LINE_PLAYING = "playing"
L.LINE_QUEUED = "queued"
L.LINE_LOCAL = "here only"
L.LINE_PAUSED = "paused"
L.PEER_QUEUED = "queued"
L.PEER_STARTED = "playing"
L.PEER_LATE_FMT = "playing, %1$d ms late"
L.PEER_FINISHED = "done"
L.PEER_MISSING = "no voice file"
L.PEER_DROPPED = "dropped"
L.PEER_YIELDED = "follows"
L.PEER_WAITING = "waiting"
L.PEER_NO_ANSWER = "no answer"

L.HOLD_SYNCING = "starting together"
L.HOLD_WAITING_FMT = "waiting for %1$s"
L.HOLD_BEHIND = "after a line played together"
L.ADMIT_PLAYED_TOGETHER = "it was just played together"

L.PROBLEM_NO_ANSWER_FMT = "%1$s did not answer about \"%2$s\"."
L.PROBLEM_MISSING_FMT = "%1$s has no voice file for \"%2$s\": captions only there."
L.PROBLEM_NO_GO_FMT = "No start signal from %1$s for \"%2$s\": played here alone."
L.PROBLEM_LOST_FMT = "Lost contact with %1$s."
L.PROBLEM_OFFLINE_FMT = "%1$s is not online."
L.PROBLEM_OLD_MODULE_FMT = "%1$s is too old to play lines from the party."

L.INVITE_POPUP = "%s invites you to a Spoken party: lines played and skipped together, on every computer. Join?"
L.MENU_TITLE = "Spoken Party Sync"
L.MENU_INVITE = "Invite to Spoken Party"
L.MENU_REMOVE = "Remove from Spoken Party"
