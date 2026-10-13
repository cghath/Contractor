class_name Spotting
extends RefCounted
## AI spotting (Captain, P0164 queue 17, part 1): awareness of an enemy builds over time while
## they're in sight, instead of every line of sight being an instant target. How long a full
## spot takes grows with distance and shrinks with what gives the target away; below full
## awareness the AI only suspects something is there (SquadAI looks, a hostile goes to search).
## Every number is proposed, for Captain's playtests.
##
##   seconds to spot = (BASE_S + distance / METRES_PER_S)
##       x stance (standing 1, crouched, prone) x movement (still 1, walking, running)
##       x camo against the zone's terrain (CAMO) x observer (suppressed, looking elsewhere)
##       x skill (an unskilled soldier takes longer)
##   fired in the last FLASH_S: x FLASH (a suppressor gives away less: SUPPRESSED_FLASH)
##   closer than POINT_BLANK_M and in front: at once.
## Not seen, awareness fades over FADE_S. Vegetation, hearing and binoculars come later.

const BASE_S := 0.4
const METRES_PER_S := 50.0
const CROUCHED := 1.6
const PRONE := 2.5
const WALKING := 0.75
const RUNNING := 0.5
const WALK_MPS := 0.5
const RUN_MPS := 3.0
const SUPPRESSED := 2.0
## Outside the observer's view cone (degrees either side of where it faces): much slower.
const VIEW_HALF_DEG := 60.0
const OFF_VIEW := 3.0
const SKILL_SLOW := 1.4   # combat skill 0
const SKILL_FAST := 0.7   # combat skill 1
const FLASH_S := 1.5
const FLASH := 0.15
const SUPPRESSED_FLASH := 0.6
const POINT_BLANK_M := 4.0
const FADE_S := 20.0
## Awareness from which the AI suspects someone is there (looks, searches).
const SUSPECT := 0.35

## Hearing (queue 17 part 2) adds awareness but never a full spot: at most HEARD_MAX.
## A heard shot adds HEARD_SHOT; footsteps HEARD_STEPS_PER_S while heard, out to
## STEPS_RUN_M running, STEPS_WALK_M walking, STEPS_CROUCH_M crouched (none prone or still).
const HEARD_MAX := 0.8
const HEARD_SHOT := 0.4
const HEARD_STEPS_PER_S := 0.25
const STEPS_RUN_M := 25.0
const STEPS_WALK_M := 12.0
const STEPS_CROUCH_M := 5.0

## How well each camo hides on each terrain preset: a factor on the time to spot (above 1
## blends in, below 1 stands out). Presets missing from a row use its "_" value.
const CAMO := {
	"multicam": {"_": 1.15, "salt_flats": 0.9},
	"woodland": {"_": 1.0, "temperate": 1.4, "plain": 1.3, "scrubland": 1.1, "rocky_ridge": 0.9, "desert_wadi": 0.75, "salt_flats": 0.65},
	"desert": {"_": 1.0, "desert_wadi": 1.4, "rocky_ridge": 1.25, "salt_flats": 1.2, "scrubland": 1.2, "temperate": 0.75, "plain": 0.8},
	"urban": {"_": 0.9, "rocky_ridge": 1.05},
}


## The camo factor for `variant` on terrain preset `preset`.
static func camo(variant: String, preset: String) -> float:
	var row: Dictionary = CAMO.get(variant, {})
	return float(row.get(preset, row.get("_", 1.0)))


## Seconds for `observer` to fully spot `target` (already in its line of sight), on terrain
## `preset`. `combat`: the observer's skill (0..1). `now`: Soldier._now().
static func spot_seconds(observer: Soldier, target: Soldier, preset: String, combat: float, suppressed: bool, now: float) -> float:
	var eyes := observer.camera.global_position
	var to := target.global_position - observer.global_position
	to.y = 0.0
	var d := to.length()
	var facing := -observer.global_basis.z
	facing.y = 0.0
	var in_view := d < 0.01 or facing.length() < 0.01 or rad_to_deg(facing.normalized().angle_to(to.normalized())) <= VIEW_HALF_DEG
	if d <= POINT_BLANK_M and in_view:
		return 0.0
	var s := BASE_S + eyes.distance_to(target.aim_point()) / METRES_PER_S
	if target.movement.is_prone():
		s *= PRONE
	elif target.is_crouching():
		s *= CROUCHED
	var speed := Vector2(target.velocity.x, target.velocity.z).length()
	if speed >= RUN_MPS:
		s *= RUNNING
	elif speed >= WALK_MPS:
		s *= WALKING
	s *= camo(String(target.model.variant) if target.model else "", preset)
	if suppressed:
		s *= SUPPRESSED
	if not in_view:
		s *= OFF_VIEW
	s *= lerpf(SKILL_SLOW, SKILL_FAST, clampf(combat, 0.0, 1.0))
	if now - target.last_shot_at <= FLASH_S:
		s *= SUPPRESSED_FLASH if target.last_shot_suppressed else FLASH
	return s


## How far `s`'s footsteps carry now (0 when still or prone).
static func footsteps_m(s: Soldier) -> float:
	var speed := Vector2(s.velocity.x, s.velocity.z).length()
	if speed < WALK_MPS or s.movement.is_prone():
		return 0.0
	if s.is_crouching():
		return STEPS_CROUCH_M
	return STEPS_RUN_M if speed >= RUN_MPS else STEPS_WALK_M


## The terrain preset of the zone `node` is in ("plain" for the compound and the base).
static func preset_of(node: Node) -> String:
	var level := CompoundLevel.current(node)
	if level is ZoneLevel and (level as ZoneLevel).terrain:
		return (level as ZoneLevel).terrain.preset_id
	return "plain"
