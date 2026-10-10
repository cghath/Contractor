# Changelog

All notable changes to Contractor are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Add new entries under
**Unreleased** in the same commit as the change. The README's "Versioning and changelog"
section explains how to cut a release.

Entry types: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## [Unreleased]

Phase 2, inventory depth: ammo, reloading, healing, an inventory screen, and item state
that travels with the item.

### Added

- **Squad AI (phase 3, first pass):** the player squad has 8 slots, and AI fills every slot players don't (7 squadmates for one player, 4 for four). See `docs/squad_design.md`.
  - Arma 3-style command menu: F1-F8 select squadmates by number (~ for all), then 1-9 / 0 or the mouse wheel and middle click pick orders: move (formation, move there, stop), engage (open / hold fire), status, action (throw smoke or frag at the crosshair), formation (wedge, file, line, staggered column) and a support menu (not built yet). Orders go to the selected units; the last player to give one leads.
  - Everyone is paired into battle buddies. In a fight, soldiers take cover, crouch when not shooting, get pinned by close fire, and buddies take turns moving while the other covers. Frags go to enemies hiding behind cover.
  - Downed friendlies (players too) get help, buddy first: in a fight, smoke and a drag to cover, then a revive or a guard; out of a fight, a revive, or the buddy carries them and follows the lead.
  - Hostile fire teams (two guards, two on patrol) use the same body and AI.
  - A runtime navmesh over the compound. The HUD lists each squadmate's status and health.
  - `tests/squad_test.tscn`: roster scaling, navigation, following, a buddy carrying a buddy, a firefight and flashbang stun.
- **Grenades (G to throw, Shift+G to switch type):** frag, flashbang (new item) and smoke.
  - Frag: up to 180 damage within 8 m, falling off with distance; walls shield you. It also blasts a crater in voxel walls.
  - Flashbang: whites out the screen for up to 5 s, depending on distance and whether you were looking at it. AI soldiers will be stunned.
  - Smoke: a 5 m cloud that lasts 30 s. It blocks the view, and will block AI line of sight.
  - Every peer sees the grenade fly; the host detonates it. The compound has smokes and flashbangs next to the frags.

- **Item state:** items carry state that goes wherever they go: rounds in a weapon or
  magazine, chips in a plate or helmet. It's kept while the item is worn, stowed, dropped,
  picked up by someone else, and saved with the zone.
- **Ammo:** weapons come loaded and every shot uses a round. Firing an empty weapon tells
  you to reload.
- **Reloading (R):** loads the fullest compatible magazine you carry. A part-used magazine
  goes back where the new one came from, and an empty one is discarded. Reload times are
  per weapon (pistol 1.6 s, M110 2.8 s); you can't fire while reloading. Other players see
  your left hand working the magazine.
- **Medical items (H):** IFAK (+35 HP over 4 s) and trauma kit (+70 HP over 8 s). You get
  the smallest kit that covers your injuries; using one keeps your hands busy for a moment.
- **Inventory screen (Tab):** equipped slots and container contents, with Equip, Stow,
  Use, move to another container, and Drop. Rounds loaded, part-used magazines and armor
  damage are shown on each item.
- **HUD:** ammo counter (loaded / spare rounds) and reloading and healing indicators.
- **Aiming down sights (hold RMB):** zooms to each weapon's aim FOV (M110 30°, pistol 65°),
  lines the weapon's sight up under your eye, and cuts spread to 12% of hip fire. It also
  halves recoil and slows movement.
- **Spread and recoil:**
  - Each weapon has a spread cone, which widens while moving (up to 2.5×) or in the air (2.5×) and tightens when crouched.
  - Each shot kicks the view up and slightly sideways.
  - Stats per weapon: `spread_deg`, `recoil_deg`, `ads_fov`.
- **Downed and revive:**
  - At 0 HP you go down instead of dying: you fall face down, can only crawl, can't shoot, and drop anything you're carrying in both hands.
  - You bleed out after 60 s. Another hit while down kills you. There is no giving up.
  - Teammates revive you with E: a trauma kit takes 3 s and brings you back at 50 HP; an IFAK takes 5 s and brings you back at 25 HP. The kit is used up when the revive completes.
  - Hitboxes lie down with the body, so shots land where you're lying.
  - Dead bodies lie down too. Target dummies get back up on their own after a few seconds.
- **Ground items:** the pickup prompt shows rounds and damage. Armor on the ground shows its chips.
- **Docs:** `docs/squad_design.md`, the phase 3 squad AI design (body/driver split,
  navigation, utility intents, co-op command, inventory loop, permadeath), with the decisions made.
- **Test builds:** `tools/make_build.sh <label>` leaves a playable build in
  `builds/<date>_<label>/`: a small `contractor.pck`, a `play.bat` launcher that runs it with
  the Voxel Tools Godot (no export templates needed) and a `BUILD.txt`. Builds stay local
  (`builds/` is git-ignored).
- **Debug key K** (debug builds only, which includes test builds): hurts you by 40 so going down and dying can be tested solo.
- `Inventory.strip()` empties a body's whole inventory into entries that keep their state.
- **Tests:**
  - `tests/gameplay_test.tscn`: end-to-end checks of a hosted session through the real requests a client sends.
  - `tests/net_test.tscn`: a two-process ENet host and client.
  - `tools/run_tests.sh` runs every suite.
  - The smoke test now has 88 checks. The gameplay test covers spread, aiming, going down and reviving, and a host-owned AI body driven through the same API, and the new death rules.

### Changed

- **Design authority:** `docs/contractor_handoff.md` (Captain's decisions, 2026-10-10) now
  overrides the README's locked decisions and `docs/squad_design.md`. Both were updated to
  match: 8-slot squad, wound model, minimal HUD, new death rules, new controls.
- **Player death:** you respawn in the default kit (M4, 2 spare magazines, a smoke and a
  frag). Everything you carried stays where you died, under a floating marker that clears
  once the gear is picked up. Before, you respawned with all your gear.
- **AI death is permanent:** an AI soldier that dies doesn't respawn; its gear stays where it fell.
- **Planned keys** (README, "Decided, not built yet"): stance adjust moves to holding Caps
  Lock + WASD, interaction to holding Left Ctrl and self-interaction to holding Left Ctrl +
  Left Alt, instead of the handoff's Ctrl+WASD, Left Windows and Ctrl+Left Windows.
- **No giving up:** a downed player can only wait for a revive or bleed out. F no longer
  does anything while down (it's reserved for fire mode); `Vitals.server_give_up` is gone.
- **Minimal HUD:** no health, ammo, grenade count, load or armor readout, as in Arma with
  ACE. The squad roster shows what each squadmate is doing, without health. Weight,
  litres, rounds loaded and armor damage are on the inventory screen (Tab).
- Keys: G throws grenades (Shift+G switches type) and Alt+G drops; F-keys are the squad command menu, so saving the zone moved from F5 to Home.
- `Player` is now `Soldier` (`scenes/soldier.tscn`, `scripts/actors/soldier.gd`), the body both players and AI use. AI bodies have non-numeric names and are driven by the host.

- Armor damage is now the item's own state, not the wearer's. A dropped plate or helmet
  keeps its holes. `Vitals` now only tracks health and healing.
- `Inventory.unequip()` returns the item with its state. `take()` accepts state.
- `Vitals` gained the downed state (`downed`, `bleed_seconds`, `server_revive`), replicated to all peers.
- **Menu:**
  - The host button is now "Play (host a session)", with a note that solo play means hosting.
  - A failed join says that someone must be hosting at that address.
  - Join retries 3 times, about 2.5 s each, so a second window started with the host still connects.
  - Hosting on a busy port suggests joining instead.

### Fixed

- Armor lying on the ground no longer tries to set an empty node name.

## [0.1.0] - 2026-10-09

First playable gray-box foundation: a co-op player can loot, gear up and shoot through
voxel armor and walls in a test compound.

### Added

- **Engine setup:** Godot 4.7.2 with Voxel Tools 1.7 (custom editor build), GDScript, Jolt physics.
- **Co-op:** ENet listen server with up to 4 players. The host is authoritative over health,
  armor and inventory, and replicates them to everyone, including late joiners. Owners
  simulate their own movement. `--host` and `--join <address>` command-line shortcuts.
- **Player:** first-person controller with walk, sprint, crouch and jump. Carried weight
  slows you down, and bulky items slow you further and block sprinting and firing.
- **Inventory:**
  - Body slots for primary, sidearm, helmet, vest, backpack and four plate pockets.
  - Volume measured in litres: pockets 2 L, plus whatever the vest and backpack add.
  - Equipping and stowing happen automatically on pickup; bulky items (HVT case, supply crate) are carried in both hands.
  - Drop (G), weapon switching (1 and 2), and an inventory detail view (Tab).
- **Items:** 28 items in `data/items.json`: rifles, a DMR and a pistol; magazines; light,
  medium and heavy carriers, helmets and plates; side plates; backpacks; medical items,
  grenades, a breaching charge, salvage and objective items.
- **Placeholder data:** 3 factions with reputation tiers (`data/factions.json`) and 5
  mission objectives (`data/missions.json`).
- **Voxel structures:** destructible 10 cm voxel walls, cover and crates. Bullets carve
  holes. Damage is kept as an edit log that the host sends to joining players and saves.
- **Zone persistence:** looted items, dropped items and voxel damage are saved to `user://saves/`. Save with F5, on quit, or reset from the menu.
- **Characters:**
  - Procedural voxel soldiers built from 2 cm voxels, in four camo variants (multicam, woodland, desert, urban), plus crash-test-yellow target dummies.
  - Code-driven animation: walk and sprint cycles, breathing, and the head following where the player looks.
  - Elbows with two-bone IK put the palms on each weapon's grip points.
  - Rifles move between the sling and the hands, and the pistol between the holster and the hands.
- **Gear art:** voxel models for the plate carriers (light, medium and heavy), backpacks
  whose depth follows capacity, the three rifles and the pistol. They're worn on the body,
  shown in first person and lying on the ground.
- **Destructible voxel armor:**
  - Plates and helmets are made of 1 cm voxels.
  - Each round is traced voxel by voxel. If it meets material it's stopped and the armor chips; if it reaches a hole it carries on to whatever is behind.
  - Damage replicates to every peer and is replayed for late joiners.
- **Armor tiers:**
  - Light: low-profile carrier with a front plate pocket, bump helmet, polyethylene plate.
  - Medium: plate carrier with front and back pockets, ballistic helmet, ceramic plate.
  - Heavy: assault carrier with front, back and side pockets, a helmet with ear covers and a visor, and a steel plate.
- **Hitboxes:** separate colliders for movement, body, head (×3 damage) and armor.
- **Test compound:** perimeter wall with a gate, a building, cover, crates, starting loot, and light, medium and heavy armored target dummies.
- **HUD:** health, weight, litres used per container, armor condition, interaction prompts and an inventory detail view.
- **Tests:** a headless smoke test with 54 checks, and a screenshot tour that regenerates `screenshots/`.
- **Docs:** README with installation steps, controls, architecture and roadmap; this changelog.

### Known issues

- No ammo use or reloading yet.
- Armor damage stays with the wearer, so a dropped plate or helmet comes back undamaged.
- No inventory screen for moving items between containers. A vest or backpack can't be dropped while it has contents.
- The head hitbox doesn't tilt with the head; the helmet does.
- The voxel world has no stream, so zones are limited to `VoxelWorld.BOUNDS`. The edit log is never compacted.
- Player inventories aren't saved; only the zone's state is.

[Unreleased]: https://github.com/cghath/Contractor/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cghath/Contractor/releases/tag/v0.1.0
