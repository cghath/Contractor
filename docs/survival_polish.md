# Contractor: Fallen — polish: pouches, waiting, worlds, the navmesh, accessibility

Built 2026-10-26 on `claude/survival-polish` (calls 134, 136, 139, 141, 142). Suite `polish`
(`tests/polish_test.gd`), R2708 PASS (polish, survival, loadout, building, ui). Numbers marked Proposed are first guesses for the Captain to tune.

## The 3D loadout editor fills pouches and pockets (call 134)

- **Boxes**: every container things go INTO is a "box", by Inventory's own names: `vest`,
  `pockets`, `backpack` and `molle:<point>` (the pouch on that point). `LoadoutPreview` draws each
  as a small square hotspot beside its slot (a pouch's beside its MOLLE point), labelled with its
  name and fill ("2 of 3", or "1.5 of 6.0 L"); key `box:<container>`, shown when its region is
  focused (torso, legs).
- **LoadoutEditor** (the base's 3D editor): click a box's hotspot (or Open on its row in the
  Carried panel, or "Fill this pouch" on a point holding one): the picker lists what's in it (Take
  out; drag a row onto another box) and what fits it (Inventory.room_for: a mag pouch takes only
  its mags, by units; the carrier, pack and pockets by litres). Pick one, or drag a picker row or a
  held row onto a hotspot, a pouch's point marker or a box row. A refusal says why (Inventory's
  words). The existing slot and MOLLE flow is untouched.
- **The template**: `Loadouts.put_into`, `take_out_of`, `move_between`, `box_items`, `box_count` edit
  the template's `containers` and each point's `held`, which Restock.build already fills into that
  very container, so saved kits (KitLibrary) and Apply fill the same pouches.
- **Companions (call 133)**: the survival gear editor (`LoadoutGear`) maps the same hotspots to its
  places (`box:<c>` <-> `container:<c>`), so dropping on a pouch's hotspot puts it in that pouch.
  Survival saved kits (`CompanionGear.template_of`) also record `into` (container -> {id: count});
  `apply_kit` puts those units back INTO each container (from the giver, or from the target's
  other containers when applying to oneself).

## Wait and pass time (call 136)

- **Where**: home (the settlement's radius, the safehouse mark within 40 m), indoors, or a quiet
  spot: none of the dead within 60 m and the zone's pressure under 25 (Proposed).
- **How**: the ground's contextual menu (in a survival world) offers Wait an hour, Wait until dusk
  (19:00), Wait until dawn (06:00); the settlement screen's buttons as before. The body and (when
  every survivor sleeps or waits) the world run at SurvivalSleep.SPEED (x12) through sleep's tick
  path, without sleep's restore; needs still run. A short fade on the HUD, and "You waited until
  dusk (19:00)".
- **Interrupted** by one of the dead chasing within 60 m or any in sight within 30 m, a horde in
  the crowd within 120 m, a noise (the zone's pressure up 10 since he sat down), a world event
  starting in the zone (`SurvivalSleep.server_interrupt_waits` from `WorldEvents.begin`), moving off
  the spot or going down (all Proposed).
- **Companions** within 30 m wait with him (their bodies at speed, no looting or plans: no
  wandering) and stop with him.
- **Co-op**: the world only speeds up when every player sleeps or waits (the ready-up); the
  others are told "<name> wants to wait until dusk: wait too to pass the time".

## Continue's world list (call 139)

- `Survival.worlds()` reads every `survival_<id>.json` save: name, day, season (by its start
  season), the survivor's name and generation, last played (the file's time, local). Newest first.
- `WorldListScreen` (the menu's "Survival: continue"): a row per world, Continue or Put away
  (confirm). Put away (`Survival.archive_world`) moves the world's save and its zone saves (with
  backups) into `user://saves/archive-<date>/`, as the campaign's reset does: nothing is deleted.
- New world warns under the name when a saved world has it already (Start would start it over).
- `Menu.host_survival_continue(id := "")` is still the newest-world path for tests.

## Builds and the navmesh (call 141)

See docs/survival_building.md, "Navigation round builds": built blocks are baked into the zone
navigation's chunks from Builder's records, solid pieces join NavBuilder's obstacles, a change
rebakes the touched chunks after 0.25 s (batched), the dead re-ask their path when the map changes.

## Accessibility (call 142)

The options screen's **Accessibility** tab (GameSettings section `access`):
- **Colour-blind-safe tells** (`colour_safe`, off by default): the noise ring sky blue and dashed
  (4 dashes for a whisper to 12 for a shout), the eye orange with brackets round it, the load tiers
  blue to vermillion with a mark each (● light, ▲ burdened, ■ overloaded, ✖ critical) on the
  inventory's mass line and the loadout editor's Weight. Okabe-Ito palette (Proposed).
- **Text size** (`text_scale`, 80% to 150%): every font size in the shared theme times this (the
  menus built on UiKit and the HUD's labels), on top of the Menu and HUD size.
- **Tension audio**: FallenAudio's own `tension_on` (the drone and heartbeat muted at once; the
  music moments stay).
- **Subtitles** (`subtitles`, on): the bottom line of barks and voice lines, "Name: line".
- The survival screens (New world, Continue, the Accessibility tab) are checked at the 10 window
  sizes at text 100% and 150% (polish suite).

## Left out

- A chair piece to wait on (there's no chair yet); waiting isn't on a key of its own.
- The base editor's box flow works on the template: a pouch the template hasn't placed on a point
  yet (a "+" key) shows no box until Apply.
- The text scale doesn't reach hand-drawn readouts (the markers' labels, the medical diagram).
- Blasts carving builds' voxels don't rebake the navigation until a block is cleared or falls.
