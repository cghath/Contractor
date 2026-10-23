class_name DriveContact
extends RefCounted
## Contact while driving (the squad's drivers part 2, 2026-10-20): what an AI-driven vehicle of
## the squad's does when it comes under fire, by the threat and its armour. SquadDrivers asks
## assess() every tick for each vehicle under orders and acts on the answer:
##   NONE      no contact near it (the squad may be fighting elsewhere): carry on;
##   THROUGH   drive on through the kill zone, faster (an ambush close by: getting out there is
##             worse; or small-arms fire its armour shrugs off), the gunner firing as it goes;
##   DISMOUNT  stop, the passengers out on the side away from the enemy to fight from there,
##             the driver and the gunner stay (the gun keeps firing: AavGunner);
##   ABANDON   it can't go on (engine or wheels gone, burning, hull nearly through): everyone
##             out, driver and gunner too, to cover away from the enemy.
## The threat: the enemies the squad knows of within CONTACT_RANGE_M (fresh enough), the hits it
## took in the last few seconds (SquadDrivers keeps them), and anti-armour: a known enemy with a
## launcher, or a hit by a shaped charge or a blast. The commander's toggle (Mount > On contact)
## turns judging off: drive through unless disabled. Proposed numbers.

const NONE := "none"
const THROUGH := "through"
const DISMOUNT := "dismount"
const ABANDON := "abandon"

## Enemies the squad knows of within this (m) of the vehicle count, seen no longer ago than
## Squad.STALE_S.
const CONTACT_RANGE_M := 300.0
## The nearest enemy closer than this (m): a near ambush, drive through it.
const NEAR_AMBUSH_M := 50.0
## Each hit by small arms adds this to the threat (each known enemy adds 1).
const HIT_WEIGHT := 0.5
## The threat an armour class (data/vehicles.json "class") drives on through.
const TOLERANCE := {"soft": 1.0, "mrap": 3.0, "ifv": 6.0, "mbt": 12.0}
## A hull below this share of its health: abandon it.
const ABANDON_HULL := 0.2


## What `v` does now (keys: "act" (above), "why", "enemy": where the threat is (Vector3.INF: not
## known), "score", "near" (m to the nearest known enemy)). `hits`: [{"kind", "from"}] of the
## last few seconds; `through_only`: the commander turned judging off.
static func assess(v: Vehicle, squad: Variant, hits: Array, through_only: bool) -> Dictionary:
	var pos := v.global_position
	var count := 0
	var near := INF
	var at := false
	var sum := Vector3.ZERO
	if is_instance_valid(squad) and squad is Squad:
		for e: Dictionary in (squad as Squad).enemy_picture():
			if float(e.age) > Squad.STALE_S:
				continue
			var p: Vector3 = e.pos
			var d := Vector2(p.x - pos.x, p.z - pos.z).length()
			if d > CONTACT_RANGE_M:
				continue
			count += 1
			sum += p
			near = minf(near, d)
			if is_instance_valid(e.who) and Launchers.launcher_of(e.who as Soldier) != null:
				at = true
	var kinetic := 0
	var hit_from := Vector3.ZERO
	var hit_seen := 0
	for h: Dictionary in hits:
		if StringName(h.get("kind", Vehicle.KINETIC)) == Vehicle.KINETIC:
			kinetic += 1
		else:
			at = true  # a shaped charge or a blast: anti-armour
		var f: Vector3 = h.get("from", Vector3.INF)
		if f != Vector3.INF:
			hit_from += f
			hit_seen += 1
	var enemy := Vector3.INF
	if count > 0:
		enemy = sum / count
	elif hit_seen > 0:
		enemy = hit_from / hit_seen
	var disabled := is_disabled(v)
	var out := {"act": NONE, "why": "", "enemy": enemy, "score": 0.0, "near": near}
	if not disabled and hits.is_empty() and count == 0:
		return out
	var score := count + kinetic * HIT_WEIGHT
	out.score = score
	out.act = decide(String(v.spec.get("class", "soft")), disabled, through_only, near, at, score)
	out.why = _why(out.act, near, at)
	return out


## The call, from the threat: `cls` the armour class, `near` m to the nearest known enemy, `at`
## an anti-armour threat, `score` the rest of it.
static func decide(cls: String, disabled: bool, through_only: bool, near: float, at: bool, score: float) -> String:
	if disabled:
		return ABANDON
	if through_only or near < NEAR_AMBUSH_M:
		return THROUGH
	if at and cls != "mbt":
		return DISMOUNT
	if score > float(TOLERANCE.get(cls, 1.0)):
		return DISMOUNT
	return THROUGH


## Whether `v` is out of the fight as a vehicle: engine or wheels (tracks) gone, burning, its hull
## nearly through, a wreck, or its modules immobile (combined arms A2: a thrown track, the
## transmission). (Out of fuel or a flat battery isn't: the crew stays for a fix.)
static func is_disabled(v: Vehicle) -> bool:
	return v.wrecked or v.is_burning() or v.zone_health(Vehicle.ZONE_ENGINE) <= 0.0 \
		or v.zone_health(Vehicle.ZONE_WHEELS) <= 0.0 or v.zone_health(Vehicle.ZONE_HULL) < ABANDON_HULL \
		or (v.modules != null and v.modules.mobility_killed())


static func _why(act: String, near: float, at: bool) -> String:
	match act:
		ABANDON:
			return "it can't go on"
		THROUGH:
			return "ambush close by" if near < NEAR_AMBUSH_M else "its armour takes it"
		DISMOUNT:
			return "anti-armour" if at else "too much fire for its armour"
	return ""
