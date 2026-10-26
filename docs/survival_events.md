# Contractor: Fallen — world events, loot states, drop-in co-op

Lane `claude/survival-events` (calls 124-126; the mod kit, call 127, is docs/fallen_modding.md).
Suite: `fallenevents` (tests/fallenevents_test.gd). Every number below is **Proposed**.

## 1. World events (call 124): `WorldEvents`, data/survival_events.json

The world sim rolls at most one a world day (`WorldModel._world_event` -> `WorldEvents.roll`):
`chance_per_day` (0.35) x the New world "world" option (`world_mult`: low 0.6, normal 1, high 1.5;
kept in the world section as `event_mult`), then a kind by weight and a zone that fits it (never the
hosted zone, but a bell may ring there). `WorldEvents.tick` runs every far tick and closes windows.
Each event is an ordinary event in the pool (the groups in its zone know it, so the rumour layer
tells it; the radio's chatter and enclave channel read it; the journal gets the near ones), with a
record in the world section's `fallen_events` ({id: kind, zone, place, t, until, state, outcome}).

| Kind | Weight | Window | What it does |
|---|---|---|---|
| supply_drop | 3 | 18 h | A place goes rich (3.0); every group in reach gets a forage goal there (the race); the enclave broadcasts it. A group foraging it first takes it (`supply_taken`); else it lapses. Hosted: a "Supply drop" crate (4 rolls of its loot); the players opening it first claim it (the enclave -5). |
| convoy | 2 | 6 h | An enclave or trader column on the road (a zone with 3+ links) toward the next zone. At the end raiders in reach ambush it (35%: their supplies up, the column's grudge), else it passes and the settlers there trade with it. Hosted: the column's wagon (a cache); robbing it is `convoy_robbed` with the actor, the column's group -30. |
| heli_down | 1 | 48 h | A wreck at a place (hosted: a "Helicopter wreck" cache) and its crew of 2 as lone survivors beside it; the enclave asks for them back. At the end the enclave takes back the crew still out there (`heli_recovered`), else `heli_lost`. |
| bell | 2 | 2 h | Cultists ring a bell to call the dead (+20 pressure; a ringing lure in the live zone). A player rings one too: `FallenBell` at each church / village / square (at most 2 a zone), "Ring the bell": a lure for 90 s heard 220 m, +18 pressure, an event carrying his profile, the journal, the companions' memory (-3). 30 s cooldown. |
| burning | 2 | 24 h | +30 pressure, its place's richness halved; zones within 2 links see a glow on the horizon (DayNight's `glow` meta: the horizon leans orange, most at night; `Survival.state().sky_glow`); hosted while it burns, the fire is lit there (`Wildfire.server_ignite`). |
| storm | 1 | 12 h | Takes a bridge out: the crossing to a linked zone closed (`crossings` "storm"; goals, journeys and hordes go round). It stays out until repaired (`Infrastructure.server_set_crossing` / the bridge_repair project). |

Hooks: `WorldModel._world_event` and `step` (roll, tick), `WorldSim._after_step`
(`WorldEvents.server_after_step`: the frequency, the live pieces, the glow), `WorldSim.JOURNAL_KINDS`,
`Intel.GROUP_KINDS`/`ENCLAVE_KINDS`, `FallenRadio.CHATTER_KINDS`, `SurvivalLevel._on_hosted`
(`server_live`), DayNight's horizon (the `glow` meta).

## 2. Loot that shows its state (call 125): `LootStates`, `WorldCache`

- **Picked over**: a box opened once (`WorldCache.server_open_for`) is `searched`: its lid up and
  its wood dulled on every peer (replicated); the zone save keeps `searched`, `searched_day`,
  `refills`, `pried` (`GameState` keeps those fields on load).
- **Hidden caches with clues**: 1-3 a zone by the seed, 25-45 m off a site, half in the ground
  ("Hidden cache"), two rolls of the field cache's table at uncommon 1 : rare 2 (the richest box in a
  zone). A handwritten note lies at another site: "...: 40 paces north and 15 east of the water
  tower. Under the loose earth." (`LootStates.clue_target` reads it back). Picking the note up puts
  a mark on the map within 12 m of the cache and the note in the journal.
- **Locked**: up to 2 of a zone's ordinary boxes (25% each, rolled once) need their key (an "Old
  Key", `fallen_key`, its state `opens` the box's uid), put in another box of the zone; or a crowbar
  pries it: "Pry it open" in the box's menu, 6 s, loud (45 m, +4 pressure at the start and again
  when it gives).
- **Refill only where people pass**: a searched box with fewer than 2 entries gets one fresh field
  cache roll after 3 world days (/ the "loot" option) when its zone is hosted, only if a living
  group or a lone survivor is in the zone, or it's the settlement's zone and a settler has the
  scavenge job. Never a hidden cache, a live event's box or a locked one.

## 3. Drop-in co-op and the shared journal (call 126): `CoopFallen`

- A friend joining a running world is a newcomer: at the farm (the settlement's middle, else the
  safehouse mark, else the zone's first insertion point), or beside the host when the world's
  "Friends join" option (New world) is "Beside the host"; the starter kit and a blank slate
  (`Survival.server_survivor_joined`); "X came to the farm: a newcomer" in the journal. The
  client is told where it stands (`_client_place`). The survivor picker for a joiner is later.
- The journal is shared: the host sends `JournalScreen.view()` to a joiner on join and to every
  peer whenever it changes (a digest of the journal, the marks and the deadlines, every 2 s); the
  client keeps it (`shared_view`) and an open journal shows it. The map's marks already sync.
- Companions remember who did what: `CoopFallen.server_deed(actor, what, by)`: every companion and
  settler's opinion of that player's profile moves and they keep the last 12 deeds
  (`remembers`); events can carry the actor's profile (`actor`: the bell, a robbed convoy).
- Leaving: the survivor's kit and needs are stored (none if he left down: the body keeps them),
  the body goes, the record is `asleep` at home; on return he wakes there ("X woke at the farm").
- Death in co-op: the existing permadeath per profile (`Survival.server_player_died`).
- `Survival.profile_of` honours a `fallen_profile` meta (a joiner's own profile key later; the
  test's second survivor now).

## 4. Left out / later

- A live convoy column (vehicles and people walking the road) and trading with it: hosted, it's
  the wagon cache; trade happens in the far sim.
- The enclave's reward for bringing the crew home; a player-dropped bell piece.
- The joiner's own survivor picker (a client message) and a joiner's own profile key (S5).
- A trail of chalk marks as a second kind of clue.
