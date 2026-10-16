class_name IntelReveal
extends Node
## Intel that means something in the field (Captain, 2026-10-16: "sell loot and intel meaning
## something"): the first time anyone of the squad (players and squad AI) has a piece of intel
## on them, it gives away enemy sites in the zone: the most telling ones not known yet (PRIORITY:
## HQ, QRF base, AA, then outposts, checkpoints, the rest), as many as its worth (SITES_PER_VALUE
## of its intel_value, at least one). Each goes on the squad's map as an enemy marker
## (MapMarkers.server_report_enemy, channel "intel") and everyone is told. Sites already taken
## out are skipped. Selling it later (Contracts.server_sell_intel) still pays.
## Host only; ZoneLevel adds one.

const TICK_S := 2.0
const SITES_PER_VALUE := 1.0 / 1000.0
const MAX_SITES := 3
const PRIORITY: Array[String] = ["hq", "qrf_base", "aa", "outpost", "checkpoint"]
const NAMES := {"hq": "HQ", "qrf_base": "QRF base", "aa": "AA site", "outpost": "outpost", "checkpoint": "checkpoint"}

var level: CompoundLevel
var _seen := {}       # intel piece key -> true
var _revealed := {}   # module id -> true
var _tick := 0.0


func _init() -> void:
	name = "IntelReveal"


func _ready() -> void:
	level = get_parent() as CompoundLevel


func _process(delta: float) -> void:
	if not multiplayer.is_server() or level == null:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	for s: Soldier in MapNodes.players(self) + MapNodes.squad_ai(self):
		for piece: Dictionary in _intel_on(s):
			var key := "%s|%s" % [piece.id, piece.intel_id]
			if not _seen.has(key):
				_seen[key] = true
				server_reveal_for(StringName(piece.id))


## The intel items `s` carries: [{"id", "intel_id"}] (one entry per piece: its intel_id, else its slot).
static func _intel_on(s: Soldier) -> Array:
	var out: Array = []
	if s == null or not is_instance_valid(s):
		return out
	var inv := s.inventory
	var lists: Array = []
	for slot in Inventory.SLOTS:
		if inv.slots.get(slot, &"") != &"":
			lists.append([{"id": inv.slots[slot], "state": inv.state_of(slot)}])
	for container in Inventory.CONTAINERS:
		lists.append(inv.containers.get(container, []))
	if inv.hands != &"":
		lists.append([{"id": inv.hands, "state": {}}])
	for list: Array in lists:
		for i in list.size():
			var e: Variant = list[i]
			if not e is Dictionary:
				continue
			var id := StringName(String((e as Dictionary).get("id", "")))
			var data := ItemDB.get_item(id) if id != &"" else null
			if data == null or data.type != "intel":
				continue
			var st: Dictionary = (e as Dictionary).get("state", {})
			out.append({"id": String(id), "intel_id": String(st.get("intel_id", "%s#%d" % [id, i]))})
	return out


## Host: a piece of intel `item_id` gives away its share of enemy sites. Returns how many.
func server_reveal_for(item_id: StringName) -> int:
	var data := ItemDB.get_item(item_id)
	var worth := int(data.stats.get("intel_value", 1000)) if data else 1000
	var count := clampi(int(round(worth * SITES_PER_VALUE)), 1, MAX_SITES)
	var markers := MapNodes.markers(self)
	var told := PackedStringArray()
	for site: ZoneModule in _sites():
		if told.size() >= count:
			break
		_revealed[site.module_id] = true
		var label := String(NAMES.get(site.type, site.type.capitalize()))
		if markers:
			markers.server_report_enemy(site.global_position, "%s (intel)" % label)
		told.append(label)
	if told.is_empty():
		return 0
	Economy._notify_all("Intel (%s): %s marked on the map" % [data.name if data else "intel", ", ".join(told)])
	return told.size()


## Enemy sites not revealed or taken out yet, most telling first.
func _sites() -> Array[ZoneModule]:
	var out: Array[ZoneModule] = []
	if not level.has_method(&"modules"):
		return out
	for m: ZoneModule in level.call(&"modules"):
		if _revealed.has(m.module_id) or bool(level.call(&"site_down", m.module_id)):
			continue
		out.append(m)
	out.sort_custom(func(a: ZoneModule, b: ZoneModule) -> bool:
		var pa := PRIORITY.find(a.type)
		var pb := PRIORITY.find(b.type)
		return (pa if pa >= 0 else 99) < (pb if pb >= 0 else 99))
	return out
