class_name MortarFire
extends Node
## Mortar rounds in flight (G-25 part c, docs/static_weapons.md; the Captain, 2026-10-19: real
## ranges). A mortar (a static weapon whose kit has "mortar" data, StaticWeapons.KITS) fires a
## round at an aim point: it lands after its time of flight (FLIGHT_S by range), off the aim by the
## crew's aim error plus the tube's own dispersion (DISPERSION_PER_KM), and bursts as its HE warhead
## (data/warheads.json: Warheads.server_burst, the explosion and the shake grenades use). The tube's
## thump is heard by both sides. One node a level (made on first use); the host's. Proposed numbers.

const NODE_NAME := "MortarFire"
## Time of flight: FLIGHT_S.x at the minimum range to FLIGHT_S.y at the maximum (high-angle fire).
const FLIGHT_S := Vector2(14.0, 38.0)
## The tube's own spread, metres off for every km of range (one sigma-ish, a uniform disc).
const DISPERSION_PER_KM := 18.0
## The tube's muzzle above the gun's origin (m): where the shell is first seen (ShellArc).
const TUBE_MUZZLE_M := 1.1

var _rounds: Array[Dictionary] = []  # host: {"at": Vector3, "when": float, "warhead": StringName, "by": Node}
var _rng := RandomNumberGenerator.new()


static func of(from: Node) -> MortarFire:
	var level := CompoundLevel.current(from)
	if level == null:
		return null
	var n := level.get_node_or_null(NODE_NAME) as MortarFire
	if n == null:
		n = MortarFire.new()
		n.name = NODE_NAME
		level.add_child(n)
	return n


func _ready() -> void:
	_rng.randomize()


## The mortar data of static weapon `gun` (its kit's "mortar"), or {} for a gun that isn't one.
static func spec_of(gun: Vehicle) -> Dictionary:
	if gun == null or not StaticWeapons.KITS.has(gun.model):
		return {}
	return StaticWeapons.KITS[gun.model].get("mortar", {})


## Whether `at` is within `gun`'s range band (its kit's min_m to max_m, flat distance).
static func in_range(gun: Vehicle, at: Vector3) -> bool:
	var m := spec_of(gun)
	if m.is_empty():
		return false
	var d := Vector2(at.x - gun.global_position.x, at.z - gun.global_position.z).length()
	return d >= float(m.min_m) and d <= float(m.max_m)


## Host: `gun` fires one round at `at`, `aim_error_m` off at most on top of the tube's dispersion,
## for `by` (whose round it is: harm, the log). Returns the time of flight, or -1 when it can't
## (not a mortar, out of its range band).
func server_fire(gun: Vehicle, at: Vector3, aim_error_m: float, by: Node = null) -> float:
	if not multiplayer.is_server() or not in_range(gun, at):
		return -1.0
	var m := spec_of(gun)
	var d := Vector2(at.x - gun.global_position.x, at.z - gun.global_position.z).length()
	var share := inverse_lerp(float(m.min_m), float(m.max_m), d)
	var flight := lerpf(FLIGHT_S.x, FLIGHT_S.y, clampf(share, 0.0, 1.0))
	var off := aim_error_m + d / 1000.0 * DISPERSION_PER_KM
	var angle := _rng.randf() * TAU
	var land := at + Vector3(cos(angle), 0.0, sin(angle)) * off * sqrt(_rng.randf())
	_rounds.append({"at": land, "when": Soldier._now() + flight, "warhead": StringName(m.warhead), "by": by if by else gun})
	var lvl := CompoundLevel.current(self)
	if lvl:  # every peer sees it leave the tube, arc over in the wind and come down (ShellArc)
		lvl.server_show_shell(gun.global_position + Vector3.UP * TUBE_MUZZLE_M, lvl.ground_point(land), flight)
	Sfx.server_play(&"explosion_far", gun.global_position + Vector3.UP * 0.6)  # the tube's thump, heard far
	if by is Soldier:
		SquadAI.server_heard_shot(by as Soldier, gun.global_position, false)
	print("[mortar] %s fires at (%.0f, %.0f), %.0f m, lands in %.0f s %.0f m off the aim" % [gun.name, at.x, at.z, d, flight, land.distance_to(at)])
	return flight


func _physics_process(_delta: float) -> void:
	if _rounds.is_empty() or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var now := Soldier._now()
	for r: Dictionary in _rounds.duplicate():
		if now < float(r.when):
			continue
		_rounds.erase(r)
		_impact(r)


func _impact(r: Dictionary) -> void:
	var lvl := CompoundLevel.current(self)
	if lvl == null:
		return
	var p: Vector3 = r.at
	if lvl.has_method(&"ground_point"):
		p = lvl.call(&"ground_point", p)
	var by: Node = r.by if is_instance_valid(r.by) else null
	Warheads.server_burst(lvl, StringName(r.warhead), p + Vector3.UP * 0.15, Vector3.DOWN, null, by)
	lvl.show_explosion.rpc(p)
	Throwables._shake_players(lvl, p)
	var dig := Digging.of(lvl)
	if dig:
		dig.server_blast(p, 2.5)


## Host: rounds still in the air (tests, the log).
func in_flight() -> int:
	return _rounds.size()
