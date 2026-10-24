# Combined arms: armour, the AI commander, high command and invasions

**Status: design, 2026-10-21; phase A1 built 2026-10-22 (calls 74-92).** Written for the build sessions to work from. Every call is made
here (listed in "Calls made" at the end); every number is **Proposed** and lives in a data file or
a named constant so it can be tuned without code. Checked against `claude/ai-driving` `e6ebcf4`.

What the Captain asked for (2026-10-21, ~23:10 to ~23:50 CDT):

- "i want to see armored gameplay with a good ui and first person and third person hud and ui",
  "im talking the tanks and apcs we designed", "were going to need semi realistic vehicle
  gameplay", "we want to have a level of detail comparable to WT while maintaining a fair balance
  in our gameplay", "we need the integration of known composite armors and era for certain upgrade
  packages etc", and "add improving blast and destruction effects for vehicle".
- "we need to start getting light armor into the game more", "we need the us to be in conflict
  with one of the rebel, cartel or such factions" ("ashen banner then kestrel if the us wins").
- "we need combined arms missions and such too, especially since were contractors for foreign
  entities and governments. there should be invasion missions in slightly larger zones" (about
  8 km), and "make it possible to purchase operations out of a fob that friendlies control".
- "we need good ai coordination and such still. on par with like HAL for A3 with lambs and vcom.
  with good integration for players to work with friendly forces. ie communication, making
  requests like for suppression or a medic etc. common sense stuff that would happen in real life",
  "we want to be very in depth here", "because this is where our gameplay starts to gain breadth
  and depth".
- "lets also make it possible to have 2 HC squads from the start", "make the hud for directing
  teams from the map logical and for gun teams allow players to select where they position the gun
  on the map with a cone of fire visible", "maybe the high commander mode is a camera in the 3d
  space that shows a marker where known friendlies and enemies are shown", "we need to start
  making some things contextual", and "i want nice modern uis with common sense and ease of use
  features".

Contractor learns from other games here and takes none of their code or names:

- **War Thunder** for the detail of armour: modules, shell physics, the x-ray hit analysis.
- **Arma Reforger, Squad and Steel Beasts** for where the vehicle feel sits: crew jobs, logistics,
  gunnery that needs a rangefinder.
- **HAL (Hetman Artificial Leader), LAMBS and VCOM** for an AI commander that sees through reports
  and gives groups roles, and for groups that help each other.
- **The Arma 3 high command bar and Zeus** for commanding squads from a camera.

## How to read this doc

- **Built** means it is in the code today, with the file and function named. **New** means a file
  or function this doc adds. **Replaces** says what stops being used.
- Section 1 is the inventory of what we build on. Sections 2 to 8 are the design. Section 9 is the
  build plan: phases sized for one session each, with their files, tests and dependencies.
- Names we invented are original. Real equipment names (M1 Abrams, M829A3, Kontakt-5) are used as
  they are.
- Armour and penetration figures are game values **based on** public estimates, rounded and tuned
  for balance. They are not claims about real classified protection levels.

## Contents

1. What exists to build on
2. Armour
3. The AI commander
4. Players and friendly forces
5. High command
6. Combined arms and invasion missions
7. Light armour across the factions, and US forces in the living war
8. Staging from a friendly FOB
9. Build plan
10. Calls made

## 1. What exists to build on

### 1.1 Vehicles and damage

| Piece | Where | What it gives us | What this doc changes |
|---|---|---|---|
| Vehicle body | `Vehicle extends RigidBody3D` (scripts/vehicles/vehicle.gd, 3,233 lines), Jolt, box colliders, own raycast suspension (`_wheel_forces` 1836), tracked skid steer (1904) | Host-authoritative physics, seats, fuel, fire, jobs, net pose at 30 Hz, saves | Physics gets terrain traction, slopes, rollovers and fording (2.8). Damage moves out to new modules (2.2). Main guns go through a new gun layer (2.7) |
| Vehicle data | data/vehicles.json: `armour` classes (soft to mbt, one `rha_mm` and `roof_mm` each), `round_tiers` (3 rounds listed), `guns` (m2hb, dshk, m240c, m240h), `models` | Every vehicle's boxes, zones, seats, turret, points | Gains `plates`, `modules`, `packages`, `weapons`, `optics`, `crew` blocks (2.2-2.7). `armour` classes stay for small arms; tanks and IFVs read plates |
| Damage resolver | `VehicleDamage.resolve` (vehicle_damage.gd:61): tier vs `resists` for kinetic; `penetration_mm` vs `rha_mm`/`roof_mm` (+`ERA_MM` 300) for HEAT; no angle, no facing | A working pipeline from hit to zone damage | **Replaced** for vehicles with plates by `ArmourModel.resolve` (2.3). Kept as the path for soft vehicles and aircraft until each gets plates |
| Hitting the real hull | `VehicleHull.first_solid` (vehicle_hull.gd:186) marches the 5 cm voxels, turret and gun parts included | The exact entry point; the voxel face gives the normal | Kept: it decides where the round lands. The slope comes from the plate data, since voxel faces are axis-aligned (2.3.2) |
| Applying damage | `Vehicle._apply_damage` (2307), `_spall` (2339: 3-6 wounds to anyone within 2.5 m), `server_start_fire` (2359), `_fire_step` (2371), `_become_wreck` (2391) | Zone health 0..1, leaks, fire, wreck | **Replaced** by `VehicleModules` and `VehicleFire` (2.2, 2.10); `_spall` by the spall cone (2.3.5) |
| Launchers | `Launchers.server_fire` → `LauncherProjectile` → `Warheads.server_burst` (warheads.gd:160) → `Vehicle.server_take_hit`; `_jet_behind` (462) kills along 3 m | Javelin and NLAW top attack, guidance, backblast | Warheads gain fuze, ricochet and spall keys and resolve through `ArmourModel`. `_jet_behind` is replaced by the module path (2.3.5) |
| Turret | `VehicleTurret` (vehicle_turret.gd): traverse and elevation limits and rates, `split()` lifts turret voxels; yaw in the vehicle frame (no stabiliser) | Turning turrets on the M-ATV, MaxxPro, AAV, technical, tripods | Gains world-frame stabilisation, drives that can be damaged, and turret specs for the **Bradley and Abrams, which have none today** (their gun is fixed and fires along the view) |
| Mounted guns | `server_fire_gun` (3005): rpm gate, `take_feed` from the cargo hold, `Ballistics.fire` | Belt-fed MGs | Main guns, autocannons, ATGMs and grenade launchers go through new `VehicleWeapons` (2.7) |
| AI gunner | `AavGunner` (scripts/supports/aav_gunner.gd) on every gun seat; needs Spotting time before firing | Any gun seat manned by AI | Extended for main guns: ammo choice, lasing, lead (2.7.7) |
| AI driving | `VehicleAI` (drive_to, follow, detours), `SquadDrivers` (take wheel, mount up, columns, `DriveContact` through/halt/dismount), `ConvoyColumn`, `RoadRoute` | Columns, road routes, contact drills | Armour behaviours: hull-down, keep the front to the threat, reverse out, ford checks (2.13) |
| Water | `AavWater` (aav_water.gd): buoyancy, drag, waterjets; `throttle()` cuts drive deeper than `ford_m` (default 0.8, **set on no model**); `ZoneWater` rivers and fords (`FORD_DEPTH_M` 0.45); `ZoneBridges` concrete, truss and foot bridges with collision and blast damage, **no load limits** | Floating AAVs, rivers, fords, bridges | Fording depth per model, flooding, current, bridge load classes (2.8.4) |
| Repair and fuel | `VehicleService` (repair_kit, engine_parts, track_links, spare_wheel, vehicle_battery; jerrycans), `MotorPool` (repair quote, days, fuel at 2/L) | Field and workshop repair | Per-module repair rules; heavy damage only at a FOB (2.9) |
| HUD | `Vehicle.readout_parts` (3098) drawn by `Hud.show_vehicle` (hud.gd:460): name, seat, speed, fuel, damage %, gun rounds | A text strip | **Replaced** by the 1P and 3P vehicle HUDs (2.12) |
| Camera | `VehicleCamera` (chase cam, `aim_point()` to 1,500 m); first person by default | 1P and 3P | Gains sight modes, zoom, thermal, commander's view (2.7) |
| Effects | One OmniLight and one orange sphere while burning; wreck tint | Something | **Replaced** by the destruction effects (2.10) |
| Art | `VehicleArt` builds the Bradley (25 mm, TOW box, coax) and Abrams (120 mm, loader's M240, CROWS) as voxels (`_bradley` 1352, `_abrams` 1457) | Models | Turret and gun voxel groups tagged so `VehicleTurret.split()` and the destruction effects can use them |

Neither the Bradley nor the Abrams is spawned anywhere today; the vehicle range (`VehicleRange`)
parks only the M-ATV, MaxxPro, technical and AAV. Five technical variants (`technical_zu23`,
`spg9`, `m40`, `rockets`, `zpu`) are defined with an empty gun.

### 1.2 AI, command and supports

| Piece | Where | What it gives us |
|---|---|---|
| Soldier brain | `SquadAI` (squad_ai.gd): intents, tactics, casualty care, morale, fire lines, `_friendly_in_line` (5169), callouts | The individual layer the commander never touches directly |
| Squad | `Squad` (squad.gd): the group's picture (`known`, `clusters()`), orders (`order_suppress`, `order_flank`, `order_assault`, `order_fall_back`, ...), formations, combat modes | The unit the commander tasks |
| Squad tactics | `SquadTactics` (tactics.gd): HOLD, SUPPRESS_FLANK, ASSAULT, CLEAR, DEFEND, BREAK_CONTACT, CASUALTY, SEARCH; `elements()`, `flank_route()`, `overwatch_spot()`, `fall_back_point()` | Contact drills and reusable geometry |
| Doctrine | `Doctrine` + data/doctrines.json (wired weights), `SquadTactics.DOCTRINES` biases | Faction fighting styles |
| Spotting | `Spotting` (awareness over time; `TOLD` 0.5 for a report) | Fair knowledge |
| Crew-served | `GunTeam`, `MortarTeam`, `StaticWeapons`, `LauncherAI` | Movable MGs, mortars, AT |
| Enemy commander | `EnemyCommand` (enemy_command.gd, hot zones): a picture from `Alert` reports with delay, combat power (CP), finite reserves, operations (hold, reinforce, probe, counterattack at 3:1, contain, hunt, consolidate, reoccupy), decapitation | The seed of the per-side commander (3) |
| Enemy report net | `Alert`: report delays 60 to 15 s by discipline, x1.5 under fire, x3 comms down; LKP uncertainty grows 1.5 m/s | Latency for the enemy |
| Enemy executor | `EnemyResponse`, `Reinforcements`, `Pressure`, `HotZoneOps`, `VehicleQrf` | Spawning, routes, QRF technicals |
| Friendly elements | `AlliedTroops` (allied_troops.gd): up to 2 elements (8-man rifle, 4-man weapons), host-only orders (move, hold, defend, assault, flank, follow, regroup, fall back, mount, drive, dismount), map submenu per element; `order` and `point` are the only record | A working first high command, no lifecycle or reports |
| Hero squads | docs/high_command.md (Proposed, not built): order records with a lifecycle, `SquadOrders`, sectors, `safe_to_fire`, CE, company net, map Command mode | The plan for section 5, adopted here |
| Supports | `Supports` registry; heli resupply/transport/extraction/medevac/cargo, fire support (81 mm, 105 mm with danger close), UAV, AAV, allied troops, rebels; paid by `Economy.server_pay_support` | The answerers for many requests (4) |
| Menus | `CommandMenu` (number trees), `InteractionMenu` (ACE3-style radial on Left Ctrl), `MapView._open_menu` (right-click), voice orders by typed phrase | What the contextual pass reorganises (5.5) |
| Callouts | `Callouts` (host-decided lines, side-only, rate limits, pre-rendered Piper TTS), `RadioChatter` (enemy net) | Voice and text for requests and reports |
| Tags | `EnemyTags` (player tags with a radio, 90 s, shown to the side), map intel markers | The start of shared spot reports |
| Performance | `DynamicSim` (sleeps far hostiles), `Virtualizer` (ALiVE-style profiles, off-screen fights, vehicle rides; 3x the force for no more frame time, measured) | What makes 8 km zones possible |

**Not there at all:** a friendly side picture shared across squads, any allied unit asking a
player for anything, deconfliction lanes between groups, an RTS camera, a cone-of-fire preview,
thermal sights, rangefinders, stabilisation, cook-off, turret toss, debris.

### 1.3 Campaign and world

| Piece | Where | What it gives us |
|---|---|---|
| Factions | data/factions.json: employers Meridian, Salvage Union, `us_forces`, `uk_forces`, `ca_forces` (kits `allied_us/uk/ca`, quartermasters with the M-ATV and MaxxPro); hostiles incl. `ashen_banner`, `kestrel`; reputation tiers hostile to allied | US forces exist as an **employer only**: they never hold ground |
| Zones | data/contracts.json `zones`: 22 contract zones (1,536-2,304 m), 5 hot zones (4,096 m); `ZoneDef.SIZE_STEP_M` 128, no max | The size steps an 8,192 m zone fits |
| Terrain | `ZoneTerrain`: 4 m cells, 128 m chunks, LOD steps to 1,200 m, apron 6 km | What an 8 km zone streams |
| Water and landmarks (cghath) | `ZoneWater`, `ZoneBridges`, data/landmarks.json (airfield, harbour, oil, mosque, farm, fuel station, garage, office), `ZoneModules.place_landmarks`, `place_harbour` | Rivers, bridges, harbours and airfields for invasions |
| Living war | `WorldSites` (holder, grip, fronts, strength, daily deterministic tick, flips, wipe-outs); `warring()` is hostile factions only; `server_contract_won` is called only for hot-zone contracts | The war the invasions feed |
| Company ground | `ZoneControl` (company flips when HQ and QRF bases fall; seize contract to move the FOB ashore) | How a zone changes hands for us |
| Region graph | `RegionMap.layout()`, `links`, `crossings` | Which zones an operation covers |
| Contracts | `ContractGen`, `Contracts`, `DebriefCalc`, `ScenarioGen`, `MissionScenario`, `Objectives` kinds | Generation, pay, objectives |
| Economy | `Economy` (rep, heat, supports, daily bills), data/prices.json (M-ATV 95k, MaxxPro 110k, supports), `MotorPool` values (Bradley 1.5M, Abrams 4M) | Prices to fit into |
| FOBs | `BaseFob`, `BaseZoneLevel` (2,304 m base zone), `Lhd`; no allied FOB exists, nothing rents a base, no flight cost is charged for a contract insertion | Where staging plugs in |
| AAV landings | `AavSupport.server_call` swims one AAV from the LHD to the caller ($18k) | The start of beach landings |

## 2. Armour

### 2.1 Where it sits

Between Arma Reforger or Squad and a full simulator like Steel Beasts:

- **Real crew jobs.** A tank needs a driver, a gunner and a loader to fight at full effect. One
  player can sit in any seat; the squad AI fills the others and takes crew orders (2.5).
- **Gunnery that needs the tools.** A sabot drops about 9 m over 2 km. The laser rangefinder and
  fire control solve that; without them you use the stadia lines and get it wrong (2.7).
- **Armour that cares about angle and where you hit.** The front of an Abrams shrugs off what
  kills it from the rear or the roof. An RPG kills an AAV from the side. Every outcome can be read
  in the x-ray (2.11).
- **Logistics that matter but don't nag.** Fuel and main-gun rounds run out over an operation, not
  a firefight. A thrown track is a 3-minute crew job; a dead engine needs the FOB (2.9).
- **Not simulated:** individual switch drills, start-up sequences, ballistic computer fault codes,
  gearbox ratios, weather on the shell (no wind or temperature in the solution), and
  manual traverse by hand-crank cranking animations (a slower rate stands in for it).

**Balance rules** (the Captain's "fair balance"):

1. **Every role has a counter, and every counter has a cost.** Infantry AT kills light armour from
   any side and heavy armour from the side, rear and top. Light armour kills infantry and
   technicals and dies to MBTs and ATGMs. MBTs dominate the open and need infantry in towns.
2. **Enemy armour is outclassed one for one, never in numbers or terrain.** The Eastern Concord's
   T-72B3 cannot beat an Abrams frontally at range, but a pair of them in a village with a Konkurs
   team on the flank can.
3. **Every number is in data and Proposed**, and the tuning sheet (2.14) lists them.
4. **The fight is winnable without armour.** Invasion missions bring friendly armour; a player
   squad on foot with AT4s and a Javelin must still be able to finish every mission type.

### 2.2 Internals and modules

Today a vehicle has seven zone kinds (`Vehicle.ZONE_*`: hull, engine, wheels, crew, cargo, rotor,
fuel), each a health value 0..1. That is replaced on armoured vehicles by **modules**: named boxes
inside the vehicle, each with its own health, what it absorbs from a passing round, and what its
damage does.

#### 2.2.1 Data

A new `modules` block per model (in data/vehicle_modules.json, merged into the model's spec by
`VehicleSpecs.spec`: 9.1). Boxes are in the vehicle frame (the same frame as `zones`).

```
"modules": [
  {"id": "engine", "kind": "engine", "box": [-1.6, 0.5, 2.8, 1.6, 1.5, 4.1], "hp": 150,
   "absorb_mm": 70, "fire": [0.05, 0.30]},
  {"id": "rack_bustle", "kind": "ammo_rack", "box": [-1.6, 1.6, 2.4, 1.6, 2.4, 3.6], "hp": 60,
   "holds": "main", "rounds": 34, "blowout": true, "doors": "bustle_doors"},
  {"id": "gunner", "kind": "crew", "seat": 1},
  ...
]
```

- `kind` decides the effect (table below). `hp` is in the existing `hp_kj` units.
- `fire`: [chance on a KE penetration through it, chance on a CE penetration]. Fuel tanks and
  ammo racks carry their own rules on top.
- `crew` modules point at a seat; the crew member's body is the real target (2.2.4).
- **Migration:** a model with no `modules` gets them built from its `zones` (engine to engine,
  wheels to tracks or wheel stations, fuel to fuel_tank, crew to a crew compartment, cargo to
  stowage), so the soft vehicles and aircraft keep working unchanged until someone authors theirs.
  `Vehicle.zone_health()` keeps answering from the modules, so `DriveContact.is_disabled`,
  `VehicleService` and `MotorPool` need no change in phase A2.

#### 2.2.2 Module kinds and what damage does

Each module is **working** (above 50% hp), **damaged** (above 0) or **destroyed** (0).

| Kind | Damaged | Destroyed | Field repair (2.9.3) |
|---|---|---|---|
| `engine` | Power x0.5; idle smoke | No drive; turret on batteries for 10 min (`BATTERY_TURRET_S` 600), then manual traverse; fire chance | Damaged to working with a repair kit (90 s) |
| `transmission` | Top speed x0.6, no neutral steer | Immobile | Damaged only (120 s) |
| `track_l`, `track_r` | Top speed x0.85 | Thrown or broken: immobile, pivots on the other track only | Yes, track links (180 s with 2 crew, 360 s alone) |
| `wheel_n` (wheeled) | x0.9 per wheel | Run-flat: x0.75 per wheel, at most 2; a third immobilises | Spare wheel (25 s, as today) |
| `fuel_tank_n` | Leaks (today's `_leak` maths) | Empties; fire roll | Patch: stops the leak (45 s) |
| `ammo_rack_n` | Rounds in it may be lost (10% each) | Detonation roll (2.10.2) | No |
| `breech` | Reload x1.5 | Main gun out | No |
| `barrel` | Dispersion x3; "barrel bent" | Main gun out | No |
| `traverse` | Traverse rate x0.5; stabiliser off | Manual traverse (`MANUAL_TRAVERSE_DPS` 6) | Damaged only (60 s) |
| `elevation` | Elevation rate x0.5; stabiliser off | Manual (3 deg/s) | Damaged only (60 s) |
| `gunner_sight` (primary) | Thermal and LRF lost; day channel only | Fall back to the auxiliary sight | No |
| `aux_sight` | Blurred | No aux sight | No |
| `commander_sight` (CITV, CIV) | Thermal lost | Periscopes only; no hunter-killer | No |
| `driver_vision` | Night channel lost | Driver must drive turned out | Periscope swap (30 s) |
| `fcs` (fire control, stabiliser) | Solution error x3 | No solution, no stabiliser: stadia only | No |
| `radio` | Reports delayed x2 | Dark: no net, no Blue Force Tracker, no requests (4) | Swap a radio item (20 s) |
| `troop` (troop compartment) | Hits wound the dismounts | | |
| `ext_gun` (pintle MG, CROWS, UGWS outside) | Jams after each burst (clear 3 s) | Gone | Damaged only |
| `smoke` (dischargers) | Half the salvos | None | Reload salvos only |
| `era_n`, `slat_n` (2.4.4) | | Used up or torn off; shown missing | Replace a tile from the vehicle's spares (40 s) |
| `structure` (the old hull hp) | | Wrecked (HE pounding, overpressure, a collapse) | Workshop only |

#### 2.2.3 Module layouts

Positions follow the voxel art in `VehicleArt` (front is -z). The build session authors the exact
boxes against the model; these are the layouts and the hp.

**M1 Abrams** (M1A2 SEP-class)

| Module | Where | hp | absorb_mm |
|---|---|---|---|
| driver (crew, seat 0), driver_vision | Hull front, centre | | |
| fuel_tank_fl, fuel_tank_fr | Hull front, either side of the driver (behind the glacis) | 120 each | 25 |
| ammo_rack_hull (6 rounds, no blow-out) | Hull, left of the driver behind armoured doors | 40 | 15 |
| breech, barrel | Turret centre; barrel outside | 150, 80 | 150, 40 |
| gunner (seat 1), gunner_sight (GPS with thermal and LRF), aux_sight (GAS 8x), fcs | Turret right front | 60, 40, 40 | 10 |
| commander (seat 2), commander_sight (CITV) | Turret right rear, above the gunner | 50 | 10 |
| loader (seat 3) | Turret left | | |
| ammo_rack_bustle (34 rounds, blow-out panels, blast doors) | Turret bustle | 80 | 15 |
| traverse, elevation | Turret ring, trunnions | 90, 60 | 35 |
| radio | Turret bustle front | 30 | 10 |
| engine (AGT1500 turbine), transmission | Rear hull | 150, 120 | 70, 50 |
| fuel_tank_rear | Rear hull | 100 | 25 |
| track_l, track_r | | 100 each | |
| ext_gun: loader's M240, commander's M2 | Turret roof | 30 each | |
| smoke (two 6-salvo dischargers) | Turret cheeks | 20 each | |

**M2A3 Bradley**

| Module | Where | hp | absorb_mm |
|---|---|---|---|
| driver (seat 0), driver_vision | Hull front left | | |
| engine, transmission | Hull front right | 80, 70 | 60, 45 |
| gunner (seat 1), gunner_sight (IBAS: day, thermal, LRF), aux_sight, fcs | Turret | 40, 30, 30 | 10 |
| commander (seat 2), commander_sight (CIV) | Turret | 40 | 10 |
| ready_25 (300: 70 AP + 230 HE, dual feed) | Turret basket | 40 | 15 |
| breech, barrel (M242 25 mm) | Turret front | 60, 40 | 60, 25 |
| tow_launcher (2 ready missiles) | Turret left side, outside | 40 | |
| rack_tow (5 TOW) | Hull right, behind the turret | 40 | 15 |
| rack_25 (600 stowed) | Hull floor | 50 | 15 |
| traverse, elevation, radio | | 50, 40, 25 | 30 |
| fuel_tank (two cells) | Under the troop floor | 60 each | 25 |
| troop (6 dismounts) | Hull rear | | |
| track_l, track_r | | 60 each | |
| smoke (two 4-salvo dischargers) | Turret front | 15 each | |

**AAV-7A1** (with the up-gunned weapon station, UGWS)

| Module | Where | hp | absorb_mm |
|---|---|---|---|
| driver (seat 0), commander (seat 1) | Hull front left, one behind the other | | |
| engine, transmission | Hull front right | 80, 60 | 60, 45 |
| gunner (seat 2), ugws (Mk19 + M2, 3x day sight) | Turret right front | 60 | 30 |
| ready_mk19 (96), ready_m2 (200) | Turret | 30 | 15 |
| rack_mk19 (288), rack_m2 (1,000) | Hull front | 30 | 15 |
| fuel_tank | **Under the troop floor** | 60 | 25 |
| troop (21) | Hull rear | | |
| waterjets | Rear, either side | 40 each | |
| track_l, track_r, radio | | 60, 25 | |

The AAV's fuel under the troops is real and dangerous; it is why an AAV hit in the side by an RPG
burns. Its answer is the EAAK appliqué and a careful landing plan (6.4.2), not a stronger hull.

**M-ATV and MaxxPro:** engine (front), crew capsule (one crew module per seat), fuel_tank (rear
side), wheel_1 to wheel_4, ext_gun (the M2 in the O-GPK turret, or CROWS), radio, spare_wheel
(stowage). **Technicals:** engine, fuel_tank, cab (crew), bed, wheels, ext_gun. Their
`structure` is low, so HE pounding still wrecks them the way the old hull hp did.

#### 2.2.4 Crew are real soldiers

Crew already sit in seats as `Soldier` bodies (`Vehicle._place_occupants`). A crew module is the
seat's position; a round or a spall fragment crossing it hits the soldier's real hitboxes through
`Vitals`, so wounds, bleeding, unconsciousness and the medical model work inside a tank exactly as
outside. Consequences:

- **The vehicle fights on with fewer jobs.** A downed gunner means nobody fires the main gun until
  someone moves into that seat (2.5.3). A downed driver stops it.
- **Casualties inside are treated inside**, at half speed (cramped), or pulled out through a hatch
  (`Vehicle.server_exit` already ejects; a downed man is dragged out by the carry action, 8 s).
- **Burns** use the existing `server_burn` and burn wounds.

#### 2.2.5 Kill states

| State | When | Shown on the model |
|---|---|---|
| **Mobility kill** | Both tracks or the transmission or the engine destroyed, three wheels gone, flooded | A track lying behind, a wheel off (2.10) |
| **Firepower kill** | Breech or barrel destroyed, or no working sight and no aux sight | Barrel drooped to its lower stop |
| **Crew kill** | No crew member able to act (dead, unconscious, or bailed out) | Hatches open |
| **Knocked out** | Mobility and firepower, or crew kill: what the AI and objectives count as "out" | |
| **Catastrophic** | Ammo detonation, or a fuel fire that burns out | Turret thrown, hulk (2.10) |

The convoy and park objectives (`destroy_vehicles`: "burns, is a wreck or can't drive") read
"knocked out or mobility kill", which keeps their meaning.

**Built in A2** (cg_brief queue item 2.1, branch `armour/modules`): `VehicleModules`
(scripts/vehicles/vehicle_modules.gd, a `Modules` child of every vehicle) with the layouts above
in data/vehicle_modules.json for the Abrams, Bradley, AAV-7, M-ATV and MaxxPro; the path, spall
cone, HE inside and partials of 2.3.5 (`plan()`, called by `ArmourModel.vehicle_hit`; applied by
`server_apply`, `Vehicle._apply_damage`'s hook); crew hits through the seated men's real hitboxes
and Vitals; the 2.2.2 effects that have something to act on today (speed and mobility, leaks and
fires, racks, guns, the radio's `radio_down`, turret drive rates); the kill states, with
"repairable"; belly blasts as crew injuries from the mine proof's floor sum
(`ArmourStandards.floor_kg`, 2.3.6 and 2.4.7); net_state, HitEvents and saves. Technicals,
aircraft and static weapons keep their zones. The calls made building it are in
docs/audits/followups.md ("Calls made", 2026-10-23, cg_brief 2.1) and what's left for later phases
is F-228 to F-240 there.

### 2.3 The shell model

Every round that can hurt a vehicle, from a 7.62x54R LPS bullet to a 120 mm sabot, goes through
one pure function, `ArmourModel.resolve(shell, plate, hit) -> HitResult` (new
`scripts/combat/armour_model.gd`, static, no nodes, so tests stage it with dictionaries). It
replaces `VehicleDamage.resolve` for every model that has `plates` (2.4); `Vehicle.server_take_hit`
picks the path by that key, so soft vehicles and aircraft keep the old resolver until they get
plates. The hit still arrives the way it does now: `Ballistics._trace` for bullets and
`Warheads.server_burst` for launcher rounds, with `VehicleHull.first_solid` finding the voxel.
Small arms keep their present path: tier 0 rounds (pistol, 5.56, 7.62x39, 7.62x51 ball) never
reach the model on a vehicle plate (Captain's call: vehicle armour is immune to small calibre),
so the common case costs nothing new.

**Built in A1:** `ArmourModel` (scripts/combat/armour_model.gd: `resolve`, `plate_at`,
`tiles_at`, `vehicle_hit`, `damage`), `Shells` (scripts/combat/shells.gd: `shell(id)`,
`for_round`, `pen_ke`), data/shells.json, data/vehicle_armour.json, the warheads.json keys, and
the hook in `Vehicle.server_take_hit`. Until A2 the result lands on the old zones (call 81).

#### 2.3.1 Shell data

New `data/shells.json`. One row per projectile. It replaces `round_tiers` for anything listed
there; `round_tiers` stays as the fallback for rounds not in it (every pistol and rifle round).
`data/warheads.json` keeps the launcher warheads; they gain the same `pen`, `fuze`, `module_dmg`
and `ricochet` keys, and `ArmourModel` reads both files through one `Shells.get(id)`.

```
"m829a3": {"name": "M829A3 APFSDS-T", "gun": "m256", "kind": "apfsds",
  "calibre_mm": 120, "mass_kg": 10.0, "rod_kg": 4.6, "muzzle_mps": 1555, "drag": 0.00035,
  "pen_ke": [[0, 800], [1000, 780], [2000, 760], [3000, 740], [4000, 715]],
  "normalise_deg": 2, "ricochet_deg": [78, 85], "overmatch": 3.0,
  "fuze": {"kind": "none"}, "module_dmg": 420, "spall": {"count": 26, "cone_deg": 14},
  "tracer": true, "price": 1100}
```

- `kind`: `apfsds`, `apds`, `ap` (full-calibre steel or tungsten core, bullets included), `api`,
  `heat`, `tandem_heat`, `he`, `hedp`, `hei`, `amp` (programmable multi-purpose), `efp`
  (explosively formed penetrator, top attack), `thermobaric`, `canister`.
- `pen_ke`: penetration table, mm RHA at 0 degrees, by range in metres, linearly interpolated.
  Tables, not a formula, so a tuner changes one number at one range without touching code.
- `pen_ce`: one number for shaped charges (range does not matter to a jet).
- `he_kg`: TNT equivalent of the filling. Drives overpressure (2.3.6) and the existing
  `Warheads` blast on soldiers and voxels (the same cube-root scaling `warheads.json` documents).
- `fuze`: 2.3.7.
- `module_dmg`: damage in the existing `hp_kj` units that the round does to the first module it
  reaches after a full penetration; residual-scaled after that (2.3.5).
- `spall`: fragments thrown behind the plate on a penetration and the cone they fill.

#### 2.3.2 Effective thickness and angle

For a hit at angle `theta` from the plate's normal. The normal is the plate's authored `normal`
in data (2.4.1), not the voxel face: the hull is built of axis-aligned 5 cm voxels, so a sloped
glacis is a staircase whose faces point straight up or straight forward. The voxel decides
*where* the round hits; the plate decides the slope:

1. **Normalisation (KE only).** `theta_n = max(0, theta - normalise_deg)`. Long rods barely turn
   (2 degrees), APDS and full-calibre AP turn more (5-8), heavy MG and autocannon bullets 6-10.
   HEAT never normalises.
2. **Overmatch.** If `calibre_mm >= overmatch x plate_mm` (the physical thickness), the plate
   cannot turn the round at all: no ricochet roll, and `theta_n` is capped at 45 degrees. A 120 mm
   sabot on a 12 mm BTR side plate goes straight through whatever the angle. A 12.7 mm bullet on
   the same plate does not.
3. **Line of sight.** `t_eff = t_rha / cos(theta_n)`, capped at 4x `t_rha` (beyond about 75
   degrees the ricochet roll decides it, not thickness). Composite arrays (`composite: true`) use the same rule,
   capped at 2x, because the published figures for them are already
   line-of-sight values at their design angle.
4. **The threat column.** `t_rha` is the zone's `ke_mm` for `apfsds`, `apds`, `ap`, `api`, `efp`
   and the KE part of `hedp` and `amp`; its `ce_mm` for `heat`, `tandem_heat`, the CE part of `hedp`
   and `amp`. Reactive armour, slat and spacing are added on top (2.4.4).

#### 2.3.3 Ricochet and fuze failure

- **KE ricochet.** Below `ricochet_deg[0]` never; above `ricochet_deg[1]` always; between, the
  chance rises linearly. Rolled from the hit's seed (2.3.9). A ricochet leaves the plate along the
  reflected direction with 60% of its speed and keeps flying through `ShellFlight`: a sabot
  glancing off a glacis can still kill the infantryman behind the tank.
- **Defaults** (Proposed): APFSDS 78-85, APDS 65-78, AP/API bullets and autocannon 55-72,
  HE 60-80 (it bursts on the plate instead of bouncing if the fuze fires first, see below).
- **HEAT graze.** A shaped charge's fuze fails to crush at very high obliquity. Above
  `graze_deg` (default 80) it either glances off as a dud (no jet) or bursts in the wrong place
  (half `pen_ce`), 50/50. Old RPG fuzes are worse (`graze_deg` 72 for PG-7V and PG-9).
- **The outcome** is always one of `ricochet`, `shatter` (KE stopped and broken up),
  `non_pen`, `pen`, `dud`, `fuzed_outside` (HE or HEAT burst on the outer layer: ERA, slat,
  skirt), each with its numbers kept in the `HitResult` for the x-ray (2.11).

#### 2.3.4 Penetration

- `pen = pen_ke(range)` or `pen_ce`.
- `pen > t_eff`: **penetration**, `residual = pen - t_eff`.
- `pen > 0.8 x t_eff` (KE): **partial**: no spall inside, but the plate's backface bulges: the
  module directly behind takes 15% of `module_dmg` and a crew member touching that wall gets
  bruising (a `Vitals` blunt hit, no wound). This is why a near-penetration still feels like
  something.
- Otherwise **non-penetration**: external damage only (2.3.6).
- **Range** is the distance flown, so `ShellFlight` passes it in; a shot from a ricochet keeps its
  flown distance.

#### 2.3.5 After the plate: the path, the modules, the spall

The round (or the HEAT jet) continues along its line through the interior, in the vehicle's own
frame, through the module boxes it crosses in order (2.2). This replaces `Warheads._jet_behind`'s
flat 3 m kill line and `Vehicle._spall`'s "everyone within 2.5 m of the hole" with what the round
actually passes through:

- Each module it crosses takes damage and eats `absorb_mm` of the residual (fuel cells 25,
  engine 70, transmission 50, ammo racks 15, breech 150, gun barrel 40, turret ring 35, radios and
  electronics 10, a crew member 8). When the residual reaches 0 the path stops.
- **Damage to a module on the path** = `module_dmg x (residual_at_module / residual_at_entry)`.
  HEAT jets lose residual faster than rods after the first module (x1.5 `absorb_mm`), so a jet
  that only just got in kills what is right behind the plate and little else.
- **Spall cone.** On every full penetration `ArmourModel` emits `n = spall.count x clamp(residual
  / 100, 0.3, 1.5)` fragments in a cone of `spall.cone_deg` around the path (wider when the
  plate was thick for the round: `cone x (1 + t_eff / pen)`). Each is a short ray (2.5 m) through
  the module boxes and seat positions. A fragment does `module_dmg x 0.04` to a module and a
  `Warheads` fragment wound (the same `frag_wounds` path a grenade uses) to a crew member it
  touches. A **spall liner** (Bradley, Abrams, MRAPs; 2.4) cuts `n` by 60% and the cone by 40%.
- **HE inside.** An `he`, `hei`, `hedp` or `amp` round that penetrates bursts inside after its
  fuze delay: overpressure to every module within `1.5 x he_kg^(1/3)` m (scaled by 1 - the
  module's own `blast` share) and `Warheads` blast and fragment wounds to every crew member in the
  compartment. This is what makes a 25 mm HEI hit on a technical's cab lethal and a 30 mm HE hit
  inside a BMP's troop compartment terrible.

#### 2.3.6 HE overpressure and fragments against armour

An HE round that does not penetrate still does work outside:

- **HE "penetration"** (the blast punching a thin plate): `pen_he = 25 x he_kg^(1/3)` mm
  (Proposed; about 32 mm for a 2.1 kg 105 mm shell, 17 mm for a 60 mm mortar, 8 mm for a 40 mm
  grenade). Against `t_eff` of the nearest zone like any other round. Soft-skins and the roofs
  of light armour fail to it; IFV sides do not.
- **External modules in the blast radius** take `module_dmg x blast` where `blast` is the zone's
  existing `blast` share from `data/vehicles.json` (kept, now applied per module): tracks, road
  wheels, tyres, optics heads, the external MG, antennas, ERA tiles (a tile within 1 m of a big
  HE burst can be set off: 25% per tile), smoke dischargers, stowage.
- **Turned-out crew** (2.6) take the normal `Warheads` blast and fragment wounds as if standing
  in the open, shielded by their hatch ring only from below.
- **Under the belly** (mines and IEDs): the belly zone's `belly_blast` share (V-hull 0.12, flat
  hull 0.45, soft 1.0) of the charge reaches the crew floor; blast seats halve the leg injury
  roll. The wheel or track station over the charge is always destroyed.

#### 2.3.7 Fuzes

`fuze` on each shell:

| `kind` | Behaviour | Rounds |
|---|---|---|
| `none` | KE, no filling | APFSDS, APDS, AP, bullets |
| `pd` (point detonating) | Bursts on the first surface with `sensitivity_mm` or more (a 2 mm car door fuzes it; grass and leaves do not) | 25 mm M792 HEI-T, 40 mm M430A1 HEDP, OG-7V, mortars |
| `pd_delay` | Fuzes on impact, bursts `delay_ms` later: travels `speed x delay` metres onward (through a thin wall or into a vehicle) | 120 mm AMP in delay mode (2 ms: through a breeze-block wall), 30 mm HE-T |
| `piezo` | Shaped charge, instant on crush, with `graze_deg` | AT4, PG-7V, PG-7VL, PG-9, M830A1 in ground mode |
| `tandem` | Precursor first: strips light ERA and slat-triggered bursts, then the main charge | PG-7VR, TOW-2A, Javelin, Konkurs-M, Kornet |
| `proximity` | Bursts within `prox_m` of a vehicle or aircraft, never against ground | M830A1 in air mode (helicopters), Javelin top-attack approach, NLAW overfly (`ota_height_m` already in warheads.json) |
| `airburst` | Bursts at a set range (the lased range plus `offset_m`) | 120 mm AMP in airburst mode, later 40 mm and 30 mm airburst |
| `self_destruct` | Bursts at `max_s` | PG-7V (already `self_destruct` in warheads.json), 25 mm HEI-T at 3,000 m |

`arming_m` (already a key on every warhead) applies to all of them: a round that hits before it
arms is a dud that does only its KE (a 40 mm grenade at 10 m bounces off a soldier).

#### 2.3.8 Shell flight

New `scripts/combat/shell_flight.gd` (`ShellFlight`), host-side, ticked in physics: position,
velocity, gravity, quadratic drag (`drag` per shell, tuned so the table in 2.7.5 comes out),
tracer, and the hit test against the voxel world, soldiers and vehicle boxes the way
`Ballistics` already tests bullets (it reuses `Ballistics`' ray and hit helpers so a sabot and a
bullet meet the world identically). Rounds above 600 m/s step at the physics rate with swept
rays; slower rockets keep `LauncherProjectile`. Clients draw the tracer from the fire event (seed,
muzzle, velocity) and correct to the host's impact event. One `ShellFlight` node per level holds
every round in flight in an array (no node per shell).

#### 2.3.9 Determinism and networking

- Every random roll (ricochet, ERA trigger, slat defeat, spall directions, fire start) comes from
  `RandomNumberGenerator` seeded with `hash(shot_id, vehicle_id, plate_id)`, so a host and a
  replay agree. Clients never roll.
- The host resolves the hit and broadcasts one compact `HitEvent` (reliable, about 120 bytes): the
  outcome, entry point and normal, `t_eff`, `pen`, the modules hit and their new states, crew hit
  ids, and the seed. Clients play the effects (2.10) from it and the x-ray (2.11) reads it.

### 2.4 Armour zones and packages

#### 2.4.1 Plates

Armoured models get a `plates` block in data/vehicles.json, beside `zones`. A plate is a box of
armour with one value per threat column. The hit's voxel point picks the plate (first box that
contains it, as `VehicleDamage.zone_at` does for zones); the plate gives the numbers and the slope.

```
"plates": [
  {"id": "turret_front", "box": [-1.75, 1.5, -1.65, 1.75, 2.45, -0.9], "normal": [0, 0.15, -1],
   "ke_mm": 900, "ce_mm": 1300, "phys_mm": 750, "material": "composite_du", "composite": true},
  {"id": "hull_side_skirt_fwd", "box": [...], "normal": [1, 0, 0],
   "ke_mm": 160, "ce_mm": 450, "phys_mm": 70, "material": "composite", "spaced_mm": 450},
  ...
],
"tiles": [ {"group": "arat_hull_l", "kind": "light_era", "box": [...], "count": 16,
            "coverage": 0.85, "package": "tusk1"} ],
"belly": {"blast": 0.45, "seats": "standard"},
"spall_liner": true
```

- `ke_mm`, `ce_mm`: RHA-equivalent at normal incidence against kinetic and chemical-energy
  threats. For a composite array, the value along its design facing (the published kind of
  figure), with the 2x obliquity cap of 2.3.2.
- `phys_mm`: the physical thickness, used only for overmatch (2.3.2) and HE punch-through.
- `material` (for the x-ray and the hit sounds): `rha`, `hhs` (high-hardness steel), `alu`
  (5083 aluminium), `composite`, `composite_du`, `glass` (transparent armour), `skirt`.
- `spaced_mm`: an air gap behind the plate. A shaped charge that fuzes on it loses
  `min(0.15, spaced_mm / 3000)` of its penetration on the next layer.
- A hit inside no plate box falls to the zone's old `armour` class (so a gap in authoring is
  never a hole in the tank).

#### 2.4.2 Base protection per vehicle (Proposed, from public estimates)

All values in mm RHA-equivalent at the plate's normal: KE / CE.

**M1 Abrams (M1A2 SEP-class, composite with a DU layer in the turret front)**

| Zone | KE | CE | Notes |
|---|---|---|---|
| Turret front (cheeks) | 900 | 1300 | The strongest face in the game |
| Gun mantlet and shield | 500 | 700 | The frontal weak spot |
| Hull front (glacis and lower plate) | 560 | 800 | Lower plate 500 / 700 |
| Turret sides, front half | 300 | 600 | |
| Turret sides, bustle | 60 | 100 | Ammo behind it: blow-out panels vent up |
| Hull side behind the heavy front skirts (front third) | 160 | 450 | `spaced_mm` 450 |
| Hull side behind the light skirts (rear two-thirds) | 85 | 160 | `spaced_mm` 450 (KE 70 raised to 85 in A1: call 76) |
| Hull rear and engine grille | 30 | 40 | |
| Turret roof | 40 | 60 | Hatches 30 / 30 |
| Engine deck | 30 | 30 | |
| Belly | 30 | 30 | `belly.blast` 0.45 |

Spall liner: yes.

**M2A3 Bradley (aluminium hull with spaced steel appliqué; BRAT I tiles fitted, as today's
`default_era`)**

| Zone | KE | CE | Notes |
|---|---|---|---|
| Hull front | 60 | 110 | Proof against 30 mm APDS past about 700 m |
| Turret front | 50 | 90 | |
| Hull sides (spaced laminate) | 35 | 70 | Proof against 14.5 mm at 300 m and beyond; BRAT I tiles over most of it (and over the hull and turret front: call 77) |
| Turret sides | 30 | 60 | BRAT I tiles |
| Rear and ramp | 25 | 40 | |
| Roof | 20 | 30 | |
| Belly | 20 | 20 | `belly.blast` 0.45 |

Spall liner: yes.

**AAV-7A1 (aluminium with the EAAK appliqué, fitted)**

| Zone | KE | CE |
|---|---|---|
| Front | 45 | 70 |
| Sides | 35 | 55 |
| Rear and ramp | 25 | 35 |
| Roof | 15 | 20 |
| Belly | 15 | 15 (`belly.blast` 0.5) |

No spall liner by default.

**M-ATV and MaxxPro (steel and composite capsule, V-hull)**

| Zone | M-ATV KE / CE | MaxxPro KE / CE |
|---|---|---|
| Front | 25 / 30 | 22 / 28 |
| Sides | 20 / 25 | 20 / 25 |
| Rear | 18 / 22 | 18 / 22 |
| Roof | 12 / 15 | 12 / 15 |
| Glass (transparent armour) | 22 / 22 | 22 / 22 |
| Belly | V-hull, `belly.blast` 0.12, blast seats | V-hull, 0.13 (0.15 before cg_brief 2.0: mine 3b, 2.4.7), blast seats |

Engine bays stay `mrap_weak` (18 / 18). Spall liner: yes.

**Technicals:** `soft` (3 / 3) and `soft_engine`, as today. No plates.

**Enemy armour** (new models, section 7):

| Zone | T-72B3 (base) | with Kontakt-5 (default for the Concord) | BMP-2 | BTR-82A | MT-LB |
|---|---|---|---|---|---|
| Turret front | 520 / 900 | 740 / 1350 | 35 / 40 | 20 / 22 | 12 / 14 |
| Hull front | 450 / 620 | 670 / 1070 | 35 / 40 | 20 / 22 | 12 / 14 |
| Hull sides | 80 / 120 (Kontakt-1 skirts on the front half: CE +400) | same | 18 / 20 | 10 / 12 | 10 / 12 |
| Rear | 40 / 40 | | 15 / 15 | 8 / 8 | 8 / 8 |
| Roof | 40 / 40 | | 12 / 12 | 7 / 7 | 7 / 7 |
| Belly | 20, `blast` 0.45 | | 15, 0.5 | 10, 0.6 | 10, 0.6 |

#### 2.4.3 Threats (Proposed, from public figures)

New rows in data/shells.json (guns) and data/warheads.json (missiles and rockets). KE is mm RHA
at 0 degrees at 100 / 500 / 1,000 / 2,000 m; CE is one number.

| Round | Fired by | Kind | KE 100 / 500 / 1k / 2k | CE | Filling kg | Fuze |
|---|---|---|---|---|---|---|
| M829A3 | Abrams 120 mm | APFSDS | 800 / 790 / 780 / 760 | | | none |
| M830A1 | Abrams | HEAT-MP | | 600 | 0.9 | piezo; proximity (air mode) |
| M1147 AMP | Abrams | multi-purpose HE | | 150 | 1.6 | pd, pd_delay, airburst |
| M791 | Bradley 25 mm | APDS | 80 / 72 / 64 / 48 | | | none |
| M919 | Bradley 25 mm (upgrade ammo) | APFSDS | 110 / 105 / 95 / 80 | | | none |
| M792 | Bradley 25 mm | HEI | | | 0.032 | pd, self-destruct 3,000 m |
| TOW-2A | Bradley | tandem HEAT, SACLOS, 3,750 m | | 900 | 3.0 | tandem |
| M430A1 | AAV Mk19 40 mm | HEDP | | 50 | 0.034 | pd, arms at 18 m |
| M33 ball | M2 .50 | AP-ish ball | 20 / 15 / 9 / - | | | none |
| M8 API | M2 .50 (upgrade belts) | API | 25 / 19 / 12 / - | | | none (incendiary: fuel fire x2) |
| B-32 12.7x108 | DShK | API | 21 / 16 / 10 / - | | | none |
| B-32 14.5x114 | ZPU-2 | API | 33 / 28 / 20 / - | | | none |
| BZT 23 mm | ZU-23-2 | API | 30 / 25 / 18 / - | | | none |
| 3BM42 | T-72B3 125 mm | APFSDS | 560 / 550 / 530 / 500 | | | none |
| 3BK29M | T-72B3 | HEAT | | 700 | 1.5 | piezo |
| 3OF26 | T-72B3 | HE-FRAG | | | 3.4 | pd, pd_delay |
| 9M119M | T-72B3 (gun-launched, 2 per tank) | tandem HEAT, 5,000 m | | 850 | 2.0 | tandem |
| 3UBR8 | BMP-2, BTR-82A 30 mm | APDS | 65 / 60 / 55 / 45 | | | none |
| 3UOF8 | BMP-2, BTR-82A 30 mm | HE-I | | | 0.049 | pd |
| 9M113M Konkurs-M | BMP-2, Concord AT teams | tandem HEAT, SACLOS, 4,000 m | | 800 | 2.7 | tandem |
| 9M133 Kornet | Concord top tier only | tandem HEAT, beam-riding, 5,500 m | | 1150 | 4.6 | tandem |
| PG-9 | SPG-9 technical | HEAT | | 300 | 0.4 | piezo (graze 72) |
| M344 | M40 106 mm technical | HEAT | | 400 | 1.3 | piezo |
| Type 63 rocket | rocket technical | HE, 12 in a ripple | | | 1.3 | pd |
| PG-7V | RPG-7 | HEAT | | 260 (as today) | 1.0 | piezo (graze 72) |
| PG-7VL | RPG-7 | HEAT | | 500 | 1.0 | piezo |
| PG-7VR | RPG-7 | tandem HEAT | | 600 | 1.4 | tandem |
| TBG-7V | RPG-7 | thermobaric | | | 1.8 | pd |
| AT4, FFV551, NLAW, Javelin | infantry (as today) | | | 420, 450, 500, 750 | | piezo / tandem |

Which RPG rounds a faction carries goes in its kit: Black Ridge, the Shura and the cartels carry
PG-7V and OG-7V; the Ashen Banner adds PG-7VL and a few PG-7VR; the Concord carries PG-7VL and
PG-7VR.

#### 2.4.4 Reactive armour, slat and spacing

Tiles are separate pieces with their own boxes, each used up when it fires, so a hit that sets one
off leaves a hole the next round goes through.

| Kind | Against single HEAT | Against tandem HEAT | Against KE | Triggered by | Real model |
|---|---|---|---|---|---|
| `light_era` | +400 CE | 0 (the precursor fires it) | 0 (+10 against autocannon) | HEAT of 30 mm and up; KE of 20 mm and up 30% of the time; HE of 0.5 kg and up within 1 m 25% | Kontakt-1, BRAT I, ARAT-1 |
| `heavy_era` | +450 CE | 0 | +220 against APFSDS and APDS only | as light | Kontakt-5 |
| `tandem_era` | +450 CE | +450 CE | 0 | as light | BRAT II, ARAT-2 |
| `slat` | Rockets (RPG family, recoilless HEAT): 50% shorted, a dud; else bursts on the slat: -15% pen and the panel is torn | Same | Passes through | Any rocket or HEAT | Cage and slat kits |
| `spaced` | -10% to -15% (2.4.1) | Same | 0 | | Skirts |

- **Coverage.** Every tile group has a `coverage` (0.8-0.9). The roll is made from the hit seed;
  a miss means the round found a gap and meets the base plate.
- **Used up and shown.** A fired tile removes its voxels from the hull (`VehicleHull.apply_ops`
  with a new `REMOVE` edit) and goes into `net_state` so every peer and late joiner sees the gap.
  The x-ray shows the empty tile in grey.
- **Danger to dismounts.** A tile going off throws fragments 8 m out in its facing
  (`Warheads` fragment wounds, 1-3 per man). The AI keeps dismounts out of the side of an
  ERA-fitted vehicle that faces the enemy; players see a small "ERA" warning on the vehicle's
  outline when standing within 8 m of a tile face.

#### 2.4.5 Packages

Upgrade packages are bought at the company FOB's motor pool, fitted to one vehicle in the pool
(stored in `MotorPool` records as `packages: []`), and drawn on the model. Each one adds weight,
which costs speed and fuel:

```
top_speed x sqrt(mass / (mass + added))
accel     x mass / (mass + added)
fuel_l_per_km x (mass + added) / mass
```

| Package | Vehicle | What it adds | Weight | Price | Needs |
|---|---|---|---|---|---|
| **Abrams TUSK I** | Abrams | ARAT-1 `light_era` on the hull sides (32 tiles), loader's gun shield, rear slat over the engine grille, belly kit (`belly.blast` 0.45 to 0.25) | 2.4 t | $180,000 | US trusted |
| **Abrams TUSK II** | Abrams | TUSK I with ARAT-2 `tandem_era` in place of ARAT-1 on hull and turret sides (48 tiles), CROWS on the commander's M2 (fired from inside, thermal and LRF) | 4.0 t | $320,000 | US allied |
| **Trophy APS** | Abrams | Two launchers (left and right), 2 shots each; intercepts rockets and ATGMs coming at up to 60 degrees above the horizon (not KE, not a Javelin's top-attack dive): 80% per shot. The intercept throws fragments 15 m out in the threat's sector: it can wound friendly infantry beside the tank | 2.5 t | $400,000 | US allied, after TUSK I |
| **Bradley BUSK III** | Bradley | BRAT II `tandem_era` in place of BRAT I, belly blast kit (0.45 to 0.18; 0.2 before cg_brief 2.0, so it meets mine 2b, 2.4.7) and blast seats, commander's shield (turned-out commander protected from the front against small arms), fuel cell protection (fuel fire chance x0.5) | 1.8 t | $120,000 | US trusted |
| **Bradley M919 ammo** | Bradley | Unlocks M919 APFSDS in the AP feed | 0 | per round | US trusted |
| **AAV slat kit** | AAV | `slat` on sides and rear | 1.2 t | $45,000 | none |
| **AAV spall liner** | AAV | `spall_liner` | 0.4 t | $30,000 | none |
| **M-ATV slat kit** / **MaxxPro slat kit** | MRAPs | `slat` on sides and rear (and the cargo box on the MaxxPro) | 0.6 / 0.7 t | $25,000 | none |
| **CROWS (M153)** | M-ATV, MaxxPro | The M2 on a remote station: gunner inside the capsule, day/thermal sight with LRF, stabilised | 0.2 t | $60,000 | US trusted |
| **M-ATV appliqué** | M-ATV | +10 KE and +10 CE on the front, sides, glass and rear, +4 on the roof (cg_brief 2.0: the rear and roof added so it meets STANAG KE 3 all round, 2.4.7) | 0.8 t | $35,000 | none |
| **MaxxPro appliqué** (cg_brief 2.0) | MaxxPro | As the M-ATV's: STANAG KE 3 | 0.9 t | $40,000 (Proposed; prices.json with A8) | none |
| **MaxxPro mine roller** | MaxxPro | A roller 6.5 m ahead: sets off pressure-plate IEDs and mines under it (they still damage the roller: 3 blasts and it's scrap) | 1.5 t | $50,000 | none |
| **Thermal sight kit** | AAV UGWS | Adds a thermal channel to the 3x day sight | 0.05 t | $40,000 | US trusted |

Prices sit in data/prices.json `packages`; the "Needs" column is the reputation tier with the
employer whose quartermaster sells it (`Quartermaster.vehicle_deals` already gates the M-ATV and
MaxxPro this way). Removing a package at the FOB refunds 50%.

**Enemy packages** come with the faction's kit, not a purchase: the Concord's T-72B3 has Kontakt-5
by default and Kontakt-1 skirts; its BMP-2s get Kontakt-1 at Pressure tier 3; the Ashen Banner's
captured MaxxPros keep their slat; the Kestrel armoured truck (7.2) is its own build.

#### 2.4.6 Who beats what (500 m unless noted)

The balance check the tuning pass starts from. "pen" penetrates head-on; "no" never; "~" depends
on the angle or the range; "tile" is stopped by a tile and penetrates through a gap (15%).

| Threat | Abrams turret front | Abrams hull front | Abrams side (rear 2/3) | Abrams roof | Bradley front | Bradley side | AAV side | M-ATV side | T-72B3 (K-5) turret | T-72B3 side | BMP-2 front |
|---|---|---|---|---|---|---|---|---|---|---|---|
| M829A3 | no | pen | pen | pen | pen | pen | pen | pen | ~ (pen at 0-20 deg) | pen | pen |
| M830A1 HEAT | no | no | pen | pen | pen | pen | pen | pen | no | pen | pen |
| M791 25 mm | no | no | no | ~ | ~ | pen | pen | pen | no | no | pen |
| M919 25 mm | no | no | ~ | pen | pen | pen | pen | pen | no | pen | pen |
| TOW-2A | no | pen | pen | pen | pen | pen | pen | pen | ~ | pen | pen |
| 3BM42 | no | ~ | pen | pen | pen | pen | pen | pen | | | |
| 3UBR8 30 mm | no | no | no | ~ | ~ | pen | pen | pen | | | |
| Konkurs-M | no | ~ | pen | pen | pen | pen | pen | pen | | | |
| Kornet | no | pen | pen | pen | pen | pen | pen | pen | | | |
| PG-7V | no | no | pen (TUSK: tile) | pen | tile | tile | pen | pen | no | tile | pen |
| PG-7VR | no | no | pen (TUSK II: no) | pen | pen | pen (BUSK III: ~) | pen | pen | no | pen | pen |
| AT4 | no | no | pen (TUSK: tile) | pen | tile | tile | pen | pen | no | tile | pen |
| Javelin (top) | pen | pen | pen | pen | pen | pen | pen | pen | pen | pen | pen |
| M2 M33 | no | no | no | no | no | no | no | no (100 m: ~) | no | no | ~ |
| Mk19 HEDP | no | no | no | ~ | no | no | no | pen | no | no | ~ |

**Built in A1** (`tests/armour_test.gd`, `_test_table`): every cell above is asserted from
data/shells.json, data/warheads.json and data/vehicle_armour.json. "pen" means through head-on
at 500 m, past a gap in the tiles and through a tile met; "no" means never through with the
tiles met, at 0-60 degrees, 100-2,000 m and on every plate of that face (the Abrams hull front
includes its lower plate; its roof includes the hatches); "~" means through somewhere in that
sweep and not somewhere else; "tile" means stopped by a tile met and through a gap. The Javelin
row is resolved on each vehicle's roof. The T-72B3 and BMP-2 columns are asserted as soon as
phase D6b adds their data. Five cells were corrected against the 2.4.2-2.4.4 numbers in A1
(calls 77 and 78).

Read across a row: the AT4 is a side and rear weapon against tanks and a killer of everything
light, which is its job. Read down a column: the Abrams' front is beaten only by a tandem ATGM's
lucky hull hit, and its roof by anything top-attack, which is why it needs infantry.

#### 2.4.7 Protection standards: STANAG 4569 and NIJ 0101.07 (cg_brief queue item 2.0)

Captain, 2026-10-22: "make sure it follows the current standards for armor". Vehicles are rated by
NATO **STANAG 4569** (AEP-55), personal armour by **NIJ 0101.07** (2023). The threat lists, ranges
and velocities are in `data/armour_standards.json`; `ArmourStandards` reads them.

**How a vehicle rating is proven** (`ArmourStandards.ke_result`, `artillery_result`,
`mine_result`; asserted for every model and package in `tests/armour_test.gd`): each level's
threats go through `ArmourModel.resolve` against every crew-envelope plate the round can meet
(tyres, an MRAP's bonnet and the open gunner's shield are outside it: `"stanag": false`), from
each azimuth of the arc (front ±30°, sides 60-120°, rear 150-210°) and the level's elevations
(0-30° for KE 1-4, level for 5-6), at the level's range, ricochets left out. A rating holds when
every level up to it is stopped everywhere and the next level gets through somewhere.

| KE level | Threats (range) | Arc |
|---|---|---|
| 1 | 7.62x51 ball, 5.56 SS109 and M193 (30 m); reference rows, 7-9 mm RHA | All round, per arc |
| 2 | 7.62x39 API BZ (30 m), 11.7 mm | All round |
| 3 | 7.62x51 AP tungsten carbide (30 m), 23.4 mm; 7.62x54R B32 API, 15.7 mm | All round |
| 4 | 14.5x114 B32 API (200 m), shells.json `b32_145`, 31.75 mm | All round |
| 5 | 25 mm APDS-T M791 (500 m), 72 mm | Front ±30° (sides stay at 4) |
| 6 | 30 mm APFSDS (500 m), 110 mm | Front ±30° |

Artillery: a 155 mm HE burst at 100 / 80 / 60 / 30 / 25 / 10 m (levels 1-6), its worst
fragment as a 20 mm FSP of 6 / 8 / 11 / 16 / 19 / 30 mm RHA, all round. Mine blast: 0.5 kg
anywhere under (1), 6 / 8 / 10 kg TNT under a wheel or track station (2a / 3a / 4a) or the belly
(2b / 3b / 4b); a hull holds it when `kg x station share (belly 1, wheel 0.35, track 0.2) x
belly.blast x (0.5 with blast seats)` reaches the crew floor at 0.55 kg or less (2.3.6; phase A2
turns the belly into crew injuries). Rifle-calibre rounds stay on `VehicleDamage`'s tiers in game
(call 79); the KE 1-3 reference rows rate the plates, and every rated crew zone also stops KE 1's
rounds on the tiers.

**The ratings** (stored as `stanag_ke`, `stanag_artillery`, `stanag_mine` in
`data/vehicle_armour.json`; a package's own replace the base's while fitted; "KE" overall is the
standard's: 1-4 all round, 5-6 the front's):

| Vehicle (package) | KE front / side / rear (overall) | Artillery | Mine (wheel/belly) |
|---|---|---|---|
| M1 Abrams | 6 / 4 / 3 (3); the front is above STANAG: RHAe figures as 2.4.2 | 6 | 2a/1 |
| Abrams TUSK I, TUSK II | 6 / 4 / 3 (3) | 6 | 4a/1 |
| Abrams Trophy | as the base | 6 | 2a/1 |
| M2A3 Bradley (BRAT I fitted) | 4 / 3 / 3 (3) | 5 | 2a/1 |
| Bradley BUSK III | 4 / 3 / 3 (3); against RPGs: 2.4.6 | 5 | 4a/2b |
| Bradley M919 ammo | as the base | 5 | 2a/1 |
| AAV-7A1 (EAAK fitted; slat, spall liner, thermal kit as the base) | 3 / 3 / 3 (3) | 5 | 1 |
| M-ATV (slat, CROWS as the base) | 2 / 2 / 2 (2) | 4 | 4a/3b |
| M-ATV appliqué | 3 / 3 / 3 (3) | 5 | 4a/3b |
| MaxxPro (slat, CROWS, mine roller as the base) | 2 / 2 / 2 (2) | 4 | 4a/3b |
| MaxxPro appliqué | 3 / 3 / 3 (3) | 5 | 4a/3b |
| Technicals (every variant) | 0 | 0 | 0 |
| UH-60M, Petrel, Razorback, AH-1Z, mortars, tripods | not rated (STANAG 4569 rates land vehicles) | | |

The T-72B3, BMP-2, BTR-82A and MT-LB get theirs with their data in phase D6b (cg_brief 4.2).

**Personal armour, NIJ 0101.07** (Ballistics.LEVELS): HG1 (9 mm FMJ at 398 m/s, .357 Magnum at
436), HG2 (9 mm at 448, .44 Magnum at 436), RF1 (7.62x51 M80 at 847, 7.62x39 MSC at 732, 5.56
M193 at 990), RF2 (RF1 plus 5.56 M855 at 950), RF3 (.30-06 M2 AP at 878); handgun rounds at
5 m, rifle at 15 m. Old 0101.06 names map on read: IIA/II to HG1, IIIA to HG2, III and III+ to
RF1, III++ to RF2, IV to RF3. `tests/armor_test.gd` fires each level's list at every rated plate,
helmet, pad and vest, and the next level's own list (at least one through).

### 2.5 Crew roles and seats

#### 2.5.1 Seats and jobs

Two seat kinds are added to `Vehicle`'s `driver`, `gunner`, `passenger`, `pilot`: **`commander`**
and **`loader`**. Today the Abrams' and Bradley's commander and loader seats are `passenger`; the
data changes, and every `kind == passenger` check that means "rider" reads `is_rider()` instead.

| Vehicle | Driver | Gunner | Commander | Loader | Riders |
|---|---|---|---|---|---|
| Abrams | drives; turned out or periscopes | main gun, coax; GPS, GAS | CITV, hunter-killer override, can fire the main gun; the M2 (turned out, or inside with CROWS) | loads the main gun; the M240 on the pintle (turned out) | |
| Bradley | drives | 25 mm, coax, TOW | CIV, override, can fire | | 6 dismounts; one reloads the TOW |
| AAV | drives; swims | Mk19 and M2 (UGWS) | spots, radio | | 21 |
| M-ATV, MaxxPro | drives | M2 (hatch or CROWS) | radio, spots | | 2 / 4 |
| Technical | drives | the bed gun | | | bed riders |

**One seat, one job.** No seat drives and fires the main gun. A player alone in a tank takes the
seat they want and the squad AI fills the rest (`SquadDrivers.pick_driver` and
`VehicleLayer.pick_gunner` already choose men; a `pick_crew` generalises them). With nobody to
fill a job, the vehicle is **short-crewed**:

| Missing | Effect |
|---|---|
| Loader (Abrams) | The gunner or commander loads: 15 s a round, and the one loading is off his sight |
| Commander | No CITV or CIV; the gunner's view is all the vehicle has; no override |
| Gunner | The commander can fire from his override at 1.5x the lay time; with no commander, the gun is silent |
| Driver | Immobile |

#### 2.5.2 Crew orders (the intercom)

From any crew seat, a **crew wheel** (hold `crew_menu`, default V) with the contextual first
options (5.5):

- To the driver: Move forward / Stop / Reverse / Turn left, right / **Move to** (aim point) /
  **Hull down here** / **Back off** (reverse 50 m on the reverse track) / Speed slow, normal, fast.
- To the gunner: **Target** (what I aim at) / Fire / Cease fire / Ammo: sabot, HEAT, HE (AMP
  mode) / TOW.
- To the loader: Load sabot, HEAT, HE / Restock from the hull.
- All: Button up / Turn out / **Pop smoke** / **Bail out**.

AI crewmen answer with short intercom lines ("Driver, moving", "Identified", "Up!" from the
loader, "On the way") through `Callouts` on a new `intercom` channel heard only inside that vehicle,
radio-filtered.

#### 2.5.3 Switching seats

`Vehicle.server_switch` (vehicle.gd:1407) is instant today. It becomes a timed move:

| Move | Time |
|---|---|
| Within the turret (gunner, commander, loader) | 3 s |
| Turret to the driver's station, or back (Abrams: the turret must face front, within 15 degrees) | 10 s |
| Troop compartment to a crew seat (IFV, AAV) | 6 s |
| MRAP, technical: any seat to any seat | 4 s |

While moving, the man is in neither seat. A wounded crew member is moved out of a seat by the
carry action. AI crews cover a lost job themselves: when the gunner goes down in contact, the
commander moves to the gun after 5 s ("Gunner's down, I'm on the gun").

### 2.6 Spotting: buttoned up or turned out

Each hatch seat (driver, commander, loader, the MRAP gunner) is **turned out** or **buttoned up**,
replicated in `net_state`.

| | Turned out | Buttoned up |
|---|---|---|
| View | Full head view, binoculars | Vision blocks: fixed slices (Abrams commander 6 blocks round the cupola, about 30 degrees each), 1x, no peripheral; or the seat's sight |
| AI spotting (`Spotting`) | x1 | x2.5 time to spot, and only inside the blocks' cones |
| Hearing | Normal | Muffled (outside sounds -12 dB, low-passed) |
| Exposure | Head and shoulders above the hatch: the soldier's hitboxes over the ring are hittable; blast and fragments hit him | Fully inside |

- `Spotting` gets a `vehicle_x(seat_state)` factor and a cone list per seat in data (`vision`:
  `[[yaw_deg, width_deg], ...]`).
- **AI:** commanders and loaders ride turned out in SAFE and AWARE, button up in COMBAT, under
  artillery or after a near miss, and turn out again 60 s after contact ends. Drivers in towns
  button up.
- **Players** toggle with `hatch` (default H): 1.5 s.
- **Thermal sights partly make up for buttoning up:** the CITV or CIV is a sight, not a block,
  with thermal and zoom, but a narrow field of view.

**Built in A4** (cg_brief queue item 2.3): `VehicleHatches` (scripts/vehicles/vehicle_hatches.gd,
the "Hatches" child of a model with `hatches` in data/vehicle_weapons.json: the Abrams' driver,
commander and loader, the Bradley's driver and commander, and its `roof_hatch` for the TOW
reloader). A turned-out man stands in his hatch at the hatch's `out` spot, head and shoulders over
the hull, so rounds meet his own hitboxes and `Vehicle.seat_open` gives blasts and fragments to
him (Warheads); `Spotting.spot_seconds` takes `VehicleHatches.spot_x`; the loader's M240 and the
commander's M2 (unless a `crows` package is fitted) need turned out. The hatch key is X (`hatch`:
H is the medical menu). AI crewmen follow a stand-in rule until A9's states (F-251): out after 60
s of quiet, in at once on contact. The hearing, the vision-block views and the driver's
periscopes came with A5 (F-252 closed; 2.12's "Built in A5").

### 2.7 Weapons and gunnery

#### 2.7.1 What each vehicle carries

| Vehicle | Weapon | Ready | Stowed |
|---|---|---|---|
| Abrams | M256 120 mm (M829A3 / M830A1 / M1147) | 34 in the bustle (default 16 / 10 / 8) | 6 in the hull |
| | Coax M240 | 800 | 1,600 |
| | Loader's M240 (pintle) | 200 | 600 |
| | Commander's M2 (manual, or CROWS with TUSK II) | 100 | 800 |
| | Smoke dischargers | 2 x 6 salvos | |
| Bradley | M242 25 mm, dual feed: AP (M791, or M919 with the ammo package) and HE (M792) | 70 AP + 230 HE | 600 (any mix) |
| | TOW-2A | 2 in the launcher | 5 |
| | Coax M240 | 800 | 1,400 |
| | Smoke | 2 x 4 salvos | |
| AAV | Mk19 40 mm | 96 | 288 |
| | M2 | 200 | 1,000 |
| M-ATV, MaxxPro | M2 (or CROWS) | 200 | 400 |
| Technicals | DShK, ZU-23-2 (twin 23 mm), SPG-9 (6 rounds), M40 106 mm (4), Type 63 (12-tube ripple, 2 reloads), ZPU-2 (twin 14.5 mm) | | |
| T-72B3 | 2A46 125 mm (3BM42 / 3BK29M / 3OF26 / 9M119M) | 22 in the autoloader carousel | 20 in the hull |
| BMP-2 | 2A42 30 mm (3UBR8 / 3UOF8), PKT, Konkurs-M | 500 (160 AP + 340 HE) | 4 Konkurs |
| BTR-82A | 2A72 30 mm, PKT | 300 | |

The five technical variants that have `"gun": {}` today get real guns in data.

#### 2.7.2 Data and code

- A `weapons` block per model replaces the single `gun` (which stays readable as `weapons[0]`
  for old data): each mount names its weapon, seat, muzzle, which turret it rides (`main`,
  `cupola`, `pintle`, `remote`), its feeds (`[{ammo, ready, stowed}]`) and its fire modes.
- New `guns` entries in data/vehicles.json: `m256`, `m242`, `tow_launcher`, `mk19`, `zu23_2`,
  `zpu2`, `spg9`, `m40_rr`, `type63`, `2a46`, `2a42`, `2a72`, `pkt`, `smoke_dischargers`.
- New `scripts/vehicles/vehicle_weapons.gd` (`VehicleWeapons`, one per vehicle, host-side state,
  replicated in `net_state`): mounts, ammo per rack and feed, the loaded round, reload timers, the
  selected ammo and mode. It fires through `ShellFlight` (cannon and autocannon), `Ballistics`
  (MGs, as today) and `LauncherProjectile` (TOW, Konkurs, Refleks, rockets). `Vehicle.server_fire_gun`
  stays as the MG path and calls into it.
- **Ammo racks are modules** (2.2.2), so losing a rack loses its rounds.
- **TOW, Konkurs-M and Refleks** get a new `LauncherProjectile` guidance kind `saclos`: the
  missile flies to the line between the launcher's sight and the crosshair, with a lag of 0.3 s.
  The gunner must hold the crosshair on the target until impact; turning the turret fast or the
  sight being blocked by smoke breaks the wire (a miss). Kornet uses `beam`: the same, but no wire
  to break and the launcher may move slowly.

#### 2.7.3 Loading and rates of fire

- **Abrams (human loader).** The loader's cycle: open the bustle doors and pull the round
  (2.0 s), ram it (1.5 s), close the doors and arm (1.0 s). A skilled AI loader averages 5-6 s by
  skill. **A player as loader** works the same three steps on one key, with a timing window on the
  ram: pressing in the window gives a 4.5 s load, outside it 6.5 s. The doors are open only for
  the first step: a bustle hit in those 2 s is not vented (2.10.2).
- **Changing rounds** loads the new type next; the round in the breech stays until fired or
  unloaded (8 s). The default is battlecarry: sabot loaded.
- **Hull rack:** restocking the bustle from the hull takes 12 s a round and needs the turret
  facing front within 15 degrees. The loader does it between fights when told, or on his own when
  the bustle is below 10.
- **Bradley M242:** single shot, low rate (100 rpm) or high rate (200 rpm). Switching feeds,
  AP to HE, takes 1.5 s. Refilling both ready boxes from stowage: 120 s, stopped and out of
  contact, by the gunner and one dismount.
- **TOW:** raise the launcher (4 s, only at a halt: moving faster than 1 m/s lowers it), fire, hold
  the crosshair to impact (about 190 m/s average: 20 s to 3,750 m). Reload: launcher down, one man
  out of the roof hatch, exposed, 45 s a missile.
- **Mk19:** 350 rpm; a new 48-round can is 30 s.
- **T-72B3 autoloader:** 7.5 s, no loader; carousel hits are the T-72's weak point (2.10.2).

**Built in A3** (cg_brief queue item 2.2, branch `armour/guns`): `VehicleWeapons`
(scripts/vehicles/vehicle_weapons.gd, the "Weapons" child of a model with `weapons`) with the
Abrams' and Bradley's mounts, turrets, racks and seat-move times in data/vehicle_weapons.json:
the M256 and the loader's cycle above (the bustle's doors open during the pull: a bustle
detonation then is catastrophic, `VehicleModules._detonation_roll`), short-crewed loading, a
damaged breech x1.5, unloading and restocking; the M242's dual feed, rates and ready-box refill;
the TOW raised, SACLOS-guided (`LauncherProjectile` guidance `saclos`, `VehicleWeapons.saclos_line`)
and reloaded; the commander's M2 and loader's M240; the commander's override; each mount on its
own modules (F-237). `ShellFlight` (scripts/combat/shell_flight.gd) is 2.3.8's shell flight, its
`drag` tuned to 2.7.5 (`ShellFlight.flight_to`; the `drag` in 2.3.1's example was a placeholder).
The vehicle's own `gun` stays the coax (every AI and support system reading `gun_info` keeps
working); the commander and loader are `commander` and `loader` seat kinds; seat moves are timed
on models with `switch_s`. Not in A3: the AAV's UGWS, the technicals' guns and the crew wheel
(F-244), sights and fire control (A4, F-243), AI crews firing the new guns (A9, F-242). The calls
made are in docs/audits/followups.md ("Calls made", 2026-10-23, cg_brief 2.2); the suite is
`maingun`.

#### 2.7.4 Sights

| Vehicle and seat | Sight | Day | Thermal | Rangefinder | Stabilised |
|---|---|---|---|---|---|
| Abrams gunner | GPS | 3x, 10x | 3x, 6x, 13x, 25x | 200-8,000 m, ±5 m | yes |
| Abrams gunner | GAS (aux) | 8x with ballistic stadia per round | no | no | no |
| Abrams commander | CITV | | 3x, 6x, 13x | yes | yes |
| Bradley gunner | IBAS | 4x, 12x | 4x, 12x | 200-4,000 m | yes |
| Bradley commander | CIV | | 4x, 12x | yes | yes |
| AAV gunner | UGWS sight | 1x, 3x | with the kit only | no | no |
| CROWS (MRAPs, Abrams TUSK II) | | 1x, 3x, 9x | 3x, 9x | yes | yes |
| T-72B3 gunner | Sosna-U class | 3x, 12x | 3x, 12x | yes | yes |
| BMP-2 gunner | | 6x | none (image intensifier 5.5x at night) | no | partly (2E36) |
| BTR-82A | | 4x, 8x | 4x | yes | yes |

- **Magnification is relative to the in-game view** (the Captain's optics call): a sight's field
  of view is the player's base FOV divided by the magnification.
- **The sight is full-screen**, not picture-in-picture: a gunner looks into his sight. It is a
  `Camera3D` at the sight's head on the turret (or the gun for the coax), switched to with
  `sight` (right mouse, as aiming down sights); the reticle and readouts are drawn by a new
  `VehicleSightOverlay` (`scripts/ui/vehicle_sight_overlay.gd`) in the UiKit look.
- **Thermal** is one system, `ThermalView` (new `scripts/combat/thermal_view.gd`), shared with
  cghath's planned thermal rifle scope (cg_brief item 8; whoever builds first builds it, the other
  reuses it):
  - a global shader uniform `thermal_view` (0 off, 1 white-hot, 2 black-hot) read by the game's
    shared material shaders (voxel bodies and gear, vehicle hulls, terrain, scatter, buildings,
    water, sky). In thermal they output a grey from a per-instance `heat` value and a cold
    ambient per material class;
  - `heat` per instance, set by a small `ThermalTag` helper: living soldiers 0.85, running engines
    and exhausts 1.0, a barrel after firing 0.8 cooling over 90 s, tracks and tyres after driving
    0.6 cooling over 120 s, burning wrecks 1.0, cold wrecks 0.35, the ground 0.2-0.4 by time of
    day, the sky 0.05;
  - ordinary smoke is transparent to thermal; the vehicle smoke dischargers fire a
    **multispectral** screen that blocks it (a real capability, and the counter to thermal sights);
  - walls block it (it is the same render);
  - the uniform is local to each machine, so only the player in the sight sees thermal.
- **Lasing** (`lase`, default R): a ray from the sight to the first solid surface out to the
  rangefinder's limit, plus its error. **First/last return** toggles which of two hits (brush
  then the target) it takes; "MULTIPLE RETURNS" shows when they differ by more than 20 m.
- **The fire control solution.** On a lase, the fire control computer takes the range, the
  selected round's ballistic table (`ShellFlight` builds a drop and time-of-flight table per round
  when data loads) and the lead, and lays the gun: **the reticle stays on the target, the gun
  moves**. Lead comes from tracking: the turret's angular rate over the last 1 s times the time of
  flight; tracking for under 1 s scales the lead error up linearly (`LEAD_TRACK_S` 1.0). The
  solution holds until the next lase; a target moving in range needs a new lase. No wind,
  temperature or cant.
- **Battlesight.** With no lase, the computer assumes 1,200 m for sabot, 900 m for HEAT and HE.
- **With the aux sight** (or the FCS destroyed), there is no solution: the gunner holds over with
  the stadia lines for the round.
- **The stabiliser.** `VehicleTurret` today holds its aim in the vehicle frame, so the turret
  turns with the hull. A stabilised turret holds a **world** aim: each step converts the world
  aim into the vehicle frame. The hold degrades with speed and ground roughness: aim jitter =
  `stab_base_mil + stab_k x speed x roughness`, and above `stab_max_kmh` (Abrams 50, Bradley 40,
  CROWS 30, T-72B3 40) the stabiliser cannot keep up and the gun drifts. Unstabilised mounts (AAV
  UGWS, technicals, tripods) fire at the halt or not at all. A damaged traverse or elevation drive
  turns it off.
- **The commander's view.** From the CITV or CIV the commander scans independently of the gun.
  `designate` (default T) puts the turret onto his line (the hunter-killer override): it slews at
  full rate and the gunner (AI or player) gets "Gunner, sabot, tank!" and the target. The commander
  can also take the trigger himself.
- **Gun accuracy.** Dispersion per gun in mils (`spread_mil`: 120 mm 0.2, 125 mm 0.3, 25 mm 0.6,
  30 mm 0.8, Mk19 3.0, M2 1.0); a damaged barrel x3.

**Built in A4** (cg_brief queue item 2.3, branch `armour/gunnery`): `VehicleGunnery`
(scripts/vehicles/vehicle_gunnery.gd, the "Gunnery" child of a model with `optics`) with the
Abrams' GPS, GAS and CITV and the Bradley's IBAS, aux sight and CIV in data/vehicle_weapons.json
(`optics`, `fire_control`, `stab`); each sight reads its module as 2.2.2 says (the fallbacks to
the aux sight, the fire control's x3 and none). `FireControl` (scripts/vehicles/fire_control.gd)
is the computer's pure sums: the ballistic table per round from ShellFlight's own integrator, the
solution with lead and parallax, the stadia. `VehicleTurret` keeps the sight's line apart from the
gun by the solution's `lay`, and turns at `rate_mult` (the commander's 1.5x). The laser (first and
last return, smoke), battlesight, the stabiliser (a world aim, jitter by speed and roughness, off
past `max_kmh` or with a damaged drive), the commander's viewer and hand-off, the AMP's airburst at
the lased range. `VehicleSight` (the full-screen Camera3D) and `VehicleSightOverlay`
(scripts/ui/vehicle_sight_overlay.gd: minimal, for A5 to restyle) are local. `ThermalView`
(scripts/combat/thermal_view.gd) is per-body additive heat overlays plus a full-screen pass
(thermal_view.gdshader), not a change to every shared shader (call A4.2); the uniform
`thermal_view` is set for any shader that wants it. `VehicleHatches` (2.6) is the hatches. The API
A9's CrewGunner uses: `server_lase(seat)`, `lay_on(point)`, `hand_off(point)`, `solution()`,
`laid()`, `server_set_fuze(round, mode)`, `server_view(seat, dir)`; `VehicleHatches.server_set` and
`auto_ai`. AI gunners get a solution only once they lase. The calls are in
docs/audits/followups.md ("Calls made", 2026-10-23, cg_brief 2.3); what's left is F-249 to F-254
there; the suite is `gunnery`.

#### 2.7.5 The ballistics, checked

`ShellFlight` is tuned so these come out within 10% (the phase A3 test asserts it):

| Round | Muzzle m/s | Time of flight 1 km / 2 km | Drop 1 km / 2 km (no superelevation) |
|---|---|---|---|
| M829A3 | 1,555 | 0.66 / 1.36 s | 2.1 / 9.1 m |
| M830A1 | 1,410 | 0.75 / 1.60 s | 2.8 / 12.6 m |
| M1147 AMP | 1,410 | 0.75 / 1.62 s | 2.8 / 12.9 m |
| M791 | 1,345 | 0.78 / 1.75 s | 3.0 / 15.0 m |
| M792 | 1,100 | 1.00 / 2.40 s | 4.9 / 28 m |
| 3BM42 | 1,700 | 0.60 / 1.25 s | 1.8 / 7.7 m |
| Mk19 M430A1 | 240 | a lobbed arc; 2,200 m maximum | |

#### 2.7.6 Engagement ranges in the world

Vehicles stay drawn to 3,000 m in invasion zones (a cheap proxy past 1,200 m, as terrain LOD
already steps), and soldiers to 1,500 m. Past that, the sight shows only terrain: a target there is
engaged from the side picture's marker (3.2) by indirect fire, not by sight. Tank gunnery in
practice happens at 500-2,500 m.

#### 2.7.7 AI gunnery

`AavGunner` grows into `CrewGunner` (renamed, `scripts/vehicles/crew_gunner.gd`; `AavGunner`
stays as the light version for MG seats):

- **Ammo by target:** tanks: sabot (HEAT if sabot is out, TOW past 1,500 m or when the 25 mm
  can't penetrate the face it sees); IFVs and APCs: sabot or 25 mm AP; MRAPs and technicals:
  HEAT or 25 mm HE; infantry in the open: AMP airburst, 25 mm HE, Mk19, coax; infantry in a
  building: AMP delay, HE; bunkers: AMP delay.
- **Lay time:** acquire (`Spotting`), then lase (0.5-1.5 s by skill), then fire. First-round
  hits come from the FCS error plus the existing aim error by skill (`SquadAI._aim_error_deg`'s
  model); a miss is corrected on the next round by half.
- **What to shoot first** (the G-10 rule, extended): an ATGM team or tank facing us, then an IFV
  facing us, then launchers, then other vehicles, then infantry by threat.
- **Aim at weak faces:** an AI gunner who knows a target's layout (they all do: it's
  recognition) aims at the side or rear when offered, at the lower hull or mantlet frontally with
  a sabot, and never wastes HEAT on a K-5 front.

### 2.8 Driving physics and terrain

#### 2.8.1 Ground

A new `ZoneTerrain.ground_at(x, z) -> StringName`, read from the terrain preset's surface splat,
the road segments in the zone def (roads have no collision today, so "on a road" is a distance to
a segment), water depth and cghath's new marsh, snow and farmland presets:

| Ground | Traction wheeled / tracked | Rolling resistance | Notes |
|---|---|---|---|
| Asphalt road | 1.0 / 0.95 | 0.015 | |
| Dirt track | 0.8 / 0.85 | 0.03 | |
| Grass, scrub, field | 0.7 / 0.8 | 0.05 | |
| Sand | 0.45 / 0.7 | 0.10 | Wheeled sink: speed cap 40 km/h |
| Mud, marsh, river bed | 0.3 / 0.55 | 0.15 | Wheeled speed cap 25 km/h; MRAPs can bog (below 3 km/h for 4 s on a slope: stuck until towed) |
| Rock | 0.85 / 0.8 | 0.04 | Track throw risk on hard pivots |
| Snow | 0.4 / 0.6 | 0.08 | |
| Rubble | 0.6 / 0.75 | 0.08 | |

#### 2.8.2 Power and traction

Drive force in `Vehicle._wheel_forces` becomes:

```
F = min(P / max(v, 2), mu x m x g x cos(slope)) - rr x m x g x cos(slope) - m x g x sin(slope)
```

with a new `power_kw` per model (Abrams 1,120, Bradley 450, AAV 390, M-ATV 276, MaxxPro 280,
technical 110, T-72B3 840, BMP-2 220, BTR-82A 220, MT-LB 175). `accel_ms2` stays as a cap and
`top_speed_kmh` as the governor. The old `CLIMB_DEG` grade hold goes: whether a vehicle climbs
a slope now comes from power and traction, so a wet hill stops a MaxxPro that a dry one doesn't.

#### 2.8.3 Slopes and rollovers

- The physics already rolls a vehicle that tips; the change is getting the centres of mass
  right (`com`): MRAPs sit high (M-ATV `com` y 1.25, MaxxPro 1.35), tanks low.
- **Rollover risk** shows on the HUD at 70% of the static tip angle (half the track width over
  the centre-of-mass height), and the AI driver will not cross ground over 60% of it.
- **A rollover** injures the crew (blunt hits through `Vitals`, halved for belted seats) and
  leaves the vehicle on its side, immobile. **Righting it** needs a tow from a vehicle of at least
  half its mass (a new `tow` action at the `service` point, 60 s), or it's abandoned.
- **Turning.** Wheeled: the radius comes from the wheelbase and `steer_deg`, as now. Tracked:
  neutral steer (a pivot) at a standstill, and at speed the yaw rate falls off with speed
  (`turn_deg_s` at 0, half at 30 km/h), scaled by traction.
- **Thrown tracks:** a hard pivot at more than 10 km/h on rock or rubble, or on a side slope of
  more than 20 degrees: 0.5% a second. The track module is destroyed (repairable, 2.9.3).

#### 2.8.4 Fording and the rivers

| Model | `ford_m` | Swims |
|---|---|---|
| Abrams | 1.2 | no |
| Bradley | 1.0 | no |
| AAV | | yes, 13 km/h (as today) |
| M-ATV | 1.37 | no |
| MaxxPro | 0.9 | no |
| Technical | 0.6 | no |
| T-72B3 | 1.2 | no |
| BMP-2 | | yes, 7 km/h |
| BTR-82A | | yes, 10 km/h |
| MT-LB | | yes, 5 km/h |

- `AavWater.throttle` already reads `ford_m` (defaulting to 0.8); the data now sets it on every
  model.
- **Deeper than `ford_m`:** the engine ingests water: stalled at once, the engine module damaged
  after 5 s and destroyed after 20 s. Water above the hull roof floods the crew compartment: the
  crew must get out (the existing wading and swimming take over).
- **Current.** A new `ZoneWater.flow_at(x, z) -> Vector2` (the river's direction and speed,
  0.5-2 m/s by width) pushes the immersed hull: `0.5 x rho x Cd x A x v_rel^2` along the flow.
  Swimming vehicles crab; a technical in a fast ford can be pushed off the ford's line into the
  deep channel.
- **River beds** are mud (2.8.1). **Banks** steeper than what traction allows block the exit, so
  fords (`ZoneWater`'s, 32 m wide at 0.45 m) and bridges are where columns cross.

#### 2.8.5 Bridges

`ZoneBridges` gets a **load class**, `mlc` (tonnes):

| Bridge | `mlc` | Takes |
|---|---|---|
| Concrete road bridge | 80 | everything |
| Steel truss | 40 | Bradley (30 t), AAV, MRAPs, BMPs; **not** the Abrams (62 t) or the T-72B3 (46 t) |
| Footbridge | 2 | people |

- A span with blast damage drops its `mlc` in proportion to its health.
- **Overload:** the span takes damage each second in proportion to the overload, and drops after
  `overload_s` (8 s at 1.5x) under the vehicle. It's in the zone save, as span health already is.
- **The AI never routes a vehicle over a span below its mass** (`RoadRoute` gets the bridge's
  `mlc` on its road segments). The driver's HUD warns approaching one: "BRIDGE MLC 40: TOO HEAVY".
- This is what makes **seizing a crossing** (6.4.4) a real objective: the concrete bridge is the
  only way the tanks get over.

### 2.9 Logistics

#### 2.9.1 Fuel

- Consumption stays as now (`_use_fuel`: per km, idle per hour, leaks). The Abrams' turbine idles
  at 40 L/h, so a tank waiting in overwatch for hours drinks; nothing else is a fuel problem inside
  one operation.
- **Sources:** the FOB motor pool (as today, 2/L); jerrycans (as today); fuel drums in supply
  pallets; and a new **fuel truck** (M978 tanker, 9,500 L): its hose action refuels a vehicle within
  8 m at 300 L/min. Allied fuel trucks come with invasion columns (6.3).

#### 2.9.2 Ammunition

- Main-gun and autocannon rounds are items: `round_120_m829a3` (21 kg, two-handed),
  `round_120_m830a1`, `round_120_m1147`, `links_25_m791` (50 rounds), `links_25_m919`,
  `links_25_m792`, `tow_2a` (29 kg, two-handed), `can_40_m430` (48 rounds), plus the enemy's for
  loot and salvage. Loaded through the vehicle's cargo point into the right rack: 10 s a 120 mm
  round, 15 s a link box, 30 s a TOW.
- **Rearming:**
  - at the FOB motor pool: everything, priced (`MotorPool.server_bring` already rearms the MG
    feeds; it fills the racks to the load-out picked at the motor pool);
  - from an **ammo truck** (new: an HEMTT cargo truck with an ammo load): a `rearm` action within
    8 m transfers at twice hand speed;
  - from **ammo pallets** (new pallet kinds in data/pallets.json, one per calibre);
  - by **helicopter resupply** (the existing support gets an "armour ammo" load: 8 x 120 mm or
    300 x 25 mm or 2 TOW).
- **Prices** (data/prices.json `ammo`, Proposed): M829A3 $1,100, M830A1 $800, M1147 $900;
  M791 $45, M919 $70, M792 $30 a round; TOW $9,000; Mk19 $40; .50 M33 $6, M8 API $9.

#### 2.9.3 Repair

| Job | Field (crew with tools) | Time (2 crew; one alone x2) | FOB only |
|---|---|---|---|
| Thrown or broken track | `track_links` | 180 s | |
| Wheel | `spare_wheel` | 25 s (as today) | |
| Engine, transmission, traverse, elevation, external gun: damaged to working | `repair_kit` | 60-120 s | |
| Fuel leak | `repair_kit` | 45 s | |
| Driver's periscope | `periscope` (new item) | 30 s | |
| Radio | a radio item | 20 s | |
| ERA tile, slat panel | `era_tile`, `slat_panel` (new items, carried as spares in the cargo hold) | 40 s each | |
| Smoke salvos | `smoke_salvo` (new item) | 10 s each | |
| Destroyed engine, transmission, breech, barrel, sights, FCS, ammo rack, structure; refitting packages | | | Motor pool: priced per module (`module_prices` in data/ground_supports.json), days by damage (as `MotorPool.repair_quote` does today) |

- Field repairs leave a module at 60% (today's `repair_to` 0.6).
- A job pauses while the crew member doing it is suppressed or the vehicle is hit.
- `VehicleService.parts_for` and `repair_problem` gain the new kinds; `zone_name` becomes
  `module_name`.

### 2.10 Fire, destruction and blast effects

All of this replaces `Vehicle.server_start_fire` / `_fire_step` / `_update_fire_fx` (one light
and an orange sphere) with a new `VehicleFire` (scripts/vehicles/vehicle_fire.gd, host state) and
`VehicleFx` (scripts/vehicles/vehicle_fx.gd, client effects). The host decides; clients play
effects from the `HitEvent` and a `FireEvent` / `KillEvent`, each carrying a seed, so every peer
sees the same flames, the same debris and the same thrown turret without streaming positions.

#### 2.10.1 Fires grow

A fire starts in a module (engine, fuel tank, ammo rack, crew compartment) and moves through
stages:

| Stage | Lasts | Looks | Does |
|---|---|---|---|
| **Smoke** | 0-10 s | Grey smoke from the grille, a hatch or the hole | Nothing yet; a crew extinguisher shot now puts it out 60% of the time |
| **Fire** | 20 s, then spreads | Flames from the openings, black smoke, heat shimmer | `server_burn` to crew in that compartment each second; after 20 s it spreads to the next module along (engine to fuel, fuel to the crew compartment) |
| **Cook-off** (ammo) | 20-60 s | Rounds popping: a crack and a spark burst every 0.5-3 s, some flying out | Each pop is a small HE event (0.05 kg for 25 mm, 0.3 kg for a 120 mm round); a 120 mm or 125 mm rack rolls 5% a second to **detonate** (2.10.2) |
| **Burn-out** | 120-300 s | Flames die down to a smoking hulk | The vehicle is a wreck once the fire reached the crew compartment or the fuel |

- **Extinguishers:** automatic halon in the crew compartment of the Abrams, Bradley and MRAPs
  (one shot, 70%, within 1 s of a crew-compartment fire); two manual engine-bay shots
  (`extinguish` action, 60% each). Empty bottles are refilled at the FOB.
- **Bail-out:** AI crews get out when a crew-compartment fire isn't out within 3 s, when a
  cook-off starts, or on a catastrophic warning (the ammo rack burning). "Bail out!" on the
  intercom; they leave by the hatches or the ramp to the lee side (`SquadDrivers.lee_of`), 20-40 m
  to cover. A crewman on fire burns for 3-6 s (burn wounds), drops and rolls, or a buddy beats it
  out.

#### 2.10.2 Ammunition

| Rack | Detonation chance: KE pen / CE pen / HE inside | On detonation |
|---|---|---|
| Abrams bustle (blow-out panels, doors shut) | 0.35 / 0.6 / 0.5 | **Vents up:** an 8 m fireball column through the roof panels for 4 s; the bustle's rounds are gone; the crew is unhurt and the tank can fight on with the hull rounds |
| Abrams bustle, doors open (loading) | same | Catastrophic |
| Abrams hull rack | 0.35 / 0.6 / 0.5 | Catastrophic |
| T-72B3 carousel | 0.5 / 0.75 / 0.6 | Catastrophic, turret thrown |
| Bradley 25 mm ready and stowed | 0.15 / 0.3 / 0.3 | A cook-off sequence (25 mm pops for 30-60 s), not a single blast |
| Bradley TOW rack | 0.4 / 0.7 / 0.5 | Catastrophic |
| Mk19, M2 cans | 0.2 / 0.4 / 0.3 | Cook-off |

#### 2.10.3 Hit effects by round

| Outcome | Effect | Sound |
|---|---|---|
| Ricochet | Spark spray, a bright streak leaving at the reflected angle | A ringing ping and a whine |
| KE stopped | Sparks, chips of paint flying out, a dent (`SCUFF`) | A heavy clang (steel), a dull thud (composite), a clank (aluminium) |
| KE penetration | A white flash at the entry, a glow from the hatches and vision blocks for 0.2 s, dust and smoke puffing from every opening | A muffled boom inside |
| HEAT stopped (ERA or armour) | An orange flash and a black smoke puff; an ERA tile goes off with a sharper blast and flying tile pieces | A crack (ERA), a bang |
| HEAT penetration | The jet's flash, a thin smoke trail from the hole, the interior glow | A sharp bang, then the interior |
| HE | A fireball by `he_kg`, black smoke, fragments sparking off the hull, a scorch (`SCORCH`, as today) | |

The existing `VehicleHull` carves (`HOLE`, `SCUFF`, `SCORCH`) stay; the tile removal (2.4.4) is a
fourth edit kind, `REMOVE`.

#### 2.10.4 Catastrophic kills, and what's left

A catastrophic kill (`KillEvent` with a seed):

1. **Fireball and shockwave:** a fireball of radius `2 + 1.5 x rounds^(1/3)` m; a
   `Warheads.server_burst` on everyone near with `blast_kg = min(0.4 x rounds, 12)`; a camera
   shake on nearby clients.
2. **The turret is thrown** when 10 or more main-gun rounds were aboard: `VehicleTurret.split()`
   already lifts the turret and gun voxels into their own part. That part becomes a `RigidBody3D`
   with an impulse of 8-15 m/s up, 2-4 m/s sideways and a random spin; it lands, comes to rest,
   and stays as its own wreck piece in the zone save. With fewer rounds the hull ruptures instead
   (the roof plates lift, the hull splits along a seam).
3. **Debris:** 12-24 voxel chunks cut from the hull by the seed, thrown as rigid bodies that hit
   the world and each other, asleep after 8 s and frozen static after 30 s. At most 64 debris
   pieces in a zone; the oldest are frozen and merged into static first. This is the same pattern
   as the seed-synced gore pieces (`BlastGore`): same seed, same pieces, no position stream.
4. **The hulk:** the hull's colours darken to char (a stronger `WRECK_TINT`, embers speckled for
   60 s), a smoke column for 5-10 minutes (billboards past 600 m), then a thin smoulder for the
   rest of the deployment. Saved with the zone and salvageable, as wrecks are today.

**Damage shown on a living vehicle:**

- **Mobility kills:** a broken track runs off the sprocket and lies flat behind (a static track
  piece); a wheel blown off by a mine or an HE burst at a wheel station flies 5-10 m (a rigid
  body).
- **Firepower kills:** the barrel droops to its lower elevation stop and stays there.
- **A burning engine** glows through the deck grilles.
- **Missing ERA tiles and torn slat panels** stay missing until replaced.

#### 2.10.5 Sound

New entries in data/sounds.json, played through `Sfx`:

- Impacts by material (steel, composite, aluminium, glass) and outcome (ping, clang, thud,
  penetration boom).
- Inside the vehicle: outside sounds muffled and low-passed; crew voice on the intercom filter.
- ERA crack; fire roar loop; cook-off pops; the detonation with its distance delay (sound speed)
  and low-pass by distance; the thrown turret's crash on landing.
- Engines by type and load: the Abrams' turbine whine, the diesels of the rest, pitched by RPM;
  tracks clattering and squealing with speed; MRAP tyre roar on asphalt.
- The main guns: a 120 mm report with a pressure thump close by; the 25 mm's thud-thud; the TOW's
  launch whoosh and the wire spool; the Mk19's chug.

#### 2.10.6 Budgets

At most 6 vehicles burning with full effects at once (more show smoke only), 64 debris pieces per
zone, 2,000 live smoke and fire particles across the zone, and every column a billboard past
600 m.

**Built in A7** (cg_brief queue item 2.5, branch `armour/fx`): `VehicleFire`
(scripts/vehicles/vehicle_fire.gd, "FireState", the host's state in the StateSync and the zone
save), `VehicleFx` (scripts/vehicles/vehicle_fx.gd, "Fx", every peer) and `VehicleSmoke`
(scripts/vehicles/vehicle_smoke.gd, "Smoke", 2.7.1's dischargers), numbers in
data/vehicle_fx.json. The stages (smoke, fire, a cook-off's pops, burn-out, smoulder) are drawn
over the burn that was there: a fire is still a loss at once and a wreck after `Vehicle.FIRE_S`,
then the wreck burns on 120-300 s under its column; extinguishers and spreading fires are F-262.
The bustle vents as a column, the other racks go up as a fireball with the turret thrown (10 or
more main-gun rounds) or the hull ruptured, 12-24 debris pieces, the hulk charred; all from the
kill's seed, the host's resting places replicated and saved. AI crews bail out by `server_exit`
(VehicleFire.auto_bail, A9 replaces it: F-236). The guns' sounds, the 120 mm's overpressure, the
TOW launcher's own part, impacts by round, the intercom and your own engine from inside (Sfx's
Intercom and Interior buses) are in. Effects are GPU particles in the voxel look (boxes). Not
built: the tile `REMOVE` edit (F-263), tracks and wheels thrown off a living vehicle and the
engine's glow (F-264), the rest of 2.10.5's sounds (F-268).

### 2.11 The x-ray: hit analysis

Learned from War Thunder's hit camera and protection analysis.

- **Every resolved hit** produces a `HitReport` on the host (JSON-safe: the round, the entry point
  and plate, the angle, `t_rha`, `t_eff`, the penetration at that range, the outcome, the path
  through the modules with each module's damage and new state, the spall rays, the crew hit and
  their new state). It goes to the shooter and to the crew of the vehicle hit (reliable, about
  300 bytes) and is kept, the last 10, on each client.
- **The card.** A small corner card for 6 s: the target, an outcome icon, one line ("PEN: engine
  destroyed, gunner wounded" or "RICOCHET: turret front, 81 degrees").
- **The full view** (`xray`, default X, while the card shows or from the last 10 in the pause
  menu): a new `VehicleXray` (`scripts/ui/vehicle_xray.gd`) draws the vehicle from its data in a
  `SubViewport`, orbitable:
  - plates as translucent boxes shaded by their KE value (pale for thin, deep for thick), used ERA
    tiles in grey;
  - modules as outlined boxes: working white, damaged yellow, destroyed red; crew as capsules:
    up green, wounded orange, down red;
  - the shell's line from entry through each module, the plate marker with the angle drawn as an
    arc, and the spall rays;
  - a text panel: "Turret side, 300 mm KE at 38 degrees: 381 mm effective. M791 at 640 m: 66 mm.
    NON-PENETRATION."
  - The game doesn't pause (it's co-op); the view is an overlay and Esc closes it.
- **The setting** (`GameSettings`, `hit_analysis`): Off / My shots / My shots and hits on me
  (default) / Every hit (dev).
- **Training:** at the base zone's firing range and in the vehicle range (`VehicleRange`), a
  **protection analysis** mode: pick a vehicle, a round and a range, click anywhere on the model
  and see the predicted outcome, with the ricochet chance. It runs `ArmourModel.resolve` locally
  with a fixed seed.
- **Dev:** `--xray-log` writes every `HitReport` to the session log.

### 2.12 The vehicle HUDs

Both HUDs replace `Vehicle.readout_parts` and `Hud.show_vehicle`'s text strip. They're new
`scripts/ui/vehicle_hud.gd` (`VehicleHud`) and `vehicle_sight_overlay.gd`, built from `UiKit`,
fitted to the ui_test's 10 resolutions. Every key shown is the player's current binding.

#### 2.12.1 Third person (any seat, chase camera)

```
+--------------------------------------------------------------------------------------+
|              N    .    .   [ turret ]    .   E   .    .    .    S                  |
|              ------------------v------------^-------------------------  hull 088    |
|                                                                                      |
|                                                                                      |
|                                   (+)  <- where the gun points (lags the crosshair)   |
|                                    +   <- your aim                                    |
|                                                                                      |
|                                                                                      |
|  ! ROLLOVER RISK    ! FORD 0.9 / 1.2 m                                                |
|                                                                                      |
|  +-----------+   M256 120 mm         SABOT [14]  HEAT 9   HE 8      hull rack 6       |
|  |   _____   |   LOADED: SABOT   [=========-----] loading HEAT 3.1 s                  |
|  |  |  G C|  |   COAX  800 | 1600     M2  100 | 800       SMOKE 6 | 6                  |
|  |  | L   |  |                                                                        |
|  |  |__D__|  |   CREW  D Okafor *   G Mercer *   C (you) *   L Hale (wounded)          |
|  | [=]   [=] |                                                                        |
|  +-----------+   24 km/h  F   FUEL [========--] 1,420 L   ENGINE ok   TRANS ok        |
|  [V] crew  [H] hatch  [B] view  [R] lase  [T] designate  [X] last hit  [F] get out     |
+--------------------------------------------------------------------------------------+
```

- **Top:** a compass tape with the hull's heading (a caret) and the turret's direction (a
  bracket), and the bearing of the last hit taken (a red tick, 10 s).
- **Centre:** your aim and, separately, where the gun is actually pointing, so the turret's
  traverse lag reads at a glance.
- **Bottom left: the vehicle doll**, top-down: modules coloured (white working, yellow damaged,
  red destroyed), tracks or wheels, ERA tiles (grey when used), crew pips with role letters at
  their seats.
- **Bottom centre:** the selected weapon, every round type with the selected one bracketed and
  the next one named, the reload bar, the other weapons, smoke salvos.
- **The crew line:** names, roles and state (from `Vitals`); "you" marked.
- **Bottom right:** speed, gear (F / N / R), fuel, engine and transmission states.
- **Alerts** (only when true): ON FIRE (with the extinguisher key), TRACK THROWN, ROLLOVER RISK,
  FORD depth, BRIDGE MLC, MISSILE LAUNCH (a launch seen by the crew), SHORT-CREWED, NO RADIO.

#### 2.12.2 First person: the gunner's sight

```
+--------------------------------------------------------------------------------------+
| THERMAL  WHOT  13x                     GPS                     STAB ON    LRF READY   |
|                                                                                      |
|                                                                                      |
|                                         |                                            |
|                                         |                                            |
|                              -----------+-----------                                 |
|                                         |                                            |
|                                         |                                            |
|                                                                                      |
|                                                                                      |
|  RANGE 1874 m  (last)                                   LEAD 2.1 mil  TRACK [=====]   |
|  SABOT  > LOADED            next HEAT        SABOT 14   HEAT 9   HE 8 (PD)            |
|  turret 012   hull 346                                   CREW D* G* C* L*   DMG none  |
+--------------------------------------------------------------------------------------+
```

- The sight's own mode, magnification and channel; STAB ON / DEGRADED / OFF; LRF READY /
  MULTIPLE RETURNS / FAULT.
- The reticle for the selected round (the GAS view has stadia per round instead).
- The lased range (first or last return), the lead and how long you've tracked.
- Rounds, the loaded one and the next; the HE fuze mode (PD, DELAY, AIRBURST at the lased range).
- The turret's and hull's headings; crew pips; a short damage word.
- **The commander's sight** is the same frame with "CITV" and the designate prompt ("[T] lay the
  gun here"). **The driver** sees his periscope slices (or the open hatch), with speed, gear, fuel,
  ford depth and the turret's direction as a small arrow, because a driver needs to know where the
  gun is before he swings the hull. **The loader** turned in sees the bustle doors and a large
  round selector; turned out, the pintle gun.
- **Night:** the driver's periscope has an image-intensified channel; the rest of the HUD dims.

**Built in A5** (cg_brief queue item 2.4, branch `armour/hud`): `VehicleHud`
(scripts/ui/vehicle_hud.gd) for any vehicle with authored modules (the Abrams, Bradley, AAV,
M-ATV, MaxxPro; the rest keep the text strip). The compass strip carries the hull's caret, the
turret's bracket and the last hit's red tick (`Compass.vehicle_marks`); in the chase view a ring
shows where the gun is laid apart from the aim; a blue chevron sits over every friendly vehicle on
the Blue Force Tracker in view, in every view and the sights (`bft_marks`: radio working,
`SideIntel.radio_ok`). The panel takes the strip's place in the HUD's bottom-centre zone: the doll
(modules by state, tracks or wheels, ERA tiles grey once fired, crew pips with role letters at
their seats), the title with the damage word, the alerts that are true (ON FIRE, TRACK THROWN,
ROLLOVER RISK, FORD, MISSILE LAUNCH, SHORT-CREWED, NO RADIO; BRIDGE MLC waits for A6's load
classes), the weapons' lines, the round selector with the loaded round bracketed and the reload
bar, the crew line, the drive line and the keys; on a small window the keys go first, then the
crew names, the drive line, the selector. The sights keep `VehicleSightOverlay`, which gains the
crew pips and the damage word and brackets the loaded round. Buttoned up in a hatch seat in first
person, `VehicleVision` (scripts/vehicles/vehicle_vision.gd) looks out through the vision blocks
(the hatch's `vision` cones, the driver's arc split into periscopes), at 1x, the player's look
picking the block, the rest of the screen masked; the driver's periscope has a night channel (the
sight channel key; NvgView's intensifier over the glass, the HUD dimmed), lost when its
`driver_vision` module is damaged, and with it destroyed he must turn out. The loader turned in
sees the bustle doors and a large round selector under his periscope. Outside sounds are muffled
in a closed seat (`Sfx.set_muffled`: -12 dB and a low-pass on the effects buses). The x-ray (2.11)
is `VehicleXray` (scripts/ui/vehicle_xray.gd) and `HitReport` (scripts/ui/hit_report.gd), built on
every peer from A2's HitEvents (which now carry the round's direction, angle, range, shooter, path
and up to 12 spall rays). The calls are in docs/audits/followups.md ("Calls made", 2026-10-23,
cg_brief 2.4); what's left is F-255 onwards there; the suite is `vehiclehud` (ui_test fits the
panel, the card and the full view).

### 2.13 AI crews and armour tactics

What the AI drivers, commanders and gunners do with all of this, on top of `VehicleAI`,
`SquadDrivers` and `DriveContact`:

- **Front to the threat.** Stopped in contact, the driver turns the hull to within 30 degrees of
  the main threat's bearing, so the thick armour faces it.
- **Hull-down.** A new `ArmourTactics.hull_down_spot(vehicle, threat_points)` (static, beside
  `SquadTactics.overwatch_spot`): a point behind a crest where the gun at turret height sees the
  threat and the hull box below it is masked (rays from the threat to the hull box's corners).
  Tanks and IFVs halt there in overwatch.
- **Shoot and scoot.** After 2-3 shots from one spot in a duel with armour, or when a launch is
  seen, reverse 30-50 m along the way they came and come up somewhere else.
- **Smoke.** A seen ATGM launch, a near miss from a big round, or a laser warning (Concord tanks
  have them) makes the commander pop smoke and reverse 50 m into it.
- **Ground sense.** The route planner avoids marsh and mud for wheeled vehicles, water deeper than
  `ford_m`, bridges below the vehicle's mass, and side slopes over 60% of the tip angle.
- **Spacing.** 50-100 m between armoured vehicles in a column (`ConvoyColumn` gap scaled by
  class), more in the open.
- **Towns.** Armour does not enter a built-up area without an infantry screen (3.6); it overwatches
  from 200-400 m outside.
- **Knocked out.** The bail-out rules (2.10.1); the crew then join the nearest friendly infantry
  group as riflemen and say so.
- **Infantry against our armour** (extends G-20): AT gunners pick the aim point by the vehicle's
  facing (side and rear first), wait for a tank to pass in an ambush, and use top attack (Javelin,
  NLAW, Konkurs is direct-only) against MBTs. Hostile AT teams learn the same.

### 2.14 Balance knobs

All in data, all Proposed:

| Knob | Where |
|---|---|
| Plate KE and CE values, `phys_mm`, normals | data/vehicles.json `plates` |
| Tile kinds' bonuses, triggers, coverage | data/vehicles.json `tiles`, `era_kinds` |
| Module hp, `absorb_mm`, fire chances, rack detonation chances | data/vehicles.json `modules` |
| Penetration tables, ricochet bands, normalisation, overmatch, fuzes, `module_dmg`, spall | data/shells.json, data/warheads.json |
| Package contents, weights, prices, tiers | data/vehicles.json `packages`, data/prices.json `packages` |
| Reload, switch and seat times; stabiliser limits; sight magnifications; LRF error | data/vehicles.json `weapons`, `optics`, `crew` |
| Traction and rolling resistance by ground; `power_kw`; `ford_m`; bridge `mlc` | data/vehicles.json, data/terrain_presets.json `ground` |
| Ammo, module and repair prices | data/prices.json `ammo`, data/ground_supports.json `module_prices` |
| AI lay times, aim errors, ammo choice table | data/doctrines.json `crew` (per doctrine) |
| Effects budgets | `VehicleFx` constants |

A tuning pass after the first armour playtest uses the "who beats what" table (2.4.6) as its
target and the x-ray log to see what actually happened.

## 3. The AI commander

Learned from HAL: a virtual commander per side that sees the battlefield only through reports,
gives its groups roles, times them together, keeps a reserve, pulls back what's broken and
counterattacks what it lost. Learned from LAMBS and VCOM: groups that help each other without
being told. The bar is the one the Captain set: as good as HAL with LAMBS and VCOM running.

### 3.1 The shape

One `SideCommand` per side present in a zone (new `scripts/campaign/side_command.gd`, host only).
It is built from three parts:

```
SideCommand            per side: the plan, the tasking cycle, reserves, counterattacks
  |-- SidePicture      what the side knows: contact reports, with latency and ageing
  |-- GroupBoard       the side's groups (live or virtual), their strength, CE and task
  `-- plan             HotZonePolicy (EnemyCommand's rules) | OperationPlan | DefencePlan
        |
        v  orders (HcOrder records: the same record and lifecycle as high command, 5.1)
SquadOrders            one per group: phase machines, sectors, watchdogs (docs/high_command.md 5.2)
SquadTactics           contact drills, masked and biased by the order (built)
SquadAI                every soldier (built)
```

- **One order executor for everyone.** The AI commander gives its groups the same `HcOrder`
  records the player gives the hero squads, run by the same `SquadOrders`. A group can't tell
  whether a human or the commander tasked it, so every improvement to execution (progress
  watchdogs, "held up", "unable", lift and shift) serves both.
- **Who it commands.** The friendly `SideCommand` commands the **allied forces**: the employer's
  troops and vehicles in an operation, and US forces in the living war (7.3). It never commands
  the company: the player squad, the hero squads and the elements the company paid for
  (`AlliedTroops`) are the player's. The commander plans around them (3.4.4) and the players
  work with it through requests (4).
- **The hostile side** runs `SideCommand` too. In hot zones its plan is `HotZonePolicy`: the
  rules `EnemyCommand` has today (hold, reinforce, probe, counterattack at 3:1, contain, hunt,
  consolidate, reoccupy, decapitation), moved, not rewritten. In operation zones it runs a
  `DefencePlan` (3.7).
- **Where it lives.** `ZoneLevel` adds a `SideCommand` per side when the zone has more than the
  player's side and a garrison (`EnemyCommand`'s spot at zone_level.gd:143), plus the friendly one
  in operation zones. `EnemyCommand` stays as a thin shim for its callers (`HotZoneOps`,
  `EnemyResponse.request`) until they call `SideCommand` directly.

### 3.2 The picture: what a side knows

New `SidePicture` (`scripts/campaign/side_picture.gd`, RefCounted, pure where it can be).
**Built in B1** (2026-10-22) with `GroupBoard` and `SideIntel`; the details it settled are in
section 10, calls B1.1-B1.18.

**A contact report** is a record:

```
{id, kind: inf|mg|at|sniper|soft_vehicle|light_armour|ifv|mbt|static_gun|mortar|air,
 count, pos, uncertainty_m, heading, speed, seen_at, reported_at, by: group id, confidence}
```

- **Where reports come from.** Each group's `Squad.known` and `clusters()` (built), the first time a
  cluster is fresh and every 30 s while it stays fresh; vehicle commanders' sightings; player tags
  (`EnemyTags`) and "Report enemy position" (`PeopleLayer.server_report`); UAVs and lookouts
  (already reporting through `EnemyTags.server_tag_reported`); for the hostile side, `Alert`'s
  reports, as today.
- **Latency.** A report reaches the picture after the sender's radio delay:

  | Side | Delay |
  |---|---|
  | Company and allied regulars with radios | 3-8 s by the reporting leader's skill |
  | Eastern Concord | 8-20 s |
  | Cartels and Black Ridge | 15-45 s |
  | Ashen Banner, Valley Shura, Highland Front | as `Alert` today: 60-15 s by discipline, x1.5 under fire |
  | Comms down (dead radio, the comms mast, a jammer) | x3 |

  A group with no radio (or whose radio man is down) reports nothing until it meets another
  group within shouting distance (80 m: `SHARE_CONTACT_M`).
- **Merging.** A report merges with an entry of the same kind within 25 m (infantry) or 60 m
  (vehicles) seen in the last 60 s: count takes the higher, position the fresher, uncertainty the
  smaller.
- **Ageing.** Uncertainty grows from the moment of the sighting: 1.5 m/s for infantry, 5 m/s for
  vehicles, capped at 600 m. An entry is dropped 10 minutes after its last report (15 for
  vehicles). The UI shows it **fresh** (under 30 s), **aged** (under 3 min) and **stale** (older),
  4.4.
- **Fairness.** Nothing reads true positions. A test checks that every input to the commander and
  every marker a player sees traces back to a report (as high_command.md 5.5 asks for the hero
  planner).
- **Blue Force Tracker.** The side's own vehicles with a working radio are always in its picture
  at their true positions (a real system), and its own groups by their last sitrep (every 30 s).
  Vehicles whose radio module is destroyed go grey.
- **Comms.** The hostile picture still loses its comms with the mast (`Alert.comms_down`); the
  friendly one degrades under a jammer (cghath's drone jammer) and when the operation HQ's relay is
  hit (an objective in some operations).

### 3.3 The group board

New `GroupBoard` (`scripts/campaign/group_board.gd`). One row per group, whether it's live soldiers
or a `Virtualizer` profile (the board holds the owner's record; `Virtualizer.up`, `lead` and
`points` already answer for both):

```
{id, side, kind, callsign, strength_cp, at_cp, ce, ammo_band, pos, mounted_in: [vehicle ids],
 task: HcOrder id, role, availability, sector, rally, virtual: bool}
```

- **Kinds:** rifle squad, weapons team, AT team, gun team, mortar section, recon team, mech
  infantry (an IFV and its squad), armour section (2 tanks), armour platoon (4), light armour
  (MRAPs, armed technicals), transport, QRF, engineers (a demolition team for bridges, 6.4.4).
- **Combat power (CP)** keeps `EnemyCommand`'s scale so hot zones don't need retuning: 1 per man x
  skill x 1.5 with body armour, an armed technical or MRAP 4, an IFV 8, an MBT 16. **AT power**
  (`at_cp`) separately: an AT4 or RPG 1, a Javelin, Konkurs or TOW 3, an IFV with an ATGM 4, an MBT
  6. A plan never sends a group with no AT power at a known tank.
- **Combat effectiveness (CE)** as in high_command.md 5.2 for infantry
  (`up/size x 0.5 + ammo x 0.25 + morale x 0.25 - 0.1 x urgent casualties`); for vehicle groups
  `crew up x 0.4 + mobility x 0.2 + firepower x 0.2 + ammo x 0.2` from the module states (2.2).
  GREEN at 0.7 and up, AMBER at 0.45, RED below.

### 3.4 Roles and tasking

#### 3.4.1 Roles

| Role | What the group does | Compiles to (built or from high_command.md) |
|---|---|---|
| **Assault** | Moves to an attack position, waits for its support to be set, assaults or clears the objective, consolidates | `Attack` order: `order_assault`, `order_clear`, `clear_op` |
| **Support by fire** | Takes an SBF spot, suppresses the objective, lifts and shifts for the assault | `Support by fire` order, `safe_to_fire` |
| **Flank** | Moves on a flank route in its sector to hit the objective from the side | `order_flank`, `flank_route`, `lanes` |
| **Recon** | Moves ahead with an avoid-contact posture, observes, reports | `Move` with `contact: avoid`; reports to the picture |
| **Reserve** | Holds at a rally point out of sight (mounted if mechanised), ready | `Hold` at the rally |
| **QRF** | A reserve tied to one area, sent on any contact there | `Move` + `Attack` on trigger |
| **Screen** | Covers a flank or an armour group's sides; kills AT teams near it | `Defend` facing out, sector |
| **Defend** | Holds a site, a building or a line | `Defend` (garrison or frontage) |
| **Overwatch** | Armour or an MG on high ground watching an approach | `ArmourTactics.hull_down_spot`, `overwatch_spot` |
| **Fire support** | Mortars or artillery on targets from the picture | `MortarTeam` ordered target, the allied fires (4.2.6) |
| **Resupply** | An ammo or fuel truck to a group that is amber on ammo | `Move` + the rearm action (2.9) |
| **CASEVAC** | A vehicle or medic team to a group with casualties | `Move` + pick-up |
| **Transport** | Carries a group from A to B | `SquadDrivers` |

#### 3.4.2 Suitability

| Group kind | Assault | SBF | Flank | Recon | Reserve, QRF | Screen | Defend | Overwatch |
|---|---|---|---|---|---|---|---|---|
| Rifle squad | 1.0 | 0.6 | 0.9 | 0.5 | 0.8 | 0.8 | 1.0 | 0.3 |
| Weapons team, gun team | 0.2 | 1.0 | 0.3 | 0.2 | 0.4 | 0.7 | 0.8 | 0.9 |
| AT team | 0.3 | 0.5 | 0.6 | 0.2 | 0.6 | 1.0 | 0.8 | 0.7 |
| Recon team | 0.2 | 0.4 | 0.4 | 1.0 | 0.3 | 0.5 | 0.4 | 0.6 |
| Mech infantry | 1.0 | 0.9 | 0.8 | 0.6 | 1.0 | 0.8 | 0.9 | 0.7 |
| Armour section | 0.7 (in the open), 0.2 (in a town) | 1.0 | 0.6 | 0.4 | 1.0 | 0.5 | 0.6 | 1.0 |
| Light armour | 0.5 | 0.8 | 0.7 | 0.8 | 0.9 | 0.8 | 0.5 | 0.6 |

#### 3.4.3 The tasking cycle

Every `TASK_S` (20 s in operation zones; hot zones keep 30 s) and at once on a trigger (an
objective falls or is lost, a group goes RED, a counterattack is seen, a request comes in):

1. **Needs.** The plan lists what the current phase needs: each objective needs an Assault and an
   SBF; each open flank of the axis a Screen; each lost site a Counterattack or Contain; the
   reserve its share (3.5.2); each AMBER group on ammo a Resupply; each group with urgent
   casualties a CASEVAC.
2. **Score.** For each need and each available group:
   `suitability x CE x (1 - distance / reach) x availability - commitment`, where `reach` is
   1,500 m on foot and 4,000 m mounted, `availability` is 0 for a group mid-assault, 0.5 in
   Defend in a quiet sector and 1 for a reserve or an idle group, and `commitment` is 0.2 for any
   group already tasked (hysteresis, so groups aren't flipped back and forth).
3. **Assign** greedily, the highest need first. An Assault is never assigned without its SBF, and a
   group with no AT power never to a need with known armour.
4. **Issue** each assignment as an `HcOrder` with a sector (3.4.5) and a rally point.
5. **Log** each decision in the session log as `[cmd]` lines with the reason ("Iron 2 to SBF on
   OBJ BRASS: score 0.81, nearest IFV"), the way `[tactics]` lines work today.

#### 3.4.4 Around the company

The company is a group on the board the commander **does not task**: its position comes from BFT,
its intent from the operation's company task (6.3). The commander plans around it: the company's
objective gets an allied SBF when the plan has one to spare; allied lanes avoid the company's
sector; and when the company asks for something (4.2), the commander weighs the request with
everything else (4.2.10).

#### 3.4.5 Sectors

Every task gets a sector: a corridor around its axis (half-width the larger of 30 m and half the
frontage), as in high_command.md 5.2. The commander keeps sectors from overlapping and moves a
lane that would cross the company's area (each player's 100 m bubble and the company's objective
box). Sectors feed `SquadOrders.safe_to_fire` (4.5).

### 3.5 Phases, reserves and falling back

#### 3.5.1 Phase timing

- **H-hour:** phase 1's orders wait as `waiting` until the operation's H-hour (`hhour` go code),
  or until the company crosses the line of departure if the operation is player-paced (6.3).
- **Synchronisation:** an Assault waits at its attack position until its SBF reports `set`, or
  `SYNC_TIMEOUT_S` (120 s) passes, then goes ("Iron 2 is set." "Saber 1, go.").
- **Consolidation:** an objective counts as taken when no known enemy is in it for
  `CONSOLIDATE_S` (90 s). The assaulting group then defends it, casualties go back, ammo comes
  forward.
- **Next phase:** when every required objective of the phase is taken.
- **Stalls.** If the phase's main objective hasn't fallen after `PHASE_STALL_MIN` (the phase's
  limit x 0.6), the commander commits the reserve to it. If it still hasn't fallen at the limit,
  it shifts the main effort to the phase's other axis if the plan has one, or calls fire support
  and pauses the phase for 5 minutes, then tries again. At 1.5x the limit the operation stalls
  (6.5).

#### 3.5.2 Reserves

- At each phase's start, a quarter of the side's CP (`RESERVE_SHARE` 0.25) is kept in reserve at a
  rally point out of the enemy's sight, mounted if it has vehicles.
- **Committed** when an assault stalls (under 20% progress in 5 minutes, or the assault group
  AMBER), when a counterattack bigger than the defenders is seen, or to **exploit**: an objective
  that fell in under half its time sends the reserve through to the next one.
- **Refilled** from groups that reconstitute (3.5.3) and from reinforcements arriving at the line of
  departure.

#### 3.5.3 Falling back

- **AMBER:** the group stops advancing, holds in its sector and asks for help (SBF, a medic, ammo)
  on the coordination net. An AMBER assault waits for its support.
- **RED:** the group breaks contact to its rally point and reports "Saber 2 is red". There it
  **reconstitutes**: casualties are evacuated, ammo comes up, and two RED squads of the same kind
  merge into one.
- **The side:** when its total CE falls under 0.4 or its losses pass `WITHDRAW_SHARE` (0.5), the
  friendly side falls back to the last phase line it held and digs in; the hostile side
  consolidates, as `EnemyCommand` already does.

### 3.6 Armour and infantry together

| Ground | Who leads | How |
|---|---|---|
| Open ground | Armour | Tanks in overwatch, hull-down at 800-2,000 m; IFVs carry the infantry and dismount 300-500 m short of the objective in dead ground, then go to SBF for their dismounts |
| Woods and broken ground | Infantry | Armour follows on the tracks at 100-200 m, overwatching clearings |
| Towns | Infantry | Armour stays 50-100 m behind the lead infantry, never first round a corner, and never sits still in sight of uncleared buildings for more than 60 s. The infantry clear; the armour kills what they mark |
| Night | Armour with thermals | Thermal-equipped vehicles lead the recon |

- **Pairing.** An armour section (or an IFV) is paired with an infantry group as its **screen**:
  they move as one, within 50-150 m, at the infantry's pace when it's dismounted. The screen's
  sector faces out; its first job is the AT teams near the armour.
- **Target hand-off.** An infantry group with a fortified target (an MG in a building, a bunker)
  that it can't take marks it to its paired armour ("Gun 2, MG in the two-storey building, 300 m,
  my tracer"); the tank fires AMP delay or HEAT at it. The same request is open to players (4.2.4).
- **Armour asks for infantry.** A tank that sees an AT team it can't hit (in dead ground, behind
  cover), or is in a town without its screen, asks its pair, or the nearest infantry, or a player
  (4.3): "Saber 2, ATGM team in the treeline at 040 052, need it cleared before we move."
- **Dismount points** come from `ArmourTactics.dismount_spot`: dead ground from every known
  enemy on the axis, 300-500 m short.

### 3.7 Counterattacks

The hostile `SideCommand` keeps `EnemyCommand`'s rule (the Captain's, 2026-10-17): **a lost site is
retaken only by a force that can retake it** (3:1 by CP, called off under 1.5:1), otherwise it is
contained. What's added:

- **Armour counts.** CP includes vehicles; a counterattack against known friendly armour must
  bring AT power at least equal to the armour's CP / 4, or it doesn't go.
- **Timing.** The force assembles at a rally point out of sight, 600-1,200 m from the objective
  in an operation zone (150 m in a hot zone, as now), and attacks 5-12 minutes after the loss,
  aiming to arrive before the friendly side has consolidated, or at dusk or dawn if that's under
  20 minutes away. A mortar or artillery preparation lands 60 s before the assault.
- **The mobile reserve.** In an operation, the defender's `DefencePlan` holds a mobile reserve
  (its armour and mechanised groups) and commits it to the most threatened phase line once the
  attacker is through the first.
- **Probes first** when the picture of the friendly force is stale (as today).
- **Telegraphing.** Players hear it coming the way `HotZoneOps` tips the squad off today: an
  allied recon team, the UAV, or an intercepted enemy radio ("Enemy armour massing at 038 061,
  expect a counterattack on the bridge in about five minutes").

### 3.8 Scaling with virtualization

- **Tasks don't care if a group is live.** The commander sets orders on the board's handles. A
  virtual group's order sets its profile's route and target (`squad.patrol`, as the Virtualizer
  already reads), and it moves at its pace along roads or straight legs.
- **Allied groups are tracked** by the `Virtualizer` (today `AlliedTroops` elements are not),
  except groups within `HC_LIVE_M` (700 m) of any player, which stay live so players see the
  allies they fight beside.
- **Off-screen fights** between virtual groups at war (built: `CONTACT_M` 150, `ROUND_S` 10)
  gain an armour table. Each group has a soft attack, a hard attack and whether it's armoured:

  | Group | Soft attack | Hard attack | Armoured |
  |---|---|---|---|
  | Rifle squad | 6 | 1 (3 with AT) | no |
  | Weapons team | 8 | 2 (4 with AT4s) | no |
  | AT team | 2 | 6 | no |
  | Technical | 5 | 1 | no |
  | MRAP | 5 | 1 | light |
  | IFV | 6 | 4 (8 with an ATGM) | yes |
  | MBT | 6 | 10 | yes |

  Hits against an armoured group use hard attack, against the rest soft. A vehicle knocked out
  off-screen becomes a real wreck where it was (as dead men are real bodies today).
- **Costs:** a tasking cycle at most 1 ms per side on the host for 40 groups; the picture merge
  uses a 64 m spatial hash; the order executor runs only for live groups (virtual ones step their
  profile).

## 4. Players and friendly forces

The common-sense rule for all of it: a friendly unit answers a request the way a real unit would,
says yes with an ETA or no with the reason, and does what it said. Nothing happens silently and
nothing teleports (bots act like players).

### 4.1 How a request works

New `RequestBroker` (`scripts/campaign/request_broker.gd`, host only, one per level, installed by
`MapNodes.install` like `MapMarkers`).

**The record** (JSON-safe, replicated to the side like `HcOrder`):

```
{id, kind, by: peer, from_pos, target: {pos, ref, radius}, to: group id or "",
 state: sent|acked|declined|countered|en_route|on_station|done|cancelled|failed,
 eta_s, why, counter: {pos, eta_s} or null, at, until}
```

**The flow:**

1. **Ask.** The player asks through the contextual menu (look at a friendly unit, an enemy, a
   casualty or the ground: 5.5), the map's right-click, the HC camera, or a typed voice phrase
   ("request suppression on my mark"). With no unit named, "the nearest that can" is meant.
2. **Pick the answerer.** The broker lists friendly groups with the capability (4.2), with a
   working radio (or within 80 m shouting distance), ordered by ETA. It asks the friendly
   `SideCommand` whether it can spare the first (`can_spare(group, request)`, 4.2.10).
3. **Answer** within 2-6 s (a radio delay, longer for a group in contact): **accept with an
   ETA**, **decline with a reason**, or **counter-offer** ("No line of sight from here, we can be
   on the ridge in 90 seconds").
4. **The player sees it** as a request card on the HUD (who, what, state, ETA counting down) and a
   marker on the map; a counter-offer has one-key accept or cancel.
5. **Done** when the job is done (4.2), the player cancels ("cancel", or right-click the card),
   or `until` runs out. Failures say why ("Iron 2: lost the target", "Saber 1: we're pinned,
   suppression lifted").

**Limits:** three open requests per player; the same request twice merges; a declined request
can't be repeated at the same group for 30 s unless something changed (it moved, got ammo).

### 4.2 The request catalogue

#### 4.2.1 Suppress

| | |
|---|---|
| **Trigger** | Look at an enemy, a building or a known marker: **Request suppression**. Map: right-click a point or marker. Phrase: "suppress that / suppress my mark" |
| **Who** | The nearest allied group with an MG, an IFV, a tank or a gun team, with (or close to) a line of sight, not mid-assault |
| **UI** | Card: "Iron 2: suppressing building at 041 053, 60 s"; a fan drawn on the map from the group to the target; a countdown |
| **Response** | Moves to an SBF spot if needed (the ETA is that move), then fires bursts on the target for 60 s (or "until I say": `lift` from the card). Lifts or shifts by itself for danger close (4.5) |
| **ETA** | 0-10 s if already in position, else its move time |
| **Refusals** | "No line of sight" (with a counter-offer if a spot is within 200 m), "We're pinned", "Friendlies in the lane", "Committed to an assault", "Ammo black", "Out of range", silence if it has no radio and is out of earshot |

#### 4.2.2 Medic and CASEVAC

| | |
|---|---|
| **Trigger** | Look at a casualty (or yourself, Ctrl+Alt as now): **Request medic** or **Request CASEVAC**. Players already have "Medic!" and "Treat me" (`Soldier.call_medic`, `treat_me`); those stay for the player squad, this reaches allied units |
| **Who** | Medic: an allied group's medic within 300 m that isn't treating someone urgent. CASEVAC: an allied vehicle in the operation that can carry a stretcher case (an IFV, AAV, MRAP), or the medevac helicopter (the existing support, paid as today) |
| **UI** | Card with the medic's name and ETA; the medic shows on the HUD as a green cross moving in |
| **Response** | The medic moves in at a careful pace (bounding if under fire), treats with the full medical model, and says what he did ("Tourniquet on, he's stable"). CASEVAC drives to the nearest covered point within 100 m, the casualty is carried to it, and it drives the casualty to the casualty collection point at the line of departure |
| **ETA** | Distance at 2.5 m/s (medic), the route time (vehicle) |
| **Refusals** | "No medic free", "Can't reach you under that fire: move him behind the wall to your west" (counter-offer to a covered point), "Hot LZ" (helicopter, as the existing wave-off does) |

#### 4.2.3 Smoke

| | |
|---|---|
| **Trigger** | Look at or mark a point or a line (drag): **Request smoke** |
| **Who** | A group within 300 m with smoke grenades or a vehicle with dischargers (screen in front of itself), or an allied mortar section (screen anywhere in range) |
| **Response** | Grenades: thrown at the point (G-14's smoke logic). Mortars: smoke rounds on the line, building a screen in 20-30 s that lasts about 2 minutes, then a re-lay if asked |
| **ETA** | Grenades 5-10 s; mortars 60-90 s |
| **Refusals** | "No smoke left", "Out of range", "Danger close for mortar smoke" (within 50 m of friendlies: the player confirms) |

#### 4.2.4 Armour support

| | |
|---|---|
| **Trigger** | Look at an allied armoured vehicle, an enemy, a building, or mark a point: **Armour: move up / engage / overwatch here** |
| **Who** | The nearest allied armour section or IFV not mid-assault, with a route |
| **Response** | Move up: comes to a hull-down or covered spot near the player. Engage: fires on the target (HE or AMP for a building, sabot for armour). Overwatch: takes the spot and watches the bearing |
| **ETA** | Its route time |
| **Refusals** | "Not entering the town without a screen: clear the street first" (3.6), "Bridge won't take us", "Route not clear of AT", "Ammo low, rearming: 4 minutes", "Committed" |

#### 4.2.5 Hold, or cover my move

| | |
|---|---|
| **Trigger** | Look at an allied group: **Hold here** or **Cover my move** (then mark where you're going) |
| **Who** | That group |
| **Response** | Hold: it stops and holds its position (it won't advance past you). Cover: it suppresses the known enemy positions facing your route ("Covering!") until you call **Set** or reach the mark, or 60 s pass |
| **Refusals** | "No line of sight on the threat", "We're pinned", "Our orders are to push: 2 minutes, then we're on you" (the commander needs it; the counter-offer is a delay) |

#### 4.2.6 Fire support

| | |
|---|---|
| **Trigger** | The existing fire mission panel and Support > Fire support, with a new **Allied fires** source in operations |
| **Who** | The operation's allied mortar section or artillery battery (its fire direction centre, callsign "Thunder") |
| **Response** | The FDC answers in proper order: "Thunder, adjust fire, over." "Shot, over." "Splash, over." Rounds use `FireSupport`'s existing flight, dispersion and danger-close rules |
| **ETA** | `response_s` as data (mortars 20 s, artillery 40 s) plus flight |
| **Rationing** | Allied fires are free to the company but rationed by the commander: the plan's main effort first, then requests in contact, then the rest; a battery has `rounds_per_phase` |
| **Refusals** | "Unable, priority to the bridge", "Danger close, confirm" (the existing confirm), "Out of range", "No rounds left this phase" |

#### 4.2.7 Transport or a pick-up

| | |
|---|---|
| **Trigger** | **Request pick-up** at my position or a mark, **to** a mark |
| **Who** | An allied transport (truck, MRAP, IFV, AAV) in the operation not carrying troops, or the existing helicopter transport (paid) |
| **Response** | Drives to the nearest covered point within 150 m of the pick-up, waits 90 s, drives to the drop-off (`SquadDrivers` columns and contact drills) |
| **Refusals** | "Hot area, move 300 m south and we'll take you", "No vehicles free", "Route impassable" |

#### 4.2.8 Ammo resupply

| | |
|---|---|
| **Trigger** | **Request ammo** (or a nearby allied soldier: "need ammo"), or for a vehicle: **Request rearm** |
| **Who** | Infantry: the nearest allied group that isn't amber on ammo itself (one man runs over two magazines of your calibre and a belt if they have one: "Ammo coming!"). Vehicles: the operation's ammo or fuel truck |
| **Response** | As described; the truck drives up and the rearm action runs (2.9.2) |
| **Refusals** | "We're amber ourselves", "Wrong calibre", "Truck's 6 minutes out" (a counter-offer) |

#### 4.2.9 Sitrep

**Look at a group or click it on the map: Sitrep.** "Saber 2: green, 7 up, ammo good, holding at
the mosque, two enemy in the orchard to our north, 200 m." Never refused unless the group is dark.

#### 4.2.10 How the commander weighs requests

`SideCommand.can_spare(group, request)`:

- **Never** from a group executing an assault, or the last reserve while a counterattack is seen.
- **Yes** from a group in Defend in a quiet sector, an idle group, or a reserve when the requesting
  player is in contact and the request is suppress, medic, smoke or ammo.
- **A counter-offer** with a delay when the group's current task ends within 3 minutes.
- **Weighted up** when the player is doing the plan's main effort; down for a player far from the
  operation's axis.

### 4.3 Allies asking players

The other direction, through the same broker, raised by allied groups (and by the hero squads,
whose requests to the commander are already in high_command.md 4.2).

| Ask | Raised when | Example |
|---|---|---|
| Contact support | An allied group in contact goes AMBER, a player is within 600 m, and no allied group can help | "Any station, Saber 2, contact front, need support at 041 053." |
| Medic | An allied casualty has no medic in reach, and a player medic (the role) is within 300 m | "Man down at the wall, 120 metres east of you, need a medic." |
| Clear an AT threat | An allied tank sees an AT team it can't hit (3.6) | "Anvil 1, ATGM team in the treeline at 040 052, need infantry to clear it before we move." |
| Ammo | An allied group is red on ammo near a player | "Saber 3, black on 5.56, anyone close?" |
| Cover a crossing | An allied group about to cross open ground near a player | "Saber 1 crossing the wadi, cover us from your position." |
| Tow or recovery | An allied vehicle is stuck or immobile under fire | "Iron 3, track's off, need cover while we fix it." |

- **The UI:** a prompt card with the asker, the ask, the grid, the distance and a bearing arrow,
  and `hc_approve` / `hc_deny` (the high command keys, Y / N by default), 30 s to answer. One card at
  a time; others queue.
- **Accepting** puts a marker and waypoint on the map and tells the asker ("Copy, waiting on
  you"); the asker adjusts (holds its move, shifts fire off your approach). The broker sees the
  job done when the threat is gone, the casualty treated, the ammo given or the crossing done.
- **Sending a squadmate** instead: the card's second option ("Send Okafor") when the player squad
  has a man with the right role in reach.
- **What it's worth:** each answered ask raises the employer's reputation by 1 (at most 5 an
  operation) and adds to the operation's cooperation bonus (6.5). Declining costs nothing but the
  outcome: an unhelped group may lose men, and the employer counts allied losses in the debrief.

### 4.4 Shared spot reports

The friendly `SidePicture` is what the players see, and only that:

- **On the map:** each entry as an icon by kind (an APP-6-inspired frame: infantry cross, armour
  oval, MG, AT, mortar), with a count, the age ("2 min") and the uncertainty circle; the reporter
  on hover ("Iron 2, 40 s ago"). Fresh entries solid, aged dashed, stale just a circle labelled
  "last seen". This replaces nothing: it joins the `MapMarkers` intel channel.
- **In the world:** a small diamond over each entry the player can't currently see himself,
  within 800 m (a setting: on by default, the range and an off switch), fading with age. A tag
  (`EnemyTags`) a player made stays red; reports from others are amber.
- **Players feed it:** tags, "report enemy position", sitreps and lased targets (a vehicle
  commander's lase is a report).
- **The hostile side has the same**, from `Alert`, so the enemy knows what it has been told and
  no more.

### 4.5 Deconfliction

| Layer | What it does | Where |
|---|---|---|
| **Sectors** | Each task's corridor (3.4.5); groups don't fire across another group's sector unless the target is inside their own | `SideCommand`, `SquadOrders` |
| **The fire fan** | No burst with any friendly (players, the player squad, hero squads, allied groups) inside a 10-degree fan around the shot line out to the target + 30 m (`SquadOrders.safe_to_fire`, high_command.md 5.4). Every AI group and `CrewGunner` asks before each burst; `_friendly_in_line` stays as the last guard on each shot | `SquadOrders`, `CrewGunner` |
| **Player bubbles** | Every player has a 100 m bubble no allied lane crosses and no allied suppression lands in | `SideCommand` |
| **Lift and shift** | SBF shifts to depth or lifts when the supported group is within 40 m of the target, or any friendly within `DANGER_CLOSE_M` (35 m) of it: "Check fire, friendlies on target" | `SquadOrders` |
| **Indirect fire** | Allied fires never land within danger close of friendlies (mortars 150 m, artillery 250 m, as `FireSupport`) without a player's confirmation. The FDC warns over the net before each mission near friendlies ("Splash in 30, friendlies stay south of the road") and checks fire when one walks into the target area | `FireSupport`, allied fires |
| **Armour IFF** | `CrewGunner` never fires within 50 m of a Blue Force Tracker position. Players get a blue chevron in their sight over BFT vehicles in view; no hard block on players | `CrewGunner`, `VehicleSightOverlay` |
| **Routes** | Vehicle columns reserve road segments for a time window, so two columns don't meet head-on on a single track; at a junction the later one yields | `RoadRoute`, `SquadDrivers` |
| **Check fire** | Any player can call **Check fire** on a point (contextual radio): all friendly fire into 100 m of it stops for 30 s | `RequestBroker` |
| **Movement** | Lanes 5 m apart in flanks (built), separation steering (built) | |

A friendly-fire incident (a player or allied unit hurt by a friendly) is logged with the shot's
details, costs the shooter's side reputation with the employer, and counts in the debrief. A test
asserts zero blue-on-blue damage in a scripted combined fight.

### 4.6 Voice and text callouts

- **Channels:**

  | Channel | Who hears it | Look |
  |---|---|---|
  | Shout | Everyone within 40-60 m | White |
  | Squad radio | The player squad | Blue |
  | Company net | The company's players (hero squads, high command) | Cyan |
  | Coordination net | Every player in the operation: allied units, requests and answers | Green |
  | Fires net | The FDC and whoever called | Amber |
  | Intercom | Inside one vehicle | Grey, radio-filtered |

  Subtitles in the UiKit style, the channel's colour, the speaker's callsign first. The
  coordination and fires nets can be muted to text-only in the settings.
- **Rate limits and priority** follow high_command.md 6: one line per speaker per 3 s, a queue
  of 4, priority casualty > request > unable > contact > set > moving, repeats within 60 s and 40 m
  dropped.
- **Grids and bearings:** `MapGrid.grid_ref` at 100 m; distances rounded; directions as cardinal
  words on the nets and clock directions in shouts (`Callouts.contact` already does both).
- **Callsigns** (original): allied infantry Saber, tanks Anvil, IFVs Iron, mortars Hammer, the
  artillery FDC Thunder, recon Shadow, logistics Packhorse (the existing cargo run's), medevac
  Dustoff (existing), the operation HQ Citadel; numbers by platoon and section ("Saber 2-1").
- **Voice:** the existing pre-rendered Piper lines, plus a new `RadioVoice` that strings
  pre-rendered clips (digits, "grid", "metres", the compass words, callsigns, the stock phrases of
  each request and answer) into one line with radio filtering. No runtime speech synthesis.
- **A full exchange:**

  > **Player:** (looks at the farmhouse, Request suppression)
  > **Iron 2:** "Iron 2, copy, suppressing the farmhouse at 041 053, on in ten."
  > **Iron 2:** (fires) "Iron 2, suppressing."
  > **Player squad:** "Moving!" ... "Set!"
  > **Iron 2:** "Iron 2, friendlies close to target, shifting fire north."
  > **Player:** (Set) "Iron 2, lifting. Out."

## 5. High command

### 5.1 The base: docs/high_command.md, adopted

The hero-squad design in docs/high_command.md (Proposed, 2026-10-14, not built) is adopted as the
base: its groundwork (Phase 0, G1-G12), its order record (`HcOrder`) and lifecycle, `SquadOrders`,
sectors, `safe_to_fire`, CE, the company net, Command mode on the map, the HC panel and the hero
roster. Its section 14 questions are answered here (each one is in "Calls made"):

| # | Question | Answer |
|---|---|---|
| 1 | Who commands in co-op | A commander token held by the host by default, handed over at the FOB ready-up or the map panel; others request |
| 2 | Who are the men | Roster members from the start, with wages, permadeath and MIA |
| 3 | Where heroes come from | Promotion first; a rare ready-made SL and a fire-team bundle on the hiring board (Phase 3) |
| 4 | How many squads, who pays | **Two standing squads always** (5.2); more by rating (rated 4: +0, rated 5: +1, hot zone +1, operations +1, cap 4 in operations and 3 elsewhere); extra squads charged as `hc_squad` |
| 5 | Squad size | 4 at first, 8 at rank 2 |
| 6 | Disobedience | Request, then decide after the timeout; never ignore a fresh order |
| 7 | Live positions or fog | Live in the MVP; fog as a later setting |
| 8 | Does high command need a radio | No in the MVP; going dark when the hero's radio is lost from Phase 2 |
| 9 | Squads mode in the world menu | Phase 2 |
| 10 | A squad left in the field | MIA, as now |
| 11 | Objective credit | Full credit to the company; no pay share |
| 12 | Traits | As listed in high_command.md 8, no flaws for now |
| 13 | Callsigns and keys | The hero's own callsign ("Hawk 2"); `high_command` default Tab on the map, `hc_approve` Y, `hc_deny` N, all checked against `Controls.KEYS` |
| 14 | Co-op players leading a hero squad | Yes, Phase 4 |

`AlliedTroops` elements the company calls in (rifle and weapons elements, company squads, the
rebels' fighters) move onto the same `HcOrder` path: their map submenu and the support menu's
"All" orders become high command orders with a lifecycle and reports. `AlliedTroops` keeps
spawning, paying and releasing them.

### 5.2 Two high command squads from the campaign start

- **The start roster** grows by two detachments of four: two named heroes (team leaders, 4+
  missions of history written into their record so they're believable veterans) and six men,
  with roles from `Roles.layout` (each team: leader, autorifleman, medic, rifleman). Their gear
  comes from the role kits, as hires' does.
- **Callsigns** Hawk 2 and Viper 3 (the player squad is 1), editable at the FOB.
- **Money:** their wages join the daily bill; start cash rises by 14 days of their wages so the
  first fortnight isn't a trap. The standing two are never charged `hc_squad` per deployment.
- **Every contract** allows the two (the old `difficulty_squads` table becomes a floor of 2 plus
  the extras in 5.1, question 4). The ready-up page shows them pre-picked; leaving one at home is a
  checkbox.
- **The player-scalable rule holds:** with more co-op players the friendly AI budget gives the
  player squad fewer AI, not the hero squads.
- **Where the code changes:** the campaign's new-game setup (`Roster` and `Heroes.promote` for the
  two), `ContractsGen.squads_max`, `BaseHub`'s ready-up page.

### 5.3 The 3D high command camera

New `HcCamera` (`scripts/ui/hc_camera.gd`): a free RTS camera over the live zone, entered with
`high_command` (Tab on foot; the map's Command mode has a "3D" button) and left the same way.

- **Controls:** WASD or edge-pan to move, the wheel to zoom (40 m to 1,500 m above the ground),
  middle-drag to orbit, Q / E to rotate, F to frame the selection, a double-click on a squad to
  follow it. It never goes lower than 40 m above the terrain or outside the zone.
- **What it shows:**
  - terrain, water, roads, bridges, buildings (module proxies past the stream radius, as the map
    uses), landmarks;
  - **friendly markers at their true positions** (the company, hero squads and, through Blue Force
    Tracker, allied groups and vehicles): APP-6-inspired frames standing on poles over the ground,
    callsign, strength, CE pip, state glyph (high_command.md 10);
  - **enemy markers only from the side's picture**, fresh, aged or stale (4.4), with their
    uncertainty circles draped on the ground;
  - order graphics in 3D, draped on the terrain: routes, attack arrows, SBF fans, defend arcs,
    lanes, gun cones (5.4), the front line and phase lines in an operation (6.3).
- **What it hides:** every actor. The camera's cull mask leaves out the soldier, vehicle, people
  and debris render layers, so an enemy the side hasn't reported is not there to see, however
  close the camera gets. Friendlies show as their markers.
- **It doesn't stream the world in.** The camera does not join `ZoneLevel.stream_focus()`, so
  flying it somewhere doesn't spawn garrisons or load modules there; far buildings stay proxies.
- **The commander's body** stays where it was (crouched). Being hit, suppressed, or a contact
  callout within 50 m shows a red edge and the "back to body" key; a setting (on by default) drops
  you back at once when hit.
- **Co-op:** only the commander-token holder gives orders; other players may open the camera
  read-only with the same fog.
- **The 3D mission map** (the Captain's 3D menus ask) uses the same camera in **map mode** on a
  light scene built from the zone def before deployment (terrain, water, roads, module proxies,
  landmarks): the briefing's plan, insertion, objectives and known enemies in relief, tilt and
  zoom. One camera, two places.

### 5.4 The map-order HUD and gun placement

#### 5.4.1 One flow for every order

Select, order, place, face, confirm, with feedback at each step. The same on the 2D map and in the
3D camera.

1. **Select:** click a unit (Shift adds; drag a box; 1-4 pick squads; `]` cycles). The selection
   panel shows what's selected and the orders it can take.
2. **Order:** the order bar's first buttons are the contextual ones for what's under the cursor
   (5.5); the rest follow. Every button shows its key and a tooltip. Space repeats the last order
   kind used.
3. **Place:** click the point. A ghost of the order follows the cursor (a route line, a position
   frame) and shows problems live (red: "off the map", "no route", "under water").
4. **Face:** drag from the point to set the facing or the sector; release to confirm. A plain
   click keeps the default facing (toward the nearest known enemy, else along the route).
5. **Confirm feedback:** the ghost turns dotted (sent), solid (the host's ack: "Hawk 2, copy"),
   then shows the order's state on the unit's frame; a refusal flashes red with its reason.
- **Queue:** Shift with an order queues it. **Cancel:** right-click while placing; Backspace
  cancels the selected unit's current order. **Undo:** Ctrl+Z undoes the last order within 10 s if
  it hasn't started.
- **Remembered:** the last order and its posture per unit.

```
+-- HAWK 2  (4/4, green)  ------------------ order bar --------------------------------+
| [Move M]  [Defend D]  [Attack A]  [Support by fire S]  [Bound B]  [Fall back F]      |
| [Hold H]  [Regroup R] [Place gun G]  [Extract X]   | posture: aware, wedge, normal   |
+--------------------------------------------------------------------------------------+
|                    .  .  .  ghost: Move -> 041 053, facing NE (drag)  . .            |
|      [HAWK 2]=====================>( )  <- release to confirm                        |
|                                         \ facing                                     |
|  right-click: cancel   Shift: queue   Ctrl+Z: undo   Space: repeat last (Defend)      |
+--------------------------------------------------------------------------------------+
```

#### 5.4.2 Placing a gun with its cone of fire

For a gun team (`GunTeam`), a mortar team (`MortarTeam`), a squadmate carrying static weapon
loads, or a hero squad's weapons team: **Place gun**.

- **The ghost** is the weapon on the ground at the cursor, with its crew positions.
- **The cone:** the arc the team will cover (a default of 60 degrees; drag wider or narrower,
  20 to 120) and range rings at the weapon's effective and maximum range (M2 1,800 / 6,800 m,
  DShK 1,500 m, M240 800 m, Mk19 1,500 m point and 2,200 m area). For a mortar: the minimum and
  maximum rings, and when a target is marked the dispersion ellipse there with "IN RANGE",
  "TOO CLOSE" or "TOO FAR".
- **Terrain-masked:** a new pure `Viewshed` (`scripts/ai/viewshed.gd`) casts 64 rays across the arc
  from the muzzle's height and samples the terrain heights (`ZoneTerrain`) and the coarse building
  boxes every 10 m out to the effective range. Ground the gun sees is shaded green, dead ground
  hatched dark, and a blocking crest or wall within 30 m red ("blocked close in"). About 4,000
  height samples: under 2 ms, recomputed at most 10 times a second while the ghost moves.
- **Read-outs:** height over the target area, how many known enemy positions can see the spot
  (from the picture), and cover at the spot.
- **Confirm:** the team moves there, sets up facing the arc's centre and fires only inside it.
  `GunTeam` gains a `sector` (two bearings) that today's flank check doesn't have; `MortarTeam`
  a firing point.

```
                        6,800 (max)
                  . ' ' ' ' ' ' ' ' ' .
              . '    1,800 (effective)  ' .
            .     ___________________      .
           /     /:::::::##::::::::::\      \      ::: ground it sees
          /     /::::::::####:::::::::\      \     ### dead ground behind the ridge
         /     /:::::::::::::::::::::::\      \
        /_____/__________ (G) __________\______\   (G) the M2, crew of 2, facing 045
                       drag to widen: 60 deg
   HEIGHT +22 m over the village   SEEN BY: 1 known enemy position   COVER: wall
```

### 5.5 Contextual orders and requests

New `ContextResolver` (`scripts/ui/context_resolver.gd`, pure): given what's under the crosshair
or cursor, what's selected and the situation (in contact, a casualty near, in a vehicle), it
returns the ordered options. The same resolver serves the world, the map and the HC camera.

| Looking at / selected | First options |
|---|---|
| A squadmate | Follow, Hold, Move here, Heal, Swap kit |
| A hero squad (in the camera or on the map) | Move, Defend, Attack, Support by fire, Regroup |
| An allied unit (not ours) | Request: suppress (in contact) or medic (a casualty near), then smoke, armour, hold or cover, fire support, transport, ammo, sitrep |
| A door or building | Stack up, Breach (the right options for the door), Clear; with armour paired: Engage the building |
| A casualty | Treat, Carry, Call a medic, CASEVAC |
| Our vehicle | Get in (the best free seat), Drive, Take the gun, Command |
| An allied armoured vehicle | Request armour support, Ride with them |
| An enemy (or its marker) | Target, Suppress, Tag, Report; with a gun team selected: Place gun to cover it |
| A gun team selected | Set up here, Facing, Pack up |
| Ground | Move, Hold here, Place the gun, Mark |
| Inside a vehicle (the crew wheel) | Driver, gunner and loader orders (2.5.2), Pop smoke, Bail out |

- **One key** (`context`, proposed middle mouse; checked against `Controls.KEYS`) does the top
  option; holding it opens the radial with the rest and "More..." (the full command menu).
- **Recently used first:** each context keeps its last three choices on top.
- **Everything stays reachable:** the number-tree `CommandMenu` and its keys are unchanged; the
  map right-click menu keeps markers; the `InteractionMenu` (Left Ctrl) gains the squadmate
  orders it lacks today.

## 6. Combined arms and invasion missions

The company is hired by governments to fight beside their forces in big operations: the
company's squads and hero squads, allied infantry and armour columns, fire support, static weapon
teams and AAVs, in zones big enough for armour.

### 6.1 Employers and operation contracts

- **Who hires:** the US, the UK and Canada (already employers with their own boards and
  quartermasters), and one new foreign government, **the Vessmark Defence Ministry** (a fictional
  small northern European state with an expeditionary battlegroup in the coalition). Vessmark is a
  data row in data/factions.json (employer, lawful, allied with the US, UK and CA, kit reusing
  `allied_ca`'s weapons with its own grey-green camo variant, its own flag, names from the UK set
  for now). Its operations are smaller (hold a town, seize a crossing) and pay a little better
  (x1.1) to win the company over.
- **A new contract kind, `operation`**, with five types (6.4). Its record adds to a contract's
  usual keys:

  ```
  {"kind": "operation", "op_type": "phased_invasion|beach_landing|armoured_thrust|seize_crossing|hold_town",
   "op_zone": "op_<seed>", "covers": ["landing_beach", "cove_outpost", "ashfield"],
   "phases": [{"id": 1, "name": "PL COPPER", "objectives": [...], "company_task": {...},
               "pay_share": 0.2, "limit_min": 25}],
   "friendly_oob": [...], "enemy_oob": [...], "allied_fires": {"mortar": 40, "artillery": 24},
   "attached": [...], "h_hour": "dawn|now|player"}
  ```

- **Where they come from:** each employer front in the living war (7.3) posts one operation on that
  employer's board, refreshed every 3 days (`Contracts.front_offer` extended). Vessmark offers
  appear when the US has a front (it joins US operations). Operations need the employer at
  **trusted** or better (rep 30).
- **What the company gets:** the zone, the allied forces, allied fires, attached armour if the type
  has it (6.4), and its own supports at its own cost as usual.
- **Attached armour.** The employer can attach vehicles to the company for the operation: a
  Bradley section on an armoured thrust, an Abrams section on a phased invasion. Players may crew
  them (the reason to put a player in an Abrams), or leave them to their allied crews under the
  company's high command. They go back after the operation.

### 6.2 Operation zones (about 8 km)

#### 6.2.1 Size and layout

An operation zone is **8,192 m** square (a multiple of `ZoneDef.SIZE_STEP_M` 128; four times a
hot zone's side). It is generated fresh for the operation (zones start fresh each contract) by a
new `ZoneDef.generate_operation(seed, op_type, covers)`, from the region and assets of the
contract zones it **covers**: two to four neighbouring zones on the region map (`RegionMap.links`)
held by the target faction. The result flips all of them (6.6).

The layout runs in bands along an **axis of advance** from the friendly edge (or the sea):

```
 friendly edge / sea                                                        enemy depth
 0 m        800        2,500       3,500            5,500             7,600     8,192
 |  START   | BAND 1   | BAND 2    | BAND 3          | BAND 4           |  keep  |
 |  LD or   | outposts,| the       | the town (or    | HQ, a QRF base,  |        |
 |  beach,  | a village| crossing: | two villages),  | the depth target:|        |
 |  FOB or  | a check- | a river   | the main road   | airfield, harbour|        |
 |  LHD     | point    | (2-4      | through it      | or oil site      |        |
 |          |          | crossings)|                 |                  |        |
 |== MSR (main supply route) runs the length, two laterals cross it ==================|
```

- **Band 2** is a river crossing the axis (cghath's `ZoneWater`, given a hint: `{axis, at_m}`) with
  one concrete road bridge (MLC 80) on the main road, one steel truss (MLC 40) and one or two fords
  (`ZoneBridges`); without a river (some inland ops), a ridge line with two passes.
- **Landmarks** come from the covered zones' assets (data/landmarks.json): the harbour on the coast
  edge for a beach landing, the airfield or oil site in band 4, the mosque and fuel station in the
  town. `ZoneModules.place_landmarks` gets band hints.
- **Terrain preset** from the covered zones (coast: `amphibious_coast` or `coastal_lowland`;
  inland: `river_valley`, `desert_wadi`, cghath's farmland or marsh).
- **Sites** (modules) as hot zones generate them, scaled: 8-12 outposts and checkpoints, 1-2 QRF
  bases, 1 HQ, 3-5 villages, 1 town (urban types where cghath's city work allows).
- **Roads:** the MSR, two laterals and tracks; road segments carry bridge `mlc` (2.8.5).
- **A friendly FOB** at the start edge for inland operations (the allied staging FOB, 8), or the
  LHD standing off 2,500 m for coast ones.

#### 6.2.2 What has to change to make 8 km run

| Today | For 8 km | Where |
|---|---|---|
| Terrain heightmap: 4 m cells, a `HeightMapShape3D` per 128 m chunk for the whole zone | Collision chunks made on demand within 1 km of any player or live vehicle, freed past 1.3 km (about 250 live of 4,096) | `ZoneTerrain` |
| Scatter (trees, thickets, rocks) has absolute caps per zone (trees 9,000) | A density per km² over a streamed scatter grid (256 m cells within 1.2 km of a player) so 8 km isn't bare | `ZoneScatter` |
| Vehicles and soldiers drawn to view distance | Vehicles drawn to 3,000 m (proxy past 1,200 m), soldiers to 1,500 m | `VehicleHull`, `CharacterModel` visibility ranges |
| Navigation baked around soldiers (radius 48 / 20 m) | Unchanged for soldiers; vehicles off-road use a new `TerrainRoute`: A* on a 32 m grid costed by slope, ground (2.8.1) and water depth, cached per zone; roads by `RoadRoute` | new `scripts/vehicles/terrain_route.gd` |
| Every hostile group live or virtual | Allied groups virtual too (3.8) | `Virtualizer`, `AlliedTroops` |

#### 6.2.3 The performance budget

Target: the Captain's PC as host (RTX 4060 class) with up to 4 players.

| Budget | Value |
|---|---|
| Host frame time, average / 99th percentile | 14 ms / 33 ms |
| Client frame time, average | 12 ms |
| Live soldiers (both sides) | 80, beyond that the Virtualizer holds them |
| Live vehicles | 16 near players; columns far off are virtual rides |
| Virtual soldiers | up to 400 |
| Host memory | 6 GB |
| Network per client | 96 KB/s |
| Tasking, picture and front per side | 1 ms per cycle |

A new `perf_timing` case **invasion**: an 8 km zone, two armour columns moving, 60 live AI, 200
virtual, one player; it must hold the budget against today's hot-zone case.

### 6.3 Phases and a moving front

- **Phases.** An operation has 2-4 phases, each with **phase lines** (original names: PL COPPER,
  BRASS, IRON, STEEL), objectives (seize a site, clear a town, hold a line for a time, keep a
  bridge intact), the allied plan for it (the friendly `SideCommand`'s `OperationPlan`, 3), the
  **company's task** (the player's objectives, with the existing `Objectives` kinds plus
  `seize_site`, `hold_line`, `keep_intact`), a pay share and a time limit.
- **H-hour:** at dawn for a beach landing (the deployment starts 10 minutes before), **now** for most,
  or **player** (the operation waits until the company crosses the line of departure).
- **The front.** The zone is a 32 x 32 grid of 256 m cells. Each cell's owner comes from the
  presence of each side's groups (live and virtual, by CP, within the cell and its neighbours) and
  the sites held in it. A cell flips when the attacker's presence is twice the defender's for 60 s
  and no defending garrison is left in it. The **front line** is the boundary between the two
  sides' connected cells: drawn on the map and in the HC camera as a thick line with arrows of
  advance, recomputed every 10 s (1,024 cells: cheap). Phase lines are the plan; the front is what
  happened.
- **Spawning by the front.** Enemy reinforcements arrive only on the enemy's side of the front,
  at least 600 m from any player and out of sight (`EnemyResponse._unseen_gate`); friendly ones
  arrive at the start edge (the FOB, the beach) and move up. Behind the front is mostly safe,
  apart from bypassed pockets and the odd infiltrator team (one every 15 minutes at most).
- **On screen:** an operation strip at the top of the HUD (the phases, the current one, its clock)
  and the front on the map.

```
 OPERATION ASHEN TIDE   [ PH1 COPPER: done ][ PH2 BRASS  12:40 / 25:00 ][ PH3 IRON ][ PH4 STEEL ]
 Company task: seize the bridge at 052 047 intact          Allied: Anvil 1 overwatch, Saber 2 SBF
```

### 6.4 Mission types

Each is an `op_type` with its own generator rules, OOBs and phases. Numbers are Proposed.

#### 6.4.1 Phased invasion

- **Length:** 4 phases, 70-120 minutes.
- **Friendly OOB:** two allied rifle platoons (6 squads), a mechanised platoon (4 Bradleys with
  squads), an armour platoon (4 Abrams), a mortar section (2 tubes), an artillery battery off the
  map, fuel and ammo trucks, a medevac helicopter; attached to the company: an Abrams section (2).
- **Enemy OOB** (the target faction's; the Banner as the example): 6-8 site garrisons, 3-4
  roaming teams, 2 QRF groups on technicals, 2-3 AT teams with PG-7VL and PG-7VR, a mortar team,
  DShK gun teams, IEDs on the MSR, and a mobile reserve (technicals, a captured MaxxPro and 2 SPG-9
  technicals). Against the Concord: a mechanised company (BMP-2s), a T-72B3 platoon, Konkurs teams.
- **Phases:** 1, COPPER: seize the line of outposts (company task: the checkpoint on the MSR).
  2, BRASS: seize the crossing (company task: the bridge, intact). 3, IRON: clear the town
  (company task: the town's centre block, with allied infantry on the flanks and armour
  overwatching from outside). 4, STEEL: seize the HQ and the depth target (company task: the HQ
  compound and its commander, alive for a bonus).
- **Fail:** the operation stalls (6.3) or the company is wiped out.

#### 6.4.2 Beach landing with AAVs

- **Coast only.** The LHD stands off 2,500 m.
- **Flow:** the company starts **in AAVs in the LHD's well deck** (new: the deployment's spawn is
  inside the AAVs on the ship, using the existing `AavSupport` swim path). Waves: wave 1 is the
  company in 2 AAVs (its own crew or allied) with 4 allied AAVs; wave 2 (allied infantry and 2
  AAVs) follows 4 minutes later. The waves launch 1,200 m offshore (6 minutes' swim at 13 km/h;
  the host can speed time x4 while afloat and out of contact).
- **Before H-hour:** allied fires on the beach defences (2 minutes of artillery and naval gunfire,
  scripted to the known positions only), then smoke on the beach.
- **The run in:** troops can stand at the open cargo hatches to see and shoot (the AAV's FFV
  positions, as `FfvGunner` does for helicopters). MG fire from the beach rakes the water; RPG
  gunners on the dunes target the AAVs (whose fuel is under the troops, 2.2.3).
- **Phases:** 1, the beachhead: seize the beach exits (two) and clear the bunkers (company task:
  the left exit). 2, the harbour and the coastal village (company task: the harbour's quays and
  sheds). 3, hold the beachhead against the counterattack (3.7) for 15 minutes.
- **Fail:** wave 1 loses more than half its AAVs before the beach, or phase 3 is lost.

#### 6.4.3 Armoured thrust

- **Inland.** The company rides in (or crews) attached allied IFVs or its own motor-pool
  vehicles, inside an allied armoured column (an Abrams platoon, a mechanised platoon).
- **Objective:** drive down the axis through 2-3 blocking positions to seize the depth target in
  time (**limit 45 minutes** for the whole thrust: speed is the point).
- **Enemy:** ambushes on the MSR (`RoadAmbush`, coming in on claude/ai-followups), AT teams in the villages, IEDs,
  technicals; against the Concord, BMP-2s and T-72B3s in hull-down positions.
- **Company task:** the column's infantry screen: dismount at each blocking position, clear the AT
  threat around it, mount up and move on. The column won't move through a blocking position until
  it's clear (3.6).
- **Bypass:** a blocking position can be bypassed off-road (`TerrainRoute`) if the ground allows,
  at the cost of leaving an enemy behind the front.
- **Fail:** the time runs out with the depth target not taken, or the column loses more than half
  its vehicles.

#### 6.4.4 Seizing a crossing

- **Objective:** take the concrete bridge **intact** and hold both banks while the armour crosses.
- **The demolition:** the enemy has charges on the bridge (`Demolitions`, `ZoneBridges` take blast
  damage already), wired to a firing point on the far bank with a 2-man engineer team. The firing
  team blows the bridge 90 s after it sees a friendly force within 1 km of it, or at once if it sees
  vehicles on the span. The company stops it by killing the engineers, cutting the firing wire
  (an interaction at a marked point on the span or the bank) or seizing the firing point.
- **Phases:** 1, close on the bridge (quietly, if the player chooses: a night or dawn H-hour);
  2, seize it and both banks; 3, hold for 10 minutes while the allied armour crosses, against a
  counterattack.
- **If it blows:** the operation goes on with a ford (the armour crosses there, slower), and the
  "intact" pay share is lost (6.5).
- **Fail:** both banks lost, or the ford and the bridge both lost.

#### 6.4.5 Holding a captured town

- **Start:** the town has just been taken. The company is its garrison with an allied platoon, 2
  Bradleys and a mortar section.
- **Prepare** (10 minutes; the clock is shown): place static weapons with their cones (5.4), dig in
  (`Digging`, the e-tool berms and foxholes), and place defences from a budget (sandbags, HESCO and
  wire as `DefencePlacer` places them at the base, `budget` 6 pieces).
- **The counterattack:** 2-3 waves over 25-35 minutes from the enemy `SideCommand`'s choice of
  axes, made from **its picture**: what it has seen of the defence. Defences it hasn't seen it
  doesn't plan around, so a hidden gun pays off. Armour or technicals come with the second wave,
  preceded by mortars.
- **Win:** hold the town centre (a `hold_point` over the central square) to the end.
- **Fail:** the enemy holds the town centre for 60 s with none of ours in it (as `defend_hold`).

### 6.5 Pay by phase

- **Base:** `operation` types pay from data/contracts.json `mission_types`: phased invasion
  $320,000, beach landing $280,000, armoured thrust $220,000, seizing a crossing $180,000, holding
  a town $160,000; then the usual rating multiplier (`difficulty_pay`), the employer tier's
  `pay_mult` and Vessmark's x1.1.
- **Split by phase** (`pay_share`): each phase pays its share when it's done. For example, the
  phased invasion: 20 / 25 / 25 / 30%.
- **Advance:** 20% on signing (kept if the operation fails, as advances are now).
- **Bonuses** (each a share of the phase's pay): fast (done in under 60% of its limit) +10%;
  low allied losses +5%; **cooperation** +2% for each allied ask the company answered, up to +10%
  (4.3); clean (no civilian casualties) as now; the crossing's bridge intact +40% of that phase.
- **Penalties:** a phase done late (past its limit) -20%; each friendly-fire incident -5% and
  reputation; the bridge blown as above.
- **Expenses** as now (field costs, treatment, death benefits, supports), plus vehicle ammo and
  fuel. **Company vehicles lost** on an operation's task are 50% reimbursed by the employer (an
  "equipment indemnity" clause); attached vehicles are the employer's loss.
- **Partial success:** the phases done are paid; the rest aren't.

### 6.6 Feeding the living war

`WorldSites` learns about operations (`server_operation_ended(contract, phases_done)`):

- **Success** (every phase): each covered zone flips to the employer's side (`us_forces` as holder,
  grip 0.6), with a war news line and a flashpoint. The employer's strength +6; the target's -10.
- **Partial** (half the phases or more): the employer's front on those zones moves by
  `phases_done / phases` toward a flip, and the target loses grip 0.2.
- **Failure:** the employer loses 10 strength and the target's grip there +0.1.
- **Contract zones count now too.** Today `server_contract_won` only runs for hot-zone contracts
  (contracts.gd:947); operations always report.
- **Abstract resolution:** an operation offer that expires (4 days) unaccepted lets the front
  resolve by the normal daily tick: the US fights without the company.

## 7. Light armour across the factions, and US forces in the living war

### 7.1 Who fields what

A `vehicles` block per faction in data/factions.json (today the only faction vehicle data is the
quartermaster's list), read by everything that spawns enemy or allied vehicles:

```
"vehicles": {"patrol": ["technical_dshk"], "qrf": ["technical_dshk", "technical_zu23"],
             "convoy_cargo": "kestrel_rhino", "convoy_escort": ["technical_dshk"],
             "park": ["technical", "technical_spg9"], "armour": [], "by_tier": {"3": {"qrf": [...]}}}
```

| Faction | Patrol and convoy | QRF and parks | Armour (rare) | New models |
|---|---|---|---|---|
| Black Ridge | technicals (DShK) | DShK, ZU-23-2 (hilltops), SPG-9 | | |
| Ashen Banner | technicals (DShK) | DShK, SPG-9, Type 63 rockets; VBIEDs (built) | captured MaxxPro (DShK in the turret, slat kept, Banner paint) | captured MaxxPro (paint and gun variant) |
| Valley Shura | technicals, rarely | DShK | | |
| Saltline Syndicate | armoured SUVs | DShK, ZPU-2 technicals | | Saltline armoured SUV |
| Kestrel Cartel | technicals, armoured SUVs | the Kestrel rhino truck, DShK and ZPU technicals | | Kestrel rhino truck |
| Highland Free Front | technicals | DShK | captured MT-LB | |
| Eastern Concord | BTR-82A, MT-LB | BTR-82A, BMP-2, MT-LB with ZU-23 | T-72B3 (Kontakt-5) at Pressure tier 3 and in operations | T-72B3, BMP-2, BTR-82A, MT-LB |
| Vantage Group | armoured SUVs (black) | M-ATV (black) | | |
| US forces | M-ATV, MaxxPro | M-ATV, MaxxPro, Bradley | Abrams; AAVs on the coast | HEMTT cargo, tanker and ammo trucks |
| UK, Canada, Vessmark | the US models in their colours (their own vehicles later: Warrior, Foxhound, LAV 6.0) | | | |

**The two new original light vehicles:**

- **Kestrel rhino truck:** an improvised armoured truck in the narco style: a heavy truck chassis
  with welded steel plate, firing ports for 6 shooters and a plated turret with an M2 or DShK.
  KE 15 front, 10 sides (stops rifle rounds, not 12.7 mm), glass 12, soft roof; slow (80 km/h,
  heavy). The cartel's convoy cargo and its enforcers' ride.
- **Saltline armoured SUV:** a civilian armoured SUV (KE 8 all round: stops 7.62x39, not
  7.62x54R), an MG out of the sunroof, 4 crew. Fast. Smuggling escorts and the Syndicate's hit
  crews.

**Where light armour appears** (today no code spawns the "armor" threat, and the enemy's vehicles
are fixed lists in `VehicleQrf` and `MissionScenario`):

- **Mounted patrols** on roads: one per contract zone at alert Suspicious and up, two in hot zones,
  from the holder's `patrol` list.
- **QRFs** (`VehicleQrf.models` becomes the holder's `qrf` list, `by_tier` at higher Pressure).
- **Convoys** (`MissionScenario`'s `CARGO_MODEL` and `ESCORT_MODEL` read the target faction's).
- **Vehicle parks** at sites (sabotage targets) from `park`.
- **Checkpoints** with a parked armed vehicle, crewed when alerted.
- **The "armor" threat** on a contract (weight 1.5 in `ContractGen.rating`) now spawns 1-2 vehicles
  from the holder's `qrf` or `armour` list.
- **Faction skirmish teams** ride in at Pressure tier 2 and up.

**Players buying light armour:** the US quartermaster sells the M-ATV (trusted) and MaxxPro
(allied) as now; the **Bradley** is added at US allied ($1,200,000); the AAV stays a support
(coast). The **Abrams is never sold** to a private company; players crew Abrams only as attached
armour in operations (6.1). The **Salvage Union** sells used technicals ($25,000) at neutral.

### 7.2 New vehicle art

`VehicleArt` builds each as voxels like the existing ones (and tags turret and gun voxel groups for
`VehicleTurret.split()` and the thrown-turret effect): T-72B3 (with Kontakt-5 bricks as separate
tile groups), BMP-2, BTR-82A, MT-LB, the HEMTT in three bodies (cargo, M978 tanker, ammo), the
Kestrel rhino truck, the Saltline armoured SUV, and the captured MaxxPro as a scheme. Interiors
only where crews sit visibly (`VehicleInteriors`).

### 7.3 US forces in the living war

Today `WorldSites.warring()` is the hostile factions only, so the US never holds ground or opens a
front. The Captain's call: the US fights **the Ashen Banner first, then the Kestrel Cartel if it
wins**.

- **A belligerent employer.** `us_forces` keeps `role: employer` and gains `belligerent: true` and
  `war_target: "ashen_banner"`; `warring()` includes belligerent employers. UK, Canada and Vessmark
  stay non-belligerent (they fight inside US operations, not as holders).
- **FOB Halberd.** A new zone in data/contracts.json (coast region, 1,920 m, `kind: allied_fob`),
  next to the Banner's coast zones on the region layout (Landing beach and Cove outpost). The US
  holds it from day 1, and it **can't fall** (like a faction's last zone and the company's FOB:
  `cant_fall`). It is where the company can stage (8).
- **Strength.** The US starts at 70 and earns a flat +3 a day (a deployment budget, not land);
  losses and wins move it like anyone's.
- **Fronts.** From day 3 the US opens fronts only on its `war_target`'s zones that border its own,
  by the same tick (`_open_front`); the Banner can open fronts on US zones like on anyone's.
- **Operations decide US fronts.** While a US operation on a front is on the board or under way,
  that front's daily progress pauses; the operation's result moves it (6.6). Unaccepted, the
  front resolves by the tick.
- **US in the field.** In US-held zones and zones bordering them: US patrols (an M-ATV and a
  MaxxPro with a rifle squad, green IFF) on the roads; a US garrison at each held zone's HQ site,
  which becomes a US outpost (the `fob` module's pieces with US dressing); US convoys on the MSR
  between its zones; US armour (a Bradley or Abrams section) on fronts. These are friendly groups
  under the friendly `SideCommand`, so players can make requests of them (4.2) and they ask players
  for help (4.3).
- **The switch to Kestrel.** The Banner's last zone falls only when the company takes its HQ and
  QRF bases there and kills or captures its leaders (the Captain's rule). When that wipe happens
  (`WorldSites._wipe`), the US `war_target` becomes `kestrel`, with a news line ("With the Banner
  broken, US forces turn on the Kestrel Cartel's routes") and fronts on Kestrel zones bordering
  US ground. If Kestrel is wiped too, the US war ends and it holds what it has.
- **News and radio:** US advances, losses and operations in the morning news and `RadioChatter`'s
  lines; the theatre map shows US zones in the allied green with the US flag.
- **The story:** the liaison arc (`arc_liaison`, "joint operations", not yet built) hangs on
  this: its first contract is the company's first US operation.

## 8. Staging from a friendly FOB

The Captain: "make it possible to purchase operations out of a fob that friendlies control. like
we operate out of their fob in an improvised way as a way to cut ops costs when working inland or
trying to avoid excessive flight cost".

### 8.1 What it is

- **Hosts:** FOB Halberd (7.3) and every US outpost in a US-held zone with an HQ site. UK, Canada
  and Vessmark host only inside US operations (at the operation's start-edge FOB).
- **The company's corner:** a 30 x 30 m area inside the host's wire: a tent with cots (basic
  medical), a crate stack with a resupply terminal at the host's prices, two parking spots, a radio
  desk with the board (contracts within 2 region links only). Built as a `staging` corner in the
  host's FOB module from `BaseFob`'s pieces. No armory, no stash, no hiring, no workshop.
- **The flow:**
  1. At the ops desk or the board, a contract's insertion options show **"Stage from FOB Halberd"**
     beside the LHD and the company FOB, with each option's cost and travel days.
  2. Choosing it rents the corner for the deployment. The squad (and its hero squads) go to the
     staging FOB; their motor-pool vehicles come along (two at most).
  3. From there the squad drives or walks over the zone crossing into the target zone (the linked
     zones' crossings, `RegionMap.crossings`), or takes a one-link helicopter hop.
  4. Extraction can bring them back to the staging FOB; the debrief happens there, and they can
     take the next contract from its board without going home. Each day staged is rented.
  5. Going home costs the usual travel.

### 8.2 Services

| Service | At the staging FOB | At the company FOB, for comparison |
|---|---|---|
| Resupply | Ammo, medical, batteries, fuel, repair kits, track links, ERA tiles: the shop price +25%. No weapons, armour or gear | Everything, shop prices |
| Medical | Stabilise and rest: wounds treated to stable, at most 2 units of blood a man; no surgery and no recovery days | Medbay |
| Fuel | $3 a litre | $2 |
| Vehicles | Parking for 2; their mechanics fix **damaged** modules for a fee (the motor pool's price +50%), nothing destroyed | Full workshop |
| Helicopters | The company's helicopter supports may refuel there: inland calls cost 40% less | |
| Respawns | Bought respawns arrive at the staging FOB, not the home base | |
| Loadouts | Only what the squad brought | Armory and stash |

### 8.3 What it costs, and what it saves

**Rent** (data/prices.json `staging`): $6,000 a deployment plus $1,500 a day staged, x 1.0 at
trusted and x 0.7 at allied with the host, x 0.5 when the contract's employer is the host.

**Insertion costs become real.** Today a contract's helicopter insertion charges nothing
(`HeliSupports.server_insert` has no payment call); only an ops-desk raid charges `transport`. So
"excessive flight cost" has nothing to cut. This doc makes insertion and extraction flights cost
**$3,000 + $1,200 per region link** from the home base each way, paid like a support
(`Economy.server_pay_support`). A ground insertion from a FOB costs fuel only. (The economy was
judged "too easy overall"; this is one of the levers, and the staging FOB and the company's own FOB
on the ground are the ways round it.)

| Inland contract 3 links from the LHD | Fly from the LHD | Stage from a US FOB next door |
|---|---|---|
| Flights in and out | 2 x $6,600 = $13,200 | none (drive over the crossing) |
| Rent (2 days, trusted) | | $9,000 |
| Travel days | 2 (inland) | 1 |
| A day of wages and upkeep saved | | about $6,000 |
| **Net** | $13,200 + 2 days | $9,000 + 1 day: **about $10,000 cheaper** |

A coast contract 1 link from the LHD is cheaper flown, so staging is an inland tool, as the
Captain described.

### 8.4 Standing and losing access

- **Needs trusted** (rep 30) with the host's faction. Below it, no rent.
- **Misconduct:** a friendly-fire incident on the host's troops: -10 rep (and eviction if one is
  killed); looting the host's dead or vehicles: -15; civilian casualties in the host's zone: the
  usual rep loss; failing the host's operation: the usual `rep_fail`.
- **Eviction:** when the rep falls below trusted, the company must leave at the end of the current
  deployment; vehicles parked there are moved back to the company's FOB for $5,000.
- **The war takes it away:** if the zone flips (a US outpost zone lost to the Banner), the staging
  FOB is lost with it; anything parked there is lost unless the squad drives it out. FOB Halberd
  can't fall, but it can be **attacked**: while the company is staged there, a Banner assault on
  Halberd is a live defend event the company can join (rep +3 with the US for each one held).

### 8.5 In the code

- New `scripts/campaign/staging.gd` (`Staging`, statics plus host requests): quotes, access checks,
  the campaign section `staging` (`{host, zone, since_day, vehicles}`), the daily rent through
  `Economy.advance_days`, eviction.
- `Briefing` insertion options gain "from the staging FOB"; `BaseHub`'s deployment origin can be the
  staging zone; `HeliSupports.server_insert` charges the flight; `MotorPool.server_bring` brings
  vehicles to the staging FOB.
- The staging zone is a `ZoneLevel` with the host's FOB module and the company's corner, loaded
  like the base zone (`BaseZoneLevel` is the template).

## 9. Build plan

### 9.1 Rules for every phase

- **One session, one phase, one branch** (`claude/ca-<phase id>-<name>`, e.g.
  `claude/ca-a1-armour-model`), off `origin/claude/ai-driving`, in its own worktree and port
  (`CONTRACTOR_PORT`, `CONTRACTOR_TEST_TAG`). Headless Godot only.
- **Affected suites plus smoke locally**, the full set on CI; a branch reaches `dev` only when its CI
  is green. Test logs are kept (R#### in B:\Contractor-test-logs).
- **Every number in data and marked Proposed.** CHANGELOG entry and a Discord note when a phase lands.
- **Data split to keep parallel phases apart.** The new per-model blocks don't go into
  data/vehicles.json (every armour phase would collide in one JSON file). They go in per-topic
  files keyed by model id: `data/vehicle_armour.json` (plates, tiles, belly, spall liner,
  packages), `data/vehicle_modules.json`, `data/vehicle_weapons.json` (weapons, optics, crew,
  vision), `data/shells.json`. `VehicleSpecs.spec(model)` merges them into the one spec the code
  reads, so the rest of this doc's "data/vehicles.json `plates`" means that merged spec.
- **New logic in new files, one-line hooks in shared ones.** `vehicle.gd`, `squad_ai.gd`,
  `squad.gd`, `zone_level.gd` and `world_sites.gd` get hooks, not bodies. When two phases running
  at once must touch the same shared file, they touch different functions, and the second to land
  rebases.
- **Wait for the sessions running now:** `claude/ai-followups` edits `squad_ai.gd`, `tactics.gd`,
  `squad_drivers.gd`, `aav_gunner.gd`; `claude/ci-cleanup` the CI and dev catch-up. Phases that
  touch those files (C1, A9, B2) start after those branches land.
- **cghath's files:** `ZoneWater` and `ZoneBridges` get two small additive changes (`flow_at`,
  `mlc`) in phase A6 and one hint each in D1; they're noted for cghath in docs/audits/followups.md as
  F-items when made, so the world work rebases cleanly.

### 9.2 The phases

Four lanes: **A** armour, **B** the AI commander and cooperation, **C** high command and the UI,
**D** operations and the world.

| Phase | What | Depends on | Main files (new in bold) |
|---|---|---|---|
| **A1** | The armour model: `ArmourModel.resolve`, shells data, plates and tiles for the Abrams, Bradley, AAV, M-ATV and MaxxPro, hit routing by `plates` | none | **armour_model.gd**, **shells.json**, **vehicle_armour.json**, warheads.json, vehicle.gd (`server_take_hit` hook), vehicle_specs.gd |
| **A2** | Modules: module data and migration from zones, the module path, spall cone, crew hits through `Vitals`, damage states and kill states, `HitEvent` | A1 | **vehicle_modules.gd**, **vehicle_modules.json**, vehicle.gd (`_apply_damage` hook), drive_contact.gd, vehicle_service.gd |
| **A3** | Weapons: `VehicleWeapons`, `ShellFlight`, Bradley and Abrams turret specs, the M256 and loader, the M242 dual feed, TOW (`saclos`), the UGWS, the five technical guns, commander and loader seats, timed seat switching, the crew wheel's basic orders | A2 | **vehicle_weapons.gd**, **shell_flight.gd**, **vehicle_weapons.json**, launcher_projectile.gd (guidance), vehicle_turret.gd, vehicle.gd (`server_switch`, gun hooks) |
| **A4** | Gunnery: sights and `VehicleSightOverlay`, `ThermalView`, LRF and fire control, lead, the stabiliser, the commander's view and designate, hatches and spotting, `CrewGunner` | A3 | **vehicle_sight_overlay.gd**, **thermal_view.gd**, **crew_gunner.gd**, vehicle_turret.gd, vehicle_camera.gd, spotting.gd, the shared material shaders |
| **A5** | HUDs and the x-ray: `VehicleHud` (1P and 3P), the doll, alerts, `VehicleXray`, `HitReport`, the setting, protection analysis at the ranges | A2, A4 | **vehicle_hud.gd**, **vehicle_xray.gd**, hud.gd, game_settings.gd, vehicle_range.gd |
| **A6** | Driving: `ground_at`, power and traction, slopes, rollovers and the tow, `ford_m` and flooding, river current, bridge `mlc` and overload, `TerrainRoute` | A1 (for data loading only) | vehicle.gd (`_wheel_forces`, `_drive_step`), aav_water.gd, zone_terrain.gd, zone_water.gd (`flow_at`), zone_bridges.gd (`mlc`), road_route.gd, **terrain_route.gd** |
| **A7** | Fire and destruction: `VehicleFire`, `VehicleFx`, ammo detonation, cook-off, blow-out, turret toss, debris, hulks, bail-out, the sounds | A2 | **vehicle_fire.gd**, **vehicle_fx.gd**, vehicle_hull.gd (`REMOVE` edit), sounds.json, vehicle.gd (fire hooks) |
| **A8** | Logistics and packages: round items, rearm from the FOB, trucks, pallets and helicopters, the fuel truck, the repair table, packages bought and fitted at the motor pool with their weight costs, prices | A2, A3 | items.json, pallets.json, prices.json, motor_pool.gd, vehicle_service.gd, vehicle_action_point.gd, heli_supports.gd (load) |
| **A9** | AI crews and armour tactics: `ArmourTactics` (hull-down, dismount spots, front to the threat, shoot and scoot, smoke on a launch), ground sense, spacing, bail-out; AT gunners aim at weak faces | A3, A4, A6; after ai-followups lands | **armour_tactics.gd**, vehicle_ai.gd, squad_drivers.gd, launcher_ai.gd |
| **B1** | The picture: `SidePicture`, `GroupBoard`, reports with latency, BFT, the hostile picture moved under `EnemyCommand`, shared spot reports on the map and HUD | none | **side_picture.gd**, **group_board.gd**, enemy_command.gd, map_markers.gd, enemy_tags.gd, hud.gd |
| **B2** | The commander: `SideCommand`, roles and suitability, the tasking cycle, `HotZonePolicy` (moved from `EnemyCommand`), phases, reserves, fallback, counterattacks, allied groups virtualised | B1, C2 (`SquadOrders`) | **side_command.gd**, **hot_zone_policy.gd**, **operation_plan.gd**, **defence_plan.gd**, enemy_command.gd (shim), virtualizer.gd, allied_troops.gd |
| **B3** | Armour with infantry: pairing, dismount points, the town rule, target hand-off, armour asking for infantry | B2, A9 | operation_plan.gd, armour_tactics.gd |
| **B4** | Requests: `RequestBroker`, the catalogue, the lifecycle, request cards, allies' asks, cooperation counts, `RadioVoice` | B2 | **request_broker.gd**, **request_cards.gd**, **radio_voice.gd**, callouts.gd |
| **B5** | Deconfliction: sectors from the commander, `safe_to_fire` in `CrewGunner` and every group, player bubbles, allied fires warnings, check fire, BFT chevrons in sights, route reservations | B2, A4 | side_command.gd, squad_orders.gd, crew_gunner.gd, fire_support.gd, road_route.gd |
| **C1** | High command Phase 0 (G1-G12) and the section 9 lifts of docs/high_command.md | after ai-followups lands | squad.gd, squad_ai.gd, tactics.gd, callouts.gd, extraction.gd, compound_level.gd, zone_level.gd, **follow_brain.gd**, **progress_watch.gd** |
| **C2** | High command Phase 1, plus the two standing squads from the start, and `AlliedTroops` onto `HcOrder` | C1 | **high_command.gd**, **squad_orders.gd**, **heroes.gd**, roster.gd, contracts_gen.gd, base_hub.gd, allied_troops.gd, map_view.gd hooks, **map_hc_panel.gd** |
| **C3** | High command Phase 2: Attack, SBF, Bound, Fall back, Defend frontage, queues, go codes, requests to the commander, CE, the company net | C2 | squad_orders.gd, high_command.gd |
| **C4** | The map-order HUD (select, order, place, face, confirm, undo) and gun placement with the cone of fire (`Viewshed`, `GunTeam.sector`) | C2 | **map_command.gd**, **viewshed.gd**, gun_team.gd, mortar_team.gd, static_weapons.gd |
| **C5** | The 3D high command camera with known-only markers, and its map mode for the 3D mission map | C4, B1 | **hc_camera.gd**, briefing_screen.gd, map_screen.gd |
| **C6** | Contextual menus everywhere: `ContextResolver`, the one key, recent first, the interaction menu's squadmate orders, the crew wheel, request options | C4, B4, A3 | **context_resolver.gd**, interaction_menu.gd, command_menu.gd, voice_order.gd |
| **D1** | Operation zones: `ZoneDef.generate_operation`, the bands, sites from covered zones, river and bridge hints, the MSR | none | zone_def.gd, **operation_gen.gd**, zone_modules.gd (band hints) |
| **D2** | 8 km performance: collision on demand, the scatter density grid, far proxies, live caps, the `invasion` perf case | D1 | zone_terrain.gd, zone_scatter.gd, perf_timing.gd |
| **D3** | Operation contracts: the `operation` kind, phases and company tasks, OOB spawning, the front grid, the operation strip, pay by phase, the debrief, feeding the war | D1, B2 | **operations.gd**, **front_grid.gd**, contracts.gd, contracts_gen.gd, contracts_debrief.gd, objectives.gd, world_sites.gd hook, hud.gd |
| **D4** | Mission types 1: the phased invasion and the armoured thrust; attached armour | D3, A3 (A9 for quality) | operation_plan.gd, operations.gd, contracts.json |
| **D5** | Mission types 2: the beach landing (AAV waves from the well deck), seizing a crossing (the demolition and its firing point), holding a town (the prep phase and its budget) | D3, A6 | operations.gd, aav_support.gd, lhd_level.gd, demolitions.gd, defence_placer.gd |
| **D6a** | New vehicle art: T-72B3, BMP-2, BTR-82A, MT-LB, the three HEMTTs, the rhino truck, the armoured SUV, the captured MaxxPro scheme | none | vehicle_art.gd, vehicle_interiors.gd |
| **D6b** | Light armour in the world: their data (plates, modules, weapons), faction `vehicles` tables, mounted patrols, QRFs, convoys, parks, the "armor" threat, the Bradley and technicals for sale | D6a, A2, A3 | factions.json, vehicle_*.json, vehicle_qrf.gd, mission_scenario.gd, enemy_response.gd, quartermaster.gd |
| **D7** | US forces in the living war: belligerent employers, FOB Halberd, US fronts, Banner then Kestrel, US patrols, garrisons and convoys, news, Vessmark | none | world_sites.gd, factions.json, contracts.json, region_map.gd, radio_chatter.gd, zone_level.gd hook |
| **D8** | Staging from a friendly FOB and the insertion cost | D7 | **staging.gd**, briefing.gd, base_hub.gd, heli_supports.gd, motor_pool.gd, prices.json |

### 9.3 Tests and budgets per phase

| Phase | Tests (new suites in bold) | Budget |
|---|---|---|
| A1 | **armour_test** (pure): effective thickness by angle, normalisation, overmatch, ricochet bands, HEAT graze, each tile kind against single and tandem, slat odds over 1,000 seeds, HE punch-through, fuzes and arming; the 2.4.6 table asserted cell by cell from data; antiarmor_test and vehicles_test unchanged for soft vehicles | `resolve` under 0.05 ms |
| A2 | armour_test (module paths, spall counts, liners), vehicles_test (kill states; `zone_health` from modules; soft vehicles exactly as before), net_test (a `HitEvent` reaches a client and a late joiner sees the states) | A hit with spall under 0.5 ms on the host |
| A3 | **vehicle_guns_test**: the 2.7.5 ballistics within 10%, the loader cycle and its window, short-crewed loading, the dual feed switch, the TOW wire break on fast traverse and smoke, rack counts, seat switch times | 50 shells in flight under 0.5 ms |
| A4 | vehicle_guns_test: the fire control hits a crossing target at 1,500 m on 90% of seeded runs; no lead hits under 40%; the stabiliser's drift above its limit; spotting factors for hatches; ui_test for the sight overlay at 10 resolutions | Thermal costs under 1 ms a frame |
| A5 | ui_test (both HUDs and the x-ray at 10 resolutions), a `HitReport` JSON round trip, the protection analysis matches `resolve` | HUD under 0.3 ms |
| A6 | **driving_test**: dry against muddy climbs, a rollover within 10% of the predicted angle, flooding times, current drift, routing round a light bridge, a span dropping under overload; water_test, vehicles_test | Physics step unchanged on the vehicle range |
| A7 | vehicles_test: the fire stages and their times, blow-out against catastrophic, bail-out; net_test: two peers make the same debris from one seed | 6 fires and 64 debris within the effects budget |
| A8 | logistics_test (rearm sources and times, fuel truck), base_test (packages bought, fitted, refunded; weight changes speed and fuel), pallets_test | |
| A9 | **armour_ai_test**: a tank finds a hull-down spot against a staged threat, turns its front to it, reverses after a launch and smokes; an AT gunner chooses a side shot | |
| B1 | **side_command_test**: merging, ageing, latency by side, comms down x3, BFT, fairness (every marker traces to a report); missions_test's hot-zone checks unchanged | Picture under 0.3 ms per side |
| B2 | side_command_test: allocation on staged boards, the assault waits for its SBF, the reserve commits on a stall, RED falls back and reconstitutes, counterattack ratios, virtual groups tasked; a hot-zone run whose `[tactics]` and operation lines match today's | Tasking under 1 ms for 40 groups |
| B3 | side_command_test: a paired tank stays with its screen; armour stops at a town's edge; a hand-off makes the tank fire HE at the building | |
| B4 | **requests_test**: each request type accepted, declined and countered with its reasons; the lifecycle states; allies' asks raised and completed; limits and merges | |
| B5 | requests_test and a scripted combined fight (2 allied groups, the player squad, a tank, mortars) with **zero blue-on-blue damage**; check fire stops fire within 1 s | |
| C1-C3 | As docs/high_command.md section 12 (**high_command_test**, **heroes_test**, base_test, contracts_test, map_test, net_test, loop_test); base_test: two standing squads on a new campaign | `perf_timing` 8 + 8 + 8 friendly AI |
| C4 | map_test (the order flow, undo, queue), a pure **viewshed** test against a staged ridge, ui_test | Viewshed under 2 ms |
| C5 | map_test; a headless check that the camera culls actors and shows only picture markers; ui_test | Camera mode costs no more than the normal view |
| C6 | **context_test** (pure: the table in 5.5), interaction_test, ui_test | |
| D1 | world_test: deterministic generation, the bands, a concrete bridge on the MSR, crossings in band 2, landmarks from the covered zones | Generation under 8 s |
| D2 | perf_timing **invasion** case against 6.2.3; virtualization_test with allied groups | 6.2.3 |
| D3 | contracts_test (offers from fronts, pay split, the advance), missions_test (phases advance, front cells flip, stall, fail), world_sites (results feed the war) | Front grid under 0.2 ms a cycle |
| D4, D5 | missions_test: each type played through by test hooks to success and failure | |
| D6a | vehicle_shots (headless screenshots on the RTX 4060 when the Captain isn't gaming) | |
| D6b | vehicles_test (the new models' data loads and resolves hits), missions_test (patrols and QRFs by faction) | |
| D7 | world_sites: a deterministic war with the US; the switch to Kestrel after a Banner wipe; Halberd never falls; contracts_test: US operation offers | |
| D8 | contracts_test and base_test: quotes, rent by the day, access by rep, eviction, the insertion charge | |

### 9.4 Order and parallel waves

```
Wave 1 (now)          A1      B1      D1      D6a     D7      (+ C1 once ai-followups lands)
Wave 2                A2      A6      C2      D2      D8
Wave 3                A3      A7      C3      C4      B2 (needs C2)
Wave 4                A4      A8      D3      C5
Wave 5                A5      A9      B4      D4      D6b
Wave 6                B3      B5      D5      C6
Then                  the armour balance pass after the Captain's first playtest (2.14)
```

- **No two phases in a wave touch the same file body.** In wave 1: A1 is the combat files and the
  `server_take_hit` hook, B1 the campaign picture and map markers, D1 the zone generator, D6a the
  vehicle art, D7 the war and factions data. A2 and A6 both hook `vehicle.gd` but in different
  functions (damage against drive). C2 and D8 both touch `base_hub.gd`: the ready-up page against
  the deployment origin. A3 and A7 both hook `vehicle.gd`: seats and guns against fire. A8 owns
  data/prices.json in its wave, so D6b (which adds the Bradley's sale price) waits a wave.
- **The critical path** to the first combined-arms operation the Captain can play: A1 > A2 > A3 >
  C1 > C2 > B2 > D3 > D4, with D1/D2 alongside: about 8 sessions in sequence, 5-6 waves with the
  parallel work.
- **The first armour the Captain can try** comes earlier: after A3 a Bradley and an Abrams fire
  their main guns at the vehicle range with the new armour; after A4 with sights and thermal; after
  A5 with the HUDs.
- **No new build** until a major feature lands (the Captain's rule): the natural cut points are
  after A5 (armoured gameplay), after C3 (high command), and after D4 (the first operations).

## 10. Calls made

Every call below was made in this doc so the build sessions don't stop to ask. Each is Proposed and
can be changed; the alternative is what was weighed against it.

### Armour

| # | Call | Why | The alternative |
|---|---|---|---|
| 1 | Pitch between Reforger/Squad and Steel Beasts: real crew jobs, LRF gunnery, modules; no start-up drills, gear ratios, wind in the solution | The Captain's "semi realistic" and "comparable to WT" | Full sim procedures (slows co-op play); arcade armour (the Captain asked for depth) |
| 2 | One pure `ArmourModel.resolve` for every armour hit; `VehicleDamage` kept for soft vehicles and aircraft until they get plates | One place to test and tune; soft vehicles keep working unchanged | Rewriting every vehicle at once |
| 3 | Plates carry their own normal; voxels decide only where a round lands | Voxel faces are axis-aligned steps and can't give a slope | Slopes from voxel normals (wrong on every glacis) |
| 4 | Penetration by range tables in data, not a formula | One tuner edit per number | De Marre-style formulas (harder to tune) |
| 5 | Normalisation, ricochet bands and a 3x overmatch rule, learned from WT | The detail bar the Captain named | Pure 1/cos (no bounces) |
| 6 | Small arms stay immune (tier 0) and skip the model | The Captain's earlier call; cheap | Every bullet through the model |
| 7 | Composite arrays given as line-of-sight RHAe from public estimates, with a 2x obliquity cap | Matches the published kind of figure | Layer-by-layer composition (no public data to tune it) |
| 8 | Base protection and shell figures as in 2.4.2-2.4.3, rounded from public estimates | Fair balance against real reputations | Invented numbers |
| 9 | Three reactive kinds (light, heavy, tandem-capable) plus slat and spacing, tiles used up and shown missing | The Captain named Kontakt-1/5, BRAT, ARAT, slat | One generic ERA bonus (today's `ERA_MM` 300) |
| 10 | Modules with working / damaged / destroyed states and the effects in 2.2.2 | WT-level detail the Captain asked for | Zone health bars as today |
| 11 | Crew are the real soldiers in their seats, hit through `Vitals` | The medical model works inside vehicles for free | A crew hp pool |
| 12 | Kill states: mobility, firepower, crew, knocked out, catastrophic; objectives read "knocked out or mobility" | Keeps `destroy_vehicles` meaning the same | Only "destroyed" |
| 13 | Spall as a cone of ray fragments, cut 60% by spall liners | Spall is what kills crews in WT and life | Today's "everyone within 2.5 m" |
| 14 | Packages bought at the company motor pool, weight costing speed and fuel, gated by the employer's tier, 50% refund on removal | The Captain's "upgrade packages" | Free fit-outs; packages as loot |
| 15 | The company never buys an Abrams; it buys up to a Bradley; players crew Abrams as attached armour in operations | A PMC fielding MBTs strains belief and the economy; players still get tank gameplay | Abrams in the shop |
| 16 | Trophy APS included as a late Abrams package that can hurt friendly infantry | Real, and it creates the infantry-armour tension | Leaving APS out |
| 17 | Commander and loader seat kinds; one seat one job; short-crewed penalties | The Captain: "one man can't drive and gun at full effect" | A player driving and gunning |
| 18 | Timed seat switching (3-10 s) | Same | Instant switching (today) |
| 19 | Full-screen sights with magnification relative to the base FOV | The Captain's optics call; a gunner looks into his sight | Picture-in-picture sights |
| 20 | One `ThermalView` (a global shader uniform plus per-instance heat) shared with cghath's thermal scope | One system, cheap, walls block it naturally | A second render pass per sight |
| 21 | Normal smoke transparent to thermal; vehicle dischargers fire multispectral smoke | Real, and it gives thermal a counter | All smoke blocking thermal |
| 22 | The FCS lays the gun with lead from 1 s of tracking; no wind or temperature | Semi-real; the skill is lasing and tracking | Manual superelevation always |
| 23 | Stabiliser holds a world aim, degrading with speed and roughness, off past `stab_max_kmh` | The Captain: "the stabiliser off while moving fast" | A perfect stabiliser |
| 24 | A loader timing window for players (4.5 s or 6.5 s) | The Captain's "loader timing" as play, not a wait | A plain progress bar |
| 25 | Traction by ground, power-limited drive, fording depths per model with flooding, river current, bridge load classes | The Captain's driving list and the new rivers | Today's grade hold and one ford depth |
| 26 | Rollovers from real centres of mass; righting by a tow or abandoning | MRAP rollovers are real and dangerous | No rollovers |
| 27 | Field repair of damaged modules, tracks and wheels; destroyed modules only at the FOB | The Captain: "heavy damage only fixed at the FOB" | Everything field-repairable |
| 28 | Main-gun rounds are items and racks are modules | Logistics and damage share one model | Abstract ammo counts |
| 29 | Fires grow smoke > fire > cook-off > burn-out with extinguishers; the Abrams bustle vents | The Captain's effects list; the blow-out panel is real | Instant explosions |
| 30 | Seed-synced debris and turret toss, as gore pieces are | Same pieces on every peer without streaming | Replicated physics bodies |
| 31 | The x-ray shown after hits by default ("my shots and hits on me"), full view on a key, protection analysis at the ranges | The Captain asked for it as a dev, training and player setting | Dev-only |
| 32 | Vehicles drawn to 3 km, soldiers to 1.5 km in operation zones | Tank gunnery happens at 0.5-2.5 km; budget | Infinite draw |

### Armour, phase A1 build (2026-10-22, Proposed)

Made while building A1; each is Proposed and can be changed.

| # | Call | Why | The alternative |
|---|---|---|---|
| 74 | `ArmourModel.plate_at`: the first plate in the list whose box holds the hit, whose normal faces the round and agrees (cos 0.3 or more) with the voxel face it crossed (`face_of`: the axis it stepped into the voxel on); else the first that faces it; else the first that holds it; none: the zone's old armour class | Boxes overlap at every corner and edge; the voxel face says which side was really hit, and the list order breaks the rest (the glacis before the deck) | The nearest box face (wrong on sloped plates); the first box only (a side shot at a turret corner read the cheek) |
| 75 | A plate's `normal` is the facing its figure applies along (the published composite figures are line-of-sight values at that facing), not the staircase's slope; `"normal": "any"` is head-on from every side, used for tyres, engine bays and small turrets (the O-GPK, the UGWS) | Keeps 2.4.2's numbers meaning what they say; voxel art can't give a slope | Real slopes with physical thicknesses (no public data to tune, and the 2.4.6 table would no longer hold) |
| 76 | Abrams hull side behind the light skirts: KE 85 (doc had 70) | M791 at 100 m (80 mm) went through it, against the table's "no"; M919 then reads "~" and 3UBR8 "no" as the table says | Changing the table (a 25 mm APDS through an Abrams side is wrong) |
| 77 | The Bradley's BRAT I (and BUSK III's BRAT II) also covers the hull and turret front; PG-7V and AT4 against the Bradley front read "tile", PG-7VR "pen" | The table had "no" for all three, which the front's 110 CE can't give; real M2A3 BRAT kits cover the front, and a tandem RPG must beat an IFV's front | A thicker front (an IFV that shrugs off RPGs) |
| 78 | Table cells corrected to the 2.4.2-2.4.4 numbers: M830A1 against the Bradley side and the T-72B3 side "pen" (600 against 70 + 400 and 120 + 400), M791 against the Abrams roof "~" (through head-on, not at 60 degrees from 2 km) | Light ERA's +400 can't stop a 600 mm jet; a roof head-on is 40 mm | Raising light ERA (it would stop PG-7VL and AT4s everywhere) |
| 79 | Rounds with no shells.json row (pistol, 5.56, 7.62x39, 7.62x51, 7.62x54R, .30-06 AP) keep `VehicleDamage`'s tiers even on plated models; the .50 M33 (`round_id` 50bmg_m33) is the first bullet with a row | The Captain's small-calibre immunity costs nothing new, and the vehicles suite's 7.62x54R-through-an-engine-bay checks keep their meaning | Every bullet through the model |
| 80 | HE with no warhead id (charges, mines, fire support, `server_explosion`) keeps `VehicleDamage` in A1 | Charges and fire support are tuned against zones (demolitions and fire support suites); they move with A2's overpressure and belly blast | Routing them now and retuning every charge |
| 81 | A1's bridge to the zones (`ArmourModel.damage`): a penetration does the shell's `module_dmg` to the zone at the hit; KE flies on with `energy x residual / pen`; a partial does 15%; a stopped shaped charge or HE does the old blast-on-the-hull share; spall (today's 2.5 m) on CE and on KE of 20 mm and up; API doubles the fire chance | Keeps zones, fire, wrecks and every caller working until A2's modules | Building modules in A1 |
| 82 | `range_m` for the pen tables: the hit's `range_m`, else the shooter's distance; arming is checked only when a hit gives `range_m` (A3's `ShellFlight` will); launcher rounds are already duds before arming in `LauncherProjectile` | No double arming check from a distance that isn't the flight | Passing flight distance through Ballistics now (outside A1's files) |
| 83 | A proximity fuze against a vehicle bursts short: blast only (`fuzed_outside`); an airburst round that meets a hull before its set range acts point-detonating | 2.3.7 leaves the jet's fate open; a HEAT burst metres off a hull is spent | Half penetration at standoff |
| 84 | Shatter: a KE round stopped below half the plate's `t_eff` on composite or high-hardness steel | 2.3.3 names the outcome but not when | No shatter outcome |
| 85 | Rolls are `hash(seed x 1000003 + salt)`, one salt per roll kind and tile; the seed is `hash(shot_id, vehicle name, plate id)`, `shot_id` falling back to the hit point and physics frame until A3 numbers shots | Deterministic, independent rolls, no RandomNumberGenerator per hit | One RNG stream (one roll shifts the next) |
| 86 | Tiles counted along their box's longest side; fired tiles and fitted packages kept as vehicle metadata (`armour_tiles`, `armour_packages`) until A2/A7 move them into `net_state` (A7 removes the voxels) | A1 touches only `server_take_hit` in vehicle.gd | New vehicle fields now |
| 87 | The M33 penetrates 24 mm at the muzzle (20 at 100 m as 2.4.3) | The "M-ATV side: no (100 m: ~)" cell and the vehicles suite's close .50 through a MaxxPro side | 20 flat to the muzzle (a .50 never through an MRAP) |
| 88 | Wheels are plates of 6/6 (`tyre`) and engine bays 18/18 from every side (`mrap_weak`), so a .50 still wrecks wheels and engines | Matches today's zones | Tyres behind the side armour |
| 89 | ATGM rows (TOW-2A, Konkurs-M, Kornet, 9M119M) arm at 25 m (real TOW about 65 m) and carry `range_m`; their guidance comes with A3 | The antiarmor suite's 5-25 m arming rule for every warhead | A longer arming distance (fails that rule) |
| 90 | `Shells.shell(id)` (not `Shells.get`, which is Object's); a warhead's `penetration_mm` and `blast_kg` are read as its `pen_ce` and `he_kg` | One reader for both files without repeating numbers | Copying the numbers into new keys |
| 91 | For phase D6b: the T-72B3's Kontakt-5 figures in 2.4.2 include the tiles; author the base plates plus `heavy_era` tiles, with the base turret CE a little under 900 so "TOW-2A: ~" holds; the BMP-2 front's "M2 M33: ~" needs a thinner front or reads "no" (the M33 is 24 mm at most) | The table test rates those columns as soon as their data lands | |
| 92 | Physical thickness (`phys_mm`, for overmatch and HE punch-through) of the M-ATV and MaxxPro capsule walls 25 mm (rear 20), roofs 8, engine bays 10 | An 84 mm HE round (22 mm of punch) only scorches an MRAP's side, as the antiarmor suite has it, while a 60 mm mortar (17 mm) still blows in its roof (2.3.6: "soft-skins and the roofs of light armour fail to it") | 12 mm walls (any HE rocket blew in the side) |

### The AI commander and cooperation

| # | Call | Why | The alternative |
|---|---|---|---|
| 33 | One `SideCommand` per side with `HotZonePolicy` (EnemyCommand's rules moved), `OperationPlan` and `DefencePlan` | One commander design for every side; hot zones keep their tuned behaviour | A separate friendly commander |
| 34 | The commander issues the same `HcOrder` records the player does, through `SquadOrders` | One execution layer; every fix serves both | Its own order system |
| 35 | The friendly commander never commands the company; players request | The player stays the company's commander; the Captain's "requests" | AI tasking the player squad |
| 36 | Report latency by side (3-8 s regulars to 60-15 s insurgents), x3 with comms down | Fair, and makes radios and comms masts matter | One delay for all |
| 37 | CP and CE scales kept from `EnemyCommand` and high_command.md | No retuning of hot zones | New scales |
| 38 | A quarter of CP kept in reserve; commit on a stall, a big counterattack or to exploit | HAL-style reserve use | No reserve |
| 39 | Counterattacks need AT power against known armour | Common sense; no infantry suicide runs at tanks | CP only |
| 40 | Allied groups virtualised except within 700 m of a player | Players see the allies beside them; budget holds | Allied groups always live |
| 41 | An armour table (soft and hard attack) for off-screen fights | Vehicles need a fair abstract fight | Treating vehicles as men |
| 42 | Requests answered with an ETA, a reason or a counter-offer within 2-6 s; three open per player | The Captain's "common sense stuff that would happen in real life" | Fire-and-forget calls |
| 43 | Allies ask players through one prompt card at a time, Y / N, 30 s; answering earns rep and a pay bonus, declining costs nothing but the outcome | Help is rewarded; nobody is nagged into it | Penalties for declining |
| 44 | Players see only the side's picture: fresh, aged, stale; world diamonds within 800 m (setting) | No omniscience (the Captain: "known friendlies and enemies") | True positions |
| 45 | Deconfliction in layers: sectors, the 10-degree fan, player bubbles, lift and shift, fires warnings, BFT, check fire | Several squads and armour in one fight need all of them | The last-guard check only |
| 46 | Pre-rendered `RadioVoice` clips for grids and numbers; no runtime speech synthesis | Matches today's pre-rendered Piper lines; no runtime cost | Runtime TTS |
| 47 | Original callsigns: Saber, Anvil, Iron, Hammer, Thunder, Shadow, Citadel | Original names | Real unit nicknames |

### High command

| # | Call | Why | The alternative |
|---|---|---|---|
| 48 | docs/high_command.md adopted as the base, its 14 open questions answered as in 5.1 | It was designed against the code and judged | A new design |
| 49 | Two standing hero squads (Hawk 2, Viper 3) on every new campaign, their wages paid, start cash +14 days of their wages | The Captain: "2 HC squads from the start" | Squads unlocked by rating |
| 50 | `AlliedTroops` elements move onto `HcOrder` | One order path with reports | Two systems |
| 51 | The 3D camera hides every actor and shows markers only; it doesn't stream the world in | Fog stays fair; no scouting with the camera | Showing the live world |
| 52 | The 3D mission map is the same camera in map mode | The Captain linked them | Two 3D views |
| 53 | Select > order > place > face > confirm, with undo (10 s), queue, repeat-last | The Captain's "logical" and "ease of use" list | Today's submenus |
| 54 | A terrain-masked cone (64-ray viewshed) for gun placement | The Captain: "a cone of fire visible" | An unmasked arc |
| 55 | One `ContextResolver` for world, map and camera; a one-key default; recent first; everything else still reachable | The Captain's contextual ask | Per-screen logic |

### High command, phase C builds (2026-10-22, Proposed)

Made while building the C lane (claude/ca-c-high-command); each is Proposed and can be changed.

| # | Call | Why | The alternative |
|---|---|---|---|
| C1.1 | `Soldier.hc_id` comes in the spawn data (like `iff`), not a replicated property | It never changes after spawn (succession keeps the group), and spawn data reaches every peer and late joiners for free | A SceneReplicationConfig entry |
| C1.2 | Allied elements get an hc_id (`allied1`, `allied2`) and a callsign now, ahead of C2's HcOrder move | They are high command groups; the groundwork fixes protect them too (rebalance used to remove them on a join) | Hero squads only |
| C1.3 | `Squad.is_squadmate(s)` = friendly AI, no hc_id, not allied or rebel marks, not recovery, not crew; `rebalance_squad` also needs the brain on the player squad | One predicate in place of G2/G3/G11's meta checks; the US troops (iff allied, no hc_id) are covered too | A meta per group |
| C1.4 | G4 by `Squad.is_player_squad()` (the level's `squad_for`), not by hc_id | Gun teams and US field squads have their own Squads without an hc_id; none of them should count the humans | `hc_id == ""` |
| C1.5 | `Callouts.HC_VOICE_M` 50 m | Middle of the doc's 40-60 m | 40 or 60 |
| C1.6 | `DeadGround` already existed (supports/, lifted for helicopter LZs); lift 4 is `DeadGround.known_watchers(level, squads)` (intel markers + squads' `known`) for game AI's `posts`, the soak and LZ picks keep `watchers()` | No second dead-ground search; the seam is the posts argument `find()` already takes | A new pure copy |
| C1.7 | FollowBrain's bands: Follow 30-60 m, Support me 60-120 m; ProgressWatch: wedged 4 s (the soak's), held up 30 s, unable 90 s | high_command.md 3.2 and 4.3 | Other numbers |
| C1.8 | Soak edits (lifts 7, 8 and the soak calling the lifted pieces) go as F-180 | coop_soak.gd isn't on claude/ai-driving | Bringing the soak branch in |
| C2.1 | The hero leads with the existing MOVE order given to himself; his men keep FOLLOW on him (he's the squad's leader). No new `Intent.LEAD` in squad_ai.gd | The followers already read only `leader`; it works today and keeps squad_ai.gd untouched | A new intent |
| C2.2 | `SquadOrders` is ticked by `HighCommand._physics_process` every 0.5 s, not from `Squad._physics_process` | No hook in squad.gd; one place ticks every group | The doc's Squad tick |
| C2.3 | The standing detachments are d02 (Hawk 2) and d03 (Viper 3), hired from `Hiring.candidate` with their role kits; the hero gets +0.12 nerve and aim and 5-8 missions, his men 2-5 | Believable veterans (5.2), the hiring board's own people | Fixed hand-made men |
| C2.4 | Hero squads spawn at the deployment's start, 100 m to either side of the insertion and 20 m back, on foot even after a helicopter insertion | high_command.md 3.1 (80-150 m); the helicopter carries the player squad only | Riding in with the player squad |
| C2.5 | Every contract carries `squads_max` = `Heroes.squads_max(rated, hot)`: 2, +1 rated 5, +1 hot, +1 operation, cap 3 (4 in operations); only the standing two exist until Phase 3 forms more | 5.1 question 4 | Rating-gated squads |
| C2.6 | The net: one line a squad every 3 s, a queue of 4 by priority; "copy", man-down and succession lines skip the gap; 4 orders a second per peer | high_command.md 6, 7 | No limits |
| C2.7 | Allied elements keep AlliedTroops' own dispatch; every order they get (support menu, map menu or HighCommand) is recorded as an HcOrder with a lifecycle: done within 12 m of the point, unable after 90 s without headway, reports on the net | One order path with reports (call 50), without rewriting AlliedTroops | Moving their dispatch into SquadOrders |
| C2.8 | A reported contact: an intel marker "Hawk 2: 6x" at once, and the other squads (and the player squad) note those enemies as heard 3 s later | 5.1's company picture with net delay | Instant sharing |
| C2.9 | Hero squads inside the extraction point at the end come out with the squad; outside, the leave-behind warning names them ("Hawk 2, 2 men, 380 m out") and a second confirm leaves them MIA | high_command.md 3.1 step 6; they never block | Waiting for them |
| C2.10 | C2's map: squad frames and order lines (MapCommandLayer), a right-click submenu per squad, and the HC panel on the left; C4 replaces the submenus with the full select > order > place > face > confirm flow | Enough to order and see the squads now | Waiting for C4 |
| C2.11 | Not in C2 (later): a debrief section per hero squad and the hero's "Led Hawk 2 at ..." history line; briefing insertion markers for hero squads | Kept the phase to the order path and the squads | |
| C3.1 | Attack: the attack position 120 m short of the objective along the approach (at once if closer); with a go code it sets there and waits; in, it uses `Squad.order_assault` (a walk-on when no enemy is known there); secure after 20 s with no known enemy within 40 m; a cluster within 60 m re-aims it; RED CE fails it and falls back to the attack position; 300 s to take it | high_command.md 3.2 and 4.1 with numbers | A fixed phase timer |
| C3.2 | Support by fire: from the order's first point onto its second (the map's "Support by fire on here" fires from where the squad stands); `safe_to_fire` checked every 6 s burst with a 5-degree fan either side out to the target + 30 m, the squad's own men and anyone within 3 m of the shooter left out; a friendly within 35 m of the target shifts fire 40 m deeper once if that's clear, else lifts; done after 60 s with the target quiet | 5.4 (10-degree fan, 35 m danger close) | Lifting only |
| C3.3 | Bound and Fall back use the squad's own drills (`order_bound`, `order_fall_back`), with no detours from ProgressWatch (it only reports) | The drills move the pairs themselves | Steering them |
| C3.4 | Defend frontage: one sector per buddy pair at its middle, facing out toward known enemies (else the order's facing); wider than 25 m a man covers the centre and says so; set when every pair is in, or after 90 s | 5.2 | A sector per man |
| C3.5 | Go codes Alpha, Bravo, Charlie and H-hour; a Move-type order on a code waits without moving; Attack and SBF move to their position first, then wait set ("Ready on Bravo"); H-hour goes at the deployment's start | high_command.md 4.1 | Gating everything at the start |
| C3.6 | One request in Phase 2: break contact, past the risk threshold on a Defend, Attack, SBF or Hold (Careful 25% down or an urgent casualty, Balanced 35%, Press on 50%); 20 s to answer; unanswered, Careful and Balanced heroes break contact, Press on holds; Careful breaks at once and reports | 4.1, 4.2 | Reinforce and CASEVAC requests now (they wait for B2's commander) |
| C3.7 | `hc_approve` Shift+Y and `hc_deny` Shift+N (Y is tag_enemy and N objectives_next in `Controls.KEYS`); pad players answer on the map panel | 5.1 question 13 checked against Controls.KEYS | Y / N alone |
| C3.8 | A squad goes dark for 15 s after a succession (no reports, no shared contacts, "No comms" on the HUD strip) | 5.3: dark until the new leader has the radio | A pick-up-the-radio action |
| C3.9 | The HUD strip shows only while hero squads are out, in the top-right zone under the objectives | high_command.md 10 | A new HUD zone |
| C3.10 | The command menu's Squads mode is left to C6's contextual menus (its number tree stays as it is) | C6 owns the menus | A second menu tree now |
| C4.1 | The order flow lives in `MapCommandLayer` (scripts/ui/map_command.gd), which MapView hands its input first and asks to draw; command mode is on whenever squads are out and you hold the command token, Tab turns it off and on | One hook each in MapView; no mode to find first | A separate Command toolbar mode |
| C4.2 | Order keys on the map: Move M, Defend D, Attack A, Support by fire S, Bound B, Fall back F, Frontage W, Hold H, Regroup R, Extract X, Follow me Y, Place gun G; 1-4 select, ] cycles, Space repeats, Backspace cancels, Ctrl+Z undoes, Esc or right-click cancels the placing; C turns command mode off and on (Tab is the map's theatre-map key) | The map has the keyboard while it's open (MapView takes the keys), so they don't clash with the on-foot keys; the letters match the order names | Function keys |
| C4.3 | A plain click (under 8 px of drag) keeps the default facing (toward the nearest enemy intel marker, else north for the gun) | 5.4.1 | Always asking for a facing |
| C4.4 | Support by fire is two clicks (where it fires from, then the target); a frontage is one drag from end to end | 5.4.1 with the two orders that need two points | A modal second step |
| C4.5 | Undo: the host undoes the squad's last order within 10 s when it's queued, waiting, or the hero is still within 5 m of where he was given it; the order it replaced comes back | 5.4.1 "if it hasn't started" | Client-side undo |
| C4.6 | The viewshed's step grows past 10 m for long ranges so a cast is at most 64 x 64 samples (the M2's 1,800 m cone samples every 28 m); thin walls come in as building boxes. Measured 2.8 ms in the debug editor (R build on the test PC), under the 2 ms budget expected in a release build; recast at most 10 times a second | 5.4.2's 4,000-sample budget at every range | 10 m always (11,500 samples for the M2) |
| C4.7 | Gun ranges in data/gun_ranges.json (M2 1,800 / 6,800 m, DShK 1,500 / 3,500, M240 800 / 3,725, Mk19 1,500 point and 2,200 area, M224 70-3,490, 2B14 85-4,100) | 5.4.2 and the mortars' KITS | Hard-coded |
| C4.8 | Place gun drives the player squad's gun loads (StaticWeapons "wt_setup:<left>:<right>"); `GunTeam.sector` faces the arc's middle, fires only inside it (its gunner too, through the gun's meta `sector` read by AavGunner) and never moves for fire from outside it. The wheel sets the arc (20-120, 60 default) | 5.4.2; one hook in AavGunner | A new gun-team order path |
| C4.9 | The mortar's firing point and dispersion read-out wait for a mortar on the bar (Place gun is the MG in C4; the mortar keeps its "wt_fire" map menu entry) | Kept C4 to the cone the Captain asked for | Both at once |
| C4.10 | The viewshed checks live in high_command_test (pure, a staged ridge), not a new suite | One fewer CI job; they're pure and fast | A viewshed suite |
| C5.1 | `high_command` is Shift+M (M alone is the map, Tab the inventory, every letter is taken in `Controls.KEYS`); PlayerInput checks it before anything else, and the map panel has a "3D view" button | 5.1 question 13 checked against Controls.KEYS | Tab (the inventory) |
| C5.2 | The camera hides the actors by hiding their nodes on this peer while it's up (every 0.5 s for new arrivals; what it hid comes back on close), not by a cull mask | Everything renders on layer 1 today; a render layer of their own would touch every soldier, vehicle and body mesh | Moving actors to their own render layer |
| C5.3 | Enemy markers in the camera come only from the map's markers ("enemy" intel and B1's "spot" markers with their uncertainty and band), so every peer, host or client, sees the same fair picture | 5.3 and 4.4 | The host's SidePicture (host only) |
| C5.4 | Orders from the camera: the same keys and validated path as the map (click the ground, drag to face, Shift to queue, Ctrl+Z); Support by fire, Frontage and Place gun stay on the map, where they have their two-point and cone tools | One flow; the 3D versions of the two-point tools can come later | All of them in 3D now |
| C5.5 | The body: a hit (its injury rises or it goes down) drops you back at once (`HcCamera.back_when_hit`, on); suppression of 0.35 or more shows the red edge | 5.3 | Only the red edge |
| C5.6 | Map mode builds a 96 x 96 relief of the zone's heights with the map's picture on it, in its own world inside a SubViewport over the map view; the briefing's "3D map" button toggles it. It shows the objectives, the insertion points and the known enemies (the map's markers) | 5.3's "one camera, two places" from what the loaded zone already has | A separate scene built from the zone def at the FOB |
| C5.7 | Camera cost: no extra rendering (it's the same world from another camera, actors hidden); markers rebuild 4 times a second (measured under 3 ms) | 9.3 budget | Every frame |
| C6.1 | `context` is the middle mouse button (a mouse binding in `Controls.BUTTONS`, rebindable): tap for the top option, hold 0.25 s for the radial; the command menu keeps the middle button while it's open | 5.5's proposal; no key in `Controls.KEYS` is free | A keyboard key |
| C6.2 | One table (`ContextResolver`, pure) for the world (`ContextMenu`), and its `hc_first` for the map's and the HC camera's order bar (enemy marker: Attack, Support by fire; building: Defend, Attack; extraction point: Extract; ground: Move, Defend) | 5.5: the same resolver everywhere | Per-screen lists |
| C6.3 | Recently used: the last 3 picks per kind of target, kept per peer for the session (not saved) | 5.5 | Saved in the settings |
| C6.4 | A prompt under the crosshair names the one key's default when you look at something other than open ground ("[Middle mouse] Follow me: Okafor") | The one-key default has to be seen to be used | No prompt |
| C6.5 | Looking at a hero squad's man in the world, its orders come to you (Move, Defend, Attack, SBF, Regroup at your position); the map and camera give them anywhere | In the world the only point to hand is where you stand | A second aim for the point |
| C6.6 | Requests from the menu go to RequestBroker (B4) with the unit's group id; fire support opens the command menu's Support page; "Swap kit" opens his loot window | B4's broker is the request path; fire missions keep their own flow | New request kinds |
| C6.7 | The crew wheel's driver and gunner orders say "Not yet" until A3's crews exist; Pop smoke and Bail out are there now (bail works, smoke waits for A3's launchers) | A3 owns the crew intercom (2.5.2) | Leaving the crew wheel out |
| C6.8 | The interaction menu (Left Ctrl) gains Follow me, Hold here, Heal up and (under More) Give ammo for a squadmate, through the command menu's own commands | 5.5's "the squadmate orders it lacks" | A second order path |
| C6.9 | voice_order.gd is unchanged: spoken orders already go through the command menu's commands | Nothing in 5.5 needs it | A voice context |

### Operations, the war and staging

| # | Call | Why | The alternative |
|---|---|---|---|
| 56 | Operation zones are 8,192 m, generated fresh, covering 2-4 neighbouring zones whose holder they flip | The Captain's ~8 km; ties the result to the map | Enlarging existing zones |
| 57 | Bands along an axis: start, outposts, crossing, town, depth | Reads as an invasion and gives every type its ground | Free layouts |
| 58 | A 256 m control grid makes the moving front | Cheap, readable, works with virtual groups | Scripted front lines |
| 59 | Five types: phased invasion, beach landing, armoured thrust, seizing a crossing, holding a town | The Captain's list | |
| 60 | Pay by phase with the shares, bonuses and penalties in 6.5; 20% advance | The Captain: "payment by phase" | Pay on completion only |
| 61 | Company vehicles lost on an operation are 50% reimbursed | Bringing armour shouldn't bankrupt the company | Full loss |
| 62 | Vessmark Defence Ministry added as a fictional government employer | The Captain: "and other foreign governments" | Only the US, UK and CA |
| 63 | Operations need trusted with the employer | They're the employer's big jobs | Open to all |
| 64 | Faction `vehicles` tables; two new original vehicles (Kestrel rhino truck, Saltline armoured SUV); Concord BTR-82A, BMP-2, MT-LB, T-72B3 | The Captain: "light armour into the game more" | Technicals everywhere |
| 65 | The US is a belligerent employer holding FOB Halberd (can't fall), fighting the Banner first, then Kestrel after the Banner is wiped | The Captain's answer | The US as a non-holding employer |
| 66 | US fronts pause while a US operation is offered or run; unaccepted, the tick resolves them | The company's choice matters; the war still moves without it | Fronts only moved by operations |
| 67 | UK, Canada and Vessmark don't hold ground; they fight in US operations | Keeps the war readable | Four allied belligerents |
| 68 | Staging rent $6,000 + $1,500 a day, x0.7 at allied, x0.5 for the host's own contract; trusted needed | The Captain: "for a fee and a standing requirement" | Free staging |
| 69 | Contract helicopter insertion and extraction cost $3,000 + $1,200 a link each way | Today it's free, so staging had nothing to save; the economy is "too easy overall" | Leaving flights free |
| 70 | Staging services are limited (no armory, stash, hiring or workshop; +25% resupply prices) | The Captain: "improvised", "limited services" | A full second base |

### Made while building D7 (US forces in the living war)

Numbered D7-n so they don't collide with other phases' calls. All Proposed.

| # | Call | Why | The alternative |
|---|---|---|---|
| D7-1 | FOB Halberd is placed by hand (`map_cell` in data/contracts.json, read by `RegionMap.layout`) north of Cove outpost, linked to it alone; no other zone moves | The grid has no free cell beside both Landing beach and Cove outpost, and filling Halberd into the grid would have moved every coast zone and its crossings | Re-flowing the coast grid; a hand-made link (two crossings on one edge) |
| D7-2 | With no war-target zone beside its ground, the US's front goes on the next zone on the shortest way to the nearest one, if an enemy of the US holds it ("clearing the way to the Banner") | The Banner's zones are scattered (coast and inland), so the US would stall after Cove outpost | Stalling until the company takes ground for it |
| D7-3 | The US's own front is outside the factions' cap of 3 (one US front at a time, its own seeded roll); the factions' fronts are counted without it | With 3 faction fronts open the US would often be locked out of its own war | Sharing the cap |
| D7-4 | Until D3's operation contracts, a US front's operation is a one-phase contract of the employer's `op_types` (US: raid, sabotage, HVT capture; Vessmark: raid, intel grab) against the front's holder, `op_front` naming the zone, up 4 days, titled "Joint operation" ("Vessmark operation") | D7 needed operations for 7.3's pause and 6.6's result before D3 builds the real ones; D3 swaps the stand-in for its phases | Waiting for D3 to make the US front pause at all |
| D7-5 | "Refreshed every 3 days" read as one operation per front: once it expires unaccepted, the front fights on by the tick to its end | Re-posting would keep a trusted company's board full and freeze every US front it ignores, against call 66's "unaccepted, the tick resolves them" | A fresh offer every 3 days |
| D7-6 | Vessmark posts beside every US operation (an `ops_only` employer, never a random board pick), x1.1 pay, needing trusted with Vessmark | 6.1: "Vessmark offers appear when the US has a front" | A board share of its own |
| D7-7 | A completed operation counts as all its phases, any other result as none; a held operation that lapses undeployed changes nothing | The stand-in has one phase; a lapse is the same as nobody taking it | A lapse as a failure |
| D7-8 | A zone the US takes is no flashpoint; an operation's success on the target's last zone sieges it instead of flipping it | A flashpoint posts a job against the new holder (the US); the Captain's wipe rule holds for the US too | 6.6's "with a flashpoint" literally |
| D7-9 | FOB Halberd defends at least as hard as the company's FOB (`FOB_DEFENCE`) | A base that can't fall shouldn't spend half the war sieged | The US's strength alone |
| D7-10 | US garrison at a held zone's HQ site (its HQ, else first outpost, compound, checkpoint); at Halberd every site (the main one 8 men, the rest 4); a site a held contract is about stays the enemy's; the other sites of a US-held zone hold the faction it took it from (else its war target) | 7.3's "garrison at each held zone's HQ site"; contract zones have no HQ module; a held zone still has work in it | Clearing every site of a US zone |
| D7-11 | US field groups: a patrol (M-ATV + MaxxPro, 8 men) in held and bordering zones; a convoy (M-ATV, MaxxPro, MaxxPro, M-ATV, 2 crew each, MaxxPros standing in for the HEMTT until D6a) every 10-15 min in held zones next to more US ground, from that crossing to the next or to the garrison and back; an armour section (2 Bradleys, an Abrams leading at US strength 85+) on a US front, halting 350 m short to overwatch, or at the garrison when US ground is attacked | 7.3's field list with the existing vehicles; a weak US doesn't field tanks | Abrams always |
| D7-12 | Until B2's friendly SideCommand they're squad-AI groups (faction friendly, green IFF, a Squad each), like AlliedTroops' elements; B2 takes them over | B2 isn't built; they still fight and the squad can see who they are | Waiting for B2 |
| D7-13 | Callsigns from call 47: Saber (patrols), Anvil (convoys), Iron (armour), Citadel (garrisons, Halberd); the US net's lines go to every player as notices, and enemy nets talk about the US every third ambient line where it's about (`radio_about`) | Original names, already chosen | Generic callsigns |
| D7-14 | US war wants: airfield 3, HQ 2, harbour 2, crossing 1; the US flag drawn in blocks (glyph `stripes`); Vessmark's flag slate blue with a gold block; its camo a grey-green variant of its own; start rep 0 | Gives the US's fronts a preference and the map a flag | |

### The plan

| # | Call | Why | The alternative |
|---|---|---|---|
| 71 | New per-model data in per-topic files merged by `VehicleSpecs.spec` | Parallel phases would collide in data/vehicles.json | One file |
| 72 | 29 session-sized phases in four lanes and six waves, new logic in new files | Parallel without overlap | Fewer, bigger phases |
| 73 | Builds cut after A5, C3 and D4 | The Captain's "builds only for major updates" | A build per phase |

### B1: the side picture (built 2026-10-22, branch claude/ca-b1-side-picture)

The details B1 had to settle that the doc left open. Each is Proposed and in data/side_picture.json
where it's a number. They're numbered B1.n so the phases landing beside it don't collide on numbers.

| # | Call | Why | The alternative |
|---|---|---|---|
| B1.1 | A `SideIntel` node per level (scripts/campaign/side_intel.gd) owns the friendly `SidePicture` and `GroupBoard` and feeds them until B2's `SideCommand` takes them over; the hostile ones live on `EnemyCommand` | B1 needed a host for the picture before the commander exists; one node, easy to hand over | Waiting for B2 to build the picture |
| B1.2 | A report gets its id when it reaches the picture; an entry keeps the ids it was built from, its freshest kept as long as the entry lives. Fairness = every entry, every spot marker and every world diamond traces to reports in the log, at its freshest report's position | Ids that rise through the log make the trace a binary search; the test checks it on 400 random reports and in play | Ids at send time (out of order after latency) |
| B1.3 | Latency profiles: the company, Meridian, US, UK and Canada regular (3-8 s); Eastern Concord and Vantage Group (a hostile PMC) 8-20 s; Black Ridge, Saltline, Kestrel and the Salvage Union irregular (15-45 s); Banner, Shura and Highland Front as `Alert` (60-15 s). Only insurgents slow under fire (x1.5, `Alert`'s rule). The delay is set by the leader's skill, no dice | The doc's table, filled in for every faction; tests can pin it | A random delay in the band |
| B1.4 | A player's tag, report or lase reaches the picture in 3 s (x3 with comms down); a lookout's or the UAV's at a mid-skill regular's 5.5 s | Players key their own radios; the fastest sender on the net | The company's 3-8 s |
| B1.5 | Radios: regular and Concord groups carry an issued set (the leader's, else the first man up); irregulars and insurgents need a radio in their kit; a squad meta `no_radio` takes it away. A report dies with its radio man if he's down before it's due (as `Alert`). A group with no radio holds its reports until one of its men is within 80 m of a man or player with a radio, who passes them on at his own delay | The doc's "radio man down" and shouting distance, without a radio item in every regular kit | Radio items in every allied kit |
| B1.6 | A report's kind comes from what the seen men carry (a launcher AT, an LMG or HMG MG, a sniper rifle or DMR sniper, else infantry); a cluster's men on foot are one report named for the most dangerous kind; each vehicle seen is its own report by its class | What a sighting tells a real observer; one icon per group on the map | One report per man |
| B1.7 | Base uncertainty by how it was seen: seen 5 m, heard 40, a tag 2, a radio report 10, a lase 1, noise 80 | A lase or a tag is a precise fix; a bearing heard isn't | One uncertainty for all |
| B1.8 | The merge window runs from the entry's last sighting; a late report of an older sighting merges (count, uncertainty) but never moves the entry back | "Position the fresher" with latency in the way | Merging by arrival time |
| B1.9 | At most 64 entries a side (full: the least lately reported of the 8 longest-standing goes); the log keeps 15 min or 512 reports, pruned in batches of 32; `EnemyCommand`'s keeps 4,096 so its fog reads every report of the last 10 min as it did | Bounded cost; hot zones unchanged | Unbounded lists |
| B1.10 | The hostile picture takes `Alert`'s contact reports with no extra delay (Alert already holds them 60-15 s, x1.5 under fire, x3 with the mast down); shots and blasts go in its log as noise, never as entries; `threat_cp` reads the log, and `_contacts` stays as the log for the tests that clear it | The doc's "moved, not rewritten": missions_test's hot-zone checks pass unchanged | A second delay on top of Alert's |
| B1.11 | A board row changes only at its group's sitrep (every 30 s): position, strength, ammo and CE as last reported. CP's skill floor is 0.3; a virtual man counts 0.6 skill without armour; a group's mounted vehicles add their CP and AT power; a vehicle group's CE stays whole until A2's modules (mobility only from fuel) | The commander knows its own groups by their reports too | Live rows |
| B1.12 | The player squad is a "company" row and `AlliedTroops` elements are rows, both with `taskable` false; garrison profiles without a squad aren't on the board until B2 needs them | 3.4.4: the commander plans around the company, never tasks it | Leaving the company off the board |
| B1.13 | BFT: a friendly vehicle (faction player, friendly or allied) is tracked at its true position while its radio works: not wrecked, battery up and no meta `radio_down` (A2's radio module sets it); grey and frozen after. Groups by their sitrep | A hook A2 fills without touching B1 | Waiting for A2's modules |
| B1.14 | Each entry is one MapMarkers `spot` marker on the intel channel, re-sent only when it changes; every peer ages it on its own clock from when it arrived; a late joiner gets ages brought up to now; players can't move or delete them | Little traffic, no shared clock needed; "joins the intel channel" (4.4) | Streaming the picture every second |
| B1.15 | The map symbol: men a diamond frame (the infantry cross, an MG mark, an AT chevron, a sniper ring), vehicles a box with the armour oval or wheels, mortars a tube; labelled "MG x1, 40 s", "last seen: ..." once stale; hovering adds who sent it and how long ago it came in ("Saber 2, 40 s ago") | APP-6-inspired and readable at a glance | Full APP-6 frames |
| B1.16 | World diamonds: none for a spot the player can see himself (in his view within 150 m with a clear line, checked 4 times a second); a tag's red diamond shows once `EnemyTags`' own mark over the man has gone; 0.95, 0.6 and 0.3 alpha by band. Settings: on/off, range 100-1,500 m (800) | No double marks, no clutter over what you're looking at | Diamonds over everything |
| B1.17 | The 0.3 ms budget is measured on a full picture (64 entries) taking 5 reports a step: 106 µs in the debug build. 40 groups each reporting a fresh cluster every 30 s make 1.3 a second; at 20 a step it's about 550 µs | A heavy fight's burst, not a steady state no fight reaches | 20 reports a second as the steady load |
| B1.18 | Friendly comms down is a hook (`SideIntel.server_set_comms`) until something calls it: no enemy jammer exists yet, and the operation HQ's relay comes with D3; the hostile picture's comms follow the mast | B1 builds the effect; its causes land with their phases | Inventing an enemy jammer now |

### B4, part 1: request plumbing before B2 (built 2026-10-22, branch claude/ca-b1-side-picture)

B4's pieces that don't need the commander: the broker, the cards and the radio voice. The jobs
themselves (moving, suppressing, treating) come with B2's SideCommand as the broker's executor.

| # | Call | Why | The alternative |
|---|---|---|---|
| B4.1 | `RequestBroker` runs the whole lifecycle now and hands each accepted request to an `executor` (B2's SideCommand), which moves it on with `server_progress`; with none, an accepted request waits and fails at `until_s` (10 min) "Timed out". No player entry point yet: C6's contextual menus and the map add them | The plumbing is testable and stable before anything can do the jobs; no half-working option in the game | Faking the jobs until B2 |
| B4.2 | `can_spare` is a hook B2 fills; until then every group can be spared | 4.2.10 is the commander's call | A stand-in rule |
| B4.3 | Refusals in a fixed order: committed to an assault, pinned (in contact and RED), ammo (black for jobs that shoot, amber or worse for an ammo ask), no medic, no smoke, out of range, the commander's answer; an ETA over 2 minutes is a counter-offer | The order a unit would answer in; data per kind (data/requests.json) | Random refusals |
| B4.4 | ETAs: within the kind's `in_place_m` 8 s, else the distance at 1.8 m/s on foot or 8 m/s mounted. Line of sight and SBF spots come with B2's executor | Close enough until routes are in | Path-finding on the host for every request |
| B4.5 | The answer comes 2-6 s after the ask by the group's CE (x1.5 in contact); a group with no radio hears only within 80 m | The doc's 2-6 s and shouting distance | One fixed delay |
| B4.6 | Groups answer under callsigns by kind and number (Saber, Iron, Anvil, Hammer, Shadow, Packhorse), kept for the deployment; the net itself is Citadel | 4.6's names | The squads' node names |
| B4.7 | Allied asks (4.3) built for contact support and ammo from the board; medic, clearing an AT threat, covering a crossing and recovery come with B2/B3 when groups know those states. One card per player at a time, 30 s; asks again from the same group after 5 min; cooperation counted per player (the employer's reputation and the operation bonus read it in D3) | The two asks the board already knows; the rest need the commander | All six now, half of them never raised |
| B4.8 | The cards answer to C2's high command keys (`hc_approve`, `hc_deny`) once they exist; until then the card's buttons | C2 owns the keys | Binding new keys here |
| B4.9 | RadioVoice says a line only when every word has a clip, digit by digit ("zero four one"); 2 voices; the words are data/radio_voice.json and requests_test checks every line the broker says is covered. The clips are rendered with tools/voices/gen_radio.py, which needs Piper: not on this PC, so they're still to render (subtitles meanwhile) | No half-spoken lines; the word list can't drift from the lines | Runtime speech synthesis (4.6 rules it out) |
| B4.10 | Requests travel as whole records to every peer on each change (a few at a time, closed ones kept 2 minutes) | Few records, simple late joins | Deltas |

### B2: the commander (built 2026-10-22, branch claude/ca-b1-side-picture)

| # | Call | Why | The alternative |
|---|---|---|---|
| B2.1 | A `SideCommand` tasks only the groups registered with it (`server_register`: an operation's employer troops, US forces once D7 fields live groups). Company groups are on the board as `taskable` false and planned around | 3.1: it never commands the company | Tasking every friendly squad |
| B2.2 | `HotZonePolicy` is moved in shape, not code: a hostile `SideCommand` sits beside `EnemyCommand` in hot zones, reads its picture and board, and tasks nothing itself; EnemyCommand's rules keep deciding there unchanged. The code move is mechanical once hot zones have their own [tactics]/operation-line comparison suite | Hot zones are tuned on that code and missions_test checks it | Moving 1,000 tuned lines now |
| B2.3 | Commanded groups run on `SquadOrders`, with the group's leader as its hero. The commander answers SquadOrders' calls itself: lines go out on the coordination net (friendly) or the enemy net (hostile); a break-contact request is approved at once; contacts reach the side through its picture, not HighCommand's shares | One order executor for everyone (3.1) | A second executor |
| B2.4 | A point worked out past the map's edge is clamped onto it before `HcOrder.clean` | Small maps and edge objectives | Refused orders |
| B2.5 | Allocation finds an Assault's SBF first, then the Assault from the rest; needs can carry `only` (a reserve, a counterattack force) and `prefer` (+0.5: whoever took an objective defends it). The rows go into packed arrays once: 0.5 ms for 40 groups and a company's 20 needs in the debug build on a quiet machine (30 needs 0.7-1.0 ms); the test fails past 2 ms, since other sessions' perf suites on the same machine double the figure | 3.4.3 and its 1 ms budget | Re-reading dictionaries per pair |
| B2.6 | Spots: an SBF 250 m back along the axis and 80 m off it; screens 300 m out on the main objective's flanks; a RED group with no plan rally falls back 250 m away from the enemies it has reported | Distances from the doc's ranges and the reels' "SBF on the flank of the assault's line" | Terrain analysis (comes with C4's viewshed) |
| B2.7 | An objective is taken when the side's picture shows no enemy in it for 90 s and one of its groups is there by sitrep | 3.5.1's consolidation, from what the side knows | The assault order's own 20 s |
| B2.8 | The reserve: the groups best suited to it (reserve suitability minus half their assault or SBF suitability), nearest the rally on a tie, never leaving fewer than two up front; topped up as groups arrive while it's uncommitted | 3.5.2, without stripping the assault of its SBF | A fixed quarter by list order |
| B2.9 | At the phase limit with no alternate axis: `fire_support_wanted` (D3's allied fires connect to it) and a 5-minute pause on the main objective | 3.5.1 | A silent stall |
| B2.10 | AMBER: an Assault or Flank still moving up holds and asks for support; one already going in keeps going. RED: falls back to the rally; two RED groups of a kind within 60 m merge, the larger keeping its callsign | 3.5.3; stopping mid-assault is worse than finishing it | Halting everything AMBER |
| B2.11 | The side withdraws on its commanded groups' losses since they were registered | The commander knows its own men | Counting the company |
| B2.12 | DefencePlan: each site held by the nearest group at the start; a site is lost when none of its groups is there and the picture shows the enemy; its own driven-off garrison may join the counterattack, other sites' garrisons don't; threat CP men 1.5 each (EnemyCommand's scale) and vehicles by the board's CP; a probe when nothing there is fresher than 3 min; the rally toward the force, 600-1,200 m (150 m hot); the go time 5-12 min, seeded; the prep 60 s before through `fire_support_wanted` | 3.7, Captain's 3:1 rule | Counterattacking at once |
| B2.13 | Players hear a counterattack coming ("Shadow, enemy massing at...") only when their side has reported enemies near its rally | 3.7's telegraphing, fair by B1's rule | Always telling them |
| B2.14 | The mobile reserve: the armour and mechanised groups not holding a site; sent to the most threatened line-1 site once a line-0 site falls | 3.7 | Holding it back for good |
| B2.15 | Off-screen fights: a commanded group carries its kind (`vf_kind`: its heaviest vehicle, else its men's kind) and the Virtualizer scales its hits by the armour table's attack over a rifle squad's 6, rounding at random; groups without one fight as before. A virtual commanded group is tasked by its profile's route. Wrecks from off-screen kills wait for virtual vehicles on profiles (A7, D2) | 3.8 without touching existing profiles | Re-tuning every virtual fight |
| B2.16 | For requests: no from a group mid-assault; a 2-minute counter from one busy on an SBF or flank; no from the last reserve while a counterattack is seen. Accepted jobs: suppress or cover is an SBF from where the group stands, hold a hold, the rest a move to the point; the request follows its order (route en route, firing or set on station, ended done or failed) | 4.2.10 | Requests the commander can't refuse |

### B3: armour with infantry (built 2026-10-22, branch claude/ca-b1-side-picture)

| # | Call | Why | The alternative |
|---|---|---|---|
| B3.1 | `ArmourInfantry` (scripts/campaign/armour_infantry.gd) rewrites each cycle's needs: every armour section is paired with the nearest infantry group (pairs stay while both exist), and paired armour takes only its own tasks: the escort, hand-offs. It stays out of the reserve | 3.6's pairing, without tanks being pulled onto the general assault when their screen falters | Pairing as a soft preference |
| B3.2 | The escort spot by ground: open (and night) overwatch 1 km off the infantry's objective; woods 150 m behind the infantry on the axis; a town 75 m behind, held at the town's edge until its screen is in the town | 3.6's table, at the middle of its ranges | Exact hull-down spots (A9's ArmourTactics) |
| B3.3 | Ground: a town or village module (or an objective marked town), woods where the scatter's foliage fills most of a 60 m cross, night when DayNight says it's dark | The world's own data | A terrain classifier |
| B3.4 | Hand-off: an infantry group AMBER, or in on its objective a minute without taking it, with an MG, gun or AT team reported within 60 m of its target, marks it to its armour ("Anvil 1, Saber 2, MG at 041 053, 120 metres, my tracer."), and the armour supports by fire on it; the round it fires is A3/A4's gunner's call | 3.6, with what's built now | Waiting for A3 |
| B3.5 | An AT team reported within 400 m of armour sends the armour's screen at it, whatever it was doing (its first job, 3.6), and the armour asks on the net; a player near is asked by card (RequestBroker "ask_clear_at") when the screen is already assaulting | 3.6 and 4.3 | Leaving it to the tank |
| B3.6 | Dismount points: 300-500 m short of the objective, the first of 15 candidates with no line from any reported enemy (a ray from 1.6 m to 2 m), else 300 m short | 3.6's dead ground, cheaply | A full viewshed (C4's) |
| B3.7 | "Never sits still in sight of uncleared buildings for more than 60 s" and "never first round a corner" are the crew's driving (A9's ArmourTactics); B3 keeps the armour behind its infantry and out of the town until it's in | Those need the crew AI | Guessing at them in the commander |

### B5: deconfliction (built 2026-10-22, branch claude/ca-b1-side-picture)

| # | Call | Why | The alternative |
|---|---|---|---|
| B5.1 | One static `Deconfliction` (scripts/campaign/deconfliction.gd) holds the layers; hooks in SquadAI's shot, SquadOrders' SBF bursts, the AAV gunner's target pick, FireSupport and Harm | One place to read and test | Rules scattered in each shooter |
| B5.2 | The fan stays SquadOrders' (5° either side, the target + 30 m) for SBF bursts and `_friendly_in_line` on every shot; `holds_fire` adds check fire, player bubbles and sectors before each AI burst, and costs nothing for squads without a sector (the player's, the company's) | The built guards keep working; the new ones cost only where they apply | A second fan check per shot |
| B5.3 | Sectors run from the group's sitrep position to its task, at least 30 m either side; overlap is judged on the far 60% of each (groups start side by side; lanes cross at the task end); a spot that can move (SBF, screen, overwatch, reserve, recon, flank) shifts sideways a lane at a time, up to four; an objective never moves | 3.4.5 | Shifting objectives |
| B5.4 | Player bubbles, 100 m: a commanded group's move bends round them (20 m outside); its suppression into one is held; an enemy it sees inside one can still be shot (the fan and the line guard decide that shot) | Players aren't suppressed over, and allies still defend them | Never firing near a player |
| B5.5 | Indirect fire: the FDC warns before a mission's first round with friendlies within twice danger close ("Splash in 45, friendlies stay south of the target."); a friendly inside danger close of the aim (not confirmed danger close) or a check fire stops the mission's unfired rounds ("Check fire, check fire.") | 4.5's FDC | Firing and hoping |
| B5.6 | Armour IFF: vehicle gunners (the AAV's now, A4's CrewGunner later) never pick a target within 50 m of a Blue Force Tracker vehicle (their own excepted) or under a check fire; the blue chevron in players' sights is A4's | 4.5 with what's built | Waiting for A4 |
| B5.7 | Check fire is a RequestBroker request with no answerer: in force at once, 100 m for 30 s, said by Citadel; its menu entry comes with the contextual menus' request options | Any player can call it, one path | A separate system |
| B5.8 | A friendly-fire incident is caught in `Harm.note_hit` (friendly hit by friendly), logged as "[ff]" with the distance and kept in `Deconfliction.incidents`; the employer's reputation cost and the debrief line are D3's, reading that list | One place every hit already passes | Per-weapon checks |
| B5.9 | Road reservations for vehicle columns (`RoadRoute`, `SquadDrivers`) are left for the driving lane: they need the columns' own timing | Out of the commander's files | Half a reservation system |
| B5.10 | The test's combined fight: two allied groups (an SBF and an assault) and a squadmate against three hostiles for 25 s live, zero incidents; then a check fire on the hostiles, and from 1 s on not a round fired at them. The mortar's check fire and the gunner's IFF are checked on their own; a live tank joins the fight when A3/A4 give it a gunner | B5's 9.3 row, cheaply and without flakes | A long full combined-arms run |

### B4, part 2: the jobs and the entry points (built 2026-10-22, branch claude/ca-b1-side-picture)

| # | Call | Why | The alternative |
|---|---|---|---|
| B4.11 | Players ask through C6's contextual menus (an allied unit looked at: the request list, suppression first in contact, a medic first with a casualty near; a casualty: CASEVAC; allied armour: armour support, a ride; open ground: Check fire here), which already send to the broker; the map's and the HC camera's menus share the same table | One table for every way in (5.5) | A request panel |
| B4.12 | A group's board id is its high command id where it has one (hawk2, allied1), what the menus name; else its node name | Named requests reach the group the player looked at | Two ids |
| B4.13 | An accepted request goes to its commander's executor (B2) for groups a SideCommand commands; for groups no commander has (the company's AlliedTroops elements), the broker runs suppress, cover, smoke, hold, ammo and a medic on the squad's own orders from its own leader, moving into range first; CASEVAC, armour and pick-ups take a commander's vehicles and are refused otherwise ("we can't do that without our orders") | Every request either happens or says why | Faking the vehicle jobs |
| B4.14 | A group that has nothing for a named request says so ("We've nothing for that") after the specific refusals (no medic, no smoke) | 4.1: nothing happens silently | Accepting and failing |
| B4.15 | The medic's green cross on the HUD is left to the cards' ETA for now (the medic's name and the countdown) | Cheap and clear | A world marker per medic |
