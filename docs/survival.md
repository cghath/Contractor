# Survival: an open world, persistent, overrun

## Where the build is (handoff 2026-10-25 ~09:00 CDT, at the 5-hour limit)

Branch `claude/survival` (worktree `B:\Contractor\.claude\worktrees\survival`, from integrate/cg-oct24 841f0ff0).
- **S1 done** (182e519f, survival suite R2592 PASS): menu Survival new world / continue, `Survival` autoload
  (world save `survival_<world>`, clock -> DayNight, hunger/thirst via Consumables' water/ration doses, slower
  stamina low, blood loss empty, death drops everything where he fell (no cleanup in survival) + starter kit,
  survivors' kit/needs saved), `SurvivalLevel` (no garrisons/patrols/US/skirmish/bots), HUD Food/Water line.
- **S2 mostly done** (next commit): `ZombieAI` (idle/hear/see/chase/search, walkers + 15% runners, night
  faster and blinder), `Vitals.undead` (head/face kill, else a hit-point pool), `CompoundLevel._make_zombie`
  (grey civilian on every peer via the AI spawner), `Survival._populate` (spawn out of view 45-75 m by site
  density, despawn past 110 m, kills thin a 64 m cell, refill 2 days), shots wake the dead (Soldier ->
  `Survival.server_noise`). Tested OK: spawning, hearing, chase + bite, headshot, pool, thinning.
- **S2b melee core** `scripts/survival/melee.gd`: telegraphed attacks (windup), dodge/sidestep i-frames,
  block (20% through, stamina, heavy breaks it), parry (block within 0.25 s of landing: stagger + 1.2 s
  counter window, counter instant x2). Zombie bites go through it. Tested OK: windup, held block, dodge.
- **OPEN BUG (first thing):** survival_test's parry check fails: the bite lands ("melee_winding" gone) but the
  parry branch isn't taken and the player isn't hurt, so `Melee._land` most likely found no target at land time
  (`target_in_front` null: the player may move or turn in the windup; the test's zombie has process disabled).
  Print `target_in_front(attacker)` in `_land`, then fix (maybe lock the victim at windup start and re-check reach).
- **Then:** regression suites on the S2 tree (R2593 ran mid-edit: loot/medical results void; smoke, world and
  levelswitch passed), commit/push, then player melee: melee weapons as weapon items tagged "melee"
  (sidearm one-handed: knife, machete, crowbar; primary two-handed: bat, axe, sledge), MeleeInput (fire = light,
  hold = heavy, aim = block/parry, dodge key + direction, sidestep), owner -> host RPCs; then S3 crowd/hordes,
  S4 survivors/companions, S5 crossings, S6 abandoned look, S7.

**Status:** design 2026-10-25, building on `claude/survival`. The Captain's calls (2026-10-25,
asked with the question tool) are in **Calls**; everything marked Proposed is a default to tune.

The Captain's direction (2026-10-25): "open world persistent zombie survival mode", from the main
menu, "players and there should be companions you can meet out in the world and hire for money,
an item or something else", and on the world: "reuse a lot of our zones with some assets edits to
make it more like an abandoned world". Scope: "design doc then more than a slice, much more".

Inspired by DayZ's persistence and scavenging, 7 Days to Die's hordes and nights, and Project
Zomboid's needs, built our own way on Contractor's zones, bodies and squad AI.

## Calls

| # | Call | Decided |
|---|---|---|
| 1 | Where | Standalone, the main menu's **Survival** section; never touches the campaign. Co-op joins as today. |
| 2 | Who | Players, plus **companions met out in the world**, each hired for **money, an item or a favour**. |
| 3 | Zombies | **Mixed**: mostly slow walkers in groups and hordes, some runners, tougher specials later; worse at night. |
| 4 | Death | **Respawn, lose your kit**: your body and everything on it stay where you fell; the world goes on. |
| 5 | World | **Our zones, made to look abandoned**: overgrowth, wrecks, litter, boarded and broken buildings, no lights. |
| 6 | Scope | Design first, then the whole mode in phases (S1-S7), not a one-zone slice. |
| 7 | Goal (2026-10-25 brainstorm) | **Three world goals, chosen at New world:** Reach the evac (a far-side evac point or a radio to repair; arriving with your people alive wins the world), Sandbox (no win: the safehouse and roster are the score), Clear the map (the hardest: every zone's dead thinned under a threshold and held). |
| 8 | Safehouse | **Free building** in the voxel world: walls, barricades, furniture and utilities placed anywhere from scavenged materials (not fixed upgrade tiers). |
| 9 | Noise | **Loud guns punish**: unsuppressed fire reliably pulls the street and can raise a horde; melee, bows, suppressors and distractions are the main tools. |
| 10 | Infection | **Players and companions from the start**: a bite starts a fever clock; antibiotics hold it; **a cure must be reachable** so any player has a reasonable chance to save their character (tied to the RPG layer, call 11). |
| 11 | RPG layer | **Experience and progression** for each survivor (XP, levels, skills); design to come (docs/survival_rpg.md). |
| 12 | Building system | **Voxel blocks + snapped pieces**, to build anything within reason and go past the DayZ base-building mods: material blocks placed and removed in the world grid (wood, scrap, sandbags/HESCO, concrete, steel) for any shape, snapped pieces for doors, hatches, windows, stairs, ladders, furniture, lights, workbench, well; structural integrity (unsupported spans fall; zombies chew wood, metal holds); blueprint mode (ghost pieces built by players or companions); repair, dismantle, upgrade in place; everything a physics object saved with the zone's voxel edits. Design in docs/survival_building.md. |
| 13 | Death (refines 4) | **Permadeath character**: a dead survivor is gone, body and kit stay where they fell; the player starts a **new survivor from zero** (no XP or skills carried over). |
| 14 | Metabolism | **Calories, water, protein/carbs/fat and a few vitamins** on a body screen (inspired by SCUM, less spreadsheet), plus fatigue/sleep, body temperature with wet clothes and wind, carried weight, hygiene; every deficit feeds the medical system (healing rate, stamina, sickness) rather than standing alone. Survival depth past today's survival games; medical depth past SCUM (wound infection staging, sepsis, antibiotic courses, field surgery, fever, blood types and transfusions, hypothermia and heat stroke, bones that heal over days, companion medics). Design in docs/survival_medical.md. |
| 15 | Cure | **Both**: a rare cure serum in hospitals and labs, and a quest chain that makes one reliably (a doctor companion or your own medical skill, a hospital or lab zone, equipment, an immune survivor's blood); antibiotics and rest buy days. |
| 16 | RPG shape | **Learn by doing + perk picks**: skill lines (medical, building, melee, firearms, archery, scavenging, mechanics, driving, cooking, fieldcraft, fitness, stealth) level from use; total XP gives a survivor level with a few general perk picks. |
| 17 | Character creation | **Blank slate by default, or background + flaws**: a background starts one line higher; flaws are taken for points that buy other skills higher (inspired by Project Zomboid's traits). |
| 18 | Companions level | **Yes, by doing**: companions earn XP in what they do beside you; their skills show when you talk to them. |
| 19 | Specials (first cut) | **Screamer** (calls a horde), **Crawler** (under cars, in grass, grabs legs), **Bloater** (bursts, taints the room: masks or distance), **Hazmat** (hard shell: the head or heavy hits). |
| 20 | Living world | **A truly living world, inspired by STALKER's A-Life, big scope**: groups of the living form dynamically with their own objectives and goals (settle, raid, trade, flee, hunt, hold ground), move between zones, fight the dead and each other, and leave traces whether or not a player is there. Design in docs/survival_world.md. |
| 21 | World sim depth | **Full world sim**: every group simulated everywhere on a slow clock (journeys, fights, supplies, deaths resolved by rules while far; live near players). **Groups judge cost against reward** before acting: a raid, a move, a fight or a trade is weighed by its likely gain, losses, noise and the relations it burns, so factions are aware of consequences. |
| 22 | Hordes | **Local and pressure-driven, never world enders**: a zone carries a noise/pressure level (shots, fights, lights, generators, crowds); the local dead drift to it, and only when the pressure peaks does a horde form in that zone. Hordes don't march in from other maps on gunfire alone; a big fight elsewhere raises that zone's pressure, not yours. (Refines S3.) |
| 23 | Settlement | **Yes, from the safehouse**: the base can grow into a settlement; survivors ask to join, the player sets jobs (farm, guard, scavenge, medic, build), it trades and gets raided. |
| 24 | Enclave + groups | A **military enclave** exists, **ambiguous**: the evac, a trap or both by seed and rumour. First-cut group kinds: **settlers, raiders, scavenger crews, cultists** (plus lone survivors as the companion pool, and the enclave). |
| 25 | Offline world | **Frozen with a bounded catch-up on return**: the clock stops when the host quits; Continue runs the world sim up to CATCH_UP_DAYS (Proposed 2) world days (groups move, trades, a raid or two resolve, cells refill) and shows a short "while you were away" report; nothing catastrophic offline (the player settlement can't fall). |
| 26 | Trade | **Barter on a value scale AND cash**, like STALKER and Fallout: every item has a value (ammo, meds, food, fuel weigh most), traders at settlements and roaming scavengers swap, prices moved by what their group needs; found cash is a real currency traders take too. Groups trade with each other on the same rules in the world sim. |
| 27 | Players | **Co-op up to 8, no PvP**: one roster of players plus companions, friendly fire real; raiders and cultists are the human threat. |
| 28 | Settlement depth | **Full politics**: jobs (farm, guard, scavenge, medic, build, cook), stocks (food, water, fuel, defence), morale (theft, desertion, a split), raids and hordes by pressure, recruits drawn by a doctor or stock, size by beds and food (Proposed 24); plus factions inside the settlement, a council or leader challenge, relations with other settlements (alliances, feuds). |

## Already in the code to build on

| Piece | Where | What it gives survival |
|---|---|---|
| Zones from a definition, linked | `ZoneDef`, `ZoneLevel`, `RegionMap.links`, crossings (`Extraction`, `BaseHub.server_cross_on`) | The open world: the campaign's region map, every zone joined to its neighbours at the edges |
| Per-zone saves | `GameState` (`looted`, `dropped`, `voxel_edits`, `bodies`, `vehicles`), `save_zone` | A zone you leave keeps what happened in it |
| A whole world's save | `Campaign` sections under a `campaign_id` | The survival world's own save (`survival_<world>`), never the campaign's |
| Hosting a zone from the menu | `Menu.host_forest_zone` (test zones) | The pattern for New world / Continue |
| Bodies, wounds, ragdolls, gore | `Soldier`, `Vitals`, `BodyDeform`, `Ragdoll` | Zombies and survivors are Soldier bodies near players |
| A cheap crowd | `ZoneAnimals` (MultiMesh, one host packet, hit areas) | The far tier of a horde |
| Sleep and virtual groups | `DynamicSim`, `Virtualizer` | What's far stays cheap |
| Noise | `PeopleLayer.server_noise`, `Alert.server_noise` (every shot, kicked doors) | What draws zombies |
| Food and water | `Consumables` (MRE, IRP, bottled water, ...: "hunger and thirst deferred") | The needs' items: eating and drinking now matter |
| Loot | `data/loot_tables.json`, `WorldValuables`, rarity boxes, compound loot | What there is to find |
| Hiring and the squad | `Hiring.candidate`, `Roster`, `SquadAI`, orders, the 8-slot squad | A recruited survivor is a squadmate |
| Day and night | `DayNight` (hour, weather) | Nights are when they come |

## S1: the mode, the world, the needs

**Menu.** A Survival section: **New world** (a name, a seed), **Continue** (the newest world),
**Join** as every session. The host's world is the save; joiners bring nothing in (their survivor
lives in the host's world, keyed by their profile).

**The world** (`Survival`, an autoload, host-authoritative, its state in Campaign sections under
`survival_<world>`): the campaign's zones on `RegionMap`'s grid, each marked abandoned, the base
zone's cell a **safehouse** (the start and the respawn: a fenced farm with a stash). The world's
clock runs only while it's hosted; a day is DAY_MIN (Proposed 48) real minutes, with
`DayNight` driven by it. Zone saves are `surv_<world>_<zone>`: crossing into a zone loads it as
it was left. Sections:
- `survival`: seed, day, hour, the zones' state (density of the dead, looted containers' times);
- `survivors`: each player's survivor by profile: zone, position, kit, needs, alive;
- `companions`: who's been recruited, their kit, needs and wounds; who's still out there.

**Needs** (on `Vitals`, replicated like stamina): **hunger** and **thirst**, 100 full to 0.
Proposed rates: thirst empties in 1.5 world days, hunger in 3. Under 25: stamina comes back slower
and the screen edges dim; at 0: a slow loss of blood volume (thirst faster) until it's fixed.
Eating and drinking (`Consumables`: `"food": n`, `"water": n` in an item's `consume`) fill them.
Running and carrying weight drain faster. The HUD shows two small bars by the stamina.

**Loot.** A `survival` loot table: food (tins, MREs, crackers), water (bottles, dirty water to
treat), meds, scarce ammo, melee weapons, tools; containers in houses and shops roll from it. A
looted container comes back after LOOT_BACK_DAYS (Proposed 3) world days, rolled again.

**Death.** Respawn at the safehouse with the starter kit (a knife, a bottle of water, a tin, a
torch, bandages). The body stays where it fell with everything on it, never cleaned up in
survival, marked on its owner's map until looted.

## S2: the dead

**Faction `infected`.** Every side's enemy; nobody's squad counts them.

**Kinds** (`data/zombies.json`, Proposed): **walker** (most; 1.1 m/s, hears shots 180 m),
**runner** (15%; sprints 5 m/s once it sees you), **brute** (S6: slow, armoured, knocks you down).
At night walkers go 1.4 m/s and hear 1.3x further.

**A zombie near players** is a Soldier body in civilian clothes (`PersonLook`, torn and grey)
with a host brain, `ZombieAI` (like `CivilianAI`: it only writes the body's intent fields):
- idle: shuffles about its spot, or along a street;
- hears (a shot, a door kicked, a car, a scream: `Survival.server_noise`): walks to the sound,
  searches round it, then idles there;
- sees (short sight, 40 m by day, 15 m by night; a crouched man half): chases at its kind's pace,
  groaning; others within GROUP_M join in;
- reaches: **melee** (`Melee`, new: a hit `round_class` `"bite"` or `"blow"` through
  `Vitals.server_hit`, shallow, bleeding; a bite can infect, S7) every ATTACK_S (Proposed 1.3 s);
- **dies** only to the head or to a lot of damage (Vitals in its `undead` mode: no pain, no
  shock, no bleeding out; the head kills; DAMAGE_POOL Proposed 12 hit points elsewhere).

**A zone's dead.** Each zone has a density per 64 m cell (rural low, towns high, cities highest),
from the zone's modules and buildings, saved in `survival`. The host keeps up to LIVE_CAP
(Proposed 40) zombies as bodies within LIVE_M (Proposed 70 m) of players; past that a cell's dead
are the **crowd** (S3). Kills thin a cell; cells refill slowly (REFILL_DAYS, Proposed 2) from the
neighbours, so cleared ground stays safer for a while.

## S3: hordes and the crowd

The crowd is the far tier: `ZoneDead`, like `ZoneAnimals` (one MultiMesh per look, host walks
them, one small unreliable packet SEND_S apart), so hundreds cost little. A crowd zombie that
comes within LIVE_M of a player becomes a body (where it was, the same kind); a body that's out of
it and not chasing goes back. **Hordes**: some nights (Proposed every 4th, and on a gunfight's
noise in a city) a horde of 30-60 forms in the zone and walks towards the noise or the players.

## S4: survivors and companions

**Survivors** are people out in the world (`PeopleLayer`, kind `survivor`): holed up in a house,
on a roof, at a camp, wandering. Each is a `Hiring.candidate` (name, role, skills) with **a
want** (Proposed: 40% money, 40% an item, 20% a favour):
- **money**: cash found as loot (survival's currency), Proposed $200-1500 by skill;
- **an item**: something from a want list (antibiotics, a rifle and mags, 5 tins, a backpack);
- **a favour**: clear a building, bring something from a marked place, find someone.

Talk (the interaction menu) shows who they are and what they want; give it (or come back with it)
and they join: a squadmate (`SquadAI`, friendly, follow and every order), in the 8-slot squad
with the players (at most 8 together). Companions eat and drink from what they carry and ask for
more; they can be wounded, treated, and killed for good. Some survivors are hostile (bandits,
S6) and some won't join at any price.

## S5: crossings and persistence

Walking out of a zone's edge at a crossing loads the next zone for the whole session (as the
campaign's crossings), saving the one left. Saving: the world on every crossing, every
SAVE_MIN (Proposed 5) real minutes, and on quit. Continue loads the world where it was: each
survivor in the zone they were in (the host's zone wins: everyone joins the host's zone).

## S6: an abandoned world

A zone def's `abandoned: true` (every survival zone) changes how it's built, never the
campaign's: roads and yards overgrown (grass and bushes through the asphalt, ZoneScatter),
wrecked and burnt cars on the roads (VehicleLayer wrecks, a few to a road), litter and bags,
boarded windows and broken doors (BuildingGen), some buildings partly fallen, no street lights or
lit windows at night, no civilians, no garrisons. Bandit camps (hostile survivors) stand in for
some of the compounds.

## S7: deeper survival

Infection from bites (a slow fever; antibiotics hold it, a cure is rare), boiling or purifying
water, cooking, crafting basics (bandages from cloth, a spear, barricades), sleeping to pass the
night at the safehouse.

## Performance

Live zombies are AI soldiers: LIVE_CAP keeps them under the fight case's AI count (32). Their
brain is lighter than SquadAI (no tactics, no cover search): one sight check and one path every
THINK_S (Proposed 0.4 s), less when far. The crowd costs what animals cost. `DynamicSim` sleeps
the rest. A survival case joins perfcases once S3 lands.

## Tests

`survival` suite: the menu's New world hosts the safehouse with the starter kit; needs drain
and eating fills them; a zombie hears a shot, walks to it, sees, chases and bites; a headshot
kills it, body shots take the pool; death respawns at the safehouse with the body left where it
fell; a survivor's want is met and he joins; a crossing saves the zone and the world and Continue
puts it back.
