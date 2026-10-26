class_name ScavengersFauna
extends RefCounted
## Crows, flies, rats and cats (docs/survival_nature.md; call 101). Host, static.
## - **Crows** circle over the bodies (the dead's corpses: Masking.corpses; the living's dead;
##   Wildlife's fresh carcasses) younger than CROW_H, more over more bodies: crow_sites, drawn by
##   Nature high over them and seen CROW_SEE_M off: a far tell of a kill.
## - **Flies** thicken on the unburied (flies_at: the corpses older than FLY_FROM_H near a spot): at
##   the settlement every world hour they raise the zone's pressure (the smell) and may give a settler
##   dysentery (Needs' sickness on their body: FLY_SICK_H a corpse).
## - **Rats** at night (RAT_HOUR): a settlement with open stores (no "stores_closed": a storeroom
##   piece will set it) loses RAT_SHARE of its food (at least one), twice that in a city; a cat at
##   the settlement (server_found_cat) halves it; now and then a settler sickens (RAT_SICK).
## - **Raccoons** (Wildlife's thieves: the zone's raccoons) at RACCOON_HOUR take RACCOON_TAKE food
##   from open stores.
## Each loss goes in the settlement's "nature_losses" (the stock loss event) and the journal.
## Every number here is Proposed.

const CROW_H := 72.0
const CROW_PER_BODY := 3
const CROW_MAX := 14
const CROW_GROUP_M := 12.0
const FLY_FROM_H := 12.0
const FLY_PER_BODY := 0.25
const FLY_PRESSURE := 1.0
const FLY_SICK_H := 0.004
const RAT_HOUR := 2
const RAT_SHARE := 0.06
const CITY_RATS_X := 2.0
const CAT_X := 0.5
const RAT_SICK := 0.05
const RACCOON_HOUR := 3
const RACCOON_TAKE := 2
## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


# --- Crows ------------------------------------------------------------------------------------------

## Every body crows would circle: [{"pos": Vector3, "age_h"}].
static func bodies(level: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var now_h := Moods.now_h()
	if level and level.is_inside_tree():
		for c: Soldier in Masking.corpses(level):
			out.append({"pos": c.global_position, "age_h": now_h - float(c.get_meta(&"down_h", now_h))})
		for n in level.get_tree().get_nodes_in_group(&"combatants"):
			var s := n as Soldier
			if s and s.faction != ZombieAI.INFECTED and s.vitals and s.vitals.is_dead() and not s.is_queued_for_deletion():
				out.append({"pos": s.global_position, "age_h": now_h - float(s.get_meta(&"down_h", now_h))})
	for a: Dictionary in Wildlife.animals:
		if not bool(a.alive) and float(a.dead_h) >= 0.0:
			out.append({"pos": Vector3((a.pos as Vector2).x, float(a.get("y", 0.0)), (a.pos as Vector2).y), "age_h": now_h - float(a.dead_h)})
	return out


## The crow flocks: [{"pos": Vector3 (over the bodies), "n" (crows)}], bodies within CROW_GROUP_M one flock.
static func crow_sites(level: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in bodies(level):
		if float(b.age_h) > CROW_H:
			continue
		var p: Vector3 = b.pos
		var joined := false
		for site: Dictionary in out:
			if (site.pos as Vector3).distance_to(p) <= CROW_GROUP_M:
				site.n = mini(int(site.n) + CROW_PER_BODY, CROW_MAX)
				joined = true
				break
		if not joined:
			out.append({"pos": p, "n": CROW_PER_BODY})
	return out


## [x, y, z, n] per crow site (Nature's packet).
static func packed_crows(level: Node) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for site: Dictionary in crow_sites(level):
		var p: Vector3 = site.pos
		out.append_array(PackedFloat32Array([p.x, p.y, p.z, float(site.n)]))
	return out


# --- Flies -------------------------------------------------------------------------------------------

## How thick the flies are at `pos` (0..1): the unburied bodies within `r` older than FLY_FROM_H.
static func flies_at(level: Node, pos: Vector3, r: float) -> float:
	var v := 0.0
	for b: Dictionary in bodies(level):
		if float(b.age_h) >= FLY_FROM_H and (b.pos as Vector3).distance_to(pos) <= r:
			v += FLY_PER_BODY
	return clampf(v, 0.0, 1.0)


# --- The settlement's hour ------------------------------------------------------------------------------

## Host, every world hour (Nature): the flies, the rats' night, the raccoons'.
static func server_hour(level: Node, hod: int) -> void:
	if not Settlement.exists():
		return
	var hosted := Settlement.zone() == Nature.zone() and level != null
	if hosted:
		server_flies_hour(level)
	if hod == RAT_HOUR:
		server_rats_night(level)
	if hod == RACCOON_HOUR and hosted and Wildlife.alive_count("raccoon") > 0:
		server_raccoons(level)


## Host: the flies over the settlement's unburied an hour: pressure (the smell) and sickness.
static func server_flies_hour(level: Node) -> float:
	var f := flies_at(level, Settlement.pos(), Settlement.radius())
	if f <= 0.0:
		return 0.0
	if level is ZoneLevel:
		Survival._raise_pressure(level, Settlement.pos(), FLY_PRESSURE * f)
	for rec: Dictionary in Settlement.settlers():
		if _roll() < FLY_SICK_H * f / FLY_PER_BODY:
			_sicken(rec, "flies")
	return f


## Whether the settlement's stores lie open to rats and raccoons.
static func stores_open() -> bool:
	return Settlement.exists() and not bool(Settlement.data().get("stores_closed", false))


static func has_cat() -> bool:
	return Settlement.exists() and bool(Settlement.data().get("cat", false))


## Host: a cat found and brought to the settlement (halves the rats' take).
static func server_found_cat() -> void:
	if Settlement.exists():
		Settlement.data()["cat"] = true
		Survival._journal_line("A half-wild cat has taken to the stores. The rats will hate it.")


## Host: a night of rats at the settlement: food lost (RAT_SHARE, a city twice, a cat half), maybe
## a settler sick. Returns the items lost.
static func server_rats_night(level: Node) -> int:
	if not stores_open():
		return 0
	var food := _food_ids()
	var total := 0
	for id: String in food:
		total += Settlement.count(id)
	if total <= 0:
		return 0
	var share := RAT_SHARE * (CITY_RATS_X if _city(level) else 1.0) * (CAT_X if has_cat() else 1.0)
	var lose := maxi(1, roundi(total * share))
	var lost := _take_food(food, lose)
	if lost > 0:
		_loss("rats", lost)
		if _roll() < RAT_SICK and not Settlement.settlers().is_empty():
			var all := Settlement.settlers()
			_sicken(all[floori(_roll() * all.size()) % all.size()], "rats")
	return lost


## Host: raccoons in the stores: RACCOON_TAKE food gone.
static func server_raccoons(_level: Node) -> int:
	if not stores_open():
		return 0
	var lost := _take_food(_food_ids(), RACCOON_TAKE)
	if lost > 0:
		_loss("raccoons", lost)
	return lost


static func _city(level: Node) -> bool:
	var zl := level as ZoneLevel
	if zl == null or not Settlement.exists():
		return false
	var m := zl.module_at(Settlement.pos())
	return m != null and ZoneModules.base(String(m.type)) == "city"


static func _food_ids() -> Array[String]:
	var out: Array[String] = []
	for key: String in Settlement.stores():
		for e: Dictionary in Settlement.stores()[key]:
			var id := String(e.get("id", ""))
			if not id in out and Settlement.category_of(id) == "food":
				out.append(id)
	return out


static func _take_food(ids: Array[String], n: int) -> int:
	var lost := 0
	var i := 0
	while lost < n and not ids.is_empty() and i < n * 4:
		var id := ids[i % ids.size()]
		i += 1
		if Settlement.count(id) <= 0:
			continue
		lost += Settlement.taken_count(Settlement.server_take(id, 1))
	return lost


static func _loss(what: String, n: int) -> void:
	var d := Settlement.data()
	if not d.get("nature_losses") is Array:
		d["nature_losses"] = []
	(d["nature_losses"] as Array).append({"what": what, "n": n, "day": Survival.day()})
	d["nature_losses"] = (d["nature_losses"] as Array).slice(-20)
	Survival._journal_line("%s got into the stores in the night: %d food gone." % [what.capitalize(), n])


## A settler sickens (the body's API: Needs' sickness on their body record).
static func _sicken(rec: Dictionary, why: String) -> void:
	var n: Dictionary = rec.get("needs", {})
	if n.is_empty():
		return
	if (n.get("sick", {}) as Dictionary).is_empty():
		n["sick"] = {"id": "dysentery", "left_h": float(Needs.SICKNESS.dysentery.hours), "onset_h": Needs.ONSET_H, "from": why}
		rec["needs"] = n
