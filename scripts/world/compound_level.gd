class_name CompoundLevel
extends Node3D
## Gray-box hostile compound: flat ground, 10 cm voxel walls you can shoot through, loot,
## and armored target dummies. Owns player and item spawning for the session.

const PLAYER_SCENE := preload("res://scenes/soldier.tscn")
const SPAWN_POINTS: Array[Vector3] = [Vector3(-3, 0.1, 24), Vector3(-1, 0.1, 24), Vector3(1, 0.1, 24), Vector3(3, 0.1, 24)]
const COMPOUND_HALF := 20.0
const WALL_THICKNESS := 0.3
## Thin-walled outbuildings (see _build_structures), as [from, to (metres), material] boxes.
## A wooden lean-to against the east wall, 10 cm plank walls with a doorway to the west and
## a sheet-metal roof, and a sheet-metal shipping container by the west wall, open to the
## east. Chunk edges of the navmesh (NavBuilder) stay clear of both openings.
const SHED := [
	[Vector3(16, 0, -11), Vector3(16.1, 2.4, -9.6), "wood"],
	[Vector3(16, 0, -8.4), Vector3(16.1, 2.4, -7), "wood"],
	[Vector3(16, 2.0, -9.6), Vector3(16.1, 2.4, -8.4), "wood"],
	[Vector3(16.1, 0, -11), Vector3(19.7, 2.4, -10.9), "wood"],
	[Vector3(16.1, 0, -7.1), Vector3(19.7, 2.4, -7), "wood"],
	[Vector3(16, 2.4, -11), Vector3(19.7, 2.5, -7), "sheet_metal"],
]
const CONTAINER := [
	[Vector3(-18.5, 0, 8), Vector3(-16.1, 2.5, 8.1), "sheet_metal"],
	[Vector3(-18.5, 0, 13.9), Vector3(-16.1, 2.5, 14), "sheet_metal"],
	[Vector3(-18.5, 0, 8.1), Vector3(-18.4, 2.5, 13.9), "sheet_metal"],
	[Vector3(-18.5, 2.5, 8), Vector3(-16.1, 2.6, 14), "sheet_metal"],
]

## Starting loot. Each uid is stable so a pickup stays picked up across saves.
const LOOT := [
	{"uid": "c01_carrier_a", "id": "plate_carrier", "pos": Vector3(-2, 0.5, 21)},
	{"uid": "c01_plate_a", "id": "plate_steel_l3", "pos": Vector3(-1, 0.5, 21)},
	{"uid": "c01_plate_b", "id": "plate_ceramic_l4", "pos": Vector3(0, 0.5, 21)},
	{"uid": "c01_m4_a", "id": "m4a1", "pos": Vector3(1, 0.5, 21)},
	{"uid": "c01_m17_a", "id": "m17", "pos": Vector3(2, 0.5, 21)},
	{"uid": "c01_pack_a", "id": "assault_pack", "pos": Vector3(3, 0.5, 21)},
	{"uid": "c01_mags_a", "id": "mag_556", "count": 6, "pos": Vector3(-3, 0.5, 21)},
	{"uid": "c01_carrier_b", "id": "plate_carrier", "pos": Vector3(-2, 0.5, 19.5)},
	{"uid": "c01_plate_c", "id": "plate_steel_l3", "pos": Vector3(-1, 0.5, 19.5)},
	{"uid": "c01_mk18_a", "id": "mk18", "pos": Vector3(1, 0.5, 19.5)},
	{"uid": "c01_ruck_a", "id": "ruck_45", "pos": Vector3(3, 0.5, 19.5)},
	{"uid": "c01_helmet_a", "id": "helmet", "pos": Vector3(0, 0.5, 19.5)},
	{"uid": "c01_carrier_light", "id": "plate_carrier_light", "pos": Vector3(-5, 0.5, 21)},
	{"uid": "c01_plate_pe", "id": "plate_pe_l3", "pos": Vector3(-5, 0.5, 22)},
	{"uid": "c01_helmet_bump", "id": "helmet_bump", "pos": Vector3(-5, 0.5, 23)},
	{"uid": "c01_carrier_heavy", "id": "plate_carrier_heavy", "pos": Vector3(5, 0.5, 21)},
	{"uid": "c01_helmet_heavy", "id": "helmet_heavy", "pos": Vector3(5, 0.5, 22)},
	{"uid": "c01_side_a", "id": "plate_side", "pos": Vector3(5.5, 0.5, 23)},
	{"uid": "c01_side_b", "id": "plate_side", "pos": Vector3(4.5, 0.5, 23)},
	{"uid": "c01_ifak_a", "id": "ifak", "count": 2, "pos": Vector3(-6, 0.5, 4)},
	{"uid": "c01_frag_a", "id": "frag_grenade", "count": 3, "pos": Vector3(6, 0.5, 4)},
	{"uid": "c01_smoke_a", "id": "smoke_grenade", "count": 3, "pos": Vector3(7, 0.5, 4)},
	{"uid": "c01_flash_a", "id": "flashbang", "count": 3, "pos": Vector3(8, 0.5, 4)},
	{"uid": "c01_smoke_green", "id": "smoke_green", "count": 2, "pos": Vector3(7, 0.5, 5)},
	{"uid": "c01_smoke_yellow", "id": "smoke_yellow", "count": 2, "pos": Vector3(8, 0.5, 5)},
	{"uid": "c01_smoke_blue", "id": "smoke_blue", "count": 2, "pos": Vector3(9, 0.5, 5)},
	{"uid": "c01_smoke_purple", "id": "smoke_purple", "count": 2, "pos": Vector3(9, 0.5, 4)},
	{"uid": "c01_rounds_556_a", "id": "rounds_556", "count": 120, "pos": Vector3(-3, 0.5, 19.5)},
	{"uid": "c01_rounds_9mm_a", "id": "rounds_9mm", "count": 51, "pos": Vector3(2, 0.5, 22.5)},
	{"uid": "c01_rounds_762_a", "id": "rounds_762", "count": 60, "pos": Vector3(-4, 0.5, -10)},
	{"uid": "c01_salvage_a", "id": "electronics_salvage", "count": 8, "pos": Vector3(3, 0.5, -10)},
	{"uid": "c01_m110_a", "id": "m110", "pos": Vector3(-3, 0.5, -10)},
	{"uid": "c01_hvt_case", "id": "hvt_case", "pos": Vector3(0, 0.5, -10)},
	{"uid": "c01_crate_a", "id": "supply_crate", "pos": Vector3(12, 0.6, -12)},
]

## Turn off to host a session without AI (the older test suites do).
static var spawn_ai := true
## Players start in their role's kit (Roles) the first time they spawn. Off for now: players
## kit out from the gate loot as before and respawn in the handoff's default kit, and the
## older suites expect an empty start. AI squadmates always get their role's kit.
static var player_role_kits := false

## The player squad has 8 slots in two fire teams (Roles); AI fills the ones players don't
## (see rebalance_squad). AI squadmates are named by callsign, the first one free.
const SQUAD_SIZE := 8
const SQUAD_CALLSIGNS: Array[String] = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"]
## A joining player stays out of the squad (AI keep every slot) until their pick arrives
## (Roles.local_choice, sent on join); if it hasn't come within JOIN_ROLE_WAIT_S they take
## DEFAULT_JOIN_ROLE.
const DEFAULT_JOIN_ROLE := Roles.RIFLEMAN
const JOIN_ROLE_WAIT_S := 5.0
## Two fire teams: a pair guarding the main building, and a pair patrolling the yard.
const HOSTILES := [
	{"name": "Hostile1", "pos": Vector3(-2.5, 0.1, -10), "buddy": "Hostile2", "guard": true},
	{"name": "Hostile2", "pos": Vector3(2.5, 0.1, -6.5), "buddy": "Hostile1", "guard": true},
	{"name": "Hostile3", "pos": Vector3(-12, 0.1, -2), "buddy": "Hostile4", "guard": false},
	{"name": "Hostile4", "pos": Vector3(-10, 0.1, -3), "buddy": "Hostile3", "guard": false},
]
const HOSTILE_LOADOUT := ["plate_carrier_light", "plate_pe_l3", "helmet_bump", "assault_pack", "mk18",
	"mag_556", "mag_556", "mag_556", "mag_556", "ifak", "frag_grenade"]
const HOSTILE_PATROL: Array[Vector3] = [Vector3(-12, 0, -2), Vector3(-12, 0, -16), Vector3(12, 0, -16), Vector3(12, 0, 0), Vector3(-4, 0, 2)]

@onready var players: Node3D = $Players
@onready var ai: Node3D = $AI
@onready var items: Node3D = $Items
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var ai_spawner: MultiplayerSpawner = $AISpawner
## Dead bodies that aren't an AI's own node: dead players' bodies and bodies restored from
## the zone save (server_spawn_body). A dead AI's own node stays under AI.
@onready var bodies: Node3D = $Bodies
@onready var body_spawner: MultiplayerSpawner = $BodySpawner
@onready var voxel_world: VoxelWorld = $VoxelWorld

var _spawn_index := 0
var _throw_count := 0
var _squads := {}  # faction -> Squad
var _ai_ready := false  # host: AI spawns once the voxel walls exist
## Host: the role each player picked, by peer id.
var player_roles := {}
var _kitted := {}  # host: peer ids that got their role kit
## Host: squad slots whose AI squadmate died (permadeath): no new squadmate takes them.
var _fallen_slots := {}
## AI callouts as subtitles (same node on every peer).
var callouts: Callouts


static func current(from: Node) -> CompoundLevel:
	return from.get_tree().get_first_node_in_group(&"level") as CompoundLevel


func squad_for(faction: StringName) -> Squad:
	return _squads.get(faction)


func _ready() -> void:
	add_to_group(&"level")
	item_spawner.spawn_function = _make_item
	ai_spawner.spawn_function = _make_soldier
	body_spawner.spawn_function = _make_body
	for faction: StringName in [&"friendly", &"hostile"]:
		var squad := Squad.new()
		squad.name = "%sSquad" % String(faction).capitalize()
		squad.faction = faction
		add_child(squad)
		_squads[faction] = squad
	_squads[&"hostile"].patrol = HOSTILE_PATROL
	callouts = Callouts.new()
	callouts.name = "Callouts"
	add_child(callouts)
	_build_environment()
	_build_structures()
	Net.hosted.connect(_on_hosted)
	Net.joined.connect(_on_joined)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return SPAWN_POINTS[_spawn_index % SPAWN_POINTS.size()]


## Host only.
func spawn_item(id: StringName, count: int, pos: Vector3, uid: String, state := {}) -> void:
	item_spawner.spawn({"id": String(id), "count": count, "pos": pos, "uid": uid, "state": state})


## Host only. Spawns an item a player dropped and records it for saving.
func server_spawn_dropped(id: StringName, count: int, pos: Vector3, state := {}) -> void:
	var uid := GameState.new_uid()
	GameState.item_dropped(uid, id, count, pos, state)
	spawn_item(id, count, pos, uid, state)


## Host only. Leaves a dead body from `record` (Soldier.body_record): a Soldier with no brain,
## dead from the start, lying at "pos" with everything in "gear" on it. A dead player's body
## ("marker") carries a GearMarker (the handoff's gear marker, until there's a map), which
## follows the body and goes once nothing is left on it. Like any body it's in
## Soldier.DEAD_GROUP: lootable, carriable, saved with the zone, under the body cap. Bodies
## spawn through BodySpawner, so late joiners get them too. Returns the body.
func server_spawn_body(record: Dictionary) -> Soldier:
	var uid := String(record.get("uid", ""))
	if uid == "":
		uid = GameState.new_uid()
	var data := record.duplicate(true)
	data.erase("gear")  # the gear replicates with the inventory (ServerSync), not in the spawn
	data["uid"] = uid
	data["name"] = ("Body_" + uid).validate_node_name()
	var corpse := body_spawner.spawn(data) as Soldier
	corpse.inventory.net_state = GameState.from_json(record.get("gear", {}))
	corpse.vitals.server_kill()  # -> Soldier._on_died: it becomes a body (DEAD_GROUP, body cap)
	corpse.died_at = Soldier._now() - float(record.get("age_s", 0.0))
	return corpse


func _make_body(data: Dictionary) -> Node:
	var corpse: Soldier = PLAYER_SCENE.instantiate()
	corpse.name = data.name
	corpse.faction = StringName(data.get("faction", "friendly"))
	corpse.variant = String(data.get("variant", "woodland"))
	var p: Array = data.get("pos", [0.0, 0.1, 0.0])
	corpse.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	corpse.rotation.y = float(data.get("rot_y", 0.0))
	corpse.role = StringName(data.get("role", ""))
	corpse.body_label = String(data.get("label", ""))
	corpse.body_uid = String(data.uid)
	corpse.collision_layer = 0
	if data.get("marker", false):
		corpse.has_gear_marker = true
		var marker := GearMarker.new()
		marker.text = "%s's gear" % corpse.body_label
		marker.position = Vector3.UP * GearMarker.HEIGHT
		corpse.add_child(marker)
	return corpse


## Host only. Puts back the bodies the zone save holds (GameState.bodies), oldest first.
func _restore_bodies() -> void:
	var records := GameState.bodies.duplicate()
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("age_s", 0.0)) > float(b.get("age_s", 0.0)))
	for record: Dictionary in records:
		server_spawn_body(record)


@rpc("authority", "call_local", "unreliable")
func show_impact(pos: Vector3, normal: Vector3, kind: String) -> void:
	var mark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.025
	sphere.height = 0.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = {"plate": Color.CYAN, "body": Color.RED}.get(kind, Color.YELLOW)
	sphere.material = material
	mark.mesh = sphere
	add_child(mark)
	mark.global_position = pos + normal * 0.01
	get_tree().create_timer(4.0).timeout.connect(mark.queue_free)


## Host only. Throws a grenade on every peer; the host's copy detonates (see Grenade).
func server_throw(id: StringName, origin: Vector3, velocity: Vector3) -> void:
	_throw_count += 1
	show_throw.rpc(_throw_count, String(id), origin, velocity)


@rpc("authority", "call_local", "reliable")
func show_throw(serial: int, id: String, origin: Vector3, velocity: Vector3) -> void:
	var grenade := Grenade.new()
	grenade.name = "Grenade%d" % serial
	grenade.setup(StringName(id))
	add_child(grenade)
	grenade.global_position = origin
	grenade.linear_velocity = velocity
	grenade.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


@rpc("authority", "call_local", "reliable")
func show_explosion(pos: Vector3) -> void:
	_burst(pos, Color(1.0, 0.6, 0.25), 3.2, 0.35)


@rpc("authority", "call_local", "reliable")
func show_flash(pos: Vector3) -> void:
	_burst(pos, Color.WHITE, 1.0, 0.15)


## A smoke cloud on every peer, in its colour (a name in SmokeCloud.COLOURS).
@rpc("authority", "call_local", "reliable")
func spawn_smoke(pos: Vector3, colour: String) -> void:
	var cloud := SmokeCloud.new()
	cloud.colour = colour
	add_child(cloud)
	cloud.global_position = pos


func _burst(pos: Vector3, colour: Color, size: float, life: float) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.material = material
	var ball := MeshInstance3D.new()
	ball.mesh = sphere
	var light := OmniLight3D.new()
	light.light_color = colour
	light.light_energy = 8.0
	light.omni_range = 14.0
	ball.add_child(light)
	add_child(ball)
	ball.global_position = pos + Vector3.UP * 0.3
	var tween := ball.create_tween().set_parallel()
	tween.tween_property(ball, "scale", Vector3.ONE * size, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.tween_property(light, "light_energy", 0.0, life)
	tween.chain().tween_callback(ball.queue_free)


func _on_hosted() -> void:
	GameState.load_zone()
	voxel_world.load_edits(GameState.voxel_edits)
	for loot: Dictionary in LOOT:
		if not GameState.is_looted(loot.uid):
			spawn_item(StringName(loot.id), loot.get("count", 1), loot.pos, loot.uid)
	for uid: String in GameState.dropped:
		var d: Dictionary = GameState.dropped[uid]
		spawn_item(StringName(d.id), int(d.count), Vector3(d.pos[0], d.pos[1], d.pos[2]), uid, d.get("state", {}))
	player_roles[1] = Roles.local_choice  # the host's own pick from the main menu
	_add_player(1)
	NavBuilder.build(self)
	# Bodies lie where they were, on the walls' collision.
	if voxel_world.is_built():
		_restore_bodies()
	else:
		voxel_world.structures_built.connect(_restore_bodies, CONNECT_ONE_SHOT)
	if spawn_ai:
		# AI needs the walls' collision before it can tell what it can see.
		if voxel_world.is_built():
			_spawn_ai()
		else:
			voxel_world.structures_built.connect(_spawn_ai, CONNECT_ONE_SHOT)


## Host only. Spawns the hostile fire teams and fills the player squad with AI.
func _spawn_ai() -> void:
	_ai_ready = true
	var hostiles := hostiles_to_spawn()
	var spawned := {}
	for h: Dictionary in hostiles:
		spawned[h.name] = spawn_soldier({"name": h.name, "faction": "hostile", "variant": "urban", "pos": h.pos,
			"loadout": HOSTILE_LOADOUT, "combat": 0.45, "discipline": 0.5, "guard": h.guard, "mode": "aware"})
	for h: Dictionary in hostiles:
		spawned[h.name].buddy = spawned.get(h.buddy)  # null if the buddy's body is in the save
	rebalance_squad()


## The HOSTILES to spawn: all but those whose bodies the zone save holds (GameState.bodies).
## A hostile killed before the save stays dead; its body and gear come back instead.
func hostiles_to_spawn() -> Array:
	var fallen := {}
	for record: Dictionary in GameState.bodies:
		if String(record.get("faction", "")) == "hostile":
			fallen[String(record.get("label", ""))] = true
	return HOSTILES.filter(func(h: Dictionary) -> bool: return not fallen.has(h.name))


## Host only. The player squad is SQUAD_SIZE slots in two fire teams of four, each with a
## medic (Roles). Players take the slot of the role they picked (Roles.assign); AI fills
## every other slot with that slot's role and kit (one player gets 7 squadmates, four
## players get 4). Called whenever a player joins, leaves or picks a role. Slots pair into
## battle buddies, players included.
func rebalance_squad() -> void:
	var humans: Array = players.get_children().filter(func(p: Node) -> bool: return p is Soldier and not p.is_queued_for_deletion())
	humans.sort_custom(func(a: Node, b: Node) -> bool: return a.name.to_int() < b.name.to_int())
	# A player whose pick hasn't arrived yet waits outside the squad (the AI keep their slots).
	for h: Soldier in humans.filter(func(p: Soldier) -> bool: return not player_roles.has(p.name.to_int())):
		h.squad_slot = -1
		h.fire_team = -1
		h.role = &""
		h.buddy = null
	humans = humans.filter(func(p: Soldier) -> bool: return player_roles.has(p.name.to_int()))
	var choices: Array = []
	var current: Array = []
	var current_roles: Array = []
	for h: Soldier in humans:
		choices.append(player_roles[h.name.to_int()])
		current.append(h.squad_slot)
		current_roles.append(h.role)
	var plan := Roles.assign(choices, current, current_roles)
	var slot_roles: Array = plan.roles
	var layout := Roles.layout()
	var everyone := {}  # slot -> Soldier
	for i in humans.size():
		var h: Soldier = humans[i]
		var slot: int = plan.slots[i]
		h.squad_slot = slot
		h.role = slot_roles[slot] if slot >= 0 else StringName(choices[i])
		h.fire_team = int(layout[slot].team) if slot >= 0 else -1
		if slot >= 0:
			everyone[slot] = h
		if player_role_kits and player_roles.has(h.name.to_int()) and not _kitted.has(h.name.to_int()):
			_kitted[h.name.to_int()] = true
			Roles.apply_kit(h.inventory, h.role)
	if _ai_ready:
		# Squadmates keep their slot unless a player took it; empty slots get a new one.
		for s: Soldier in _squad_ai():
			if s.squad_slot < 0 or everyone.has(s.squad_slot) or s.role != slot_roles[s.squad_slot]:
				_remove_squadmate(s)
			else:
				everyone[s.squad_slot] = s
		for slot in layout.size():
			if not everyone.has(slot) and not _fallen_slots.has(slot):
				var mate := _spawn_squadmate(slot, slot_roles[slot], int(layout[slot].team))
				if mate:
					everyone[slot] = mate
	for slot: int in everyone:
		(everyone[slot] as Soldier).buddy = everyone.get(Roles.buddy_slot(slot))


## Living friendly AI squadmates in the session. A dead squadmate's body is no member: it
## keeps no slot and is never removed by rebalance_squad (it lies where it fell).
func _squad_ai() -> Array:
	return ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and s.faction == &"friendly" \
		and not s.is_queued_for_deletion() and not s.vitals.is_dead())


## A squadmate whose slot a player took (or whose role changed) leaves the session. A dead one
## never does: its body and gear stay where it fell.
func _remove_squadmate(s: Soldier) -> void:
	if s.vitals.is_dead():
		return
	s.release_carried()
	if is_instance_valid(s.carried_by):
		s.carried_by.release_carried()
	s.queue_free()


## Host only: a squadmate died (permadeath). Its body stays where it fell; it leaves the squad
## (no slot, no orders) and nobody new takes its slot.
func _on_died_for_good(s: Soldier) -> void:
	if s.faction == &"friendly" and s.squad_slot >= 0:
		_fallen_slots[s.squad_slot] = true
		s.squad_slot = -1


## Host only. A new AI squadmate in `slot`, named with the first callsign no other node holds
## (dead squadmates' bodies keep theirs, so past the eighth it's "Alpha 2" and so on), in its
## role's kit, placed in formation behind the lead.
func _spawn_squadmate(slot: int, role: StringName, team: int) -> Soldier:
	var callsign := ""
	var lap := 1
	while callsign == "":
		for c in SQUAD_CALLSIGNS:
			var candidate := c if lap == 1 else "%s %d" % [c, lap]
			if ai.get_node_or_null(NodePath(candidate)) == null:  # queued-for-deletion bodies still hold their name
				callsign = candidate
				break
		lap += 1
	var squad := squad_for(&"friendly")
	var anchor: Node3D = squad.leader if is_instance_valid(squad.leader) else null
	var wedge: Array = Squad.FORMATIONS["wedge"]
	var pos := anchor.global_transform * (wedge[maxi(slot - 1, 0) % wedge.size()] as Vector3) if anchor \
		else SPAWN_POINTS[slot % SPAWN_POINTS.size()] + Vector3(0, 0, 3)
	return spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": pos, "loadout": [],
		"role": String(role), "team": team, "slot": slot, "combat": 0.5 + 0.03 * (slot % 5), "discipline": 0.6, "guard": false})


## Host only. `data`: name, faction, variant, pos, loadout, AI stats combat, discipline,
## guard, and optionally role (its kit is added to the loadout), team, slot and mode
## (a Squad.COMBAT_MODES name).
func spawn_soldier(data: Dictionary) -> Soldier:
	return ai_spawner.spawn(data) as Soldier


func _make_soldier(data: Dictionary) -> Node:
	var soldier: Soldier = PLAYER_SCENE.instantiate()
	soldier.name = data.name
	soldier.faction = StringName(data.faction)
	soldier.variant = data.variant
	soldier.position = data.pos
	soldier.role = StringName(data.get("role", ""))
	soldier.fire_team = int(data.get("team", -1))
	soldier.squad_slot = int(data.get("slot", -1))
	if multiplayer.is_server():
		var inventory: Inventory = soldier.get_node(^"Inventory")
		for id: String in data.loadout:
			inventory.take(StringName(id))
		if soldier.role != &"":
			Roles.apply_kit(inventory, soldier.role)
		var brain := SquadAI.new()
		brain.name = "SquadAI"
		brain.squad = squad_for(soldier.faction)
		brain.combat = data.combat
		brain.discipline = data.discipline
		brain.guard = data.guard
		brain.combat_mode = Squad.COMBAT_MODES.get(data.get("mode", "combat"), Squad.CombatMode.COMBAT)
		soldier.add_child(brain)
		soldier.get_node(^"Vitals").went_down.connect(_on_soldier_down.bind(soldier))
		soldier.died_for_good.connect(_on_died_for_good)
	return soldier


## Host only: a soldier went down; a squadmate who saw it calls it out.
func _on_soldier_down(soldier: Soldier) -> void:
	if is_instance_valid(soldier) and callouts:
		callouts.man_down(soldier)


## Client: tell the host which role this player picked in the main menu.
func _on_joined() -> void:
	request_role.rpc_id(1, String(Roles.local_choice))


## A player picks their role (sent on join). The host gives them that role's slot.
@rpc("any_peer", "call_local", "reliable")
func request_role(role: String) -> void:
	if not multiplayer.is_server() or not Roles.has(StringName(role)):
		return
	player_roles[multiplayer.get_remote_sender_id()] = StringName(role)
	rebalance_squad()


func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	voxel_world.send_edit_log_to(id)
	_add_player(id)
	get_tree().create_timer(JOIN_ROLE_WAIT_S).timeout.connect(_on_join_role_timeout.bind(id))


## Host: a joined player's pick never came; they play DEFAULT_JOIN_ROLE.
func _on_join_role_timeout(id: int) -> void:
	if players.get_node_or_null(str(id)) != null and not player_roles.has(id):
		player_roles[id] = DEFAULT_JOIN_ROLE
		rebalance_squad()


func _on_peer_left(id: int) -> void:
	var player := players.get_node_or_null(str(id)) as Soldier
	if player:
		if multiplayer.is_server():
			_server_player_leaves(player)
		player.queue_free()
	if multiplayer.is_server():
		player_roles.erase(id)
		_kitted.erase(id)
		var squad := squad_for(&"friendly")
		if squad.leader == player:
			squad.leader = players.get_node_or_null(^"1")
		rebalance_squad()


## Host only: a player leaves the session. Whoever they carry is put down, and anyone carrying
## them lets go. One who leaves while down (unconscious) leaves their body behind, gear and
## all, like a player who died; one who leaves on their feet takes their gear with them.
func _server_player_leaves(player: Soldier) -> void:
	player.release_carried()
	if not player.vitals.is_up() and not player.vitals.is_dead():
		player.server_leave_body()
	elif is_instance_valid(player.carried_by):
		player.carried_by.release_carried()


func _add_player(id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.position = next_spawn_point()
	players.add_child(player, true)
	if id == 1:
		_squads[&"friendly"].leader = player  # the host leads until someone else gives an order
	(player as Soldier).vitals.went_down.connect(_on_soldier_down.bind(player))
	rebalance_squad()


func _make_item(data: Dictionary) -> Node:
	var item := WorldItem.new()
	item.item_id = StringName(data.id)
	item.count = data.count
	item.state = data.get("state", {})
	item.uid = data.uid
	item.name = data.uid
	item.position = data.pos
	return item


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6d6a55")
	plane.material = material
	mesh_instance.mesh = plane
	ground.add_child(mesh_instance)
	add_child(ground)


## Voxel structures, in metres, each in its material (VoxelWorld.Mat): a concrete walled
## compound with a south gate, a painted-concrete main building with a doorway, concrete
## and sandbag low cover, wooden crates, a wooden lean-to shed with a sheet-metal roof
## against the east wall, and a sheet-metal shipping container by the west wall. Rounds go
## through the wood and the sheet metal; the concrete only takes small marks.
func _build_structures() -> void:
	var h := COMPOUND_HALF
	var t := WALL_THICKNESS
	var C := VoxelWorld.Mat.CONCRETE
	# Perimeter, with a 4 m gate in the south wall.
	voxel_world.add_box_m(Vector3(-h, 0, -h), Vector3(h, 2.6, -h + t), C)
	voxel_world.add_box_m(Vector3(-h, 0, -h), Vector3(-h + t, 2.6, h), C)
	voxel_world.add_box_m(Vector3(h - t, 0, -h), Vector3(h, 2.6, h), C)
	voxel_world.add_box_m(Vector3(-h, 0, h - t), Vector3(-2, 2.6, h), C)
	voxel_world.add_box_m(Vector3(2, 0, h - t), Vector3(h, 2.6, h), C)
	# Main building, 10 x 8 m, doorway in the south wall.
	var P := VoxelWorld.Mat.PAINTED
	voxel_world.add_box_m(Vector3(-5, 0, -12), Vector3(5, 3, -12 + t), P)
	voxel_world.add_box_m(Vector3(-5, 0, -12), Vector3(-5 + t, 3, -4), P)
	voxel_world.add_box_m(Vector3(5 - t, 0, -12), Vector3(5, 3, -4), P)
	voxel_world.add_box_m(Vector3(-5, 0, -4 - t), Vector3(-0.6, 3, -4), P)
	voxel_world.add_box_m(Vector3(0.6, 0, -4 - t), Vector3(5, 3, -4), P)
	voxel_world.add_box_m(Vector3(-0.6, 2.2, -4 - t), Vector3(0.6, 3, -4), P)
	# Low cover: a sandbag wall and two concrete ones.
	voxel_world.add_box_m(Vector3(-9, 0, 6), Vector3(-6, 1.1, 6.4), VoxelWorld.Mat.SANDBAG)
	voxel_world.add_box_m(Vector3(6, 0, 3), Vector3(9, 1.1, 3.4), C)
	voxel_world.add_box_m(Vector3(-1.5, 0, 10), Vector3(1.5, 1.1, 10.4), C)
	# Crates.
	var W := VoxelWorld.Mat.WOOD
	voxel_world.add_box_m(Vector3(-13, 0, -11), Vector3(-12, 1, -10), W)
	voxel_world.add_box_m(Vector3(-12, 0, -11), Vector3(-11, 1, -10), W)
	voxel_world.add_box_m(Vector3(-12.5, 1, -11), Vector3(-11.5, 2, -10), W)
	var S := VoxelWorld.Mat.SHEET_METAL
	for box: Array in SHED + CONTAINER:
		voxel_world.add_box_m(box[0], box[1], W if box[2] == "wood" else S)
