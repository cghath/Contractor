class_name Spotting
extends RefCounted
## AI spotting (Captain, P0164 queue 17, part 1): awareness of an enemy builds over time while
## they're in sight, instead of every line of sight being an instant target. How long a full
## spot takes grows with distance and shrinks with what gives the target away; below full
## awareness the AI only suspects something is there (SquadAI looks, a hostile goes to search).
## Every number is proposed, for Captain's playtests.
##
##   seconds to spot = (BASE_S + distance / METRES_PER_S, the distance past OPTIC_FROM_M
##       shortened by the observer's optics: optic_x)
##       x stance (standing 1, crouched, prone) x movement (still 1, walking, running)
##       x camo against the zone's terrain (camo()) x foliage in the way (FOLIAGE_M)
##       x observer (suppressed, looking elsewhere) x skill (an unskilled soldier takes longer)
##   fired in the last FLASH_S: x FLASH (a suppressor gives away less: SUPPRESSED_FLASH)
##   a weapon light or visible laser on: x LIT towards the observer, else x LIT_SIDE
##   closer than POINT_BLANK_M and in front: at once.
##   FOLIAGE_OPAQUE_M or more of scrub or tree crown on every line to them: not seen at all.
## Not seen, awareness fades over FADE_S. Hearing (below) adds to it. Night and NVGs wait for
## day and night (wave 7).

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
## A weapon light or visible laser that's on (GunAttachments.lit; wave 7 S3) gives its carrier
## away: x LIT when it points at the observer (within LIT_TOWARDS_DEG of them), x LIT_SIDE
## otherwise (the beam and the splash it throws). Proposed.
const LIT := 0.4
const LIT_SIDE := 0.75
const LIT_TOWARDS_DEG := 45.0
const FADE_S := 20.0
## Awareness from which the AI suspects someone is there (looks, searches).
const SUSPECT := 0.35

## Hearing (queue 17 part 2) adds awareness but never a full spot: at most HEARD_MAX.
## A heard shot adds HEARD_SHOT; footsteps HEARD_STEPS_PER_S while heard, out to
## STEPS_RUN_M running, STEPS_WALK_M walking, STEPS_CROUCH_M crouched (none prone or still).
const HEARD_MAX := 0.8
const HEARD_SHOT := 0.4
const HEARD_STEPS_PER_S := 0.25
## A squadmate's contact report (SquadAI._share_contact) adds this.
const TOLD := 0.5
const STEPS_RUN_M := 25.0
const STEPS_WALK_M := 12.0
const STEPS_CROUCH_M := 5.0

## Camo against the ground (Captain: "make the camo matrix complete"): worked out from the
## colours, so every uniform, plain clothes and terrain preset gets a value, and new ones do
## too. The ground behind someone is the preset's palette and scrub, by GROUND share; a
## uniform's colour is its camo's mean (a pattern blends at range), plain clothes each
## garment's own colour. The factor on the time to spot falls from CAMO_BEST by CAMO_PER_DE
## per unit of colour difference (CIE Lab, lightness counting CAMO_LIGHTNESS: shade varies
## more than hue on the ground), x CAMO_BREAKUP for a pattern, kept in CAMO_MIN..CAMO_MAX.
## Above 1 blends in, below 1 stands out. tests/squad_test.gd prints the whole matrix.
const CAMO_BEST := 1.4
const CAMO_PER_DE := 0.02
const CAMO_LIGHTNESS := 0.6
const CAMO_BREAKUP := 1.1
const CAMO_MIN := 0.5
const CAMO_MAX := 1.5
const GROUND := {"grass": 0.45, "dry": 0.2, "earth": 0.15, "scrub": 0.2}

## Foliage (Captain's terrain pass: "foliage that blocks the AI's sight"): scrub and tree
## crowns (ZoneScatter.foliage_between) on the line to someone. Every FOLIAGE_M of it
## multiplies the time to spot by e; FOLIAGE_OPAQUE_M hides them. The lines run from the
## observer's eyes to the target's head and chest; the clearer one counts.
const FOLIAGE_M := 0.7
const FOLIAGE_OPAQUE_M := 1.2

## Optics: a weapon's sight magnifies as much as its "ads_fov" zooms the player's view from
## NAKED_FOV (PlayerInput.BASE_FOV); binoculars (their "magnification") when the observer is
## calm (out of contact, not suppressed). Only part of that counts (OPTIC_USE: the AI isn't
## looking through it all the time, and its field is narrow), and only past OPTIC_FROM_M.
const NAKED_FOV := 80.0
const OPTIC_USE := 0.5
const OPTIC_FROM_M := 60.0

static var _camo_cache := {}  # "variant|preset" -> factor


## The camo factor for `variant` (a VoxelArt variant, or plain clothes: VoxelArt.CIV_PREFIX)
## on terrain preset `preset`.
static func camo(variant: String, preset: String) -> float:
	var key := variant + "|" + preset
	if not _camo_cache.has(key):
		_camo_cache[key] = _camo_factor(variant, preset)
	return _camo_cache[key]


static func _camo_factor(variant: String, preset: String) -> float:
	var ground := _ground_lab(TerrainPresets.get_preset(preset))
	var de := 0.0
	var patterned := false
	if variant.begins_with(VoxelArt.CIV_PREFIX) or variant.begins_with("civp:"):
		var f := variant.split(":")
		var cloth: Array = [f[1]] if variant.begins_with("civp:") or f.size() < 3 else [f[1], f[2]]
		for hex: String in cloth:
			de += _de(_lab(Color(hex)), ground)
		de /= cloth.size()
	else:
		var cols: Array = VoxelArt.spec(variant if variant != "" else "multicam").camo
		var mean := Vector3.ZERO
		for c: Variant in cols:
			mean += _lab(Color(c))
		de = _de(mean / cols.size(), ground)
		patterned = true
	var factor := CAMO_BEST - CAMO_PER_DE * de
	if patterned:
		factor *= CAMO_BREAKUP
	return clampf(factor, CAMO_MIN, CAMO_MAX)


## A preset's ground colour in Lab: its palette and scrub by GROUND share.
static func _ground_lab(def: Dictionary) -> Vector3:
	var palette: Dictionary = def.get("palette", {})
	var scrub: Array = def.get("scatter", {}).get("colours", {}).get("scrub", ["55633a"])
	var sum := Vector3.ZERO
	var weight := 0.0
	for part: String in GROUND:
		var hexes: Array = scrub if part == "scrub" else ([palette[part]] if palette.has(part) else [])
		for hex: Variant in hexes:
			sum += _lab(Color(String(hex))) * (float(GROUND[part]) / hexes.size())
		if not hexes.is_empty():
			weight += float(GROUND[part])
	return sum / weight if weight > 0.0 else _lab(Color("5f6a3c"))


static func _de(a: Vector3, b: Vector3) -> float:
	var d := a - b
	return sqrt(pow(d.x * CAMO_LIGHTNESS, 2) + d.y * d.y + d.z * d.z)


## sRGB to CIE Lab (D65): x lightness, y a, z b.
static func _lab(c: Color) -> Vector3:
	var x := (0.4124 * _linear(c.r) + 0.3576 * _linear(c.g) + 0.1805 * _linear(c.b)) / 0.95047
	var y := 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)
	var z := (0.0193 * _linear(c.r) + 0.1192 * _linear(c.g) + 0.9505 * _linear(c.b)) / 1.08883
	var fy := _lab_f(y)
	return Vector3(116.0 * fy - 16.0, 500.0 * (_lab_f(x) - fy), 200.0 * (fy - _lab_f(z)))


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


## Seconds for `observer` to fully spot `target` (already in its line of sight), on terrain
## `preset`; INF while foliage hides them. `combat`: the observer's skill (0..1). `now`:
## Soldier._now(). `foliage`: metres of leaves in the way (foliage_m). `calm`: out of contact
## and not suppressed (binoculars come out).
static func spot_seconds(observer: Soldier, target: Soldier, preset: String, combat: float, suppressed: bool, now: float,
		foliage := 0.0, calm := false) -> float:
	var eyes := observer.camera.global_position
	var to := target.global_position - observer.global_position
	to.y = 0.0
	var d := to.length()
	var facing := -observer.global_basis.z
	facing.y = 0.0
	var in_view := d < 0.01 or facing.length() < 0.01 or rad_to_deg(facing.normalized().angle_to(to.normalized())) <= VIEW_HALF_DEG
	if d <= POINT_BLANK_M and in_view:
		return 0.0
	if foliage >= FOLIAGE_OPAQUE_M:
		return INF
	var range_m := eyes.distance_to(target.aim_point())
	if range_m > OPTIC_FROM_M:
		range_m = OPTIC_FROM_M + (range_m - OPTIC_FROM_M) / optic_x(observer, calm and not suppressed)
	var s := BASE_S + range_m / METRES_PER_S
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
	s *= exp(foliage / FOLIAGE_M)
	if suppressed:
		s *= SUPPRESSED
	if not in_view:
		s *= OFF_VIEW
	s *= lerpf(SKILL_SLOW, SKILL_FAST, clampf(combat, 0.0, 1.0))
	if now - target.last_shot_at <= FLASH_S:
		s *= SUPPRESSED_FLASH if target.last_shot_suppressed else FLASH
	if GunAttachments.lit(target):
		s *= lit_factor(observer, target)
	return s


## LIT or LIT_SIDE: is `target`'s beam (along its aim) pointing at `observer`?
static func lit_factor(observer: Soldier, target: Soldier) -> float:
	var aim := -target.camera.global_basis.z
	var to := observer.camera.global_position - target.camera.global_position
	if to.length_squared() < 0.0001 or aim.length_squared() < 0.0001:
		return LIT
	return LIT if rad_to_deg(aim.angle_to(to)) <= LIT_TOWARDS_DEG else LIT_SIDE


## How much `observer`'s optics shorten distance (1: none): its weapon's sight, and when
## `calm` its binoculars; OPTIC_USE of their magnification.
static func optic_x(observer: Soldier, calm: bool) -> float:
	var x := 1.0
	var weapon := observer.active_weapon() if observer.inventory else null
	if weapon and weapon.stats.has("ads_fov"):
		x = tan(deg_to_rad(NAKED_FOV * 0.5)) / tan(deg_to_rad(float(weapon.stats.ads_fov) * 0.5))
	if calm and observer.inventory and observer.inventory.count_of(&"binoculars") > 0:
		var binos := ItemDB.get_item(&"binoculars")
		x = maxf(x, float(binos.stats.get("magnification", 1.0)) if binos else 1.0)
	return 1.0 + maxf(x - 1.0, 0.0) * OPTIC_USE


## Metres of scrub and tree crown between `observer`'s eyes and `target`: the clearer of the
## lines to its head and its chest. 0 off a zone (no scatter).
static func foliage_m(scatter: ZoneScatter, observer: Soldier, target: Soldier) -> float:
	if scatter == null:
		return 0.0
	return scatter.foliage_least(observer.camera.global_position, target.camera.global_position, target.aim_point())  # one walk for both lines


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


## The scrub and trees of the zone `node` is in (null for the compound and the base).
static func scatter_of(node: Node) -> ZoneScatter:
	var level := CompoundLevel.current(node)
	return (level as ZoneLevel).scatter if level is ZoneLevel else null
