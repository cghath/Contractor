# Contractor: Fallen — world events, loot states, drop-in co-op

Lane `claude/survival-events` (calls 124-126; the mod kit, call 127, is docs/fallen_modding.md).
Suite: `fallenevents` (tests/fallenevents_test.gd); R2688 PASS (fallenevents, survival, worldsim, loot); the live convoy and the
crew's reward (lane `claude/survival-convoy`, sections 1b-1c): R2718 PASS (fallenevents, survival, worldsim, enclave, mounts); convoys that drive and cross zones (feat/fallen-convoy-drive): R0956 PASS (smoke, fallenevents), R0955 (firsthour, worldsim PASS), R0937 (survival PASS), R0930 (mounts PASS). Every number below is **Proposed**.

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
| convoy | 2 | 6 h | An enclave or trader column on the road (a zone with 3+ links) toward the next zone. At the end raiders in reach ambush it (35%: their supplies up, the column's grudge), else it passes and the settlers there trade with it. Hosted: a live column on the main road (1b); with no road, the column's wagon (a cache); robbing either is `convoy_robbed` naming the actor, the column's group -30. |
| heli_down | 1 | 48 h | A wreck at a place (hosted: a "Helicopter wreck" cache) and its crew of 2 as lone survivors beside it; the enclave asks for them back (1c: the players can bring them home for its reward). At the end the enclave takes back the crew still out there (`heli_recovered`; -5 standing if a player came near and left them), `escorted` when the players have them, else `heli_lost`. |
| bell | 2 | 2 h | Cultists ring a bell to call the dead (+20 pressure; a ringing lure in the live zone). A player rings one too: `FallenBell` at each church / village / square (at most 2 a zone), "Ring the bell": a lure for 90 s heard 220 m, +18 pressure, an event carrying his profile, the journal, the companions' memory (-3). 30 s cooldown. |
| burning | 2 | 24 h | +30 pressure, its place's richness halved; zones within 2 links see a glow on the horizon (DayNight's `glow` meta: the horizon leans orange, most at night; `Survival.state().sky_glow`); hosted while it burns, the fire is lit there (`Wildfire.server_ignite`). |
| storm | 1 | 12 h | Takes a bridge out: the crossing to a linked zone closed (`crossings` "storm"; goals, journeys and hordes go round). It stays out until repaired (`Infrastructure.server_set_crossing` / the bridge_repair project). |

Hooks: `WorldModel._world_event` and `step` (roll, tick), `WorldSim._after_step`
(`WorldEvents.server_after_step`: the frequency, the live pieces, the glow), `WorldSim.JOURNAL_KINDS`,
`Intel.GROUP_KINDS`/`ENCLAVE_KINDS`, `FallenRadio.CHATTER_KINDS`, `SurvivalLevel._on_hosted`
(`server_live`), DayNight's horizon (the `glow` meta).

### 1b. The live convoy: `FallenConvoy` (scripts/survival/fallen_convoy.gd), data/survival_convoy.json

- **The column**: `WorldEvents.server_live` brings an open convoy in the hosted zone in as a node `Convoy_<id>` under
  the level, on the road: `ConvoyRoad` finds the way along the laid roads (split at their junctions, shortest by length)
  from the road in at the edge it came through (`ZoneRoads.exits()`: the first zone of its way, the exit farthest from
  the one it leaves by) to the road out toward the zone it's bound for; no way through, the zone's longest laid road (80
  m at least), in at one end by the event's id. It goes along it at the way's length over the window left (enclave 2-5
  m/s, carts 1.5-3). Enclave: an M-ATV (the cargo) and a technical, 4 guards (M4s, an AKM); trader: two carts and a horse,
  2 guards (AKMs). A driver a vehicle and the trader: 5-7 people. The cargo is the lead vehicle's real hold (`enclave_cargo`
  / `trader_cargo` rolled by the event's id, or what it carried in from the last zone). The guards and drivers are a
  friendly-faction squad of their own (hc_id `convoy_<id>`): they shoot the dead and never the players.
- **Riding**: everyone rides in or on the vehicles while it moves: a driver at each wheel, the guards in the passenger
  seats (open ones first, so they're seen on the technical's bed), the enclave's quartermaster's man in a seat; the
  trader of a cart train walks beside his cart. A seated man's AI is off, like any rider's.
- **Driving (motor columns, `"drive": true`)**: with a player within `drive_near_m` (350) each truck drives for real,
  `VehicleAI.steer_to` on the road's next 70 m, given every `THINK_S` (0.25 s); the lead at the column's speed, crawling
  (1.5 m/s) for a straggler 2.5 gaps back; the one behind by `ConvoyColumn.follow_speed` on the gap along the road. Out of
  sight of every player it slides as the carts do: frozen, set along the road each physics step, so nothing far from
  anyone can fall through unstreamed ground and it costs no wheel rays. **Carts and the horse always slide**: a Mount's
  drive is a scripted glide anyway, and these carts have no horse in the shafts (Mount.can_drive is false without one).
- **Stretches with no road**: where two laid roads meet only at a site (a compound's walls between them), there's nothing
  to drive: `ConvoyRoad` costs a site 250 m in and out, so it goes round by junctions when there's a way, and the column
  slides across what's left, from 25 m short of it to 25 m past. A truck there has no road to be on.
- **Recovery, so a world event can't hang**: a truck 12 s with less than 2.5 m gained, 14 m off the road, overturned,
  fallen through or unable to drive goes back to sliding on the road for 10 s, then drives again, 3 times a column
  vehicle; after that it slides out its road. `until` + 6 h always ends it, however it's held up.
- **Halts**: a vehicle (a wreck) or a `convoy_blocks` node (a barricade) on the road within 14 m ahead: they get down,
  and after 8 s push it 9 m off the road, then walk back and mount up (`mount_s`, 12 s, is the most it waits; those near
  their vehicle get in at once); the dead within 22 m of the lead: they fight until none are near; raiders within 110 m;
  someone not of the column at one of its wheels ("wheel"): it holds until he gets out or drives off. Its noise every 3 s
  (`Survival.server_noise`: 70 m truck, 35 m carts) brings the dead and the zone's pressure as a shot's would, scaled.
  A vehicle wrecked or left with nobody to drive it drops out of the column (a wreck ahead then halts the rest); its seats
  are dealt again; a driver shot dead is replaced by the next man aboard.
- **Hailing**: a player up and not aiming within 18 m: it holds while someone stays within 30 m (120 s at most), the
  trader (a world person: meta `world_person`, record status `convoy`, his kit the `*_stock` roll) answers the talk
  menu's Trade (the barter screen); an enclave convoy's record carries `min_standing` 10 (`Barter.trader_problem`:
  "They only deal with friends of the enclave").
- **Robbing**: a player's hit on one of its people, anything taken from its cargo, or **driving off in one of its
  vehicles** (a stranger at the wheel, a player or a man he told to drive, and the vehicle gone 6 m from where he sat down):
  its people get out and turn hostile and fight, `WorldEvents.server_convoy_robbed` (outcome robbed, the owner -30, a
  `convoy_robbed` event naming the player, the companions' memory); its vehicles are let go, kept with the zone like any
  other. A passenger steals nothing, and neither does someone who sits at the wheel and gets out again. Taken with no
  crime: a vehicle given away (`FallenConvoy.server_give_vehicle`; nothing in the game gives one yet, the barter has no
  vehicles) and any vehicle left when all its people are dead by other hands (the column ends `lost`, a line on the radio).
  The players' own "mount up" and squad drivers leave a convoy's vehicles alone.
- **The ambush**: `WorldEvents.ambush_group` (raiders in reach at 35%; the live roll is kept as `ambush_by`, the far tick
  honours it). Live: at 35% of the road 3-5 raiders (hostile, a squad of their own) come out 90 m up the road either
  side; the guards all down: `convoy_ambushed` and the column is lost; the raiders all down: it goes on.
- **The end, and on into the next zone**: the far edge reached (or the window 6 h over): it crosses into the zone it's
  bound for (`legs`: 3 zones in all, a link not back the way it came, another if the crossing's closed by a storm) in the
  world sim (`r.crossing` {`from`, `to`, `arrive`}, `cross_h` 2 h away), an event on the radio; at the end of its way
  `convoy_passed`. A column that never comes live crosses at its window's end the same way (after the ambush roll and the
  settlers' trade). On arrival (`WorldEvents._convoy_arrives`, a far tick) it takes a new place and a fresh 6 h window, a
  new ambush roll, the zone's pressure up. **If the players are hosted there it arrives as a live convoy**, in at the edge
  it crossed by, the record's `carry` deciding what comes: who's alive (their crew index, the same people by name),
  which vehicles and their condition (fuel, damage, no carved look), the cargo as it was and the trader's stock
  (alive and wounded are the same to it: the road heals nobody but it doesn't kill them either). The record keeps `s`,
  `live` (the far tick leaves a live column alone; `live` left in a save for a zone not hosted is treated as stale), and
  everything above saves with the world section, including mid-crossing. No road: the wagon cache as before
  (`FallenConvoy.force_no_road` for tests).

### 1c. The downed crew's reward: `HeliCrew` (scripts/survival/heli_crew.gd), data/survival_convoy.json "crew"

- "Come with me" (the talk menu on a crew member out there): a companion (`heli_escort`), following, zone to zone.
- Delivered by walking them within 60 m of an enclave post (`Enclave.posts()`, checked on SurvivorsLayer's tick), or
  "Radio a pickup" on an escorted one (a repaired radio carried, powered; the enclave set up and not broken).
  "Take their tags" on a dead crew member's body: the profile carries them, handed in at a post or with a pickup.
- The reward: the enclave's standing +15 a crew member, +5 a set of tags; 3 rolls a crew member of medical stock (IFAK,
  morphine, antibiotics, saline, a surgical kit), a serum dose at 15%; into the deliverer's kit (the rest at his feet);
  a journal line and the enclave's thanks as a broadcast (the radio's enclave channel); the crew join the enclave
  (`Enclave._take_person`); the event closes `delivered`.
- Left: the window's end as before (the enclave takes back those still out there); a player who came within 120 m of
  them (`near` on the record) and left them: -5 standing with the enclave.

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

- Carts drawn by their horses under real steering (they slide on the road: a Mount's drive is scripted and a column's
  carts have no horse in the shafts); a guard on a technical's gun (it stays empty, they fight on foot).
- Dog tags as an item (the tags are carried on the profile); the pickup by radio is instant (no truck drives in).
- A player-dropped bell piece.
- The joiner's own survivor picker (a client message) and a joiner's own profile key (S5).
- A trail of chalk marks as a second kind of clue.
