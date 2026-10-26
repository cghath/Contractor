# Contractor: Fallen: condition and wear

Calls 120-123 (docs/survival.md), with call 38 (durability), 43 (improvised guns jam more) and
31 (vehicles). Built on `claude/survival-wear`. Every number here is **Proposed**.

## Where the build is

- 2026-10-26: weapon, ammo, clothing and vehicle wear built; see the CHANGELOG's entry and the
  verdict in docs/survival.md's "Where the build is".

## The model

Every item that wears keeps a `condition` 0-100 in its item state (`Wear.KEY`); a vehicle keeps
its wear in its meta (`"wear"`). Absent reads as 100, so items from before and everything outside
a survival world are as new. Wear only runs in a survival world on the host (`Wear.enabled()`;
tests set `Wear.force`). The host's tick (`Wear.server_tick`, from
`Survival.server_tick_survivors`, every 10 real seconds) steps the slow parts.

## Guns and melee (`WeaponCondition`, call 120)

- A shot wears 0.08 (x2.5 wet, x3 improvised guns, tag `improvised`). A gun gets wet in the rain
  outdoors, in soaked clothes, wading or swimming; wet, it rusts 0.25 a world hour and dries in
  about 4 hours out of it.
- Under 70 a shot can jam: chance 0.15 x ((70 - c) / 70)^2 (x1.25 wet, x3 improvised). A jam
  fails the shot and sets `jammed`; R clears it (3 s, 1.5 s from firearms 3, 1 s from 6).
- At 0 it's broken: it won't fire until a **Gun Repair Kit** (firearms 2, 40 s, back to 45%).
- **Gun Cleaning Kit** (10 uses): 20 s (x0.75 from firearms 3), +30 up to 85%; with a **Gun Oil**
  carried (used up) +50 up to 100%; dries and unjams. Gun Oil alone: a wipe, +8, dries.
- Melee: a swing wears 0.12. A blade cuts as new from 50, x0.7 at 20 and under; a blunt weapon
  x0.85 worn to nothing. **Whetstone** (30 uses): 8 s, +50. Duct tape on a blunt weapon is in
  the API (`server_tape`) but duct tape isn't a usable item yet.
- An axe or hatchet loses 0.05 a second of felling; under 50 it fells slower, x1.6 at 0
  (`Trees._tool_x` reads `WeaponCondition.tool_mult`).

## Ammo (`AmmoCondition`, call 121)

- `condition` on a magazine's or loose stack's state; loaded, the gun's state holds it as
  `ammo_cond` (`Inventory.reload` moves it in and the old magazine takes the old one out).
- Misfire (a dud: a click, jammed, R clears) chance 0.25 x ((85 - c) / 85)^1.5 under 85.
- Found ammo (WorldCache seeding) rolls 85-100 under a roof, 25-75 in the open.
- Lying outdoors in the rain it loses 3 a world hour; under a roof (a built one too: anything
  overhead within 4 m) it keeps. Carried, only wading/swimming soaks it (6 an hour).
- Hand-loaded rounds are 90 (`AmmoCondition.reloaded_state()`, for the reloading bench).
- The inventory shows it from firearms 2 ("clean", "tarnished", "corroded", "badly corroded").

## Clothes (`ClothingWear`, call 122)

- Worn, a piece loses 2 a world day / its `durability` (x1.5 in the rain for head, outer and mid
  torso and legs; x2 wading for legs and feet; boots x1.5 walking; x0.2 asleep).
- A melee blow on a covered part tears the outermost layer there by 6.
- Under 60 a piece keeps less of its warmth and wet_resist (down to 40% at 0; `Clothing.layers`).
- Worn-out boots (20 and under) or bare feet on the move build sore feet (0.15 an hour); they ease
  0.1 an hour otherwise; at worst stamina comes back 25% slower (`Needs.stamina_mult`).
- **Needle and Thread** (8 uses): 15 s, +35 to the most worn piece. Washing stays Hygiene's.

## Vehicles (`VehicleWear`, call 123)

- Per km: engine 0.02, tyres 0.04, battery 0.01; a flat battery (0) stops it starting until a
  new one; under 40 the engine is slower (x0.75 at 0).
- Punctures per 100 m by the ground (asphalt 0.2%, dirt 0.6%, rock 3%, rubble 5%), 15% within 6 m
  of a wreck, x3 on tyres under 25. A flat: top speed x0.4 until a **Tyre Patch Kit** (25 s,
  x0.7 from mechanics 2; Use it within 5 m of the vehicle).
- Fuel age: found fuel is 90 days old; fresh for 60 days, fully stale 180 later; refuelling blends
  the tank's age. Stale fuel stalls a driven engine for 3-6 s (0.4% a second at worst).
- The service's repairs reset the wear (engine parts: engine to 80; a wheel: tyres and the flat;
  a battery: battery).
- A settlement's "maintain" job services the vehicles in its radius (engine and battery +5 an
  hour, to 90). Horses' hooves wear by distance (a stub for a farrier later).

## Recipes and loot

Gun oil from engine oil (firearms 1, x3), needle and thread from rags and copper wire, tyre
patches from a bicycle inner tube (mechanics 1, x2). The homes' loot table has the new items.

## Hooks in shared files (a line or two each)

`Soldier._server_fire` (jams, duds, shot wear), `Soldier._server_reload` (R clears a jam),
`Inventory.reload` (ammo condition), `MeleeWeapons.server_action` (dull blades), `Melee._hit`
(tears), `Clothing.layers` (torn clothes), `Needs.stamina_mult` (sore feet), `Trees` (worn
axes), `Vehicle` (`_use_fuel`, `can_drive`, `top_speed`, `server_refuel`, `server_repair`,
`server_set_battery`), `Consumables` (tool items), `SettlementJobs` (the mechanic),
`WorldCache.server_seed` (found ammo), `InventoryScreen._condition` (the readout),
`Survival.server_tick_survivors` (the tick).

## What's left

- Gunsmithing at firearms 8-9 on a gunsmith bench (call 85): no recipes yet; the repair kit
  stands in. Gun parts as loot exist (`weapon_parts`) but aren't used here.
- AI guns don't wear (only the players' `_server_fire` path); companions never jam.
- Loose rounds loaded into a magazine don't carry their condition (`Inventory.load_rounds`).
- Shotgun shells have no condition (tube guns skip duds).
- The dead's kit and ground loot don't roll a found condition yet (only WorldCache seeding).
- No inventory "Inspect" panel line: the condition shows in the item's row readout.
- Suppressors wearing out (call 38), a gun blowing up (call 43), the farrier job.
