# Contractor

Tactical first-person co-op shooter with physical inventory and voxel destruction.
Godot 4.7.2 + Zylann Voxel Tools 1.7, GDScript.

## Opening the project

Voxel Tools is compiled into a custom Godot build, so the stock editor **can't** open this project.
Use:

```
%USERPROFILE%\Downloads\GodotVoxel_1.7\godot.windows.editor.x86_64.exe
```

(From https://github.com/Zylann/godot_voxel/releases/tag/v1.7. Exports need the matching
`godot.windows.template_release.x86_64.exe.zip` custom template from the same release.)

## Testing co-op on one machine

Debug → Customize Run Instances → enable multiple instances (2). Set the first instance's
arguments to `-- --host` and the second's to `-- --join 127.0.0.1`. Press F5.
Or use the menu: **Host co-op** in one window, **Join** in the other.

## Controls

| Key | Action |
|---|---|
| WASD / Space / Shift / Ctrl | Move, jump, sprint, crouch |
| Mouse / LMB | Look, fire |
| E | Take / carry the item under the crosshair |
| G | Drop carried bulky item, otherwise drop active weapon |
| 1 / 2 | Primary / sidearm |
| Tab | Inventory detail |
| Esc | Release mouse |
| F5 | Save zone (host) |

## Design decisions (locked)

| Area | Decision |
|---|---|
| Camera | First-person |
| Multiplayer | Co-op from day one, listen server (host is authoritative), up to 4 players |
| Voxels | World structures at 10 cm voxels; characters and gear as 1–2 cm voxel models |
| Armor | Plates and helmets are runtime voxel objects; hits chip voxels, holes let rounds through. Light, medium and heavy tiers |
| Inventory | Volume budget in **litres** + visible gear; auto-stow, bulky items need two hands |
| Squad | One shared AI squad; revivable, permadeath if bled out or left at extraction |
| Missions | Simple reinforcement timer from the start; 3 factions; zone-graph world map |
| Vehicles | Drivable ground vehicles (players or AI); aircraft AI-flown only |
| Player-built faction | Late-game stretch goal |

## Architecture

```
autoload/
  controls.gd     input actions, registered in code
  item_db.gd      loads data/items.json → ItemData
  game_state.gd   zone persistence: looted uids, dropped items, voxel edit log → user://saves/
  net.gd          ENet host/join, connection signals
scripts/
  inventory/      ItemData, Inventory (slots + litre containers), WorldItem (pickup)
  combat/         Vitals (health + plate damage), VoxelArmorPlate, GearRig (worn gear), Ballistics
  player/         Player (FP controller + host requests), CharacterModel (procedural voxel soldier), Hud
  art/            VoxelArt: code-built voxel models (body parts, helmet, vest, packs, rifles, pistol)
  world/          VoxelWorld (10 cm destructible structures), CompoundLevel, TargetDummy
  ui/             Menu
data/             items.json, factions.json (placeholder), missions.json (placeholder)
tests/            smoke_test (headless)
```

**Who owns what in multiplayer:**

- The owning peer simulates its own movement, which `Sync` replicates.
- The host owns health, plate damage and inventory, which `ServerSync` replicates to everyone, including players who join late.
- Clients never change shared state directly. They send requests like `_server_fire` and `_server_interact`, and the host validates them.
- Voxel destruction is a log of edits kept by the host. Every peer builds the same base structures itself and then replays the log, so only small edit events go over the network. The same log is what gets saved.

**Armor:**

- Plates and helmets are `VoxelArmor`: 1 cm voxels that are both the visual and the hit target.
- A round is traced voxel by voxel along its path. If it meets material it's stopped, and a chip is carved there. If it reaches the empty interior (the head inside a helmet) or leaves through a hole, it carries on to whatever is behind.
- Each chip punches a hole, spalls the surface around it, and scars a ring beyond that.
- The mesh is rebuilt by replaying the full chip list, so everyone sees the same damage.
- Tiers (stats in `data/items.json`):

  | Tier | Carrier | Plate pockets | Helmet | Plate |
  |---|---|---|---|---|
  | Light | Low-profile, 3 L | Front | Bump helmet: thin, open face | Polyethylene: light, chips badly |
  | Medium | Plate carrier, 6 L | Front, back | Ballistic helmet with NVG shroud and rails | Ceramic |
  | Heavy | Assault carrier, 8 L, collar and groin flap | Front, back, 2 sides | Assault helmet with ear covers and visor | Steel: heavy, small holes |

- Helmets are rounded-box shells shaped to fit the blocky head. The heavy helmet's visor stops rounds to the face.

**Characters and hits:**

- Bodies are procedural voxel soldiers built from 2 cm voxels: head, torso, arms and legs on joint pivots, animated in code.
- There are four camo variants (multicam, woodland, desert, urban). Each player's variant is picked from their peer id. Dummies use a crash-test yellow variant.
- Gear is voxel art mounted on the torso or head, so it follows the animation.
- Each body has three separate colliders:
  - a movement capsule on the `movers` layer;
  - slim body and head boxes on the `hitboxes` layer that bullets hit (the head does ×3 damage, set by the `damage_mult` meta);
  - armor areas on the `armor` layer.
- Bullets ignore the movement capsule, so a slim torso can wear plates without them being buried inside the capsule.
## Tests

```
godot.windows.editor.x86_64.exe --headless --path . res://tests/smoke_test.tscn
```

The smoke test covers 30 checks across the item database, inventory rules, plate chipping, voxel building and carving, and armor penetration against a target dummy.

To regenerate the screenshots in `screenshots/` (this opens a window for a few seconds):

```
godot.windows.editor.x86_64.exe --path . res://tests/screenshot_tour.tscn
```

## Known gaps (next up)

- No ammo consumption or reloading yet. Weapons fire as long as one is equipped.
- Plate damage belongs to whoever is wearing the plate, not to the plate itself. A plate you drop and pick up again comes back undamaged.
- A vest or backpack can't be dropped while it still has things in it. There's no inventory screen for moving items between containers yet.
- The voxel world has no stream, so it's limited to `VoxelWorld.BOUNDS`. Bigger zones will need a `VoxelStream`.
- The voxel edit log grows with every bullet hole. Compact it before shipping.
- Player inventories aren't saved yet; only the zone's state is.

## Revised roadmap

1. **Foundation (done here):** gray-box compound, FP co-op player, volume inventory, voxel plates, destructible walls, zone save.
2. **Inventory depth:** ammo and reloading, an inventory UI for moving items between containers, plate state that travels with the plate, medical items.
3. **Squad prototype (early, highest risk):** one shared AI squadmate who carries their own gear, follows, takes cover, and can be downed and revived.
4. **Mission loop:** contracts, reinforcement timer, extraction, salvage share, persistent zone graph.
5. **Ground vehicles:** drivable, modular damage, cargo as a rolling stash. Aircraft as AI-flown transport and fire support.
6. **Factions:** territory, reputation tiers, dynamic events.
7. **Vertical slice + art:** voxel character and gear models, voxel import pipeline, polish.
