class_name GroupBoard
extends RefCounted
## A side's groups, one row each, live or virtual (docs/combined_arms.md 3.3, phase B1). The
## commander (B2's SideCommand) tasks from it; B1 builds and keeps it. A row:
##   {"id", "side", "kind" (KINDS), "callsign", "strength_cp", "at_cp", "ce", "ce_band" ("green",
##    "amber", "red"), "ammo" (0..1), "ammo_band", "pos", "up", "size", "mounted_in": [vehicle
##    ids], "task" (an HcOrder id, "" untasked), "role", "availability", "sector", "rally",
##    "virtual", "taskable" (false for the company and what it paid for: 3.4.4), "sitrep_at"}
## - Rows change only at a group's sitrep (every sitrep_s), as the side would hear of them: its
##   position, strength and state are what the group last reported, never read between.
## - CP keeps EnemyCommand's scale (1 per man x skill x 1.5 with body armour; a technical or MRAP
##   4, an IFV 8, an MBT 16); AT power apart (an AT4 or RPG 1, a guided launcher 3, an IFV with an
##   ATGM 4, an MBT 6).
## - CE: infantry up/size x 0.5 + ammo x 0.25 + morale x 0.25 - 0.1 x urgent casualties; vehicles
##   crew x 0.4 + mobility x 0.2 + firepower x 0.2 + ammo x 0.2 (whole until A2's modules); a
##   mounted group the lower of the two. GREEN from 0.7, AMBER from 0.45, RED under.
## Numbers in data/side_picture.json "board", Proposed.

const KINDS: Array[String] = ["rifle_squad", "weapons_team", "at_team", "gun_team", "mortar_section", "recon_team", "mech_infantry",
	"armour_section", "armour_platoon", "light_armour", "transport", "qrf", "engineers", "company"]

var side: StringName
## id -> row.
var rows := {}


func _init(p_side: StringName = &"friendly") -> void:
	side = p_side


static func cfg() -> Dictionary:
	return SidePicture.data().get("board", {})


static func _cfg_num(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


# --- Pure scales ---------------------------------------------------------------------------------

## Combat power of one man: {"skill" 0..1, "armour": bool}.
static func man_cp(man: Dictionary) -> float:
	var skill := maxf(float(man.get("skill", 0.6)), _cfg_num("skill_floor", 0.3))
	return _cfg_num("man_cp", 1.0) * skill * (_cfg_num("armour_mult", 1.5) if bool(man.get("armour", false)) else 1.0)


## AT power of one man: his launcher ("" none, "guided", anything else a plain one).
static func man_at_cp(launcher: String) -> float:
	if launcher == "":
		return 0.0
	var table: Dictionary = cfg().get("launcher_at_cp", {})
	return float(table.get(launcher, table.get("default", 1.0)))


## Combat power of a vehicle by its picture kind (SidePicture.VEHICLE_KINDS).
static func vehicle_cp(kind: String) -> float:
	return float((cfg().get("vehicle_cp", {}) as Dictionary).get(kind, 0.0))


## AT power of a vehicle: an MBT, or an IFV with an ATGM.
static func vehicle_at_cp(kind: String, atgm: bool) -> float:
	var table: Dictionary = cfg().get("vehicle_at_cp", {})
	if kind == "mbt":
		return float(table.get("mbt", 6.0))
	if kind == "ifv" and atgm:
		return float(table.get("ifv_atgm", 4.0))
	return 0.0


## Infantry CE (3.3).
static func infantry_ce(up: int, size: int, ammo: float, morale: float, urgent: int) -> float:
	var c: Dictionary = cfg().get("ce", {})
	if size <= 0:
		return 0.0
	return clampf(float(up) / size * float(c.get("up", 0.5)) + ammo * float(c.get("ammo", 0.25)) + morale * float(c.get("morale", 0.25))
		- float(c.get("urgent", 0.1)) * urgent, 0.0, 1.0)


## Vehicle CE (3.3), each part 0..1.
static func vehicle_ce(crew: float, mobility: float, firepower: float, ammo: float) -> float:
	var c: Dictionary = cfg().get("vehicle_ce", {})
	return clampf(crew * float(c.get("crew", 0.4)) + mobility * float(c.get("mobility", 0.2)) + firepower * float(c.get("firepower", 0.2))
		+ ammo * float(c.get("ammo", 0.2)), 0.0, 1.0)


static func ce_band(ce: float) -> String:
	var c: Dictionary = cfg().get("ce", {})
	return "green" if ce >= float(c.get("green", 0.7)) else ("amber" if ce >= float(c.get("amber", 0.45)) else "red")


static func ammo_band(ammo: float) -> String:
	var b: Dictionary = cfg().get("ammo_bands", {})
	return "red" if ammo < float(b.get("red", 0.25)) else ("amber" if ammo < float(b.get("amber", 0.5)) else "green")


## The picture kind of a vehicle model (data/vehicles.json "class", by its base).
static func vehicle_kind(model: String) -> String:
	var spec := VehicleSpecs.spec(model)
	match String(spec.get("class", "soft")):
		"mbt":
			return "mbt"
		"ifv":
			return "ifv"
		"mrap":
			return "light_armour"
		"aircraft":
			return "air"
	if String(spec.get("kind", "")) == "static":
		return "mortar" if model.begins_with("mortar") else "static_gun"
	return "soft_vehicle"


## The picture kind of a soldier seen (by what he carries): "at", "mg", "sniper" or "inf".
static func soldier_kind(s: Soldier) -> String:
	if s == null:
		return "inf"
	if Launchers.launcher_of(s) != null:
		return "at"
	var w := s.active_weapon()
	if w and (w.tags.has("lmg") or w.tags.has("hmg")):
		return "mg"
	if w and (w.tags.has("sniper") or w.tags.has("dmr")):
		return "sniper"
	return "inf"


# --- Rows ----------------------------------------------------------------------------------------

## Brings the board up to date with `groups` (live Squads or Virtualizer records with a "squad"):
## new groups get a row at once (their first sitrep), the rest at their next sitrep; groups gone
## or wiped out leave. `meta` (optional) by group id: {"taskable", "kind", "callsign"}.
func refresh(groups: Array, now: float, meta := {}) -> void:
	var sitrep_s := SidePicture.num("sitrep_s", 30.0)
	var seen := {}
	for g: Variant in groups:
		var id := group_id(g)
		if id == "":
			continue
		seen[id] = true
		var row: Dictionary = rows.get(id, {})
		if not row.is_empty() and now - float(row.sitrep_at) < sitrep_s:
			continue
		var fresh := row_for(g, now, meta.get(id, {}))
		if int(fresh.up) <= 0:
			rows.erase(id)
			continue
		if not row.is_empty():  # what the commander set stays: task, role, sector, rally
			for k in ["task", "role", "availability", "sector", "rally"]:
				fresh[k] = row[k]
			fresh.size = maxi(int(fresh.size), int(row.size))
		rows[id] = fresh
	for id: String in rows.keys():
		if not seen.has(id):
			rows.erase(id)


## A group's id: its Squad's (callsign meta or name), "" for none.
static func group_id(g: Variant) -> String:
	var squad: Squad = null
	if g is Squad:
		squad = g
	elif g is Dictionary:
		squad = (g as Dictionary).get("squad") as Squad
	if squad == null or not is_instance_valid(squad):
		return ""
	return String(squad.get_meta(&"group_id", squad.name))


## A fresh row for `g` (a Squad, or a record {"squad", "soldiers", "virtual"?}).
func row_for(g: Variant, now: float, meta := {}) -> Dictionary:
	var squad: Squad = g if g is Squad else (g as Dictionary).get("squad") as Squad
	var record: Dictionary = g if g is Dictionary else {}
	var men: Array = []
	var cp := 0.0
	var at_cp := 0.0
	var up := 0
	var urgent := 0
	var ammo := 0.0
	var morale := 0.0
	var vehicles := {}
	var launchers := 0
	var mgs := 0
	var pos := Vector3.INF
	var soldiers: Array = squad.members() if g is Squad else record.get("soldiers", [])
	for n: Variant in soldiers:
		var s := n as Soldier
		if s == null or not is_instance_valid(s) or s.is_queued_for_deletion() or s.vitals.is_dead() or s.is_in_group(Soldier.DEAD_GROUP):
			continue
		men.append(s)
		if not s.vitals.is_up():
			urgent += 1
			continue
		up += 1
		if not pos.is_finite():
			pos = s.global_position
		var brain := SquadAI.of(s)
		var launcher := Launchers.launcher_of(s)
		var lkind := "" if launcher == null else ("guided" if launcher.tags.has("guided") else "default")
		cp += man_cp({"skill": brain.combat if brain else 0.6, "armour": s.inventory != null and s.inventory.slots.get(&"plate_front", &"") != &""})
		at_cp += man_at_cp(lkind)
		launchers += 1 if lkind != "" else 0
		mgs += 1 if soldier_kind(s) == "mg" else 0
		ammo += brain.ammo_share(_cfg_num("ammo_full_mags", 6.0)) if brain else 1.0
		morale += brain.morale if brain else 1.0
		if s.vehicle and is_instance_valid(s.vehicle) and not s.vehicle.wrecked:
			vehicles[s.vehicle] = true
	var virtual_up := Virtualizer.virtual_men(record).size() if not record.is_empty() else 0
	if virtual_up > 0:
		up += virtual_up
		cp += virtual_up * man_cp({"skill": 0.6, "armour": false})
		ammo += virtual_up
		morale += virtual_up
		if not pos.is_finite():
			pos = Virtualizer.lead(record)
	var mounted: Array = []
	var v_ce := 1.0
	var v_kinds: Array[String] = []
	for v: Vehicle in vehicles:
		var vk := vehicle_kind(v.model)
		v_kinds.append(vk)
		cp += vehicle_cp(vk)
		at_cp += vehicle_at_cp(vk, v.model == "bradley" or v.spec.has("atgm"))
		mounted.append(v.vehicle_id if v.vehicle_id != "" else String(v.name))
		var mobility := 1.0 if v.fuel > 0.0 else 0.0
		v_ce = minf(v_ce, vehicle_ce(1.0, mobility, 1.0, 1.0))
	var size := maxi(men.size() + virtual_up, int(meta.get("size", 0)))
	var ammo_share := ammo / up if up > 0 else 0.0
	var ce := infantry_ce(up, size, ammo_share, morale / up if up > 0 else 0.0, urgent)
	if not vehicles.is_empty():
		ce = minf(ce, v_ce)
	var id := group_id(g)
	return {"id": id, "side": String(side), "kind": String(meta.get("kind", squad.get_meta(&"group_kind", _guess_kind(up, mgs, launchers, v_kinds)))),
		"callsign": String(meta.get("callsign", squad.get_meta(&"callsign", id))), "strength_cp": cp, "at_cp": at_cp, "ce": ce,
		"ce_band": ce_band(ce), "ammo": ammo_share, "ammo_band": ammo_band(ammo_share), "pos": pos, "up": up, "size": size,
		"mounted_in": mounted, "task": "", "role": "", "availability": 1.0, "sector": null, "rally": Vector3.INF,
		"virtual": Virtualizer.is_virtual(record) if not record.is_empty() else false, "taskable": bool(meta.get("taskable", true)), "sitrep_at": now}


## A group's kind by what it has (a squad's meta "group_kind" wins).
static func _guess_kind(up: int, mgs: int, launchers: int, vehicle_kinds: Array[String]) -> String:
	if vehicle_kinds.has("mbt"):
		return "armour_section" if vehicle_kinds.count("mbt") <= 2 else "armour_platoon"
	if vehicle_kinds.has("ifv"):
		return "mech_infantry"
	if vehicle_kinds.has("light_armour") or vehicle_kinds.has("soft_vehicle"):
		return "light_armour"
	if up <= 4 and launchers >= 2:
		return "at_team"
	if up <= 4 and mgs >= 1:
		return "weapons_team"
	return "rifle_squad"


## Rows of `kind` (or all).
func list(kind := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in rows:
		if kind == "" or String(rows[id].kind) == kind:
			out.append(rows[id])
	return out


## The side's total CP on the board.
func total_cp() -> float:
	var cp := 0.0
	for id: String in rows:
		cp += float(rows[id].strength_cp)
	return cp


## Every live Squad of `faction` with someone in it (from the combatants).
static func squads_of(tree: SceneTree, faction: StringName) -> Array[Squad]:
	var out: Array[Squad] = []
	var seen := {}
	for n in tree.get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or not s.is_ai() or s.faction != faction:
			continue
		var brain := SquadAI.of(s)
		if brain and brain.squad and is_instance_valid(brain.squad) and not seen.has(brain.squad):
			seen[brain.squad] = true
			out.append(brain.squad)
	return out
