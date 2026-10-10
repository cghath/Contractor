# Contractor

Near-future tactical first-person shooter: command an 8-slot squad (up to 4 players, AI
fills the rest) through a persistent campaign, with physical inventory, a blood-and-wound
medical model and voxel destruction. Godot 4.7.2 + Zylann Voxel Tools 1.7, GDScript.

**Design authority:** [docs/contractor_handoff.md](docs/contractor_handoff.md) sums up
Captain's decisions and working agreements. Where it disagrees with this README or
`docs/squad_design.md`, the handoff wins.

**Version:** 0.1.0. See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## Installation

### Requirements

- **Godot 4.7.2 with Voxel Tools 1.7 built in.** Voxel Tools is a C++ engine module, so the
  project only opens in Zylann's custom editor build. The stock Godot editor (from
  godotengine.org) will fail with errors about `VoxelTerrain`, `VoxelBuffer` and similar classes.
- A GPU with Vulkan support (Forward+ renderer).
- Git, to clone the repository.

### 1. Get the code

```bash
git clone https://github.com/cghath/Contractor.git
```

The repository is private, so you need access to it on GitHub.

### 2. Get the Voxel Tools editor

Download the editor for your platform from the
[Voxel Tools v1.7 release](https://github.com/Zylann/godot_voxel/releases/tag/v1.7):

| Platform | File |
|---|---|
| Windows | `godot.windows.editor.x86_64.exe.zip` |
| Linux | `godot.linuxbsd.editor.x86_64.zip` |
| macOS | `godot.macos.editor.app.zip` |

Unzip it anywhere outside the project folder. It's a self-contained Godot editor and needs no installer.

Use the editor build, not `GodotVoxelExtension.zip` (the v1.7x GDExtension release). The
project was built and tested against the module build, and the author says the GDExtension
build has had less testing.

### 3. Open the project

1. Run the Voxel Tools editor you just unzipped.
2. In the Project Manager, choose **Import**, then select `project.godot` in the cloned folder.
3. The first open imports all assets. This takes a few seconds and creates the `.godot/` cache folder, which git ignores.
4. Press **F5** to run. On the main menu, choose **Host co-op** to play.

### 4. Play co-op

- **On one machine:** Debug → Customize Run Instances → enable multiple instances (2). Set
  the first instance's arguments to `-- --host` and the second's to `-- --join 127.0.0.1`.
  Press F5.
- **Over a network:** one player picks **Host co-op**. The others type the host's IP address
  and pick **Join**. The host must allow **UDP port 24680** through their firewall. Over the
  internet, the host's router also needs to forward that port.
- **From the command line**, without the editor (`--path` is the project folder):

  ```bash
  godot.windows.editor.x86_64.exe --path . -- --host
  ```

  ```bash
  godot.windows.editor.x86_64.exe --path . -- --join 192.168.1.20
  ```

### 5. Test builds

`tools/make_build.sh <label> ["what to test"]` leaves a playable build in
`builds/<date>_<label>/`: the game as a small `contractor.pck`, a `play.bat` launcher and a
`BUILD.txt` saying which commit it is and what to test. It needs no export templates; the
launcher runs the pack with the Voxel Tools editor build (set `CONTRACTOR_GODOT` if it isn't
in `Downloads\GodotVoxel_1.7`). `builds/` and `export_presets.cfg` are git-ignored; the
script writes a minimal preset if there's none.

```bash
GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/make_build.sh death-rules
```

A standalone `.exe` export needs the custom export templates from the same release:
`godot.windows.template_release.x86_64.exe.zip` (or the Linux or macOS template). In the
export preset, set it as the custom release template. The stock export templates don't
include Voxel Tools.

### Troubleshooting

| Problem | Fix |
|---|---|
| Errors like `Unknown class VoxelTerrain` or `Could not find type "VoxelBuffer"` | You opened the project with the stock Godot editor. Use the Voxel Tools build. |
| Walls appear, but bullets pass through them for the first second | Voxel collision builds in the background after the walls appear. This is expected. |
| A client can't connect | Check that the host's firewall allows UDP 24680, and that you used the host's LAN address, not `127.0.0.1`. |
| The compound comes back damaged after restarting | The host saves the zone on quit and with Home. Use **Reset compound save** on the main menu. |

## Controls

| Key | Action |
|---|---|
| WASD / Space / Shift / Ctrl | Move, jump, sprint, crouch |
| Mouse / LMB | Look, fire |
| RMB (hold) | Aim down sights: zoom, much tighter spread, half recoil, slower movement |
| E | Take / carry the item under the crosshair |
| R | Reload (fullest spare magazine; a part-used one goes back in your pouch) |
| H | Use a medical item (smallest kit that covers your injuries) |
| E on a downed teammate | Revive with your fastest kit (trauma kit 3 s to 50 HP, IFAK 5 s to 25 HP) |
| G | Throw the selected grenade (frag, flashbang or smoke) |
| Shift+G | Switch grenade type |
| Alt+G | Drop carried bulky item, otherwise drop active weapon |
| 1 / 2 | Primary / sidearm |
| F1-F8 | Select squadmates by number (F1 is the first player) and open the command menu; press more F-keys to add units |
| ~ | Select the whole squad and open the command menu |
| In the command menu | 1-9 and 0 pick an entry, or scroll the mouse wheel and click the middle button; Backspace goes back, Esc closes |
| Tab | Inventory screen: equip, stow, move between containers, use, drop |
| Esc | Close the inventory screen / release mouse |
| Home | Save zone (host) |
| K | Debug builds only: hurt yourself by 40, to test going down and dying (once down, the next hit kills) |

The command menu follows Arma 3's layout: 1 Move (return to formation, move there, stop), 3 Engage (open fire,
hold fire), 5 Status, 6 Action (throw smoke or frag at the crosshair), 8 Formation (wedge, file, line, staggered
column) and 0 Support. Target, Mount, Combat mode, Team and the support calls are listed but not built yet.

**Decided, not built yet** (from the handoff, with changes agreed since):

| Key | Action |
|---|---|
| F | Change fire mode |
| X / Z / C | Crouch / prone / mount the weapon on a surface |
| Q / E (hold, or double-tap to stay) | Lean left / right |
| Caps Lock (hold) + W / S | Step stance up or down in fine steps (replaces the handoff's Ctrl+W/S) |
| Caps Lock (hold) + A / D | Shift stance to the side (replaces the handoff's Ctrl+A/D) |
| Left Ctrl (hold) | Interaction menu on objects and people (replaces Left Windows, which opens the Start menu) |
| Left Ctrl + Left Alt (hold) | Self-interaction menu for your own body and gear (replaces Ctrl+Left Windows) |


## Design decisions (locked)

Updated 2026-10-10 to Captain's calls in [docs/contractor_handoff.md](docs/contractor_handoff.md),
which has the full rules.

| Area | Decision |
|---|---|
| Camera | First-person |
| Multiplayer | Co-op from day one, listen server (host is authoritative), up to 4 players |
| Voxels | World structures at 10 cm voxels; characters and gear as 1–2 cm voxel models |
| Armor | Plates and helmets are runtime voxel objects; hits chip voxels, holes let rounds through. Rounds and armor share an NIJ-named rating ladder (IIA to IV); ceramic cracks in zones, steel throws spall |
| Medical | No hitpoints: 6 L of blood, wounds per body part, pain, unconsciousness at 40% lost, cardiac arrest at 50% with a 10-minute window |
| Inventory | Volume budget in **litres** + visible gear; auto-stow, bulky items need two hands |
| Squad | 8 slots (two fire teams of four, a medic each, battle-buddy pairs); up to 4 players, AI fills the rest. Starts at 1 AI squadmate. AI tactics modeled on LAMBS Danger and VCOM |
| Death | AI: permadeath on bleed-out, MIA if left behind alive. Players respawn in the default kit (M4, 2 spare mags + 90 rounds, 1 smoke, 1 frag); their old gear stays where they died, with a marker |
| HUD | Minimal, like Arma with ACE: no health bar or ammo counter |
| Missions | Contract zones and hot zones (several contracts, ends at extraction); cash economy; supports (resupply, transport, AAVs, extraction) called from the LHD or FOB |
| World | 3 factions with shifting territory; day and night, weather, NVGs as gear |
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
  combat/         Vitals (health, healing), VoxelArmor (plates, helmets), GearRig (worn gear), Ballistics, Grenade/Throwables/SmokeCloud
  actors/         Soldier: the shared body for players and AI (state, carrying, host-validated requests);
                  SoldierMovement (walking, crouching, speed costs); PlayerInput (human driver, camera, HUD)
  ai/             SquadAI (utility intents, buddy tactics, casualty care), Squad (orders, formations)
  player/         CharacterModel (procedural voxel soldier), Hud
  art/            VoxelArt: code-built voxel models (body parts, carriers, packs, rifles, pistol)
  world/          VoxelWorld (10 cm destructible structures), CompoundLevel, NavBuilder, GearMarker, TargetDummy
  ui/             Menu, InventoryScreen, CommandMenu
data/             items.json, factions.json (placeholder), missions.json (placeholder)
tests/            smoke_test, gameplay_test, squad_test, net_test (headless), screenshot_tour
tools/            run_tests.sh, make_build.sh
```

**Who owns what in multiplayer:**

- The owning peer simulates its own movement, which `Sync` replicates.
- The host owns health and inventory, which `ServerSync` replicates to everyone, including players who join late. Item state (rounds loaded, armor chips) is part of the inventory, so it replicates the same way, and travels into the world when an item is dropped.
- Clients never change shared state directly. They send requests like `_server_fire` and `_server_interact`, and the host validates them.
- Voxel destruction is a log of edits kept by the host. Every peer builds the same base structures itself and then replays the log, so only small edit events go over the network. The same log is what gets saved.

**Armor:**

- Plates and helmets are `VoxelArmor`: 1 cm voxels that are both the visual and the hit target.
- A round is traced voxel by voxel along its path. If it meets material it's stopped, and a chip is carved there. If it reaches the empty interior (the head inside a helmet) or leaves through a hole, it carries on to whatever is behind.
- Each chip punches a hole, spalls the surface around it, and scars a ring beyond that.
- The mesh is rebuilt by replaying the full chip list, so everyone sees the same damage. The chip list is the item's own state, so a dropped plate keeps its holes, and so does whoever picks it up.
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

Run every suite with one command (from Git Bash on Windows):

```bash
GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
```

There are three suites. Each prints PASSED or FAILED and exits with its failure count.

| Suite | Scene | What it covers |
|---|---|---|
| Smoke | `tests/smoke_test.tscn` | 88 checks of the core systems directly: item database, inventory rules, carrier tiers, item state (damage and ammo that travel with an item), ammo and reloading, healing, downed/bleed-out/revive, voxel armor and walls, ballistics, headshots, elbow IK |
| Gameplay | `tests/gameplay_test.tscn` | Hosts a real session and drives the player through the same requests a client sends: fire, reload, heal, inventory-screen actions, drop and pick up, spread and aiming, going down, reviving a downed body, dying and respawning |
| Network | `tests/net_test.tscn` | Two processes over ENet. The client fires, reloads, heals and drops through the host, and checks that the results replicate back |

The gameplay and network tests use their own save zones and never touch your compound save.
To regenerate the screenshots in `screenshots/` (this opens a window for a few seconds):

```bash
godot.windows.editor.x86_64.exe --path . res://tests/screenshot_tour.tscn
```

## Versioning and changelog

Versions follow [Semantic Versioning](https://semver.org). While the version is 0.x, a minor
bump (0.1 → 0.2) means a new playable milestone, and anything may change between versions.
The current version is `config/version` in `project.godot`.

Every change that affects the game or how to work on it gets a line in
[CHANGELOG.md](CHANGELOG.md), under **Unreleased**, in the same commit as the change. To cut
a release:

1. In `CHANGELOG.md`, rename **Unreleased** to the new version and today's date, and add a
   fresh empty **Unreleased** section above it.
2. Update the comparison links at the bottom of `CHANGELOG.md`.
3. Bump `config/version` in `project.godot` and the version line at the top of this README.
4. Commit as `Release vX.Y.Z`, then tag and push:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   ```

   ```bash
   git push origin main --follow-tags
   ```

## Known gaps (next up)

- Shots are hitscan, with no bullet drop or travel time. Spread is decided by the shooter's machine (fine for co-op, not cheat-proof).
- Every inventory change, including each shot fired, re-sends the whole inventory snapshot. That's fine on a LAN; it needs a lighter path (for example, ammo only) before internet play.
- Reloading and healing can't be cancelled, and taking damage doesn't interrupt them.
- The gear marker over a dead player's gear isn't sent to players who join later. The respawn kit lacks the handoff's 90 rounds until there's a loose-ammo item.
- Downed bodies keep an upright movement capsule, so others bump into an invisible standing body.
- A vest or backpack can't be dropped while it still has things in it. Empty it from the inventory screen first.
- The voxel world has no stream, so it's limited to `VoxelWorld.BOUNDS`. The voxel edit log grows with every bullet hole and is never compacted.
- Player inventories aren't saved yet; only the zone's state is.
## Revised roadmap

1. **Foundation (v0.1.0):** gray-box compound, FP co-op player, volume inventory, voxel plates, destructible walls, zone save.
2. **Inventory depth (done, unreleased):** ammo and reloading, an inventory screen, armor damage and ammo that travel with the item, medical items.
3. **Squad prototype (early, highest risk):** the wound model, then one AI squadmate scaling to the 8-slot squad with buddy pairs, throwables, carry/drag and treatment, the Arma-style command menu and the new controls. See the checklist in [docs/contractor_handoff.md](docs/contractor_handoff.md) and the design in [docs/squad_design.md](docs/squad_design.md). Step 1 (the shared `Soldier` body) is done.
4. **Mission loop:** contracts, reinforcement timer, extraction, salvage share, persistent zone graph.
5. **Ground vehicles:** drivable, modular damage, cargo as a rolling stash. Aircraft as AI-flown transport and fire support.
6. **Factions:** territory, reputation tiers, dynamic events.
7. **Vertical slice + art:** voxel character and gear models, voxel import pipeline, polish.
