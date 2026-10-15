# Loadout menu (FOB)

Captain, 2026-10-14: "we need a menu for equipping yourself better and your squadmates how you
want to as well". Today kitting up is by hand (pick world items up in the armory, Give item to a
squadmate at the muster line) plus "Restock last loadout". The loadout menu does it from one
screen, out of the same stash.

## Screen

`LoadoutScreen` (scripts/campaign/loadout_screen.gd), its own full-window layer (not the fixed
980x640 base screen), opened from the Ops desk's squad page ("Loadouts"), the armory page and
the inventory screen at the base (next to Restock). Esc or Close shuts it. Three columns that
share the window and scroll on their own, so it fits 1280x720 to 3840x2160 at UI scale 0.75 to
1.5 (checked headless in the loadout suite):

- **People** (left): you, the other players (view only), and the squad picked for the next
  deployment (everyone at the muster line if nobody is picked). Each shows role, load and
  load tier, and a "short" mark if their last restock left them short.
- **Paper doll** (middle) for the one selected:
  - worn: primary and sidearm (with optic), launcher, helmet, carrier and its plate pockets,
    pack; each with a picker of what the stash has that goes there (or "none": back to stash);
  - optic picker on rail guns;
  - carried, grouped: ammo and mags, medical, grenades, pouches, other; counts, with "-1"
    (back to the stash) and "Give 1 to..." (another person);
  - load in kg and its movement tier (MovementRules), and what the last change was short of;
  - helpers: Fill ammo, Medic kit, Role kit (role picker), Copy kit from (person picker);
  - standing loadout: Save as standing, Standing = role kit, Copy standing to squad, Restock to
    standing; the standing loadout's item count and its shortfall.
- **Stash** (right): what the armory holds by group, counts, "+1" / "+5" onto the selected person.

## How a change is made (host)

Every gear change is a loadout template edit (Restock's format: slots, optics, MOLLE points
with what they hold, containers), rebuilt from the stash by `Restock.build`: the person's kit
goes into the pool with the stash first, the edited template is drawn from it, the rest is the
stash. So nothing is ever made or lost, what's missing is listed in Restock's words ("Missing
from the stash: ...", "No room for: ..."), and the armory's world items follow through
`BaseHub._apply_stash`. The person's own carrier, pack and pouches go into the pool unpacked (loose), so a rebuild
that draws another carrier still finds their own meds and mags (R0976). A side effect worth knowing: the rebuild draws the best units (full
mags, undamaged plates, full kits), so a change also tops up partly used mags from the stash.

`Loadouts` (scripts/campaign/loadouts.gd) holds the pure template edits (set slot, set optic,
add/remove units, fill ammo, medic kit, role kit) and `rebuild` over several people at once
(give = one person's template minus, another's plus, one pool).

## Network

Client asks, host applies (BaseHub.request): `request("loadout", [who, op, params])`.
`who` is a member id or `player:<key>`. A player may change their own kit and any AI squadmate's,
never another player's (they can give to another player). Ops: `slot`, `optic`, `add`,
`remove`, `give`, `fill_ammo`, `medic_kit`, `role_kit`, `copy_kit`, `save`, `standing_role`,
`copy_standing`, `restock`, `sync` (read the muster line's gear into the roster for the view).
The answer comes back as the usual note; the roster and stash broadcast with the view.

Buying (2026-10-15): an edit the stash can't fill writes `edit_missing` on the roster entry; the
Kit column then shows "Buy missing (N items, $X)" (and one button per item), disabled with the
reason when cash is short. Op `buy_missing` [params `id` optional] buys at shop prices through
Economy.server_buy and redoes the edit. The armory lays the stash out in category bands
(BaseArmory.BANDS); deliveries and returns take the next free slot of their band.

## Numbers (Proposed)

- Fill ammo: each gun's magazines up to the role kit's count for that magazine, else 6 for a
  primary, 2 for a sidearm (Proposed). Launcher rounds are phase 2.
- Medic kit: the medic role kit's medical items, aid bag and sustainment pouch, up to its counts.
- Stash "+5" for ammo and medical (Proposed).

## Phases

**Phase 1 (MVP, built):** the screen above; weapons, optics, helmet, carrier, plates, pack,
mags/ammo, medical, grenades; give between people; Fill ammo, Medic kit, Role kit, Copy kit;
standing loadout save / role preset / copy / restock; stash accounting and shortfall text; the
fit check; the loadout suite (conservation, save then restock, client through the host, role
preset within stock).

**Phase 2:**
- Drag and drop between the doll, the stash and other people; hover compare (weight, armour).
- Per-pouch layout editing: which pouch on which MOLLE point, what goes in which pouch, pack
  contents by container (today a rebuild places them as Restock does).
- Loading loose rounds into mags from the stash ("fill mags" with loose rounds), not just
  swapping for full ones.
- A bindable key (Controls) to open it at the base; gamepad focus order.
- Launcher rounds in Fill ammo; a "Wear" for an optic onto the sidearm or a second rifle
  (Mount goes on the primary).
- Keep item condition on a change (today the best unit is drawn, so a damaged plate is swapped
  for a good one when the stash has one).
- Named loadout presets per company (beyond roles), a squad-wide "fill everyone" pass with the
  medic-first fair shares Restock squad uses.
