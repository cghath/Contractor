class_name PeopleLayer
extends Node3D
## People on the map for one level (wave 4, W11): civilians, HVTs, hostiles who give up, and
## the intel lying about. The level adds one as "People" on every peer (CompoundLevel._ready);
## a world module hosting people adds its own the same way, and calls the server_* API below.
##
## - Civilians and HVTs are Soldier bodies in the "civilian" faction (Person.FACTION): the
##   same hitboxes, wound model, carrying, bodies and replication as everyone else, with no
##   weapons. They spawn through this node's spawner (so late joiners get them) and the host
##   drives each with a CivilianAI, or HvtAI for an HVT, named BRAIN. Their looks are
##   placeholders behind PersonLook.dress.
## - Who each person is and what they're doing (kind, side, HVT id, cuffed, surrendered, who
##   leads them, their order, delivered) is `states`, decided by the host and sent to every
##   peer and late joiner by RPC. Person reads it.
## - The interaction menu's people actions (cuff, lead, stop, cover, search) and the command
##   menu's radio report arrive as request() and request_report(), checked on the host.
## - Every TICK_S the host banks intel carried into an extraction point (any node in
##   DeliveryPoint.GROUP), delivers HVTs brought there (the objective hook), and, when
##   surrender_enabled, lets badly hurt, isolated hostiles give up. What happens goes in the
##   People autoload's ledger.
## - Gunfire (Soldier._server_fire) and grenades (Grenade) make noise (server_noise) that
##   frightens people nearby.

const PLAYER_SCENE := preload("res://scenes/soldier.tscn")
const GROUP := &"people_layers"
## The brain's node name on a person's body (CivilianAI or HvtAI).
const BRAIN := &"PersonAI"

## Spawn the compound's placeholder people and intel (COMPOUND) when hosting. Off by
## default so the compound and the older test suites stay as they were; the main menu has a
## checkbox for it (Menu), and a mission sets it.
static var populate := false
## Let badly hurt, isolated hostiles surrender (proposed; optional in the spec). Off by default
## for the same reason; the main menu's checkbox turns it on with populate.
static var surrender_enabled := false
## Put a contract's people and intel in the level when it goes live (Contracts.contract_live):
## its HVT or hostage, the intel it places, civilians in the zone's modules and delivery
## points at the zone's landing zones. On by default; a test that drives objectives by hand
## turns it off.
static var contract_people := true

const TICK_S := 0.25
const SURRENDER_CHECK_S := 1.0
## Proposed surrender rule: a hostile up but at least this hurt (pain, or blood left at most
## SURRENDER_BLOOD, or injury), with no other hostile up within SURRENDER_ALONE_M and someone
## from the squad in sight within SURRENDER_SEEN_M, gives up with this chance per check.
const SURRENDER_PAIN := 0.6
const SURRENDER_BLOOD := 0.75
const SURRENDER_INJURY := 0.5
const SURRENDER_ALONE_M := 15.0
const SURRENDER_SEEN_M := 25.0
const SURRENDER_CHANCE := 0.35
## How far gunfire and explosions frighten people (proposed).
const GUNFIRE_HEARD_M := 45.0
const BLAST_HEARD_M := 70.0
## Reach for people actions, body to body (the interaction menu's, plus slack for lag).
const REACH := Soldier.INTERACT_REACH + Soldier.INTERACT_SLACK
## Moving this far (cuffer, or the one being cuffed) interrupts cuffing.
const CUFF_MOVE_M := 1.0
const CUFF_CHECK_S := 0.1
## Proposed: zip-cuffing takes this long when the item doesn't say (zip_cuffs "cuff_s").
const CUFF_S := 3.0
## An HVT counts as brought in when someone from the squad is this close (or leads or carries him).
const ESCORT_M := 6.0
## Radio report (proposed): hostiles within REPORT_RADIUS_M of the marked point, at least one
## in the reporter's sight within REPORT_RANGE_M, each worth REPORT_VALUE; an enemy already
## reported isn't again for REPORT_AGAIN_S.
const REPORT_RADIUS_M := 20.0
const REPORT_RANGE_M := 400.0
const REPORT_VALUE := 150
const REPORT_AGAIN_S := 300.0
## Subtitles from people reach players within this far, one line per speaker per SAY_GAP_S.
const SAY_RADIUS_M := 30.0
const SAY_GAP_S := 3.0
const SURRENDER_LINES: Array[String] = ["Don't shoot! I give up!", "Okay, okay! I surrender!"]

## The compound's placeholder content (populate): civilians on routines around the buildings
## and outside the gate, a hostile HVT in the main building, a friendly HVT (a hostage) in the
## shed, intel in the building and the container, zip cuffs with the gate loot and an
## extraction point south of the gate.
const COMPOUND := {
	"people": [
		{"name": "Civilian1", "kind": "civilian", "side": "neutral", "label": "Civilian (Farid)", "pos": Vector3(-8, 0.1, 12),
			"routine": [Vector3(-8, 0, 12), Vector3(-14, 0, 4), Vector3(-10, 0, -6), Vector3(-6, 0, 2)]},
		{"name": "Civilian2", "kind": "civilian", "side": "neutral", "label": "Civilian (Samira)", "pos": Vector3(8, 0.1, 14),
			"routine": [Vector3(8, 0, 14), Vector3(13, 0, 8), Vector3(14, 0, -3), Vector3(10, 0, 0)]},
		{"name": "Civilian3", "kind": "civilian", "side": "neutral", "label": "Civilian (Omar)", "pos": Vector3(-14, 0.1, 15),
			"routine": [Vector3(-14, 0, 15), Vector3(-15, 0, 11), Vector3(-6, 0, 16)]},
		{"name": "Civilian4", "kind": "civilian", "side": "neutral", "label": "Civilian (Leila)", "pos": Vector3(8, 0.1, 28),
			"routine": [Vector3(8, 0, 28), Vector3(-8, 0, 30), Vector3(0, 0, 36)]},
		{"name": "HvtCommander", "kind": "hvt", "side": "hostile", "label": "HVT (the Commander)", "pos": Vector3(0, 0.1, -10),
			"hvt_id": "hvt_compound_commander", "rot_y": PI, "intel": ["intel_phone"]},
		{"name": "HvtHostage", "kind": "hvt", "side": "friendly", "label": "HVT (the Engineer)", "pos": Vector3(18, 0.1, -9),
			"hvt_id": "hvt_compound_engineer", "rot_y": -PI * 0.5},
	],
	"intel": [
		{"uid": "c01_intel_laptop", "id": "intel_laptop", "pos": Vector3(3.5, 0.5, -11), "source": "main building"},
		{"uid": "c01_intel_docs", "id": "intel_documents", "pos": Vector3(-17.5, 0.5, 13), "source": "container"},
	],
	"items": [
		{"uid": "c01_zip_cuffs", "id": "zip_cuffs", "count": 4, "pos": Vector3(4, 0.5, 19.5)},
	],
	"points": [
		{"name": "Extraction", "pos": Vector3(0, 0, 31), "radius": 4.0, "label": "Extraction"},
	],
}

## Every peer: per-person state, by the person's path from the level (Person.state).
var states: Dictionary = {}
## Host: lines people said, newest last: {"speaker", "text", "time"} (tests read it).
var said: Array[Dictionary] = []

var level: Node3D
var persons: Node3D
var spawner: MultiplayerSpawner
var _tick := 0.0
var _surrender_tick := 0.0
var _said_at := {}  # speaker name -> time of their last line
var _reported := {}  # enemy name -> when they were last reported
var _report_serial := 0
var _cuffing := {}  # target instance id -> true while being cuffed
var _rng := RandomNumberGenerator.new()
var _zone_people := false  # host: the zone's civilians and delivery points are out


## The people layer of the level `from` is in (or null).
static func find(from: Node) -> PeopleLayer:
	if from == null or not from.is_inside_tree():
		return null
	return from.get_tree().get_first_node_in_group(GROUP) as PeopleLayer


func _init() -> void:
	name = "People"


func _ready() -> void:
	add_to_group(GROUP)
	level = get_parent() as Node3D
	persons = Node3D.new()
	persons.name = "Persons"
	add_child(persons)
	spawner = MultiplayerSpawner.new()
	spawner.name = "PersonSpawner"
	spawner.spawn_path = NodePath("../Persons")
	spawner.spawn_function = _make
	add_child(spawner)
	_rng.seed = 4511
	Net.hosted.connect(_on_hosted)
	Contracts.contract_live.connect(_on_contract_live)
	Net.peer_joined.connect(_on_peer_joined)


# --- Who's who (every peer) ----------------------------------------------------------------

## The key `states` uses for `s`: its path from the level.
func key_of(s: Node) -> String:
	return str(level.get_path_to(s)) if level and s and s.is_inside_tree() else ""


func state_of(s: Node) -> Dictionary:
	return states.get(key_of(s), {})


## Every person body this layer spawned (civilians and HVTs), alive or not.
func people() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in persons.get_children():
		if n is Soldier and not n.is_queued_for_deletion():
			out.append(n)
	return out


## The HVT with `hvt_id` (or null).
func hvt(hvt_id: String) -> Soldier:
	for s in people():
		if String(state_of(s).get("hvt_id", "")) == hvt_id:
			return s
	return null


# --- Host: spawning ------------------------------------------------------------------------

func _on_hosted() -> void:
	if not populate:
		return
	var world := level.get_node_or_null(^"VoxelWorld") as VoxelWorld
	if world and not world.is_built():
		await world.structures_built
	server_populate(COMPOUND)


## Host only. Spawns a level's people, intel, items and extraction points from `content` (as
## COMPOUND). Skips civilians and HVTs whose bodies the zone save holds, HVTs already
## delivered this deployment, and placed intel and items already picked up.
func server_populate(content: Dictionary) -> void:
	var fallen := {}
	for record: Dictionary in GameState.bodies:
		fallen[String(record.get("label", ""))] = true
	for data: Dictionary in content.get("people", []):
		if fallen.has(String(data.get("label", data.name))) or People.is_delivered(String(data.get("hvt_id", "-"))):
			continue
		server_spawn_person(data)
	for data: Dictionary in content.get("intel", []):
		server_place_intel(StringName(data.id), data.pos, String(data.get("source", "")), String(data.uid))
	var lvl := level as CompoundLevel
	for data: Dictionary in content.get("items", []):
		if lvl and not GameState.is_looted(data.uid):
			lvl.spawn_item(StringName(data.id), int(data.get("count", 1)), data.pos, data.uid)
	for data: Dictionary in content.get("points", []):
		server_add_point(data.pos, float(data.get("radius", DeliveryPoint.DEFAULT_RADIUS)), String(data.get("label", "Extraction")), String(data.get("name", "")))


# --- Host: a contract's people (wave 4B) ---------------------------------------------------

func _on_contract_live(_cid: String, objectives: Array) -> void:
	if multiplayer.is_server() and contract_people and is_inside_tree():
		server_contract_content(objectives)


## Host only. What a contract's objectives need in the level (Objectives.from_contract's
## params): the HVT or hostage of each DELIVER_HVT (with the intel they carry), each intel
## piece an EXTRACT_ITEM placed; and the first time in a world-scale zone, civilians going
## about their day in its modules and a delivery point at each landing zone (HVTs brought
## there are delivered, intel carried there is banked).
func server_contract_content(objectives: Array) -> void:
	var lvl := level as CompoundLevel
	for o: Dictionary in objectives:
		var p: Dictionary = o.get("params", {})
		var at: Array = p.get("pos", [])
		if at.size() != 3:
			continue
		var pos := Vector3(float(at[0]), float(at[1]), float(at[2]))
		if o.kind == Objectives.DELIVER_HVT and p.has("person") and p.has("hvt"):
			var hvt_id := String(p.hvt)
			if hvt(hvt_id) != null or People.is_delivered(hvt_id):
				continue
			var person: Dictionary = p.person
			var s := server_spawn_person({"name": ("Person_" + hvt_id).validate_node_name(), "kind": "hvt",
				"side": String(person.get("side", Person.HOSTILE)), "label": String(person.get("label", "HVT")), "pos": pos, "hvt_id": hvt_id})
			for carried: Dictionary in person.get("intel", []):
				s.inventory.take(StringName(carried.id), 1, {"intel_id": String(carried.intel_id), "source": "HVT %s" % s.display_name()})
		elif o.kind == Objectives.EXTRACT_ITEM and p.has("place") and lvl:
			for intel_id: String in p.get("intel_ids", []):
				if not GameState.is_looted(intel_id):
					lvl.spawn_item(StringName(p.place), 1, pos, intel_id, {"intel_id": intel_id, "source": String(o.get("text", ""))})
	if not _zone_people and level.has_method(&"modules"):
		_zone_people = true
		_spawn_civilians()
		var n := 0
		for lz: Vector3 in level.call(&"extraction_points"):
			n += 1
			server_add_point(lz, Extraction.RADIUS_M, "LZ %d" % n, "LZ%d" % n)


## Host only. Civilians in every module of a world-scale zone that has them (contracts.json
## "civilians"), each with a real name of their own in the zone (the region's people:
## Names.mission_person), the same every time, walking their routine. One the zone save holds
## the body of stays dead.
func _spawn_civilians() -> void:
	var nation := Names.region_nation(String(MissionRegistry.zone(GameState.zone_id).get("region", "")))
	var used := {}
	var fallen := {}
	for record: Dictionary in GameState.bodies:
		fallen[String(record.get("label", ""))] = true
	for m: Node in level.call(&"modules"):
		var module := m as ZoneModule
		var list: Array = MissionRegistry.module(module.type).get("civilians", [])
		for i in list.size():
			var data: Dictionary = list[i]
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(["civilian", module.module_id, i])
			var who := Names.mission_person(rng, "civilian", nation, Names.MALE, used)
			used[who] = true
			var label := "Civilian (%s)" % who
			if fallen.has(label):
				continue
			var routine: Array = []
			for q: Array in data.get("routine", []):
				routine.append(module.to_global(Vector3(float(q[0]), float(q[1]), float(q[2]))))
			var at: Array = data.get("pos", [0, 0.1, 0])
			server_spawn_person({"name": ("Civ_%s_%d" % [module.module_id, i]).validate_node_name(), "kind": "civilian", "side": "neutral",
				"label": label, "pos": module.to_global(Vector3(float(at[0]), float(at[1]), float(at[2]))), "routine": routine})


## Host only. HVTs getting out at an extraction point centred on `centre` (x, z) within
## `radius`, or carried by one of `extracted`, not delivered yet: [{"hvt", "alive"}] for the
## debrief (an extraction point the squad picked, which isn't a delivery point).
func hvts_out(centre: Vector2, radius: float, extracted: Array) -> Array:
	var out: Array = []
	for s in people():
		var st := state_of(s)
		if Person.kind_of(s) != Person.HVT or bool(st.get("delivered", false)):
			continue
		var inside := Vector2(s.global_position.x, s.global_position.z).distance_to(centre) <= radius
		if inside or (is_instance_valid(s.carried_by) and s.carried_by in extracted):
			out.append({"hvt": String(st.get("hvt_id", s.name)), "alive": not s.vitals.is_dead()})
	return out


## Host only. A civilian or HVT. `data`: "name" (node name), "kind" ("civilian" or "hvt"),
## "side" ("neutral", "friendly" or "hostile"), "pos", optional "rot_y", "label" (the name
## players see), "routine" (points it walks between), "hvt_id", "loadout" (item ids) and
## "intel" (intel item ids it carries, each given its own intel_id). Returns the body.
func server_spawn_person(data: Dictionary) -> Soldier:
	var d := data.duplicate(true)
	d["type"] = "person"
	var s := spawner.spawn(d) as Soldier
	var kind := StringName(d.get("kind", Person.CIVILIAN))
	var st := {"kind": String(kind), "side": String(d.get("side", Person.NEUTRAL)), "uid": "%s_%s" % [GameState.zone_id, d.name],
		"cuffed": false, "surrendered": false, "led_by": "", "order": "", "delivered": false}
	if kind == Person.HVT:
		st["hvt_id"] = String(d.get("hvt_id", d.name))
	server_set_state(s, st)
	for id: String in d.get("intel", []):
		server_give_intel(s, StringName(id), "HVT %s" % s.display_name())
	return s


## Host only. An extraction point for people and intel (DeliveryPoint), seen on every peer.
func server_add_point(pos: Vector3, radius := DeliveryPoint.DEFAULT_RADIUS, label := "Extraction", node_name := "") -> DeliveryPoint:
	return spawner.spawn({"type": "point", "name": node_name if node_name != "" else "Point%d" % persons.get_child_count(),
		"pos": pos, "radius": radius, "label": label}) as DeliveryPoint


func _make(data: Dictionary) -> Node:
	if data.get("type", "") == "point":
		var point := DeliveryPoint.new()
		point.name = data.name
		point.radius = float(data.radius)
		point.label = String(data.label)
		point.position = data.pos
		return point
	var s: Soldier = PLAYER_SCENE.instantiate()
	var kind := StringName(data.get("kind", Person.CIVILIAN))
	var side := StringName(data.get("side", Person.NEUTRAL))
	s.name = data.name
	s.faction = Person.FACTION
	s.variant = PersonLook.variant_for(kind, side)
	s.position = data.pos
	s.rotation.y = float(data.get("rot_y", 0.0))
	s.body_label = String(data.get("label", ""))
	PersonLook.dress(s, kind, side)
	if multiplayer.is_server():
		var inventory: Inventory = s.get_node(^"Inventory")
		for id: String in data.get("loadout", []):
			inventory.take(StringName(id))
		var brain: CivilianAI = HvtAI.new() if kind == Person.HVT else CivilianAI.new()
		brain.name = BRAIN
		brain.kind = kind
		brain.side = side
		brain.routine = data.get("routine", [])
		s.add_child(brain)
		s.get_node(^"Vitals").died.connect(_on_person_died.bind(s))
	return s


## Host only. Gives `holder` (anyone's inventory: an officer, an HVT) one intel item with its
## own intel_id and `source`. Returns whether it fit.
func server_give_intel(holder: Soldier, item_id: StringName, source: String) -> bool:
	return holder.inventory.take(item_id, 1, intel_state(item_id, source, holder.name)) == 1


## Host only. Places an intel item in the world (an outpost's laptop, a checkpoint's papers).
## `uid` is its stable zone-save id: once picked up it isn't placed again.
func server_place_intel(item_id: StringName, pos: Vector3, source: String, uid: String) -> void:
	var lvl := level as CompoundLevel
	if lvl == null or GameState.is_looted(uid):
		return
	lvl.spawn_item(item_id, 1, pos, uid, intel_state(item_id, source, uid))


## The item state an intel item starts with: {"intel_id", "source"}.
static func intel_state(item_id: StringName, source: String, salt: Variant) -> Dictionary:
	return {"intel_id": "%s_%s_%s" % [GameState.zone_id, String(item_id), str(salt)], "source": source}


## Is `id` an intel item?
static func is_intel(id: StringName) -> bool:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	return item != null and item.type == "intel"


# --- Host: state ---------------------------------------------------------------------------

## Host only. Merges `changes` into `s`'s state and sends it to every peer.
func server_set_state(s: Soldier, changes: Dictionary) -> void:
	var key := key_of(s)
	if key == "":
		return
	var st: Dictionary = states.get(key, {}).duplicate(true)
	st.merge(changes, true)
	states[key] = st
	s.carriable_while_up = bool(st.get("cuffed", false))
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_client_state.rpc(key, st)


@rpc("authority", "call_remote", "reliable")
func _client_state(key: String, st: Dictionary) -> void:
	states[key] = st


@rpc("authority", "call_remote", "reliable")
func _client_states(all: Dictionary) -> void:
	states = all


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_client_states.rpc_id(id, states)


# --- Host: casualties ----------------------------------------------------------------------

## A person died: an HVT or hostage not yet brought in is lost (their objective fails); a
## civilian is a casualty for us if our side hurt them last (Harm).
func _on_person_died(s: Soldier) -> void:
	if not is_instance_valid(s):
		return
	var st := state_of(s)
	if Person.kind_of(s) == Person.HVT and not bool(st.get("delivered", false)):
		People.server_hvt_lost(String(st.get("hvt_id", s.name)), s.display_name())
	if not Person.is_civilian(s):
		return
	var harm := Harm.last(s)
	if String(harm.get("faction", "")) == "friendly":
		People.server_civilian_casualty(s, harm, true)


# --- Host: noise and voices ----------------------------------------------------------------

## Host only. A shot or blast at `pos` (by `source`, may be null) frightens people within `radius`.
static func server_noise(source: Node, pos: Vector3, radius := GUNFIRE_HEARD_M) -> void:
	var layer := find(source) if source else null
	if layer == null or not layer.multiplayer.is_server():
		return
	for s in layer.people():
		if s != source and s.vitals.is_up() and s.global_position.distance_to(pos) <= radius:
			var brain := s.get_node_or_null(NodePath(BRAIN)) as CivilianAI
			if brain:
				brain.hear(pos)


## Host only. `speaker` (a person) says `text`: a subtitle for every player within SAY_RADIUS_M
## (through the level's Callouts), at most one line per SAY_GAP_S.
func server_say(speaker: Soldier, text: String) -> bool:
	var now := Soldier._now()
	if now - float(_said_at.get(speaker.name, -1000.0)) < SAY_GAP_S:
		return false
	_said_at[speaker.name] = now
	said.append({"speaker": speaker.display_name(), "text": text, "time": now})
	var lvl := level as CompoundLevel
	var callouts := lvl.callouts if lvl else null
	if callouts == null:
		return true
	var peers := multiplayer.get_peers()
	for node in lvl.players.get_children():
		var player := node as Soldier
		if player == null or player.is_queued_for_deletion() or player.global_position.distance_to(speaker.global_position) > SAY_RADIUS_M:
			continue
		var peer := player.owner_peer()
		if peer == multiplayer.get_unique_id() or peer in peers:
			callouts._show.rpc_id(peer, speaker.get_path(), speaker.display_name(), "people", text)
	return true


## Host only. A hostile HVT gives the squad away: every hostile soldier within `radius` of
## `speaker` learns that the threat is at `threat` (their SquadAI goes into contact).
func server_expose(speaker: Soldier, threat: Vector3, radius: float) -> int:
	var told := 0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s == speaker or s.faction != Person.HOSTILE or not s.vitals.is_up() or Person.is_captive(s):
			continue
		if s.global_position.distance_to(speaker.global_position) <= radius and SquadAI.of(s):
			s.threat_pos = threat
			s.threat_time = Soldier._now()
			told += 1
	return told


# --- Host: the tick ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_check_extraction()
	if surrender_enabled:
		_surrender_tick -= delta
		if _surrender_tick <= 0.0:
			_surrender_tick = SURRENDER_CHECK_S
			_check_surrenders()


## Host only. Banks the intel of every squad member standing in an extraction point and
## delivers every HVT brought there. Called every TICK_S; the map's extraction can call it too.
func server_check_extraction() -> void:
	var points := get_tree().get_nodes_in_group(DeliveryPoint.GROUP)
	if points.is_empty():
		return
	for s in _squad():
		if s.vitals.is_up() and DeliveryPoint.at(get_tree(), s.global_position):
			server_bank_intel(s)
	for s in people():
		if Person.kind_of(s) != Person.HVT or s.vitals.is_dead() or bool(state_of(s).get("delivered", false)):
			continue
		var point := DeliveryPoint.at(get_tree(), s.global_position)
		if point:
			var by := _escort(s)
			if by:
				server_deliver(s, by, point)


## Who brings HVT `s` in: whoever carries or leads him, or anyone from the squad within
## ESCORT_M of a cuffed, surrendered or friendly HVT. Null for nobody.
func _escort(s: Soldier) -> Soldier:
	if is_instance_valid(s.carried_by) and s.carried_by.faction == &"friendly":
		return s.carried_by
	var st := state_of(s)
	var leader := level.get_node_or_null(NodePath(String(st.get("led_by", "")))) as Soldier if String(st.get("led_by", "")) != "" else null
	if leader and leader.faction == &"friendly":
		return leader
	if StringName(st.get("side", "")) == Person.HOSTILE and not Person.is_captive(s) and s.vitals.is_up():
		return null  # a hostile HVT who hasn't given up isn't delivered by walking in
	for m in _squad():
		if m.vitals.is_up() and m.global_position.distance_to(s.global_position) <= ESCORT_M:
			return m
	return null


## Host only. Delivers HVT `s` (brought in `by`, at extraction `point`): the objective hook
## (People.hvt_delivered, the ledger). He stops and waits there.
func server_deliver(s: Soldier, by: Soldier, point: Node3D) -> void:
	var st := state_of(s)
	server_set_state(s, {"delivered": true, "led_by": "", "order": "stop"})
	var p := point.global_position
	People.server_hvt_delivered({"hvt_id": String(st.get("hvt_id", s.name)), "name": s.display_name(), "side": String(st.get("side", "")),
		"alive": not s.vitals.is_dead(), "cuffed": bool(st.get("cuffed", false)), "by": by.display_name() if by else "",
		"point": [p.x, p.z]})
	if by and not by.is_ai():
		by._client_message.rpc_id(by.owner_peer(), "%s delivered" % s.display_name())


## Host only. Takes every intel item `s` carries out of its gear and banks it (People),
## "carried" out. Returns the entries banked.
func server_bank_intel(s: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv := s.inventory
	for container in inv.search_containers():  # MOLLE pouches too
		var list: Array = inv.containers[container]
		for i in range(list.size() - 1, -1, -1):
			if not is_intel(list[i].id):
				continue
			var entry := inv.remove_entry(container, i, int(list[i].count))
			for n in int(entry.count):
				var item := ItemDB.get_item(entry.id)
				var st: Dictionary = entry.get("state", {})
				var intel_id := String(st.get("intel_id", ""))
				if intel_id == "" or People.has_intel(intel_id):
					intel_id = "%s_%s_%s_%d" % [GameState.zone_id, String(entry.id), String(s.name), Time.get_ticks_usec() + n]
				var banked := {"intel_id": intel_id, "how": "carried", "item": String(entry.id), "name": item.name,
					"value": int(item.stats.get("intel_value", 0)), "source": String(st.get("source", "")), "by": s.display_name()}
				if People.server_bank_intel(banked):
					out.append(banked)
	if not out.is_empty() and not s.is_ai():
		s._client_message.rpc_id(s.owner_peer(), "Intel banked: %s" % ", ".join(PackedStringArray(out.map(func(e: Dictionary) -> String: return e.name))))
	return out


## The players and their AI squad (living bodies).
func _squad() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.faction == &"friendly" and not s.is_queued_for_deletion() and not s.vitals.is_dead():
			out.append(s)
	return out


# --- Host: surrender -----------------------------------------------------------------------

func _check_surrenders() -> void:
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and surrender_reason(s) != "" and _rng.randf() < SURRENDER_CHANCE:
			server_surrender(s, surrender_reason(s))


## Why hostile soldier `s` would give up now ("" if he wouldn't): badly hurt, alone and seen.
func surrender_reason(s: Soldier) -> String:
	if s.faction != Person.HOSTILE or not s.vitals.is_up() or s.is_queued_for_deletion() or SquadAI.of(s) == null or Person.is_captive(s):
		return ""
	var hurt := s.vitals.pain() >= SURRENDER_PAIN or s.vitals.blood_fraction() <= SURRENDER_BLOOD or s.vitals.injury() >= SURRENDER_INJURY
	if not hurt:
		return ""
	var seen := false
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var o := n as Soldier
		if o == null or o == s or o.is_queued_for_deletion() or not o.vitals.is_up():
			continue
		var d := o.global_position.distance_to(s.global_position)
		if o.faction == Person.HOSTILE and not Person.is_captive(o) and d <= SURRENDER_ALONE_M:
			return ""  # not alone
		if o.faction == &"friendly" and d <= SURRENDER_SEEN_M and Squad.sees(s, o):
			seen = true
	return "badly hurt and alone" if seen else ""


## Host only. `s` gives up: a hostile soldier drops his weapons and his SquadAI makes way for
## a captive's brain; an HVT just stops running. Either way he's a captive (no longer a
## target) who can be cuffed from any side, led and searched.
func server_surrender(s: Soldier, why := "") -> void:
	if s.vitals.is_dead() or Person.is_captive(s):
		return
	var squad_ai := SquadAI.of(s)
	if squad_ai:
		squad_ai.name = "SquadAIGone"
		squad_ai.queue_free()
		s.move_input = Vector2.ZERO
		s.want_aim = false
		s.release_carried()
		for slot: StringName in Inventory.WEAPON_SLOTS:
			var removed := s.inventory.unequip(slot)
			if not removed.is_empty():
				s._server_spawn_in_front(removed.id, 1, removed.state)
		var brain := CivilianAI.new()
		brain.name = BRAIN
		brain.kind = Person.SOLDIER
		brain.side = Person.HOSTILE
		s.add_child(brain)
	var st := state_of(s)
	var changes := {"surrendered": true, "order": "", "led_by": ""}
	if st.is_empty():
		changes.merge({"kind": String(Person.SOLDIER), "side": String(Person.HOSTILE), "uid": "%s_%s" % [GameState.zone_id, s.name],
			"cuffed": false, "delivered": false})
	server_set_state(s, changes)
	server_say(s, SURRENDER_LINES[_rng.randi() % SURRENDER_LINES.size()])
	print("[people] %s surrendered (%s)" % [s.display_name(), why])


# --- Requests (interaction menu, command menu) ---------------------------------------------

## A player's people action on `path` from the interaction menu: "cuff", "lead", "stop",
## "cover" or "search". Checked on the host.
@rpc("any_peer", "call_local", "reliable")
func request(action: String, path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	var target := get_node_or_null(path) as Soldier
	if actor == null or target == null or target == actor or target.is_queued_for_deletion() or not actor.vitals.is_up():
		return
	if actor.global_position.distance_to(target.global_position) > REACH:
		actor._client_message.rpc_id(actor.owner_peer(), "Too far away")
		return
	match action:
		"cuff":
			server_cuff(actor, target)
		"lead":
			_tell(actor, server_lead(actor, target))
		"stop":
			_tell(actor, server_order(actor, target, "stop"))
		"cover":
			_tell(actor, server_order(actor, target, "cover"))
		"search":
			_tell(actor, server_search(actor, target))


## A player reports the enemies around `point` by radio (command menu). Checked on the host.
@rpc("any_peer", "call_local", "reliable")
func request_report(point: Vector3) -> void:
	if not multiplayer.is_server() or not point.is_finite():
		return
	var actor := _sender()
	if actor == null or not actor.vitals.is_up():
		return
	var result := server_report(actor, point)
	_tell(actor, result.get("why", "") if result.has("why") else "Reported %d enemies by radio" % int(result.count))


func _sender() -> Soldier:
	var lvl := level as CompoundLevel
	return lvl.players.get_node_or_null(str(multiplayer.get_remote_sender_id())) as Soldier if lvl else null


func _tell(actor: Soldier, text: String) -> void:
	if text != "":
		actor._client_message.rpc_id(actor.owner_peer(), text)


## Host only. Zip-cuffs `target` (Person.cuff_problem says when that's allowed): takes the
## item's cuff_s, during which `actor` is busy; moving, going down, the target pulling away or
## going out of reach interrupts it. Uses up one zip cuff. Returns whether it worked (await it).
func server_cuff(actor: Soldier, target: Soldier) -> bool:
	var why := Person.cuff_problem(actor, target)
	if why == "" and _cuffing.has(target.get_instance_id()):
		why = "Someone is already cuffing them"
	if why == "" and actor._is_busy():
		why = "You're busy"
	if why != "":
		_tell(actor, why)
		return false
	var item := ItemDB.get_item(Person.ZIP_CUFFS)
	var seconds := float(item.stats.get("cuff_s", CUFF_S))
	var id := target.get_instance_id()
	_cuffing[id] = true
	actor._server_busy_until = Soldier._now() + seconds
	actor._client_busy.rpc_id(actor.owner_peer(), seconds, "Zip-cuffing %s..." % target.display_name())
	var my_start := actor.global_position
	var their_start := target.global_position
	var end := Soldier._now() + seconds
	var interrupted := ""
	while Soldier._now() < end:
		await get_tree().create_timer(clampf(end - Soldier._now(), 0.01, CUFF_CHECK_S)).timeout
		if not is_instance_valid(actor) or not is_instance_valid(target):
			_cuffing.erase(id)
			return false
		if not actor.vitals.is_up():
			interrupted = "you went down"
		elif target.vitals.is_dead():
			interrupted = "they're dead"
		elif actor.global_position.distance_to(my_start) > CUFF_MOVE_M:
			interrupted = "you moved"
		elif target.global_position.distance_to(their_start) > CUFF_MOVE_M:
			interrupted = "they pulled away"
		elif actor.global_position.distance_to(target.global_position) > REACH:
			interrupted = "out of reach"
		if interrupted != "":
			break
	_cuffing.erase(id)
	if interrupted == "" and not actor.inventory.remove_one(Person.ZIP_CUFFS):
		interrupted = "you have no zip cuffs left"
	if interrupted != "":
		actor._server_busy_until = Soldier._now()
		actor._client_busy.rpc_id(actor.owner_peer(), 0.0, "Cuffing interrupted: %s" % interrupted)
		return false
	server_set_state(target, {"cuffed": true, "led_by": "", "order": ""})
	_tell(actor, "Cuffed %s" % target.display_name())
	print("[people] %s cuffed %s" % [actor.display_name(), target.display_name()])
	return true


## Host only. `target` follows `actor` (Follow me). Returns the message for the player.
func server_lead(actor: Soldier, target: Soldier) -> String:
	if not Person.leadable(target):
		return "They won't follow you"
	server_set_state(target, {"led_by": key_of(actor), "order": "follow"})
	return "%s follows you" % target.display_name()


## Host only. Stop ("stop": wait here) or Get in cover ("cover") for `target`.
func server_order(_actor: Soldier, target: Soldier, order: String) -> String:
	if not Person.leadable(target):
		return "They won't listen"
	server_set_state(target, {"led_by": "", "order": order})
	return "%s: %s" % [target.display_name(), "waiting here" if order == "stop" else "getting into cover"]


## Host only. Searches a captive or an unconscious body for intel: every intel item on them
## goes into `actor`'s gear if it fits. Returns the message for the player.
func server_search(actor: Soldier, target: Soldier) -> String:
	if not Person.searchable(actor, target):
		return "You can't search them"
	var found := PackedStringArray()
	var left := 0
	var inv := target.inventory
	for container in inv.search_containers():  # MOLLE pouches too
		var list: Array = inv.containers[container]
		for i in range(list.size() - 1, -1, -1):
			if not is_intel(list[i].id):
				continue
			var entry := inv.remove_entry(container, i, int(list[i].count))
			var moved := actor.inventory.take(entry.id, int(entry.count), entry.get("state", {}))
			if moved < int(entry.count):
				var rest := entry.duplicate(true)
				rest.count = int(entry.count) - moved
				inv.insert_entry(container, rest)
				left += 1
			if moved > 0:
				found.append(ItemDB.get_item(entry.id).name)
	if found.is_empty():
		return "No room for what they carry" if left > 0 else "Searched %s: nothing" % target.display_name()
	return "Found: %s%s" % [", ".join(found), " (no room for the rest)" if left > 0 else ""]


## Host only. Radio report: the hostiles around `point` (REPORT_RADIUS_M) become one intel
## entry banked at once (People), if `reporter` sees at least one of them. Returns the entry,
## or {"why": reason} if nothing was reported.
func server_report(reporter: Soldier, point: Vector3) -> Dictionary:
	var now := Soldier._now()
	var group: Array[Soldier] = []
	var seen := false
	var already := 0
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s == null or s.faction != Person.HOSTILE or s.is_queued_for_deletion() or not s.vitals.is_up() or Person.is_captive(s):
			continue
		if CivilianAI._flat_between(s.global_position, point) > REPORT_RADIUS_M:
			continue
		if now - float(_reported.get(s.name, -1000.0)) < REPORT_AGAIN_S:
			already += 1
			continue
		group.append(s)
		if s.global_position.distance_to(reporter.global_position) <= REPORT_RANGE_M and Squad.sees(reporter, s):
			seen = true
	if group.is_empty():
		return {"why": "Already reported" if already > 0 else "No enemies there"}
	if not seen:
		return {"why": "You can't see them from here"}
	var centre := Vector3.ZERO
	var names := PackedStringArray()
	for s in group:
		centre += s.global_position
		names.append(String(s.name))
		_reported[s.name] = now
	centre /= group.size()
	_report_serial += 1
	var entry := {"intel_id": "%s_report_%d_%d" % [GameState.zone_id, _report_serial, int(Time.get_unix_time_from_system())],
		"how": "reported", "item": "", "name": "Enemy position (%d)" % group.size(), "value": REPORT_VALUE * group.size(),
		"source": "radio", "by": reporter.display_name(), "pos": [centre.x, centre.z], "count": group.size(), "enemies": Array(names)}
	People.server_bank_intel(entry)
	return entry


# --- Hooks for later waves -----------------------------------------------------------------

## Host only. Seats `person` in `vehicle` (wave 5: vehicles): he rides at
## vehicle.seat_transform(seat) if the vehicle has one, and is delivered with it when it
## reaches an extraction point. Returns whether he was seated.
func server_seat_in_vehicle(person: Soldier, vehicle: Node3D, seat := "") -> bool:
	if person == null or vehicle == null or person.vitals.is_dead():
		return false
	if is_instance_valid(person.carried_by):
		person.carried_by.release_carried()
	server_set_state(person, {"seated_in": key_of(vehicle), "seat": seat, "led_by": "", "order": ""})
	return true


## Host only. Gets `person` out of whatever he's seated in, where he is.
func server_unseat(person: Soldier) -> void:
	server_set_state(person, {"seated_in": "", "seat": ""})
