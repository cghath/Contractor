# Changelog

All notable changes to Contractor are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Add new entries under
**Unreleased** in the same commit as the change. The README's "Versioning and changelog"
section explains how to cut a release.

Entry types: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## [Unreleased]

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
