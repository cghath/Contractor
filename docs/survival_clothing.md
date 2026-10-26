# Contractor: Fallen: clothing, the gear editor, third person

Calls 132-135 (docs/survival.md), branch `claude/survival-clothing`. Numbers marked Proposed are
calls made without the Captain; change them freely.

## Clothing slots and layers (call 132): `scripts/survival/clothing.gd`

- **Slots**: `Inventory.CLOTHING_SLOTS` = head, face, torso_base, torso_mid, torso_outer, hands,
  legs, feet, kept apart from `Inventory.SLOTS` so the campaign's code that walks SLOTS is
  unchanged; `Inventory.all_slots()` is both (saves, strip, mass, snapshots, `Survival.kit_of`).
- **Items**: type "clothing" with stats `layer` (the slot), `warmth` (0..1), `wet_resist` (0..1
  shed), `noise` (step-noise multiplier), `camo` (woodland, desert, snow, urban, dark, plain,
  bright), `pockets` (litres), `durability` (for the wear lane, call 122), `colour`. 25 items, from
  a T-shirt to a winter parka. The four older warm items (tactical gloves, balaclava, shemagh, the
  enclave uniform) keep their type and gain a layer: worn they still count (`count_of` counts
  worn clothes, `remove_one` takes them off), so the enclave disguise and the frost checks work.
- **Wearing**: in a survival world (`Clothing.enabled()`: `Survival.running`, or `force` in
  tests) a clothing item picked up goes on when its slot is free; elsewhere it's only carried.
  The gear editor puts it on explicitly.
- **Warmth**: the sum of what's worn, a wet layer keeping 30% of its own (WET_WARMTH_LOSS 0.7,
  Proposed), at most `BodySeason.CLOTHING_MAX`. `Needs.context_of` passes `clothing`, `layers`
  and `fire`; only worn clothes count now (no more "carried counts as worn").
- **Wetness per layer** (in the body's dictionary, `layer_wet`): rain soaks the outer torso layer
  first; what a layer sheds (`wet_resist`) runs off, what it can't hold goes in to the next, then
  the skin (`wet`, the old value). Out of the rain every layer dries at Needs.WET_DRY_H an hour,
  x1.5 indoors, x6 by a fire (a built stove or a campfire within 3 m; Proposed). Wading soaks all.
- **Noise**: `Clothing.noise_mult(s)` in `Survival._footsteps` (a rain jacket x1.35, sneakers x0.85).
- **Camouflage**: `Clothing.camo_mult(s, terrain, night)` for the living's sight (not yet read):
  a matching top or legs x0.8 each, bright x1.25, dark at night x0.9 (Proposed).
- **Pockets**: the clothes' `pockets` add to the pockets container; a garment whose pockets hold
  what the rest can't won't come off until they're emptied.
- **Starting clothes**: a T-shirt, a shirt/hoodie/denim jacket, jeans or cargo trousers, sneakers
  or boots by the survivor's seed (`Clothing.STARTER`); companions and lone survivors with none
  get a set when their body is made (`SurvivorsLayer._dress`).
- **Loot**: rows in the home, barracks and stores tables by rarity, and a "clothes" table and
  pool (`Clothing.roll_find`) for the dead's dress lane. A winter parka, trapper hat and snow
  pants are rare.
- **Drawn**: `ClothingArt` (GearRig): the outer torso layer as a shell (no carrier) or its hem
  and collar (under a carrier), a hat (not under a helmet), a face band; flat colours, Proposed.

## The gear editor (calls 133-134): `scripts/ui/loadout_gear.gd`, `scripts/survival/companion_gear.gd`

- **Opens** from a companion's talk menu ("Gear", looking at them within 3 m), or on yourself
  (`LoadoutGear.open_on(player, player)`; the person picker switches between you and companions
  within reach). Same idea as the base's 3D loadout editor: their body in 3D (`LoadoutPreview`
  with `clothing = true`, clothing slots marked), their kit place by place, your kit, and their
  needs, mood, clothes and warmth (`CompanionGear.info_of`, sent by the host).
- **Places**: every body slot (gear and clothes), every MOLLE point, and the containers things go
  INTO: pockets, vest, backpack and each pouch (`molle:<point>`) with litres or units used.
  Pick one (header or marker), then Give (yours), Move (theirs) or Take; or drag a row onto a
  place or a marker. One unit at a time.
- **Host** (`CompanionGear.server_op`, via `SurvivorsLayer.request_talk("gear")`): give, take,
  move, kit_save, kit_apply, info. Inventory's own rules decide (`room_for`, `attach_problem`,
  `fit_problem`); a refused move goes back where it was and the actor is told why. The
  companion's record keeps up (`rec.kit`).
- **Saved kits**: the world's `gear_kits` (name -> worn slots, points, carried counts), at most
  30 (Proposed). Applying moves what the kit needs from the giver's stowed kit; what the target
  wore in those slots goes back to the giver; what's missing is named.

## Third person on foot (call 135): `scripts/vehicles/vehicle_camera.gd`

- In a survival zone, B (the vehicle view key) toggles it on foot; B also raises binoculars, so
  with binoculars carried it's Shift+B (Proposed). The camera hangs 2.4 m behind the eye and
  0.55 m to the shoulder (left for the left-handed), pulled in by walls like the vehicle arm.
- Aiming, binoculars and being down give first person back while they last; the rays (fire,
  interaction, melee) still come from the eye, the HUD is unchanged. Your own body is drawn; the
  first-person gun isn't (its layer left out).

## Left out

- Clothing wear and repair (call 122: `durability` is there, nothing wears yet), boots wearing
  out the feet; the living's sight reading `camo_mult`; voxel art for the clothes.
- Saved kits and companions' needs on a co-op client come from the host (info is sent; the kit
  list is the host's).
- No key opens the gear editor on yourself yet (the companion editor's person picker does).
