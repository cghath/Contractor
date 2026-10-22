class_name PerfWarm
extends RefCounted
## What a zone warms up as it starts (perf pass, Captain 2026-10-22: "we definitely need more
## performance fixes"; docs/performance.md), so the first soldier of each look doesn't rasterise
## his uniform on the main thread mid-game (0.4-0.6 s each, tests/perf_spawn.tscn).
## PeopleLayer already warms the hostiles' urban kit and plain clothes; this adds the company's
## uniform and the uniforms and guns of the factions holding and attacking the zone, both bodies,
## on a worker (VoxelArt.warm: each look once a session).

## Effects drawn once, tiny, in front of the camera in the zone's first frames, so their shaders'
## pipelines are compiled before the first shot (a first tracer, impact, burst or smoke cloud
## compiled on its first draw: a hitch mid-firefight). Not on a headless server.
const EFFECT_FRAMES := 3


## The men of a faction's kit looked at (their uniform, clothes and guns go by their index).
const KIT_MEN := 8


## Warms what `level`'s soldiers will be built from.
static func warm_zone(level: ZoneLevel) -> void:
	var art: Array = []
	var factions: Array[String] = []
	for f: String in [String(level._enemy_response.enemy_faction) if level._enemy_response else "", level._zone_attacker(), FactionSkirmish.DEFAULT_HOLDER]:
		if f != "" and not f in factions:
			factions.append(f)
	for body: String in VoxelArt.BODIES:
		_add(art, VoxelArt.uniform(Soldier.COMPANY_VARIANT, Roles.kit(Roles.RIFLEMAN).map(func(pair: Array) -> String: return String(pair[0])), body))
		for f in factions:
			var kit_id := Kits.kit_of(f)
			for i in KIT_MEN:
				var loadout: Array = Kits.loadout(kit_id, i) if Kits.is_data(kit_id) else CompoundLevel.hostile_loadout(i)
				_add(art, VoxelArt.uniform(Kits.variant(kit_id, i), loadout, body))
	VoxelArt.warm(art)


## Adds the effect warm-up to `level` (see EFFECT_FRAMES).
static func warm_effects(level: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var warm := EffectWarm.new()
	warm.name = "EffectWarm"
	level.add_child(warm)


class EffectWarm extends Node3D:
	var _frames := 0

	func _ready() -> void:
		top_level = true
		var looks: Array = [Tracer.material(Tracer.Kind.RED, false), Tracer.material(Tracer.Kind.BALL, false),
			CompoundLevel._effect_material(Color.YELLOW, false), CompoundLevel._effect_material(Color(1.0, 0.6, 0.25), true)]
		var smoke := StandardMaterial3D.new()  # (as SmokeCloud's: lit, alpha)
		smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smoke.roughness = 1.0
		looks.append(smoke)
		for m: Material in looks:
			var mi := MeshInstance3D.new()
			mi.mesh = Tracer.unit_box()
			mi.material_override = m
			mi.scale = Vector3.ONE * 0.001
			add_child(mi)

	func _process(_delta: float) -> void:
		var camera := get_viewport().get_camera_3d()
		if camera == null:
			return
		global_transform = camera.global_transform.translated_local(Vector3(0, 0, -0.5))
		_frames += 1
		if _frames >= EFFECT_FRAMES:
			queue_free()


static func _add(into: Array, pairs: Array) -> void:
	for p: Array in pairs:
		if not into.has(p):
			into.append(p)
