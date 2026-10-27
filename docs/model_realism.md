# Model realism pass (2026-10-26)

Captain asked for soldiers that look more realistic in their armour and kit, staying voxel
("stay voxel, more detail"). In his order: armour that reads as built gear, not boxes stuck on;
body proportions (male and female); clothing and camo; and the loadout showing on the model.
Branch `claude/model-realism`, off `dev`.

## Captain's calls (asked 2026-10-26)

| Question | His call |
|---|---|
| Carrier camo | Carrier in the uniform's camo, pouches solid |
| Build | "Fit operator", and for women "a more female profile ... something that tracks for strong women that work out" |
| Loadout | Pouches show their contents, plus a battle belt; "ear pro is wearable" |
| Helmet | High-cut with kit |

Mid-pass corrections: "pretty much all characters are round at the waist" (fixed, see Body), and
two dismemberment bugs (see the last section).

## How to look at the models without a window

`tools/model_render.tscn` draws soldiers headless into PNG sheets (front, three-quarter, side,
back, orthographic, flat-lit from the vertex colours), so no window opens. Keep its output as an
S run (docs/debugging.md):

```
<voxel godot> --headless --path . res://tools/model_render.tscn -- <out folder> [px per m] [names...] [crop=<lo>,<hi>]
```

Soldiers: `uniform_m`, `uniform_f` (no kit), `rifleman_m`, `rifleman_f`, `medic_m` (woodland),
`leader_f` (desert), `gunner_m` (black), `headset_m` (woodland, ComTac, sidearm, no helmet).

- Before: **S2740** (dev at `1aa38406`).
- Passes: S2741 (armour), S2742 (body), S2750 (all), S2752 (close-ups); the final sheets are
  listed at the end.

## Before and after

### 1. Armour

Before: the carrier was one flat coyote or olive colour, with MOLLE as flat paint lines and
plate pockets as slabs. From the side it read as a box. The helmet was a dome with paint-line
rails.

After:
- **Camo carrier, solid pouches.** Pocket panels, cummerbund and shoulder pads are printed in the
  uniform's camo (`VoxelArt._vest`, `C.CAMO`). Plates show the pocket's camo through the window
  (`VoxelArmor.camo_cloth`, `GearRig._rebuild` → `set_camo`). Cloth takes the pattern's own
  colours; painted steel stays a shade darker. Pouches, straps and binding stay solid.
- **Built, not boxed.** Padded pocket edges (a softer bevel), bound side and bottom edges, PALS
  webbing standing 0.5 cm proud and bar-tacked into loops every 4 cm, top binding and tuck seams
  where the cummerbund goes under the front panel, quick-release buckles on the shoulder pads, and
  zips on the back panel. The geometry the pouches fit to (pocket faces, cummerbund) is unchanged,
  so `armor`'s gear-fit checks hold.
- **High-cut helmet** (medium shells, no face guard; `VoxelArmor._helmet_shape`, `HIGH_CUT`):
  the sides arch up over the ears. The rails run along the cut's top, and the NVG shroud is a
  little wider. `GearRig._helmet_kit` adds Velcro panels on the sides and a counterweight pouch
  low on the back, as small gear. Helmets marked `faction_color` wear a camo cover in the side's
  scheme; the LX-3's face guard stays bare.

### 2. Body proportions

Joints, pivots and hitboxes did not move. Only the shapes inside them changed, and the hit shape
(BodyVolume) follows the drawn voxels as before.

Before: a box tunic ended in a flat hem over the hips and legs. The shoulders were a square shelf
with a short drop to a thin 11 cm neck. The forearms were cones, and there was no calf.

After (male, "fit operator"):
- The trunk narrows into a crotch between the legs, so trousers read as trousers. The pelvis is
  flat in front and as wide as the thighs' tops. (Captain's "round at the waist": the first cut
  bulged below the belt; fixed.)
- A trim waist at the belt, lats flaring to the chest, round deltoids over the shoulder joints,
  and traps sloping up into a thicker neck (12.4 cm, `FaceArt`) with a stand-up shirt collar
  (`VoxelArt._collar`; the torso frame grows to 70 cm, joints unchanged).
- Upper arms have a deltoid cap and biceps. Forearms are full below the elbow and slim at the
  wrist. Quads are fuller over the knee, and there is a calf behind the shin (`VoxelArt.calf`, in
  `Feet` shins too).

After (female, a strong woman who trains; `FEMALE_SCALE` and `FEMALE_SHOULDER` unchanged):
- The crotch is shaped the same way. Her hips are as wide as her thighs' tops (no ledge), over a
  trim waist, with athletic glutes behind and a flat front below the belt.
- A broader back and lats up to round, defined deltoids, the shoulder line sloping into a firmer
  10 cm neck, and toned arms, quads and calves. Her bust (and how a carrier holds it) is as before.

### 3. Clothing and camo

Before: a flat camo shell. Pockets and knee pads were painted rectangles; the knee pads were
black 10 cm blocks.

After (all paint seams use the scheme's own colours, so no new palette entries; plain clothes stay
plain):
- Shirt: a buttoned placket, chest pocket flaps and sides, the collar, and belt loops. Trousers
  have a fly.
- Sleeves: seams round the shoulder pocket's Velcro patch, an elbow crease, a fold of bunched
  sleeve below the elbow, and a cuff lip over the glove.
- Trousers: bellows cargo pockets standing off the leg with a flap edge and a seam, plus the boot
  blousing that was already there.
- Knee pads: rounded hard caps over the knee with a strap round the back of the leg
  (`VoxelArt.knee_pad`), the top on the thigh.
- Camo is still worked out per part in centimetres, so its scale matches across parts and the
  carrier.

### 4. Loadout on the model

Before: every pouch was a box with a flap. A pouch with anything in it showed only a radio's
antenna or an IFAK's tabs.

After:
- **Mag pouches** (`GearRig.mag_pouch_parts`) are open-topped. Each cell shows a mag's top for
  every mag held, with brass showing when it's loaded and a pull tab over it. An empty cell is a
  dark mouth. Pouches redraw as mags come and go (`_pouch_key` counts units). Everything stays
  inside the pouch's own box, so the carrier fit is unchanged.
- **Radio**: the antenna plus the handset cable up to a push-to-talk.
- **IFAK, tourniquet, aid bag**: as before (red tabs, the TQ showing, the cross).
- **Battle belt** (`VoxelArt._battle_belt`, `GearRig._set_belt`): worn by anyone in uniform
  carrying a gun, carrier or not. A padded belt round the hips fitted to the body (and his build),
  webbing, a cobra buckle, a double pistol mag pouch on the support side (with a sidearm; its mags
  show), and a rolled dump pouch behind.
- **Ear pro is wearable** (`GearRig._set_ear_pro`): a ComTac, Sordin or electronic ear pro
  carried is worn, with cups on the ears (the ComTac with its mic stub). With no helmet the band
  goes over the head; under a high-cut helmet the cups sit by the rails. None is drawn under a
  heavy helmet's ear covers or the LX-3. It still works from anywhere in the kit, as before.
- The pack and the plates show as before (plates now in the pocket's camo).

### Perf

The new parts are small gear (`_small_detail`: no shadow, gone past `SMALL_GEAR_M`): the helmet
kit, mag tops, belt and its pouches, and ear pro. The camo carrier is still one mesh per scheme
and tier. The body parts keep their mesh count; their rasters grew by the collar and calves only.
`perfcases`: see the run below.

## Dismemberment fixes (Captain, 2026-10-26)

1. **"The neck stays where it was."** The neck's stump is drawn on the head's bone. After a head
   cut, the ragdoll held that bone frozen where the head had been, so the stump hung in the air
   while the body flew off. `Ragdoll._bones` now puts the cut head's bone on the torso's collar
   (`HEAD_PIVOT`), on the host and on every client (ragdoll_net). A pulped head (a launcher's
   direct hit: no piece flies) now hides its face too (`BodyDeform._done_work` →
   `FaceRig.head_severed(null)`), so no eyes or mouth float over the stump.
2. **"Arms and legs don't show they were blown off" by an RPG or AT4.** Three causes:
   - A man next to the burst was still alive when the gore was decided, so the rule for the living
     (only a shin or forearm, never the head) applied.
   - The sever reach was a grenade's: about 0.5 m even for a 1 kg PG-7V.
   - A dud (inside arming distance) hit with no energy, so it never tore anything.

   Now a warhead filling of `GIB_DIRECT_KG` or more kills outright when a limb is in reach and uses
   `HEAVY_SEVER_Z` 0.9 and `HEAVY_GIB_Z` 0.75 (Proposed). Grenades keep their old numbers. A dud
   carries its rocket's ½mv², so it tears what it hits past `Vitals.LETHAL_J`. `gore` checks both:
   the stump on the collar with no face left, and a PG-7V 0.8 m from a living man.

## Tests

Listed in the commit messages and below as they run.
