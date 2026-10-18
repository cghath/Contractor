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


## The kit id `faction` fields ("insurgent" without one).
static func kit_of(faction: Variant) -> String:
	return String(MissionRegistry.faction(String(faction)).get("kit", INSURGENT))


## A data kit's entry ({} for the code kits or an unknown id).
static func data(kit_id: String) -> Dictionary:
	MissionRegistry.factions()
	return (MissionRegistry._factions.get("kits", {}) as Dictionary).get(kit_id, {})


## Whether `kit_id` is one of the data kits (not Black Ridge's or Vantage's code kit).
static func is_data(kit_id: String) -> bool:
	return not data(kit_id).is_empty()


## The `index`-th man's kit (item ids) for `kit_id`, at contract `difficulty` (1-5).
static func loadout(kit_id: String, index: int, difficulty := 1) -> Array:
	match kit_id:
		PMC:
			return CompoundLevel.rival_pmc_loadout(index, difficulty)
		INSURGENT:
			return CompoundLevel.hostile_loadout(index)
	var k := data(kit_id)
	if k.is_empty():
		return CompoundLevel.hostile_loadout(index)
	var mix: Array = k.get("mix", [])
	var guns: Dictionary = k.get("guns", {})
	var gun: Array = guns.get(String(mix[posmod(index, mix.size())]), []) if not mix.is_empty() else []
	return (k.get("body", []) as Array) + gun + (k.get("tail", []) as Array)


## The AI role the `index`-th man of `kit_id` spawns with ("" for none).
static func role(kit_id: String, index: int) -> String:
	match kit_id:
		PMC:
			return CompoundLevel.rival_pmc_role(index)
		INSURGENT:
			return CompoundLevel.hostile_role(index)
	var k := data(kit_id)
	var mix: Array = k.get("mix", [])
	if mix.is_empty():
		return ""
	return String((k.get("roles", {}) as Dictionary).get(String(mix[posmod(index, mix.size())]), ""))


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
