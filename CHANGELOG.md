# Changelog

All notable changes to Contractor are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Add new entries under
**Unreleased** in the same commit as the change. The README's "Versioning and changelog"
section explains how to cut a release.

Entry types: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.

## [Unreleased]

### Wave 2 of the build plan (phase 3 finish)

Built by three agents in parallel (kit and treatment, AI casualty care, ammo and smokes),
then finished by two more after Captain's direction mid-wave: no revive, bodies keep their
gear, medics put the wounded first. Merged on `dev`. See `docs/build_plan.md`.

#### Added

- **Field kit on the wound model:**
  - The IFAK and trauma kit are bags of real items. IFAK: 1 tourniquet, 2 pressure
    bandages, 1 hemostatic gauze, 1 vented chest seal. Trauma kit: 2 tourniquets, 4
    bandages, 2 gauze, 2 seals, 1 splint, 2 morphine, 1 NPA. Loose items are used first,
    and the inventory screen shows what's left in each kit.
  - Treat yourself (Left Ctrl + Left Alt) or others (Left Ctrl): a Treat submenu lists
    what's needed in casualty-care order with the body part ("Tourniquet, left thigh"),
    greyed out with a reason when you don't carry the item. H applies the next item for
    your own most urgent wound.
  - Times: tourniquet 4 s (6 s on yourself), bandage 5 s, gauze 8 s, chest seal 5 s, splint
    8 s, morphine 2 s, NPA 3 s. Moving away, going down, or the casualty being moved
    interrupts it without using the item.
  - Tourniquet: stops all bleeding on that limb below it and adds pain; on a leg you limp.
    A rushed one (1.5 s, or any put on under fire) only stops 70%; a second beside it fixes
    that. Packing the wound with gauze lets you take it off again.
  - Bandages fix venous, muscle and graze wounds; gauze packs junctional bleeds. A vented
    chest seal stops tension pneumothorax from starting (it can't relieve one already
    started). A splint lets you jog on a broken leg and steadies a broken arm.
  - An unconscious casualty's airway can block; an NPA prevents or clears it. A short
    spell out (under 45 s) clears its own airway.
- **Consciousness follows the body (no dice):** you stay out while any cause holds: low
  blood oxygen (SpO2 under 85), pain at the knockout threshold, 40% of your blood lost,
  cardiac arrest, a concussion, morphine sedation, or too many serious wounds at once
  (total trauma). About 10 to 20 s after the last cause clears you come round on your own.
  - **SpO2** (hidden): falls with heavy blood loss, an unsealed chest wound, tension
    pneumothorax, a blocked airway and too much morphine. Your vision greys and closes in;
    a medic checking you sees laboured breathing and blue lips. About 2 minutes under 70%
    stops the heart.
  - **Morphine** is a level in the blood: a dose goes in over 30 s and halves every 12
    minutes, and pain relief follows the level. Two doses are fine, three sedate, five or
    more slow breathing dangerously.
  - **Slow blood recovery** (Captain's stand-in until IV in wave 3): once every bleed has
    stopped, internal ones too, the body makes back 1.5% of its blood a minute, so a
    patched-up casualty past 40% lost comes round after a few minutes. Any bleeding stops it.
  - Check condition shows plain signs: Unresponsive, Breathing laboured, Blue lips,
    Pinpoint pupils (morphine).
- **AI casualty care:** the fire team's medic answers first, then the battle buddy, then
  the other medic ("Moving to Charlie", "Treating Charlie"). Medics put the wounded first
  even in a firefight: smoke between a casualty in the open and the threat, drag to cover,
  massive bleeding first, the rest once in cover; they fight back only at close range, and
  the rest of the squad covers them. Afterwards they stay with an unconscious casualty or
  carry them with the squad until they wake. A wounded squadmate puts its own tourniquet on
  at once and calls "Medic!" for what it can't fix. A responder that can't reach a casualty
  sidesteps and then hands them to someone else.
- **Bodies keep their gear:** every dead player, squadmate and enemy leaves a body where they
  fell with everything still on it; only something carried in both hands drops. Left Ctrl on
  a body: Loot (take one thing), Loot all (what fits; the rest stays on the body), Carry,
  Drag. Bodies and their gear are saved with the zone and appear for late joiners. Past 12
  bodies the oldest goes and its gear drops where it lay.
- **Ammo:** loose 5.56, 7.62x51 and 9mm rounds; magazines weigh what they hold; empties go
  back in the pouch and stack. "Load magazines" on loose rounds (inventory screen) fills that
  calibre's magazines, fullest first, at 5 rounds a second; moving or firing stops it.
- **Coloured smoke:** green, yellow, blue and purple grenades (for the wave 5 supports);
  Shift+G cycles through what you carry. Coloured smoke blocks AI sight like white.
- Tests: medical, casualty (including a two-lap soak and an under-fire engagement) and
  logistics suites, in the default run (12 suites).

#### Changed

- You respawn with an M4, 2 spare magazines and 90 loose rounds, a smoke and a frag. Your
  body stays where you fell with your old gear, and the gear marker floats over it.
- Medics carry a trauma kit and extra tourniquets, gauze, bandages, seals, splints, morphine
  and NPAs; everyone else carries an IFAK.
- A dead squadmate leaves the squad (no slot, no orders, not on the roster) and isn't
  replaced this session.
- Squad AI routes through breached walls: once a gap is big enough to fit through, the
  navigation around it updates within a fraction of a second.
- Enemies and squadmates leave unconscious foes alone, except a dead-check within about 8 m
  while assaulting or searching a position.
- Squadmates pass through each other (no more doorway jams); AI only throws a frag when its
  arc is clear.
- The zone save keeps full number precision, so armor damage comes back exactly.

#### Removed

- **The stopgap revive.** There's no Revive anywhere: casualties come round when their body
  lets them. The 15% wake roll and the morphine overdose dice are gone too.

#### Fixed

- Dead players, squadmates and enemies no longer vanish or scatter their gear on the ground.
  Players joining or changing roles no longer delete dead squadmates' bodies.
- AI medics no longer get stuck behind a player standing on their route.

### Wave 1 of the build plan (phase 3 core)

Built by five agents in parallel and merged on `dev`. See `docs/build_plan.md`.

#### Added

- **Wound model (no more hitpoints):**
  - Hits make wounds on 14 body parts. Arteries and big veins bleed by how close the round
    passed, so a femoral hit takes about 2 to 3 minutes to knock you out.
  - Bones can break: a broken leg means no sprint and walking speed; a broken arm means
    heavy sway and slow reloads.
  - Heart hits stop the heart within seconds, lung hits open the chest (with a chance of
    tension pneumothorax), and a head hit past the helmet is fatal.
  - 6 L of blood. From 15% lost you sway more, recover stamina more slowly and move slower;
    from 30% you can't sprint; at 40% you're unconscious. At 50% the heart stops and a
    10-minute cardiac-arrest window starts.
  - Pain from 0 to 1 can knock you out, more easily the more blood you've lost. Once
    stable you have a chance to wake every 15 s.
  - Blood loss fades and greys your vision, with tunnel vision from 30% lost. Unconscious
    shows a black screen with UNCONSCIOUS or a cardiac-arrest countdown.
  - Frag grenades cause 3 to 8 fragment wounds on exposed parts; walls, other bodies,
    plates, helmets and vests stop them.
  - Target dummy labels show condition, blood %, bleed rate, pain and wound types.
- **Armor ratings:**
  - Rounds and armor share an NIJ-named ladder (IIA to IV): armor stops what it's rated
    for and nothing above it. Light and medium helmets no longer stop rifle rounds; the
    heavy helmet stops rifle rounds up to M855 and 7.62x51 ball.
  - Plates: PE III (light), steel III++ (medium), ceramic IV (heavy); names show the
    rating. Plates only fit the right carrier (PE in the light carrier; steel and ceramic
    in medium and heavy; side plates in heavy), with a message when they don't.
  - Ceramic cracks around each hit; hits near earlier cracks get through more often, and
    enough hits shatter the plate. Cracks stay with the plate and show when inspected.
  - Steel doesn't crack but throws spall at the neck, face and arms; the medium carrier
    covers the neck, the heavy one neck, face and arms.
  - Vests are aramid soft armor that stop pistol rounds and fragments where they cover you,
    even after the plate fails.
  - Stopped rounds still hit: pain, stagger, getting winded, cracked ribs at close range,
    concussions from helmet hits, and rarely a fatal helmet stop from a full-power rifle
    within about 200 m.
  - ACE3-style ballistics: rounds lose energy with range (M855 from far enough away is
    stopped by a light plate).
- **Stances and handling:**
  - X crouch and Z prone (toggles); Caps Lock + W/S steps through three standing and
    three crouching heights and prone; Caps Lock + A/D for side stances.
  - Q/E lean: hold, double-tap to stay, tap to return; leaning stops short of walls.
  - C rests the weapon on a surface for half the sway and recoil until you move.
  - F fire mode: M4 and Mk18 have semi and auto and start on semi.
  - Movement has weight: about 0.3 s to reach a jog or stop, roughly double under a heavy
    load, with momentum into turns and a moment of sway after a hard stop.
  - Sprinting uses stamina (about 15 s from full, less under load). No sprint or jump
    while crouched or prone. Prone is steadiest, then crouched.
  - Hitboxes follow the pose, so crouched and prone soldiers are lower targets.
- **Interaction menus (ACE-style):** hold Left Ctrl for action points on items, downed
  bodies and squadmates within about 3 m; hold Left Ctrl + Left Alt for yourself. Actions:
  pick up, revive, carry (55% speed), drag (35%, the body slides behind you), check
  condition, check your wounds, use medical, put down, drop held item, and give a stowed
  item to a squadmate.
- **Squad roles and fire teams:**
  - Two fire teams of four (A and B), each with a medic. Roles: team leader, medic,
    autorifleman, grenadier, marksman, rifleman, with starting kits for AI squadmates.
  - Pick your role on the main menu; AI fills the rest.
  - Command menu: Target (focus fire), Combat mode (Safe, Aware, Combat, Stealth) and Team
    (fire teams and colour teams). F1-F8 follow squad slots; Shift+F-key adds.
  - Squadmates call out subtitles: contacts with direction and distance, reloading, man
    down, frag out, smoke out, moving and covering. Voice lines play once audio exists in
    `audio/callouts/`.
  - The HUD roster shows fire team, role and colour team.
- **Tests:** new suites `wounds`, `armor`, `movement`, `interaction` and `roles`;
  `tools/run_tests.sh` runs all nine by default.

#### Changed

- E leans right; picking up and reviving moved to the Left Ctrl menu. Ctrl and C no longer
  crouch.
- IFAK and trauma kit are stopgaps until the wave 2 kit: using one stops bleeding wound by
  wound and takes off pain; reviving stops all bleeding, brings blood up to 62% and
  restarts the heart.
- The debug K key costs 24% of your blood and adds pain; two presses knock you out.
- Squadmates no longer fire through you or each other, battle buddies don't move to new
  cover at the same time, and AI aims at your chest wherever your stance puts it.
- Downed bodies get a lying-down movement capsule (they used to block as an invisible
  upright body).

#### Fixed

- `tools/run_tests.sh` exits non-zero when a suite fails.

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
- **Soldier split (build plan wave 0):** `scripts/actors/soldier.gd` is now three parts so
  parallel work doesn't collide: `soldier_movement.gd` (Movement node), `player_input.gd`
  (PlayerInput node: the human driver, camera, view model, HUD) and the body with its
  host-side requests. No behaviour change.
- **Wound-model interface:** everything outside `Vitals` now goes through named calls
  (`server_hit(part, hit)`, `server_impact`, `injury()`, `condition_text()`,
  `seconds_to_death()`, `speed_mult()`, `sway_mult()` and others), backed by HP until the
  wound model replaces it. Hitboxes name their body part in a `body_part` meta (was
  `damage_mult`); `Vitals.net_state` is replicated for the wound model's extra state.
  Squad reports and dummy labels show a condition instead of HP.
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
