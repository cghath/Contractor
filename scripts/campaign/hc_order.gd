class_name HcOrder
extends RefCounted
## A high command order (docs/high_command.md 4.1): JSON-safe, so it replicates, goes in the
## session log and survives saves. clean() is the one validation every path uses (the RPCs, the
## tests, the soak bot), pure and static.
##
## {"id": int, "squad": "hawk2", "verb": String (VERBS), "points": [[x, z], ...],
##  "target": {"kind", "pos": [x, z], "radius", "ref"} or {}, "facing": [dx, dz] or [],
##  "posture": {"roe", "mode", "formation", "speed", "contact"}, "risk", "go", "after",
##  "state", "phase", "by": peer, "at": seconds, "why": ""}

## Phase 1 (C2) verbs; C3 adds the Phase 2 ones.
const VERBS_1: Array[String] = ["move", "hold", "defend", "follow", "support", "regroup", "extract", "posture", "report"]
const VERBS_2: Array[String] = ["attack", "sbf", "bound", "fall_back", "defend_frontage"]
## Verbs that need a point.
const POINTED: Array[String] = ["move", "defend", "regroup", "extract", "attack", "sbf", "bound", "fall_back", "defend_frontage"]
const STATES: Array[String] = ["sent", "queued", "waiting", "active", "set", "done", "failed", "cancelled"]
const ENDED: Array[String] = ["done", "failed", "cancelled"]
const MAX_POINTS := 16
const MAX_QUEUE := 8
const EDGE_M := 80.0
const ROE: Array[String] = ["free", "return", "hold"]
const MODES: Array[String] = ["safe", "aware", "combat", "stealth"]
const FORMATIONS: Array[String] = ["wedge", "line", "column", "file", "staggered column"]
const SPEEDS: Array[String] = ["slow", "normal", "fast"]
const CONTACT: Array[String] = ["react", "push", "avoid"]
const RISK: Array[String] = ["careful", "balanced", "press"]
const GO_CODES: Array[String] = ["", "alpha", "bravo", "charlie", "hhour"]

static var _next_id := 1


## A new order dict with the defaults filled in.
static func make(squad: String, verb: String, points: Array = [], extra := {}) -> Dictionary:
	var o := {"id": 0, "squad": squad, "verb": verb, "points": points, "target": {}, "facing": [],
		"posture": {}, "risk": "balanced", "go": "", "after": 0, "state": "sent", "phase": "route",
		"by": 0, "at": 0.0, "why": ""}
	o.merge(extra, true)
	return o


## Validates `order` and returns {"ok": bool, "why": String, "order": the cleaned copy}.
## ctx: {"area": Rect2 (the map), "squads": {id: true} (deployed, not dark), "commander": bool
## (the sender holds the token), "queued": int (orders queued on that squad now), "phase2": bool}.
static func clean(order: Variant, ctx: Dictionary) -> Dictionary:
	if not order is Dictionary:
		return _no("not an order")
	var o: Dictionary = (order as Dictionary).duplicate(true)
	if not bool(ctx.get("commander", false)):
		return _no("you don't have command")
	var squad := String(o.get("squad", ""))
	if not (ctx.get("squads", {}) as Dictionary).has(squad):
		return _no("no squad %s out" % squad if squad != "" else "no squad named")
	var verb := String(o.get("verb", ""))
	var allowed := VERBS_1 + (VERBS_2 if bool(ctx.get("phase2", false)) else ([] as Array[String]))
	if verb not in allowed:
		return _no("unknown order '%s'" % verb)
	var pts: Variant = o.get("points", [])
	if not pts is Array:
		return _no("bad points")
	if (pts as Array).size() > MAX_POINTS:
		return _no("too many route points (%d, at most %d)" % [(pts as Array).size(), MAX_POINTS])
	var area: Rect2 = ctx.get("area", Rect2(-1e6, -1e6, 2e6, 2e6))
	var inner := area.grow(-EDGE_M) if area.size.x > EDGE_M * 3.0 and area.size.y > EDGE_M * 3.0 else area
	var out_pts: Array = []
	for p: Variant in pts:
		var v := _vec2(p)
		if not v.is_finite():
			return _no("a point isn't a number")
		if not area.has_point(v):
			return _no("off the map")
		v = Vector2(clampf(v.x, inner.position.x, inner.end.x), clampf(v.y, inner.position.y, inner.end.y))  # clamped inside map_area().grow(-80)
		out_pts.append([v.x, v.y])
	if verb in POINTED and out_pts.is_empty():
		return _no("%s needs a point" % verb)
	o.points = out_pts
	var facing := _vec2(o.get("facing", []))
	o.facing = [facing.x, facing.y] if facing.is_finite() and facing.length() > 0.01 else []
	var posture: Dictionary = o.get("posture", {}) if o.get("posture", {}) is Dictionary else {}
	for key: String in posture.keys():
		var lists := {"roe": ROE, "mode": MODES, "formation": FORMATIONS, "speed": SPEEDS, "contact": CONTACT}
		if not lists.has(key) or String(posture[key]) not in lists[key]:
			return _no("bad posture %s" % key)
	o.posture = posture
	if String(o.get("risk", "balanced")) not in RISK:
		return _no("bad risk")
	if String(o.get("go", "")) not in GO_CODES:
		return _no("bad go code")
	if int(ctx.get("queued", 0)) >= MAX_QUEUE and bool(ctx.get("append", false)):
		return _no("%d orders queued already" % MAX_QUEUE)
	o.why = ""
	return {"ok": true, "why": "", "order": o}


static func next_id() -> int:
	_next_id += 1
	return _next_id - 1


static func point(o: Dictionary, i := -1) -> Vector2:
	var pts: Array = o.get("points", [])
	if pts.is_empty():
		return Vector2.INF
	return _vec2(pts[i if i >= 0 else pts.size() - 1])


static func ended(o: Dictionary) -> bool:
	return String(o.get("state", "")) in ENDED


## Readable verb for the net and the panel.
static func verb_text(verb: String) -> String:
	return {"sbf": "support by fire", "fall_back": "fall back", "defend_frontage": "defend the frontage"}.get(verb, verb)


static func _vec2(p: Variant) -> Vector2:
	if p is Vector2:
		return p
	if p is Vector3:
		return Vector2((p as Vector3).x, (p as Vector3).z)
	if p is Array and (p as Array).size() >= 2 and (typeof(p[0]) in [TYPE_FLOAT, TYPE_INT]) and (typeof(p[1]) in [TYPE_FLOAT, TYPE_INT]):
		return Vector2(float(p[0]), float(p[1]))
	if p is PackedFloat32Array or p is PackedFloat64Array:
		return Vector2(p[0], p[1]) if p.size() >= 2 else Vector2.INF
	return Vector2.INF


static func _no(why: String) -> Dictionary:
	return {"ok": false, "why": why, "order": {}}
