extends Node
## Headless checks for combined arms A1, the armour model (docs/combined_arms.md 2.3, 2.4),
## pure: no level, no vehicles, only ArmourModel, Shells and the merged specs. Effective
## thickness by angle and its caps, normalisation, overmatch, ricochet bands, HEAT graze,
## each tile kind against single and tandem warheads and KE, slat odds over 1,000 seeds, HE
## punch-through, fuzes and arming, spacing, partials and shatters, plate and tile lookup on
## the real data, the damage bridge, determinism, the 2.4.6 "who beats what" table asserted
## cell by cell from data, every vehicle's and package's STANAG 4569 ratings proven from its
## plates and belly (cg_brief queue item 2.0: each level's threats stopped at its range, the
## next level's not always), and resolve()'s budget (under 0.05 ms).
##   <voxel godot exe> --headless --path . res://tests/armour_test.tscn
## Exits with the number of failures.

const BUDGET_MS := 0.05

## The 2.4.6 table as docs/combined_arms.md has it (A1 corrections in its section 10). Columns:
## [label, model, main plate, other plates of that face, the model's roof (top attack)].
const COLUMNS := [
	["Abrams turret front", "abrams", "turret_front", [], "turret_roof"],
	["Abrams hull front", "abrams", "hull_front", ["hull_front_lower"], "turret_roof"],
	["Abrams side (rear 2/3)", "abrams", "side_rear_r", [], "turret_roof"],
	["Abrams roof", "abrams", "turret_roof", ["hatch_commander", "hatch_loader"], "turret_roof"],
	["Bradley front", "bradley", "hull_front", [], "hull_roof"],
	["Bradley side", "bradley", "hull_side_r", [], "hull_roof"],
	["AAV side", "aav7", "side_r", [], "roof"],
	["M-ATV side", "matv", "side_r", [], "roof"],
	["T-72B3 (K-5) turret", "t72b3", "turret_front", [], "turret_roof"],
	["T-72B3 side", "t72b3", "hull_side_r", [], "turret_roof"],
	["BMP-2 front", "bmp2", "hull_front", [], "turret_roof"],
]
## Rows: [label, shell id, top attack, cells]. A cell is "pen", "no", "~", "tile", "" (not
## rated), or {"": base, package: with it fitted, "close": within 100 m}.
const ROWS := [
	["M829A3", "m829a3", false, ["no", "pen", "pen", "pen", "pen", "pen", "pen", "pen", "~", "pen", "pen"]],
	["M830A1 HEAT", "m830a1", false, ["no", "no", "pen", "pen", "pen", "pen", "pen", "pen", "no", "pen", "pen"]],
	["M791 25 mm", "m791", false, ["no", "no", "no", "~", "~", "pen", "pen", "pen", "no", "no", "pen"]],
	["M919 25 mm", "m919", false, ["no", "no", "~", "pen", "pen", "pen", "pen", "pen", "no", "pen", "pen"]],
	["TOW-2A", "tow2a", false, ["no", "pen", "pen", "pen", "pen", "pen", "pen", "pen", "~", "pen", "pen"]],
	["3BM42", "3bm42", false, ["no", "~", "pen", "pen", "pen", "pen", "pen", "pen", "", "", ""]],
	["3UBR8 30 mm", "3ubr8", false, ["no", "no", "no", "~", "~", "pen", "pen", "pen", "", "", ""]],
	["Konkurs-M", "konkurs_m", false, ["no", "~", "pen", "pen", "pen", "pen", "pen", "pen", "", "", ""]],
	["Kornet", "kornet", false, ["no", "pen", "pen", "pen", "pen", "pen", "pen", "pen", "", "", ""]],
	["PG-7V", "pg7v", false, ["no", "no", {"": "pen", "tusk1": "tile"}, "pen", "tile", "tile", "pen", "pen", "no", "tile", "pen"]],
	["PG-7VR", "pg7vr", false, ["no", "no", {"": "pen", "tusk2": "no"}, "pen", "pen", {"": "pen", "busk3": "~"}, "pen", "pen", "no", "pen", "pen"]],
	["AT4", "at4_heat", false, ["no", "no", {"": "pen", "tusk1": "tile"}, "pen", "tile", "tile", "pen", "pen", "no", "tile", "pen"]],
	["Javelin (top)", "javelin", true, ["pen", "pen", "pen", "pen", "pen", "pen", "pen", "pen", "pen", "pen", "pen"]],
	["M2 M33", "m33", false, ["no", "no", "no", "no", "no", "no", "no", {"": "no", "close": "~"}, "no", "no", "~"]],
	["Mk19 HEDP", "m430a1", false, ["no", "no", "no", "~", "no", "no", "no", "pen", "no", "no", "~"]],
]
const HEAD_RANGE_M := 500.0
const SWEEP_ANGLES: Array[float] = [0.0, 20.0, 40.0, 60.0]
const SWEEP_RANGES: Array[float] = [100.0, 500.0, 1000.0, 2000.0]
const CLOSE_RANGES: Array[float] = [0.0, 50.0, 100.0]

var failures := 0


func _ready() -> void:
	GameState.zone_id = "test_armour" + OS.get_environment("CONTRACTOR_TEST_TAG")  # never touch a real save
	_test_data()
	_test_angles()
	_test_overmatch_ricochet()
	_test_graze()
	_test_tiles()
	_test_slat_odds()
	_test_he()
	_test_fuzes()
	_test_spaced_partial_shatter()
	_test_lookup()
	_test_damage()
	_test_determinism()
	_test_table()
	_test_budget()
	_test_stanag()
	print("ARMOUR TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)


func check(condition: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", what])
	if not condition:
		failures += 1


## A staged plate facing -z (front).
static func _plate(ke: float, ce: float, phys: float, extra := {}) -> Dictionary:
	var p := {"id": "test", "box": [-1, 0, -1, 1, 2, 1], "normal": [0, 0, -1], "ke_mm": ke, "ce_mm": ce, "phys_mm": phys, "material": "rha"}
	p.merge(extra, true)
	return p


## A direction `deg` off head-on into a plate with normal `n` (tilted about a side axis).
static func _dir(n: Vector3, deg: float) -> Vector3:
	n = n.normalized()
	var axis := n.cross(Vector3.UP)
	if axis.length_squared() < 0.001:
		axis = n.cross(Vector3.RIGHT)
	return (-n).rotated(axis.normalized(), deg_to_rad(deg))


static func _res(shell_id: String, plate: Dictionary, deg := 0.0, range_m := HEAD_RANGE_M, extra := {}) -> Dictionary:
	var hit := {"dir": _dir(ArmourModel.normal_of(plate, Vector3.FORWARD), deg), "range_m": range_m, "seed": 1}
	hit.merge(extra, true)
	return ArmourModel.resolve(Shells.shell(shell_id), plate, hit)


# --- Data ----------------------------------------------------------------------------------

func _test_data() -> void:
	print("Shells, warheads and plates in data")
	var threats := ["m829a3", "m830a1", "m1147", "m791", "m919", "m792", "tow2a", "m430a1", "m33", "m8_api", "b32_127", "b32_145", "bzt_23",
		"3bm42", "3bk29m", "3of26", "9m119m", "3ubr8", "3uof8", "konkurs_m", "kornet", "pg9", "m344", "type63_he", "pg7v", "pg7vl", "pg7vr", "tbg7v",
		"at4_heat", "ffv551", "nlaw", "javelin"]
	var missing: Array = threats.filter(func(id: String) -> bool: return Shells.shell(id).is_empty())
	check(missing.is_empty(), "every 2.4.3 threat has a row (shells.json or warheads.json): %d, missing %s" % [threats.size(), missing])
	var fuzed := true
	for w: StringName in Warheads.ids():
		var d := Warheads.data(w)
		fuzed = fuzed and d.has("fuze") and d.has("module_dmg")
	check(fuzed, "every warhead has a fuze and module_dmg (%d warheads)" % Warheads.ids().size())
	check(Shells.for_round(&"50bmg_m33") == &"m33" and Shells.for_round(&"556_m855") == &"" and Shells.for_round(&"762x54r_lps") == &"",
		"the .50's M33 has vehicle numbers; 5.56 and 7.62x54R don't (they stay on the old tiers)")
	check(is_equal_approx(float(Shells.shell(&"pg7v").pen_ce), 260.0) and is_equal_approx(float(Shells.shell(&"pg7v").he_kg), 1.0)
		and String(Shells.shell(&"pg7v").fuze.kind) == "piezo" and bool(Shells.shell(&"pg7v").rocket),
		"a warhead reads as a shell: PG-7V pen_ce 260 (its penetration_mm), he_kg 1.0, piezo, a rocket")
	check(is_equal_approx(Shells.pen_ke(Shells.shell(&"m829a3"), 750.0), 785.0) and is_equal_approx(Shells.pen_ke(Shells.shell(&"m829a3"), 9000.0), 715.0),
		"pen_ke interpolates (M829A3 785 mm at 750 m) and holds past its end (715)")
	var sound := true
	var plated := 0
	for model in ["abrams", "bradley", "aav7", "matv", "maxxpro"]:
		var spec := VehicleSpecs.spec(model)
		if not (spec.get("plates", []) as Array).is_empty():
			plated += 1
		var ids := {}
		for p: Dictionary in spec.get("plates", []):
			sound = sound and not ids.has(p.id) and (p.box as Array).size() == 6 and p.has("ke_mm") and p.has("ce_mm") and p.has("phys_mm") and p.has("material")
			ids[p.id] = true
		for t: Dictionary in spec.get("tiles", []):
			sound = sound and String(t.kind) in ["light_era", "heavy_era", "tandem_era", "slat"] and float(t.coverage) > 0.0 and int(t.count) > 0
	check(plated == 5 and sound, "the Abrams, Bradley, AAV, M-ATV and MaxxPro have plates and tiles, merged by VehicleSpecs.spec (%d)" % plated)
	check(not VehicleSpecs.spec("technical").has("plates") and not VehicleSpecs.spec("technical_dshk").has("plates") and not VehicleSpecs.spec("uh60").has("plates")
		and String(VehicleSpecs.spec("abrams").get("default_armour", "")) == "mbt",
		"soft vehicles and aircraft have none (VehicleDamage as before); vehicles.json keys are kept")


# --- Angles --------------------------------------------------------------------------------

func _test_angles() -> void:
	print("Effective thickness by angle")
	check(is_equal_approx(ArmourModel.los(100.0, 0.0), 100.0) and absf(ArmourModel.los(100.0, 60.0) - 200.0) < 0.01
		and absf(ArmourModel.los(100.0, 85.0) - 400.0) < 0.01 and absf(ArmourModel.los(100.0, 70.0, true) - 200.0) < 0.01,
		"t / cos: 100 mm at 0 deg 100, at 60 deg 200, at 85 deg capped at 4x (400); composite capped at 2x")
	var plate := _plate(100.0, 100.0, 100.0)
	var r := _res("m829a3", plate, 30.0)
	check(absf(float(r.theta_deg) - 30.0) < 0.01 and absf(float(r.theta_n_deg) - 28.0) < 0.01 and absf(float(r.t_eff) - 100.0 / cos(deg_to_rad(28.0))) < 0.01,
		"a long rod normalises 2 deg (30 -> 28 deg, t_eff %.1f)" % r.t_eff)
	r = _res("m791", plate, 30.0)
	check(absf(float(r.theta_n_deg) - 24.0) < 0.01, "APDS normalises 6 deg (30 -> %.1f)" % r.theta_n_deg)
	r = _res("pg7v", plate, 30.0)
	check(absf(float(r.t_eff) - 100.0 / cos(deg_to_rad(30.0))) < 0.01, "HEAT never normalises (t_eff %.1f at 30 deg)" % r.t_eff)
	r = _res("m829a3", _plate(100.0, 100.0, 100.0, {"normal": "any"}), 0.0)
	check(is_zero_approx(float(r.theta_deg)) and is_equal_approx(float(r.t_eff), 100.0), "a plate with normal \"any\" is head-on from every side")


func _test_overmatch_ricochet() -> void:
	print("Overmatch and ricochet bands")
	var thin := _plate(12.0, 14.0, 12.0)
	var r := _res("m829a3", thin, 84.0)
	check(r.outcome == ArmourModel.PEN and bool(r.overmatch) and float(r.theta_n_deg) <= 45.0,
		"a 120 mm sabot overmatches a 12 mm plate: no bounce at 84 deg, angle capped (%.0f), through (%s)" % [r.theta_n_deg, r.outcome])
	r = _res("m33", thin, 74.0, 100.0)
	check(r.outcome == ArmourModel.RICOCHET and not bool(r.overmatch) and is_equal_approx(float(r.speed_frac), 0.6)
		and (r.ricochet_dir as Vector3).dot(ArmourModel.normal_of(thin, Vector3.FORWARD)) > 0.0,
		"a .50 on the same plate at 74 deg always bounces (band 55-72), leaving at 60% speed, away from the plate")
	var plate := _plate(900.0, 1300.0, 750.0)
	var bands := {77.0: 0, 81.5: 0, 86.0: 0}
	for deg: float in bands:
		for s in 1000:
			var hit := {"dir": _dir(Vector3(0, 0, -1), deg), "range_m": 500.0, "seed": s}
			if ArmourModel.resolve(Shells.shell(&"m829a3"), plate, hit).outcome == ArmourModel.RICOCHET:
				bands[deg] += 1
	check(bands[77.0] == 0 and bands[86.0] == 1000 and bands[81.5] > 400 and bands[81.5] < 600,
		"APFSDS ricochet band 78-85: never at 77 deg, always at 86, about half at 81.5 (%d of 1000)" % bands[81.5])
	r = _res("m791", plate, 70.0, 500.0, {"force": {"ricochet": false}})
	check(r.outcome != ArmourModel.RICOCHET, "a pinned roll (force.ricochet) holds (tests and the table)")


func _test_graze() -> void:
	print("HEAT graze")
	var plate := _plate(100.0, 100.0, 50.0)
	var duds := 0
	var halves := 0
	for s in 1000:
		var r := ArmourModel.resolve(Shells.shell(&"at4_heat"), plate, {"dir": _dir(Vector3(0, 0, -1), 82.0), "range_m": 100.0, "seed": s})
		if r.outcome == ArmourModel.DUD:
			duds += 1
		elif is_equal_approx(float(r.pen), 210.0):
			halves += 1
	check(duds + halves == 1000 and duds > 430 and duds < 570, "AT4 at 82 deg (graze 80): a dud or half its jet, 50/50 (%d duds, %d halves)" % [duds, halves])
	var r := _res("at4_heat", plate, 78.0)
	check(r.outcome != ArmourModel.DUD and is_equal_approx(float(r.pen), 420.0), "at 78 deg it fuzes cleanly (pen %.0f)" % r.pen)
	r = _res("pg7v", plate, 75.0, 100.0, {"force": {"graze": "dud"}})
	var r2 := _res("pg7vl", plate, 75.0, 100.0, {"force": {"graze": "dud"}})
	check(r.outcome == ArmourModel.DUD and r2.outcome != ArmourModel.DUD, "the old PG-7V fuze grazes from 72 deg; the PG-7VL's still fires at 75")


# --- Tiles ---------------------------------------------------------------------------------

func _tile(kind: String) -> Array:
	return [{"group": "g", "kind": kind, "index": 0, "coverage": 1.0, "used": false}]


func _test_tiles() -> void:
	print("Reactive tiles and slat against single, tandem and KE")
	var plate := _plate(100.0, 100.0, 60.0)
	var pin := {"coverage": true, "trigger": true, "slat": "burst"}
	for kind in ["light_era", "heavy_era", "tandem_era"]:
		var single := _res("at4_heat", plate, 0.0, 100.0, {"tiles": _tile(kind), "force": pin})
		var tandem := _res("pg7vr", plate, 0.0, 100.0, {"tiles": _tile(kind), "force": pin})
		var sabot := _res("m829a3", plate, 0.0, 500.0, {"tiles": _tile(kind), "force": pin})
		var cannon := _res("m791", plate, 0.0, 500.0, {"tiles": _tile(kind), "force": pin})
		var e: Dictionary = ArmourModel.ERA[kind]
		check(is_equal_approx(float(single.t_eff), 100.0 + float(e.ce)) and is_equal_approx(float(tandem.t_eff), 100.0 + float(e.ce_tandem))
			and is_equal_approx(float(sabot.t_eff), 100.0 + float(e.ke)) and is_equal_approx(float(cannon.t_eff), 100.0 + float(e.ke) + float(e.ke_autocannon))
			and (single.tiles_fired as Array).size() == 1 and (tandem.tiles_fired as Array).size() == 1 and single.tile == kind,
			"%s: single HEAT +%d, tandem +%d (the tile is spent either way), APFSDS +%d, 25 mm APDS +%d" % [kind, e.ce, e.ce_tandem, e.ke, int(e.ke) + int(e.ke_autocannon)])
	var used := _res("at4_heat", plate, 0.0, 100.0, {"tiles": [{"group": "g", "kind": "light_era", "index": 0, "coverage": 1.0, "used": true}], "force": pin})
	var gap := _res("at4_heat", plate, 0.0, 100.0, {"tiles": _tile("light_era"), "force": {"coverage": false}})
	check(is_equal_approx(float(used.t_eff), 100.0) and is_equal_approx(float(gap.t_eff), 100.0) and (used.tiles_fired as Array).is_empty(),
		"a spent tile is a hole and a missed coverage roll a gap: the round meets the plate")
	var small := _res("m33", plate, 0.0, 100.0, {"tiles": _tile("light_era"), "force": pin})
	var heavy_he := _res("3of26", plate, 0.0, 500.0, {"tiles": _tile("light_era"), "force": pin})
	var light_he := _res("m792", plate, 0.0, 500.0, {"tiles": _tile("light_era"), "force": pin})
	check((small.tiles_fired as Array).is_empty() and (heavy_he.tiles_fired as Array).size() == 1 and (light_he.tiles_fired as Array).is_empty(),
		"what sets one off: not a .50 (under 20 mm), a 3.4 kg HE shell yes, a 25 mm HEI no (under 0.5 kg)")
	var ke_odds := 0
	for s in 1000:
		if not (ArmourModel.resolve(Shells.shell(&"m791"), plate, {"dir": Vector3(0, 0, 1), "seed": s, "tiles": _tile("light_era")}).tiles_fired as Array).is_empty():
			ke_odds += 1
	check(ke_odds > 250 and ke_odds < 350, "25 mm KE sets a tile off about 30%% of the time (%d of 1000)" % ke_odds)
	var slat_ke := _res("m791", plate, 0.0, 500.0, {"tiles": _tile("slat"), "force": pin})
	var slat_he := _res("og7v", plate, 0.0, 50.0, {"tiles": _tile("slat"), "force": pin})
	var slat_atgm := _res("tow2a", plate, 0.0, 500.0, {"tiles": _tile("slat"), "force": {"coverage": true}})
	var slat_burst := _res("pg7v", plate, 0.0, 50.0, {"tiles": _tile("slat"), "force": pin})
	var slat_tandem := _res("pg7vr", plate, 0.0, 50.0, {"tiles": _tile("slat"), "force": pin})
	check((slat_ke.tiles_fired as Array).is_empty() and slat_ke.tile == "" and slat_he.outcome == ArmourModel.FUZED_OUTSIDE
		and is_equal_approx(float(slat_atgm.pen), 900.0 * 0.85) and is_equal_approx(float(slat_burst.pen), 260.0 * 0.85)
		and is_equal_approx(float(slat_tandem.pen), 600.0 * 0.85) and (slat_burst.tiles_fired as Array).size() == 1,
		"slat: KE passes; an HE rocket bursts on it; a missile is never shorted but loses 15%; a rocket that bursts on it (single or tandem) loses 15% and tears the panel")


func _test_slat_odds() -> void:
	print("Slat odds over 1,000 seeds")
	var plate := _plate(20.0, 25.0, 12.0)
	var duds := 0
	var pens := 0
	for s in 1000:
		var r := ArmourModel.resolve(Shells.shell(&"pg7v"), plate, {"dir": Vector3(0, 0, 1), "seed": s, "range_m": 50.0,
			"tiles": [{"group": "slat", "kind": "slat", "index": 0, "coverage": 0.8, "used": false}]})
		if r.outcome == ArmourModel.DUD:
			duds += 1
		elif r.outcome == ArmourModel.PEN:
			pens += 1
	check(duds > 350 and duds < 450 and duds + pens == 1000,
		"PG-7V into an MRAP's slat (80%% coverage, half shorted): about 40%% duds (%d), the rest through (%d)" % [duds, pens])


# --- HE, fuzes ------------------------------------------------------------------------------

func _test_he() -> void:
	print("HE punch-through")
	var mrap_roof := _plate(12.0, 15.0, 8.0, {"normal": [0, 1, 0]})
	var tank_roof := _plate(40.0, 60.0, 40.0, {"normal": [0, 1, 0]})
	var r := _res("3of26", mrap_roof, 0.0)
	var r2 := _res("3of26", tank_roof, 0.0)
	check(r.outcome == ArmourModel.PEN and r.column == "he" and r.burst == "inside" and absf(float(r.pen) - 25.0 * pow(3.4, 1.0 / 3.0)) < 0.01
		and r2.outcome == ArmourModel.NON_PEN and r2.burst == "outside",
		"a 125 mm HE shell (%.1f mm) blows in an MRAP roof (8 mm) and bursts inside; an Abrams roof (40 mm) holds" % r.pen)
	var tech := _plate(3.0, 3.0, 3.0)
	r = _res("m792", tech, 0.0)
	check(r.outcome == ArmourModel.PEN and r.burst == "inside", "a 25 mm HEI punches a technical's 3 mm skin (%.1f mm) and bursts inside" % r.pen)
	r = _res("m430a1", mrap_roof, 0.0, 300.0)
	check(r.outcome == ArmourModel.PEN and r.column == "ce", "the 40 mm HEDP's jet beats an MRAP roof (50 against 15)")
	r = _res("m430a1", _plate(30.0, 60.0, 30.0), 0.0, 300.0)
	check(r.outcome == ArmourModel.NON_PEN, "and not a 60 mm CE plate, nor blows it in (8 mm of HE punch against 30)")
	r = _res("m1147", _plate(12.0, 160.0, 8.0), 0.0)
	check(r.outcome == ArmourModel.PEN and r.column == "he", "AMP: the jet fails (150 against 160) but the 1.6 kg filling blows in the 8 mm plate")


func _test_fuzes() -> void:
	print("Fuzes and arming")
	var plate := _plate(20.0, 25.0, 12.0)
	var r := _res("m430a1", plate, 0.0, 10.0, {"check_arming": true})
	var r2 := _res("m430a1", plate, 0.0, 30.0, {"check_arming": true})
	var r3 := _res("m430a1", plate, 0.0, 10.0)
	check(r.outcome == ArmourModel.DUD and r2.outcome == ArmourModel.PEN and r3.outcome == ArmourModel.PEN,
		"arming: a 40 mm HEDP at 10 m is a dud (arms at 18 m), at 30 m it works; unchecked (a launcher already did) it works")
	r = _res("m792", plate, 0.0, 3100.0)
	check(r.outcome == ArmourModel.DUD and r.burst == "air", "the 25 mm HEI self-destructs past 3,000 m")
	r = _res("m830a1", plate, 0.0, 500.0, {"fuze_mode": "air"})
	r2 = _res("m830a1", plate, 0.0, 500.0)
	check(r.outcome == ArmourModel.FUZED_OUTSIDE and r.fuze == "proximity" and r2.outcome == ArmourModel.PEN and r2.fuze == "piezo",
		"M830A1: in air mode the proximity fuze bursts short (blast only); in ground mode piezo, through")
	r = _res("m1147", plate, 0.0, 800.0, {"fuze_mode": "airburst", "airburst_m": 600.0})
	r2 = _res("m1147", plate, 0.0, 400.0, {"fuze_mode": "airburst", "airburst_m": 600.0})
	check(r.outcome == ArmourModel.FUZED_OUTSIDE and r.burst == "air" and r2.outcome == ArmourModel.PEN,
		"AMP airburst set for 600 m: burst before a hull at 800 m; a hull at 400 m is hit first (point detonating)")
	r = _res("3of26", _plate(5.0, 5.0, 5.0), 0.0, 500.0, {"fuze_mode": "delay"})
	r2 = _res("3of26", plate, 85.0, 500.0, {"fuze_mode": "delay"})
	check(r.outcome == ArmourModel.PEN and r.burst == "inside" and r.fuze == "pd_delay" and r2.outcome == ArmourModel.RICOCHET and r2.burst == "outside",
		"HE on delay: through a thin wall and bursts inside; at 85 deg it skips off and bursts beside the hull")
	r = _res("m792", _plate(1.0, 1.0, 1.0), 0.0)
	check(r.outcome == ArmourModel.PEN and r.burst == "inside" and is_zero_approx(float(r.pen)),
		"a 1 mm sheet doesn't fire a point-detonating fuze (2 mm): it goes through and bursts inside")
	r = _res("m829a3", plate, 0.0, 5.0, {"check_arming": true})
	check(r.outcome == ArmourModel.PEN and r.fuze == "none", "KE has no fuze and no arming")


func _test_spaced_partial_shatter() -> void:
	print("Spacing, partials and shatters")
	var skirt := _plate(85.0, 160.0, 50.0, {"spaced_mm": 450})
	var r := _res("at4_heat", skirt, 0.0, 100.0)
	var r2 := _res("m829a3", skirt, 0.0, 500.0)
	check(is_equal_approx(float(r.pen), 420.0 * 0.85) and is_equal_approx(float(r2.pen), 790.0),
		"a 450 mm air gap costs a shaped charge 15%% (AT4 %.0f), a rod nothing" % r.pen)
	r = _res("m791", _plate(80.0, 80.0, 60.0), 0.0, 500.0)
	check(r.outcome == ArmourModel.NON_PEN and bool(r.partial), "M791 (72 mm) on 80 mm: stopped, but the backface bulges (partial)")
	r = _res("m791", _plate(500.0, 700.0, 250.0, {"material": "composite", "composite": true}), 0.0, 500.0)
	r2 = _res("m791", _plate(500.0, 700.0, 250.0), 0.0, 500.0)
	check(r.outcome == ArmourModel.SHATTER and r2.outcome == ArmourModel.NON_PEN, "on composite far beyond it, a 25 mm penetrator shatters; on soft RHA it's just stopped")


# --- Lookup on the real data ---------------------------------------------------------------

func _test_lookup() -> void:
	print("Plates and tiles on the real models")
	var abrams := VehicleSpecs.spec("abrams")
	var p := ArmourModel.plate_at(abrams, Vector3(1.8, 2.0, -1.5), Vector3(-1, 0, 0), Vector3(1, 0, 0))
	var p2 := ArmourModel.plate_at(abrams, Vector3(1.7, 2.0, -1.69), Vector3(0, 0, 1), Vector3(0, 0, -1))
	var p3 := ArmourModel.plate_at(abrams, Vector3(-1.0, 2.34, 2.0), Vector3(0, -1, 0), Vector3(0, 1, 0))
	var p4 := ArmourModel.plate_at(abrams, Vector3(0.7, 2.5, 0.0), Vector3(0, -1, 0), Vector3(0, 1, 0))
	check(String(p.get("id", "")) == "turret_side_fwd_r" and String(p2.get("id", "")) == "turret_front" and String(p3.get("id", "")) == "turret_roof"
		and String(p4.get("id", "")) == "hatch_commander",
		"the Abrams turret's front corner: from the side the side plate, from the front the cheek; from above the roof or the hatch (%s, %s, %s, %s)" % [p.get("id"), p2.get("id"), p3.get("id"), p4.get("id")])
	p = ArmourModel.plate_at(abrams, Vector3(0.0, 1.2, -2.4), Vector3(0, -0.2, 1).normalized(), Vector3(0, 0, -1))
	p2 = ArmourModel.plate_at(abrams, Vector3(0.0, 1.2, -2.4), Vector3(0, -1, 0), Vector3(0, 1, 0))
	check(String(p.get("id", "")) == "hull_front" and String(p2.get("id", "")) == "hull_roof",
		"the glacis staircase: a voxel's front face is the glacis, its top face from above the deck (%s, %s)" % [p.get("id"), p2.get("id")])
	check(ArmourModel.plate_at(abrams, Vector3(0, 9, 0), Vector3(0, -1, 0)).is_empty(), "outside every plate: none (the zone's armour class decides)")
	var matv := VehicleSpecs.spec("matv")
	p = ArmourModel.plate_at(matv, Vector3(1.2, 0.6, -2.1), Vector3(-1, 0, 0), Vector3(1, 0, 0))
	p2 = ArmourModel.plate_at(matv, Vector3(1.19, 1.4, 0.0), Vector3(-1, 0, 0), Vector3(1, 0, 0))
	check(String(p.get("id", "")) == "wheel_fr" and String(p2.get("id", "")) == "side_r", "an M-ATV's tyre is a tyre, its capsule side a capsule side (%s, %s)" % [p.get("id"), p2.get("id")])
	var at := Vector3(1.75, 1.0, 1.0)
	var base := ArmourModel.tiles_at(abrams, at)
	var tusk1 := ArmourModel.tiles_at(abrams, at, ["tusk1"])
	var tusk2 := ArmourModel.tiles_at(abrams, at, ["tusk2"])
	check(base.is_empty() and tusk1.size() == 1 and tusk1[0].kind == "light_era" and tusk2.size() == 1 and tusk2[0].kind == "tandem_era",
		"Abrams hull side: bare; TUSK I fits ARAT-1; TUSK II swaps it for ARAT-2")
	var rear := ArmourModel.tiles_at(abrams, Vector3(0.0, 1.0, 4.9), ["tusk2"])
	check(rear.size() == 1 and rear[0].kind == "slat", "TUSK II keeps TUSK I's rear slat (includes)")
	var brad := VehicleSpecs.spec("bradley")
	var brat := ArmourModel.tiles_at(brad, Vector3(1.78, 1.2, -2.99))
	var brat2 := ArmourModel.tiles_at(brad, Vector3(1.78, 1.2, 2.99))
	var busk := ArmourModel.tiles_at(brad, Vector3(1.78, 1.2, 0.0), ["busk3"])
	check(brat.size() == 1 and brat[0].kind == "light_era" and int(brat[0].index) == 0 and int(brat2[0].index) == 11 and busk[0].kind == "tandem_era",
		"the Bradley wears BRAT I (12 tiles along each side, front tile 0, rear 11); BUSK III swaps in BRAT II")
	var used := ArmourModel.tiles_at(brad, Vector3(1.78, 1.2, -2.99), [], {"brat1_hull_r": PackedByteArray([1])})
	check(bool(used[0].used), "a fired tile reads as used")
	check(ArmourModel.face_of(null, Vector3.ZERO, Vector3(0.2, -0.9, 0.1)) == Vector3.UP, "no hull: the face is the round's main axis")


# --- Damage bridge, determinism --------------------------------------------------------------

func _test_damage() -> void:
	print("Results as zone damage (phase A1's bridge)")
	var zone := {"zone": Vehicle.ZONE_CREW, "armour": "mrap", "hp_kj": 160.0, "era": false}
	var side := _plate(20.0, 25.0, 12.0)
	var shell := Shells.shell(&"m33")
	var res := ArmourModel.resolve(shell, side, {"dir": Vector3(0, 0, 1), "range_m": 0.0, "seed": 1})
	var d := ArmourModel.damage(res, shell, zone, {"energy_j": 18000.0})
	check(bool(d.penetrated) and not bool(d.stopped) and is_equal_approx(float(d.damage_kj), 18.0) and absf(float(d.energy_left) - 18000.0 * 4.0 / 24.0) < 0.5
		and not bool(d.spall) and d.armour == res,
		"a .50 through an MRAP side at the muzzle: 18 kJ to the zone, it flies on with its residual share (%.0f J), no spall" % d.energy_left)
	res = ArmourModel.resolve(shell, side, {"dir": Vector3(0, 0, 1), "range_m": 500.0, "seed": 1})
	d = ArmourModel.damage(res, shell, zone, {"energy_j": 12000.0})
	check(not bool(d.penetrated) and bool(d.stopped) and is_zero_approx(float(d.damage_kj)), "at 500 m it doesn't get in: no damage")
	shell = Shells.shell(&"pg7v")
	res = ArmourModel.resolve(shell, side, {"dir": Vector3(0, 0, 1), "seed": 1})
	d = ArmourModel.damage(res, shell, zone, {})
	check(bool(d.penetrated) and is_equal_approx(float(d.damage_kj), 100.0) and bool(d.spall) and is_equal_approx(float(d.fire_chance), float(VehicleDamage.FIRE_CHANCE[Vehicle.ZONE_CREW][1])),
		"a PG-7V through it: module_dmg 100, spall, the zone's CE fire chance")
	res = ArmourModel.resolve(shell, _plate(500.0, 700.0, 300.0), {"dir": Vector3(0, 0, 1), "seed": 1})
	d = ArmourModel.damage(res, shell, {"zone": Vehicle.ZONE_HULL, "armour": "mbt", "hp_kj": 900.0}, {})
	check(not bool(d.penetrated) and is_equal_approx(float(d.damage_kj), VehicleDamage.HEAT_STOPPED_PER_KG * 1.0 * 0.01),
		"stopped by a tank: only the old blast-on-the-hull share")
	shell = Shells.shell(&"m8_api")
	res = ArmourModel.resolve(shell, side, {"dir": Vector3(0, 0, 1), "range_m": 50.0, "seed": 1})
	d = ArmourModel.damage(res, shell, {"zone": Vehicle.ZONE_FUEL, "armour": "mrap_weak", "hp_kj": 25.0}, {"energy_j": 17000.0})
	check(is_equal_approx(float(d.fire_chance), float(VehicleDamage.FIRE_CHANCE[Vehicle.ZONE_FUEL][0]) * 2.0), "API through a fuel tank: twice the fire chance")


func _test_determinism() -> void:
	print("Determinism")
	var plate := _plate(100.0, 100.0, 60.0)
	var tiles := [{"group": "g", "kind": "light_era", "index": 0, "coverage": 0.85, "used": false}]
	var same := true
	var differs := false
	var first := ArmourModel.resolve(Shells.shell(&"m791"), plate, {"dir": _dir(Vector3(0, 0, -1), 70.0), "seed": 77, "tiles": tiles})
	for i in 20:
		var again := ArmourModel.resolve(Shells.shell(&"m791"), plate, {"dir": _dir(Vector3(0, 0, -1), 70.0), "seed": 77, "tiles": tiles})
		same = same and again.outcome == first.outcome and again.tiles_fired == first.tiles_fired
	for s in 50:
		var other := ArmourModel.resolve(Shells.shell(&"m791"), plate, {"dir": _dir(Vector3(0, 0, -1), 70.0), "seed": s, "tiles": tiles})
		differs = differs or other.outcome != first.outcome
	check(same and differs, "one seed, one result (the host and a replay agree); other seeds roll differently")


# --- The 2.4.6 table -----------------------------------------------------------------------

## Whether `shell_id` gets through `plate_id` on `model` at `deg` and `range_m` with the
## model's tiles under `packages` met (covered) or missed; KE tile triggers and ricochets pinned.
func _gets_through(shell_id: String, model: String, plate_id: String, packages: Array, covered: bool, deg: float, range_m: float) -> bool:
	var spec := VehicleSpecs.spec(model)
	var plate := {}
	for p: Dictionary in spec.get("plates", []):
		if p.id == plate_id:
			plate = p
	var centre := VehicleSpecs.box(plate.box).get_center()
	var hit := {"dir": _dir(ArmourModel.normal_of(plate, Vector3.FORWARD), deg), "range_m": range_m, "seed": 1,
		"tiles": ArmourModel.tiles_at(spec, centre, packages), "force": {"coverage": covered, "trigger": true, "ricochet": false, "slat": "burst", "graze": "half"}}
	return ArmourModel.resolve(Shells.shell(shell_id), plate, hit).outcome == ArmourModel.PEN


## What the data says for one cell: {"gap": through head-on at 500 m past a gap in the tiles,
## "tile": through head-on with a tile met, "covered": through at some angle, range or plate of
## the face with the tiles met, "varies": through somewhere and not somewhere else}.
func _rate(shell_id: String, model: String, main: String, others: Array, packages: Array, ranges: Array[float]) -> Dictionary:
	var out := {"gap": _gets_through(shell_id, model, main, packages, false, 0.0, HEAD_RANGE_M),
		"tile": _gets_through(shell_id, model, main, packages, true, 0.0, HEAD_RANGE_M), "covered": false, "varies": false}
	var seen := {}
	for plate_id: String in [main] + others:
		for deg in SWEEP_ANGLES:
			for r in ranges:
				for covered: bool in [true, false]:
					var through := _gets_through(shell_id, model, plate_id, packages, covered, deg, r)
					seen[through] = true
					out.covered = out.covered or (covered and through)
	out.varies = seen.size() == 2
	return out


## The doc's legend against the data: "pen" penetrates head-on (gap or tile); "no" never with
## the tiles met; "~" depends on the angle, the range or where on the face; "tile" is stopped
## by a tile and penetrates through a gap.
static func _cell_ok(expected: String, got: Dictionary) -> bool:
	match expected:
		"pen":
			return got.gap and got.tile
		"tile":
			return got.gap and not got.tile
		"no":
			return not got.covered
		"~":
			return got.varies
	return false


func _test_table() -> void:
	print("Who beats what (2.4.6), from data")
	var cells := 0
	var wrong: Array = []
	var skipped := {}
	for row: Array in ROWS:
		for c in COLUMNS.size():
			var col: Array = COLUMNS[c]
			var cell: Variant = row[3][c]
			if typeof(cell) == TYPE_STRING and String(cell) == "":
				continue
			if not VehicleSpecs.spec(col[1]).has("plates"):
				skipped[col[0]] = true  # the Concord's armour arrives with phase D6b
				continue
			var main: String = col[4] if row[2] else col[2]
			var others: Array = [] if row[2] else col[3]
			var wants: Dictionary = cell if typeof(cell) == TYPE_DICTIONARY else {"": cell}
			for ctx: String in wants:
				var packages: Array = [] if ctx in ["", "close"] else [ctx]
				var ranges: Array[float] = CLOSE_RANGES if ctx == "close" else SWEEP_RANGES
				var expected := String(wants[ctx])
				var got := _rate(String(row[1]), col[1], main, others, packages, ranges)
				cells += 1
				if not _cell_ok(expected, got):
					wrong.append("%s vs %s%s: table %s, data %s" % [row[0], col[0], "" if ctx == "" else " (" + ctx + ")", expected, got])
	for w in wrong:
		print("    ", w)
	check(wrong.is_empty(), "%d cells as the table has them (%d wrong); not rated yet (no data until D6b): %s" % [cells, wrong.size(), skipped.keys()])


# --- STANAG 4569 (cg_brief queue item 2.0) ---------------------------------------------------

## Models with no protection to rate under STANAG 4569 (aircraft, crew-served weapons).
const NOT_RATED: Array[String] = ["uh60", "vtol_petrel", "vtol_razorback", "ah1z", "mortar_m224", "mortar_2b14", "tripod_m2", "tripod_dshk"]
## The in-game rounds of STANAG KE level 1 (5.56 ball and SS109, 7.62x51 ball): VehicleDamage's tier 0.
const LEVEL1_ROUNDS: Array[StringName] = [&"556_m193", &"556_m855", &"762x51_m80"]


func _test_stanag() -> void:
	print("STANAG 4569: every vehicle and package rated per arc, and its plates and belly meet it")
	var unrated := PackedStringArray()
	for model: String in VehicleSpecs.models():
		var spec := VehicleSpecs.spec(model)
		if model in NOT_RATED:
			if ArmourStandards.rated(spec) or String(spec.get("stanag_note", "")) == "":
				unrated.append("%s should be marked not rated, with a note" % model)
			continue
		var r := ArmourStandards.rating(spec)
		if not r.rated or not (r.ke as Dictionary).has_all(["front", "side", "rear"]) or not spec.has("stanag_artillery") or not (r.mine as Dictionary).has_all(["wheel", "belly"]):
			unrated.append(model)
	check(unrated.is_empty(), "every model in vehicles.json is rated (stanag_ke per arc, stanag_artillery, stanag_mine) or marked not rated (%d models; %s)" % [VehicleSpecs.models().size(), ", ".join(unrated)])
	# Plated models, base and with each package: the stored ratings are what the plates and belly
	# give: every level up to the rating stopped at its range over the arc, the next not always.
	var wrong := PackedStringArray()
	var rows := PackedStringArray()
	var proofs := 0
	for model: String in ["abrams", "bradley", "aav7", "matv", "maxxpro"]:
		var spec := VehicleSpecs.spec(model)
		var sets: Array = [[]]
		for id: String in (spec.get("packages", {}) as Dictionary):
			sets.append([id])
		for packages: Array in sets:
			var r := ArmourStandards.rating(spec, packages)
			var label := "%s%s" % [model, "" if packages.is_empty() else " + " + String(packages[0])]
			for arc: String in ArmourStandards.ARCS:
				var level := int(r.ke[arc])
				var cap := 6 if arc == "front" else 4
				for l in range(1, level + 1):
					proofs += 1
					var res := ArmourStandards.ke_result(spec, l, arc, packages)
					if not res.stopped:
						wrong.append("%s %s KE %d not stopped (%s)" % [label, arc, l, res.worst])
				if level < cap:
					proofs += 1
					if not ArmourStandards.ke_result(spec, level + 1, arc, packages).through:
						wrong.append("%s %s: KE %d always stopped, rated %d" % [label, arc, level + 1, level])
			var art := int(r.artillery)
			for l in range(1, art + 1):
				proofs += 1
				if not ArmourStandards.artillery_result(spec, l, packages).stopped:
					wrong.append("%s artillery %d not stopped (%s)" % [label, l, ArmourStandards.artillery_result(spec, l, packages).worst])
			if art < ArmourStandards.ARTILLERY_MAX and not ArmourStandards.artillery_result(spec, art + 1, packages).through:
				wrong.append("%s artillery %d always stopped, rated %d" % [label, art + 1, art])
			for station: String in ["wheel", "belly"]:
				var stored := String(r.mine[station])
				var order: Array[String] = ArmourStandards.MINE_WHEEL if station == "wheel" else ArmourStandards.MINE_BELLY
				for i in range(1, order.find(stored) + 1):
					proofs += 1
					if not ArmourStandards.mine_result(spec, order[i], packages).held:
						wrong.append("%s mine %s not held (%.2f kg at the floor)" % [label, order[i], ArmourStandards.mine_result(spec, order[i], packages).floor_kg])
				var next := ArmourStandards.mine_next(station, stored)
				if order.find(stored) < 0:
					wrong.append("%s mine %s: %s isn't a level" % [label, station, stored])
				elif next != "" and ArmourStandards.mine_result(spec, next, packages).held:
					wrong.append("%s mine %s held, rated %s" % [label, next, stored])
			rows.append("%s: KE %s (front %d, side %d, rear %d), artillery %d, mine %s" % [label, ArmourStandards.ke_overall(r.ke), int(r.ke.front), int(r.ke.side), int(r.ke.rear), art, ArmourStandards.mine_text(r.mine)])
	print("    ", "\n    ".join(rows))
	check(wrong.is_empty(), "%d ratings (5 models and their packages) proven from the plates and belly in %d checks (wrong: %s)" % [rows.size(), proofs, ", ".join(wrong)])
	# The brief's proposed ratings hold.
	var matv := VehicleSpecs.spec("matv")
	var maxxpro := VehicleSpecs.spec("maxxpro")
	check(ArmourStandards.ke_overall(ArmourStandards.rating(matv).ke) == 2 and ArmourStandards.ke_overall(ArmourStandards.rating(maxxpro).ke) == 2
		and String(ArmourStandards.rating(matv).mine.belly) == "3b" and String(ArmourStandards.rating(maxxpro).mine.belly) == "3b"
		and ArmourStandards.ke_overall(ArmourStandards.rating(matv, ["matv_applique"]).ke) == 3 and ArmourStandards.ke_overall(ArmourStandards.rating(maxxpro, ["maxxpro_applique"]).ke) == 3,
		"the M-ATV and MaxxPro are KE 2 / mine 3b, KE 3 with their appliqué")
	check(int(ArmourStandards.rating(VehicleSpecs.spec("bradley")).ke.front) == 4 and int(ArmourStandards.rating(VehicleSpecs.spec("abrams")).ke.front) == 6
		and ArmourStandards.ke_result(VehicleSpecs.spec("abrams"), 6, "front").stopped and String(VehicleSpecs.spec("abrams").get("stanag_note", "")).contains("RHAe"),
		"the Bradley's front is KE 4; the Abrams' front stops level 6 and is above STANAG, keeping its RHAe figures")
	# Above the plates: KE level 1's rifle rounds (and the rest of small arms) stay on
	# VehicleDamage's tiers in game (call 79); every rated crew zone stops them there too.
	var leaks := PackedStringArray()
	for model: String in ["abrams", "bradley", "aav7", "matv", "maxxpro"]:
		var spec := VehicleSpecs.spec(model)
		for z: Dictionary in spec.get("zones", []):
			if String(z.zone) != "crew":
				continue
			for round_id: StringName in LEVEL1_ROUNDS:
				var res := VehicleDamage.resolve({"kind": Vehicle.KINETIC, "round": round_id, "energy_j": Ballistics.energy_at(String(round_id), 30.0)}, {"zone": &"crew", "armour": String(z.get("armour", spec.default_armour)), "hp_kj": 100.0, "era": false}, Vector3.BACK)
				if res.penetrated:
					leaks.append("%s %s" % [model, round_id])
	check(leaks.is_empty(), "level 1's rifle rounds don't get through a rated crew zone on the tier rule either (%s)" % ", ".join(leaks))
	# The technicals: KE 0, artillery 0, mine 0, and the tier rule agrees (soft: level 1's rounds go
	# through every zone; no belly to rate).
	var soft_ok := true
	for model: String in ["technical", "technical_dshk", "technical_zu23", "technical_spg9", "technical_m40", "technical_rockets", "technical_zpu"]:
		var spec := VehicleSpecs.spec(model)
		var r := ArmourStandards.rating(spec)
		soft_ok = soft_ok and r.rated and ArmourStandards.ke_overall(r.ke) == 0 and int(r.artillery) == 0 and ArmourStandards.mine_text(r.mine) == "0"
		soft_ok = soft_ok and ArmourStandards.mine_proven(spec) == {"wheel": "0", "belly": "0"} and not spec.has("plates")
		for z: Dictionary in spec.get("zones", []) + [{"zone": "hull"}]:
			var res := VehicleDamage.resolve({"kind": Vehicle.KINETIC, "round": &"556_m193", "energy_j": Ballistics.energy_at("556_m193", 30.0)}, {"zone": StringName(z.zone), "armour": String(z.get("armour", spec.default_armour)), "hp_kj": 100.0, "era": false}, Vector3.BACK)
			soft_ok = soft_ok and res.penetrated
	check(soft_ok, "every technical is rated 0 all round: 5.56 ball goes through each zone, and there's no belly")
	# The helpers.
	check(ArmourStandards.text(matv) == "STANAG 4569 KE 2, artillery 4, mine 4a/3b"
		and ArmourStandards.text(VehicleSpecs.spec("abrams")) == "STANAG 4569 KE 3 (front 6, side 4), artillery 6, mine 2a/1"
		and ArmourStandards.text(VehicleSpecs.spec("uh60")) == "STANAG 4569: not rated",
		"one line for a HUD or shop: %s / %s" % [ArmourStandards.text(matv), ArmourStandards.text(VehicleSpecs.spec("abrams"))])
	check(ArmourStandards.ke_overall({"front": 6, "side": 4, "rear": 4}) == 6 and ArmourStandards.ke_overall({"front": 5, "side": 3, "rear": 4}) == 3
		and ArmourStandards.ke_overall({"front": 4, "side": 3, "rear": 3}) == 3, "levels 1-4 all round, 5-6 the front's over 4 all round")
	var side := {}
	for p: Dictionary in matv.plates:
		if p.id == "side_r":
			side = p
	var fitted := ArmourModel.with_packages(side, matv, ["matv_applique"])
	check(is_equal_approx(float(fitted.ke_mm), 30.0) and is_equal_approx(float(side.ke_mm), 20.0) and is_same(ArmourModel.with_packages(side, matv, ["matv_slat"]), side),
		"the appliqué bolts 10 mm onto the M-ATV's side plate where it's fitted (vehicle_hit uses it), and nothing else changes it")


# --- Budget --------------------------------------------------------------------------------

func _test_budget() -> void:
	print("Budget")
	var shell := Shells.shell(&"pg7vr")
	var plate := _plate(70.0, 160.0, 50.0, {"spaced_mm": 450})
	var tiles := [{"group": "slat", "kind": "slat", "index": 0, "coverage": 0.8, "used": false},
		{"group": "era", "kind": "tandem_era", "index": 0, "coverage": 0.85, "used": false}]
	var ke := Shells.shell(&"m791")
	var n := 5000
	var hits: Array = []
	for i in n:
		hits.append({"dir": _dir(Vector3(0, 0, -1), float(i % 80)), "range_m": 300.0 + float(i % 7) * 100.0, "seed": i, "tiles": tiles})
	var ms := INF
	var bare := INF
	for batch in 3:  # the best of three: a busy machine slows one batch, not the model
		var t0 := Time.get_ticks_usec()
		for i in n:
			ArmourModel.resolve(shell, plate, hits[i])
			ArmourModel.resolve(ke, plate, hits[i])
		ms = minf(ms, float(Time.get_ticks_usec() - t0) / 1000.0 / float(n * 2))
		t0 = Time.get_ticks_usec()
		for i in n:
			ArmourModel.resolve(ke, _plate(70.0, 160.0, 50.0), {"dir": Vector3(0, 0, 1), "range_m": 800.0, "seed": i})
		bare = minf(bare, float(Time.get_ticks_usec() - t0) / 1000.0 / float(n))
	print("    a bare KE hit (no tiles, its plate and hit built in the loop): %.4f ms" % bare)
	check(ms < BUDGET_MS, "resolve: %.4f ms a hit (budget %.2f ms; tiles, spacing and rolls included)" % [ms, BUDGET_MS])
