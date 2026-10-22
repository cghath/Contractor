class_name VehicleSpecs
extends RefCounted
## The vehicle numbers from res://data/vehicles.json (wave 5): per model its kind, mass,
## speeds, fuel, cargo, wheels, collision boxes, hit zones, seats, mounted gun and action
## points; the armour classes; the round tiers vehicles care about; the mounted guns. A
## model entry with "base" takes everything from that model and overrides what it names.
## Everything in the file is Proposed (Captain decided only that small calibre doesn't
## defeat vehicle armour and that 7.62x54R and up can). Read-only after the first load.

const PATH := "res://data/vehicles.json"
## Combined arms (docs/combined_arms.md 9.1): per-topic files keyed by model id, merged into
## the model's spec so parallel phases never edit one JSON file: plates, tiles, belly, spall
## liner and packages (A1); modules (A2); weapons, optics, crew and vision (A3). A file that
## isn't there yet is skipped.
const TOPIC_PATHS: Array[String] = ["res://data/vehicle_armour.json", "res://data/vehicle_modules.json", "res://data/vehicle_weapons.json"]
const KMH := 1.0 / 3.6

## Vehicle threat tiers (round_tier): small arms, full-power rifle (7.62x54R up), heavy
## machine gun, autocannon.
const TIER_SMALL := 0
const TIER_FULL_POWER := 1
const TIER_HMG := 2
const TIER_AUTOCANNON := 3
## A round with no tier in the file and at least this calibre counts as a heavy machine gun.
const HMG_CALIBRE_MM := 12.0

static var _data: Dictionary = {}
static var _topics: Array = []       # each TOPIC_PATHS file's "models" ({model: {key: value}})
static var _models: Dictionary = {}  # model -> merged spec
static var _guns: Dictionary = {}    # gun id -> ItemData built for Ballistics


static func _load() -> void:
	if not _data.is_empty():
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("VehicleSpecs: cannot open %s" % PATH)
		_data = {"models": {}, "armour": {}, "round_tiers": {}, "guns": {}}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("VehicleSpecs: %s is not valid JSON" % PATH)
		_data = {"models": {}, "armour": {}, "round_tiers": {}, "guns": {}}
		return
	_data = parsed
	for path in TOPIC_PATHS:
		if not FileAccess.file_exists(path):
			continue
		var topic: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(topic) != TYPE_DICTIONARY or typeof(topic.get("models")) != TYPE_DICTIONARY:
			push_error("VehicleSpecs: %s is not valid JSON with \"models\"" % path)
			continue
		_topics.append(topic.models)


## Every model with numbers (the VehicleArt models).
static func models() -> Array:
	_load()
	return (_data.models as Dictionary).keys()


static func has_model(model: String) -> bool:
	_load()
	return (_data.models as Dictionary).has(model)


## The merged spec of `model` ({} for an unknown one).
static func spec(model: String) -> Dictionary:
	_load()
	if _models.has(model):
		return _models[model]
	var raw: Dictionary = (_data.models as Dictionary).get(model, {})
	if raw.is_empty():
		return {}
	var out: Dictionary = {}
	if raw.has("base"):
		out = spec(String(raw.base)).duplicate(true)
	for key: String in raw:
		if key != "base":
			out[key] = raw[key]
	for topic: Dictionary in _topics:  # a derived model keeps its base's unless it names its own
		var extra: Dictionary = topic.get(model, {})
		for key: String in extra:
			out[key] = extra[key]
	_models[model] = out
	return out


## An armour class's numbers (resists, rha_mm, roof_mm, loss_j, blast).
static func armour(cls: String) -> Dictionary:
	_load()
	return (_data.armour as Dictionary).get(cls, (_data.armour as Dictionary).get("soft", {"resists": -1, "rha_mm": 3, "roof_mm": 2, "loss_j": 250, "blast": 1.0}))


## The vehicle threat tier of a round (an id in data/rounds.json, or its data): from the file's
## round_tiers, else by calibre (12 mm and up: heavy machine gun), else small arms.
static func round_tier(round_id: StringName) -> int:
	_load()
	var tiers: Dictionary = _data.round_tiers
	if tiers.has(String(round_id)):
		return int(tiers[String(round_id)])
	var data := Ballistics.round_data(round_id)
	if float(data.get("calibre_mm", 0.0)) >= HMG_CALIBRE_MM:
		return TIER_HMG
	return TIER_SMALL


## A mounted gun's numbers (name, round, rpm, spread_deg, feed), or {}.
static func gun(id: String) -> Dictionary:
	_load()
	return (_data.guns as Dictionary).get(id, {})


## A mounted gun as an ItemData Ballistics can fire (type weapon, its round, rate, spread).
static func gun_item(id: String) -> ItemData:
	if _guns.has(id):
		return _guns[id]
	var g := gun(id)
	if g.is_empty():
		return null
	var item := ItemData.from_dict({"id": "vehicle_" + id, "name": String(g.get("name", id)), "type": "weapon",
		"stats": {"round": String(g.round), "rpm": float(g.get("rpm", 600)), "spread_deg": float(g.get("spread_deg", 0.4)), "auto": true}})
	_guns[id] = item
	return item


## Helpers on a spec -------------------------------------------------------------------------

static func vec(a: Variant, fallback := Vector3.ZERO) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return fallback
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func box(a: Array) -> AABB:
	var lo := Vector3(minf(a[0], a[3]), minf(a[1], a[4]), minf(a[2], a[5]))
	var hi := Vector3(maxf(a[0], a[3]), maxf(a[1], a[4]), maxf(a[2], a[5]))
	return AABB(lo, hi - lo)
