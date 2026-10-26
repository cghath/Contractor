# Contractor: Fallen: mounts (horses, bicycles, carts)

Calls 31 and 35 (docs/survival.md), people section 6 (docs/survival_people.md: riding, the
tied horse guarded). Built on `claude/survival-mounts`. Every number here is **Proposed**.

## Where the build is

- RUN_STATUS_LINE

## What's built

- **`Mount`** (`scripts/vehicles/mount.gd`): a `Vehicle` of kind `"mount"` (numbers in
  `data/mounts.json`, read by `VehicleSpecs` beside the vehicles but kept out of
  `VehicleSpecs.models()`, so the campaign's lists, armour ratings and motor pool never see them).
  Seats, getting on and off (V or the seat's menu), the seated views (first person at the saddle
  with the horse's head ahead; B for third person), the packs (the cargo hold and its Left Ctrl
  point), the AI's driving (`VehicleAI`, `SquadDrivers`), replication and the zone save are the
  vehicles'. Its own:
  - **the drive**: no wheels or engine; it eases toward a speed, follows the ground under it by a
    ray, turns on the spot (a horse) or only rolling (a bicycle);
  - **bicycle**: 7 m/s on asphalt, x0.8 on dirt, x0.4 on grass, x0.2 or less in sand, mud, rock,
    snow, rubble (useless cross-country); no fuel, one rider, silent; meeting something hard over
    5 m/s it falls and throws its rider, half the time with a flat (a `bicycle_tube` fixes it;
    "Stand it up");
  - **horse**: walk 1.7, trot 4.2, gallop 12 m/s (x0.9 on asphalt, x0.5 in mud); stamina 0-100:
    a gallop spends 1.1/s, a trot 0.06/s, walking or standing gives it back; under 8 it won't
    gallop; one rider and packs (120 L, 90 kg); `feed` and `water` 0-100, a day's need each,
    grazing back 60 feed and 30 water a world day while loose on grass or dirt; under 25 of either
    it won't gallop; 3 days starved or 2 parched it dies; a sack of oats (`horse_feed`) gives 50,
    a litre of water 4, open water within 8 m fills it; 100 HP of its own (rounds by energy,
    bites 6 each); dead, it lies on its side with its packs;
  - **spooking**: a shot within 15 m (`Survival.server_noise` -> `Mounts.on_noise`) or the dead
    within 15 m (half the time a second) bolts it 2.5-4.5 s away from the cause (6 s between);
    a rider below fieldcraft 2 (a shot) or 1 (the dead) is thrown (a 1.4 m fall); its own
    rider's shot bolts it a quarter of the time below fieldcraft 3 and never throws him; tied it
    can't bolt; minded ("Stay with the horses") it shrugs off 60%;
  - **noise**: hooves heard 20 / 35 / 60 m by gait; a cart 30 / 45 m on hard ground, half on
    soft; a bicycle nothing;
  - **the dead** within 1.9 m bite a horse every 1.3 s each; bitten, it screams (heard 60 m);
  - **wild horses** wander about their spot; caught with a `rope` and fieldcraft 1 by staying
    within 3.5 m for 4 s (the rope is used up, fieldcraft XP); tied, a horse stays;
  - **cart**: walk 1.5, trot 3.6 m/s behind a hitched horse (x0.8 on grass, x0.35 in mud);
    1200 L / 600 kg stash; a driver and a bench; "Hitch a horse" takes a tame, loose horse within
    6 m of the shafts (it rides in them, its wind spent pulling); dismounted and left, it stays in
    the zone save with its stash and its horse;
  - **from the saddle**: the rider fires whatever is in the sidearm slot and swings a one-handed
    weapon (`ffv_seat`; `Soldier._server_melee` lets a mount's rider swing), never a long gun.
- **`MountArt`** (`scripts/vehicles/mount_art.gd`): voxel models at 5 cm in VehicleArt's canvas
  (a horse 1.6 m at the withers, coat by scheme: bay, chestnut, grey, black; a bicycle in red,
  blue or green; a farm cart with shafts), a box far LOD past 70 m, a gait bob, lying on the
  side when dead or fallen.
- **`Mounts`** (`scripts/survival/mounts.gd`, a node under each SurvivalLevel): places the zone's
  mounts by stable ids once the save is loaded (2 wild horses and a cart at the start farm; at
  other farms 1 horse and a cart half the time; 1-2 bicycles at villages and towns), so the save's
  wins; the shot hook; companions mounting up (one free mount each, walking up and getting on;
  then SquadDrivers' column has them follow the player's mount; with no mount each they walk);
  "Stay with the horses" (the nearest companion holds by a tied horse, it's minded, he calls out
  the dead within 30 m, and stands down when ordered otherwise).
- **The menu**: a Mount is `InteractionMenu`'s `"mount"` target kind: Ride / Drive the cart / Sit
  on the bench, Catch it (rope), Feed, Water it, Tie it here / Untie, Stay with the horses, Hitch /
  Unhitch, Stand it up, Fix the tyre, Everyone mount up, Check.
- **Riding controls**: W/S, A/D as a vehicle; the mouse wheel steps walk/trot
  (`PlayerInput.wheel_pace` -> `Mount.local_wheel`), Shift gallops; the HUD readout shows speed,
  gait, wind, hungry, thirsty, bolting.
- **For the world lane**: `Mounts.server_spawn(level, model, pos, yaw, {"wild", "id", "scheme",
  "faction", "save"})` and `Mount.counts_in_zone(level)` (`horse`, `bicycle`, `cart`, `ridden`,
  `wild`).
- **Items**: `rope`, `horse_feed` (Sack of Oats), `bicycle_tube`, in the homes' loot.

## Hooks in shared files (a few lines each)

`VehicleLayer._make` (a mount model makes a Mount), `VehicleSpecs` (data/mounts.json),
`VehicleArt` (schemes, MODELS, `_shape_for` asks MountArt), `InteractionMenu` (the MOUNT kind),
`PlayerInput.wheel_pace` (gaits), `Soldier._server_melee` (swing from the saddle),
`Survival.server_level_ready` (installs Mounts) and `Survival.server_noise` (spooking).

## What's left

- Riding poses: the rider sits the vehicle seat pose (legs forward), not astride; no leg animation
  on the horse (one voxel mesh with a bob).
- Jumping low fences: not built (a horse walks through anything under its body box, 0.85 m).
- Companions don't fire from the saddle (their brain is off while seated, as in vehicles), and
  the talk menu has no "Mount up" line yet (the mount's menu and the command menu's Mount up do it).
- Horses on ZoneAnimals (herds, predators taking foals) and the world sim's groups riding in the far
  tick: the API is there, the world lane wires it.
- A dead horse can't be butchered yet; no horseshoes, saddle or tack items; carts can't be built.
