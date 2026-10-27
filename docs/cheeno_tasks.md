# Cheeno's tasks (cghath): models, wounds and dismemberment

What's on Cheeno's plate, and what other sessions have taken in those areas, so nobody builds
the same thing twice.

## Taken by other sessions

- **Model realism pass (taken 2026-10-26, branch `claude/model-realism`).** Soldier models in
  their armour and kit: plate carriers, plates and helmets, body proportions (male and female),
  clothing and camo, and loadout on the model. Please stay off these until it lands on dev:
  `scripts/art/voxel_art.gd` (body parts, `_vest`, belt), `scripts/combat/gear_rig.gd`,
  `scripts/combat/voxel_armor.gd` (helmet shape, camo covers), `scripts/player/feet.gd` (calf,
  knee pads), and the neck in `scripts/art/face_art.gd`. Notes: [model_realism.md](model_realism.md).
  The same branch also fixes two dismemberment bugs Captain reported on 2026-10-26 (the neck left
  standing after a decapitation, and limbs not coming off to RPG/AT4 hits); see that doc for the
  files touched.
