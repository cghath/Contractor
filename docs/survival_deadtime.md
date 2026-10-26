# Contractor: Fallen: the dead over time

Calls 112 (decay stages), 114 (the dead wear what they were), 115 (nests and roosts) and 140
(climbing rules in full) from docs/survival.md. Built on `claude/survival-deadtime`. Every number
is **Proposed**.

## Decay stages (`DeadDecay`, scripts/survival/dead_decay.gd)

- **The world's date.** The fall came `fall_weeks()` before day one: 2-8 weeks, from the seed
  (state `fall_weeks` overrides). A world day is `STORY_DAYS` (about 9.1) of the story's days, so a
  world year of four 10-day seasons is a story year.
- **Age.** Each of the dead has a `turned` time on the cold-kept clock (`kept_since`: winter's
  world days left out, because the frozen don't rot and the thaw brings back fresh-looking ones).
  Its decay runs 0..1 from `FRESH_DAYS` (14) over `ROT_DAYS` (120) of age.
- **Stages.** fresh (< 0.25), worn, old (>= 0.6). From fresh to old: pace x1.15 to x0.8, pool
  x1.0 to x0.55 (a fresh one at its kind's full pool), the bite x1.25 to x0.8, limb hits on the pool x1.0 to x1.6 (they come apart).
- **The mix.** A new head is fresh (turned in the last weeks) at a share that falls from 0.9 at
  the fall by 0.25 a month to 0.1; the rest turned in the fall's first weeks. `count_mult`: the dead
  about grow from x0.9 to x1.3 over 8 months (`Survival.dead_near`).
- **The look.** Body metas: `dead_turned`, `dead_decay` (the stage, for the model), `dead_decay_x`.
  The plain-clothes variant is greyed and dirtied by stage, and the skin goes from flesh-grey to
  grey-green to bone (`DeadDecay.look`, `SKIN`).
- **The crowd.** ZoneDead heads carry `turned` and `origin` (rolled where they're put down, kept
  when a head becomes a body and back: `ZoneDead.carry`, `DeadDecay.carry`).

## The dead wear what they were (`DeadDress`, scripts/survival/dead_dress.gd)

- **Origin by site.** `site_at`: a generated town's lot under it (clinic, police, warehouse:
  ZoneModules' town cache now keeps `lots`), else the module's base type. `ORIGINS` has each site's
  mix: hq 75% soldiers, a checkpoint soldiers and cops, a clinic 60% doctors, a police station 70%
  cops, a farm farmers, factories and garages workers, a town mostly townsfolk with a few of each.
  The hazmat kind is always a decon-team soldier.
- **Look by origin.** The plain-clothes variant in the origin's colours (`CLOTHES`): soldier olive,
  cop navy, doctor whites and scrubs, worker hi-vis and overalls, farmer work clothes. These are
  plain colours, not the factions' camo kits: the zombie body is the civilian voxel body.
- **Kit on the body.** `KITS` go into the body's Inventory when it spawns (`kit_roll`, then
  `server_kit`), so the corpse is looted like any other body. A soldier has an assault pack, a light
  carrier 60% of the time (a steel plate in it 50%), a helmet 45%, and his M4 only 25% (see the early
  loot curve below). A doctor has a hydration pack, an aid bag, a suture kit, antibiotics and bandages. A cop has
  cuffs and, 30% of the time, a Glock with 0-6 rounds in it. Workers, farmers and townsfolk carry a few small things. Weapons are
  stowed, never in a weapon slot: the dead don't use them.
- **The tell.** `tell(level, pos)`: the origins of the dead about a place say what it was, for
  example "Uniforms and plate carriers among the dead: this was a military post."

## Nests and roosts (`DeadNests`, scripts/survival/nests.gd)

- **Where.** One nest per site of a `NEST_SITES` base type, with 6 to 14 heads scaled by the "dead"
  option: churches, mosques, factories, schools, garages, offices, the harbour, the airfield, the
  fuel depot, the military's hq and qrf barracks, and a town's warehouse (or the middle of the town
  when it has none). State lives in `Survival.state()["nests"][zone]`. The host ticks it every 2 s
  from ZoneDead.
- **By day** (06:00-19:30) the heads are only a count inside. The site's dead outside are halved
  (`outside_mult` in `dead_near`).
- **At dusk** they pour out of the door as ZoneDead heads tagged with the nest, 0.4 s apart,
  walking 12-35 m out.
- **At dawn** they walk back and are counted in. Any still out 2 h after dawn go in at once.
- **Entered by day.** When a player comes within 15 m, the heads inside become bodies packed by the
  door, **dormant**: their sight works at 35% and sounds give 30% of their awareness, and they don't
  wander. A silent kill works. A sound at 0.9 or louder (a shot, a scream: the screamer special), or
  one of them noticing him, wakes the whole nest at once, and any still inside pour out after them.
  A nest's body that ends up far from everyone by day goes back inside.
- **Cleared.** When the last of a nest's heads (inside, out in the crowd or as bodies) goes down,
  the nest is cleared: a `bonus` flag marks its loot as untouched (`loot_bonus`, `take_bonus`), and a
  journal line is written. It refills by 2 heads a world day, slower where the zone's cells are
  thinned.

## Climbing rules (ZombieAI, call 140)

- `can_climb(kind)`: none of the dead climb ladders, walls or roofs. Platforms, ladders and roofs
  are safe. The only way up is a pile at a wall (Sieges).
- `can_get_up(kind, h)`: everyone gets up a 0.45 m step; a runner vaults up to 1 m (the same
  `VAULT_M` as Sieges).
- `can_pass_gap(kind, gap)`: a crawler gets through an opening from 0.25 m high; everyone else
  needs 1.5 m.
- Paths use `NAV_LAYERS` (the walk layer). `CLIMB_LAYER` is kept free for ladder and climb links
  if a navmesh ever carries them.
- One chasing a man up out of reach (more than 1.5 m above it and within 3 m) stops under him,
  faces him and piles (`under_ledge`, the `under_ledge` meta). It can't bite more than 1.7 m up.

## Early loot curve (`FoundLoot`, scripts/survival/found_loot.gd)

The Captain's playtest (2026-10-26): "got a gun off a mil zombie in the first 5 minutes". Call 38
says ammo is scarce and guns common-ish but a real find; a working rifle off the first of the dead
broke the early game. Built on `claude/survival-startloot`; every number is **Proposed**.

- **The zone's tier** (`zone_tier`): links from the start zone on the region map (0 the start zone,
  up to 3), +1 in the city region.
- **Origins** (`DeadDress.roll_at`, `FoundLoot.armed_mults`): the open country's mix is now 2%
  soldiers and 3% cops (was 10% soldiers, no cops). Outside military places (hq, qrf base, outpost,
  checkpoint, comms, airfield, fuel depot, compound) the soldier and cop shares are x(1 + tier), the
  difference to or from the townsfolk; in the start zone no soldiers turn within 250 m of the farm
  (`START_CLEAR_M`) unless a military place is there. Military places keep their own mix.
- **What a soldier carries** (`KITS`, `kit_roll`): the rifle 25% of the time (taken or lost), its
  carrier 60% (a plate in it 50%) and a helmet 45%. A kept rifle is weathered
  (`WeaponCondition.found_state`: 10-45%, a fifth rusted through to 0, 45% jammed, wet; one of a
  nest's, lying inside, 40-85% and 10% jammed) with 0-8 rounds in it and 0-1 spare magazines of 0-8
  rounds, their condition low out in the weather (`AmmoCondition.roll`). The decon teams' rifle 25%
  too (was 40%). A cop's pistol 30% with 0-6 rounds, no spare (was always, with a full spare).
- **Boxes, first roll** (`first_roll`, from `WorldCache.server_fill` for WorldValuables' boxes:
  site boxes, field caches in the open, strongboxes): within 250 m of the farm a box not at a military
  place holds no gun (taken by whoever left); a box in the open elsewhere keeps its gun 35% / 60% /
  80% / 100% by tier; a gun that's there gets a found condition (dry 40-85%, in the weather as on
  the dead). Bunker rooms, events' crates and survivors' stashes pass as rolled; a refill
  (`LootStates`) still rolls new guns.
- **Ground loot** (`ground_state`, ZoneLevel's module loot): guns and ammo lying about get a found
  condition by where they lie.
- **The tables** (data/loot_tables.json): no firearm in the commonest tier of a home or a stash (the
  Makarov and the TT-33 uncommon at home; the Lee-Enfield and the Remington 870, the plausible
  civilian finds, rare; the AKM, Type 56 and M70 out of homes, they stay in stashes, caches and the
  military's boxes); loose rounds in homes and stashes halved. The TT-33's and the Lee-Enfield's
  rarity follow the loot suite's rule (uncommon). A home box holds a gun 3.5% of the time (was 7.2%)
  and 2.3 rounds on average (was 4.9).
- **The start.** The starter kit is a combat knife and a knife (no gun); the cold open's gifts are
  a crowbar, a machete, a hatchet or supplies. Unchanged.

**Before and after** (the deadtime suite's probe: world seed 777, everything within 300 m of the
farm, the first 30 of the dead spawned 45-300 m about it; R2712 before, R2713 after):

| | Before | After |
|---|---|---|
| Guns in boxes and on the ground | 1 (an AKM in a field cache, working) | 0 |
| Rounds in boxes and on the ground | 90 | 60 |
| Soldiers among 600 origins about the farm | 63 (10.5%) | 1 (0.2%; cops 10) |
| Of the first 30 dead, carrying a gun | 3, all working, 270 rounds | 0, 0 rounds |
| Expected guns on the first 30 dead | 3.2 (90 rounds each) | 0.16 (8 or fewer rounds, a fifth broken) |

Away from the farm in the start zone's open country about one in 70 of the dead carries a gun
(0.02 x 25% + 0.03 x 30%), most of them worn, near empty or jammed; in a tier-2 zone about one in
25; at a military place most of the dead are soldiers (an hq 75%) and a quarter of those kept the rifle.
A working gun with ammo is a find of the first hour (a cop's pistol off the road, a stash, a
village's rare box), and the military places stay the reward.

## Left out

- Building-level origins inside cities: this works where BuildingGen gives the lot types (town and
  city blocks). There are no hospital or police landmarks.
- A loot pass that reads `loot_bonus` (the flag and its API are there).
- The far tier's look by stage and origin: crowd stand-ins are drawn by kind only.
- Torn-off limbs as visuals: decay only changes the damage share.
- Ladder links in the navmesh: the game has none yet.
