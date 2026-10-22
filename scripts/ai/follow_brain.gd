class_name FollowBrain
extends RefCounted
## Where a follower goes next when it keeps station off a leader (docs/high_command.md section 9
## lift 1). Pure: the co-op soak bot's follow decisions (_follow_tick, _follow_spot, _wedge_spot)
## as one rule, with the actuator left to the caller: the soak walks a player body over RPCs, a
## hero squad (Follow / Support me) walks through SquadAI. One brain, tested two ways.
##
## decide(input) -> {"kind": "walk"|"hold"|"board"|"exit"|"none", "point": Vector3, "speed": String}
## input keys:
##   me: Vector3                 where the follower stands
##   lead: Vector3, lead_yaw: float   the leader's position and yaw (Node3D.rotation.y)
##   lead_ride: Variant          the leader's vehicle (anything non-null), or null
##   my_ride: Variant            the follower's vehicle, or null
##   door: Vector3               the nearest door of the leader's vehicle (when lead_ride)
##   contact: bool               the follower is in contact (hold and fight)
##   points: Array               active extraction points [{"pos": Vector2, "radius": float}]
##   offset: Vector2             (right, back) metres off the leader, turned his way
##   near_m, far_m: float        the station band (soak: 10 / 25; Follow 30 / 60; Support me 60 / 120)
##   slot: int                   which place in an extraction point (spreads the group)

const WALK := "walk"
const RUN := "run"
## The soak's numbers (coop_soak.gd FOLLOW_NEAR_M / FOLLOW_FAR_M); hero squads pass their own.
const NEAR_M := 10.0
const FAR_M := 25.0
## Off the station spot by more than this: walk back to it.
const SPOT_SLACK_M := 8.0
## Further than far_m + this: run.
const RUN_EXTRA_M := 10.0
## Close enough to the door to get in.
const DOOR_M := 3.0
## Inside an extraction point: stand this share of its radius from its centre, spread by slot.
const POINT_SPREAD := 0.4
const POINT_SLACK_M := 1.5
## Station bands for the high command verbs (high_command.md 3.2). Proposed.
const BANDS := {"follow": Vector2(30.0, 60.0), "support": Vector2(60.0, 120.0)}


static func decide(i: Dictionary) -> Dictionary:
	var me: Vector3 = i.get("me", Vector3.ZERO)
	var lead: Vector3 = i.get("lead", me)
	var lead_ride: Variant = i.get("lead_ride")
	var my_ride: Variant = i.get("my_ride")
	if lead_ride != null:
		if my_ride != null and my_ride == lead_ride:
			return _out("none", me)
		if my_ride != null:
			return _out("exit", me)  # in the wrong vehicle: out first
		var door: Vector3 = i.get("door", lead)
		if flat(me, door) > DOOR_M:
			return _out(WALK, door, RUN)
		return _out("board", door)
	if my_ride != null:
		return _out("exit", me)  # the leader got out: so do we
	for point: Dictionary in i.get("points", []):
		var p: Vector2 = point.pos
		var r := float(point.get("radius", 20.0))
		if Vector2(lead.x, lead.z).distance_to(p) <= r:
			var a := TAU * float(int(i.get("slot", 0))) / 4.0 + 0.4
			var spot := Vector3(p.x + cos(a) * r * POINT_SPREAD, me.y, p.y + sin(a) * r * POINT_SPREAD)
			if flat(me, spot) > POINT_SLACK_M:
				return _out(WALK, spot, RUN)
			return _out("hold", me)
	var near := float(i.get("near_m", NEAR_M))
	var far := float(i.get("far_m", FAR_M))
	var to_lead := flat(me, lead)
	var spot := station(lead, float(i.get("lead_yaw", 0.0)), i.get("offset", Vector2(0.0, near + 5.0)))
	if bool(i.get("contact", false)) and to_lead <= far:
		return _out("hold", me)  # in contact: hold and fight
	if to_lead > far or to_lead < near * 0.6 or flat(me, spot) > SPOT_SLACK_M:
		return _out(WALK, spot, RUN if to_lead > far + RUN_EXTRA_M else WALK)
	return _out("none", me)


## The spot `offset` (right, back) metres off a leader at `lead` facing `yaw`.
static func station(lead: Vector3, yaw: float, offset: Vector2) -> Vector3:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return lead + right * offset.x - fwd * offset.y


## A hero squad's offset for Follow / Support me: back and to one side, in the band's middle
## (Support me in echelon: further out to the side).
static func offset_for(verb: String, side := 1.0) -> Vector2:
	var band: Vector2 = BANDS.get(verb, Vector2(NEAR_M, FAR_M))
	var mid := (band.x + band.y) * 0.5
	return Vector2(side * mid * (0.7 if verb == "support" else 0.35), mid * (0.7 if verb == "support" else 0.9))


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _out(kind: String, point: Vector3, speed := WALK) -> Dictionary:
	return {"kind": kind, "point": point, "speed": speed}
