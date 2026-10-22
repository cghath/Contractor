class_name Wading
extends RefCounted
## On foot in water (queue item 1.1 of docs/cg_brief.md): a river, stream, lake or the sea
## (ZoneTerrain.water_height). SoldierMovement asks here every step (the owner's: the human's
## peer, the host for AI).
## - Wading: the deeper the water over his feet, the slower he goes (knee-deep about 0.67 of his
##   pace, waist-deep 0.3), no sprinting past NO_SPRINT_M, no going prone past
##   NO_PRONE_M, and a current pushes him along with it (FLOW_PUSH of its speed at full depth).
## - Deep water (the call, logged in docs/audits/followups.md: Arma 3, the realism bar, has men
##   swim): deeper than SWIM_DEPTH_M over the bottom he swims, head and shoulders out
##   (SWIM_FLOAT_M), at SWIM_SPEED, slower under a load (SWIM_LOADED at a full one), standing
##   stance, his hands busy (no firing, reloading or throwing: his weapon's slung), drifting
##   with the current. The AI doesn't walk into it: deep water is left out of its navigation
##   mesh (ZoneWater.NAV_WATER_M), so its paths take the bridges and fords. No drowning.
## Numbers Proposed.

const WADE_FROM_M := 0.1
const WADE_FULL_M := 1.0
## The share of his pace lost at WADE_FULL_M and deeper, and the curve's power (under 1: the
## first of it costs most: knee-deep already drags).
const WADE_SLOW := 0.7
const WADE_POWER := 0.8
const NO_SPRINT_M := 0.6
const NO_PRONE_M := 0.45
const SWIM_DEPTH_M := 1.45
const SWIM_FLOAT_M := 1.35
const SWIM_SPEED := 1.1
const SWIM_LOADED := 0.45
## How fast he rises or sinks to the swimming height (1/s, and at most m/s).
const SWIM_RISE := 2.5
const SWIM_RISE_MAX := 1.6
const FLOW_PUSH := 0.5
const SWIM_DRIFT := 0.8
## Hands busy while swimming: pushed this far ahead every step.
const SWIM_BUSY_S := 0.25
## The terrain looked up again this often (physics frames).
const LOOKUP_FRAMES := 30

static var _terrain: WeakRef
static var _looked_up := -1000


## The zone's ground (water and all) under `body`, or null (the compound, a base without one).
static func terrain_of(body: Node) -> ZoneTerrain:
	var frame := Engine.get_physics_frames()
	var t: ZoneTerrain = _terrain.get_ref() as ZoneTerrain if _terrain else null
	if frame - _looked_up < LOOKUP_FRAMES and (t == null or t.is_inside_tree()):
		return t  # (null too: no zone here, asked again in a while)
	_looked_up = frame
	t = null
	var lvl := CompoundLevel.current(body) if body.is_inside_tree() else null
	var found: Variant = lvl.get(&"terrain") if lvl else null
	if found is ZoneTerrain:
		t = found
	_terrain = weakref(t) if t else null
	return t


## The water's surface over `body`'s feet, -INF with none (or none over him).
static func surface(body: Node3D) -> float:
	var t := terrain_of(body)
	if t == null or (t.water == null and t.sea_side < 0):
		return -INF
	var p := body.global_position
	return t.water_height(p.x, p.z)


## How deep the water is over `body`'s feet (m; 0 when dry).
static func depth(body: Node3D) -> float:
	var s := surface(body)
	return maxf(s - body.global_position.y, 0.0) if s > -INF else 0.0


## The share of his pace he keeps wading `wet` metres deep.
static func speed_mult(wet: float) -> float:
	return 1.0 - WADE_SLOW * pow(clampf((wet - WADE_FROM_M) / (WADE_FULL_M - WADE_FROM_M), 0.0, 1.0), WADE_POWER)


## Whether water of surface `s` over ground `ground` is too deep to stand in.
static func swims(s: float, ground: float) -> bool:
	return s > -INF and s - ground > SWIM_DEPTH_M


## The current at `body` (m/s, flat), zero in still water or on land.
static func flow(body: Node3D) -> Vector3:
	var t := terrain_of(body)
	if t == null or t.water == null:
		return Vector3.ZERO
	var p := body.global_position
	return t.water.flow_at(p.x, p.z)


## His swimming speed with `load_fraction` (0 light to 1 a full load) on him.
static func swim_speed(load_fraction: float) -> float:
	return SWIM_SPEED * lerpf(1.0, SWIM_LOADED, clampf(load_fraction, 0.0, 1.0))


## The share of his pace the ground under `body` leaves him (queue item 1.3: soft marsh ground and
## snow, ZoneFeatures.slow_at; 1 elsewhere, in a vehicle, or off a zone). The same hook as the
## water's: SoldierMovement reads it each step with the depth.
static func ground_mult(body: Node3D) -> float:
	var t := terrain_of(body)
	if t == null or t.features == null:
		return 1.0
	var p := body.global_position
	if p.y > t.height_at(p.x, p.z) + 0.8:
		return 1.0  # up on something (a bridge, a rock, a roof): not in the mud or the snow
	return t.features.slow_at(p.x, p.z)
