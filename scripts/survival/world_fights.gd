class_name WorldFights
extends RefCounted
## Far fights (docs/survival_world.md 4.5): a fight between far groups, or a far group and a
## horde, resolved by rules: strength = members x (skill x kit x morale) (WorldGroup.strength),
## the defender's defence (its home place and its fortifying), the attacker's surprise (scouted
## or not), a small roll; the fight's noise raises the zone's pressure and a horde may come to it
## and take the field. Losses on both sides are named people (their records dead where it
## happened), the bodies and kit left as traces, supplies taken, captives (cultists), a home
## lost; both groups remember it and the event goes into the pool. Static.

## Proposed: a fight's pressure (scaled by how many fought) and the roll's spread.
const FIGHT_PRESSURE := 25.0
const ROLL := 0.15
const SURPRISE := {true: 1.2, false: 0.9}
## Proposed: a horde's strength per walker, and the chance a far horde finds a group in its zone a tick.
const HORDE_STRENGTH_PER := 0.15
const HORDE_FIND := 0.12


## `att` attacks `def` at `place_id` (its home's, or ""). Returns whether the attacker won.
static func resolve(m: WorldModel, att: Dictionary, def: Dictionary, place_id := "", scouted := false) -> bool:
	var z := String(def.zone)
	var zd := m.zone(z)
	var pl := WorldRegions.place(zd, place_id)
	var rng := m.rng_for(String(att.id) + "|" + String(def.id), "fight")
	var at_home := not pl.is_empty() and String(pl.get("holder", "")) == String(def.id)
	var defence := 1.0 + float(def.get("defence", 0.0)) * 0.6 + (float(pl.get("defence", 0.0)) if at_home else 0.0)
	var a := WorldGroup.strength(att, m.people) * float(SURPRISE[scouted])
	var d := WorldGroup.strength(def, m.people) * defence
	var ratio := a / maxf(a + d, 0.01) + rng.randf_range(-ROLL, ROLL)
	var att_won := ratio > 0.5
	var edge := clampf(absf(ratio - 0.5) * 2.0, 0.0, 1.0)
	var winner := att if att_won else def
	var loser := def if att_won else att
	var dead_names: Array = []
	dead_names.append_array(_losses(m, loser, lerpf(0.3, 0.7, edge), rng, "killed by %s" % String(winner.name), pl, true))
	dead_names.append_array(_losses(m, winner, 0.1 + 0.25 * (1.0 - edge), rng, "killed fighting %s" % String(loser.name), pl, false))
	# the noise: the dead come; past the threshold a horde takes the field
	var pos := WorldModel._place_v(pl) if not pl.is_empty() else WorldGroup.pos2(def)
	var before := m.pressure_of(z)
	m.raise_pressure(z, FIGHT_PRESSURE * clampf((a + d) / 8.0, 0.4, 2.0), pos)
	var horde_came := z != m.hosted and before < WorldModel.HORDE_AT and m.pressure_of(z) >= WorldModel.HORDE_AT
	if horde_came:
		for g: Dictionary in [att, def]:
			dead_names.append_array(_losses(m, g, 0.2, rng, "taken by the dead in the fight", pl, false, true))
	# spoils: the winner takes half; cultists take captives; a home taken or lost
	for k: String in WorldGroup.SUPPLY_KEYS:
		var share := WorldGroup.supply(loser, k) * 0.5
		WorldGroup.add_supply(loser, k, -share)
		WorldGroup.add_supply(winner, k, share)
	if String(winner.kind) == "cultists":
		for i in mini(2, WorldGroup.size(loser)):
			var pid := String(loser.members[-1])
			(loser.members as Array).erase(pid)
			if pid == String(loser.leader):
				m._new_leader(loser)
			var rec: Dictionary = m.people.get(pid, {})
			if not rec.is_empty():
				rec.status = "captive"
				rec["captor"] = String(winner.id)
				rec.erase("world_group")
				m.note(rec, "taken by %s" % String(winner.name))
				(winner.captives as Array).append(pid)
	if att_won and at_home:
		m.clear_home(def)
		def.goal = {"kind": "flee", "zone": _quietest_link(m, z), "place": "", "target": "", "since": m.tick(), "phase": "go", "work": 0}
		if String(att.kind) == "raiders" and (att.home as Dictionary).is_empty():
			m.set_home(att, z, pl)
	# standing and memory
	WorldGroup.change_relation(def, String(att.id), -60.0)
	WorldGroup.change_relation(att, String(def.id), -20.0)
	for oid: String in WorldModel._sorted(m.groups().keys()):
		var o: Dictionary = m.groups()[oid]
		if oid != String(def.id) and oid != String(att.id) and bool(o.alive) and WorldGroup.relation(o, String(def.id)) >= 30.0:
			WorldGroup.change_relation(o, String(att.id), -10.0)
	var where := m.place_name(z, place_id) if place_id != "" else String(zd.get("name", z))
	var text := "%s attacked %s at %s; %s won" % [String(att.name), String(def.name), where, String(winner.name)]
	if not dead_names.is_empty():
		text += " (dead: %s)" % ", ".join(dead_names)
	if horde_came:
		text += "; the noise drew a horde"
	m.add_trace(z, place_id, "bodies and spent cases", dead_names)
	WorldGroup.remember(att, m.now, "fight", text, String(def.id))
	WorldGroup.remember(def, m.now, "fight", text, String(att.id))
	m.event(z, "fight", [String(att.id), String(def.id)], text, place_id)
	for g: Dictionary in [att, def]:
		if WorldGroup.size(g) == 0:
			m._group_dies(g, "wiped out")
	return att_won


## `share` of `g`'s people die (at least one when `at_least_one`); returns their names.
static func _losses(m: WorldModel, g: Dictionary, share: float, rng: RandomNumberGenerator, how: String, pl: Dictionary, at_least_one: bool, by_dead := false) -> Array:
	var n := roundi(float(WorldGroup.size(g)) * share)
	if at_least_one and WorldGroup.size(g) > 0:
		n = maxi(n, 1)
	var names: Array = []
	for i in mini(n, WorldGroup.size(g)):
		var pid := String(g.members[rng.randi_range(0, WorldGroup.size(g) - 1)])
		names.append(String((m.people.get(pid, {}) as Dictionary).get("name", pid)))
		m.person_dies(pid, g, how, by_dead, pl)
	return names


static func _quietest_link(m: WorldModel, z: String) -> String:
	var best := z
	var best_p := INF
	for nb: String in m.zone(z).get("links", []):
		if m.pressure_of(nb) < best_p:
			best_p = m.pressure_of(nb)
			best = nb
	return best


## A far horde in `z` finds the groups there now and then (cautious ones less).
static func horde_on_groups(m: WorldModel, z: String) -> void:
	for gid: String in WorldModel._sorted(m.groups().keys()):
		var g: Dictionary = m.groups()[gid]
		if not bool(g.alive) or String(g.zone) != z or String(g.kind) in ["lone", "enclave"] or bool(g.get("live", false)):
			continue
		var caution := float((g.get("personality", {}) as Dictionary).get("caution", 0.5))
		if m.rng_for(gid, "horde_find").randf() < HORDE_FIND * (1.2 - caution * 0.6):
			horde_fight(m, g, z)


## `g` and the horde in `z`: the group's strength (and its home's defence) against the horde's;
## those killed by the dead rise; the horde loses some of its number.
static func horde_fight(m: WorldModel, g: Dictionary, z: String) -> void:
	var zd := m.zone(z)
	var horde: Dictionary = zd.get("horde", {})
	if horde.is_empty() or WorldGroup.size(g) == 0:
		return
	var rng := m.rng_for(String(g.id), "horde_fight")
	var home := not (g.home as Dictionary).is_empty() and String((g.home as Dictionary).zone) == z
	var mine := WorldGroup.strength(g, m.people) * (1.0 + (float(g.get("defence", 0.0)) if home else 0.0))
	var theirs := float(horde.n) * HORDE_STRENGTH_PER
	var ratio := mine / maxf(mine + theirs, 0.01) + rng.randf_range(-ROLL, ROLL)
	var share := clampf(0.6 - ratio * 0.6, 0.05, 0.6)
	var pl := WorldRegions.place(zd, String((g.home as Dictionary).get("place", ""))) if home else {}
	var names := _losses(m, g, share, rng, "pulled down by the dead", pl, false, true)
	for pid: String in g.members:  # bitten survivors (a mark for the infection chain, phase D)
		if rng.randf() < share * 0.2:
			(m.people.get(pid, {}) as Dictionary)["bitten_day"] = m.day()
	var killed := roundi(mine * 2.0 * rng.randf_range(0.6, 1.2))
	horde.n = maxi(0, int(horde.n) - killed)
	zd.dead = maxf(0.0, float(zd.get("dead", 1.0)) - killed / maxf(1.0, WorldModel.DEAD_PER_ZONE * WorldRegions.dead_base(zd)))
	if int(horde.n) < 5:
		zd.horde = {}
	WorldGroup.add_supply(g, "ammo", -float(WorldGroup.size(g)) * 0.5)
	(g.mood as Dictionary).morale = maxf(0.0, float((g.mood as Dictionary).morale) - share * 0.5)
	var text := "the dead fell on %s in %s" % [String(g.name), String(zd.get("name", z))]
	if not names.is_empty():
		text += " (dead: %s)" % ", ".join(names)
	m.add_trace(z, String(pl.get("id", "")), "a barricade broken from outside", names)
	WorldGroup.remember(g, m.now, "horde", text)
	m.event(z, "horde_attack", [String(g.id)], text, String(pl.get("id", "")))
	if WorldGroup.size(g) == 0:
		m._group_dies(g, "overrun by the dead")
	elif ratio < 0.5 and home:
		m.add_trace(z, String(pl.get("id", "")), "a camp abandoned to the dead", [])
		m.clear_home(g)
