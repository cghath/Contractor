class_name PerfWarm
extends RefCounted
## What a zone warms up as it starts (perf pass, Captain 2026-10-22: "we definitely need more
## performance fixes"; docs/performance.md), so the first soldier of each look doesn't rasterise
## his uniform on the main thread mid-game (0.4-0.6 s each, tests/perf_spawn.tscn).
## PeopleLayer already warms the hostiles' urban kit and plain clothes; this adds the company's
## uniform and the uniforms and guns of the factions holding and attacking the zone, both bodies,
## on a worker (VoxelArt.warm: each look once a session).

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


static func _add(into: Array, pairs: Array) -> void:
	for p: Array in pairs:
		if not into.has(p):
			into.append(p)
