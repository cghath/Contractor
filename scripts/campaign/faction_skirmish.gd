class_name FactionSkirmish
extends Node
## Factions fight each other in the field (wave 6, "faction-vs-faction in the field"): now and
## then, while the squad is out in a zone, a team of a faction at war with the zone's holder
## (MissionRegistry.enemies_of, factions.json) comes in from the map's edge and hits one of the
## holder's garrisoned sites, at least AWAY_M from every player. A faction the company stands badly
## with (reputation below zero) comes under the tag RIVAL: it and the garrison shoot each other
## (SquadAI fights any other faction), and the squad too. One the company gets on with comes as
## "friendly" (green, allied marks): it fights the garrison and leaves the squad be, a squad of its
## own outside the high command. The radio says where the shooting is; what's left is the
## squad's to use (a thinned garrison, bodies, their kit). One at a time; none at the base.
## Host only. Proposed numbers.

const NODE_NAME := "FactionSkirmish"
const RIVAL := &"rival"
const FIRST_S := Vector2(300.0, 600.0)
const GAP_S := Vector2(720.0, 1200.0)
const CHANCE := 0.6
const TEAM := 6
const AWAY_M := 300.0
const START_BACK_M := 250.0
const SITE_TYPES: Array[String] = ["compound", "outpost", "checkpoint", "hq", "qrf_base", "comms"]

var team: Array = []  # the skirmishers out now
var last := {}         # the last one: {"faction", "against", "site", "at"}
var _next_s := 0.0
var _rng := RandomNumberGenerator.new()


static func of(from: Node) -> FactionSkirmish:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as FactionSkirmish if lvl else null


func _ready() -> void:
	name = NODE_NAME
	_rng.seed = hash([get_parent().name, Time.get_ticks_msec()])
	_next_s = _rng.randf_range(FIRST_S.x, FIRST_S.y)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_next_s -= delta
	if _next_s > 0.0:
		return
	_next_s = _rng.randf_range(GAP_S.x, GAP_S.y)
	if CompoundLevel.spawn_ai and _alive() == 0 and BaseHub.deployment_running() and _rng.randf() < CHANCE:  # (never in a test level without AI)
		server_start()


func _alive() -> int:
	team = team.filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Soldier).is_queued_for_deletion())
	return team.filter(func(s: Soldier) -> bool: return s.vitals.is_up()).size()


## Whose men hold `lvl`: its zone enemy (ZoneLevel._zone_enemy), "" there meaning the usual
## Black Ridge mix.
static func holder_of(lvl: Node) -> String:
	var h: String = lvl.call(&"_zone_enemy") if lvl and lvl.has_method(&"_zone_enemy") else ""
	return h if h != "" else DEFAULT_HOLDER


const DEFAULT_HOLDER := "black_ridge"


## The factions that would come at `holder` here: its enemies.
static func rivals_of(holder: String) -> Array:
	return MissionRegistry.enemies_of(holder).filter(func(f: String) -> bool: return f != holder)


## Which side `faction`'s men take here: RIVAL (shooting everyone else) when the company stands
## badly with it, else friendly.
static func side_of(faction: String) -> StringName:
	return RIVAL if Economy.reputation(faction) < 0 else &"friendly"


## Host: a skirmish starts now (when one can). Returns "" or why not.
func server_start(faction := "") -> String:
	var lvl := CompoundLevel.current(self)
	if lvl == null or lvl.is_base():
		return "No skirmishes at the base"
	var holder := holder_of(lvl)
	var rivals := rivals_of(holder)
	if faction == "":
		if rivals.is_empty():
			return "Nobody here is at war with %s" % holder
		faction = String(rivals[_rng.randi() % rivals.size()])
	var site := _pick_site(lvl)
	if site == null:
		return "No site away from the squad"
	var at := site.global_position
	var area: Rect2 = lvl.map_area() if lvl.has_method(&"map_area") else Rect2(at.x - 600, at.z - 600, 1200, 1200)
	var flat := Vector2(at.x, at.z)
	var out := (flat - area.get_center()).normalized() if flat.distance_to(area.get_center()) > 1.0 else Vector2.RIGHT.rotated(_rng.randf() * TAU)
	var start2 := flat + out * START_BACK_M
	start2 = Vector2(clampf(start2.x, area.position.x + 40.0, area.end.x - 40.0), clampf(start2.y, area.position.y + 40.0, area.end.y - 40.0))
	var start: Vector3 = lvl.call(&"ground_point", Vector3(start2.x, 0.0, start2.y)) if lvl.has_method(&"ground_point") else Vector3(start2.x, 0.0, start2.y)
	var side := side_of(faction)
	var squad := Squad.new()
	squad.name = "Skirmish_%s" % faction
	squad.faction = side
	add_child(squad)
	var kit_id := Kits.kit_of(faction)
	var across := Vector3(at.x - start.x, 0.0, at.z - start.z).normalized().cross(Vector3.UP)
	team.clear()
	for i in TEAM:
		var pos: Vector3 = start + across * 3.0 * (i - (TEAM - 1) / 2.0)
		if lvl.has_method(&"ground_point"):
			pos = lvl.call(&"ground_point", pos)
		var loadout: Array = Kits.loadout(kit_id, i, 2) if Kits.is_data(kit_id) else CompoundLevel.hostile_loadout(i)
		var s: Soldier = lvl.call(&"spawn_soldier", {"name": "Sk_%s_%d" % [faction.left(6), i + 1], "faction": String(side), "iff": ("militia" if kit_id == Kits.INSURGENT else "hostile") if side == RIVAL else "allied",
			"variant": Kits.variant(kit_id) if Kits.is_data(kit_id) else "woodland", "pos": pos, "loadout": loadout,
			"combat": 0.6, "discipline": 0.6, "guard": false, "mode": "combat"})
		if s == null:
			continue
		var brain := SquadAI.of(s)
		if brain:
			brain.squad = squad
		team.append(s)
	var route: Array[Vector3] = [at]
	squad.patrol = route
	last = {"faction": faction, "against": holder, "site": String(site.get(&"module_id")), "at": [at.x, at.z], "side": String(side)}
	var who := String(MissionRegistry.faction(faction).get("name", faction))
	var them := String(MissionRegistry.faction(holder).get("name", holder)) if holder != "" else "the garrison"
	var me := MapNodes.local_player(self)
	var dir := _compass(Vector2(at.x - me.global_position.x, at.z - me.global_position.z)) if me else "far"
	Contracts._notify_all("Gunfire to the %s: %s are hitting %s's %s.%s" % [dir, who, them, String(site.get(&"type")).replace("_", " "),
		" They're no friends of ours either." if side == RIVAL else " Friendlies: check your fire."])
	SessionLog.note("skirmish: %s (%d men) against %s at %s" % [faction, team.size(), holder, last.site])
	return ""


## A garrisoned site at least AWAY_M from every player (the furthest-off of the near ones).
func _pick_site(lvl: CompoundLevel) -> Node3D:
	var players: Array = lvl.players.get_children().filter(func(n: Node) -> bool: return n is Soldier)
	var options: Array = []
	for m: Node in lvl.call(&"modules") if lvl.has_method(&"modules") else []:
		var t := ZoneModules.base(String(m.get(&"type")))
		if t not in SITE_TYPES:
			continue
		var p := (m as Node3D).global_position
		if players.all(func(s: Soldier) -> bool: return Vector2(s.global_position.x - p.x, s.global_position.z - p.z).length() >= AWAY_M):
			options.append(m)
	return options[_rng.randi() % options.size()] if not options.is_empty() else null


static func _compass(d: Vector2) -> String:
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(fposmod(atan2(d.x, -d.y), TAU) / (TAU / 8.0))) % 8]
