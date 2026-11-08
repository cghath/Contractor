class_name Archery
extends RefCounted
## Bows and arrows (the archery line, docs/survival_rpg.md: "faster draw, arrow recovery, bow
## making"; DayZ's and SCUM's improvised bow): the quiet weapon you make yourself. A bow is a
## melee-held weapon item (MeleeWeapons: it equips like a spear) with a "bow" stat:
##   {"draw_s": seconds to full draw, "mps": the arrow's speed at full draw, "energy_j": the blow a
##    full-draw arrow lands as (the melee wound path: a broadhead cuts, it doesn't need a bullet's
##    energy), "depth": the wound channel at full draw, "spread_deg"}.
## The owner holds fire to draw and lets go to loose (MeleeInput); the host flies the arrow on a
## ballistic arc (no drag), resolves its first hit at once like a round does, and every peer
## draws it flying for the real flight time (show_flight). What it hits:
##   a body: Vitals.server_hit as a blade's thrust where it struck (the dead's head at full draw
##     drops a walker, Vitals.undead's HEAD_ONE_HIT_J); an animal: its hit box's "on_bullet"; a
##     plate, a vehicle or the world: it stops there.
## An arrow that hit the ground is found again KEEP_WORLD of the time (a body's KEEP_BODY), more
## from archery 2 (KEEP_PERK); archery 1 draws faster (FAST_DRAW). Loosing is all but silent
## (HEARD_M, a footstep's kind for the dead). Every number is Proposed.

const ARROW := &"arrow"
const MIN_DRAW := 0.25          # let go sooner and the arrow just drops off the string
const GRAVITY := 9.8
const STEP_S := 1.0 / 60.0
const MAX_FLIGHT_S := 4.0
const HEARD_M := 6.0
const KEEP_WORLD := 0.7
const KEEP_BODY := 0.5
const KEEP_PERK := 0.2
const FAST_DRAW := 0.75
const MASK := (1 << 0) | (1 << 1) | (1 << 3) | Vehicle.LAYER  # world, hitboxes, armor, vehicles (as Ballistics)
const STUCK_S := 2.0            # a drawn arrow stays where it struck this long

## Tests: the roll for keeping an arrow (0..1; -1 rolls).
static var force_keep_roll := -1.0
## Tests: no spread, the arrow leaves along the aim (a full draw's spread is a degree either way,
## a quarter metre at 15 m: enough to pass a walker's side, F-381).
static var no_spread := false


static func is_bow(item: ItemData) -> bool:
	return MeleeWeapons.is_melee(item) and item.stats.has("bow")


static func bow_of(item: ItemData) -> Dictionary:
	return item.stats.get("bow", {}) if is_bow(item) else {}


## Seconds `s` takes to full draw with `item`.
static func draw_s(s: Soldier, item: ItemData) -> float:
	var t := float(bow_of(item).get("draw_s", 1.0))
	return t * (FAST_DRAW if s != null and Rpg.gate(s, "archery", 1) else 1.0)


## The velocity an arrow leaves `item` with at `draw` (0..1) along `dir`.
static func launch_velocity(item: ItemData, dir: Vector3, draw: float) -> Vector3:
	var b := bow_of(item)
	return dir.normalized() * float(b.get("mps", 50.0)) * lerpf(0.45, 1.0, clampf(draw, 0.0, 1.0))


## Why `s` can't loose now, or "".
static func loose_problem(s: Soldier, draw: float) -> String:
	if not is_bow(s.active_weapon()):
		return "No bow up"
	if s.inventory.count_of(ARROW) <= 0:
		return "No arrows"
	if draw < MIN_DRAW:
		return "Not drawn"
	return ""


## Host: `s` looses an arrow from `origin` along `dir` at `draw`. Returns the flight
## {"result": "body"|"animal"|"stopped"|"none", "position", "flight_s"} or {"why"}.
static func server_loose(s: Soldier, origin: Vector3, dir: Vector3, draw: float) -> Dictionary:
	var why := loose_problem(s, draw)
	if why != "":
		if not s.is_ai():
			s._client_message.rpc_id(s.owner_peer(), why)
		return {"why": why}
	var bow := s.active_weapon()
	var b := bow_of(bow)
	s.inventory.remove_one(ARROW)
	var spread := 0.0 if no_spread else deg_to_rad(float(b.get("spread_deg", 1.0)) * lerpf(1.5, 1.0, draw))
	var jitter := Basis(Vector3.UP, randf_range(-spread, spread)) * Basis(s.global_basis.x, randf_range(-spread, spread))
	var v := launch_velocity(bow, jitter * dir, draw)
	var flight := _fly(s, origin, v)
	flight["flight_s"] = float(flight.get("t", 0.0))
	var at: Vector3 = flight.position
	match String(flight.result):
		"body":
			_wound(s, flight, b, draw, v)
			_maybe_keep(s, (flight.victim as Node3D).global_position + Vector3.UP * 0.1, KEEP_BODY)
		"animal":
			_maybe_keep(s, at, KEEP_BODY)
		"stopped", "world":
			_maybe_keep(s, at - v.normalized() * 0.15, KEEP_WORLD)
	s._client_arrow.rpc(origin, v, float(flight.flight_s))
	Survival.server_noise(s, s.global_position, HEARD_M, ZombieAI.HEAR_STEP)  # the string's slap: barely a sound
	return flight


## The arc from `origin` at `v`: the first thing it meets ({"result", "position", "t", "collider",
## "victim", "part"}), or {"result": "none"} once it's flown MAX_FLIGHT_S.
static func _fly(s: Soldier, origin: Vector3, v: Vector3) -> Dictionary:
	var space := s.get_world_3d().direct_space_state
	var exclude: Array[RID] = [s.get_rid()]
	for child in s.get_children():
		if child is Area3D:
			exclude.append(child.get_rid())  # never your own hitboxes
	var gear := s.get_node_or_null(^"Gear") as GearRig
	if gear:
		exclude.append_array(gear.armor_rids())
	var t := 0.0
	var from := origin
	while t < MAX_FLIGHT_S:
		t += STEP_S
		var to := origin + v * t + Vector3.DOWN * 0.5 * GRAVITY * t * t
		var query := PhysicsRayQueryParameters3D.create(from, to, MASK, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			from = to
			continue
		var collider: Object = hit.collider
		var out := {"position": hit.position, "t": t, "collider": collider}
		if collider is Node and (collider as Node).has_meta(&"on_bullet"):
			((collider as Node).get_meta(&"on_bullet") as Callable).call(hit.position, s)  # an animal (Wildlife.server_shot)
			out["result"] = "animal"
			return out
		var vitals := Vitals.find_on(collider)
		if vitals and vitals.get_parent() is Soldier:
			out["result"] = "body"
			out["victim"] = vitals.get_parent()
			out["part"] = collider.get_meta(&"body_part", Vitals.TORSO) if collider is Node else Vitals.TORSO
			return out
		out["result"] = "stopped" if collider is VoxelArmor or Vehicle.find_on(collider) else "world"
		return out
	return {"result": "none", "position": from, "t": t}


## Host: the arrow's wound in the body it struck: a blade's thrust there (the melee wound path).
static func _wound(s: Soldier, flight: Dictionary, b: Dictionary, draw: float, v: Vector3) -> void:
	var victim := flight.victim as Soldier
	if not victim.vitals.is_up() or Children.on_harmed(victim, s):
		return  # (a child: "You don't.", call 128)
	var part: StringName = flight.part
	var share := clampf(draw, 0.0, 1.0)
	victim.vitals.server_hit(part, {"round_class": &"pistol", "position": flight.position, "direction": v.normalized(),
		"hitbox": flight.collider, "channel_depth": float(b.get("depth", 0.1)) * share, "melee": "arrow",
		"energy_j": float(b.get("energy_j", 260.0)) * share, "stays_in": true})
	ClothingWear.on_hit(victim, part)
	Rpg.xp(s, "archery", 3.0 if victim.vitals.undead else 5.0)
	SessionLog.note("archery: %s's arrow in %s's %s (draw %.2f)" % [s.log_name(), victim.log_name(), part, draw])


static func _maybe_keep(s: Soldier, at: Vector3, chance: float) -> void:
	var keep := chance + (KEEP_PERK if Rpg.gate(s, "archery", 2) else 0.0)
	var roll := force_keep_roll if force_keep_roll >= 0.0 else randf()
	if roll >= keep:
		return
	var level := CompoundLevel.current(s)
	if level:
		level.server_spawn_dropped(ARROW, 1, at)


## Every peer: an arrow drawn flying the arc from `origin` at `v` for `flight_s`, then left
## stuck there a moment.
static func show_flight(s: Soldier, origin: Vector3, v: Vector3, flight_s: float) -> void:
	var level := CompoundLevel.current(s)
	if level == null or DisplayServer.get_name() == "headless":
		return
	var arrow := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.33, 0.2)
	mesh.material = mat
	arrow.mesh = mesh
	level.add_child(arrow)
	var place := func(t: float) -> void:
		var p := origin + v * t + Vector3.DOWN * 0.5 * GRAVITY * t * t
		var vel := v + Vector3.DOWN * GRAVITY * t
		arrow.global_position = p
		if vel.length() > 0.01 and absf(vel.normalized().dot(Vector3.UP)) < 0.999:
			arrow.look_at(p + vel, Vector3.UP)
	place.call(0.0)
	var tween := arrow.create_tween()
	tween.tween_method(place, 0.0, flight_s, maxf(flight_s, 0.01))
	tween.tween_interval(STUCK_S)
	tween.tween_callback(arrow.queue_free)
