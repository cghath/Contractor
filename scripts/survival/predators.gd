class_name Predators
extends RefCounted
## Wolves, feral dogs and the bear (docs/survival_nature.md; call 100), in Wildlife's records. They
## hunt the weak: a lone survivor (nobody else within LONE_M), a horse (Mounts), the settlers'
## livestock (ZoneAnimals' sheep and goats), and at night anyone within HUNT_M; a bear in its deep
## woods goes for whoever comes within BEAR_M, day or night. A pack hunts together (one target for
## the herd), bites every BITE_S in reach (Vitals.server_damage: the species' "bite"), gives up past
## GIVE_UP_M or after GIVE_UP_S, and keeps off the dead (fear_dead_m) unless it's hunting. A wolf shot
## at turns on the shooter. Every number here is Proposed.

const HUNT_M := 80.0
const LONE_M := 25.0
const BEAR_M := 15.0
const BITE_M := 1.6
const BITE_S := 1.5
const GIVE_UP_M := 120.0
const GIVE_UP_S := 60.0
const PICK_S := 2.0
## A lone man in the day: a pack of this many or more takes him on.
const DAY_PACK := 3
## Livestock bitten: dies at once (sheep and goats are no match).


static func step(level: Node, a: Dictionary, dt: float, ctx: Dictionary) -> void:
	var now := Soldier._now()
	var d := Wildlife.spec(String(a.sp))
	if String(a.state) == "hunt":
		if _hunt(level, a, now):
			return
	elif now >= float(a.get("pick_at", 0.0)):
		a["pick_at"] = now + PICK_S
		var prey: Variant = pick_target(level, a, ctx)
		if prey != null:
			_set_pack(a, prey)
			return
	if String(a.state) != "hunt":
		var dead := Wildlife.nearest_dead(ctx, a.pos, float(d.get("fear_dead_m", 0.0)))
		if dead != Vector2.INF:
			Wildlife.server_flee(level, a, dead)
			return
		if String(a.state) == "flee" and now < float(a.until):
			return
		if String(a.state) == "flee":
			a.state = "idle"
			a.home = a.pos
		Wildlife._wander(a, dt)


## What `a` would go for now (a Soldier, a Mount, or {"zoo": ZoneAnimals, "i"}), or null.
static func pick_target(level: Node, a: Dictionary, ctx: Dictionary) -> Variant:
	var p: Vector2 = a.pos
	var night := float(ctx.get("dark", 0.0)) > 0.5
	var bear := String(a.sp) == "bear"
	var pack := Wildlife.animals.filter(func(o: Dictionary) -> bool: return bool(o.alive) and int(o.herd) == int(a.herd)).size()
	# People.
	for row: Dictionary in ctx.living:
		var s: Soldier = row.s
		var dist := (row.p as Vector2).distance_to(p)
		if bear:
			if dist <= BEAR_M:
				return s
			continue
		if dist > HUNT_M:
			continue
		if night or (pack >= DAY_PACK and _lone(ctx, row)):
			return s
	if bear:
		return null
	# Horses.
	if night and level and level.is_inside_tree():
		for m: Mount in Mounts.all(level):
			if is_instance_valid(m) and Vector2(m.global_position.x, m.global_position.z).distance_to(p) <= HUNT_M:
				return m
	# Livestock.
	var zoo := livestock(level)
	if zoo:
		for i in zoo.animals.size():
			var l: Dictionary = zoo.animals[i]
			if bool(l.alive) and (l.pos as Vector2).distance_to(p) <= HUNT_M:
				return {"zoo": zoo, "i": i}
	return null


static func _lone(ctx: Dictionary, row: Dictionary) -> bool:
	for o: Dictionary in ctx.living:
		if o != row and (o.p as Vector2).distance_to(row.p) <= LONE_M:
			return false
	return true


## The zone's livestock layer (ZoneAnimals: sheep, goats, dogs), or null.
static func livestock(level: Node) -> ZoneAnimals:
	if level == null:
		return null
	var sc: Node = level.get(&"scatter") if level is ZoneLevel else null
	return sc.get_node_or_null(^"Animals") as ZoneAnimals if sc else null


## Host: `a`'s pack goes for `who` (a shot fired at it, say).
static func server_attack(a: Dictionary, who: Soldier) -> void:
	_set_pack(a, who)


static func _set_pack(a: Dictionary, prey: Variant) -> void:
	for o: Dictionary in Wildlife.animals:
		if bool(o.alive) and int(o.herd) == int(a.herd) and not bool(o.get("infected", false)):
			o.state = "hunt"
			o["prey"] = prey
			o.until = Soldier._now() + GIVE_UP_S
			o.wait = 0.0


## One tick of the hunt: run at it, bite in reach. False when it's over (gone, dead, too far, too long).
static func _hunt(level: Node, a: Dictionary, now: float) -> bool:
	var prey: Variant = a.get("prey")
	var at := Vector2.INF
	var alive := false
	if prey is Node3D and is_instance_valid(prey):
		var n := prey as Node3D
		at = Vector2(n.global_position.x, n.global_position.z)
		alive = not (n is Soldier) or (n as Soldier).vitals.is_up()
	elif prey is Dictionary and (prey as Dictionary).has("zoo") and is_instance_valid((prey as Dictionary).zoo):
		var zoo: ZoneAnimals = (prey as Dictionary).zoo
		var l: Dictionary = zoo.animals[int((prey as Dictionary).i)]
		at = l.pos
		alive = bool(l.alive)
	if at == Vector2.INF or not alive or now > float(a.until) or at.distance_to(a.pos) > GIVE_UP_M:
		a.state = "idle"
		a.erase("prey")
		a.home = a.pos
		a.wait = 1.0
		return false
	a.target = at
	if at.distance_to(a.pos) <= BITE_M and now >= float(a.get("bite_at", 0.0)):
		a["bite_at"] = now + BITE_S
		bite(level, a, prey)
	return true


## Host: `a` bites `prey`: a man takes the species' bite as trauma (and an "animal_bite" mark the
## body lane reads), livestock dies, a horse is hurt and bolts.
static func bite(_level: Node, a: Dictionary, prey: Variant) -> void:
	var dmg := float(Wildlife.spec(String(a.sp)).get("bite", 6.0))
	if bool(a.get("infected", false)):
		dmg = InfectedAnimals.bite(String(a.sp))
	if prey is Soldier:
		var s := prey as Soldier
		s.vitals.server_damage(dmg)
		s.set_meta(&"animal_bite", {"sp": String(a.sp), "infected": bool(a.get("infected", false)), "at_h": Moods.now_h()})
		Survival._tell(s, "A %s has you!" % String(Wildlife.spec(String(a.sp)).get("name", a.sp)))
	elif prey is Dictionary and (prey as Dictionary).has("zoo"):
		var zoo: ZoneAnimals = (prey as Dictionary).zoo
		zoo._shot(Vector3.ZERO, null, int((prey as Dictionary).i))
		SessionLog.note("survival: a %s took livestock" % String(a.sp))
	elif prey is Node:
		(prey as Node).set_meta(&"animal_bite", {"sp": String(a.sp), "at_h": Moods.now_h()})
