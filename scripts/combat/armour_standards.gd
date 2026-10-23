class_name ArmourStandards
extends RefCounted
## The protection standards armour is rated by (cg_brief queue item 2.0; Captain, 2026-10-22:
## "make sure it follows the current standards for armor"), from res://data/armour_standards.json:
##
## - Personal armour: NIJ Standard 0101.07 (2023). Ballistics.LEVELS is its ladder (HG1, HG2,
##   RF1, RF2, RF3); nij_threats() gives each level's test rounds with the standard's velocities
##   and ranges, which armor_test fires at every rated piece.
## - Vehicles: NATO STANAG 4569 (AEP-55). Each model in data/vehicle_armour.json carries its
##   ratings: "stanag_ke" per arc (front, side, rear: KE levels 1-6), "stanag_artillery" (1-6, a
##   155 mm HE burst's distance) and "stanag_mine" ({"wheel": "4a", "belly": "3b"}: 1 to 4a/4b, 6-10
##   kg TNT); a fitted package's own values replace the base's (rating()). ke_proven(),
##   artillery_proven() and mine_proven() work out what the plates and belly really give, by
##   running the standard's threats through ArmourModel.resolve over the arc (pure: armour_test
##   asserts the stored ratings against them, and phase A5's protection analysis can show them).
##   Above STANAG's top level (an MBT's front) the plates keep their RHAe line-of-sight figures
##   from public estimates (docs/combined_arms.md 2.4.2).
##
## Models marked "stanag_rated": false (aircraft and static weapons: STANAG 4569 rates land
## vehicles' crew protection) have no ratings. Every number is Proposed.

const PATH := "res://data/armour_standards.json"
const ARCS: Array[String] = ["front", "side", "rear"]
const KE_MAX := 6
const ARTILLERY_MAX := 6
## Mine levels by station, weakest first ("0": none; level 1 counts for both stations).
const MINE_WHEEL: Array[String] = ["0", "1", "2a", "3a", "4a"]
const MINE_BELLY: Array[String] = ["0", "1", "2b", "3b", "4b"]
## A plate a round only grazes (its normal this close to square to the round) isn't met.
const FACING_MIN := 0.0001

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("ArmourStandards: %s is missing or not valid JSON" % PATH)
			_data = {"nij_0101_07": {}, "stanag_4569": {}}
		else:
			_data = parsed
	return _data


# --- NIJ 0101.07 ----------------------------------------------------------------------------

## The 0101.07 levels, weakest first.
static func nij_levels() -> Array:
	return (data().nij_0101_07 as Dictionary).get("levels", [])


## The test rounds `level` must stop: its own list plus any level it includes (RF2 takes RF1's).
## Each {"round" (rounds.json id), "name", "mps", "range_m"}.
static func nij_threats(level: Variant) -> Array:
	var nij: Dictionary = data().nij_0101_07
	var key := String(Ballistics.level_name(StringName(level)))
	var out: Array = (nij.get("threats", {}) as Dictionary).get(key, []).duplicate()
	var inc := String((nij.get("includes", {}) as Dictionary).get(key, ""))
	if inc != "":
		out.append_array(nij_threats(inc))
	return out


## The level's own test rounds, without the ones it includes.
static func nij_own_threats(level: Variant) -> Array:
	return ((data().nij_0101_07 as Dictionary).get("threats", {}) as Dictionary).get(String(Ballistics.level_name(StringName(level))), [])


# --- STANAG 4569: the ratings stored with a vehicle -----------------------------------------

static func _stanag() -> Dictionary:
	return data().stanag_4569


## Whether `spec` (VehicleSpecs.spec) is rated at all.
static func rated(spec: Dictionary) -> bool:
	return bool(spec.get("stanag_rated", true)) and spec.has("stanag_ke")


## The ratings of `spec` with `packages` fitted: {"rated", "ke" ({front, side, rear}),
## "artillery", "mine" ({wheel, belly})}; a fitted package's stanag_* replace the base's, later
## packages over earlier ones. Not rated: {"rated": false, "note"}.
static func rating(spec: Dictionary, packages: Array = []) -> Dictionary:
	if not rated(spec):
		return {"rated": false, "note": String(spec.get("stanag_note", ""))}
	var out := {"rated": true, "ke": (spec.stanag_ke as Dictionary).duplicate(), "artillery": int(spec.get("stanag_artillery", 0)),
		"mine": (spec.get("stanag_mine", {"wheel": "0", "belly": "0"}) as Dictionary).duplicate()}
	var defs: Dictionary = spec.get("packages", {})
	for id: String in ArmourModel.fitted_packages(spec, packages):
		var def: Dictionary = defs.get(id, {})
		if def.has("stanag_ke"):
			out.ke.merge(def.stanag_ke, true)
		if def.has("stanag_artillery"):
			out.artillery = int(def.stanag_artillery)
		if def.has("stanag_mine"):
			out.mine.merge(def.stanag_mine, true)
	return out


## The one KE level a rating gives all round, the standard's way: levels 1-4 must hold on every
## arc; 5 and 6 are the front's, with the sides and rear at 4.
static func ke_overall(ke: Dictionary) -> int:
	var front := int(ke.get("front", 0))
	var rest := mini(int(ke.get("side", 0)), int(ke.get("rear", 0)))
	if rest >= 4 and front > 4:
		return front
	return mini(mini(front, rest), 4)


## "4a/3b", "1" or "0" for a mine rating.
static func mine_text(mine: Dictionary) -> String:
	var wheel := String(mine.get("wheel", "0"))
	var belly := String(mine.get("belly", "0"))
	return wheel if wheel == belly else "%s/%s" % [wheel, belly]


## One line for a HUD or a shop: "STANAG 4569 KE 2 (front 3), artillery 4, mine 4a/3b".
static func text(spec: Dictionary, packages: Array = []) -> String:
	var r := rating(spec, packages)
	if not r.rated:
		return "STANAG 4569: not rated"
	var overall := ke_overall(r.ke)
	var arcs := PackedStringArray()
	for arc in ARCS:
		if int(r.ke.get(arc, 0)) != overall:
			arcs.append("%s %d" % [arc, int(r.ke.get(arc, 0))])
	return "STANAG 4569 KE %d%s, artillery %d, mine %s" % [overall, " (%s)" % ", ".join(arcs) if not arcs.is_empty() else "", int(r.artillery), mine_text(r.mine)]


# --- STANAG 4569: what the plates really give ------------------------------------------------

## The plates the ratings are about, with `packages`' plates_add on them: the crew envelope
## (not tyres or a plate marked "stanag": false).
static func plates(spec: Dictionary, packages: Array = []) -> Array:
	var fitted := ArmourModel.fitted_packages(spec, packages)
	var out: Array = []
	for p: Dictionary in spec.get("plates", []):
		if not bool(p.get("stanag", true)) or String(p.get("material", "")) == "tyre":
			continue
		out.append(ArmourModel.with_packages(p, spec, fitted))
	return out


## The KE threats of `level`: [{"shell" (a Shells-shaped row), "range_m", "name"}].
static func ke_threats(level: int) -> Array:
	var def: Dictionary = (_stanag().get("ke", {}) as Dictionary).get(str(level), {})
	var refs: Dictionary = _stanag().get("ke_reference", {})
	var out: Array = []
	for t: Dictionary in def.get("threats", []):
		var shell: Dictionary
		if t.has("shell"):
			shell = Shells.shell(t.shell)
		else:
			shell = Shells.normalised(StringName(t.ref), refs.get(t.ref, {}))
		out.append({"shell": shell, "range_m": float(t.range_m), "name": String(shell.get("name", t.get("ref", t.get("shell", ""))))})
	return out


## The round's direction (vehicle frame: front is -z, x right) coming from `azimuth_deg` off the
## front (+ from the right) and `elevation_deg` above level.
static func incoming(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return -Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


## KE `level`'s threats on `arc` of `spec` with `packages`: every plate the round can meet from
## each of the arc's azimuths and the level's elevations, at the level's range, ricochets left
## out (thickness decides). {"stopped": all stopped, "through": any got through, "worst":
## "plate id, threat" of one that got through}.
static func ke_result(spec: Dictionary, level: int, arc: String, packages: Array = []) -> Dictionary:
	var def: Dictionary = (_stanag().get("ke", {}) as Dictionary).get(str(level), {})
	var out := {"stopped": true, "through": false, "worst": ""}
	if def.is_empty() or (String(def.get("arc", "all")) == "front" and arc != "front"):
		return out
	var list := plates(spec, packages)
	var threats := ke_threats(level)
	for az: Variant in (_stanag().get("arcs", {}) as Dictionary).get(arc, []):
		for el: Variant in def.get("elevations_deg", [0]):
			var dir := incoming(float(az), float(el))
			for p: Dictionary in list:
				if ArmourModel.normal_of(p, dir).dot(-dir) <= FACING_MIN:
					continue
				for t: Dictionary in threats:
					var res := ArmourModel.resolve(t.shell, p, {"dir": dir, "range_m": t.range_m, "seed": 1, "force": {"ricochet": false}})
					if res.outcome == ArmourModel.PEN:
						out.stopped = false
						if not out.through:
							out.worst = "%s, %s from %s/%s deg" % [p.id, t.name, az, el]
						out.through = true
	return out


## The highest KE level `arc` holds: every level up to it stopped (5 and 6 only on the front).
static func ke_proven(spec: Dictionary, arc: String, packages: Array = []) -> int:
	var proven := 0
	for level in range(1, KE_MAX + 1):
		var def: Dictionary = (_stanag().get("ke", {}) as Dictionary).get(str(level), {})
		if String(def.get("arc", "all")) == "front" and arc != "front":
			break
		if not ke_result(spec, level, arc, packages).stopped:
			break
		proven = level
	return proven


## Artillery `level`: its burst's worst fragment (a 20 mm FSP of frag_pen_mm) on every plate
## it can meet from all round at the level's elevations. {"stopped", "through", "worst"}.
static func artillery_result(spec: Dictionary, level: int, packages: Array = []) -> Dictionary:
	var def: Dictionary = (_stanag().get("artillery", {}) as Dictionary).get(str(level), {})
	var out := {"stopped": true, "through": false, "worst": ""}
	if def.is_empty():
		return out
	var frag := Shells.normalised(&"stanag_155_fragment", {"name": "155 mm HE fragment (20 mm FSP)", "kind": "ap", "calibre_mm": 20.0,
		"pen_ke": [[0, float(def.frag_pen_mm)]]})
	var list := plates(spec, packages)
	if list.is_empty():
		return {"stopped": false, "through": true, "worst": "no plates"}
	for az: Variant in _stanag().get("artillery_azimuths", [0]):
		for el: Variant in def.get("elevations_deg", [0]):
			var dir := incoming(float(az), float(el))
			for p: Dictionary in list:
				if ArmourModel.normal_of(p, dir).dot(-dir) <= FACING_MIN:
					continue
				var res := ArmourModel.resolve(frag, p, {"dir": dir, "range_m": 0.0, "seed": 1, "force": {"ricochet": false}})
				if res.outcome == ArmourModel.PEN:
					out.stopped = false
					if not out.through:
						out.worst = "%s from %s/%s deg" % [p.id, az, el]
					out.through = true
	return out


static func artillery_proven(spec: Dictionary, packages: Array = []) -> int:
	var proven := 0
	for level in range(1, ARTILLERY_MAX + 1):
		if not artillery_result(spec, level, packages).stopped:
			break
		proven = level
	return proven


## The belly `spec` has with `packages` (a package's "belly" over the base's).
static func belly(spec: Dictionary, packages: Array = []) -> Dictionary:
	if not spec.has("belly"):
		return {}
	var out: Dictionary = (spec.belly as Dictionary).duplicate()
	var defs: Dictionary = spec.get("packages", {})
	for id: String in ArmourModel.fitted_packages(spec, packages):
		out.merge((defs.get(id, {}) as Dictionary).get("belly", {}), true)
	return out


## Mine `level` ("1", "2a" ... "4b") under `spec` with `packages`: {"held": the crew floor takes
## it, "floor_kg": the TNT that reaches it}. No belly: never held.
static func mine_result(spec: Dictionary, level: String, packages: Array = []) -> Dictionary:
	var def: Dictionary = (_stanag().get("mine", {}) as Dictionary).get(level, {})
	if def.is_empty() or belly(spec, packages).is_empty():
		return {"held": false, "floor_kg": INF}
	var station := String(def.station)
	if station == "wheel" and String(spec.get("kind", "")) == "tracked":
		station = "track"
	var kg := floor_kg(spec, float(def.kg), station, packages)
	return {"held": kg <= floor_limit_kg() + 0.000001, "floor_kg": kg}


## The TNT (kg) of a `kg` charge under station `station` ("wheel", "track", "belly") of `spec`
## with `packages` that reaches the crew floor: kg x the station's share x belly.blast (x0.5 with
## blast seats). The one sum the mine ratings are proven with and phase A2's belly blast turns
## into crew injuries (VehicleModules.belly_injury). INF with no belly.
static func floor_kg(spec: Dictionary, kg: float, station: String, packages: Array = []) -> float:
	var b := belly(spec, packages)
	if b.is_empty():
		return INF
	var proof: Dictionary = _stanag().get("mine_proof", {})
	var out := kg * float((proof.get("station_share", {}) as Dictionary).get(station, 1.0)) * float(b.get("blast", 1.0))
	if String(b.get("seats", "")) == "blast":
		out *= float(proof.get("blast_seat_mult", 1.0))
	return out


## The most TNT (kg) the crew floor takes and the crew fight on (mine_proof floor_kg).
static func floor_limit_kg() -> float:
	return float((_stanag().get("mine_proof", {}) as Dictionary).get("floor_kg", 0.55))


## The mine levels the belly really holds: {"wheel", "belly"} (MINE_WHEEL, MINE_BELLY).
static func mine_proven(spec: Dictionary, packages: Array = []) -> Dictionary:
	var out := {}
	for station: String in ["wheel", "belly"]:
		var order: Array[String] = MINE_WHEEL if station == "wheel" else MINE_BELLY
		var best := "0"
		for i in range(1, order.size()):
			if not mine_result(spec, order[i], packages).held:
				break
			best = order[i]
		out[station] = best
	return out


## The next mine level above `level` at its station ("" past 4a/4b).
static func mine_next(station: String, level: String) -> String:
	var order: Array[String] = MINE_WHEEL if station == "wheel" else MINE_BELLY
	var i := order.find(level)
	return order[i + 1] if i >= 0 and i + 1 < order.size() else ""
