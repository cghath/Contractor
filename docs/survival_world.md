# Contractor: Fallen — the living world

The world simulation behind the survival mode: the groups of the living, the regions they hold,
the dead as pressure, the enclave and the organization behind the fall, trade, information and
the maps. Written from the Captain's calls of 2026-10-25 (docs/survival.md, calls 7-65; the
numbers below refer to them). Inspired by STALKER's A-Life, RimWorld's people and Fallout's
factions; built on what Contractor already has (the living war, the AI commander layer, the
virtualizer, the region map, hiring and the roster).

## Where the build is (2026-10-26 ~07:40 CDT)

- **Phase C core built on `claude/survival-worldsim`** (sections 2-5, 9, 11-13; the settlement lane merged in):
  `WorldSim` (a child of Survival: the far tick on a WorkerThreadPool task, applied on the main thread; the
  catch-up; goal modes), `WorldModel` (the pure sim: groups, zones, pressure, far hordes, forming/splitting,
  the trickle, world events), `WorldGroup`, `WorldGoals` (the judgement of 4.3 and every goal of the table but
  patrol/enforce), `WorldFights`, `WorldRegions` + `data/survival_regions.json`, `WorldTrade.value`, `Rumours`,
  `WorldLive` (live groups: people for settlers/scavengers, hostile SquadAI squads with SquadOrders for
  raiders/cultists). Raider demands on the players' farm go to the settlement's council (`Council.server_put`);
  the sim reads `Settlement` stores and defence. Suites: worldsim + survival + settlement, R2652 PASS (worldsim, survival, settlement; a far tick 13 ms for 78 groups).
- Proposed defaults (in code): tick 15 world min; travel 2 h a zone; a busy group rethinks hourly; live 400 m,
  fold 500 m, 24 live people in a 64 budget with the dead; demand 6 h to pay, 40% share; catch-up 2 days and the
  clock moves with it; evac refill +10% / dead +5% each 10 days; clear refill x2, quiet under 15% of a zone's dead;
  the farm's zone starts with no group and no group walks into it (or raids the farm) on day one.
- Left for the next lanes: the enclave's price, detachments, patrols/tolls and the arc (section 6: the enclave is a
  placeholder group, `server_set_evac_paid`); ARCHE's trail and bunkers (section 7: no places of that type yet);
  trade with the players (section 8: `WorldTrade.value` is a stub, `server_player_trade` moves standing,
  `server_pay_demand` answers a demand); the intel layer (section 10: events in `world.events`, `rumours_for`,
  `events_near`, `event_added`; the map's political colour from `region_holders`; radio chatter).
  Also: CivilianAI tasks for live settlers beyond idling, the one stealth model for the living (call 131),
  the dead's decay/dress/nests (calls 112-115), fauna (100-103), the "settlement night" perf case (TODO in
  tests/fallen_test.gd).

Companion docs: survival_building.md, survival_people.md, survival_medical.md, survival_rpg.md.
Phase C of the build order (call 50) is this doc; its pieces that phase A and B need (zone
pressure, the dead's density, the safehouse cell) are marked **early**.

## 1. What the world is

- **The map** (call 32, 36): ~24 typed zones on `RegionMap`'s grid, grouped into **geographic
  regions** (plains, hills and mountains, desert, coast; later a river valley and wilderness
  zones between, the 48-zone plan). A zone has a type that sets its look, loot, the dead's
  density and the groups it attracts (table in §3).
- **The clock** (call 30): a world day is 2 real hours; four seasons of ~10 world days each;
  `DayNight` driven by it. The clock runs only while the world is hosted (call 25); Continue runs
  a bounded catch-up (§9).
- **The living** (call 20-24, 52): every person who isn't a player or a companion belongs to a
  **group**. Groups are simulated everywhere, always, on a slow tick; near players they are
  bodies with brains (the existing Soldier + SquadAI/CivilianAI), far away they are records
  (the `Virtualizer`, scaled up). There are no caps on how many groups exist (call 52): the
  world can empty or crowd by seed; performance is guarded by the live cap near players, not by
  design limits.
- **The dead** (call 22, 29): a zone's dead are a density per 64 m cell plus a zone-wide
  **pressure** that noise, light and crowds raise. Hordes are local: they form in a zone when
  its pressure peaks, never march in from another map on gunfire alone.
- **The goal** (call 7, 44): picked at New world, one world for all three: Reach the evac,
  Sandbox, Clear the map (§11).

## 2. The world sim: `WorldSim` (autoload, host-authoritative)

State lives in Campaign sections under `survival_<world>` (S1): `world` (clock, season,
weather, goal), `regions`, `zones` (pressure, density cells, holder, traces), `groups`,
`people` (every named person: in a group, a companion, dead), `relations`, `rumours`, `map`
(what the players know), `enclave`, `story` (the antagonist's trail, §7).

**Two tick rates.**
- **Far tick** every WORLD_TICK_S (Proposed 30 s real = 15 world minutes): every group not
  live takes one decision step (§4.3), journeys advance, supplies change, fights between far
  groups resolve by rules (§4.5), zone pressure decays, the dead drift and refill.
- **Live**: a group within LIVE_M (Proposed 400 m, one zone) of a player is spawned as bodies
  with the AI it would have (SquadAI for anyone armed, CivilianAI for the rest), its goal
  turned into orders (§4.4). Going far again, the bodies are folded back into the record
  (position, wounds, kit, who died). The existing `DynamicSim` sleeps bodies that are live but
  idle.

**Determinism.** Every far decision rolls from the world seed + group id + tick, so the
catch-up (§9) and a reloaded save produce the same world.

## 3. Regions and zones

| Region | Zones (types) | Climate / terrain | Loot bias | The dead | Dominant group kind |
|---|---|---|---|---|---|
| Plains | the safehouse farm, villages, a town, farms | mild; fields, hedges, roads | food, seeds, tools, fuel cans | low; towns medium | **settlers** (most people live here) |
| Hills and mountains | hill villages, a mine, caves, the dam, a ski town | cold, wind, snow in winter; hard travel, few roads | mining tools, explosives, cold-weather kit, the dam's parts | low, but hordes linger near warmth | **raiders** (camps in the compounds) |
| Desert | a desert town, an airstrip, the military base, a fuel depot | heat, scarce water, open sightlines | military kit, ammo, vehicles, fuel | few, slow by day, more at the base | the **enclave's** patrols; scavengers |
| Coast | the port, a fishing village, a resort town, the lab | fog, salt rot, storms; boats later | meds (the lab), fish, boats, the port's containers | high in the resort town | the **enclave** (the port); cultists in the resort |
| The city (its own region) | the city, its suburbs, a hospital | dense, dark, lootable | everything, the best; specials | highest | nobody holds it; scavenger crews and cultists pass through |
| Wilderness (48-zone plan) | forests, a river valley, moors | between regions; game, water | hides, meat, herbs | rare | travelling groups, hunters, hidden camps |

Each **zone type** carries: `abandoned: true` (S6: overgrowth, wrecks, litter, boarded and
broken buildings, no lights, no garrisons), a dead density profile per 64 m cell, a loot table
bias, the **places** the sim and the story use (a clinic, a police station, a fuel station, a
church, a school, the bunker door, a radio mast), and crossings to its neighbours.

**Regions as territories** (call 36): a region's dominant kind is a tendency, not a rule. The
political map is the sum of which groups hold which places; it shifts as groups win, lose and
move (§4). The map screen shows it (§10).

## 4. Groups

### 4.1 What a group is

```
Group { id, kind, name, leader: person, members: [person], home: place|null,
        supplies: {food, water, fuel, ammo, meds, wood, scrap}, mounts, vehicles,
        mood: {fear, hunger, morale}, personality: {greed, caution, cruelty, faith, loyalty},
        goal: Goal, journey: Journey|null, relations: {group_id: -100..100, player: -100..100},
        memory: [events], traces: [place, kind, day] }
```

**Kinds** (call 24): **settlers** (build, farm, trade; get raided), **raiders** (prey on
settlers and players; camps in compounds), **scavenger crews** (roam between zones; trade or
fight by mood), **cultists** (treat the dead as holy; keep a horde fed; convert or capture the
lone), **lone survivors** (the companion pool: a group of one), and the **enclave** (§6, one
group with many detachments). A group's kind comes from its leader's personality (§4.2) and can
change: settlers who lose everything and keep a cruel leader become raiders; raiders whose
leader dies and whose members fear the dead more than they hate people may settle.

### 4.2 People

Every member is a `Person` (the hiring candidate record, extended): name, age, background and
flaws (survival_rpg.md), skills with XP (companions and groups level by doing, call 18), needs
(survival_medical.md), mood and traits (survival_people.md), kit, wounds, **immune** flag
(rare, call 46), and a history (where they've been, what they saw: the source of rumours).
People are the same objects whether in a group, a companion, or a settler in the player's
settlement, so recruiting, capturing, deserting and dying move a person between records, never
copy them.

### 4.3 Decisions: the cost/reward judgement (call 21)

Every far tick (or every DECIDE_S live, Proposed 20 s) the leader scores the goals open to the
group and takes the best, with hysteresis (a goal in progress keeps a bonus so groups don't
dither):

```
score(goal) = expected_gain(goal) * need_weight
            - expected_losses(goal) * (1 + caution)
            - noise_cost(goal) * fear_of_dead
            - relation_cost(goal) * (1 - cruelty)
            + personality_bias(goal)
```

- `expected_gain`: what the goal gets (food for a hungry group weighs most; loot by the place's
  known bias; a captive for cultists; ground for settlers).
- `expected_losses`: from what the group **knows** (its scouts' reports, rumours, memory), not
  the truth: a raider group that hasn't scouted the settlement guesses from its size and the
  rumour of its guards. Scouting is itself a goal that lowers the uncertainty.
- `noise_cost`: fights raise the zone's pressure; a group that knows the zone is near a horde
  threshold avoids a loud goal.
- `relation_cost`: attacking a group others like costs standing with them; groups remember.

Goals, with their outputs:

| Goal | Who | What happens (far) | What happens (live) |
|---|---|---|---|
| forage | all | journey to a place, loot rolled against the zone's loot state, the place marked looted | the group walks to the place, searches containers (the real loot), leaves |
| hunt / fish / farm | settlers, scavengers | supplies up by region yield and season | the group at work (animals, nets, beds) |
| trade | all but cultists | a swap with another group or the player's settlement at value-scale prices (§8) | a trader walks to you or sits at the market |
| settle / move home | settlers, raiders | the home moves to a scored place (water, defensibility, loot nearby, low pressure) | a camp appears: tents, a fire, a fence, builds over days (survival_building.md) |
| raid | raiders; desperate anyone | the target judged (§4.3), a demand sent first (settlements: call 55), then a fight resolved (§4.5) | scouts first, the demand, then the attack with the tactics AI (support by fire, breach) |
| defend / fortify | settlers, enclave | defence value up; a horde or a raid resolved against it | guards, watch rotation, barricades built |
| flee | all | the group leaves a zone whose pressure or a stronger enemy threatens it | they run, leaving things behind |
| scout | all | a report on a place or a group (lowers uncertainty; the source of accurate rumours) | one or two people watching from cover; can be spotted |
| recruit | all | a lone survivor near the group joins if its relation and the group's reputation allow | a conversation at the camp |
| search | any with a missing member | a journey toward the last known place | people calling a name |
| convert / capture | cultists | a lone or small group captured (its people become captives: a rescue goal for their friends) | the cult comes at night, quietly |
| feed the horde | cultists | a captive given to the kept horde; the zone's pressure held high | the ritual, if you're there |
| patrol / enforce | enclave | detachments walk routes, shoot looters, take tolls | §6 |
| hunt the player | any wronged | a group with a grudge and the means tracks the players | they come for you |

### 4.4 Live groups

A live group's goal becomes orders for the existing AI: SquadAI with a `HcOrder` (move,
defend, assault, flank, follow) for the armed; CivilianAI tasks for the rest; the tactics layer
(docs/ai_tactics.md) for fights. Their relation to the players decides the stance: hostile
(attack on sight within the judgement), wary (weapons up, warnings, a line not to cross),
neutral (ignore), friendly (greet, trade, share a fire). The contextual talk menu (call 54)
reads the same record.

### 4.5 Far fights

A fight between far groups (or a far group and a horde) resolves by rules, not dice alone:
strength = members × (skill × kit × morale), the defender's defence value, the attacker's
surprise (scouted or not), the dead drawn by the noise (the fight raises pressure; a horde may
arrive mid-fight and take the field). Outcome: losses on both sides (named people die; their
bodies and kit are left as traces at the place), supplies taken, captives, a home lost. The
events go into both groups' memories and into the rumour pool (§10).

### 4.6 Forming, splitting, dying (call 52)

- **Form**: lone survivors (or two tiny groups) that meet near shelter and food, with
  compatible relations, merge; the leader is the one with the most loyalty-earning traits; the
  kind comes from the leader.
- **Grow**: a group recruits when its reputation and supplies allow; settlements draw people by
  a doctor, a well, a wall.
- **Split**: when morale breaks (hunger, losses, a cruel leader) or two leaders disagree on a
  goal; the split takes a share of people and supplies and a grudge.
- **Die**: supplies and members at zero. The place keeps the traces (a burnt camp, graves, a
  last note: §10).
- **Trickle**: new lone survivors appear at the map's edges at a low rate (they walked in from
  outside), so the companion pool never runs dry; they bring rumours of "outside" that never
  resolve.

## 5. The dead as pressure (early: phases A and B need it)

**Density**: per 64 m cell, from the zone type (plains farm 0-2, village 2-6, town 6-15, city
20-40 per cell, Proposed), saved in `zones`. Kills thin a cell; cells refill from neighbours at
REFILL_DAYS (Proposed 2; faster in Clear the map).

**Pressure** (call 22): one number per zone, 0-100. Raised by: shots (by loudness and count),
fights, vehicles and generators running, lights at night, a crowd of the living (a settlement's
size), blood and bodies left out, cultists feeding. Lowered by time (half-life Proposed 6 world
hours), rain, and the dead leaving to a louder cell. The local dead **drift** toward the loudest
cells. At PRESSURE_HORDE (Proposed 80) a **horde** forms from the zone's own dead (30-60) and
walks the pressure gradient; it disperses when the pressure falls and it finds nothing. A horde
never crosses into another zone unless that zone's pressure is higher than its own and the
crossing is on its path (so a settlement next door to a loud city is at risk, a quiet one across
the map is not).

**Senses and awareness** (call 29, 33): on the live zombies (ZombieAI): sight, sound, smell, the
visible awareness states. The crowd tier (S3, ZoneDead) uses the cell pressure only.

**Specials** (call 19): screamer (raises pressure sharply when it sees you: the local horde
trigger), crawler, bloater, hazmat; distributed by zone type (the city and the lab most) and by
the world option.

**Seasons on the dead** (call 34): winter slows walkers and draws them to warmth (smoke, light,
a running generator); summer speeds them and makes bloaters worse.

## 6. The enclave (call 56)

One group record with detachments: the **port** (its home: fuel, the radio mast, boats) and
the **military base** in the desert (ammo, vehicles, a sealed level it doesn't control: §7).
It broadcasts an evac that is real but rationed. Entry costs something, by seed: the cure
recipe or an immune person; an escorted convoy from the base to the port; a settlement's
loyalty (handed over); your best people conscripted. Its patrols walk routes between its places
and shoot looters at them; it trades with settlements it trusts (meds and fuel for food and
people); its officers disagree (a hard one, a decent one, a frightened one: named people whose
standing with you matters). By seed the enclave is **honest, corrupt or collapsing**, and only
rumours, scouting and its own broadcasts tell which. Routes to the evac: help it (earn the
price), infiltrate it (uniforms, a forged pass, a defector), or break it (take the port, with
everything that follows).

## 7. The organization behind the fall (call 62)

Not the military: an **internal R&D branch tied to it**, a mix of the CIA and the CDC. Its own
name (**ARCHE**, "Applied Research and Containment, Health and Epidemics": the Captain's call 66; a quiet blue-and-grey seal, acronyms everywhere), logo, jargon, and sites: the **lab** on the coast, the
**sealed level under the military base**, **bunkers** across the map (call 62: sealed, stocked,
trapped, the best loot and the best player stories), relay stations, a quarantine camp that
failed. The story is a **trail**: notes, terminals, recordings, a survivor who worked there, an
enclave officer who knows part of it, the broadcasts on a frequency the repaired radio can find.
Each world's seed lays the trail across its places; no two worlds tell it in the same order, and
it never fully resolves (call 62 keeps the mystery; the organization's own theories contradict).
The cure chain (call 15, 46) runs through its sites: the serum is theirs, the immune are what
they were looking for, and the enclave's price often is their work.

**Bunkers** (call 62): a place type: a door that needs power, a code (from the trail), a torch
cut or explosives; inside, stocked rooms, a trap or two, sometimes the dead that were sealed in,
sometimes a survivor, always a piece of the trail. Groups want them too: a bunker a raider gang
has opened is a different place from a sealed one.

## 8. Trade (call 26)

A **value scale** on every item (ammo, meds, food, fuel weigh most; season and region move
them: water in the desert, warm clothes in winter). Traders (settlement markets, scavengers on
the road, the enclave's quartermaster) swap at prices moved by what their group **needs**
(their supplies record) and their relation to you; **cash** is real too (traders take it, its
value drifts by seed). Groups trade with each other on the same rules in the far tick, so a
settlement that trades well grows and the trade routes become known (§10). Cheating a trader
(a theft seen, a bad deal by rumour) costs relations with everyone who hears.

## 9. Persistence and the catch-up (call 25)

Saved: every record above, per-zone voxel edits and builds (survival_building.md), bodies and
dropped kit, the players' survivors and companions. The world saves on every crossing, every
SAVE_MIN (Proposed 5) real minutes and on quit. On Continue, if world time was frozen while
nobody hosted, the sim runs **up to CATCH_UP_DAYS (Proposed 2) world days** of far ticks:
groups move, trades happen, a raid or two resolves, cells refill; the player settlement cannot
fall (its raids are deferred to a demand on return) and companions don't die; a **"while you
were away"** report lists what changed near the players (from the rumour pool).

## 10. Information: rumours, the journal, the radio, the maps (call 37, 45)

- **Events** from the sim (a fight, a move, a trade, a death, a horde, a bunker opened) go into
  a pool with a place, a day and the groups involved.
- **Rumours**: talking to anyone gives events their group knows (by its scouts, its travels, its
  trades), coloured by the teller: true, half-true (the wrong group, the wrong day) or a lie (a
  raider sending you into a horde). Companions report what they noticed on the road.
- **The journal**: what you've seen and been told, as entries: people (want, skills, where),
  places (what's there, when last seen), deadlines (a demand, a fever clock), the story trail.
- **The radio** (repaired, powered): group chatter in range, the enclave's broadcasts, the
  organization's frequency.
- **The maps** (call 37): **one map, continuous zoom**: the world (regions, zones, roads,
  rivers, coast, relief, the political shape as faint colour) down to the zone (streets,
  buildings, your marks). It shows only what's explored or told; marks **age** (a camp seen
  three days ago is drawn faded, may be gone). Found maps, a settlement's map table (call 45:
  the C-lane map HUD reused: scouts' and allies' reports near real time, trade routes, known
  group movements) and the radio add to it.

## 11. The goal modes (call 44)

| Mode | Setup | Pressure curve | Win |
|---|---|---|---|
| Reach the evac | the enclave at the far edge; the trail leads there | rises slowly over the season (the dead refill a little faster each 10 days) so lingering costs | arriving at the evac with the roster alive, the price paid |
| Sandbox | no evac; the enclave is just a faction | local and seasonal only | none; the score is days, settlement size, roster, places opened |
| Clear the map | no evac; faster refill; specials spread by season | each zone's density must be driven under a threshold and **held** by a standing presence (an outpost of yours or an allied settlement, a watched border) | every zone quiet at once |

## 12. The start (call 41, 64)

The safehouse farm in the plains at the quiet edge. Each start rolls: who left the note and
what they left (a map with one place marked, a weapon, a warning); which neighbour is met first
(a settler family, a scavenger, a wounded stranger with a rumour); something nearby (a wreck
with a part, a bunker door, a well gone bad, a walker in the barn, a raider scout watching);
the day-one season and weather. The first companion candidate is within a kilometre with a
simple want. Difficulty grows with distance from home.

## 13. Performance

Far groups cost a few hundred bytes and one decision per tick; a world of 300 groups is under a
millisecond a tick. Live: the existing fight-case AI count (32) is the budget for all live
people and zombies together; LIVE_CAP (S2, Proposed 40 zombies) and a live-people cap (Proposed
24) share it, the crowd tier (S3) and the virtualizer take the rest. The far tick runs on a
worker thread with the result applied on the main thread. A perfcases case "settlement night"
(a horde siege on a built settlement with 12 people) joins the suite in phase C.

## 14. Tests (phase C)

`worldsim` suite: a group forages, trades and settles by the judgement; a raid is judged against
a scouted settlement and sends a demand first; a far fight leaves traces and a rumour; pressure
rises on noise, forms a local horde at the threshold and never crosses into a quieter zone; a
cultist group captures a lone survivor and a friend's group gets a search goal; the enclave
takes a toll and shoots a looter; the catch-up moves the world within bounds and the report
lists it; a rumour from a raider lies and from a scout is true; the map draws only what's known
and ages a mark; each goal mode's win condition.

## 15. Calls answered (2026-10-25)

1. The organization is **ARCHE** (call 66).
2. The catch-up runs up to **2 world days**, companions safe (call 67).
3. The enclave **can be joined** as a path with a cost (call 68): serving it is the third route
   to the evac in §6, beside helping and breaking it; infiltration is a flavour of serving.
4. Wilderness zones come **after phase D** (call 69): §3's wilderness row is the expansion.
