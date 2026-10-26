class_name SurvivorsLayer
extends Node3D
## The living people of a Contractor: Fallen zone (docs/survival_people.md sections 1-6 and 8,
## calls 2, 18, 40, 51, 54, 74-77): SurvivalLevel adds one as "Survivors" on every peer.
##
## Host:
## - Lone survivors out in the world: a new zone gets PER_ZONE of them (more near villages),
##   placed by the world's seed about its sites (SurvivorPerson records in Survival.state()
##   "people"); within LIVE_M of a player each is a body (PeopleLayer's person, kind "survivor":
##   plain clothes, CivilianAI idling about a home spot, faction "civilian" so the dead go for
##   them too), past DESPAWN_M a record again. The wary and hostile warn players off.
## - Talking (TalkMenu) and hiring by a want: met, they join as a companion: the person's body
##   goes and a friendly squadmate takes its place (SquadAI, the squad's orders, follows) with a
##   CompanionAI beside its brain (needs, moods, autonomy, refusals). Companions come along to
##   whatever zone is hosted and are saved with the world (zone, pos, kit, needs, moods).
## - Every world hour moods tick (Moods) and breaks play out (_on_break); favours are checked
##   when a player reaches the marked place; promises kept or broken.
## - Death (section 8): the body stays with its kit, the others grieve, a body left out costs
##   mood and a little zone pressure; burying one (server_start_bury: a shovel or bare hands)
##   leaves a grave marker and eases the grief; one killed by the dead rises after RISE_S unless
##   buried first (Survival.server_spawn_zombie in their kit); putting them down is its own
##   moodlet. A player's death: companions grieve, the newcomer is a stranger, and willing
##   companions can be taken over (server_take_over, call 51).
## Every peer: `known` (which body is which survivor, by path from the level) and the graves'
## markers, sent by the host.

const NODE_NAME := "Survivors"
const GROUP := &"survivors_layers"
const KEY := "people"
const GRAVES_KEY := "people_graves"
## Proposed numbers.
const PER_ZONE := Vector2i(2, 5)
const VILLAGE_BONUS_MAX := 2
const PLACE_FROM_SITE_M := Vector2(6.0, 28.0)
const LIVE_M := 90.0
const DESPAWN_M := 110.0
const TICK_S := 1.0
const WARN_M := 10.0
const WARN_GAP_S := 45.0
const SCARE_M := 14.0
const RISE_S := 180.0
const BURY_S := {"shovel": 8.0, "hands": 25.0}
const BURY_REACH_M := 3.0
const BODY_PRESSURE_DAY := 4.0
const FRIEND_AT := 30.0
const NEWCOMER_LOYALTY := 20.0
const TAKE_OVER_MOOD := 40.0
const TAKE_OVER_LOYALTY := 40.0
const KILLED_BY_DEAD_M := 3.0
const DESERT_M := Vector2(60.0, 85.0)
const FAVOUR_FROM_M := Vector2(40.0, 90.0)
const FAVOUR_REACH_M := 12.0
const FAVOUR_CLEAR_M := 20.0
const PROMISE_DAYS := 3.0
const COMPANION_AROUND_M := 3.0
const SHOVEL_TAGS := ["shovel", "etool"]

var level: SurvivalLevel
## Every peer: {path from the level: {"id", "status", "name", "buried"}}.
var known := {}
## Every peer: this zone's graves ([{pos, name, id, day}]).
var graves: Array = []
## Host: what survivors said ([{speaker, id, text, time}], tests and the journal).
var said: Array = []
var graves_node: Node3D

var _bodies := {}  # host: id -> Soldier (live or dead bodies of records)
var _started := false
var _tick := 0.0
var _hour_index := -1
var _warned := {}
var _bury_jobs: Array = []
var _rng := RandomNumberGenerator.new()


static func find(from: Node) -> SurvivorsLayer:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group(GROUP) as SurvivorsLayer


## Every person's record, by id (Survival.state()["people"]).
static func records() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func record(id: String) -> Dictionary:
	return records().get(id, {})


## The shovel `s` carries: an item tagged shovel or etool, stowed, worn or held; &"" for none.
static func shovel_of(s: Soldier) -> StringName:
	for e: Dictionary in Survival.kit_of(s.inventory):
		var item := ItemDB.get_item(StringName(String(e.id)))
		if item and SHOVEL_TAGS.any(func(t: String) -> bool: return t in item.tags):
			return item.id
	return &""


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	add_to_group(GROUP)
	level = get_parent() as SurvivalLevel
	graves_node = Node3D.new()
	graves_node.name = "Graves"
	add_child(graves_node)
	_rng.seed = hash([int(Survival.state().get("seed", 0)), "people_rng"])
	if multiplayer.is_server():
		Net.peer_joined.connect(_on_peer_joined)


# --- Who's who (every peer) ----------------------------------------------------------------------

func _key(s: Node) -> String:
	return str(level.get_path_to(s)) if level and s and s.is_inside_tree() else ""


## What every peer knows of `s`: {"id", "status", "name", "buried"} or {}.
func info_of(s: Node) -> Dictionary:
	return known.get(_key(s), {})


## Host: the record of the survivor body `s` ({} for anyone else).
func record_of(s: Node) -> Dictionary:
	if s == null or not is_instance_valid(s):
		return {}
	var id := String(s.get_meta(&"survivor_id", info_of(s).get("id", "")))
	return record(id) if id != "" else {}


## Host: the live body of the record `id`, or null.
func body_of(id: String) -> Soldier:
	var s: Variant = _bodies.get(id)
	return s as Soldier if s != null and is_instance_valid(s) and not (s as Node).is_queued_for_deletion() else null


## Host: every companion's body here.
func companions() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for id: String in _bodies:
		var s := body_of(id)
		if s and s.vitals.is_up() and String(record(id).get("status", "")) == "companion":
			out.append(s)
	return out


func _set_known(s: Soldier, rec: Dictionary) -> void:
	var key := _key(s)
	if key == "":
		return
	var info := {"id": String(rec.id), "status": String(rec.status), "name": String(rec.name), "buried": bool(rec.get("buried", false))}
	known[key] = info
	if _has_peers():
		_client_known.rpc(key, info)


func _forget(s: Soldier) -> void:
	var key := _key(s)
	if key == "" or not known.has(key):
		return
	known.erase(key)
	if _has_peers():
		_client_known.rpc(key, {})


func _has_peers() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty()


## A companion's state for the gear editor (CompanionGear.info_of), from the host (LoadoutGear).
signal gear_info(info: Dictionary)


@rpc("authority", "call_remote", "reliable")
func _client_gear_info(info: Dictionary) -> void:
	gear_info.emit(info)


@rpc("authority", "call_remote", "reliable")
func _client_known(key: String, info: Dictionary) -> void:
	if info.is_empty():
		known.erase(key)
	else:
		known[key] = info


@rpc("authority", "call_remote", "reliable")
func _client_all(all: Dictionary, zone_graves: Array) -> void:
	known = all
	graves = zone_graves
	_build_graves()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_client_all.rpc_id(id, known, graves)


# --- Host: the zone comes up -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or level == null or not Survival.running:
		return
	if not _started:
		if bool(level.get(&"_ai_ready")) and level.players.get_child_count() > 0:
			_server_start()
		return
	_tick += delta
	if _tick < TICK_S:
		return
	_tick = 0.0
	server_tick()
	var h := floori(Moods.now_h())
	if h != _hour_index:
		var first := _hour_index < 0
		_hour_index = h
		if not first:
			server_hour()


func _zone() -> String:
	return String(Survival.state().get("zone", ""))


## Host: the zone's people: placed once per zone, companions brought along, the dead's bodies
## found again, the graves built.
func _server_start() -> void:
	_started = true
	_hour_index = floori(Moods.now_h())
	var zone := _zone()
	var placed: Dictionary = Survival.state().get("people_placed", {})
	if not placed.has(zone):
		placed[zone] = true
		Survival.state()["people_placed"] = placed
		server_place_zone(zone)
	var lead := _lead_player()
	for id: String in records().keys():
		var rec: Dictionary = records()[id]
		match String(rec.get("status", "")):
			"companion":
				var at := lead.global_position if lead else SurvivorPerson.pos_of(rec)
				if String(rec.get("zone", "")) == zone and SurvivorPerson.pos_of(rec) != Vector3.ZERO and lead and SurvivorPerson.pos_of(rec).distance_to(at) < LIVE_M:
					at = SurvivorPerson.pos_of(rec)  # (Continue in the same zone: where they were)
				else:
					var a := _rng.randf() * TAU
					at = at + Vector3(cos(a), 0.0, sin(a)) * COMPANION_AROUND_M
				server_spawn_companion(rec, level.ground_point(at))
			"dead":
				if String(rec.get("zone", "")) == zone and not bool(rec.get("buried", false)) and not bool(rec.get("risen", false)):
					_find_body(rec)
	_send_graves()
	server_tick()


func _lead_player() -> Soldier:
	var ps := MapNodes.players(level)
	ps.sort_custom(func(a: Soldier, b: Soldier) -> bool: return a.name.to_int() < b.name.to_int())
	return ps[0] if not ps.is_empty() else null


## Host: a dead record's body after a Continue (the zone save brings it back as a plain body):
## the dead body nearest where they fell.
func _find_body(rec: Dictionary) -> void:
	var at := SurvivorPerson.pos_of(rec, "body_pos")
	var best: Soldier = null
	for n in get_tree().get_nodes_in_group(&"dead_bodies"):
		var b := n as Soldier
		if b and b.global_position.distance_to(at) < 3.0 and (best == null or b.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = b
	if best:
		best.set_meta(&"survivor_id", String(rec.id))
		_bodies[String(rec.id)] = best
		_set_known(best, rec)


## Host: lone survivors for a new zone: PER_ZONE (plus one a village, up to VILLAGE_BONUS_MAX),
## each about a site (holed up in a house, at a camp, wandering), by the world's seed.
func server_place_zone(zone: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(Survival.state().get("seed", 0)), zone, "people"])
	var sites: Array = level.modules()
	var villages := sites.filter(func(m: ZoneModule) -> bool: return ZoneModules.base(String(m.type)) in ["village", "town", "farm"])
	var n := rng.randi_range(PER_ZONE.x, PER_ZONE.y) + mini(villages.size(), VILLAGE_BONUS_MAX)
	var made: Array = []
	var area: Rect2 = level.map_area()
	for i in n:
		var site: ZoneModule = null
		if not villages.is_empty() and rng.randf() < 0.7:
			site = villages[rng.randi_range(0, villages.size() - 1)]
		elif not sites.is_empty():
			site = sites[rng.randi_range(0, sites.size() - 1)]
		var centre := site.global_position if site else Vector3(area.get_center().x, 0.0, area.get_center().y)
		var a := rng.randf() * TAU
		var at := centre + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(PLACE_FROM_SITE_M.x, PLACE_FROM_SITE_M.y)
		at = _on_nav(at)
		var rec := SurvivorPerson.make(rng, _new_id())
		var where: String = ["holed up in a house", "at a camp", "wandering"][rng.randi_range(0, 2)]
		_place(rec, zone, at)
		SurvivorPerson.note(rec, "%s near %s" % [where, String(site.type) if site else "the road"])
		made.append(rec)
	SessionLog.note("survival: %d lone survivors placed in %s" % [made.size(), zone])
	return made


func _new_id() -> String:
	var n := int(Survival.state().get("people_next", 1))
	Survival.state()["people_next"] = n + 1
	return "p%d" % n


func _place(rec: Dictionary, zone: String, at: Vector3) -> void:
	rec.zone = zone
	rec.status = "out_there"
	SurvivorPerson.set_pos(rec, at)
	SurvivorPerson.set_pos(rec, at, "home")
	records()[String(rec.id)] = rec


func _on_nav(at: Vector3) -> Vector3:
	var map := level.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, at)
	return level.ground_point(p if p != Vector3.ZERO and p.distance_to(at) < 25.0 else at)


## Host: a survivor made here at `at` (tests, the cold open's first neighbour later): `opts`
## override the record (SurvivorPerson.make). Their body comes at once when a player is in range.
func server_add_person(at: Vector3, opts := {}) -> Dictionary:
	var rec := SurvivorPerson.make(_rng, _new_id(), opts)
	_place(rec, _zone(), at)
	if _near_player(at, LIVE_M):
		_spawn_person(rec)
	return rec


func _near_player(at: Vector3, within: float) -> bool:
	for p: Soldier in MapNodes.players(level):
		if p.global_position.distance_to(at) <= within:
			return true
	return false


# --- Host: bodies -------------------------------------------------------------------------------

## A lone survivor's body (PeopleLayer's person, kind "survivor"), in their kit.
func _spawn_person(rec: Dictionary) -> Soldier:
	if level.people == null:
		return null
	var id := String(rec.id)
	var s := level.people.server_spawn_person({"name": ("Surv_" + id).validate_node_name(), "kind": "survivor", "side": "neutral",
		"label": String(rec.name), "pos": SurvivorPerson.pos_of(rec), "look": String(rec.look), "face": String(rec.get("face", ""))})
	if s == null:
		return null
	_dress(s, rec)
	_bodies[id] = s
	_set_known(s, rec)
	return s


## Host: `s` takes `rec`'s kit, needs (the same dictionary) and name.
func _dress(s: Soldier, rec: Dictionary) -> void:
	s.inventory.strip()
	for e: Dictionary in rec.get("kit", []):
		if ItemDB.get_item(StringName(String(e.id))) != null:
			s.inventory.take(StringName(String(e.id)), int(e.get("count", 1)), GameState.from_json(e.get("state", {})))
	Clothing.dress_if_bare(s.inventory, String(rec.id))  # their own clothes (call 132)
	if not rec.get("needs") is Dictionary or (rec.needs as Dictionary).is_empty():
		rec["needs"] = Needs.fresh()
	Needs.ensure(rec.needs)
	s.set_meta(&"needs", rec.needs)
	s.set_meta(&"survivor_id", String(rec.id))
	s.set_meta(&"survivor_name", String(rec.name))
	if not s.died_for_good.is_connected(_on_died):
		s.died_for_good.connect(_on_died)


## Host: `rec`'s companion body at `at`: a friendly AI squadmate (the level's spawn_soldier, no
## role kit: their own), named by their first name (a callsign for voice orders), on the players'
## squad following its lead, with a CompanionAI beside its SquadAI.
func server_spawn_companion(rec: Dictionary, at: Vector3) -> Soldier:
	var first := String(rec.get("first", String(rec.name).get_slice(" ", 0))).validate_node_name()
	var node_name := first
	var lap := 2
	while level.ai.get_node_or_null(NodePath(node_name)) != null:
		node_name = "%s %d" % [first, lap]
		lap += 1
	var female := String(rec.get("sex", "m")) == "f"
	var s := level.spawn_soldier({"name": node_name, "faction": "friendly", "variant": String(rec.look), "body": VoxelArt.FEMALE if female else VoxelArt.MALE,
		"face": String(rec.get("face", "")), "person_name": String(rec.name), "nation": "US", "pos": at, "loadout": [], "role": "",
		"team": -1, "slot": -1, "combat": 0.45, "discipline": 0.5, "guard": false, "spawn_id": "surv_" + String(rec.id)})
	if s == null:
		return null
	_dress(s, rec)
	rec.status = "companion"
	rec.zone = _zone()
	SurvivorPerson.set_pos(rec, at)
	var brain := CompanionAI.new()
	brain.name = CompanionAI.NODE_NAME
	brain.rec = rec
	brain.layer = self
	s.add_child(brain)
	var squad := level.squad_for(&"friendly")
	if squad and not is_instance_valid(squad.leader):
		squad.leader = _lead_player()
	_bodies[String(rec.id)] = s
	_set_known(s, rec)
	return s


## Host: the survivor `rec` joins (TalkMenu: their want met): their person body goes and a
## companion takes its place where they stood.
func server_recruit(rec: Dictionary, by: Soldier) -> Soldier:
	var body := body_of(String(rec.id))
	var at := body.global_position if body else SurvivorPerson.pos_of(rec)
	if body:
		_forget(body)
		body.queue_free()
	_bodies.erase(String(rec.id))
	rec.erase("grudge")
	Moods.add(rec, "joined")
	var w: Dictionary = rec.get("want", {})
	if String(w.get("kind", "")) == "favour" and w.has("mark_pos"):
		_drop_mark(w)
	SurvivorPerson.note(rec, "joined %s" % Survival.survivor_name(by) if by else "joined the group")
	Survival._journal_line("%s joined us (%s)." % [String(rec.name), SurvivorPerson.want_text(rec)])
	var s := server_spawn_companion(rec, at)
	if s and by:
		var brain := SquadAI.of(s)
		if brain:
			brain.on_order(Squad.Order.FOLLOW, by.global_position)
	return s


## Host: what's said: a subtitle for players near the speaker (PeopleLayer.server_say), else a
## message flash to the nearest player; kept in `said`.
func say(speaker: Soldier, text: String) -> void:
	if text == "" or speaker == null or not is_instance_valid(speaker):
		return
	said.append({"speaker": speaker.display_name(), "id": String(speaker.get_meta(&"survivor_id", "")), "text": text, "time": Soldier._now()})
	said = said.slice(-60)
	var shown := level.people != null and level.people.server_say(speaker, text)
	if not shown:
		for p: Soldier in MapNodes.players(level):
			if p.global_position.distance_to(speaker.global_position) <= PeopleLayer.SAY_RADIUS_M:
				Survival._tell(p, "%s: %s" % [speaker.display_name(), text])


## Host: `rec` says their line for `topic` (TalkMenu.line_for), if they have a body.
func say_topic(rec: Dictionary, topic: String, extra := {}) -> String:
	var s := body_of(String(rec.id))
	if s == null or not s.vitals.is_up():
		return ""
	var line := TalkMenu.line_for(rec, topic, extra)
	say(s, line)
	return line


## Host: one thing a frightened survivor drops at their feet (a threat: TalkMenu), its name or "".
func server_drop_one(s: Soldier) -> String:
	var rec := record_of(s)
	for c: StringName in s.inventory.search_containers():
		var list: Array = s.inventory.containers[c]
		if list.is_empty():
			continue
		var e: Dictionary = s.inventory.remove_entry(c, list.size() - 1, 1)
		if e.is_empty():
			continue
		level.server_spawn_dropped(StringName(String(e.id)), 1, s.global_position + s.global_basis.z * -0.6 + Vector3.UP * 0.4, e.get("state", {}))
		if not rec.is_empty():
			rec.kit = Survival.kit_of(s.inventory)
		var item := ItemDB.get_item(StringName(String(e.id)))
		return item.name if item else String(e.id)
	return ""


## Host: a live body's place, kit and zone into its record.
func _store(rec: Dictionary, s: Soldier) -> void:
	if s == null or not is_instance_valid(s) or s.vitals.is_dead():
		return
	SurvivorPerson.set_pos(rec, s.global_position)
	rec.kit = Survival.kit_of(s.inventory)
	rec.zone = _zone()


## Host (Survival.server_save): every live body's record brought up to date.
func server_store_all() -> void:
	for id: String in _bodies:
		var s := body_of(id)
		if s and s.vitals.is_up():
			_store(record(id), s)


# --- Host: the tick ------------------------------------------------------------------------------

## Host, every TICK_S: lone survivors in and out of LIVE range, warnings, fright at the dead,
## favours, burials under way, the dead rising.
func server_tick() -> void:
	var players := MapNodes.players(level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	var zone := _zone()
	var dead := Survival.zombies(level)
	var now := Soldier._now()
	for id: String in records().keys():
		var rec: Dictionary = records()[id]
		var status := String(rec.get("status", ""))
		if String(rec.get("zone", "")) != zone:
			continue
		if status == "out_there":
			var s := body_of(id)
			var at := s.global_position if s else SurvivorPerson.pos_of(rec)
			var d := INF
			var nearest: Soldier = null
			for p: Soldier in players:
				var pd := p.global_position.distance_to(at)
				if pd < d:
					d = pd
					nearest = p
			if s == null and d <= LIVE_M:
				s = _spawn_person(rec)
			elif s and d > DESPAWN_M:
				_store(rec, s)
				_forget(s)
				s.queue_free()
				_bodies.erase(id)
				continue
			if s and s.vitals.is_up():
				if nearest and d <= WARN_M and String(rec.get("disposition", "friendly")) != "friendly" and now - float(_warned.get(id, -1000.0)) > WARN_GAP_S:
					_warned[id] = now
					say(s, TalkMenu.line_for(rec, "warn"))
				for z: Soldier in dead:
					if z.global_position.distance_to(s.global_position) <= SCARE_M:
						var brain := s.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI
						if brain:
							brain.alarm(z.global_position)
						break
			_check_favour(rec, players, dead)
		elif status == "dead":
			_check_rise(rec, now)
	_tick_burials(now)


## Host, every world hour: moods (Moods.hour_tick: needs' conditions, expiry, breaks), a horde
## seen, bodies left out (mood and pressure), promises broken.
func server_hour() -> void:
	var night := Survival.hour() >= 21.0 or Survival.hour() < 5.0
	Sickness.server_spread_people(records().values(), 1.0)  # colds and flu pass between people living together (phase D)
	var crowd := ZoneDead.of(level)
	var horde := crowd != null and crowd.horde_count() > 0
	var zone := _zone()
	for id: String in records().keys():
		var rec: Dictionary = records()[id]
		match String(rec.get("status", "")):
			"companion", "settler":
				if horde and String(rec.get("zone", "")) == zone and not Moods.has(rec, "saw_horde"):
					Moods.add(rec, "saw_horde")
				var n: Dictionary = rec.get("needs", {})
				if not n.is_empty() and float(n.get("sleep", 100.0)) < 10.0:
					Moods.add(rec, "no_sleep")
				Mind.person_hour(rec, horde)  # nerve and habits in the mood (Mind)
				var kind := Moods.hour_tick(rec, night, _rng)
				if kind != "":
					_on_break(rec, kind)
			"out_there":
				Moods.expire(rec)
				_check_promise(rec)
			"dead":
				if String(rec.get("zone", "")) == zone and not bool(rec.get("buried", false)) and not bool(rec.get("risen", false)):
					Survival._raise_pressure(level, SurvivorPerson.pos_of(rec, "body_pos"), BODY_PRESSURE_DAY / 24.0)


# --- Host: breaks (call 75) ------------------------------------------------------------------------

func _on_break(rec: Dictionary, kind: String) -> void:
	var s := body_of(String(rec.id))
	say_topic(rec, "break_" + kind)
	Survival._journal_line("%s broke down (%s)." % [String(rec.name), kind])
	if s == null:
		return
	var brain := SquadAI.of(s)
	match kind:
		"crying", "hiding":
			if brain:
				brain.on_order(Squad.Order.HOLD, s.global_position)  # useless for a while, where they are
		"rage":
			for other: Soldier in companions():
				if other != s:
					var orec := record_of(other)
					SurvivorPerson.change_relation(rec, String(orec.id), -20.0)
					SurvivorPerson.change_relation(orec, String(rec.id), -20.0)
					break
		"binge":
			var ai := CompanionAI.of(s)
			if ai:
				ai.eat_any(2)
		"desertion":
			server_desert(rec)


## Host: `rec` leaves the group (a desertion: at night, with their kit): a lone survivor again
## DESERT_M off, with a grudge when their mood or their opinion of the players is low.
func server_desert(rec: Dictionary) -> void:
	var s := body_of(String(rec.id))
	var from := s.global_position if s else SurvivorPerson.pos_of(rec)
	if s:
		_store(rec, s)
		_forget(s)
		s.queue_free()
	_bodies.erase(String(rec.id))
	var opinions: Dictionary = rec.get("opinion_of_players", {})
	var avg := 0.0
	for k: String in opinions:
		avg += float(opinions[k]) / maxf(1.0, opinions.size())
	rec["grudge"] = Moods.mood(rec) < 10.0 or avg < 0.0
	rec["break"] = ""
	rec["low_hours"] = 0.0
	var a := _rng.randf() * TAU
	var at := _on_nav(from + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(DESERT_M.x, DESERT_M.y))
	_place(rec, _zone(), at)
	rec.want = SurvivorPerson.roll_want(_rng)
	SurvivorPerson.note(rec, "left the group%s" % (" with a grudge" if rec.grudge else ""))
	Survival._journal_line("%s left in the night." % String(rec.name))


# --- Host: favours and promises ---------------------------------------------------------------------

## Host: `rec`'s favour gets its place on the map (a mark) and its promise clock; a fetch puts
## the thing there.
func server_mark_favour(rec: Dictionary, near: Vector3) -> void:
	var w: Dictionary = rec.get("want", {})
	if String(w.get("kind", "")) != "favour" or w.has("mark_pos"):
		return
	var a := _rng.randf() * TAU
	var at := _on_nav(near + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(FAVOUR_FROM_M.x, FAVOUR_FROM_M.y))
	w["mark_pos"] = [at.x, at.y, at.z]
	w["zone"] = _zone()
	w["promised"] = Moods.now_h()
	var text := "%s: %s" % [String(rec.get("first", rec.name)), "clear the dead" if String(w.get("task", "")) == "clear" else "fetch"]
	SurvivalMap.server_add_mark(_zone(), at, text, "favour")
	if String(w.get("task", "")) == "fetch" and String(w.get("item", "")) != "" and ItemDB.get_item(StringName(String(w.item))) != null:
		level.server_spawn_dropped(StringName(String(w.item)), 1, at + Vector3.UP * 0.4)
	var map := SurvivalMap.of(level)
	if map:
		map.server_changed()


func _drop_mark(w: Dictionary) -> void:
	var all := SurvivalMap.marks("")
	var p: Array = w.get("mark_pos", [])
	for i in all.size():
		var m: Dictionary = all[i]
		if String(m.get("kind", "")) == "favour" and p.size() >= 3 and SurvivalMap.mark_pos(m).distance_to(Vector2(float(p[0]), float(p[2]))) < 0.5:
			SurvivalMap.server_remove_mark(i)
			return


## Host: a player at a favour's place: a clear done when no dead are left near it, a fetch when
## they've been there (the thing itself is checked when they recruit).
func _check_favour(rec: Dictionary, players: Array, dead: Array) -> void:
	var w: Dictionary = rec.get("want", {})
	if String(w.get("kind", "")) != "favour" or bool(w.get("done", false)) or not w.has("mark_pos") or String(w.get("zone", "")) != _zone():
		return
	var p: Array = w.mark_pos
	var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var there: Soldier = null
	for pl: Soldier in players:
		if pl.global_position.distance_to(at) <= FAVOUR_REACH_M:
			there = pl
	if there == null:
		return
	if String(w.get("task", "")) == "clear" and dead.any(func(z: Soldier) -> bool: return z.global_position.distance_to(at) <= FAVOUR_CLEAR_M):
		return
	server_favour_done(rec, there)


## Host: `rec`'s favour is done (by `by`): the promise kept.
func server_favour_done(rec: Dictionary, by: Soldier = null) -> void:
	var w: Dictionary = rec.get("want", {})
	if bool(w.get("done", false)):
		return
	w["done"] = true
	if not bool(w.get("broken", false)):
		Moods.add(rec, "promise_kept")
	if by:
		SurvivorPerson.change_opinion(rec, Survival.profile_of(by), 10.0)
		Survival._tell(by, "Done. Go back to %s." % String(rec.get("first", rec.name)))
	Survival._journal_line("The favour for %s is done." % String(rec.name))


func _check_promise(rec: Dictionary) -> void:
	var w: Dictionary = rec.get("want", {})
	if String(w.get("kind", "")) != "favour" or bool(w.get("done", false)) or bool(w.get("broken", false)) or not w.has("promised"):
		return
	if Moods.now_h() - float(w.promised) > PROMISE_DAYS * 24.0:
		w["broken"] = true
		Moods.add(rec, "promise_broken")


# --- Host: death, grief, graves, the rise (section 8, call 77) -----------------------------------------

func _on_died(s: Soldier) -> void:
	if not is_instance_valid(s) or not s.has_meta(&"survivor_id"):
		return
	var rec := record_of(s)
	if rec.is_empty() or String(rec.get("status", "")) == "dead":
		return
	var was := String(rec.status)
	rec.kit = Survival.kit_of(s.inventory)
	rec.status = "dead"
	rec.died_day = Survival.day()
	rec.zone = _zone()
	SurvivorPerson.set_pos(rec, s.global_position, "body_pos")
	rec.killed_by_dead = _killed_by_dead(s)
	rec.rise_at = Soldier._now() + RISE_S if bool(rec.killed_by_dead) else 0.0
	_set_known(s, rec)
	Survival._journal_line("%s died." % String(rec.name))
	Nerve.server_on_death(s, rec, was)  # the living's nerve, the killer's (Mind)
	if was != "companion" and was != "settler":
		return
	var id := String(rec.id)
	for other_id: String in records().keys():
		var o: Dictionary = records()[other_id]
		if other_id == id or not String(o.get("status", "")) in ["companion", "settler"]:
			continue
		var friend := SurvivorPerson.relation(o, id) >= FRIEND_AT or SurvivorPerson.relation(rec, other_id) >= FRIEND_AT
		Moods.add(o, ("friend_died:" if friend else "companion_died:") + id)
		Moods.add(o, "body_left_out:" + id)
		SurvivorPerson.note(o, "lost %s" % String(rec.name))
	var mourner := _nearest_companion(s.global_position)
	if mourner:
		say_topic(record_of(mourner), "grief")


func _nearest_companion(at: Vector3) -> Soldier:
	var best: Soldier = null
	for c: Soldier in companions():
		if best == null or c.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = c
	return best


## Whether the dead killed `s`: the last hit was theirs, one of them is on the body, or a test
## says so (meta "killed_by_dead").
func _killed_by_dead(s: Soldier) -> bool:
	if bool(s.get_meta(&"killed_by_dead", false)):
		return true
	if String(Harm.last(s).get("faction", "")) == String(ZombieAI.INFECTED):
		return true
	for z: Soldier in Survival.zombies(level):
		if z.global_position.distance_to(s.global_position) <= KILLED_BY_DEAD_M:
			return true
	return false


## Host: `actor` starts burying the dead survivor `body`: BURY_S with a shovel, slower by hand;
## he must stay by it (server_tick finishes or cancels it).
func server_start_bury(actor: Soldier, body: Soldier) -> String:
	var rec := record_of(body)
	if rec.is_empty() or String(rec.get("status", "")) != "dead" or bool(rec.get("buried", false)):
		return "Nothing to bury"
	if actor.global_position.distance_to(body.body_point() if body.has_method(&"body_point") else body.global_position) > BURY_REACH_M + 1.0:
		return "Too far"
	var secs := float(BURY_S.shovel if shovel_of(actor) != &"" else BURY_S.hands)
	_bury_jobs.append({"actor": actor, "body": body, "until": Soldier._now() + secs})
	actor.server_busy(secs, "Burying %s" % String(rec.name))
	return ""


func _tick_burials(now: float) -> void:
	for job: Dictionary in _bury_jobs.duplicate():
		var ok: bool = is_instance_valid(job.actor) and is_instance_valid(job.body)
		var actor: Soldier = job.actor if ok else null
		var body: Soldier = job.body if ok else null
		if not ok or not actor.vitals.is_up() or actor.global_position.distance_to(body.global_position) > BURY_REACH_M + 2.0:
			_bury_jobs.erase(job)
			if is_instance_valid(job.actor):
				Survival._tell(job.actor, "You stop digging")
			continue
		if now >= float(job.until):
			_bury_jobs.erase(job)
			server_bury(actor, body)


## Host: the dead survivor `body` is buried (by `by`, may be null): their kit laid by the grave
## (Proposed: nothing of theirs is lost), the body gone, a grave marker saved with the zone; the
## others' grief eases (friend_died halved, the body no longer left out, a grave moodlet).
func server_bury(by: Soldier, body: Soldier) -> bool:
	var rec := record_of(body)
	if rec.is_empty() or bool(rec.get("buried", false)):
		return false
	var at := body.global_position
	var entries := body.inventory.strip()
	for i in entries.size():
		var e: Dictionary = entries[i]
		level.server_spawn_dropped(StringName(String(e.id)), int(e.get("count", 1)), at + Vector3(0.9 + 0.25 * (i % 3), 0.4, 0.3 * (i / 3)), e.get("state", {}))
	rec.kit = []
	rec.buried = true
	rec.rise_at = 0.0
	var gs: Array = Survival.state().get(GRAVES_KEY, [])
	gs.append({"zone": _zone(), "pos": [at.x, at.y, at.z], "id": String(rec.id), "name": String(rec.name), "day": Survival.day()})
	Survival.state()[GRAVES_KEY] = gs
	var id := String(rec.id)
	for other_id: String in records().keys():
		var o: Dictionary = records()[other_id]
		if not String(o.get("status", "")) in ["companion", "settler"]:
			continue
		var friend := Moods.has(o, "friend_died:" + id)
		if friend:
			Moods.add(o, "friend_died:" + id, Moods.value_of(o, "friend_died:" + id) * 0.5)
		Moods.remove(o, "body_left_out:" + id)
		Moods.add(o, ("grave_for_friend:" if friend else "grave:") + id)
	_forget(body)
	_bodies.erase(id)
	body.queue_free()
	Survival._journal_line("%s was buried%s." % [String(rec.name), (" by " + Survival.survivor_name(by)) if by else ""])
	var mourner := _nearest_companion(at)
	if mourner:
		say_topic(record_of(mourner), "bury_thanks")
	_send_graves()
	return true


## Host: a dead survivor killed by the dead rises RISE_S after, unless buried or their head is
## gone (meta "head_destroyed": the gore system sets it later): one of the dead at the body in
## their kit; the body goes.
func _check_rise(rec: Dictionary, now: float) -> void:
	if bool(rec.get("buried", false)) or bool(rec.get("risen", false)) or float(rec.get("rise_at", 0.0)) <= 0.0 or now < float(rec.rise_at):
		return
	var body := body_of(String(rec.id))
	if body == null or bool(body.get_meta(&"head_destroyed", false)):
		rec.rise_at = 0.0
		return
	server_rise(rec)


func server_rise(rec: Dictionary) -> Soldier:
	var body := body_of(String(rec.id))
	if body == null:
		return null
	var at := body.global_position
	var entries := body.inventory.strip()
	_forget(body)
	_bodies.erase(String(rec.id))
	body.queue_free()
	var z := Survival.server_spawn_zombie(level, level.ground_point(at), "walker")
	rec.risen = true
	rec.rise_at = 0.0
	rec.kit = []
	if z:
		for e: Dictionary in entries:
			z.inventory.take(StringName(String(e.id)), int(e.get("count", 1)), e.get("state", {}))
		z.person_name = String(rec.name)
		z.set_meta(&"risen_id", String(rec.id))
		z.died_for_good.connect(_on_risen_down.bind(String(rec.id)))
	Survival._journal_line("%s rose." % String(rec.name))
	return z


func _on_risen_down(_z: Soldier, id: String) -> void:
	var rec := record(id)
	if rec.is_empty():
		return
	rec.put_down = true
	for other_id: String in records().keys():
		var o: Dictionary = records()[other_id]
		if String(o.get("status", "")) in ["companion", "settler"]:
			Moods.remove(o, "body_left_out:" + id)
			Moods.add(o, "put_down_friend:" + id, NAN if Moods.has(o, "friend_died:" + id) else -5.0)
	var mourner := companions()
	if not mourner.is_empty():
		say_topic(record_of(mourner[0]), "put_down")


func _send_graves() -> void:
	var zone := _zone()
	graves = (Survival.state().get(GRAVES_KEY, []) as Array).filter(func(g: Dictionary) -> bool: return String(g.get("zone", "")) == zone)
	_build_graves()
	if _has_peers():
		_client_all.rpc(known, graves)


## A grave marker per grave here: a mound and a cross (every peer).
func _build_graves() -> void:
	if graves_node == null:
		return
	for c in graves_node.get_children():
		c.queue_free()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.18)
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(0.27, 0.22, 0.16)
	for g: Dictionary in graves:
		var p: Array = g.get("pos", [0, 0, 0])
		var marker := Node3D.new()
		marker.name = ("Grave_" + String(g.get("id", "x"))).validate_node_name()
		marker.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		marker.set_meta(&"grave_of", String(g.get("name", "")))
		for part: Array in [[Vector3(0.8, 0.18, 1.8), Vector3(0.0, 0.09, 0.0), dirt], [Vector3(0.08, 1.0, 0.08), Vector3(0.0, 0.5, -0.8), wood],
				[Vector3(0.5, 0.08, 0.08), Vector3(0.0, 0.72, -0.8), wood]]:
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = part[0]
			mesh.mesh = box
			mesh.position = part[1]
			mesh.material_override = part[2]
			marker.add_child(mesh)
		graves_node.add_child(marker)


# --- Host: a player's death and the take-over (calls 13, 51) ------------------------------------------

## Host (Survival.server_player_died): the player `s` lost his survivor `old_name`: companions
## grieve (a friend if they thought well of him), those willing (mood and loyalty) may be taken
## over, and the newcomer is a stranger to every one of them (opinion 0, loyalty low).
func server_on_player_died(s: Soldier, old_name: String) -> Array:
	var profile := Survival.profile_of(s)
	var willing: Array = []
	for id: String in records().keys():
		var rec: Dictionary = records()[id]
		if String(rec.get("status", "")) != "companion":
			continue
		var friend := SurvivorPerson.opinion_of(rec, profile) >= FRIEND_AT
		if Moods.mood(rec) >= TAKE_OVER_MOOD and float(rec.get("loyalty", 0.0)) >= TAKE_OVER_LOYALTY:
			rec["take_over_ok"] = profile
			willing.append(String(rec.get("first", rec.name)))
		Moods.add(rec, ("friend_died:" if friend else "lost_their_player:") + profile)
		(rec.opinion_of_players as Dictionary)[profile] = 0.0
		rec.loyalty = minf(float(rec.get("loyalty", 0.0)), NEWCOMER_LOYALTY)
		SurvivorPerson.note(rec, "%s died" % old_name)
		say_topic(rec, "newcomer")
	if not willing.is_empty() and not s.is_ai():
		s._client_message.rpc_id(s.owner_peer(), "Or take over a companion: %s (the take-over screen comes later)" % ", ".join(willing))
	return willing


## Host: `player` takes over the companion `companion_id` (call 51): his survivor record becomes
## theirs (name; their kit and needs on his body, where they stood), their companion body goes, the
## record's status is "player"; the others see that person lead now (their opinion of the player
## is their relation to them). Only a willing companion (server_on_player_died), or `force`.
func server_take_over(player: Soldier, companion_id: String, force := false) -> bool:
	var rec := record(companion_id)
	var body := body_of(companion_id)
	var profile := Survival.profile_of(player)
	if rec.is_empty() or String(rec.get("status", "")) != "companion" or body == null or not body.vitals.is_up():
		return false
	if not force and String(rec.get("take_over_ok", "")) != profile:
		return false
	var srec := Survival.survivor_of(player)
	srec["name"] = String(rec.name)
	srec["taken_over"] = companion_id
	player.set_meta(&"survivor_name", String(rec.name))
	var entries := body.inventory.strip()
	player.inventory.strip()  # (the newcomer's starter kit: he's them now)
	for e: Dictionary in entries:
		player.inventory.take(StringName(String(e.id)), int(e.get("count", 1)), e.get("state", {}))
	var n := Survival.needs_of(player)
	Needs.restore(n, (rec.get("needs", {}) as Dictionary).duplicate(true))
	Needs.apply(player, n)
	var at := body.global_position
	var yaw := body.rotation.y
	_forget(body)
	_bodies.erase(companion_id)
	body.queue_free()
	player.server_place(at, yaw)
	rec.status = "player"
	rec["player_profile"] = profile
	rec.erase("take_over_ok")
	for other_id: String in records().keys():
		var o: Dictionary = records()[other_id]
		if other_id != companion_id and String(o.get("status", "")) == "companion":
			(o.opinion_of_players as Dictionary)[profile] = SurvivorPerson.relation(o, companion_id)
	Survival._journal_line("%s leads now." % String(rec.name))
	Survival._send_needs(player)
	Survival._tell(player, "You are %s now." % String(rec.name))
	return true


# --- Host: settlers (Settlement, docs/survival_building.md §5, call 23) -------------------------------

## Host: `rec` becomes a settler (a survivor whose want is a place, or a companion made one):
## their body here goes (a person body comes back at home when the settlement's zone is played
## near a player: server_settler_body); they live at the settlement from now on.
func server_settle(rec: Dictionary, by: Soldier = null) -> void:
	var s := body_of(String(rec.id))
	if s:
		_store(rec, s)
		_forget(s)
		s.queue_free()
	_bodies.erase(String(rec.id))
	Settlement.server_make_settler(rec, by)


## Host: a settler's body at home on (a person like a lone survivor's, standing about their spot)
## or off (the record kept). Returns the body (or null).
func server_settler_body(rec: Dictionary, on: bool) -> Soldier:
	var s := body_of(String(rec.id))
	if on and s == null:
		s = _spawn_person(rec)
	elif not on and s:
		_store(rec, s)
		_forget(s)
		s.queue_free()
		_bodies.erase(String(rec.id))
		s = null
	return s


## Host: "Take along": the settler `rec` comes with `by` as a companion again.
func server_take_along(rec: Dictionary, by: Soldier) -> Soldier:
	var body := body_of(String(rec.id))
	var at := body.global_position if body else (by.global_position + Vector3(1.5, 0.0, 0.0) if by else SurvivorPerson.pos_of(rec))
	server_settler_body(rec, false)
	Settlement.server_unsettle(rec)
	var c := server_spawn_companion(rec, level.ground_point(at))
	if c and by:
		var brain := SquadAI.of(c)
		if brain:
			brain.on_order(Squad.Order.FOLLOW, by.global_position)
	return c


# --- Every peer: talk requests ---------------------------------------------------------------------

## A player's talk entry (TalkMenu.actions_for), checked and answered on the host.
@rpc("any_peer", "call_local", "reliable")
func request_talk(action: String, path: NodePath, arg: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var actor := level.players.get_node_or_null(str(sender)) as Soldier
	var target := get_node_or_null(path) as Soldier
	if actor == null or target == null:
		return
	TalkMenu.server_talk(self, actor, target, action, arg)
