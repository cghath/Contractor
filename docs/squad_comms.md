# Squad comms

Captain, 2026-10-14: "bots should act like players, communicate with the player".

The AI squadmates now answer every order, explain themselves when they leave the squad, and
report what the players should know, through the same subtitles as the callouts. Every line is
built from what the AI is actually doing (`SquadAI.intent`, `care`, `status_text()`), read after
the AI has thought about the order, so the comms can't say something the AI isn't doing. The
HUD squad list (`ai_status`) is unchanged and stays the always-on detail.

This is phase 1 (the MVP). Phases 2 and 3 are at the end.

## Where it lives

| Piece | File | Job |
|---|---|---|
| Delivery | `scripts/ui/callouts.gd` (`Callouts`) | Priorities, the side's budget, the queue, each listener's own wording of a place, subtitles, the session log |
| Content | `scripts/ai/squad_comms.gd` (`SquadComms`) | When to speak and what to say: order answers, Status?, the unprompted moments |
| Hooks | `squad.gd` (`var comms`, one `SquadComms.step` call), `soldier.gd` (`_server_squad_command` yields its reason, then one `SquadComms.heard` call), `command_menu.gd` (Report status goes to the host), `radio_chatter.gd` (one `Callouts.relay` call) | |
| Tests | `tests/comms_test.gd` (suite `comms`) | |

Everything runs on the host. Clients only show the lines they're sent (`Callouts._show_line`).
`SquadComms` only reads SquadAI state: nobody behaves differently because of it.

## What's said, and when

Each line is a subtitle "F3 Torres: Copy, holding". The F-key is the speaker's slot in your
command menu, so you know whom to select. The colour shows the priority. The audio hook plays
`res://audio/callouts/<id>.ogg` if that file exists (none do yet).

### Answers to orders

Each order is judged 0.6 s after it's given (`ANSWER_DELAY_S`), once the squadmates have
thought about it.

| Case | Who says it | Heard by | Example |
|---|---|---|---|
| They comply | One for the group: the team leader among them, else the lowest slot | The whole side | "Copy, holding", "Moving", "Suppressing!" (`ACK_LINES`) |
| One can't comply | Each one, at most 2; the acknowledgement counts the rest | The player who gave it | "Can't, carrying Miller's body", "Can't, pinned down!", "Can't leave Miller" |
| One will comply after | Each one, at most 2 | The player who gave it | "Getting to Miller first", "Treating Miller first", "Patching myself up first" |
| The order couldn't be given at all | The first selected | The player who gave it | "No body there", "No building there", "No visual". The red flash stays too |
| Move, Bound, Take cover, Fall back or Garrison | The one who acknowledged, once they're all there | The whole side | "In position" |

Throws, launchers, supports and the radio report get no "Copy". They answer for themselves:
"Frag out!", "Backblast clear!", or the helicopter on the radio.

Which units count for an order: commands that pick one or a few (Give me ammo, Treat that
casualty, Rearm from that body, Heal up, packs, Escort) are answered only by those who got
them.

### Status?

Status > Report status now asks the host. Each selected squadmate who is up answers you alone,
0.7 s apart (`STATUS_GAP_S`):

> "Watching over Miller. 2 mags, out of tourniquets, wounded. I'm back left, 400 m."

The parts are:

- what he's doing (`status_text`);
- his spare magazines;
- the life-saving items he's out of;
- how he is, unless OK;
- where he is, from your view, when more than 40 m away.

### Unprompted

Checked every 0.5 s (`THINK_S`) from what changed since the last look.

| Moment | When | Line | Priority, repeat |
|---|---|---|---|
| Pinned | Suppression at `SquadAI.PINNED` for 1.5 s | "I'm pinned!" | CRITICAL; once a spell, at most every 15 s |
| Hit | A new hit: a wound, or a round armor stopped. Not a rise in `injury()`, which includes blood lost and rises while he bleeds | "I'm hit!" (injury 0.35 and up), "Hit, still good", "Armor took it, I'm good" | CRITICAL; at most every 10 s |
| Ammunition | Spare magazines for the primary: 2 or fewer, none left, nothing at all. Checked every 3 s | "Low on ammo, 2 mags", "Last mag!", "Out of ammo!" | TACTICAL (out: CRITICAL); each level once, again after a restock, at most every 90 s |
| Medical | A life-saving item (`Scavenge.CRITICAL_MED`) his kit has, run out, as scavenging counts it (`Scavenge.needs`) | "Out of tourniquets" | INFO; again after a restock, at most every 180 s |
| Falling behind | On Follow, more than 100 m from the lead for 8 s | Kept by something: "Falling behind: watching over Miller, back left, 400 m". The rest, one for all: "Falling behind, four of us, back, 150 m" | TACTICAL; again after 60 s, or once twice as far |
| Stuck | Out of contact, more than 15 m from where he's going, under 2 m moved in 10 s (not while reaching a casualty or a body to scavenge: those give up on their own) | "I'm stuck, can't get to you" / "I'm stuck", and a session-log anomaly | TACTICAL; at most every 60 s |
| Explains a move | Starts on something nobody ordered (no order to him in the last 3 s): going for a body, scavenging a body more than 15 m off, falling back, patching himself up | "Going for Miller's body, bringing it with us", "Getting ammo off that body", "Falling back!", "Patching myself up" | INFO (falling back TACTICAL); said only while he's still doing it |
| Gives up a casualty | Let go of a casualty he couldn't reach (`SquadAI._give_up_casualty`) | "Can't reach Miller, someone else take over!" (a body: "Can't get to Miller's body") | CRITICAL (a body INFO); per casualty every 20 s |
| Contact | The existing `Callouts.contact` | "Contact, front, 80 m"; several together: "Contacts, three, front right, 120 m", worded from each listener's own view | TACTICAL; one call per group (`Squad.CLUSTER_M`) per 6 s |

The existing lines stay as they were (man down, medic, moving to, treating, frag out,
reloading, moving and covering, the tactics calls, carrying, scavenging).

## Throttles

All numbers are proposed; tune them with the Captain.

| Rule | Value | Where |
|---|---|---|
| Priorities | CRITICAL (lives, grenades), ANSWER, TACTICAL, INFO, by callout id | `Callouts.PRIO_OF` |
| Speaker gap | One line per 2 s per speaker. CRITICAL and ANSWER cut in | `SPEAKER_GAP_S` |
| Repeat gap | The same callout from the same speaker not within 8 s | `REPEAT_GAP_S` |
| Side budget | A token bucket per side: 3 at once, then one per 1.5 s, about 40 a minute. CRITICAL lines go with the bucket empty (they still take a token). Answers to one player don't use it | `CHANNEL_BURST`, `CHANNEL_REFILL_S` |
| Queue | A line that can't go yet waits, one per speaker and priority (the newest wins), at most 8 per side (the lowest priority, oldest first, is dropped). Best priority first, then the longest waiting | `QUEUE_MAX` |
| Staleness | A waiting line older than 1.5 / 4 / 2.5 / 6 s (by priority) is dropped, never said late. Counted in `Callouts.dropped` | `TTL_S` |
| Explanations | INFO lines wait while the speaker is in contact or his squad is engaged, and at most one per side every 4 s | `INFO_GAP_S` |
| Subtitles | 5 lines at once. Answers stay up 6 s, the rest 4 s | `MAX_LINES`, `SHOW_S_BY` |

The firefight check in `tests/comms_test.gd` holds a 30 s fight to 55 lines a minute side-wide
(budget plus the CRITICAL lines), 20 a minute from one squadmate, and no INFO lines.

## Network

- The host decides every line. Clients never do.
- `Callouts._show_line(path, name, id, text, prio)` is a reliable RPC to each listener, with
  that listener's own text: "{where}" is worded from his own soldier.
- The enemy's net on a captured radio (RadioChatter) goes through the same queue
  (`Callouts.relay`, TACTICAL, with its own gaps), so the enemy's chatter can't crowd out
  "Man down". `_show` keeps its signature for PeopleLayer (civilians talking to whoever is
  near, not the squad net).
- Status replies, refusals and deferrals go to the player who asked (`opts.to`).
  Acknowledgements and the unprompted lines go to the whole side.
- `sent` (the host's log) keeps the squad leader's wording in `text`, and each peer's in `texts`.
- The host's session log gets every line said to players: `comms <speaker>: <text>`, with
  `(to player N)` for answers. "I'm stuck" also raises the `comms_stuck` anomaly, so a bug
  stays a bug.

## Merging with fix/respawn-own-kit

That branch also touches `callouts.gd` (adds `putting_down()` between `carrying()` and
`scavenging()`, which this branch leaves as they were), `squad.gd` and `squad_ai.gd`. Once it
lands:

- `putting_down` is already INFO in `PRIO_OF`.
- "Stop bringing casualties" answers "Copy, leaving them where they lie" by itself once
  `Squad.hold_casualties` exists (dev answers "Copy, no casualty point").
- The body explanation takes its destination from `SquadAI._body_destination` when that
  exists: ", taking it to the CCP" or ", taking it to the exfil" (dev: ", bringing it with us").

## Phases left

**Phase 2**

- Voice range against radio: by voice within 60 m; beyond that only if both carry
  `SquadAI.RADIO`, with a "[radio]" tag. This builds on `SHARE_RADIO_S`.
- A chatter setting in `game_settings.gd`: Full, Essential (CRITICAL, ANSWER and contact) or
  Off, filtered on the client.
- A comms log panel on the map screen: the last 30 lines, plus the helicopter's radio.
- Vehicle contacts ("Technical, left, 200 m"), "Clear" and "Contact lost", HVT escort lines
  ("He's running!").
- Queue and drop counts in `ai_overlay`.
- A host/join test: a client orders Hold and gets `_show_line` from the host. This is for the
  coop-soak owner; `net_test` has no squad today.

**Phase 3**

- Recorded voice per callout id through `Callouts.play`, voice sets by Demographics, a radio
  squelch.
- Player quick-comms: a whitelisted, rate-limited `_server_say(id)` into the same queue, so
  humans and the coop-soak bots talk through one path.
- The AI answering player calls: a player's "Medic!" gets "Coming to you, Player 1".

## Questions for the Captain

1. Everyone on the side hears everything for now. Is radio range (phase 2) wanted soon?
2. Should the default chatter level be Full or Essential?
3. When an order collides with body carrying, should the AI obey (put the body down) or refuse
   with its reason? The comms report either way; the behaviour is fix/respawn-own-kit's to
   settle.
