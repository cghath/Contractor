# Contractor: Fallen: fauna and flora

Calls 42 (hunting, fishing, foraging), 100-107 of docs/survival.md. Branch `claude/survival-nature`.
Every number below is **Proposed**.

## Where the build is

- Built (2026-10-26): wildlife, predators, infected animals, migration and fishing, crows/flies/rats/cats,
  regrowth, foraging, trees, wildfire; the `nature` suite. **R2670 PASS** (nature, survival, seasons).

## What's built

All of it lives in new files under `scripts/survival/` and two data files; the shared files carry one-line hooks.

| Piece | File | What it does |
|---|---|---|
| The node | `nature.gd` (`Nature`) | On every peer at the survival level (SurvivalLevel adds it). Host: ticks the animals (0.25 s), the fire (1 s), the slow smell pass (5 s), each world hour (snares, rats, flies, raccoons; a clock jump over 12 h is not lived through), each world day (stumps regrow, regrowth); sends animals, crow flocks and burning cells every 0.5 s; one Area3D per animal for rounds. Peers draw MultiMeshes (`NatureArt`). Data loaders `Nature.fauna()`, `Nature.flora()`; state in `Survival.state()["nature"]`. |
| Wildlife | `wildlife.gd` | Records far (host), drawn near. Laid out per zone and season by habitat, never within 150 m of a player. Prey flees the living (45 m for deer, half for a sneaking man), the dead and noise; herd runs together; a running herd is a tell (companion line, else the nearest player). `zombie_hunt` (ZombieAI hook): the dead go after an animal within 20 m (12 at night), bite it down in reach, else walk to a carcass/blood they smell. `smell_sources()`: carcasses 72 h, blood 6 h; the crowd's heads within 60 m drift there. Shots (`server_shot`), snares (6%/h a rabbit, +15% a fieldcraft level), tracking (fieldcraft 3), butchering (a blade: deer 4 raw meat + a hide), `calendar()` (fieldcraft 2 or a field guide; fish at 4). |
| Predators | `predators.gd` | Packs hunt within 80 m: anyone at night, a lone man (no one within 25 m) by day for a pack of 3+, horses at night, livestock (ZoneAnimals); bear within 15 m any time; bites (wolf 8, dog 6, bear 25 trauma) every 1.5 s; give up past 120 m / 60 s. |
| Infected animals | `infected_animals.gd` | Dogs and wolves turn (15% / 10% of packs carry one): run 9.5-10.5 m/s (a man sprints 6), 0.45-0.55 m high, heard 3-4 m; chase the living within 35 m (25 at night), bite 10-12. `bite_companion_dog(rec)` is call 94's stub flag. |
| Migration, fishing | `migration.gd` | `where(sp, season)`: deer to the valleys in winter, birds gone, the bear denned. Fish an hour with a rod by water and season (river: spring 1.0, summer 0.7, autumn 0.9, winter 0.2); a net 2.5x; through the ice 0.3x; +8% a fieldcraft level; timed on the world clock (`server_start_fishing` / `server_stop_fishing`). Settlement hunters: autumn 1.2x, winter 0.5x. |
| Crows, flies, rats | `scavengers_fauna.gd` | Crows over bodies under 72 h (3 a body, up to 14), drawn circling 18 m up, seen 700 m. Flies on bodies over 12 h: at the settlement +1 pressure an hour per full swarm and dysentery for settlers. Rats at 02:00: 6% of open stores' food (x2 in a city, x0.5 with a cat), 5% a settler sickens; raccoons at 03:00 take 2. `Settlement.data().stores_closed` (a storeroom piece, later) stops them. |
| Regrowth | `flora.gd` | `regrowth(day) = 1 - exp(-day/120)`; grass up to 1.8x, up to 60% of roads growing over; the settlement's radius stays clear. ZoneScatter's ground cover reads `Flora.grass_now` / `road_now` (1 and 0 outside survival). |
| Foraging | `foraging.gd` | Spots on scrub, thickets and trees, the plant fixed by position. Berries (summer), mushrooms (autumn), nettles and wild garlic (spring), willow bark (all year), yarrow (summer/autumn), wild honey (a hive, stings). Nightshade (tell at fieldcraft 2) and the death cap (4) come as their look-alikes for a novice, `{"poison"}` in the entry's state; a field guide counts +2. Eaten (`Survival.server_eat` hook), a poison sets Needs' food poisoning (18 h / 48 h) and a `poison` record for the medical lane. |
| Trees | `trees.gd` | Species by position (conifers are pine; oak 40%, birch 30%, apple 15%, hedgerow 15%). Felling with an axe (a hatchet 1.8x as long): oak 90 s, birch 50, apple 45, pine 35, hedge 20; a chop every 2 s heard 30-45 m; planks (oak 8) and firewood (green 5 days); a stump (ZoneScatter draws 12% of the trunk); regrows after 20 days. The settlement's cut wood (`WorkOrders`) fells the trees within 2.5x its radius. Apples in autumn. |
| Wildfire | `wildfire.gd` | 8 m cells; dryness summer 1 (0.8 out of the heat), autumn 0.5, spring 0.3, winter/rain/snow 0; fuel 1 for grass + 0.25 a tree + 0.1 a bush (none on water, roads, fields, the sea, firebreaks); heat 0.12/s from each burning neighbour, x(1 + 1.6 * downwind share * wind/5), at least 0.1x upwind; catch at 1; a cell burns 40 s a unit of fuel. Wood blocks lose 5% a second, the living 2 trauma a second, the dead catch fire (their pool burns 0.5 a second; they keep walking). Smoke: pressure every 30 s and one world sim event a fire. Seasons' summer roll (15% a day) lights one 150-400 m from the players. |

Hooks in shared files: `SurvivalLevel._ready` (adds Nature), `Survival.server_noise` (`Wildlife.server_noise`),
`Survival.server_eat` (`Foraging.on_eaten`), `ZombieAI._decide` (`Wildlife.zombie_hunt`), `WorkOrders` cut wood
(`Trees.settlement_cut`), `SettlementJobs` hunt (`Migration.hunt_x`), `Seasons._wildfire_roll` (`Wildfire.server_natural`),
`ZoneScatter` (`_regrown`, `_grows_through`, stumps in `visual_parts`, `redraw_at`, a "tier" meta on cell nodes),
`Settlement.ITEM_CATS` (firewood), items/prices/recipes data.

## What's left

- No player-facing interactions yet: butcher, set/check a snare, fish, forage, fell and pick fruit are host APIs
  (`Wildlife.server_butcher`, `server_set_snare`, `Migration.server_start_fishing`, `Foraging.server_forage`,
  `Trees.server_fell`, ...) waiting for the interaction menu's entries; tracking marks aren't drawn.
- Bows (a quiet kill) and molotovs (`Wildfire.server_ignite(level, pos, "molotov")`) wait for their items; lit
  campfires call `Wildfire.campfire_risk` once a lit fire entity exists.
- Pieces of the buildings other than wood blocks don't burn; houses' wooden walls (module voxels) don't catch.
- Ivy on walls and saplings in yards (only grass and roads regrow); the foliage index still counts a felled tree's crown
  for concealment; felled trees keep their trunk collision (a stump that blocks).
- Animals walk straight lines (no navmesh, no ray check), nothing swims; water as terrain (call 108) is not built.
- Livestock (chickens, goats, cows penned and fed: call 42's fourth part), tanning hides, the dead's interest in
  the crows themselves, a cat as an item.
- Poison's trauma (`n.poison.trauma`) is a record for the medical lane; nothing grinds it down yet.
