class_name CompoundLevel
extends Node3D
## Gray-box hostile compound: flat ground, 10 cm voxel walls you can shoot through, loot,
## and armored target dummies. Owns player and item spawning for the session.

const PLAYER_SCENE := preload("res://scenes/soldier.tscn")
const SPAWN_POINTS: Array[Vector3] = [Vector3(-3, 0.1, 24), Vector3(-1, 0.1, 24), Vector3(1, 0.1, 24), Vector3(3, 0.1, 24)]
const COMPOUND_HALF := 20.0
## The flat ground pad's side (m), centred on the origin (the compound and the base hub).
const GROUND_SIZE_M := 160.0
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
	# MOLLE pouches and what goes in them, west of the gate.
	{"uid": "c01_pouch_mag_a", "id": "pouch_mag_double", "count": 3, "pos": Vector3(-8, 0.5, 21)},
	{"uid": "c01_pouch_mag_b", "id": "pouch_mag_single", "count": 2, "pos": Vector3(-8, 0.5, 22)},
	{"uid": "c01_pouch_pistol", "id": "pouch_pistol_mag", "pos": Vector3(-8, 0.5, 23)},
	{"uid": "c01_pouch_ifak", "id": "pouch_ifak", "pos": Vector3(-8, 0.5, 24)},
	{"uid": "c01_pouch_radio", "id": "pouch_radio", "pos": Vector3(-9, 0.5, 21)},
	{"uid": "c01_radio", "id": "radio", "pos": Vector3(-9, 0.5, 22)},
	{"uid": "c01_pouch_binos", "id": "pouch_binos", "pos": Vector3(-9, 0.5, 23)},
	{"uid": "c01_binoculars", "id": "binoculars", "pos": Vector3(-9, 0.5, 24)},
	{"uid": "c01_knife", "id": "knife", "pos": Vector3(-10, 0.5, 21)},
	{"uid": "c01_pouch_sustain", "id": "pouch_sustainment", "pos": Vector3(-10, 0.5, 22)},
	{"uid": "c01_pouch_gp", "id": "pouch_utility", "pos": Vector3(-10, 0.5, 23)},
	{"uid": "c01_pouch_nade", "id": "pouch_grenade", "count": 2, "pos": Vector3(-10, 0.5, 24)},
	{"uid": "c01_ifak_a", "id": "ifak", "count": 2, "pos": Vector3(-6, 0.5, 4)},
	{"uid": "c01_iv18_a", "id": "iv_18", "count": 3, "pos": Vector3(-7, 0.5, 4)},
	{"uid": "c01_iv14_a", "id": "iv_14", "count": 1, "pos": Vector3(-7, 0.5, 5)},
	{"uid": "c01_iv10_a", "id": "iv_10", "pos": Vector3(-8, 0.5, 5)},
	{"uid": "c01_io_a", "id": "io_kit", "pos": Vector3(-6, 0.5, 5)},
	{"uid": "c01_saline_a", "id": "saline_500", "count": 2, "pos": Vector3(-8, 0.5, 4)},
	{"uid": "c01_blood_a", "id": "blood_1000", "pos": Vector3(-6, 0.5, 6)},
	{"uid": "c01_pbag_a", "id": "pressure_bag", "pos": Vector3(-7, 0.5, 6)},
	{"uid": "c01_needle_a", "id": "decompression_needle", "count": 2, "pos": Vector3(-8, 0.5, 6)},
	{"uid": "c01_oximeter_a", "id": "pulse_oximeter", "pos": Vector3(-5, 0.5, 5)},
	{"uid": "c01_epi_a", "id": "epinephrine", "count": 2, "pos": Vector3(-5, 0.5, 6)},
	{"uid": "c01_atropine_a", "id": "atropine", "pos": Vector3(-5, 0.5, 4)},
	{"uid": "c01_adenosine_a", "id": "adenosine", "pos": Vector3(-8, 0.5, 3)},
	{"uid": "c01_defib_a", "id": "defibrillator", "pos": Vector3(-7, 0.5, 3)},
	{"uid": "c01_surgery2_a", "id": "surgery_kit_2", "pos": Vector3(-6, 0.5, 3)},
	{"uid": "c01_surgery5_a", "id": "surgery_kit_5", "pos": Vector3(-5, 0.5, 3)},
	{"uid": "c01_burn_a", "id": "burn_dressing", "count": 3, "pos": Vector3(-8, 0.5, 2)},
	{"uid": "c01_blanket_a", "id": "hypothermia_blanket", "count": 2, "pos": Vector3(-7, 0.5, 2)},
	{"uid": "c01_earpro_a", "id": "ear_protection", "pos": Vector3(-6, 0.5, 2)},
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
## The clean test layout (Captain: a clean test environment, no needless clutter): players
## come in their role's kit, so the gate holds one tidy row of spares behind the spawn, and the
## compound only what the test contract and scavenging need.
const CLEAN_LOOT := [
	{"uid": "c01_frag_a", "id": "frag_grenade", "count": 3, "pos": Vector3(-3, 0.5, 27)},
	{"uid": "c01_smoke_a", "id": "smoke_grenade", "count": 3, "pos": Vector3(-2, 0.5, 27)},
	{"uid": "c01_flash_a", "id": "flashbang", "count": 3, "pos": Vector3(-1, 0.5, 27)},
	{"uid": "c01_charge_a", "id": "breaching_charge", "count": 3, "pos": Vector3(0, 0.5, 27)},
	{"uid": "c01_rounds_556_a", "id": "rounds_556", "count": 120, "pos": Vector3(1, 0.5, 27)},
	{"uid": "c01_rounds_9mm_a", "id": "rounds_9mm", "count": 51, "pos": Vector3(2, 0.5, 27)},
	{"uid": "c01_rounds_762_a", "id": "rounds_762", "count": 60, "pos": Vector3(3, 0.5, 27)},
	{"uid": "c01_salvage_a", "id": "electronics_salvage", "count": 8, "pos": Vector3(3, 0.5, -10)},
	{"uid": "c01_hvt_case", "id": "hvt_case", "pos": Vector3(0, 0.5, -10)},
	{"uid": "c01_crate_a", "id": "supply_crate", "pos": Vector3(12, 0.6, -12)},
]

## Turn off to host a session without AI (the older test suites do).
static var spawn_ai := true
## Players start in their role's kit (Roles) the first time they spawn, and respawn in it. Off
## by default (the older suites expect an empty start and the gate loot); the main menu's play
## entries turn it on with clean_loot. AI squadmates always get their role's kit.
static var player_role_kits := false
## Lay out CLEAN_LOOT instead of LOOT (the main menu's play entries).
static var clean_loot := false


## The starting loot this session lays out.
static func starting_loot() -> Array:
	return CLEAN_LOOT if clean_loot else LOOT

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
## People (wave 4): "intel" is what an officer or squad leader ("rank") carries, looted from
## his body (PeopleLayer.server_give_intel gives each its own intel id).
const HOSTILES := [
	{"name": "Hostile1", "pos": Vector3(-2.5, 0.1, -10), "buddy": "Hostile2", "guard": true, "rank": "officer", "intel": ["intel_phone", "intel_documents"]},
	{"name": "Hostile2", "pos": Vector3(2.5, 0.1, -6.5), "buddy": "Hostile1", "guard": true},
	{"name": "Hostile3", "pos": Vector3(-12, 0.1, -2), "buddy": "Hostile4", "guard": false, "rank": "squad leader", "intel": ["intel_documents"]},
	{"name": "Hostile4", "pos": Vector3(-10, 0.1, -3), "buddy": "Hostile3", "guard": false},
]
## OPFOR small arms (weapon pack 1): the hostile faction carries Eastern-bloc stand-ins, not M4s.
## HOSTILE_LOADOUT is the AKM kit; hostile_loadout(i) hands a team or garrison its mix.
const HOSTILE_BODY := ["plate_carrier_light", "plate_pe_l3", "helmet_bump", "assault_pack"]
const HOSTILE_TAIL := ["ifak", "frag_grenade"]
const HOSTILE_GUNS := {
	"akm": ["akm", "mag_762x39", "mag_762x39", "mag_762x39", "mag_762x39"],
	"ak74": ["ak74", "mag_545", "mag_545", "mag_545", "mag_545"],
	"rpk": ["rpk", "mag_rpk40", "mag_rpk40", "mag_rpk40"],
	"pkm": ["pkm", "belt_762x54r", "belt_762x54r"],
	"svd": ["svd", "mag_svd", "mag_svd", "mag_svd", "mag_svd", "mag_svd"],
}
## Who in a group of eight carries what: mostly AKs, a gunner, a marksman, a machine-gunner.
const HOSTILE_MIX: Array[String] = ["akm", "ak74", "akm", "rpk", "ak74", "svd", "akm", "pkm"]
const HOSTILE_LOADOUT := HOSTILE_BODY + HOSTILE_GUNS.akm + HOSTILE_TAIL


## The OPFOR kit for the `index`-th soldier of a team, wave or garrison.
static func hostile_loadout(index: int) -> Array:
	return HOSTILE_BODY + (HOSTILE_GUNS[HOSTILE_MIX[posmod(index, HOSTILE_MIX.size())]] as Array) + HOSTILE_TAIL


## True for HOSTILE_LOADOUT and every kit hostile_loadout hands out.
static func is_hostile_kit(kit: Array) -> bool:
	for i in HOSTILE_MIX.size():
		if kit == hostile_loadout(i):
			return true
	return false
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
## The compound's voxel structures (null on a zone, whose modules each have their own: see
## voxel_worlds()).
@onready var voxel_world: VoxelWorld = get_node_or_null(^"VoxelWorld") as VoxelWorld

var _spawn_index := 0
var _throw_count := 0
var _throwers := {}  # host: grenade serial -> who threw it (Harm: whose fragments hurt whom)
var _squads := {}  # faction -> Squad
var _ai_ready := false  # host: AI spawns once the voxel walls exist
## Host: the role each player picked, by peer id.
var player_roles := {}
## Host: each player's shooting shoulder (peer id -> true for left-handed), from their main-menu
## pick (Handedness), sent on join like the role.
var player_handed := {}
var _kitted := {}  # host: peer ids that got their role kit
## Host: squad slots whose AI squadmate died (permadeath): no new squadmate takes them.
var _fallen_slots := {}
## AI callouts as subtitles (same node on every peer).
var callouts: Callouts
## Civilians, HVTs and intel (wave 4, PeopleLayer; same node on every peer).
var people: PeopleLayer


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
	MapNodes.install(self)  # W13: map markers, briefing, extraction, reinforcement timer
	_build_environment()
	_build_structures()
	Net.hosted.connect(_on_hosted)
	Net.joined.connect(_on_joined)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	people = PeopleLayer.new()  # "People": civilians, HVTs, intel (wave 4)
	add_child(people)
	add_child(Charges.new())  # "Charges": placed explosives (wave 4B)
	add_child(VehicleLayer.new())  # "Vehicles": vehicles and wrecks (wave 5)
	add_child(Launchers.new())  # "Launchers": anti-armour rockets and missiles in flight (wave 5)
	add_child(HeliSupports.new())  # "HeliSupports": Black Hawk resupply, transport, extraction (wave 5b V3)
	AavSupport.install(self)  # wave 5b (V4): the LHD or FOB origin, the AAV support, the motor pool
	add_child(GroundGuard.new())  # "GroundGuard": puts back on the ground anything lost below or past it


## The playable area on the map, in metres on the ground plane (x along x, y along z): the
## map and its grid cover this (wave 4 interface; a world-scale zone level provides the same).
func map_area() -> Rect2:
	# W13: the ground the squad and the AI move on (the navigation area, 108 m square), not
	# just the voxel bounds (44 m): the gate, the spawn and the fields around are on the map.
	var b := NavBuilder.AREA
	return Rect2(b.position.x, b.position.z, b.size.x, b.size.z)


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return spawn_point(_spawn_index)


# --- Respawn points (Captain, playtest P0362, 2026-10-13) ---------------------------------------
# A dead player came back at once at one fixed point with their killer standing on it. Now
# (Soldier._server_respawn_now) they come back at the first of respawn_candidates() that is
# safe: no live enemy within RESPAWN_SAFE_M and none that can see it from within RESPAWN_SIGHT_M.
# With none safe, at respawn_fallback() (a zone's FOB) if that is safe; else wherever is least
# dangerous (respawn_clearance: the nearest enemy's distance, one in sight counting as closer).
# Design intent (docs/mission_brainstorm.md, squad wipe): respawn at the LHD or FOB and push back in.

## Proposed (Captain: about 150 m, and none with line of sight).
const RESPAWN_SAFE_M := 150.0
## An enemy further off than this doesn't count as seeing a respawn point.
const RESPAWN_SIGHT_M := 400.0
## Eye height above a respawn point, for the line-of-sight check.
const RESPAWN_EYE_M := 1.6
## Players respawning at one point stand this far apart (two rows of four).
const RESPAWN_SPREAD_M := 2.0
## Host: what the last respawn_point() picked and why, for the session log and tests.
var last_respawn := {}


## Host only. Where `player` respawns (see above), on the ground, spread from the last one.
func respawn_point(player: Soldier) -> Vector3:
	var cands := respawn_candidates()
	if cands.is_empty():
		last_respawn = {"why": "the level's spawn point"}
		return next_spawn_point()
	var foes := respawn_enemies(player)
	var pick: Variant = null
	var why := ""
	for i in cands.size():
		if respawn_clearance(cands[i], foes) >= RESPAWN_SAFE_M:
			pick = cands[i]
			why = "candidate %d of %d, no enemy near or in sight" % [i + 1, cands.size()]
			break
	var fallback: Variant = respawn_fallback()
	if pick == null and fallback != null and respawn_clearance(fallback, foes) >= RESPAWN_SAFE_M:
		pick = fallback
		why = "every insertion hot: the FOB"
	if pick == null:
		var best := -1.0
		var all: Array[Vector3] = cands.duplicate()
		if fallback != null:
			all.append(fallback)
		for p in all:
			var c := respawn_clearance(p, foes)
			if c > best:
				best = c
				pick = p
		why = "every point hot: the least dangerous (nearest enemy %.0f m, or in sight)" % best
	_spawn_index += 1
	var k := posmod(_spawn_index, 8)
	var at: Vector3 = ground_point((pick as Vector3) + Vector3((k % 4 - 1.5) * RESPAWN_SPREAD_M, 0, (k / 4) * RESPAWN_SPREAD_M))
	last_respawn = {"pos": at, "why": why, "point": pick}
	SessionLog.note("%s respawned at (%.0f, %.0f): %s" % [player.log_name(), at.x, at.z, why])
	return at


## Where a dead player may respawn, best first (ground points). Here: with the briefing
## deployed, its chosen insertion point, then its other insertion points and its extraction
## points; else none (the level's spawn point). ZoneLevel has the zone's own.
func respawn_candidates() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var briefing := MapNodes.briefing(self)
	if briefing == null or not briefing.is_deployed():
		return out
	add_respawn_candidate(out, briefing.insertion().get("pos", []))
	for point: Dictionary in briefing.insertion_points():
		add_respawn_candidate(out, point.get("pos", []))
	for point: Dictionary in briefing.zone.get("extraction_points", []):
		add_respawn_candidate(out, point.get("pos", []))
	return out


## Adds `at` (a Vector3, or an [x, z] map position) to `out` unless one already there is close.
func add_respawn_candidate(out: Array[Vector3], at: Variant) -> void:
	var p: Vector3
	if at is Vector3:
		p = at
	elif at is Array and (at as Array).size() >= 2:
		p = ground_point(Vector3(float(at[0]), 0.1, float(at[1])))
	else:
		return
	for q in out:
		if Vector2(q.x - p.x, q.z - p.z).length() < RESPAWN_SPREAD_M * 4.0:
			return
	out.append(p)


## A safe point to fall back on when every candidate is hot (a zone's FOB), or null.
func respawn_fallback() -> Variant:
	return null


## Host: the soldiers who'd make a respawn point unsafe for `player`: on another side, up, and
## not civilians, captives or HVTs (Person.is_noncombatant).
func respawn_enemies(player: Soldier) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s != player and s.faction != player.faction and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and not Person.is_noncombatant(s):
			out.append(s)
	return out


## How safe `at` is from `foes`: the nearest one's distance, where one that can see it (from
## within RESPAWN_SIGHT_M) counts as RESPAWN_SAFE_M / RESPAWN_SIGHT_M as far. RESPAWN_SAFE_M and
## over is safe; INF with no foes.
func respawn_clearance(at: Vector3, foes: Array[Soldier]) -> float:
	var out := INF
	var eye := at + Vector3.UP * RESPAWN_EYE_M
	var world := get_world_3d()
	for s in foes:
		var d := s.global_position.distance_to(at)
		var c := d
		if d < RESPAWN_SIGHT_M and d >= RESPAWN_SAFE_M and Throwables.clear_line(world, s.camera.global_position, eye):
			c = d * RESPAWN_SAFE_M / RESPAWN_SIGHT_M
		out = minf(out, c)
	return out


## The `index`th of the level's player spawn points (they repeat): the compound's gate.
func spawn_point(index: int) -> Vector3:
	return SPAWN_POINTS[posmod(index, SPAWN_POINTS.size())]


# --- Level API shared with ZoneLevel (wave 4) -------------------------------------------------

## What a joining client must load to play this level (LevelSwitch sends it on join).
func level_info() -> Dictionary:
	return {"level": "compound"}


## `pos` moved onto the ground (the compound's ground is flat at 0; a zone's follows its terrain).
func ground_point(pos: Vector3) -> Vector3:
	return pos


## The ground's height at (x, z): the compound's is flat at 0 (ZoneLevel: its terrain).
func ground_height(_x: float, _z: float) -> float:
	return 0.0


## Where there is ground (x along x, y along z, metres): the compound's GROUND_SIZE_M pad
## (ZoneLevel: the whole zone). Past it there is nothing to stand on (GroundGuard).
func ground_area() -> Rect2:
	return Rect2(-GROUND_SIZE_M * 0.5, -GROUND_SIZE_M * 0.5, GROUND_SIZE_M, GROUND_SIZE_M)


## `pos` relative to the ground: its y is height above the ground at (x, z). The compound's
## fixed placements (PeopleLayer.COMPOUND) are written for flat ground at 0; B-05: in a
## procedural zone they spawned under the terrain and fell to y -120.
func above_ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x, ground_height(pos.x, pos.z) + pos.y, pos.z)


## The nearest spot on the ground to `pos` (Captain, 2026-10-14: anything that fell below or
## past the ground goes back on it nearby, GroundGuard): (x, z) kept inside the ground area by
## GroundGuard.INSET_M, then on the ground (ground_point).
func put_on_ground(pos: Vector3) -> Vector3:
	var area := ground_area().grow(-GroundGuard.INSET_M)
	var x := clampf(pos.x if is_finite(pos.x) else 0.0, area.position.x, area.end.x)
	var z := clampf(pos.z if is_finite(pos.z) else 0.0, area.position.y, area.end.y)
	return Vector3(x, ground_height(x, z) + 0.1, z)


## Every voxel world in the level that is loaded now.
func voxel_worlds() -> Array[VoxelWorld]:
	var out: Array[VoxelWorld] = []
	if voxel_world:
		out.append(voxel_world)
	return out


## Host only. A blast (a frag) at a world-space point against the voxels around it
## (VoxelWorld.server_blast on each loaded world it reaches).
func server_blast(pos: Vector3, radius_m: float) -> void:
	for world in voxel_worlds():
		world.server_blast(pos, radius_m)


## Host only.
func spawn_item(id: StringName, count: int, pos: Vector3, uid: String, state := {}) -> void:
	item_spawner.spawn({"id": String(id), "count": count, "pos": pos, "uid": uid, "state": state})


## Host only. Spawns an item a player dropped and records it for saving. Returns its uid
## (WorldItem.uid), so whoever dropped it can find that very item again.
func server_spawn_dropped(id: StringName, count: int, pos: Vector3, state := {}) -> String:
	var uid := GameState.new_uid()
	GameState.item_dropped(uid, id, count, pos, state)
	spawn_item(id, count, pos, uid, state)
	return uid


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
	corpse.body = String(data.get("body", ""))
	var p: Array = data.get("pos", [0.0, 0.1, 0.0])
	corpse.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	corpse.rotation.y = float(data.get("rot_y", 0.0))
	corpse.role = StringName(data.get("role", ""))
	corpse.body_label = String(data.get("label", ""))
	corpse.person_name = String(data.get("person_name", ""))  # the name tape (older saves: none)
	corpse.nation = String(data.get("nation", ""))
	corpse.left_handed = bool(data.get("left", false))
	corpse.body_uid = String(data.uid)
	corpse.collision_layer = 0
	# Lies as it lay (its ragdoll pose; older saves and fresh bodies: none, it falls from where it is drawn).
	(corpse.get_node(^"Model") as CharacterModel).ragdoll_net = PackedFloat32Array(data.get("ragdoll", []))
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
	# Wave 5: the zone's vehicles and wrecks too (GameState.vehicles), bodies back in their seats.
	var vehicles := get_node_or_null(^"Vehicles") as VehicleLayer
	if vehicles:
		vehicles.server_restore()


## Host only. A visible tracer streak along the round's real curved path on every peer
## (Captain, 2026-10-16: "we dont have tracers or bullets that can be seen in game yet"). Purely
## cosmetic (Sfx.server_shot already carries the sound); suppressed shots get a faint one, not
## none, since the round still flies even if the bang is quiet.
@rpc("authority", "call_local", "unreliable")
func show_tracer(points: PackedVector3Array, suppressed: bool, kind: int = Tracer.Kind.RED) -> void:
	Tracer.spawn(self, points, suppressed, kind)


@rpc("authority", "call_local", "unreliable")
func show_impact(pos: Vector3, normal: Vector3, kind: String) -> void:
	Sfx.play_at({"plate": &"impact_plate", "vehicle": &"impact_plate", "body": &"impact_body"}.get(kind, &"impact_dirt"), pos)
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
## `thrower` is noted on the host's copy (Grenade.thrower).
func server_throw(id: StringName, origin: Vector3, velocity: Vector3, thrower: Node = null) -> void:
	_throw_count += 1
	if thrower:
		_throwers[_throw_count] = thrower
	show_throw.rpc(_throw_count, String(id), origin, velocity)


@rpc("authority", "call_local", "reliable")
func show_throw(serial: int, id: String, origin: Vector3, velocity: Vector3) -> void:
	var grenade := Grenade.new()
	grenade.name = "Grenade%d" % serial
	grenade.setup(StringName(id))
	if is_instance_valid(_throwers.get(serial)):
		grenade.thrower = _throwers[serial]
	_throwers.erase(serial)
	add_child(grenade)
	grenade.global_position = origin
	grenade.linear_velocity = velocity
	grenade.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))


@rpc("authority", "call_local", "reliable")
func show_explosion(pos: Vector3) -> void:
	_burst(pos, Color(1.0, 0.6, 0.25), 3.2, 0.35)
	Sfx.play_at(&"explosion", pos)


@rpc("authority", "call_local", "reliable")
func show_flash(pos: Vector3) -> void:
	_burst(pos, Color.WHITE, 1.0, 0.15)
	Sfx.play_at(&"flashbang", pos)


## A smoke cloud on every peer, in its colour (a name in SmokeCloud.COLOURS), `age` seconds
## old (a late joiner gets the clouds already out: _send_smoke_to).
@rpc("authority", "call_local", "reliable")
func spawn_smoke(pos: Vector3, colour: String, age := 0.0) -> void:
	var cloud := SmokeCloud.new()
	cloud.colour = colour
	cloud.age = age
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
	BodyVolume.warm(["", BodyVolume.FEMALE])  # hits are judged on the host: build both bodies' shapes before the first one
	GameState.load_zone()
	voxel_world.load_edits(GameState.voxel_edits)
	for loot: Dictionary in starting_loot():
		if not GameState.is_looted(loot.uid):
			spawn_item(StringName(loot.id), loot.get("count", 1), loot.pos, loot.uid)
	for uid: String in GameState.dropped:
		var d: Dictionary = GameState.dropped[uid]
		spawn_item(StringName(d.id), int(d.count), Vector3(d.pos[0], d.pos[1], d.pos[2]), uid, GameState.from_json(d.get("state", {})))
	player_roles[1] = Roles.local_choice  # the host's own pick from the main menu
	player_handed[1] = Handedness.local_left()
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
			"loadout": hostile_loadout(HOSTILES.find(h)), "combat": 0.45, "discipline": 0.5, "guard": h.guard, "mode": "aware"})
	for h: Dictionary in hostiles:
		spawned[h.name].buddy = spawned.get(h.buddy)  # null if the buddy's body is in the save
		for intel_id: String in h.get("intel", []):  # people (wave 4): officers' intel
			people.server_give_intel(spawned[h.name], StringName(intel_id), "%s (%s)" % [h.name, h.get("rank", "")])
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
		if BaseHub.campaign_running:
			BaseHub.server_give_due_kit(h)  # B-23: campaign gear is the player's own; a new player's kit, once
		elif player_role_kits and player_roles.has(h.name.to_int()) and not _kitted.has(h.name.to_int()):
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
## keeps no slot and is never removed by rebalance_squad (it lies where it fell). Nor is a
## squadmate a recovery contract is about (BaseHub, meta "recovery"): found in the zone, they
## come along outside the slots.
func _squad_ai() -> Array:
	return ai.get_children().filter(func(s: Node) -> bool: return s is Soldier and s.faction == &"friendly" \
		and not s.is_queued_for_deletion() and not s.vitals.is_dead() and not s.has_meta(&"recovery") and not s.has_meta(&"vehicle_crew"))  # wave 5b: an AAV's crew


## A squadmate whose slot a player took (or whose role changed) leaves the session. A dead one
## never does: its body and gear stay where it fell.
func _remove_squadmate(s: Soldier) -> void:
	if s.vitals.is_dead():
		return
	BaseHub.server_squadmate_leaving(s)  # campaign: a roster member keeps their gear (wave 4)
	if not s.has_meta(&"roster_id"):
		_drop_extras(s)  # outside the campaign: what it was given or picked up stays here
	s.release_carried()
	if is_instance_valid(s.carried_by):
		s.carried_by.release_carried()
	s.queue_free()


## Host only. A squadmate leaving its slot outside the campaign (a player took it) drops what it
## holds beyond the kit it spawned with (meta "start_gear"): what players handed it, what it
## scavenged, an objective item. Whole stacks with their state (part-used magazines, damaged
## armor), in a pile at its feet. Its own kit goes with it, so a join doesn't hand out free
## gear (audit L1-03: before, anything it had been given was lost).
func _drop_extras(s: Soldier) -> void:
	var inv := s.inventory
	var start: Dictionary = s.get_meta(&"start_gear", {})
	var now := Roster.gear_counts(inv.net_state)
	var extra := {}
	for id: String in now:
		var n := int(now[id]) - int(start.get(id, 0))
		if n > 0:
			extra[id] = n
	var pile: Array[Dictionary] = []
	var take := func(entry: Dictionary) -> void:
		if entry.is_empty():
			return
		pile.append(entry)
		var counted := {}
		Roster.count_entry(entry, counted)  # an entry's state may carry more (a carrier's pouches)
		for id: String in counted:
			if extra.has(id):
				extra[id] = int(extra[id]) - int(counted[id])
	# Stowed stacks: first the ones unlike anything in its starting kit (the 7-round magazine it
	# was handed, not one of its own full ones), then any others still over.
	var kit_states: Dictionary = s.get_meta(&"start_states", {})
	for unlike_first: bool in [true, false]:
		for c: StringName in inv.search_containers():
			var i: int = (inv.containers.get(c, []) as Array).size() - 1
			while i >= 0:
				var e: Dictionary = inv.containers[c][i]
				var id := String(e.id)
				var like_kit: bool = (kit_states.get(id, []) as Array).has(e.get("state", {}))
				if int(extra.get(id, 0)) > 0 and not (unlike_first and like_kit):
					take.call(inv.remove_entry(c, i, int(extra[id])))
				i -= 1
	for slot: StringName in Inventory.SLOTS:
		var id := String(inv.slots[slot])
		if id != "" and int(extra.get(id, 0)) > 0:
			var off := inv.unequip(slot)
			if not off.is_empty():
				take.call({"id": off.id, "count": 1, "state": off.state})
	if inv.hands != &"" and int(extra.get(String(inv.hands), 0)) > 0:
		take.call({"id": inv.release_hands(), "count": 1})
	for i in pile.size():
		var e: Dictionary = pile[i]
		var at := s.global_position + Vector3(0.35 * (i % 3) - 0.35, 0.4, 0.35 * (i / 3))
		server_spawn_dropped(StringName(e.id), int(e.get("count", 1)), at, e.get("state", {}))


## Host only: a squadmate died (permadeath). Its body stays where it fell; it leaves the squad
## (no slot, no orders) and nobody new takes its slot.
func _on_died_for_good(s: Soldier) -> void:
	if s.faction == &"friendly" and s.squad_slot >= 0:
		BaseHub.server_squadmate_died(s)  # campaign: a roster member is lost (wave 4)
		_fallen_slots[s.squad_slot] = true
		s.squad_slot = -1


## Host only. A new AI squadmate in `slot`, named with the first callsign no other node holds
## (dead squadmates' bodies keep theirs, so past the eighth it's "Alpha 2" and so on), in its
## role's kit, placed in formation behind the lead.
func _spawn_squadmate(slot: int, role: StringName, team: int) -> Soldier:
	if BaseHub.campaign_squad():  # campaign: the company's own people, from the roster (wave 4)
		return BaseHub.server_spawn_roster_squadmate(self, slot, role, team)
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
		else spawn_point(slot) + Vector3(0, 0, 3)
	return spawn_soldier({"name": callsign, "faction": "friendly", "variant": "multicam", "pos": ground_point(pos), "loadout": [],
		"role": String(role), "team": team, "slot": slot, "combat": 0.5 + 0.03 * (slot % 5), "discipline": 0.6, "guard": false})


## Host only. `data`: name, faction, variant, optionally body (VoxelArt.BODIES), pos, loadout, AI stats combat, discipline,
## guard, and optionally role (its kit is added to the loadout), team, slot and mode
## (a Squad.COMBAT_MODES name).
## Host: spawns an AI soldier from `data` (see _make_soldier). Who they are is settled here,
## before the spawn, so it rides the spawn data and every peer builds the same soldier: a
## surname and nationality (Names) and a male or female body by that nation's norms for
## their role (Demographics), unless `data` already says.
func spawn_soldier(data: Dictionary) -> Soldier:
	var d := data.duplicate()
	if multiplayer.is_server():
		var faction := StringName(d.faction)
		if not d.has("person_name"):
			var who := Names.pick(faction, String(d.name), _names_on(faction))
			d["person_name"] = who.name
			d["nation"] = who.nation
		if not d.has("body"):
			var female := Demographics.is_female(String(d.name), String(d.get("nation", "")), StringName(d.get("role", "")))
			d["body"] = VoxelArt.FEMALE if female else VoxelArt.MALE
		if d.body == VoxelArt.FEMALE:
			d["person_name"] = Names.feminine(String(d.person_name), String(d.get("nation", "")))
	return ai_spawner.spawn(d) as Soldier


## Host: the surnames already on `faction`'s side, the dead included (so a recruit replacing a
## fallen squadmate gets a name of his own).
func _names_on(faction: StringName) -> Dictionary:
	var taken := {}
	for s in ai.get_children():
		if s is Soldier and s.faction == faction and s.person_name != "":
			taken[s.person_name] = true
	return taken


func _make_soldier(data: Dictionary) -> Node:
	var soldier: Soldier = PLAYER_SCENE.instantiate()
	soldier.name = data.name
	soldier.faction = StringName(data.faction)
	soldier.variant = data.variant
	soldier.body = String(data.get("body", ""))
	soldier.position = data.pos
	soldier.role = StringName(data.get("role", ""))
	soldier.fire_team = int(data.get("team", -1))
	soldier.squad_slot = int(data.get("slot", -1))
	soldier.left_handed = bool(data.get("left", Handedness.roll_ai(String(data.name))))  # LEFT_SHARE of AI
	if multiplayer.is_server():
		soldier.person_name = String(data.get("person_name", ""))  # settled in spawn_soldier
		soldier.nation = String(data.get("nation", ""))
		var inventory: Inventory = soldier.get_node(^"Inventory")
		for id: String in data.loadout:
			inventory.take(StringName(id))
		if soldier.faction == &"hostile" and is_hostile_kit(data.loadout):
			for id: StringName in LauncherAI.insurgent_kit(self):  # wave 5: some carry an RPG-7
				inventory.take(id)
		if soldier.role != &"":
			Roles.apply_kit(inventory, soldier.role)
		# What it started with, so what it's handed or picks up later can be told apart
		# (_drop_extras, when a player takes its slot).
		soldier.set_meta(&"start_gear", Roster.gear_counts(inventory.net_state))
		var states := {}
		for c: StringName in inventory.search_containers():
			for e: Dictionary in inventory.containers[c]:
				if not states.has(String(e.id)):
					states[String(e.id)] = []
				states[String(e.id)].append(e.get("state", {}))
		soldier.set_meta(&"start_states", states)
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
	request_handedness.rpc_id(1, Handedness.local_left())


## A player picks their role (sent on join). The host gives them that role's slot.
@rpc("any_peer", "call_local", "reliable")
func request_role(role: String) -> void:
	if not multiplayer.is_server() or not Roles.has(StringName(role)):
		return
	player_roles[multiplayer.get_remote_sender_id()] = StringName(role)
	rebalance_squad()


## A player says which shoulder they shoot from (sent on join, from the main menu).
@rpc("any_peer", "call_local", "reliable")
func request_handedness(left: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	player_handed[id] = left
	var player := players.get_node_or_null(str(id)) as Soldier
	if player:
		player.left_handed = left


func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server():
		return
	voxel_world.send_edit_log_to(id)
	_send_smoke_to(id)
	_add_player(id)
	get_tree().create_timer(JOIN_ROLE_WAIT_S).timeout.connect(_on_join_role_timeout.bind(id))


## Host: the smoke clouds still out, to a player who just joined (audit L2-01: they missed the
## one-time spawn, so the AI could hide in smoke they couldn't see).
func _send_smoke_to(id: int) -> void:
	for cloud in SmokeCloud.active:
		if is_instance_valid(cloud) and is_ancestor_of(cloud) and not cloud.is_queued_for_deletion():
			spawn_smoke.rpc_id(id, cloud.global_position, cloud.colour, cloud.age)


## Host: a joined player's pick never came; they play DEFAULT_JOIN_ROLE.
func _on_join_role_timeout(id: int) -> void:
	if players.get_node_or_null(str(id)) != null and not player_roles.has(id):
		player_roles[id] = DEFAULT_JOIN_ROLE
		rebalance_squad()


## A client leaves the leaver's player alone: the host's despawn frees it there (B-04: freed
## here first, the despawn that followed logged 'Condition "!pinfo.recv_nodes.has(net_id)"').
func _on_peer_left(id: int) -> void:
	var player := players.get_node_or_null(str(id)) as Soldier
	if player and multiplayer.is_server():
		_server_player_leaves(player)
		player.queue_free()
	if multiplayer.is_server():
		player_roles.erase(id)
		player_handed.erase(id)
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
	# Placed before it enters the tree: the spawn goes to the clients as it does, with its
	# spawn_position (B-04: a level moving the player after that sent the old spot).
	player.position = _player_start(id)
	(player as Soldier).left_handed = bool(player_handed.get(id, false))
	(player as Soldier).spawn_position = player.position  # a client's own player starts here too
	players.add_child(player, true)
	if id == 1:
		_squads[&"friendly"].leader = player  # the host leads until someone else gives an order
	(player as Soldier).vitals.went_down.connect(_on_soldier_down.bind(player))
	BaseHub.server_player_added(self, player)  # campaign: their gear, the respawn pool (wave 4)
	rebalance_squad()


## Host: where the player of peer `id` comes in (the compound's gate; a zone's insertion).
func _player_start(_id: int) -> Vector3:
	return next_spawn_point()


func _make_item(data: Dictionary) -> Node:
	var item := WorldItem.new()
	item.item_id = StringName(data.id)
	item.count = data.count
	item.state = data.get("state", {})
	item.uid = data.uid
	item.name = data.uid
	item.position = data.pos
	item.rotation = ItemArt.spawn_rotation(ItemDB.get_item(item.item_id))  # a plate lies flat
	return item


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	GameSettings.apply_sun(sun)  # the shadows setting
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
	box.size = Vector3(GROUND_SIZE_M, 1, GROUND_SIZE_M)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
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
	for box: Array in structure_boxes():
		voxel_world.add_box_m(box[0], box[1], box[2])


## The compound's structures as [from, to (metres), VoxelWorld.Mat] boxes, in build order
## (see _build_structures). A zone places the same compound as a module (ZoneModules).
static func structure_boxes() -> Array:
	var out: Array = []
	var h := COMPOUND_HALF
	var t := WALL_THICKNESS
	var C := VoxelWorld.Mat.CONCRETE
	# Perimeter, with a 4 m gate in the south wall.
	out.append([Vector3(-h, 0, -h), Vector3(h, 2.6, -h + t), C])
	out.append([Vector3(-h, 0, -h), Vector3(-h + t, 2.6, h), C])
	out.append([Vector3(h - t, 0, -h), Vector3(h, 2.6, h), C])
	out.append([Vector3(-h, 0, h - t), Vector3(-2, 2.6, h), C])
	out.append([Vector3(2, 0, h - t), Vector3(h, 2.6, h), C])
	# Main building, 10 x 8 m, doorway in the south wall.
	var P := VoxelWorld.Mat.PAINTED
	out.append([Vector3(-5, 0, -12), Vector3(5, 3, -12 + t), P])
	out.append([Vector3(-5, 0, -12), Vector3(-5 + t, 3, -4), P])
	out.append([Vector3(5 - t, 0, -12), Vector3(5, 3, -4), P])
	out.append([Vector3(-5, 0, -4 - t), Vector3(-0.6, 3, -4), P])
	out.append([Vector3(0.6, 0, -4 - t), Vector3(5, 3, -4), P])
	out.append([Vector3(-0.6, 2.2, -4 - t), Vector3(0.6, 3, -4), P])
	# Low cover: a sandbag wall and two concrete ones.
	out.append([Vector3(-9, 0, 6), Vector3(-6, 1.1, 6.4), VoxelWorld.Mat.SANDBAG])
	out.append([Vector3(6, 0, 3), Vector3(9, 1.1, 3.4), C])
	out.append([Vector3(-1.5, 0, 10), Vector3(1.5, 1.1, 10.4), C])
	# Crates.
	var W := VoxelWorld.Mat.WOOD
	out.append([Vector3(-13, 0, -11), Vector3(-12, 1, -10), W])
	out.append([Vector3(-12, 0, -11), Vector3(-11, 1, -10), W])
	out.append([Vector3(-12.5, 1, -11), Vector3(-11.5, 2, -10), W])
	var S := VoxelWorld.Mat.SHEET_METAL
	for box: Array in SHED + CONTAINER:
		out.append([box[0], box[1], W if box[2] == "wood" else S])
	return out
