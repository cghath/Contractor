class_name FactionVehicles
extends RefCounted
## Combined arms D6b (cg_brief queue item 4.2; docs/combined_arms.md 7.1): which vehicles a
## faction fields, from its "vehicles" block in data/factions.json, read by everything that
## spawns the enemy's vehicles: VehicleQrf (patrols and QRFs), MissionScenario (convoys, vehicle
## parks) and Operations (the Concord's order of battle). All data; a faction with no block (or
## a use it doesn't name) gets the caller's old choice.
##
## "vehicles": {"patrol": [model, ...], "qrf": [...], "convoy_cargo": model, "convoy_escort":
## [...], "park": [...], "armour": [...], "by_tier": {"3": {"qrf": [...]}}, "schemes": {model:
## scheme}}. by_tier replaces a use from that Pressure tier up (the highest tier named at or
## under the zone's).


static func table(faction: Variant) -> Dictionary:
	return (MissionRegistry.faction(String(faction)).get("vehicles", {}) as Dictionary)


## The models `faction` fields for `use` at Pressure tier `tier`, or [] with no such list.
static func models(faction: Variant, use: String, tier := 0) -> Array:
	var t := table(faction)
	if t.is_empty():
		return []
	var best := -1
	for key: Variant in t.get("by_tier", {}):
		var at := int(String(key))
		if at <= tier and at > best and ((t.by_tier as Dictionary)[key] as Dictionary).has(use):
			best = at
	var use_of: Dictionary = (t.by_tier as Dictionary)[str(best)] if best >= 0 else t
	var v: Variant = use_of.get(use, [])
	if v is Array:
		return v
	return [v] if String(v) != "" else []


## The `index`th model of `faction`'s `use` (cycling through its list), or `fallback` with no list.
static func pick(faction: Variant, use: String, index: int, fallback: String, tier := 0) -> String:
	var list := models(faction, use, tier)
	return String(list[index % list.size()]) if not list.is_empty() else fallback


## The paint scheme `faction` puts on `model` ("": the model's default).
static func scheme(faction: Variant, model: String) -> String:
	return String((table(faction).get("schemes", {}) as Dictionary).get(model, ""))


## The packages `faction` fits to `model` at Pressure tier `tier` (the Concord's BMP-2s get
## Kontakt-1 at tier 3: 2.4.5). A by_tier block's "packages": {model: [package ids]}.
static func packages(faction: Variant, model: String, tier := 0) -> Array:
	var t := table(faction)
	var best := -1
	var out: Array = []
	for key: Variant in t.get("by_tier", {}):
		var at := int(String(key))
		var row: Dictionary = (t.by_tier as Dictionary)[key]
		if at <= tier and at > best and row.has("packages") and (row.packages as Dictionary).has(model):
			best = at
			out = row.packages[model]
	return out


## `count` models of `faction`'s vehicle park (from `fallback`'s when it has no list), deterministic.
static func park(faction: Variant, count: int, fallback: Array) -> Array:
	var list := models(faction, "park")
	if list.is_empty():
		return fallback
	var out: Array = []
	for i in count:
		out.append(String(list[i % list.size()]))
	return out
