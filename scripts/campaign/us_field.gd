class_name UsField
extends Node
## US forces in the field (D7, docs/combined_arms.md 7.3): what a belligerent employer of the
## living war (WorldSites.belligerents(): the US) has out in a zone while the squad is there, in its
## kit (factions.json "allied_us") and its vehicles (its "vehicles" block: the M-ATV, MaxxPro,
## Bradley and Abrams), green IFF, as friendly squads of their own:
##
## - A garrison at each zone it holds, at the zone's HQ site (its "hq", else its first outpost,
##   compound or checkpoint): that site is a US outpost, its men in place of the hostile garrison
##   (ZoneLevel._spawn_garrison's hook). At its base (a zone with "cant_fall": FOB Halberd) every
##   site is, the main one at full strength, the rest at half. A site a held contract here is
##   about stays the enemy's. The zone's other sites hold the last of the enemy the US took it
##   from (remnants()).
## - A mounted patrol in each zone it holds or borders: its "patrol" vehicles (an M-ATV and a
##   MaxxPro) with a rifle squad aboard, from its garrison or the crossing from its ground, along the
##   roads from site to site and back (RoadRoute), dismounting to fight when it's hit.
## - A convoy now and then in a zone it holds next to more of its ground: its "convoy" vehicles in
##   from the crossing on that side, along the MSR to the next crossing of its own (and out of the
##   zone) or to the garrison and back.
## - Armour on a front: an armour section ("armour_section" of its "armour" list: Bradleys, an Abrams
##   leading once its strength reaches "abrams_strength") in from its own side, halting
##   ARMOUR_HOLD_M short of the fight to overwatch; on its own ground under attack, at the garrison.
##
## plan() decides it from the campaign (read only: a test zone writes no campaign), the same every
## time; the node puts it in the world (host only, one "UsField" node per zone level that has any,
## install()). The friendly SideCommand (B2) takes these groups over when it lands; until then
## they patrol and fight on the squad AI as AlliedTroops' elements do. Numbers in factions.json
## "field" and here, all Proposed.

const NODE_NAME := "UsField"
## Seconds after the zone loads before the patrol sets out (and the armour moves up).
const FIRST_S := Vector2(20.0, 45.0)
## Seconds between convoys.
const CONVOY_GAP_S := Vector2(600.0, 900.0)
const PATROL_KMH := 35.0
const CONVOY_KMH := 40.0
const ARMOUR_KMH := 22.0
## The patrol waits this long at each end of its run before driving back.
const PATROL_DWELL_S := 60.0
## A patrol visits up to this many sites, nearest first from where it starts.
const PATROL_SITES := 3
## The armour section stops this far short of the fight.
const ARMOUR_HOLD_M := 350.0
## Vehicles in a column start this far apart (m).
const SPACING_M := 14.0
const TICK_S := 0.5
## Seconds between lines of the US net's own talk (factions.json "radio") while its groups are out.
const CHATTER_S := Vector2(180.0, 300.0)
## Site types a garrison and a patrol use, in order of preference for the HQ site.
const HQ_TYPES: Array[String] = ["hq", "outpost", "compound", "checkpoint"]
const PATROL_TYPES: Array[String] = ["outpost", "checkpoint", "village", "compound", "town", "hq", "qrf_base", "comms"]

## What plan() said for this zone.
var p := {}
## Host: the groups out now: {"kind" ("patrol", "convoy", "armour"), "squad", "vehicles", "men",
## "path" (PackedVector3Array), "state" ("out", "back", "dwell", "halted", "gone"), "until"}.
var groups: Array = []
## Host: the garrisons put in, module id -> [Soldier].
var garrisons := {}
## Host: every message it sent the squad (tests, the session log).
var said: Array[String] = []
var _first_s := 0.0
var _chatter_s := 120.0
var _convoy_s := INF
var _tick := 0.0
var _rng := RandomNumberGenerator.new()


static func of(from: Node) -> UsField:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as UsField if lvl else null


## Host (ZoneLevel._ready): the node, in a zone where a belligerent has anything (plan()).
static func install(level: Node) -> void:
	if level == null or not level.multiplayer.is_server() or level.get_node_or_null(NODE_NAME) != null:
		return
	var plan_ := plan(GameState.zone_id)
	if plan_.is_empty():
		return
	var node := UsField.new()
	node.name = NODE_NAME
	node.p = plan_
	level.add_child(node)


# --- The plan (pure) --------------------------------------------------------------------------

## Who holds `zone_id` as the campaign has it, without seeding a row: the company, the war's holder,
## else its data "controller".
static func holder_of(zone_id: String) -> String:
	if ZoneControl.is_company(zone_id):
		return ZoneControl.PLAYER
	var row: Dictionary = Campaign.section(WorldSites.SECTION).get(zone_id, {})
	return String(row.get("holder", ZoneControl.zone_def_raw(zone_id).get("controller", "")))


## What a belligerent has in `zone_id`, {} for nothing: {"side", "held", "base" (its cant_fall
## base), "patrol" (bool), "from" (the neighbouring zone of its it comes in from, "" from its own
## garrison), "convoy" ([in from, out to]: zone ids, "" for the garrison), "armour" ("" none,
## "front" on its own front here, "defend" its ground attacked)}.
static func plan(zone_id: String) -> Dictionary:
	if zone_id == "" or zone_id == RegionMap.BASE:
		return {}
	var f: Dictionary = (Campaign.section(WorldSites.SECTION).get(zone_id, {}) as Dictionary).get("front", {})
	for side in WorldSites.belligerents():
		var held := holder_of(zone_id) == side
		var mine: Array[String] = []
		for l: Dictionary in RegionMap.links(zone_id):
			if holder_of(String(l.to)) == side:
				mine.append(String(l.to))
		var front_by := String(f.get("by", ""))
		if not held and mine.is_empty() and front_by != side:
			continue
		var z := ZoneControl.zone_def_raw(zone_id)
		var out := {"side": side, "held": held, "base": held and bool(z.get("cant_fall", false)), "patrol": held or not mine.is_empty(),
			"from": "" if held or mine.is_empty() else mine[0], "convoy": [], "armour": ""}
		if held and not mine.is_empty() and not out.base:
			out.convoy = [mine[0], mine[1] if mine.size() > 1 else ""]
		if front_by == side:
			out.armour = "front"
		elif held and front_by != "":
			out.armour = "defend"
		return out
	return {}


## The vehicle models `side` uses for `use` ("patrol", "armour", "convoy"), from factions.json.
static func models(side: String, use: String) -> Array:
	var f := MissionRegistry.faction(side)
	var cfg: Dictionary = f.get("field", {})
	var veh: Dictionary = f.get("vehicles", {})
	match use:
		"convoy":
			return cfg.get("convoy", [veh.get("convoy_escort", ["matv"])[0], veh.get("convoy_cargo", "maxxpro")])
		"armour":
			var list: Array = veh.get("armour", ["bradley"])
			var n := int(cfg.get("armour_section", 2))
			var out: Array = []
			var heavy := WorldSites.strength(side) >= float(cfg.get("abrams_strength", 85)) and list.size() > 1
			for i in n:
				out.append(String(list[1]) if heavy and i == 0 else String(list[0]))
			return out
	return veh.get("patrol", ["matv", "maxxpro"])


## The enemy at a held zone's other sites (ZoneLevel._zone_enemy's hook): the one the belligerent
## took it from if that one is still in the war and hostile, else its war_target; "" for a zone no
## belligerent holds (or nothing left to hold out).
static func remnants(zone_id: String) -> String:
	var h := holder_of(zone_id)
	if not WorldSites.is_belligerent(h):
		return ""
	var row: Dictionary = Campaign.section(WorldSites.SECTION).get(zone_id, {})
	var prev := String(row.get("prev", ""))
	if prev != "" and MissionRegistry.faction(prev).get("role", "") == "hostile" and not WorldSites.is_wiped(prev):
		return prev
	return WorldSites.war_target(h)


## The HQ site of a zone's modules (`modules`: ZoneModules or the def's dictionaries): its id.
static func hq_site(modules: Array) -> String:
	for t in HQ_TYPES:
		for m: Variant in modules:
			var type := String(m.get(&"type") if m is Object else (m as Dictionary).get("type", ""))
			if ZoneModules.base(type) == t:
				return String(m.get(&"module_id") if m is Object else (m as Dictionary).get("id", ""))
	return ""


# --- The garrison -----------------------------------------------------------------------------

## Host (ZoneLevel._spawn_garrison's hook): whether `module` is a US site here; if so its US
## garrison is put in (once) and the hostile one isn't.
static func server_garrison(level: Node, module: ZoneModule) -> bool:
	var node := level.get_node_or_null(NODE_NAME) as UsField if level else null
	if node == null or not bool(node.p.get("held", false)) or not node.is_site(module):
		return false
	if not node.garrisons.has(module.module_id):
		node._put_garrison(level, module)
	return true


## Whether `module` holds a US garrison: the HQ site of a held zone (every site at its base), not
## one a held contract here is about.
func is_site(module: ZoneModule) -> bool:
	for c: Dictionary in Contracts.held():
		if String(c.get("zone_id", "")) == GameState.zone_id and String(c.get("module_id", "")) == module.module_id:
			return false
	if bool(p.get("base", false)):
		return true
	var lvl := get_parent()
	return lvl != null and lvl.has_method(&"modules") and hq_site(lvl.call(&"modules")) == module.module_id


func _put_garrison(level: Node, module: ZoneModule) -> void:
	var side := String(p.side)
	var cfg: Dictionary = MissionRegistry.faction(side).get("field", {})
	var men := int(cfg.get("garrison_men", 8))
	if bool(p.get("base", false)) and level.has_method(&"modules") and hq_site(level.call(&"modules")) != module.module_id:
		men = maxi(2, men / 2)
	var spots: Array = ZoneModules.GARRISON.get(module.type, [])
	var sq := _squad("%s_%s" % [_callsign("garrison"), module.module_id.validate_node_name().replace("@", "_")])
	var list: Array = []
	for i in men:
		var local: Vector3 = spots[i % spots.size()] + Vector3(1.5 * (i / maxi(spots.size(), 1)), 0.0, 0.0) if not spots.is_empty() \
			else Vector3(cos(TAU * i / men), 0.0, sin(TAU * i / men)) * 6.0
		var s := _soldier(level, "USG_%s_%d" % [module.module_id.left(10), i + 1], module.to_global(local), i, sq)
		if s:
			list.append(s)
	garrisons[module.module_id] = list
	print("[us field] %s garrison at %s: %d men" % [side, module.module_id, list.size()])


# --- The field groups -------------------------------------------------------------------------

func _ready() -> void:
	_rng.seed = hash([GameState.zone_id, "us_field", Time.get_ticks_msec()])
	_first_s = _rng.randf_range(FIRST_S.x, FIRST_S.y)
	if not (p.get("convoy", []) as Array).is_empty():
		_convoy_s = _first_s + _rng.randf_range(CONVOY_GAP_S.x, CONVOY_GAP_S.y) * 0.5


func _process(delta: float) -> void:
	if not multiplayer.is_server() or not CompoundLevel.spawn_ai:
		return
	if _first_s > 0.0:
		_first_s -= delta
		if _first_s <= 0.0 and BaseHub.deployment_running():
			server_start()
	_convoy_s -= delta
	if _convoy_s <= 0.0:
		_convoy_s = _rng.randf_range(CONVOY_GAP_S.x, CONVOY_GAP_S.y)
		if BaseHub.deployment_running() and not groups.any(func(g: Dictionary) -> bool: return g.kind == "convoy" and g.state != "gone"):
			server_convoy()
	_chatter_s -= delta
	if _chatter_s <= 0.0:
		_chatter_s = _rng.randf_range(CHATTER_S.x, CHATTER_S.y)
		var lines: Array = MissionRegistry.faction(String(p.get("side", ""))).get("radio", [])
		if BaseHub.deployment_running() and not lines.is_empty() and not groups.is_empty():
			_say(String(lines[_rng.randi() % lines.size()]))
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		_step()


## Host: the patrol and the armour set out (tests call it directly).
func server_start() -> void:
	if bool(p.get("patrol", false)) and not groups.any(func(g: Dictionary) -> bool: return g.kind == "patrol"):
		server_patrol()
	if String(p.get("armour", "")) != "" and not groups.any(func(g: Dictionary) -> bool: return g.kind == "armour"):
		server_armour()


## Host: the mounted patrol. Returns the group ({} when it couldn't go out).
func server_patrol() -> Dictionary:
	var lvl := get_parent()
	var start := _start_point(String(p.get("from", "")))
	var sites := _patrol_sites(start)
	if sites.is_empty():
		return {}
	var path := _road_path([start] + sites)
	var cfg: Dictionary = MissionRegistry.faction(String(p.side)).get("field", {})
	var g := _column("patrol", models(String(p.side), "patrol"), start, path, int(cfg.get("patrol_men", 8)), PATROL_KMH)
	if not g.is_empty():
		_say("%s, %s: mounted patrol rolling, %s. Contractors in the area, check your fire." % [_callsign("patrol"), _callsign("garrison"),
			RadioChatter.compass(Vector3.ZERO, path[path.size() - 1]) + " side" if lvl else "on the roads"])
	return g


## Host: a convoy along the MSR. Returns the group ({} when it couldn't go).
func server_convoy() -> Dictionary:
	var c: Array = p.get("convoy", [])
	if c.is_empty():
		return {}
	var start := _start_point(String(c[0]))
	var end := _start_point(String(c[1])) if String(c[1]) != "" else _garrison_point()
	var path := _road_path([start, end])
	var cfg: Dictionary = MissionRegistry.faction(String(p.side)).get("field", {})
	var list := models(String(p.side), "convoy")
	var g := _column("convoy", list, start, path, int(cfg.get("convoy_crew", 2)) * list.size(), CONVOY_KMH, int(cfg.get("convoy_crew", 2)))
	if not g.is_empty():
		g["leaves"] = String(c[1]) != ""
		_say("%s: convoy inbound on the MSR from %s. Keep the road clear." % [_callsign("convoy"), RegionMap.zone_name(String(c[0]))])
	return g


## Host: the armour section. Returns the group ({} when it couldn't go).
func server_armour() -> Dictionary:
	var start := _start_point(String(p.get("from", ""))) if String(p.armour) == "front" else _garrison_point()
	var aim := _fight_point(start)
	var to := aim
	var flat := Vector3(aim.x - start.x, 0.0, aim.z - start.z)
	if flat.length() > ARMOUR_HOLD_M:
		to = start + flat.normalized() * (flat.length() - ARMOUR_HOLD_M)
	var lvl := get_parent()
	if lvl and lvl.has_method(&"ground_point"):
		to = lvl.call(&"ground_point", to)
	var cfg: Dictionary = MissionRegistry.faction(String(p.side)).get("field", {})
	var list := models(String(p.side), "armour")
	var g := _column("armour", list, start, _road_path([start, to]), int(cfg.get("armour_crew", 3)) * list.size(), ARMOUR_KMH, int(cfg.get("armour_crew", 3)))
	if not g.is_empty():
		_say("%s: %s section moving up to overwatch, %s." % [_callsign("armour"), " and ".join(PackedStringArray(_names(list))),
			RadioChatter.compass(start, aim)])
	return g


## A column of `list` vehicles from `start` along `path`, `men` aboard (`per` a vehicle at most, else
## as the seats allow), as one friendly squad. {} if none could be put out.
func _column(kind: String, list: Array, start: Vector3, path: PackedVector3Array, men: int, kmh: float, per := 99) -> Dictionary:
	var lvl := get_parent()
	var layer := lvl.get_node_or_null(^"Vehicles") as VehicleLayer if lvl else null
	if layer == null or path.is_empty():
		return {}
	var fwd := Vector3(path[0].x - start.x, 0.0, path[0].z - start.z)
	if fwd.length() < 1.0 and path.size() > 1:
		fwd = Vector3(path[1].x - start.x, 0.0, path[1].z - start.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var sq := _squad("%s_%d" % [_callsign(kind), groups.size() + 1])
	var g := {"kind": kind, "squad": sq, "vehicles": [], "men": [], "path": path, "back": _reversed(path, start), "state": "out", "until": 0.0, "kmh": kmh}
	var left := men
	for i in list.size():
		var at := start - fwd * SPACING_M * i
		if lvl.has_method(&"ground_point"):
			at = lvl.call(&"ground_point", at)
		var v := layer.server_spawn(String(list[i]), Transform3D(Basis.looking_at(fwd, Vector3.UP), at + Vector3.UP * 0.3), "", &"friendly", "")
		if v == null:
			continue
		v.set_meta(&"no_save", true)
		v.set_meta(&"us_field", kind)
		var seats := VehicleQrf._seat_order(v)
		var take := mini(mini(seats.size(), per), left) if i < list.size() - 1 else mini(seats.size(), left)
		for k in take:
			var s := _soldier(lvl, "US%s%d_%d_%d" % [kind.left(1).to_upper(), groups.size() + 1, i + 1, k + 1], at, k, sq)
			if s == null:
				continue
			if v.server_enter(s, int(seats[k])):
				(g.men as Array).append(s)
				left -= 1
			else:
				s.queue_free()
		AavGunner.attach(v)
		v.damaged.connect(_on_hit.bind(g))
		(g.vehicles as Array).append(v)
		v.server_follow_path(path, kmh)
	if (g.vehicles as Array).is_empty():
		sq.queue_free()
		return {}
	groups.append(g)
	print("[us field] %s %s out: %d vehicles, %d men" % [String(p.side), kind, (g.vehicles as Array).size(), (g.men as Array).size()])
	return g


## Host, every TICK_S: a patrol drives back and forth (dwelling at each end), a convoy that reached
## its far crossing leaves the zone, the armour holds where it stopped.
func _step() -> void:
	var now := Soldier._now()
	for g: Dictionary in groups:
		if g.state in ["halted", "gone"]:
			continue
		var vs: Array = (g.vehicles as Array).filter(func(v: Variant) -> bool: return is_instance_valid(v) and not (v as Vehicle).wrecked)
		if vs.is_empty():
			g.state = "gone"
			continue
		var lead: Vehicle = vs[0]
		var moving := is_instance_valid(lead.ai) and lead.ai.active
		if g.state == "dwell":
			if now >= float(g.until):
				var next: PackedVector3Array = g.back
				g.back = g.path
				g.path = next
				g.state = "out"
				for v: Vehicle in vs:
					v.server_follow_path(next, float(g.kmh))
			continue
		if moving:
			continue
		match String(g.kind):
			"patrol":
				g.state = "dwell"
				g.until = now + PATROL_DWELL_S
			"convoy":
				if bool(g.get("leaves", false)) or g.back == PackedVector3Array():
					_leave(g)
				elif g.get("returned", false):
					_leave(g)
				else:
					g["returned"] = true
					g.state = "dwell"
					g.until = now + PATROL_DWELL_S
			"armour":
				g.state = "halted"


func _on_hit(_zone: StringName, _hit: Dictionary, g: Dictionary) -> void:
	if String(g.state) in ["halted", "gone"]:
		return
	g.state = "halted"
	for v: Variant in g.vehicles:
		if not is_instance_valid(v):
			continue
		var veh := v as Vehicle
		veh.server_stop()
		if String(g.kind) == "armour":
			continue  # the crews fight from inside
		var keep := veh.gunner() if not veh.gun_info().is_empty() else null
		for s: Soldier in veh.occupants():
			if s != keep and s.vitals.is_up() and s != veh.driver():
				veh.server_exit(s)
	_say("%s: contact, dismounting." % _callsign(String(g.kind)))


## A convoy out of the zone: its vehicles and crews go (they drove on).
func _leave(g: Dictionary) -> void:
	g.state = "gone"
	for v: Variant in g.vehicles:
		if is_instance_valid(v):
			for s: Soldier in (v as Vehicle).occupants():
				s.queue_free()
			(v as Vehicle).queue_free()


# --- Places -----------------------------------------------------------------------------------

## Where a group starts: the crossing to `from` (a neighbouring zone), else the garrison.
func _start_point(from: String) -> Vector3:
	var lvl := get_parent()
	var def: Dictionary = lvl.get(&"def") if lvl and lvl.get(&"def") is Dictionary else {}
	if from != "":
		for c: Dictionary in def.get("crossings", []):
			if String(c.get("to", "")) == from:
				return _ground(Vector3(float(c.pos[0]), 0.0, float(c.pos[1])))
	return _garrison_point()


func _garrison_point() -> Vector3:
	var lvl := get_parent()
	if lvl and lvl.has_method(&"modules"):
		var id := hq_site(lvl.call(&"modules"))
		for m: ZoneModule in lvl.call(&"modules"):
			if m.module_id == id:
				var half: Vector2 = ZoneModules.HALF.get(ZoneModules.base(m.type), Vector2(30, 30))
				return _ground(m.global_position + Vector3(half.x + 12.0, 0.0, 0.0))  # outside its gate side
	return _ground(Vector3.ZERO)


## Up to PATROL_SITES sites, each the nearest not yet visited from the last.
func _patrol_sites(start: Vector3) -> Array[Vector3]:
	var lvl := get_parent()
	var left: Array[Vector3] = []
	if lvl and lvl.has_method(&"modules"):
		for m: ZoneModule in lvl.call(&"modules"):
			if ZoneModules.base(m.type) in PATROL_TYPES:
				left.append(_ground(m.global_position))
	var out: Array[Vector3] = []
	var at := start
	while out.size() < PATROL_SITES and not left.is_empty():
		left.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(at) < b.distance_to(at))
		at = left.pop_front()
		if at.distance_to(start) > 40.0:
			out.append(at)
	return out


## Where the fight in this zone is: the holder's HQ site (on a front of ours), else the garrison.
func _fight_point(start: Vector3) -> Vector3:
	var lvl := get_parent()
	if String(p.armour) == "front" and lvl and lvl.has_method(&"modules"):
		var id := hq_site(lvl.call(&"modules"))
		for m: ZoneModule in lvl.call(&"modules"):
			if m.module_id == id:
				return _ground(m.global_position)
	return _garrison_point() if start.distance_to(_garrison_point()) > 1.0 else start


## A path through `points` by the zone's roads where they help (RoadRoute), else straight.
func _road_path(points: Array) -> PackedVector3Array:
	var lvl := get_parent()
	var def: Dictionary = lvl.get(&"def") if lvl and lvl.get(&"def") is Dictionary else {}
	var out := PackedVector3Array()
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		for q: Vector2 in RoadRoute.route(def, Vector2(a.x, a.z), Vector2(b.x, b.z)):
			out.append(_ground(Vector3(q.x, 0.0, q.y)))
		if out.is_empty() or out[out.size() - 1].distance_to(b) > 1.0:
			out.append(b)
	return out


static func _reversed(path: PackedVector3Array, start: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(path.size() - 2, -1, -1):
		out.append(path[i])
	out.append(start)
	return out


func _ground(at: Vector3) -> Vector3:
	var lvl := get_parent()
	return lvl.call(&"ground_point", at) if lvl and lvl.has_method(&"ground_point") else at


# --- Men and words ----------------------------------------------------------------------------

func _squad(squad_name: String) -> Squad:
	var sq := Squad.new()
	sq.name = squad_name.validate_node_name()
	sq.faction = &"friendly"
	add_child(sq)
	return sq


func _soldier(level: Node, soldier_name: String, at: Vector3, i: int, sq: Squad) -> Soldier:
	var side := String(p.side)
	var kit := Kits.kit_of(side)
	var k := Kits.data(kit)
	var pos: Vector3 = level.call(&"ground_point", at) if level.has_method(&"ground_point") else at
	var s: Soldier = level.call(&"spawn_soldier", {"name": soldier_name, "faction": "friendly", "iff": "allied", "variant": Kits.variant(kit, i),
		"pos": pos, "loadout": Kits.loadout(kit, i, 1), "role": Kits.role(kit, i), "combat": float(k.get("combat", 0.6)),
		"discipline": float(k.get("discipline", 0.7)), "guard": false, "mode": "aware", "faction_id": side})
	if s == null:
		return null
	var brain := SquadAI.of(s)
	if brain:
		brain.squad = sq
	return s


## The side's callsign for a group (factions.json "field" "callsigns").
func _callsign(kind: String) -> String:
	var calls: Dictionary = (MissionRegistry.faction(String(p.get("side", ""))).get("field", {}) as Dictionary).get("callsigns", {})
	return String(calls.get(kind, kind.capitalize()))


const NAMES := {"matv": "M-ATV", "maxxpro": "MaxxPro", "bradley": "Bradley", "abrams": "Abrams"}


static func _names(list: Array) -> Array:
	return list.map(func(m: Variant) -> String: return String(NAMES.get(String(m), VehicleSpecs.spec(String(m)).get("name", String(m)))))


## A line on the US net to every player (Contracts' notices), kept in `said`.
func _say(text: String) -> void:
	var line := "US net: %s" % text
	said.append(line)
	Contracts._notify_all(line)
	SessionLog.note("us field: %s" % text)
