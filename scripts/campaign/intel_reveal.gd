class_name IntelReveal
extends Node
## Intel that means something in the field (Captain, 2026-10-16: "sell loot and intel meaning
## something"): the first time anyone of the squad (players and squad AI) has a piece of intel
## on them, it gives away enemy sites in the zone: the most telling ones not known yet (PRIORITY:
## HQ, QRF base, AA, then outposts, checkpoints, the rest), as many as its worth (SITES_PER_VALUE
## of its intel_value, at least one). Each goes on the squad's map as an enemy marker
## (MapMarkers.server_report_enemy, channel "intel") and everyone is told. Sites already taken
## out are skipped. Selling it later (Contracts.server_sell_intel) still pays.
## A manhunt's intel (LZ-7, Captain 2026-10-20: "the intel case doesn't tell you where dude is"):
## whatever piece its intel objective wants, intel or a hard case, says where the man went the
## first time one of the squad has it (Contracts.server_intel_lead).
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
				server_reveal_for(StringName(piece.id), s)
		if Contracts.is_deployed():
			for entry: Dictionary in _carried(s):
				Contracts.server_intel_lead(entry)


## The intel items `s` carries: [{"id", "intel_id"}] (one entry per piece: its intel_id, else its slot).
static func _intel_on(s: Variant) -> Array:
	var out: Array = []
	for e: Dictionary in _carried(s):
		var data := ItemDB.get_item(StringName(e.id))
		if data == null or data.type != "intel":
			continue
		out.append({"id": String(e.id), "intel_id": String((e.state as Dictionary).get("intel_id", "%s#%d" % [e.id, int(e.i)]))})
	return out


## Everything `s` carries, slots, containers and hands: [{"id", "state", "i" (its place in its list)}].
static func _carried(s: Variant) -> Array:
	var out: Array = []
	if not is_instance_valid(s) or not s is Soldier:
		return out
	var inv := (s as Soldier).inventory
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
			var id := String((e as Dictionary).get("id", ""))
			var st: Variant = (e as Dictionary).get("state", {})
			if id != "":
				out.append({"id": id, "state": st if st is Dictionary else {}, "i": i})
	return out


## Host: a piece of intel `item_id` gives away its share of enemy sites; `by`, if given, calls
## it out (Callouts.intel_found) for the first (most telling) one. Returns how many.
func server_reveal_for(item_id: StringName, by: Soldier = null) -> int:
	var data := ItemDB.get_item(item_id)
	var worth := int(data.stats.get("intel_value", 1000)) if data else 1000
	var count := clampi(int(round(worth * SITES_PER_VALUE)), 1, MAX_SITES)
	var markers := MapNodes.markers(self)
	var told := PackedStringArray()
	var first_type := ""
	for site: ZoneModule in _sites():
		if told.size() >= count:
			break
		_revealed[site.module_id] = true
		if first_type == "":
			first_type = ZoneModules.base(site.type)
		var label := String(NAMES.get(ZoneModules.base(site.type), ZoneModules.base(site.type).capitalize()))
		if markers:
			markers.server_report_enemy(site.global_position, "%s (intel)" % label)
		told.append(label)
	if told.is_empty():
		return 0
	Economy._notify_all("Intel (%s): %s marked on the map" % [data.name if data else "intel", ", ".join(told)])
	var callouts := Callouts.of(self) if by else null
	if callouts:
		callouts.intel_found(by, first_type)
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
		var pa := PRIORITY.find(ZoneModules.base(a.type))
		var pb := PRIORITY.find(ZoneModules.base(b.type))
		return (pa if pa >= 0 else 99) < (pb if pb >= 0 else 99))
	return out
