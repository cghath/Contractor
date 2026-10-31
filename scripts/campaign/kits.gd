class_name Kits
extends RefCounted
## What each enemy faction fields (wave 6b, 2026-10-18): data/factions.json "kits", a faction's
## "kit". A data kit is body + one of its "guns" by "mix" (a team, wave or garrison's i-th man
## gets mix[i % size]) + tail, with "roles" casting a gun's carrier (Roles), "variant" his camo
## and optional "combat"/"discipline". Any gun a faction is known to field goes in its kit, AR-
## pattern rifles included (Captain, 2026-10-18). Two kits stay in code because they have more
## than a list: "insurgent" (Black Ridge: CompoundLevel.hostile_loadout) and "pmc" (Vantage:
## CompoundLevel.rival_pmc_loadout, its exo gear by difficulty).

const INSURGENT := "insurgent"
const PMC := "pmc"


## The kit id `faction` fields in `zone_id` ("insurgent" without one). A faction can field a
## different kit by region ("regional_kits", region id -> kit) or for one zone ("zone_kits",
## zone id -> kit, which wins): the Eastern Concord Forces' Russian, Iranian or Chinese kit
## (wave 6b call 4, Captain 2026-10-18). `zone_id` "" means the zone being played now.
static func kit_of(faction: Variant, zone_id := "") -> String:
	var f := MissionRegistry.faction(String(faction))
	if zone_id == "":
		zone_id = _current_zone()
	if zone_id != "":
		var by_zone: Dictionary = f.get("zone_kits", {})
		if by_zone.has(zone_id):
			return String(by_zone[zone_id])
		var region := String(MissionRegistry.zone(zone_id).get("region", ""))
		var by_region: Dictionary = f.get("regional_kits", {})
		if by_region.has(region):
			return String(by_region[region])
	return String(f.get("kit", INSURGENT))


## The nationality `kit_id`'s men are from (Names; a data kit's "nation"), or "" to leave it to
## the faction's own.
static func nation(kit_id: String) -> String:
	return String(data(kit_id).get("nation", ""))


static func _current_zone() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState") if tree else null
	return String(gs.get("zone_id")) if gs else ""


## A data kit's entry ({} for the code kits or an unknown id).
static func data(kit_id: String) -> Dictionary:
	MissionRegistry.factions()
	return (MissionRegistry._factions.get("kits", {}) as Dictionary).get(kit_id, {})


## Whether `kit_id` is one of the data kits (not Black Ridge's or Vantage's code kit).
static func is_data(kit_id: String) -> bool:
	return not data(kit_id).is_empty()


## A data kit's man-by-man gun list: its "mix", or one of its other "mixes" by name (the allied
## kits' "weapons_team", wave 6e). [] for none.
static func mix(kit_id: String, mix_name := "") -> Array:
	var k := data(kit_id)
	if mix_name != "":
		return (k.get("mixes", {}) as Dictionary).get(mix_name, [])
	return k.get("mix", [])


## The `index`-th man's kit (item ids) for `kit_id`, at contract `difficulty` (1-5); `mix_name`
## picks one of a data kit's other "mixes" (mix()).
static func loadout(kit_id: String, index: int, difficulty := 1, mix_name := "") -> Array:
	match kit_id:
		PMC:
			return CompoundLevel.rival_pmc_loadout(index, difficulty)
		INSURGENT:
			return CompoundLevel.hostile_loadout(index)
	var k := data(kit_id)
	if k.is_empty():
		return CompoundLevel.hostile_loadout(index)
	var m := mix(kit_id, mix_name)
	var guns: Dictionary = k.get("guns", {})
	var gun: Array = guns.get(String(m[posmod(index, m.size())]), []) if not m.is_empty() else []
	return (k.get("body", []) as Array) + gun + (k.get("tail", []) as Array)


## The AI role the `index`-th man of `kit_id` spawns with ("" for none).
static func role(kit_id: String, index: int, mix_name := "") -> String:
	match kit_id:
		PMC:
			return CompoundLevel.rival_pmc_role(index)
		INSURGENT:
			return CompoundLevel.hostile_role(index)
	var m := mix(kit_id, mix_name)
	if m.is_empty():
		return ""
	return String((data(kit_id).get("roles", {}) as Dictionary).get(String(m[posmod(index, m.size())]), ""))


## The camo `kit_id` wears.
static func variant(kit_id: String) -> String:
	match kit_id:
		PMC:
			return "black"
		INSURGENT:
			return "urban"
	return String(data(kit_id).get("variant", "urban"))


## The exo `kit_id`'s `index`-th man wears at `difficulty` ("" for none; Vantage only for now).
static func exo_at(kit_id: String, index: int, difficulty: int) -> String:
	return CompoundLevel.rival_pmc_exo_at(index, difficulty) if kit_id == PMC else ""
