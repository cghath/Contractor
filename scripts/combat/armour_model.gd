class_name ArmourModel
extends RefCounted
## The shell model (combined arms A1, docs/combined_arms.md 2.3 and 2.4): how a round with
## vehicle numbers (Shells: data/shells.json, data/warheads.json) comes out against a vehicle's
## armour plates (data/vehicle_armour.json, merged into the spec by VehicleSpecs.spec).
##
## resolve() is pure (dictionaries in, a HitResult dictionary out, no nodes), so armour_test
## stages it directly: the angle to the plate's authored normal, normalisation, overmatch,
## ricochet bands, HEAT graze, fuzes and arming, reactive tiles, slat and spacing, penetration
## by range tables, HE punch-through. Every random roll comes from the hit's seed (2.3.9), so a
## host and a replay agree; tests can force a roll with hit.force.
##
## vehicle_hit() is the host glue Vehicle.server_take_hit calls for a model with "plates": it
## finds the shell, the plate (plate_at) and the tiles over the point (tiles_at), resolves, uses
## up the tiles that fired, and turns the result into the damage dictionary Vehicle._apply_damage
## already takes (damage(), with the HitResult under "armour"); on a model with modules (phase
## A2, VehicleModules.plan) it adds the path through them, the spall cone and any burst inside,
## which VehicleModules applies. Rounds with no vehicle numbers (pistol and
## rifle rounds: small calibre stays immune, Captain's call), charges, mines and fire support
## (HE with no warhead id), and hits inside no plate keep VehicleDamage. Every number here is
## Proposed.

## Outcomes (2.3.3).
const RICOCHET := &"ricochet"
const SHATTER := &"shatter"
const NON_PEN := &"non_pen"
const PEN := &"pen"
const DUD := &"dud"
const FUZED_OUTSIDE := &"fuzed_outside"

## Line of sight: t / cos(theta), at most these times t (beyond that the ricochet roll decides,
## not thickness); composite figures are already line-of-sight values at their design facing.
const LOS_CAP := 4.0
const LOS_CAP_COMPOSITE := 2.0
## An overmatching round's angle is capped here (2.3.2).
const OVERMATCH_MAX_DEG := 45.0
## A KE round with more than this share of t_eff bulges the backface (partial, 2.3.4).
const PARTIAL_SHARE := 0.8
## A KE round with less than this share of t_eff breaks up on hard armour: a shatter.
const SHATTER_SHARE := 0.5
const SHATTER_MATERIALS: Array[String] = ["composite", "composite_du", "hhs"]
const SHATTER_KINDS: Array[String] = ["apfsds", "apds", "ap", "api"]
## A ricochet leaves with this share of its speed.
const RICOCHET_SPEED := 0.6
## HEAT graze (2.3.3): above graze_deg a shaped charge is a dud or bursts wrong (half its pen).
const GRAZE_DEG := 80.0
const GRAZE_DUD_CHANCE := 0.5
const GRAZE_PEN_MULT := 0.5
## HE punch-through (2.3.6): pen_he = HE_PEN_K * he_kg^(1/3) mm against the physical plate.
const HE_PEN_K := 25.0
## A point-detonating fuze needs a surface this thick (mm) to fire (2.3.7).
const SENSITIVITY_MM := 2.0
## Spacing (2.4.1): a shaped charge that fuzes on a skirt loses min(SPACED_MAX, spaced_mm *
## SPACED_PER_MM) of its penetration.
const SPACED_MAX := 0.15
const SPACED_PER_MM := 1.0 / 3000.0
## Slat (2.4.4): a rocket is shorted (a dud) this often; else it bursts on the slat and loses
## this share of its penetration, and the panel is torn.
const SLAT_SHORT_CHANCE := 0.5
const SLAT_PEN_MULT := 0.85
## Reactive armour (2.4.4): mm added against a single shaped charge, a tandem one, KE (APFSDS
## and APDS only), and against autocannon KE (20-40 mm).
const ERA := {
	"light_era": {"ce": 400.0, "ce_tandem": 0.0, "ke": 0.0, "ke_autocannon": 10.0},
	"heavy_era": {"ce": 450.0, "ce_tandem": 0.0, "ke": 220.0, "ke_autocannon": 0.0},
	"tandem_era": {"ce": 450.0, "ce_tandem": 450.0, "ke": 0.0, "ke_autocannon": 0.0},
}
const ERA_KE_KINDS: Array[String] = ["apfsds", "apds"]
const AUTOCANNON_MM := Vector2(20.0, 40.0)
## What sets a tile off: shaped charges of ERA_CE_MIN_MM and up always; KE of ERA_KE_MIN_MM and
## up ERA_KE_CHANCE of the time; HE of ERA_HE_MIN_KG and up ERA_HE_CHANCE.
const ERA_CE_MIN_MM := 30.0
const ERA_KE_MIN_MM := 20.0
const ERA_KE_CHANCE := 0.3
const ERA_HE_MIN_KG := 0.5
const ERA_HE_CHANCE := 0.25
## plate_at: a plate box holds the hit grown by this; its normal must agree with the voxel face
## the round met by at least this (cosine) to be the one hit.
const PLATE_GROW := 0.03
const FACE_AGREE := 0.3
## damage(): a partial bulges the backface (15% of module_dmg); KE throws spall from this
## calibre up; API doubles the fire chance.
const PARTIAL_DMG := 0.15
const KE_SPALL_MIN_MM := 20.0
const INCENDIARY_FIRE_MULT := 2.0
## The rolls (2.3.9): each its own salt on the hit's seed, so one roll never shifts another.
const ROLL_RICOCHET := 1
const ROLL_GRAZE := 2
const ROLL_COVERAGE := 16
const ROLL_SLAT := 17
const ROLL_TRIGGER := 18
const ROLL_PER_TILE := 8
## Vehicle metadata the host keeps the armour's state in until phase A2/A7 move it into the
## vehicle's net state: fitted packages (Array of ids; phase A8 fits them) and used tiles
## ({group: PackedByteArray, 1 = fired or torn off}).
const META_PACKAGES := &"armour_packages"
const META_TILES := &"armour_tiles"


# --- The pure model ------------------------------------------------------------------------

## Resolves `shell` (Shells.shell) against `plate` (a plates entry). `hit`: "dir" (the round's
## direction in the plate's frame, required), "range_m" (flown, for pen_ke; default 0),
## "check_arming" (true: a fuzed round closer than its arming_m is a dud), "seed" (int),
## "tiles" (tiles_at: the tiles over the point, outermost first), "fuze_mode" (a mode of the
## shell's fuze: "air", "delay", "airburst"), "airburst_m" (the set burst range), "force"
## ({"coverage", "trigger", "ricochet": bool; "graze": "dud"/"half"; "slat": "dud"/"burst"}:
## tests pin a roll). Returns the HitResult (2.3.3): "outcome" (RICOCHET, SHATTER, NON_PEN, PEN,
## DUD, FUZED_OUTSIDE), "shell", "plate", "material", "column" (ke, ce, he), "fuze", "burst"
## (none, outside, inside, air), "theta_deg", "theta_n_deg", "overmatch", "pen", "t_eff",
## "residual", "partial", "tile" (the tile kind that mattered), "tiles_fired" ([[group, index]]),
## "ricochet_dir", "speed_frac", "seed".
static func resolve(shell: Dictionary, plate: Dictionary, hit: Dictionary) -> Dictionary:
	var dir: Vector3 = (hit.get("dir", Vector3.FORWARD) as Vector3).normalized()
	var force: Dictionary = hit.get("force", {})
	var seed := int(hit.get("seed", 0))
	var kind := String(shell.get("kind", "he"))
	var column := "ke" if kind in Shells.KE_KINDS else ("ce" if kind in Shells.CE_KINDS else "he")
	var n := normal_of(plate, dir)
	var cos_t := (-dir).dot(n)
	var theta := rad_to_deg(acos(clampf(cos_t, -1.0, 1.0))) if cos_t > 0.0001 else 89.9
	var range_m := float(hit.get("range_m", 0.0))
	var fuze: Dictionary = shell.get("fuze", {"kind": "none"})
	var mode := String(hit.get("fuze_mode", ""))
	if mode != "" and (fuze.get("modes", {}) as Dictionary).has(mode):
		fuze = fuze.modes[mode]
	var fk := String(fuze.get("kind", "none"))
	var out := {"outcome": NON_PEN, "shell": shell.get("id", &""), "plate": String(plate.get("id", "")),
		"material": String(plate.get("material", "rha")), "column": column, "fuze": fk, "burst": "none",
		"theta_deg": theta, "theta_n_deg": theta, "overmatch": false, "pen": 0.0, "t_eff": 0.0, "residual": 0.0,
		"partial": false, "tile": "", "tiles_fired": [], "ricochet_dir": Vector3.ZERO, "speed_frac": 1.0, "seed": seed}
	# Fuzes before the plate (2.3.7).
	if fk != "none":
		if bool(hit.get("check_arming", false)) and range_m < float(shell.get("arming_m", 0.0)):
			out.outcome = DUD  # hit before it armed: only its KE, which a plate shrugs off
			out.burst = "none"
			return out
		if float(fuze.get("self_destruct_m", 0.0)) > 0.0 and range_m > float(fuze.self_destruct_m):
			out.outcome = DUD  # it went off in the air on its way
			out.burst = "air"
			return out
		if fk == "proximity" or (fk == "airburst" and hit.has("airburst_m") and range_m >= float(hit.airburst_m) + float(fuze.get("offset_m", 0.0))):
			out.outcome = FUZED_OUTSIDE  # burst short of the hull: blast only, no jet into it
			out.burst = "air" if fk == "airburst" else "outside"
			return out
	var tandem := kind == "tandem_heat" or fk == "tandem"
	var pen_mult := 1.0
	var era_ce := 0.0
	var era_ke := 0.0
	var calibre := float(shell.get("calibre_mm", 0.0))
	var he_kg := float(shell.get("he_kg", 0.0))
	# The outer layer: slat, then reactive tiles (2.4.4). A used tile is a hole; a missed
	# coverage roll is a gap: either way the round meets the plate.
	var tiles: Array = hit.get("tiles", [])
	for ti in tiles.size():
		var t: Dictionary = tiles[ti]
		if bool(t.get("used", false)):
			continue
		var covered: bool = force.coverage if force.has("coverage") else roll(seed, ROLL_COVERAGE + ti * ROLL_PER_TILE) < float(t.get("coverage", 1.0))
		if not covered:
			continue
		var tkind := String(t.get("kind", ""))
		if tkind == "slat":
			if column == "ke":
				continue  # KE goes straight through a cage
			(out.tiles_fired as Array).append([t.group, int(t.get("index", 0))])
			out.tile = "slat"
			if column == "he":
				out.outcome = FUZED_OUTSIDE  # an HE rocket bursts on the cage
				out.burst = "outside"
				return out
			if bool(shell.get("rocket", false)):
				var shorted: bool = (String(force.slat) == "dud") if force.has("slat") else roll(seed, ROLL_SLAT + ti * ROLL_PER_TILE) < SLAT_SHORT_CHANCE
				if shorted:
					(out.tiles_fired as Array).pop_back()  # caught in the bars, not burst: the panel stays
					out.outcome = DUD
					return out
			pen_mult *= SLAT_PEN_MULT  # burst on the slat: the jet forms at the wrong standoff
			continue
		if not ERA.has(tkind):
			continue
		var trigger := false
		match column:
			"ce":
				trigger = calibre >= ERA_CE_MIN_MM
			"ke":
				trigger = calibre >= ERA_KE_MIN_MM and ((bool(force.trigger)) if force.has("trigger") else roll(seed, ROLL_TRIGGER + ti * ROLL_PER_TILE) < ERA_KE_CHANCE)
			"he":
				trigger = he_kg >= ERA_HE_MIN_KG and ((bool(force.trigger)) if force.has("trigger") else roll(seed, ROLL_TRIGGER + ti * ROLL_PER_TILE) < ERA_HE_CHANCE)
		if not trigger:
			continue
		(out.tiles_fired as Array).append([t.group, int(t.get("index", 0))])
		out.tile = tkind
		var e: Dictionary = ERA[tkind]
		if column == "ce":
			era_ce = float(e.ce_tandem) if tandem else float(e.ce)  # a tandem's precursor sets light and heavy tiles off
		elif column == "ke":
			if kind in ERA_KE_KINDS:
				era_ke += float(e.ke)
			if calibre >= AUTOCANNON_MM.x and calibre <= AUTOCANNON_MM.y:
				era_ke += float(e.ke_autocannon)
		break  # one reactive tile per hit
	var composite := bool(plate.get("composite", false))
	var phys := float(plate.get("phys_mm", plate.get("ke_mm", 0.0)))
	match column:
		"ke":
			var overmatch := calibre >= float(shell.get("overmatch", 3.0)) * phys
			var theta_n := maxf(0.0, theta - float(shell.get("normalise_deg", 0.0)))
			out.overmatch = overmatch
			if overmatch:
				theta_n = minf(theta_n, OVERMATCH_MAX_DEG)
			elif _ricochets(shell.get("ricochet_deg", []), theta, force, seed):
				return _ricochet(out, dir, n)
			out.theta_n_deg = theta_n
			out.pen = Shells.pen_ke(shell, range_m)
			out.t_eff = los(float(plate.get("ke_mm", 0.0)), theta_n, composite) + los(era_ke, theta_n, false)
			if out.pen > out.t_eff:
				out.outcome = PEN
				out.residual = out.pen - out.t_eff
			else:
				out.outcome = NON_PEN
				out.partial = out.pen > PARTIAL_SHARE * out.t_eff
				if out.pen < SHATTER_SHARE * out.t_eff and String(out.material) in SHATTER_MATERIALS and kind in SHATTER_KINDS:
					out.outcome = SHATTER
		"ce":
			if fk in ["piezo", "tandem"] and theta > float(fuze.get("graze_deg", GRAZE_DEG)):
				var g := String(force.graze) if force.has("graze") else ("dud" if roll(seed, ROLL_GRAZE) < GRAZE_DUD_CHANCE else "half")
				if g == "dud":
					out.outcome = DUD  # glanced off: the fuze never crushed
					return out
				pen_mult *= GRAZE_PEN_MULT  # burst in the wrong place
			var spaced := float(plate.get("spaced_mm", 0.0))
			if spaced > 0.0:
				pen_mult *= 1.0 - minf(SPACED_MAX, spaced * SPACED_PER_MM)
			out.pen = float(shell.get("pen_ce", 0.0)) * pen_mult
			out.t_eff = los(float(plate.get("ce_mm", 0.0)), theta, composite) + los(era_ce, theta, false)
			out.burst = "outside"  # the filling bursts on the hull; the jet goes on
			if out.pen > out.t_eff:
				out.outcome = PEN
				out.residual = out.pen - out.t_eff
			elif he_kg > 0.0 and _he_punches(out, he_kg, phys, theta):
				pass  # the jet failed but the filling blew the thin plate in (HEDP, AMP on light armour)
			else:
				out.outcome = NON_PEN
		"he":
			if fk == "pd" and phys < float(fuze.get("sensitivity_mm", SENSITIVITY_MM)):
				out.outcome = PEN  # too thin to fire the fuze: it goes in and bursts on what's inside
				out.burst = "inside"
				return out
			if fk == "pd_delay" and _ricochets(shell.get("ricochet_deg", []), theta, force, seed):
				_ricochet(out, dir, n)
				out.burst = "outside"  # skips off and bursts beside the hull
				return out
			if not _he_punches(out, he_kg, phys, theta):
				out.outcome = NON_PEN
				out.burst = "outside"
	return out


## A roll in [0, 1) from `seed` and `salt`: the same pair always rolls the same (a host and a
## replay agree), and costs a hash, not a RandomNumberGenerator.
static func roll(seed: int, salt: int) -> float:
	return float(hash(seed * 1000003 + salt) & 0xFFFFFF) / 16777216.0


## The plate's normal (its "normal" in data, normalised), or head-on to `dir` for "any".
static func normal_of(plate: Dictionary, dir: Vector3) -> Vector3:
	var n: Variant = plate.get("normal", "any")
	if typeof(n) != TYPE_ARRAY:
		return -dir.normalized()
	var v := VehicleSpecs.vec(n, -dir)
	return v.normalized() if v.length_squared() > 0.000001 else -dir.normalized()


## Line-of-sight thickness of `t` mm at `theta_deg` from the normal (capped, 2.3.2).
static func los(t: float, theta_deg: float, composite := false) -> float:
	if t <= 0.0:
		return 0.0
	var c := cos(deg_to_rad(clampf(theta_deg, 0.0, 89.99)))
	return t * minf(1.0 / maxf(c, 0.0001), LOS_CAP_COMPOSITE if composite else LOS_CAP)


## HE punch-through (2.3.6) on `out`: true (and out set to a penetration that bursts inside)
## when the filling blows in the plate's physical thickness at this angle.
static func _he_punches(out: Dictionary, he_kg: float, phys: float, theta: float) -> bool:
	var pen_he := HE_PEN_K * pow(maxf(he_kg, 0.0), 1.0 / 3.0)
	var t := los(phys, theta)
	if out.column == "he":
		out.pen = pen_he
		out.t_eff = t
	if pen_he <= t:
		return false
	out.outcome = PEN
	out.column = "he"
	out.pen = pen_he
	out.t_eff = t
	out.residual = pen_he - t
	out.burst = "inside"
	return true


static func _ricochets(band: Variant, theta: float, force: Dictionary, seed: int) -> bool:
	if typeof(band) != TYPE_ARRAY or (band as Array).size() < 2:
		return false
	var lo := float(band[0])
	var hi := float(band[1])
	if theta <= lo:
		return false
	if force.has("ricochet"):
		return bool(force.ricochet)
	return theta >= hi or roll(seed, ROLL_RICOCHET) < (theta - lo) / maxf(hi - lo, 0.001)


static func _ricochet(out: Dictionary, dir: Vector3, n: Vector3) -> Dictionary:
	out.outcome = RICOCHET
	out.ricochet_dir = dir.bounce(n).normalized()
	out.speed_frac = RICOCHET_SPEED
	return out


# --- Plates and tiles on a model ------------------------------------------------------------

## The plate a hit at `local` (vehicle frame) flying along `ldir` meets on `spec`: the first in
## the list whose box holds it, whose normal faces the round and agrees with `face` (the voxel
## face it met, Vector3.ZERO when unknown); else the first that faces it; else the first that
## holds it; {} when none does (the zone's armour class decides, so a gap in authoring is never
## a hole in the tank).
static func plate_at(spec: Dictionary, local: Vector3, ldir: Vector3, face := Vector3.ZERO) -> Dictionary:
	var facing := {}
	var holding := {}
	for p: Dictionary in spec.get("plates", []):
		if not VehicleSpecs.box(p.box).grow(PLATE_GROW).has_point(local):
			continue
		if holding.is_empty():
			holding = p
		var n := normal_of(p, ldir)
		if n.dot(-ldir) <= 0.0:
			continue
		if face != Vector3.ZERO and typeof(p.get("normal")) == TYPE_ARRAY and n.dot(face) < FACE_AGREE:
			if facing.is_empty():
				facing = p
			continue
		return p
	return facing if not facing.is_empty() else holding


## The tiles of `spec` over `local` that are fitted with `packages` (an Array of package ids),
## outermost (slat) first: [{"group", "kind", "index" (the tile along the group's box), "coverage",
## "used" (from `used`: {group: PackedByteArray}), "normal"}].
static func tiles_at(spec: Dictionary, local: Vector3, packages: Array = [], used: Dictionary = {}) -> Array:
	var fitted := fitted_packages(spec, packages)
	var slats: Array = []
	var era: Array = []
	for t: Dictionary in spec.get("tiles", []):
		if not tile_fitted(t, fitted):
			continue
		var box := VehicleSpecs.box(t.box)
		if not box.grow(PLATE_GROW).has_point(local):
			continue
		var count := maxi(int(t.get("count", 1)), 1)
		var axis := box.get_longest_axis_index()
		var index := clampi(floori((local[axis] - box.position[axis]) / maxf(box.size[axis], 0.001) * count), 0, count - 1)
		var flags: PackedByteArray = used.get(String(t.group), PackedByteArray())
		var entry := {"group": String(t.group), "kind": String(t.kind), "index": index, "coverage": float(t.get("coverage", 1.0)),
			"used": index < flags.size() and flags[index] != 0, "normal": t.get("normal", "any")}
		if String(t.kind) == "slat":
			slats.append(entry)
		else:
			era.append(entry)
	return slats + era


## `packages` plus what they include (spec.packages[id].includes).
static func fitted_packages(spec: Dictionary, packages: Array) -> Array:
	var out: Array = []
	var defs: Dictionary = spec.get("packages", {})
	for p: Variant in packages:
		var id := String(p)
		if not id in out:
			out.append(id)
		for inc: Variant in (defs.get(id, {}) as Dictionary).get("includes", []):
			if not String(inc) in out:
				out.append(String(inc))
	return out


## `plate` with what `fitted` packages (fitted_packages) bolt onto it: each package's
## "plates_add" {plate id: [ke_mm, ce_mm]} added to its figures (the M-ATV and MaxxPro
## appliqué). The plate itself when nothing is added (no copy).
static func with_packages(plate: Dictionary, spec: Dictionary, fitted: Array) -> Dictionary:
	var out := plate
	var defs: Dictionary = spec.get("packages", {})
	for id: Variant in fitted:
		var add: Variant = ((defs.get(String(id), {}) as Dictionary).get("plates_add", {}) as Dictionary).get(String(plate.get("id", "")))
		if typeof(add) != TYPE_ARRAY or (add as Array).size() < 2:
			continue
		if is_same(out, plate):
			out = plate.duplicate()
		out["ke_mm"] = float(out.get("ke_mm", 0.0)) + float(add[0])
		out["ce_mm"] = float(out.get("ce_mm", 0.0)) + float(add[1])
	return out


## Whether tile group `t` is on the vehicle with `fitted` packages (fitted_packages).
static func tile_fitted(t: Dictionary, fitted: Array) -> bool:
	for r: Variant in t.get("removed_by", []):
		if String(r) in fitted:
			return false
	var need: Variant = t.get("package", "")
	if typeof(need) == TYPE_ARRAY:
		for p: Variant in need:
			if String(p) in fitted:
				return true
		return false
	return String(need) == "" or String(need) in fitted


# --- On a real vehicle (host) ---------------------------------------------------------------

## The shell a server_take_hit dictionary carries: "shell" (a gun round, phase A3), "warhead"
## (Warheads.server_burst), or the Ballistics round's shells.json row; {} for none.
static func shell_of(hit: Dictionary) -> Dictionary:
	if hit.has("shell"):
		return Shells.shell(hit.shell)
	if hit.has("warhead"):
		return Shells.shell(hit.warhead)
	if hit.has("round"):
		var id := Shells.for_round(hit.round)
		if id != &"":
			return Shells.shell(id)
	return {}


## Host: resolves `hit` (Vehicle.server_take_hit's dictionary) on `vehicle`, a model with
## plates, at `local` (where it met the hull's voxels) flying along `ldir` (vehicle frame), in
## zone `zone` (VehicleDamage.zone_at). Returns VehicleDamage.resolve's dictionary, with the
## HitResult under "armour" when the armour model decided it.
static func vehicle_hit(vehicle: Vehicle, hit: Dictionary, zone: Dictionary, local: Vector3, ldir: Vector3) -> Dictionary:
	var shell := shell_of(hit)
	if shell.is_empty():
		return VehicleDamage.resolve(hit, zone, ldir)
	var spec: Dictionary = vehicle.spec
	var plate := plate_at(spec, local, ldir, face_of(vehicle.hull, local, ldir))
	if plate.is_empty():
		return VehicleDamage.resolve(hit, zone, ldir)
	plate = with_packages(plate, spec, fitted_packages(spec, vehicle.get_meta(META_PACKAGES, [])))  # appliqué (cg_brief 2.0)
	var at := vehicle.to_global(local)
	var range_m := float(hit.get("range_m", 0.0))
	var shooter: Variant = hit.get("shooter")
	if not hit.has("range_m") and shooter is Node3D and is_instance_valid(shooter):
		range_m = (shooter as Node3D).global_position.distance_to(at)
	var shot_id: Variant = hit.get("shot_id", hash([snapped(at, Vector3.ONE * 0.001), Engine.get_physics_frames()]))
	var used: Dictionary = vehicle.get_meta(META_TILES, {})
	var shot := {"dir": ldir, "range_m": range_m, "check_arming": hit.has("range_m"), "fuze_mode": String(hit.get("fuze_mode", "")),
		"seed": hash([shot_id, String(vehicle.name), String(plate.id)]),
		"tiles": tiles_at(spec, local, vehicle.get_meta(META_PACKAGES, []), used)}
	if hit.has("airburst_m"):
		shot.airburst_m = hit.airburst_m
	if hit.has("force"):
		shot.force = hit.force
	var res := resolve(shell, plate, shot)
	res["range_m"] = range_m  # (A5: the x-ray's "at 640 m")
	for f: Array in res.tiles_fired:
		var flags: PackedByteArray = used.get(f[0], PackedByteArray())
		if flags.size() <= int(f[1]):
			flags.resize(int(f[1]) + 1)
		flags[int(f[1])] = 1
		used[f[0]] = flags
	if not (res.tiles_fired as Array).is_empty():
		vehicle.set_meta(META_TILES, used)
	var d := damage(res, shell, zone, hit)
	if vehicle.modules and vehicle.modules.authored:  # A2: what it does inside (the path, spall, a burst)
		VehicleModules.plan(vehicle.modules.mods, d, shell, local, ldir, hit,
			VehicleModules.has_liner(spec, vehicle.get_meta(META_PACKAGES, [])))
	return d


## The voxel face (an axis normal, vehicle frame) a round along `ldir` met at `local` on
## `hull`: the axis it crossed into the voxel on; the round's main axis for a turret or gun part
## (their voxels are at rest, not where they are) or when the hull isn't known.
static func face_of(hull: VehicleHull, local: Vector3, ldir: Vector3) -> Vector3:
	var axis := ldir.abs().max_axis_index()
	if hull != null and VehicleHull.is_ready(hull.model):
		var v := hull.voxel_of(local)
		if hull.solid(v):
			var step := float(VehicleHull.canvas(hull.model).vs) * 0.4
			var d := v - hull.voxel_of(local - ldir * step)
			var best := -1.0
			for i in 3:
				if d[i] != 0 and absf(ldir[i]) > best:
					best = absf(ldir[i])
					axis = i
	var face := Vector3.ZERO
	face[axis] = -signf(ldir[axis]) if ldir[axis] != 0.0 else 1.0
	return face


## A HitResult `res` for `shell` in zone `zone` as the damage dictionary Vehicle._apply_damage
## takes (VehicleDamage.resolve's shape: stopped, penetrated, damage_kj, energy_left,
## fire_chance, spall, crew_blast), plus "armour": `res`. Phase A1's bridge to the zones; A2's
## modules replace it.
static func damage(res: Dictionary, shell: Dictionary, zone: Dictionary, hit: Dictionary) -> Dictionary:
	var out := {"stopped": true, "penetrated": false, "damage_kj": 0.0, "energy_left": 0.0, "fire_chance": 0.0, "spall": false, "crew_blast": 0.0, "armour": res}
	var cls := VehicleSpecs.armour(String(zone.get("armour", "soft")))
	var chances: Array = VehicleDamage.FIRE_CHANCE.get(zone.get("zone", &"hull"), [0.0, 0.0])
	var he_kg := float(shell.get("he_kg", 0.0))
	var thermobaric := String(shell.get("kind", "")) == "thermobaric"
	var module_dmg := float(shell.get("module_dmg", 0.0))
	var outcome: StringName = res.outcome
	var column := String(res.column)
	if outcome == PEN:
		out.penetrated = true
		match column:
			"ke":
				out.damage_kj = module_dmg
				var energy := float(hit.get("energy_j", 0.0))
				out.energy_left = energy * clampf(float(res.residual) / maxf(float(res.pen), 0.001), 0.0, 1.0)
				out.stopped = out.energy_left <= 0.0
				out.fire_chance = float(chances[0]) * (INCENDIARY_FIRE_MULT if bool(shell.get("incendiary", false)) else 1.0)
				out.spall = float(shell.get("calibre_mm", 0.0)) >= KE_SPALL_MIN_MM
			"ce":
				out.damage_kj = module_dmg
				out.fire_chance = float(chances[1])
				out.spall = true
			_:
				out.damage_kj = (VehicleDamage.THERMOBARIC_PER_KG if thermobaric else VehicleDamage.HE_PER_KG) * he_kg
				out.fire_chance = float(chances[1]) * 0.5
				out.spall = not thermobaric
				out.crew_blast = 1.0 if thermobaric else 0.0
		return out
	if outcome == DUD or outcome == RICOCHET or outcome == SHATTER:
		return out
	# Stopped outside: a KE backface bulge, or the filling's blast on the hull (as before).
	if column == "ke":
		if bool(res.partial):
			out.damage_kj = PARTIAL_DMG * module_dmg
	elif column == "ce":
		out.damage_kj = VehicleDamage.HEAT_STOPPED_PER_KG * he_kg * float(cls.blast)
	else:
		out.damage_kj = (VehicleDamage.THERMOBARIC_PER_KG if thermobaric else VehicleDamage.HE_PER_KG) * he_kg * float(cls.blast)
		if thermobaric:
			out.crew_blast = clampf(float(cls.blast) * 2.0, 0.0, 1.0)
	return out
