# Visible wounds and blood (claude/wounds-blood, 2026-10-26)

The Captain: "i want the visible wounds to get better and blood to stop floating too", and later:
blood that drips onto helmets and backpacks should "stain those items if they can be stained"
instead of floating or stacking on them.

## The Captain's calls (2026-10-26)

- Soak: spreads with the blood lost at the wound, and uncapped: a big bleed soaks on into the next
  part (thigh to shin, chest to belly). Blood still drips to the ground as before (reworked below).
- Bruising: from closed breaks and round holes, and from armour stops (plate and helmet).
- Detail range: 40 m. Past it the coarse blood voxels stand in (to 80 m).
- Reduced gore: holes smaller, no torn flesh or cloth, trails shorter.

## How it works (the Captain, 2026-10-27: "more realistic in how it works"; all four picked)

- **Gravity as he lies.** Each hole's blood runs the way down is now. When that turns more than
  35 degrees (he falls, is laid down, carried), a new run starts from the hole and the old one
  stays where it ran; 3 runs a hole at most (the first and the latest kept). The soak sags toward
  the low side as it is now.
- **Arterial spurts.** Arterial and junctional bleeds (not under a tourniquet) spurt with the
  heartbeat: 4 drops a beat out along the skin's outward line, as fast as 3 m/s at full blood,
  weaker as blood is lost (none under 40%), none once the heart stops. Drips leave from where
  the blood gets to lowest (the ends of the runs, the low edge of the soak), not the hole.
- **Cloth wicking.** Darkest where it's soaked through, lighter at the ragged wet edge; a soak
  reaches past the belt, knee pads or boot tops only a third as far. Bare skin doesn't soak:
  blood on it stays close to the wound and runs (the whole head counts as bare).
- **Blood through dressings.** A dressing over a wound still bleeding under it (a bandaged
  muscle wound over a vein it doesn't hold, a tourniquet's trickle) reddens from the middle out
  with the blood through it, wet while it comes; one put on a wound that had bled 30 mL or more
  shows dried blood at its edges.
- **Bruises** are a darker, redder skin that greys a little with age ("too purple" before), a
  small ring right round a hole and over closed breaks, and where armour stopped a round.

## What draws what

| What | Where | How |
|---|---|---|
| Hole core, torn cloth / raw rim, trail, soak, bruises | `WoundSkin` (new) | The part's own mesh drawn again (`WoundSkin` child of the mesh) by a shader that recolours whole 0.5 cm voxels and discards the rest. Cannot float: it is the body's surface. Per mesh: 8 spots, 6 bruises. Within 40 m. |
| Coarse holes and blood, 40-80 m | `WoundMarks` "WoundMark" | MultiMesh on the bone, widened with the build (`fit_of`). |
| Dressings | `WoundMarks` "WoundDressing" | MultiMesh on the bone; seals and trunk pads laid onto the skin cell by cell (`_conform`), limb dressings wrapped round the limb. |
| Devices | `BodyDevices` | Unchanged look; widened with the build. |
| Blood on people, gear, items | `BloodStain` (new) | The thing's mesh drawn again, its voxels under where drops fell recoloured (faces that look up the way the drop fell, in an 8 cm column under the hit, since colliders stand off the mesh). Wet red, drying brown, gone after 7 min. 12 stains a mesh, 24 things a bleeder. |
| Pools, specks, smears, brain | `WoundMarks` | On the ground under each cell's middle, tilted to it. |
| Bruises from armour stops | `Vitals._bruise` | Gore record `{"k": "b", "p", "a" (rest-pose skin point), "s"}`: replicated, saved and late-joined with the gore list; 10 at most, a stop within 6 cm deepening one. Shows on bare skin only (face, hands; the torso's uniform covers plate bruises). |

## Floating blood: causes found and fixed (a test each, `tests/blood_test.gd`)

1. **Build width.** `CharacterModel._apply_girth` widens each part's mesh (slim 0.95, broad 1.07
   on the trunk), not the marks on the bone: up to ~1 cm off a slim chest, sunk into a broad one.
   Marks, dressings, devices, hand blood and drip starts now go through `WoundMarks.fit_of`.
2. **Flat dressings on a curve.** The chest seal (10.5 cm square) and trunk pads were flat planes;
   their edges stood off the chest. Each cell now sits on the skin under it.
3. **Hand blood on the wrong hand shape.** Laid on the relaxed hand's model; a gripping hand moved
   away from it. Now laid on the model the hand is drawn with (`BodyVolume.surface(..., model)`),
   redrawn when the pose changes. Cells are flat (0.4 cm), not cubes.
4. **Pools on slopes.** Flat cells at the drop's height, not the cell's: edges floated on a
   slope. Each cell now lies on the ground under its middle, tilted to its normal (smears and
   brain too).
5. **Drops off a ledge.** A drop's floor was found under where it started; one that flew off a
   shelf, roof or truck bed "landed" at that height in the air. It now looks again and falls on
   (or goes if there is no ground at all).
6. **Ground going from under it.** A crate, door or terrain blown away left the pool hanging.
   `_settle` re-checks 48 cells a body every 10 s: moved ground, the blood lies on the new ground
   (within 1 m); gone, the blood goes.
7. **Drops on people and gear.** Landed as flat cells at the hitbox's or collider's box surface
   (centimetres off the person), stacking on helmets and packs. Now a `BloodStain` in the
   gear's or body's own voxels; a drop that meets something with no mesh falls on past it.

Checked and not a cause: marks on a body posing, lying, carried or ragdolled (they ride the
bones; the ragdoll drives the same bones); marks past a cut (already dropped).

## Perf

- Painted skin: one extra draw of each wounded part's mesh within 40 m (`visibility_range_end`,
  capped by the part's own fine-LOD range), no shadows; uniforms updated at most every 0.3 s while
  bleeding and every 10 s while drying.
- Coarse marks only between 40 m and 80 m.
- Stains: one extra draw per stained mesh within 40 m; capped as above.
- Settling: 48 rays a body every 10 s.
- Cosmetic dice (drips, spurts, splashes) use WoundMarks' own RNG, never the global one the game's
  dice may be seeded from (the spurts shifted the wounds suite's seeded fragment rolls).
- Measured (local, locked runner): R2814 at a703aac9, perfcases fight 24.3 / 40.9 ms average / 95th,
  woods 10.7 / 21.0, drive 14.1 / 22.6, heli 18.5 / 33.0, all inside budget. R2810 (the same cases
  over budget, woods 31.7 ms) ran beside another session's perfcases; these cases vary 6-52 ms run
  to run on this machine.

## Tests

`tests/blood_test.gd` (new suite "blood", in tools/run_tests.sh and CI): one check per floating
cause above, the painted look, face, bruises, reduced gore, and the four realism behaviours.
`devices_test` also checks every drag-smear streak lies on the ground; `wounds_test`'s dummy has a
floor now (its pool was 2.5 m below it in the air, which the old code allowed).
Last full local run: R2810 (smoke, blood, devices, gore, armor, interaction, net, medical,
casualty green) and R2814 (wounds, blood, devices, perfcases green).

## Hooks for model-realism (not edited here)

`character_model.gd` and `gear_rig.gd` are owned by the model-realism branch. This branch reads
from them only:

- `fit_of` reads the part mesh's `base` meta (`_apply_girth`). If proportions change by another
  route (scaling the mesh without `base`), the marks need the same mapping: keep `base` = the
  unwidened `[position, scale]` of each part's mesh.
- `WoundSkin` paints the part's first `MeshInstance3D` child and, on the head, its `Face_*`
  children. A first-person body or new clothing meshes on the bones will need the same (a
  `WoundSkin` per mesh) to show wounds; clothing that covers the skin will hide the paint under it.
- Gear meshes take `BloodStain`s as they are; nothing needed from `gear_rig`. A torn hole in a
  plate carrier over a chest wound would need gear_rig's help (not done).
