# Animation: locomotion, first person, world scale

Procedural, in code (`scripts/player/character_model.gd`), for every Soldier: player, squad
AI and enemies alike. Speed and direction come from the body's own movement (position change,
in the model's space), so remote and AI bodies animate the same as the local one.

## Gait cycles (third person)

| Cycle | When | Ground speed |
|---|---|---|
| idle | still (below ~0.1 m/s; the stance pose with breathing) | 0 |
| walk | standing, below `JOG_AT` | ADS move 2.4 m/s, slow paces |
| jog | standing, `JOG_AT`..`SPRINT_AT` (2-5 m/s) | stand 4.0 (`WALK_SPEED`), low stands 3.0-3.5 |
| sprint | standing, from 5 m/s | 6.5 (`SPRINT_SPEED`) |
| crouch_walk | hips below `CROUCH_GAIT_HIP` (0.65 m) | crouch 1.6-2.4 |
| crawl | prone | 0.8 |

Tables by speed (`GAIT_*`, anchors 0 / 1.4 / 2.5 / 4.0 / 6.5 m/s, blended between):

- cadence 0.9 / 1.0 / 1.25 / 1.42 / 1.6 cycles/s (two steps a cycle), raised where needed so the
  legs reach (`gait_hz`): in practice ~1.13 at a walk, ~1.45 at 4 m/s, ~1.62 at a sprint;
- duty (share of a cycle a foot is down) 0.55 / 0.5 / 0.36 / 0.26 / 0.2: double support walking,
  a flight phase running;
- hip drop 0 / 6 / 7 / 8 / 10 cm (soft knees), swing-foot lift 6-32 cm, lean 0-0.2 rad,
  free-arm swing 0.15-0.85 rad; hip bob 1.2 cm walking (up over the planted leg) to 3.2 cm
  sprinting (down onto it).

**Feet don't slide**: a planted foot moves back under the hips at exactly the ground speed
(stride while down = duty x speed / cadence), solved with two-bone IK to the ground, so it stays
where it landed. Strafing turns the legs half way towards the movement (`GAIT_HIP_TURN`), the
upper body keeps facing the aim; backwards runs the same cycle in reverse. The cycle fades in
over 0.1-0.5 m/s on top of the stance pose, so stance changes and stops blend.

Cost: no allocations in the cycle; level of detail draws a body every 2nd frame past 30 m and
every 4th past 70 m or behind the view (`LOD_*`), with the elapsed time so cycles keep pace.

## First person (`scripts/actors/player_input.gd`)

In step with the drawn legs: the view rides half the hips' bob plus 0.8 cm side sway at a
sprint (**Head bob** toggle in Settings > Video, on by default); the weapon bobs up to 1.2 cm;
sprinting brings it down and across (`SPRINT_VIEW`, `SPRINT_TILT`). None of it while aiming.

## World scale

| | Before | After | Real |
|---|---|---|---|
| Standing eye (male model 1.76 m to the top of the head) | 1.65 m (94%) | same | ~93% of stature |
| Female eye (model 1.64 m) | 1.65 m (camera near the top of her head) | 1.53 m (scaled with her) | ~1.51 m |
| Crouched / prone eye | 1.00 / 0.27 m | same | |
| Doors | 2.1 x 1.1 m | same | 2.03-2.1 m |
| Field of view | camera `fov` 80, **vertical** (Godot keeps height): ~112 deg across 16:9 | setting is **horizontal at 16:9**, default 90 (= 58.7 vertical); Hor+ on wider screens | |

The eye height, doors and body were fine; the view was the problem: 112 deg across shrinks
everything and makes every pace look fast. The setting has a new key (`hfov`, 70-120) so an
old saved vertical 80 doesn't carry over as 80 across. Weapons' `ads_fov` and the optics'
magnification rule are unchanged (vertical camera degrees; magnification is against the
player's unaimed view), so iron sights now zoom ~1.2x instead of ~1.6x.

Tests: `tests/animations_test.gd` "World scale" and "Locomotion" (every pace, stance and
direction: the cycle shown, and the most a planted foot moves, under 1 cm measured).
