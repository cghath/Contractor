extends Node
## How open the campaign zones are (Captain, 2026-10-18: "we need to not have so many 300m
## sightlines"). Headless, no level hosted: each zone's terrain and scatter are generated as
## ZoneLevel does, then SAMPLES eye points (EYE_M over the ground, anywhere off the pads) look
## DIRECTIONS ways to a man's chest (CHEST_M up) at each of RANGES_M. A line counts as clear
## when no ground rises into it (checked every STEP_M) and less than Spotting.FOLIAGE_OPAQUE_M
## of foliage lies on it (ZoneScatter.foliage_between: what the AI's spotting uses). Buildings
## and trunks aren't counted: this is the open country between the sites.
##   <voxel godot exe> --headless --path . res://tests/sightline_probe.tscn [-- zone_id ...]
## Prints one line per zone and preset; exits 0.

const SAMPLES := 160
const DIRECTIONS := 12
const RANGES_M: Array[float] = [150.0, 200.0, 300.0]
const EYE_M := 1.6
const CHEST_M := 1.2
const STEP_M := 5.0
const EDGE_M := 120.0


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void: get_tree().quit(2))  # never idle forever
	await get_tree().process_frame
	var only := OS.get_cmdline_user_args()
	var totals := {}
	for z: Dictionary in MissionRegistry.zones():
		var id := String(z.zone_id)
		if not only.is_empty() and id not in only:
			continue
		var def := MissionRegistry.zone_def(id)
		if def.is_empty():
			continue
		var r := probe(def)
		print("[sightlines] %-36s %-20s %s" % [id, String(def.get("terrain", "?")), _fmt(r)])
		for k: float in r:
			totals[k] = totals.get(k, 0.0) + float(r[k])
		totals["n"] = int(totals.get("n", 0)) + 1
		await get_tree().process_frame
	if int(totals.get("n", 0)) > 0:
		var avg := {}
		for k: float in RANGES_M:
			avg[k] = float(totals[k]) / int(totals.n)
		print("[sightlines] %-36s %-20s %s" % ["ALL (%d zones)" % int(totals.n), "", _fmt(avg)])
	get_tree().quit(0)


## Share of clear lines at each of RANGES_M (range -> 0..1) on zone `def`.
static func probe(def: Dictionary) -> Dictionary:
	var terrain := ZoneTerrain.new()
	terrain.generate(def, _flat_areas(def))
	var scatter := ZoneScatter.new()
	scatter.generate(terrain, def)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(def.get("seed", 1)) + 4242
	var half := float(def.get("size_m", 1536.0)) * 0.5 - EDGE_M
	var pads := _flat_areas(def)
	var clear := {}
	var lines := 0
	var tried := 0
	while lines < SAMPLES * DIRECTIONS and tried < SAMPLES * 20:
		tried += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if pads.any(func(p: Rect2) -> bool: return p.grow(10.0).has_point(Vector2(x, z))) or terrain.height_at(x, z) < 0.5:
			continue  # off the pads, out of the sea
		var eye := Vector3(x, terrain.height_at(x, z) + EYE_M, z)
		var a0 := rng.randf() * TAU
		for d in DIRECTIONS:
			var a := a0 + TAU * d / DIRECTIONS
			var dir := Vector3(cos(a), 0.0, sin(a))
			lines += 1
			for range_m: float in RANGES_M:
				var t := eye + dir * range_m
				t.y = terrain.height_at(t.x, t.z) + CHEST_M
				if _clear(terrain, scatter, eye, t):
					clear[range_m] = int(clear.get(range_m, 0)) + 1
	var out := {}
	for range_m: float in RANGES_M:
		out[range_m] = float(clear.get(range_m, 0)) / maxf(lines, 1.0)
	terrain.free()
	scatter.free()
	return out


static func _clear(terrain: ZoneTerrain, scatter: ZoneScatter, eye: Vector3, to: Vector3) -> bool:
	var length := Vector2(to.x - eye.x, to.z - eye.z).length()
	var steps := int(length / STEP_M)
	for i in range(1, steps):
		var p := eye.lerp(to, float(i) / steps)
		if terrain.height_at(p.x, p.z) > p.y:
			return false
	return scatter.foliage_between(eye, to) < Spotting.FOLIAGE_OPAQUE_M


static func _flat_areas(def: Dictionary) -> Array:
	var out: Array = []
	for m: Dictionary in def.get("modules", []):
		var half: Vector2 = ZoneModules.HALF.get(String(m.type), Vector2(20, 20))
		var p := Vector2(float(m.pos[0]), float(m.pos[1]))
		out.append(Rect2(p - half, half * 2.0))
	for p: Array in def.get("extraction", []):
		out.append(Rect2(float(p[0]) - 12.0, float(p[1]) - 12.0, 24.0, 24.0))
	for p: Array in def.get("insertion", []):
		out.append(Rect2(float(p[0]) - 8.0, float(p[1]) - 8.0, 16.0, 16.0))
	return out


static func _fmt(r: Dictionary) -> String:
	var parts: Array[String] = []
	for k: float in RANGES_M:
		parts.append("%d m: %2d%% clear" % [int(k), roundi(float(r.get(k, 0.0)) * 100.0)])
	return ", ".join(parts)
