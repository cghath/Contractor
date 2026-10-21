class_name Bombers
extends Node
## Suicide bombers on foot (wave 6f; Captain, 2026-10-11: "where it fits best in the roadmap",
## the insurgents' behaviour). A hostile with no rifle in a bulky heavy vest walks straight at
## the squad, ignoring cover, and at TRIGGER_M from any of them sets off the charge he wears
## (Charges: placed on him and fired at once, the same blast as a breaching charge). Shot down
## first, nothing goes off. The tells are his: no weapon, the heavy vest, the straight walk.
## Counterplay: spot him, shoot early.
##
## Host only; one per zone ("Bombers", ZoneLevel). Only factions that send them (factions.json
## "bombers": the Ashen Banner and the Valley Shura, Captain 2026-10-20; Black Ridge did before): from Pressure tier MIN_TIER, or any time the faction is hunting
## the squad (Economy.hunting), at most one every GAP_S, from an unseen spot SEND_M away
## [min, max] (EnemyResponse._unseen). All numbers Proposed.

const TICK_S := 0.5
const TRIGGER_M := 7.0
const MIN_TIER := 2
const GAP_S := 600.0
const SEND_M := [150.0, 250.0]
const CHANCE_PER_CHECK := 0.1
## How often the dice are rolled (Captain, 2026-10-20: 10% every 3 minutes or so is more balanced;
## it was every 30 s): about one bomber per half hour once the conditions hold, GAP_S apart at most.
const CHECK_S := 180.0
const KIT: Array[String] = ["plate_carrier_heavy", "assault_pack"]
## VBIEDs (wave 6f): a technical (VBIED_MODEL) with one driver drives at the nearest of the squad
## and goes off within VBIED_TRIGGER_M, a bigger blast (VBIED_BLAST_M carve and VBIED_FRAGS frag
## bursts round it). Its driver down or the truck unable to drive first, nothing. VBIED_SHARE of
## the bombers sent are VBIEDs. Proposed.
const VBIED_MODEL := "technical"  # the unarmed pickup
const VBIED_TRIGGER_M := 12.0
const VBIED_BLAST_M := 3.5
const VBIED_FRAGS := 3
const VBIED_SPEED_KMH := 55.0
const VBIED_SHARE := 0.3

## Tests and dev tools: false stops the random sends (_maybe_send); server_send and
## server_send_vbied still work, and those out still walk and go off.
static var enabled := true
## Host: bombers out: {"soldier", "squad"}; and how many went off (tests, the session log).
var out: Array[Dictionary] = []
## VBIEDs out: {"vehicle", "driver"}.
var vbieds: Array[Dictionary] = []
var detonated := 0
var _tick := 0.0
var _check := 0.0
var _last_sent := -INF
var _n := 0


func _init() -> void:
	name = "Bombers"


static func of(from: Node) -> Bombers:
	var lvl := CompoundLevel.current(from)
	return lvl.get_node_or_null(^"Bombers") as Bombers if lvl else null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK_S
		server_tick()
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_S
		_maybe_send()


## Host: every bomber out walks at the nearest of the squad; close enough, he goes off.
func server_tick() -> void:
	var targets := _targets()
	_tick_vbieds(targets)
	for b: Dictionary in out.duplicate():
		var s: Soldier = b.soldier if is_instance_valid(b.soldier) else null
		if s == null or not s.vitals.is_up():
			out.erase(b)  # stopped in time
			continue
		var near: Soldier = null
		var best := INF
		for t in targets:
			var d := t.global_position.distance_to(s.global_position)
			if d < best:
				best = d
				near = t
		if near == null:
			continue
		if best <= TRIGGER_M:
			_go_off(b)
			continue
		var route: Array[Vector3] = [near.global_position]
		if is_instance_valid(b.squad):
			(b.squad as Squad).patrol = route
			var brain := SquadAI.of(s)
			if brain:
				brain._patrol_index = 0


## Host: a bomber sets out from `at` (on the ground), walking at the squad. Returns him.
func server_send(at: Vector3) -> Soldier:
	var lvl := get_parent() as CompoundLevel
	if lvl == null:
		return null
	_n += 1
	var squad := Squad.new()
	squad.name = "Bomber%d" % _n
	squad.faction = &"hostile"
	add_child(squad)
	var spawn := {"name": "Bomber%d_1" % _n, "faction": "hostile", "pos": at,
		"loadout": KIT, "combat": 0.2, "discipline": 1.0, "guard": false, "mode": "safe"}
	spawn.merge(_dress(_n), true)
	var s: Soldier = lvl.spawn_soldier(spawn)
	if s == null:
		squad.queue_free()
		return null
	var brain := SquadAI.of(s)
	if brain:
		brain.squad = squad
	out.append({"soldier": s, "squad": squad})
	_last_sent = Soldier._now()
	print("[bombers] %s sets out from (%.0f, %.0f)" % [s.name, at.x, at.z])
	return s


## Host: a VBIED sets out from `at`, a technical with one driver. Returns the vehicle.
func server_send_vbied(at: Vector3) -> Vehicle:
	var lvl := get_parent() as CompoundLevel
	var layer := lvl.get_node_or_null(^"Vehicles") as VehicleLayer if lvl else null
	if layer == null:
		return null
	_n += 1
	var v := layer.server_spawn(VBIED_MODEL, Transform3D(Basis(), at + Vector3.UP * 0.3), "", &"hostile", "")
	if v == null:
		return null
	v.set_meta(&"no_save", true)
	var spawn := {"name": "VBIED%d_1" % _n, "faction": "hostile", "pos": at + Vector3(3, 0.1, 0),
		"loadout": ["assault_pack"], "combat": 0.2, "discipline": 1.0, "guard": false, "mode": "safe"}
	spawn.merge(_dress(_n), true)
	var driver: Soldier = lvl.spawn_soldier(spawn)
	var seat := 0
	var seats: Array = v.spec.get("seats", [])
	for i in seats.size():
		if String(seats[i].get("kind", "")) == "driver":
			seat = i
			break
	if driver == null or not v.server_enter(driver, seat):
		return v
	vbieds.append({"vehicle": v, "driver": driver})
	_last_sent = Soldier._now()
	print("[bombers] a VBIED (%s) sets out from (%.0f, %.0f)" % [VBIED_MODEL, at.x, at.z])
	return v


func _tick_vbieds(targets: Array[Soldier]) -> void:
	for b: Dictionary in vbieds.duplicate():
		var v: Vehicle = b.vehicle if is_instance_valid(b.vehicle) else null
		var d: Soldier = b.driver if is_instance_valid(b.driver) else null
		if v == null or v.wrecked or not v.can_drive() or d == null or not d.vitals.is_up() or v.seat_of(d) < 0:
			vbieds.erase(b)  # stopped in time
			continue
		var near: Soldier = null
		var best := INF
		for t in targets:
			var dist := t.global_position.distance_to(v.global_position)
			if dist < best:
				best = dist
				near = t
		if near == null:
			continue
		if best <= VBIED_TRIGGER_M:
			vbieds.erase(b)
			_vbied_off(v, d)
			continue
		v.server_drive_to(near.global_position, VBIED_SPEED_KMH)


func _vbied_off(v: Vehicle, driver: Soldier) -> void:
	detonated += 1
	var pos := v.global_position + Vector3.UP * 0.8
	print("[bombers] the VBIED goes off at (%.0f, %.0f)" % [pos.x, pos.z])
	var lvl := get_parent() as CompoundLevel
	var charges := Charges.of(self)
	if charges:
		var id := charges.server_place_at(null, Transform3D(v.global_basis, pos), v)
		if id != "":
			charges._detonate(id)
	if lvl:
		lvl.server_blast(pos, VBIED_BLAST_M)
		for k in VBIED_FRAGS:
			var a := TAU * k / VBIED_FRAGS
			Throwables.server_detonate(lvl, "frag", pos + Vector3(cos(a), 0.0, sin(a)) * 2.0)
	if is_instance_valid(driver) and driver.vitals.is_up():
		driver.vitals.server_damage(1000.0)


func _go_off(b: Dictionary) -> void:
	out.erase(b)
	var s: Soldier = b.soldier
	var charges := Charges.of(self)
	detonated += 1
	print("[bombers] %s goes off at (%.0f, %.0f)" % [s.name, s.global_position.x, s.global_position.z])
	if charges:
		var id := charges.server_place_at(null, Transform3D(s.global_basis, s.global_position + Vector3.UP * 1.2), s)
		if id != "":
			charges._detonate(id)
	if s.vitals.is_up():
		s.vitals.server_damage(1000.0)  # (whatever the blast left of him)


## Host, every CHECK_S: maybe a bomber, when the zone's enemy is a faction that sends them
## (Kits.sends_bombers) and has been pushed (tier) or is hunting the squad.
func _maybe_send() -> void:
	if not enabled:
		return
	var response := get_parent().get_node_or_null(^"EnemyResponse") as EnemyResponse
	var pressure := get_parent().get_node_or_null(^"Pressure") as Pressure
	if response == null or not Kits.sends_bombers(String(response.enemy_faction)):  # (Captain 2026-10-20: the Banner and the Shura)
		return
	var tier := pressure.tier() if pressure else 0
	if tier < MIN_TIER and not Economy.hunting(String(response.enemy_faction)):
		return
	if Soldier._now() - _last_sent < GAP_S or not out.is_empty() or not vbieds.is_empty() or randf() > CHANCE_PER_CHECK:
		return
	var targets := _targets()
	if targets.is_empty():
		return
	var centre := targets[0].global_position
	for k in 8:
		var a := randf() * TAU
		var at := response._ground(centre + Vector3(cos(a), 0.0, sin(a)) * randf_range(float(SEND_M[0]), float(SEND_M[1])))
		if response._hidden(at):
			if randf() < VBIED_SHARE:
				server_send_vbied(at)
			else:
				server_send(at)
			return


func _targets() -> Array[Soldier]:
	var all: Array[Soldier] = MapNodes.players(self)
	all.append_array(MapNodes.squad_ai(self))
	return all.filter(func(t: Soldier) -> bool: return is_instance_valid(t) and t.vitals.is_up())


## A bomber's or driver's clothes and marks: the zone's enemy's (plain clothes for the terror
## groups; Black Ridge's grey when nobody else holds the zone).
func _dress(n: int) -> Dictionary:
	var response := get_parent().get_node_or_null(^"EnemyResponse") as EnemyResponse
	var faction := String(response.enemy_faction) if response else FactionSkirmish.DEFAULT_HOLDER
	var kit_id := Kits.kit_of(faction)
	var out := Kits.dress(faction, kit_id, n * 7 + 1)
	if Kits.is_data(kit_id) and Kits.is_uniform(kit_id, n * 7 + 1):
		out["variant"] = Kits.variant(kit_id, n * 7 + 2)  # (a bomber never wears the uniform)
	return out
