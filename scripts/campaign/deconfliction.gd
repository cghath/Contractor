class_name Deconfliction
extends RefCounted
## Keeping friendly fire off friendlies (docs/combined_arms.md 4.5; phase B5). Several squads,
## allied groups, armour and mortars in one fight need every layer:
##
## | Layer | Here |
## | Sectors | SideCommand gives each task a corridor (sector_of); lanes don't overlap (shift_clear)
##   and bend round players (detour); a group with a sector holds fire across another group's
##   sector unless the target is inside its own (holds_fire) |
## | The fire fan | SquadOrders.safe_to_fire (built, C3) before each SBF burst; SquadAI's
##   _friendly_in_line stays the last guard on every shot |
## | Player bubbles | no allied group suppresses a point within BUBBLE_M of a player (holds_fire) |
## | Lift and shift | SquadOrders (built, C3) |
## | Indirect fire | FireSupport warns over the net before a mission near friendlies and checks fire
##   when one walks into the target area (warn / check_mission) |
## | Armour IFF | a main gun (HE, splash) never fires within BFT_M of a Blue Force Tracker
##   position (near_bft); a mounted machine gun (AavGunner: door guns, the M2, the coax) never
##   fires with one within BFT_LINE_M of its line of fire, out to BFT_OVERSHOOT_M past the
##   target (bft_in_line); the sight's blue chevron is A5's (VehicleSightOverlay) |
## | Check fire | any player calls it on a point (RequestBroker "check_fire"): all friendly fire into
##   CHECK_FIRE_M of it stops for CHECK_FIRE_S |
## - A friendly-fire incident (a friendly hurt by a friendly) is logged with the shot's details
##   ("[ff]" in the session log) and kept in `incidents` for the debrief and the employer.
## Static, host only. Numbers Proposed.

const CHECK_FIRE_M := 100.0
const CHECK_FIRE_S := 30.0
const BUBBLE_M := 100.0
const BFT_M := 50.0
## A machine gun's line of fire (bft_in_line, cg_brief queue item 2.4's door-gunner fix): a BFT
## vehicle this close to the line (m), the line run on this far past the target (rounds that miss
## carry on). Proposed. The 50 m area held every gunner of a convoy, a heli's door guns over the
## range and an MRAP's M2 off every enemy within 50 m of any friendly vehicle, the convoy itself.
const BFT_LINE_M := 6.0
const BFT_OVERSHOOT_M := 150.0
## Fired down at the target (a door gun, a gun on a hull at a man close by), a miss meets the
## ground once it has dropped this far below the target's feet: the overshoot ends there.
const BFT_GROUND_M := 2.0
const SECTOR_MIN_HALF_M := 30.0
## A detour passes a player's bubble this far out.
const DETOUR_MARGIN_M := 20.0
const FRIENDLY: Array[StringName] = [&"friendly", &"player", &"allied"]

## Active check fires: {"pos", "until", "side", "by"}.
static var check_fires: Array[Dictionary] = []
## Friendly-fire incidents: {"at", "shooter", "victim", "shooter_side", "victim_side", "player"}.
static var incidents: Array[Dictionary] = []
## Tests: added to the clock.
static var offset := 0.0


static func now() -> float:
	return Soldier._now() + offset


# --- Check fire -----------------------------------------------------------------------------------

## Host: all `side`'s fire into CHECK_FIRE_M of `pos` stops for CHECK_FIRE_S.
static func server_check_fire(pos: Vector3, side: StringName = &"friendly", by := "") -> void:
	check_fires.append({"pos": pos, "until": now() + CHECK_FIRE_S, "side": side, "by": by})
	SessionLog.note("[deconfliction] check fire at (%.0f, %.0f) by %s" % [pos.x, pos.z, by])


## Whether fire from `side` onto `pos` is checked now.
static func checked(pos: Vector3, side: StringName = &"friendly") -> bool:
	if check_fires.is_empty():
		return false
	var t := now()
	var live: Array[Dictionary] = []
	var hit := false
	for c: Dictionary in check_fires:
		if t >= float(c.until):
			continue
		live.append(c)
		if _side_of(side) == _side_of(c.side) and _flat(c.pos, pos) <= CHECK_FIRE_M:
			hit = true
	check_fires = live
	return hit


static func _side_of(faction: StringName) -> StringName:
	return &"friendly" if faction in FRIENDLY else faction


# --- Bubbles, sectors and the shot ----------------------------------------------------------------

## Where the players are (up), for bubbles.
static func players(from: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if from == null or not from.is_inside_tree():
		return out
	for p: Soldier in MapNodes.players(from):
		if not p.is_queued_for_deletion() and p.vitals.is_up():
			out.append(p.global_position)
	return out


## Whether `pos` is in a player's bubble.
static func in_bubble(from: Node, pos: Vector3) -> bool:
	for p in players(from):
		if _flat(p, pos) <= BUBBLE_M:
			return true
	return false


## Whether `shooter` (AI) holds fire at `target`: a check fire there, an allied group's suppression
## into a player's bubble (`suppressing`: a point, not a man it sees), or the shot crossing another
## group's sector when the target isn't in its own.
static func holds_fire(shooter: Soldier, target: Vector3, suppressing := false) -> bool:
	if shooter == null or not (shooter.faction in FRIENDLY):
		return false
	if checked(target, shooter.faction):
		return true
	var brain := SquadAI.of(shooter)
	var squad := brain.squad if brain else null
	if squad == null or not squad.has_meta(&"sector"):
		return false  # the player's squad and the company's: no sectors, players lead them
	if suppressing and in_bubble(shooter, target):
		return true
	var own: Dictionary = squad.get_meta(&"sector")
	if in_sector(own, target):
		return false
	for other: Node in shooter.get_tree().get_nodes_in_group(Squad.HC_GROUP):
		var sq := other as Squad
		if sq == null or sq == squad or not sq.has_meta(&"sector") or sq.faction != squad.faction:
			continue
		if crosses(sq.get_meta(&"sector"), shooter.global_position, target):
			return true
	return false


## A task's corridor: from `a` to `b`, `half` either side (at least SECTOR_MIN_HALF_M, or half the
## frontage).
static func sector_of(a: Vector3, b: Vector3, frontage := 0.0) -> Dictionary:
	return {"from": Vector2(a.x, a.z), "to": Vector2(b.x, b.z), "half": maxf(SECTOR_MIN_HALF_M, frontage * 0.5)}


static func in_sector(s: Dictionary, p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	var c := Geometry2D.get_closest_point_to_segment(q, s.from, s.to)
	return c.distance_to(q) <= float(s.half)


## Whether the line from `a` to `b` passes through sector `s`.
static func crosses(s: Dictionary, a: Vector3, b: Vector3) -> bool:
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var c := Geometry2D.get_closest_points_between_segments(pa, pb, s.from, s.to)
	return (c[0] as Vector2).distance_to(c[1]) <= float(s.half)


## Whether two sectors' corridors overlap where they matter: their far parts, past FAR_SHARE of
## the way (groups start beside each other; it's at the task end that lanes cross).
const FAR_SHARE := 0.4
static func overlap(a: Dictionary, b: Dictionary) -> bool:
	var a0: Vector2 = (a.from as Vector2).lerp(a.to, FAR_SHARE)
	var b0: Vector2 = (b.from as Vector2).lerp(b.to, FAR_SHARE)
	var c := Geometry2D.get_closest_points_between_segments(a0, a.to, b0, b.to)
	return (c[0] as Vector2).distance_to(c[1]) < float(a.half) + float(b.half)


## Sector `s` moved sideways (its far end, by its width a step) until it overlaps none of `others`;
## as it was if no shift within `tries` clears it.
static func shift_clear(s: Dictionary, others: Array, tries := 4) -> Dictionary:
	if not others.any(func(o: Dictionary) -> bool: return overlap(s, o)):
		return s
	var axis: Vector2 = (s.to - s.from)
	var side := Vector2(-axis.y, axis.x).normalized() if axis.length() > 0.1 else Vector2.RIGHT
	for k in range(1, tries + 1):
		for sgn in [1.0, -1.0]:
			var moved := s.duplicate()
			moved.to = (s.to as Vector2) + side * sgn * float(s.half) * 2.0 * k
			if not others.any(func(o: Dictionary) -> bool: return overlap(moved, o)):
				return moved
	return s


## The way from `a` to `b` bent round every bubble (centre, radius) it would cross: a waypoint
## beside the bubble on the side the line passes. [] if it crosses none.
static func detour(a: Vector3, b: Vector3, bubbles: Array[Vector3], radius := BUBBLE_M) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in bubbles:
		if _flat(c, b) <= radius or _flat(c, a) <= radius:
			continue  # it starts or ends there: the player's with it
		var q := Geometry2D.get_closest_point_to_segment(Vector2(c.x, c.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
		var d := q.distance_to(Vector2(c.x, c.z))
		if d > radius:
			continue
		var away := (q - Vector2(c.x, c.z))
		if away.length() < 0.1:
			var ab := Vector2(b.x - a.x, b.z - a.z)
			away = Vector2(-ab.y, ab.x)
		away = away.normalized() * (radius + DETOUR_MARGIN_M)
		out.append(Vector3(c.x + away.x, a.y, c.z + away.y))
	return out


# --- Vehicles, indirect fire ----------------------------------------------------------------------

## Whether `pos` is within `m` of a friendly vehicle on the Blue Force Tracker (`except`: the
## shooter's own vehicle's key, "v:<id>").
static func near_bft(from: Node, pos: Vector3, m := BFT_M, except := "") -> bool:
	var pic := SideIntel.picture_of(from, &"friendly")
	if pic == null:
		return false
	for b: Dictionary in pic.bft.values():
		if String(b.what) == "vehicle" and String(b.key) != except and _flat(b.pos, pos) <= m:
			return true
	return false


## The Blue Force Tracker's key for vehicle `v` (SideIntel._track): "v:<id>", or its node name.
static func bft_key(v: Vehicle) -> String:
	return "v:" + (v.vehicle_id if v.vehicle_id != "" else String(v.name))


## Whether a friendly vehicle on the Blue Force Tracker (not `except`, the shooter's own key) is
## within `m` of the line of fire from `muzzle` through `target` and BFT_OVERSHOOT_M past it
## (flat, as near_bft; shorter fired downhill: BFT_GROUND_M): a machine gun's rounds go where
## they're aimed, so only what's on or behind that line is at risk. `target` is the man's feet.
static func bft_in_line(from: Node, muzzle: Vector3, target: Vector3, m := BFT_LINE_M, except := "") -> bool:
	var pic := SideIntel.picture_of(from, &"friendly")
	if pic == null:
		return false
	var a := Vector2(muzzle.x, muzzle.z)
	var seg := Vector2(target.x, target.z) - a
	var length := seg.length()
	if length < 0.1:
		return false
	var dir := seg / length
	# Fired downhill, a miss goes into the ground soon past the target: BFT_GROUND_M of drop past it.
	var slope := (muzzle.y - target.y) / length
	var reach := length + (BFT_OVERSHOOT_M if slope <= 0.01 else minf(BFT_OVERSHOOT_M, BFT_GROUND_M / slope))
	for b: Dictionary in pic.bft.values():
		if String(b.what) != "vehicle" or String(b.key) == except:
			continue
		var p := Vector2((b.pos as Vector3).x, (b.pos as Vector3).z) - a
		var t := clampf(p.dot(dir), 0.0, reach)
		if t > 1.0 and p.distance_to(dir * t) <= m:
			return true
	return false


## The friendlies (players and friendly AI up) within `m` of `pos`, and the compass side of `pos`
## they should keep to: {"count", "away": "south"}.
static func friendlies_near(from: Node, pos: Vector3, m: float) -> Dictionary:
	var n := 0
	var centre := Vector3.ZERO
	if from and from.is_inside_tree():
		for node in from.get_tree().get_nodes_in_group(&"combatants"):
			var s := node as Soldier
			if s and s.faction in FRIENDLY and s.vitals.is_up() and _flat(s.global_position, pos) <= m:
				n += 1
				centre += s.global_position
	var away := ""
	if n > 0:
		away = RadioChatter.compass(pos, centre / n)
	return {"count": n, "away": away}


# --- Incidents ------------------------------------------------------------------------------------

## Host (Harm.note_hit): `victim` was hit by `attacker`; friendly on friendly is an incident.
static func note_hit(victim: Node, attacker: Node) -> void:
	var v := victim as Soldier
	var a := attacker as Soldier
	if v == null or a == null or v == a or not (v.faction in FRIENDLY) or not (a.faction in FRIENDLY):
		return
	var rec := {"at": now(), "shooter": String(a.name), "victim": String(v.name), "shooter_side": String(a.faction),
		"victim_side": String(v.faction), "player": not a.is_ai(), "pos": v.global_position, "distance": a.global_position.distance_to(v.global_position)}
	incidents.append(rec)
	SessionLog.note("[ff] %s hit %s at %.0f m" % [rec.shooter, rec.victim, float(rec.distance)])


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
