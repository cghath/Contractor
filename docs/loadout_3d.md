# 3D loadout editor and 3D armory

Captain, 2026-10-22: the loadout and armory had to be 3D ("we never made it 3d like i told you
to"), "with the option just built in to buy what you do not own", and "saving custom loadouts
and applying them to units". Branch `claude/loadout-3d`. Numbers marked Proposed are calls made
without Captain; change them freely.

## Where it opens

The base screen (base, FOB, LHD: wherever `BaseHub.in_base()`), next to the old loadout menu:
**3D loadout editor** (`BaseHub.open_loadout_3d(fit := "")`, layer 22) and **Armory**
(`BaseHub.open_armory()`, layer 21). Only between deployments, like the loadout menu. The old
paper-doll menu (`LoadoutScreen`) stays for now: it still has give-to-a-squadmate and sell.

## Loadout editor (`scripts/ui/loadout_editor.gd`)

- **Model** (`LoadoutPreview`, `scripts/ui/loadout_preview.gd`): a `SubViewport` with its own
  world holding a `CharacterModel` + `GearRig` + `Inventory`, so the kit is drawn by the field
  code itself (camo, face, build, 0.5 cm voxel art). The look is copied from the person's body
  at the hub when there is one, else from their roster identity. Drag turns, wheel zooms,
  1-5 focus head / torso / legs / weapons / whole body.
- **Slots are markers** projected from the model (`anchors()`): `slot:<slot>`,
  `mount:<slot>:<mount>` (optic, muzzle, underbarrel, side, choke on a gun; `nvg` on a helmet),
  `point:<attach point id>` (every carrier and pack MOLLE point) and `pockets`. The whole-body
  view shows only the main ones; a focused region shows its own.
- **Picker**: every item that fits the picked slot, owned or for sale (`BaseEconomy.item_price`
  > 0), owned first. Unowned rows show their price; picking one fits it in the draft and shows
  a **Buy now: $X** offer (price, cash) that buys one into the stash (`BaseHub` "buy").
- **Draft**: edits are `Loadouts` template edits (`set_slot`, `set_mount`, `set_point`,
  `add_units`, `remove_units`, `fill_ammo`, `medic_kit`) kept on an undo stack (60). The model
  wears the draft as if the stash had all of it (`dressed()`). **Apply** (Enter) sends the
  whole draft (`"loadout"` op `"template"`), which the host cleans
  (`KitLibrary.clean_template`) and rebuilds from the stash with the existing rules
  (`Loadouts.rebuild` / `Restock.build`: litres, kg, bulky items, plates in pockets).
  **Buy missing: $X** (B) sends it with `buy: true`: the host buys the draft's shortfall
  (`KitLibrary.shortfall`) first, or refuses with nothing bought when cash is short.
- **Stats** (`KitLibrary.stats_of`): kg and load tier, litres used of the containers' total,
  each armour piece's NIJ rating (`ArmorRules.rating`), magazines and rounds per gun, speed
  (`MovementRules.load_speed_mult`), a warning when overloaded.
- **Remembered** (`user://loadout_editor.cfg`, per machine): the last person, kit, target and
  focus; **Last applied** (L) restores the last draft applied to that person.

## Saved kits (`scripts/campaign/kit_library.gd`)

- On the roster: `roster.kits = {name: {"template", "by", "role"}}`. The roster is saved with
  the campaign and sent to every peer in the base view, so co-op players share one list.
  At most 40 (Proposed); names up to 32 characters.
- Host ops (`BaseHub.server_loadout`): `kit_save {name, template?}`, `kit_delete {name}`,
  `kit_apply {name, to, buy}`. Targets (`KitLibrary.resolve`): a person, `team:1`/`team:2`
  (the picked squad in fours, Proposed), `role:<role>`, `squad`, `hc:<detachment id>` (Hawk 2,
  Viper 3; men not at the muster line get their roster gear rebuilt). A player never changes
  another player's kit (`may_change_loadout`).
- Applying rebuilds everyone together from one stash pool and makes the kit their standing
  loadout (Restock refills to it). **Buy missing** totals the shortfall over all of them.

## Mounts in templates (`scripts/campaign/gear_mounts.gd`)

Restock templates gain an optional `"mounts": {slot: {mount: id}}` for a gun's muzzle,
underbarrel, side and choke and a helmet's NVG. A slot listed is the whole truth for that holder
(what it leaves out comes off into the stash); a slot not listed keeps what the drawn item
carries, so every template saved before works as it did. `Loadouts.units` counts mounted items,
so the conservation checks see them.

## Armory (`scripts/ui/armory_room.gd`)

- A room with nine shelves in a ring, one per `Loadouts.GROUPS` kind, each item as its own
  voxel model (`ItemArt.ground_node`; plates and helmets as `VoxelArmor`). A shelf shows up to
  40 items (Proposed): owned first, then the cheapest; the search finds any item.
- Point (hover) or click an item: it lights up and the panel shows price (and the quartermaster
  deal, `Quartermaster.seller_text`), owned count, cash, kind and rarity, weight and litres,
  NIJ rating, fire rate and ammo, description and uses. **Buy** (B), **Buy 5** for ammo,
  medical and throwables, **Fit on me** (F).
- Your soldier stands to the right of the view in what you wear; drag an item onto him (or
  Fit on me) to open the loadout editor with it fitted (`LoadoutEditor.fit_item`).
- Look round with drag, A/D, the wheel; 1-9 or the kind buttons turn to a shelf.

## Tests

- `loadout_test`: mounts and points conserve units; kits save, clean, resolve targets and total
  the shortfall; at the hub kit_apply with buy (a dollar short refused, then exactly the
  shortfall bought), the editor's template op with buy; the editor's markers, picker, undo,
  Buy now, Apply, kit save; the armory's shelves, pointing, Buy, Fit on me.
- `base_test`: the armory's buy is the shop's; saved kits survive a save and reload.
- `ui_test`: both screens fit at the ten window sizes and four UI scales.

## Not done yet

- Visual check: no windowed screenshots were taken (Captain games on this PC). Worth a look
  in game: marker placement on the female build, gun rail marker positions, shelf spacing.
- Kits are not yet in the co-op net_test (they ride the roster section, which already syncs).
- Selling and giving to a squadmate stay in the old loadout menu.
