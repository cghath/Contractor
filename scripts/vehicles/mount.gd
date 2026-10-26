class_name Mount
extends Vehicle
## A mount (Contractor: Fallen, docs/survival_mounts.md; calls 31, 35): a horse, a bicycle or a
## horse-drawn cart. A Vehicle (kind "mount", numbers in data/mounts.json, model MountArt), so its
## seats, getting on and off (V, the seat's menu), the seated views (VehicleCamera: first person at
## the saddle with the horse's head ahead, B for third person), the packs (the cargo hold and its
## Left Ctrl point), the squad's driving (VehicleAI, SquadDrivers' mount up and column), the
## replication and the zone save (VehicleLayer) are the vehicles'. What's its own:
## - the drive (_drive_step): no wheels or engine; a speed it eases toward by gait (horse, cart)
##   or by the ground (bicycle: fast on asphalt, slow on grass, useless cross-country), turning on
##   the spot (a horse) or only rolling (a bike), following the ground under it;
## - gaits (horse, cart): walk, trot, gallop on the pace keys (the wheel walk/trot, Shift gallops;
##   the AI as fast as it may); stamina drains at a gallop, comes back walking or standing; a
##   hungry or thirsty horse won't gallop (HUNGRY_BELOW);
## - needs (horse): `feed` and `water` (0-100, a day's need each: FEED_DAY, WATER_DAY), fed oats
##   (horse_feed) and watered from bottles or open water, grazing where it stands loose; starved or
##   parched for STARVE_DAYS / THIRST_DAYS it dies;
## - spooking (horse): a shot within SPOOK_M (Survival.server_noise, through Mounts.on_noise) or the
##   dead within SPOOK_M: it bolts BOLT_S away from it and may throw a rider of low fieldcraft
##   (Rpg); its own rider's shot only startles it; tied, it pulls at the rope instead; minded by a
##   companion ("Stay with the horses", Mounts.server_stay), it spooks less;
## - noise: hooves heard HOOF_M by gait (20-60 m), a cart loud on hard ground; a bike is silent;
## - the dead bite a horse within BITE_M (it has HP of its own, not the vehicles' zones; a dead
##   horse lies where it fell, its packs still on it);
## - wild horses (farms, Mounts) wander and are caught with a rope and fieldcraft 1 (CATCH_S close
##   by); tied, a horse stays; a cart takes a horse in its shafts (hitch) and is its stash on wheels;
## - a bicycle falls on a hard hit (CRASH_MS into something), throwing its rider; a fall can puncture
##   a tyre (a bicycle_tube fixes it);
## - from the saddle the rider fires a sidearm or swings a one-handed weapon (ffv_seat: the sidearm
##   slot), never a long gun.
## The menu: a Mount is InteractionMenu's "mount" target kind (interaction_actions). Host
## authoritative; the state every peer needs rides net_state["mount"]. Numbers are Proposed.

const KIND := "mount"
const HORSE := "horse"
const BICYCLE := "bicycle"
const CART := "cart"
const GROUP_MOUNTS := &"mounts"

enum Gait { WALK, TROT, GALLOP }
const GAIT_NAMES: Array[String] = ["Walk", "Trot", "Gallop"]

## The ground under it -> its share of the speed (Proposed).
const SURFACE := {
	"horse": {"asphalt": 0.9, "dirt": 1.0, "grass": 1.0, "sand": 0.75, "mud": 0.5, "rock": 0.6, "snow": 0.6, "rubble": 0.55},
	"bicycle": {"asphalt": 1.0, "dirt": 0.8, "grass": 0.4, "sand": 0.2, "mud": 0.12, "rock": 0.25, "snow": 0.2, "rubble": 0.25},
	"cart": {"asphalt": 1.0, "dirt": 1.0, "grass": 0.8, "sand": 0.5, "mud": 0.35, "rock": 0.5, "snow": 0.5, "rubble": 0.4},
}
## Hard ground: a cart rattles loud on it; hooves ring a little louder.
const HARD_GROUND: Array[String] = ["asphalt", "dirt", "rock", "rubble"]
## The drive (m/s2, m/s, 1/s).
const COAST_DECEL := 1.5
const BRAKE_DECEL := 5.0
const REVERSE_MS := 0.8
const GROUND_FOLLOW := 10.0
const STILL_MS := 0.3
## Stamina (0-100) per second by gait, and what a gallop needs.
const STAMINA_GALLOP_S := 1.1
const STAMINA_TROT_S := 0.06
const STAMINA_WALK_S := -0.6
const STAMINA_STILL_S := -1.2
const GALLOP_MIN_STAMINA := 8.0
## Needs (per world day, Survival.DAY_MIN real minutes): a day's feed and water each 100.
const FEED_DAY := 100.0
const WATER_DAY := 100.0
const GRAZE_FEED_DAY := 60.0
const GRAZE_WATER_DAY := 30.0
const HUNGRY_BELOW := 25.0
const STARVE_DAYS := 3.0
const THIRST_DAYS := 2.0
const FEED_ITEM := &"horse_feed"
const FEED_PER_SACK := 50.0
const WATER_PER_L := 4.0
const WATER_ITEMS: Array[StringName] = [&"water_bottle", &"dirty_water_bottle"]
## Open water this close (m) waters it full.
const WATER_REACH_M := 8.0
## Spooking.
const SPOOK_M := 15.0
const BOLT_S := Vector2(2.5, 4.5)
const SPOOK_COOLDOWN_S := 6.0
const DEAD_SPOOK_CHANCE := 0.5
const MINDED_CALM := 0.6         # a minded horse shrugs off this share of what would spook it
const OWN_SHOT_BOLT := 0.25      # its own rider's shot bolts it this often (under CALM_FIELDCRAFT)
const CALM_FIELDCRAFT := 3       # fieldcraft 3 ("horses", RpgLines): its own rider's shots don't bolt it
const THROW_FIELDCRAFT := 2      # a bolt from a shot throws a rider below this fieldcraft
const DEAD_THROW_FIELDCRAFT := 1 # a bolt from the dead throws a rider below this
const AI_FIELDCRAFT := 2         # companions ride as if at this fieldcraft (Rpg reads 0 for the AI)
const THROW_FALL_M := 1.4
## Noise: hooves heard this far by gait (m); a cart on hard ground by gait, half on soft.
const HOOF_M: Array[float] = [20.0, 35.0, 60.0]
const CART_M: Array[float] = [30.0, 45.0, 45.0]
const SOFT_MULT := 0.5
const NOISE_S := 0.6
## The dead at a horse.
const BITE_M := 1.9
const BITE_S := 1.3
const BITE_HP := 6.0
## Catching a wild horse.
const ROPE := &"rope"
const CATCH_S := 4.0
const CATCH_M := 3.5
const CATCH_FIELDCRAFT := 1
const CATCH_XP := 12.0
## Wild horses wander about their spot.
const WANDER_M := 12.0
const WANDER_PAUSE_S := Vector2(6.0, 18.0)
## A cart takes a horse within this of its shafts.
const HITCH_M := 6.0
## A bicycle meeting something this fast (m/s) falls; a fall punctures a tyre this often.
const CRASH_MS := 5.0
const FLAT_CHANCE := 0.5
const TUBE := &"bicycle_tube"
## Reach for the menu's actions (m from its centre).
const REACH_M := 4.0
const TICK_S := 1.0

## Host state (saved; every peer reads it through mount_state()).
var mount_type := HORSE
var tamed := true
var tied := false
var feed := 100.0
var water := 100.0
var stamina := 100.0
var health := 100.0
var starving_days := 0.0
var thirst_days := 0.0
var fallen := false
var flat := false
var home := Vector3.ZERO
var spooked_s := 0.0
var bolt_dir := Vector3.FORWARD
var minder: Soldier = null
var mspec: Dictionary = {}
var _hitch_id := ""             # a cart: its horse's vehicle_id; a horse: its cart's
var _partner: Mount = null      # resolved hitch partner
var _gait_choice := Gait.TROT   # the player rider's (request_gait)
var _gait := Gait.WALK          # what it's doing now (by speed)
var _spooked_at := -100.0
var _tick_left := 0.0
var _noise_left := 0.0
var _bites := {}                # zombie instance id -> next bite time
var _catch := {}                # {"actor": Soldier, "until": time}
var _wander_to: Variant = null
var _wander_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _seen_dead := false
## Host: how far its last step's noise carried before the weather (m; tests and the HUD).
var last_noise_m := 0.0
## Local (the rider's peer): the wheel's gait and what was last sent.
var _local_gait := Gait.TROT
var _sent_gait := -1
var _bob_t := 0.0


## Whether `model` is a mount's (data/mounts.json, kind "mount").
static func is_mount_model(model: String) -> bool:
	return String(VehicleSpecs.spec(model).get("kind", "")) == KIND


## A new mount of `model`, ready for the tree (VehicleLayer._make).
static func make(p_model: String, p_scheme := "", p_faction := &"player", id := "") -> Mount:
	var m := Mount.new()
	m.setup(p_model, p_scheme, p_faction, id)
	return m


func setup(p_model: String, p_scheme := "", p_faction := &"player", id := "") -> void:
	super.setup(p_model, p_scheme, p_faction, id)
	mspec = spec.get("mount", {})
	mount_type = String(mspec.get("type", HORSE))
	health = float(mspec.get("hp", 100.0))
	tamed = mount_type != HORSE  # a horse is wild until caught (Mounts.server_spawn tames)
	gravity_scale = 0.0
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	angular_damp = 4.0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	physics_material_override = mat
	_rng.seed = hash(id) if id != "" else randi()
	_wander_wait = _rng.randf_range(WANDER_PAUSE_S.x, WANDER_PAUSE_S.y)


func _ready() -> void:
	super._ready()
	add_to_group(GROUP_MOUNTS)
	add_to_group(InteractionMenu.INTERACTABLES)
	if multiplayer.is_server() and home == Vector3.ZERO:
		home = global_position
	if hull and is_instance_valid(hull.art):
		for c in hull.art.get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).visibility_range_end = MountArt.LOD_M
		add_child(MountArt.far_lod(model, scheme))


# --- Queries (every peer) -------------------------------------------------------------------

## The shared state: the host's own, a client's from net_state.
func mount_state() -> Dictionary:
	if multiplayer.is_server() or not net_state.has("mount"):
		return _state_out()
	return net_state.mount


func _state_out() -> Dictionary:
	return {"type": mount_type, "tamed": tamed, "tied": tied, "feed": snappedf(feed, 0.1), "water": snappedf(water, 0.1),
		"stamina": snappedf(stamina, 0.1), "hp": snappedf(health, 0.1), "gait": _gait, "spooked": spooked_s > 0.0,
		"fallen": fallen, "flat": flat, "hitch": _hitch_id, "minded": is_instance_valid(minder)}


func rider() -> Soldier:
	return driver()


func is_horse() -> bool:
	return mount_type == HORSE


func is_dead() -> bool:
	return wrecked


## The horse that pulls it: a horse itself, a cart's hitched horse, else null.
func horse() -> Mount:
	if mount_type == HORSE:
		return self
	if mount_type == CART and not is_instance_valid(_partner) and not multiplayer.is_server() and is_inside_tree():
		var id := String(mount_state().get("hitch", ""))  # a client: the horse the host hitched
		var layer := get_parent() as VehicleLayer
		var found: Vehicle = layer.find(id) if layer and id != "" else null
		_partner = found as Mount
	if mount_type == CART and is_instance_valid(_partner):
		return _partner
	return null


## A cart's hitched horse, or a horse's cart.
func hitched() -> Mount:
	return _partner if is_instance_valid(_partner) else null


func gait() -> int:
	return int(mount_state().get("gait", Gait.WALK))


func gait_name() -> String:
	return GAIT_NAMES[clampi(gait(), 0, 2)] if mount_type != BICYCLE else ""


func engine_running() -> bool:
	return false  # no engine (Sfx's engine sound, thermal heat)


func can_drive() -> bool:
	if wrecked:
		return false
	match mount_type:
		HORSE:
			return tamed and not tied and not is_instance_valid(_partner)
		BICYCLE:
			return not fallen
		CART:
			var h := horse()
			return h != null and not h.wrecked and not h.tied
	return false


## Top speed now (m/s): a horse's gallop (or what it may do now), a bike's on asphalt, a cart's trot.
func top_speed(reverse := false) -> float:
	if reverse:
		return REVERSE_MS
	return gait_speed(allowed_gait()) if mount_type != BICYCLE else gait_speed(Gait.GALLOP)


## The speed of gait `g` on good ground (m/s).
func gait_speed(g: int) -> float:
	if mount_type == BICYCLE:
		return float(mspec.get("top_ms", 7.0)) * (0.5 if flat else 1.0)
	var gaits: Array = mspec.get("gaits_ms", [1.7, 4.2, 12.0])
	return float(gaits[clampi(g, 0, gaits.size() - 1)]) * VehicleWear.hoof_mult(self)  # worn hooves (survival wear)


## The fastest gait the horse will go now: no gallop hungry, thirsty or blown.
func allowed_gait() -> int:
	var h := horse()
	if mount_type == BICYCLE:
		return Gait.GALLOP
	if h == null:
		return Gait.WALK
	if h.feed < HUNGRY_BELOW or h.water < HUNGRY_BELOW or h.stamina < GALLOP_MIN_STAMINA:
		return Gait.TROT
	return Gait.GALLOP


## The ground's share of the speed at its feet.
func surface_mult(ground: StringName = &"") -> float:
	if ground == &"":
		ground = ground_here()
	return float((SURFACE.get(mount_type, {}) as Dictionary).get(String(ground), 0.8))


func ground_here() -> StringName:
	return VehicleDrive.ground_at(level(), global_position) if is_inside_tree() else VehicleDrive.DEFAULT_GROUND


## Counts of the mounts in `from`'s level (the world lane's groups read it: riders seen):
## {"horse", "bicycle", "cart" (alive and whole), "ridden", "wild"}.
static func counts_in_zone(from: Node) -> Dictionary:
	var out := {"horse": 0, "bicycle": 0, "cart": 0, "ridden": 0, "wild": 0}
	if from == null or not from.is_inside_tree():
		return out
	for n in from.get_tree().get_nodes_in_group(GROUP_MOUNTS):
		var m := n as Mount
		if m == null or m.is_queued_for_deletion() or m.wrecked:
			continue
		out[m.mount_type] = int(out.get(m.mount_type, 0)) + 1
		if m.rider() != null:
			out.ridden = int(out.ridden) + 1
		if m.mount_type == HORSE and not m.tamed:
			out.wild = int(out.wild) + 1
	return out


# --- Seats ------------------------------------------------------------------------------------

## Why nobody can get on now ("" if they can).
func ride_block() -> String:
	if wrecked:
		return "It's dead" if mount_type == HORSE else "It's wrecked"
	match mount_type:
		HORSE:
			if not tamed:
				return "It's wild: catch it first (rope)"
			if tied:
				return "It's tied: untie it first"
			if is_instance_valid(_partner):
				return "It's in the cart's shafts"
			if spooked_s > 0.0:
				return "It's bolting"
		BICYCLE:
			if fallen:
				return "It's lying on its side: stand it up"
	return ""


func server_enter(soldier: Node, index := -1) -> bool:
	var s := soldier as Soldier
	if s and s.vitals.is_up():
		var why := ride_block()
		if why != "":
			_tell(s, why)
			return false
	return super.server_enter(soldier, index)


## Fire from the saddle: a one-handed weapon (the sidearm slot: a pistol, a knife, a machete),
## never a long gun.
func ffv_seat(s: Soldier) -> bool:
	if s == null or wrecked or seat_of(s) < 0:
		return false
	var w := s.active_weapon()
	return w != null and w.slot == &"sidearm"


func ffv_ok(s: Soldier, direction: Vector3, origin: Variant = null) -> bool:
	if not ffv_seat(s):
		return false
	var from: Vector3 = origin if origin != null else s.camera.global_position
	return ffv_clear(from, direction)


# --- The drive (host) ---------------------------------------------------------------------------

func _drive_step(delta: float) -> void:
	if mount_type == HORSE and is_instance_valid(_partner):
		return  # in the shafts: the cart moves it
	var input := _mount_input()
	var throttle := clampf(float(input.throttle), -1.0, 1.0)
	var steer := clampf(float(input.steer), -1.0, 1.0)
	var brake := bool(input.brake)
	if not can_drive() and not bool(input.get("bolt", false)) and not bool(input.get("wild", false)):
		throttle = 0.0
		steer = 0.0
		brake = true
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD
	var speed := linear_velocity.dot(fwd)
	var cap := gait_speed(mini(int(input.choice), allowed_gait())) * surface_mult()
	if mount_type == HORSE:
		cap *= lerpf(0.5, 1.0, clampf(health / float(mspec.get("hp", 100.0)), 0.0, 1.0))
	var accel := float(mspec.get("accel_ms2", 2.0))
	if throttle > 0.01:
		speed = move_toward(speed, cap, (accel * maxf(throttle, 0.3) if speed < cap else BRAKE_DECEL) * delta)
	elif throttle < -0.01:
		speed = move_toward(speed, -REVERSE_MS, accel * delta)
	else:
		speed = move_toward(speed, 0.0, (BRAKE_DECEL if brake else COAST_DECEL) * delta)
	var turn := float(mspec.get("turn_rads", 1.2))
	if mount_type == BICYCLE:
		turn *= clampf(absf(speed) / 2.0, 0.0, 1.0)  # it only turns rolling
	elif mount_type == HORSE and absf(speed) > gait_speed(Gait.TROT) + 1.0:
		turn *= 0.7
	var vy := _ground_vy(delta)
	if mount_type == BICYCLE and speed > CRASH_MS and _hard_ahead(fwd, speed, delta):
		server_crash()
		speed = 0.0
	linear_velocity = fwd * speed + Vector3.UP * vy
	angular_velocity = Vector3(0.0, -steer * turn, 0.0)
	_gait = _gait_of(absf(speed))


## What drives it this step: {"throttle", "steer", "brake", "choice" (the gait wanted), "bolt", "wild"}.
func _mount_input() -> Dictionary:
	var h := horse()
	if h and h.spooked_s > 0.0 and not h.tied:
		var to := h.bolt_dir
		var fwd := -global_basis.z
		var ang := rad_to_deg(Vector2(fwd.x, fwd.z).normalized().angle_to(Vector2(to.x, to.z).normalized()))
		return {"throttle": 1.0, "steer": clampf(ang / 45.0, -1.0, 1.0), "brake": false, "choice": Gait.GALLOP, "bolt": true}
	if tied or (mount_type == HORSE and is_instance_valid(_catch.get("actor"))):
		return {"throttle": 0.0, "steer": 0.0, "brake": true, "choice": Gait.WALK}  # (still while being caught)
	if mount_type == HORSE and not tamed:
		return _wander_input()
	var input := _current_input()
	var d := driver()
	var choice := _gait_choice if d and not d.is_ai() else Gait.GALLOP
	return {"throttle": float(input.get("throttle", 0.0)), "steer": float(input.get("steer", 0.0)), "brake": bool(input.get("brake", true)), "choice": choice}


## A wild horse grazes about its spot, walking a little now and then.
func _wander_input() -> Dictionary:
	var still := {"throttle": 0.0, "steer": 0.0, "brake": true, "choice": Gait.WALK, "wild": true}
	if _wander_to == null:
		return still
	var to: Vector3 = (_wander_to as Vector3) - global_position
	to.y = 0.0
	if to.length() < 1.5:
		_wander_to = null
		return still
	var fwd := -global_basis.z
	var ang := rad_to_deg(Vector2(fwd.x, fwd.z).normalized().angle_to(Vector2(to.x, to.z).normalized()))
	return {"throttle": 0.5 if absf(ang) < 60.0 else 0.0, "steer": clampf(ang / 45.0, -1.0, 1.0), "brake": false, "choice": Gait.WALK, "wild": true}


## The vertical speed that keeps it on the ground under it (the world and other vehicles).
func _ground_vy(delta: float) -> float:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]
	if is_instance_valid(_partner):
		exclude.append(_partner.get_rid())
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.2, global_position + Vector3.DOWN * 3.0, GROUND_MASK, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return linear_velocity.y - 9.8 * delta
	return clampf(((hit.position as Vector3).y - global_position.y) * GROUND_FOLLOW, -8.0, 6.0)


## Something hard right ahead at this speed (a wall, a car, a steep bank): a bike's crash.
func _hard_ahead(fwd: Vector3, speed: float, delta: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.6
	var exclude: Array[RID] = [get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * (speed * delta * 2.0 + 0.95), GROUND_MASK, exclude)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit.normal as Vector3).y < 0.5


func _gait_of(speed: float) -> int:
	if mount_type == BICYCLE or speed < STILL_MS:
		return Gait.WALK
	if speed <= gait_speed(Gait.WALK) + 0.4:
		return Gait.WALK
	if speed <= gait_speed(Gait.TROT) + 0.8:
		return Gait.TROT
	return Gait.GALLOP


func forward_speed() -> float:
	if multiplayer.is_server():
		var fwd := -global_basis.z
		fwd.y = 0.0
		return linear_velocity.dot(fwd.normalized()) if fwd.length_squared() > 0.0001 else 0.0
	return float(net_state.get("speed", 0.0))


# --- The host's steps -----------------------------------------------------------------------------

func _server_step(delta: float) -> void:
	super._server_step(delta)
	if is_instance_valid(_partner) and mount_type == CART:
		var off := VehicleSpecs.vec(mspec.get("hitch"), Vector3(0, 0, -2.6))
		_partner.global_transform = global_transform * Transform3D(Basis(), off)
		_partner._gait = _gait
	if wrecked:
		return
	_step_stamina(delta)
	if spooked_s > 0.0:
		spooked_s = maxf(spooked_s - delta, 0.0)
		if spooked_s <= 0.0:
			_publish_state(true)
	_step_catch()
	_noise_left -= delta
	if _noise_left <= 0.0:
		_noise_left = NOISE_S
		_make_noise()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = TICK_S
		_mount_tick(TICK_S)


func _step_stamina(delta: float) -> void:
	if mount_type != HORSE:
		return
	var speed := absf(forward_speed()) if not is_instance_valid(_partner) else absf(_partner.forward_speed())
	var rate := STAMINA_STILL_S
	if speed >= STILL_MS:
		rate = [STAMINA_WALK_S, STAMINA_TROT_S, STAMINA_GALLOP_S][_gait_of(speed)]
		if is_instance_valid(_partner):
			rate = maxf(rate, STAMINA_TROT_S) * 1.5  # pulling a loaded cart
	stamina = clampf(stamina - rate * delta, 0.0, 100.0)


## Once a TICK_S (host): needs, the dead about it, a wild horse's wandering, a minder, the hitch.
func _mount_tick(dt: float) -> void:
	_resolve_hitch()
	if is_instance_valid(minder) and (not minder.vitals.is_up() or not tied):
		minder = null  # (Mounts also stands him down when he's told otherwise)
	if mount_type == HORSE:
		var days := dt / (Survival.DAY_MIN * 60.0)
		var loose := rider() == null and absf(forward_speed()) < STILL_MS and not is_instance_valid(_partner)
		step_needs(days, loose and String(ground_here()) in ["grass", "dirt", "mud", "snow"])
		if wrecked:
			return
		_dead_about()
		if not tamed and _wander_to == null:
			_wander_wait -= dt
			if _wander_wait <= 0.0:
				_wander_wait = _rng.randf_range(WANDER_PAUSE_S.x, WANDER_PAUSE_S.y)
				var a := _rng.randf() * TAU
				_wander_to = home + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(2.0, WANDER_M)
	_publish_state(true)


## Feed and water used over `days` (world days), grass grazed when `grazing`; hungry, thirsty and
## at last dead. Host; the tests call it directly.
func step_needs(days: float, grazing: bool) -> void:
	if wrecked or mount_type != HORSE or days <= 0.0:
		return
	feed = clampf(feed - FEED_DAY * days + (GRAZE_FEED_DAY * days if grazing else 0.0), 0.0, 100.0)
	water = clampf(water - WATER_DAY * days + (GRAZE_WATER_DAY * days if grazing else 0.0), 0.0, 100.0)
	starving_days = starving_days + days if feed <= 0.0 else 0.0
	thirst_days = thirst_days + days if water <= 0.0 else 0.0
	if starving_days >= STARVE_DAYS:
		server_die("starved")
	elif thirst_days >= THIRST_DAYS:
		server_die("died of thirst")


## The dead about a horse: spooking it, and biting it within reach.
func _dead_about() -> void:
	var lvl := level()
	if lvl == null or not Survival.running:
		return
	var now := Soldier._now()
	var nearest: Soldier = null
	for z: Soldier in Survival.zombies(lvl):
		var d := z.global_position.distance_to(global_position)
		if d > SPOOK_M:
			continue
		if nearest == null or d < nearest.global_position.distance_to(global_position):
			nearest = z
		var flat_d := Vector2(z.global_position.x - global_position.x, z.global_position.z - global_position.z).length()
		if flat_d <= BITE_M and absf(z.global_position.y - global_position.y) < 2.0 and now >= float(_bites.get(z.get_instance_id(), 0.0)):
			_bites[z.get_instance_id()] = now + BITE_S
			server_hurt(BITE_HP, "bitten")
			if wrecked:
				return
	_seen_dead = nearest != null
	if nearest and _rng.randf() < DEAD_SPOOK_CHANCE:
		server_spook(nearest.global_position, "dead", nearest)


## Hooves on the ground (Survival.server_noise): the dead hear a horse 20-60 m off by its gait, a
## cart further on hard ground; a bicycle not at all.
func _make_noise() -> void:
	if mount_type == BICYCLE or not Survival.running:
		return
	if mount_type == HORSE and is_instance_valid(_partner):
		return  # the cart makes the noise for both
	var speed := absf(forward_speed())
	if speed < STILL_MS:
		return
	var g := _gait_of(speed)
	if rider() == null and mount_type == HORSE:
		last_noise_m = 0.0
		return  # a loose horse (grazing, wandering, bolting off alone) isn't heard; only a ridden one's hooves
	var hard := String(ground_here()) in HARD_GROUND
	var radius: float = (CART_M[g] if mount_type == CART else HOOF_M[g]) * (1.0 if hard or mount_type == HORSE else SOFT_MULT)
	last_noise_m = radius
	var src: Node = rider() if rider() and not rider().is_ai() else self
	Survival.server_noise(src, global_position, radius * DayNight.hearing_x(), ZombieAI.HEAR_RUN if g == Gait.GALLOP else ZombieAI.HEAR_STEP)


## Host: something frightening at `from` ("shot", "dead", "bitten"; `source` who): it bolts away
## BOLT_S, may throw its rider. Its own rider's shot only startles it; tied, it can't bolt; a
## minded horse shrugs most of it off. A cart's horse bolts with the cart.
func server_spook(from: Vector3, why: String, source: Node = null) -> bool:
	if not multiplayer.is_server() or wrecked or mount_type == BICYCLE:
		return false
	if mount_type == CART:
		return _partner.server_spook(from, why, source) if is_instance_valid(_partner) else false
	var now := Soldier._now()
	if now - _spooked_at < SPOOK_COOLDOWN_S or spooked_s > 0.0:
		return false
	var r := rider()
	var fc := fieldcraft_of(r)
	if why == "shot" and source != null and source == r:
		if fc >= CALM_FIELDCRAFT or _rng.randf() > OWN_SHOT_BOLT:
			return false  # it startles, and the rider holds it
	if is_instance_valid(minder) and minder.global_position.distance_to(global_position) < 8.0 and _rng.randf() < MINDED_CALM:
		return false
	_spooked_at = now
	if tied:
		return false  # it pulls at the rope and stamps
	spooked_s = _rng.randf_range(BOLT_S.x, BOLT_S.y)
	var away := global_position - from
	away.y = 0.0
	bolt_dir = away.normalized() if away.length_squared() > 0.01 else Vector3(cos(_rng.randf() * TAU), 0.0, sin(_rng.randf() * TAU))
	_catch.clear()
	if r and source != r and fc < (THROW_FIELDCRAFT if why == "shot" else DEAD_THROW_FIELDCRAFT):
		throw_rider(r)
	elif r:
		_tell(r, "The horse bolts!")
	_publish_state(true)
	return true


## A rider's fieldcraft (Rpg; companions ride as AI_FIELDCRAFT).
static func fieldcraft_of(s: Soldier) -> int:
	if s == null:
		return 0
	if s.is_ai():
		return AI_FIELDCRAFT
	return Rpg.level(s, "fieldcraft")


## Host: `r` is thrown off (a bolt, a crash): out beside it and a fall.
func throw_rider(r: Soldier) -> void:
	if r == null or seat_of(r) < 0:
		return
	server_exit(r)
	r.vitals.server_fall(THROW_FALL_M)
	_tell(r, "Thrown!")


## Host: hurt (a bite, a round, a blast); dead at 0.
func server_hurt(amount: float, why := "") -> void:
	if not multiplayer.is_server() or wrecked or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if mount_type == HORSE and why == "bitten":
		Survival.server_noise(self, global_position, 60.0, ZombieAI.HEAR_SHOT * 0.6)  # it screams
		server_spook(global_position - bolt_dir, "bitten")
	if health <= 0.0:
		server_die(why)
	else:
		_publish_state(true)


## Host: dead (a horse) or wrecked (a bike, a cart): riders off, unhitched, lying where it is; its
## packs stay on it (the cargo point still opens them).
func server_die(why := "") -> void:
	if not multiplayer.is_server() or wrecked:
		return
	health = 0.0
	for s: Soldier in occupants():
		if seat_of(s) >= 0:
			server_exit(s)
	server_unhitch()
	wrecked = true
	spooked_s = 0.0
	tied = false
	minder = null
	linear_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if is_instance_valid(ai):
		ai.stop()
	set_meta(&"died_of", why)
	_publish_state(true)
	became_wreck.emit(self)


## Host: a hit from a round or a blast (Ballistics, launchers): a horse takes it in its HP and
## bolts; a cart's planks soak a little; a bicycle's frame lets rounds by.
func server_take_hit(hit: Dictionary) -> Dictionary:
	var pos: Vector3 = hit.get("position", global_position)
	var energy := float(hit.get("energy_j", 0.0))
	var blast := float(hit.get("blast_kg", 0.0))
	var out := {"stopped": false, "zone": ZONE_HULL, "penetrated": true, "missed": mount_type == BICYCLE, "position": pos,
		"energy_left": energy * 0.5, "lost_j": energy * 0.5}
	if not multiplayer.is_server() or wrecked or mount_type == BICYCLE and blast <= 0.0:
		return out
	var dmg := energy / 60.0 + blast * 60.0 + (40.0 if StringName(hit.get("kind", KINETIC)) != KINETIC and blast <= 0.0 else 0.0)
	if mount_type == CART:
		dmg *= 0.4
	server_hurt(dmg, "shot")
	if mount_type == HORSE and not wrecked:
		server_spook(pos, "shot", hit.get("shooter") as Node)
	return out


func server_explosion(pos: Vector3, _kind: String = "") -> void:
	var d := pos.distance_to(global_position)
	server_hurt(maxf(120.0 - d * 30.0, 0.0), "blast")
	if mount_type == BICYCLE and d < 3.0:
		server_crash()


## Host: a bicycle meets something hard: it falls, its rider is thrown, a tyre may go.
func server_crash() -> void:
	if not multiplayer.is_server() or mount_type != BICYCLE or fallen:
		return
	var r := rider()
	fallen = true
	if _rng.randf() < FLAT_CHANCE:
		flat = true
	if r:
		throw_rider(r)
	linear_velocity = Vector3.ZERO
	_publish_state(true)


# --- Catching, tying, hitching (host) -------------------------------------------------------------

func _step_catch() -> void:
	if _catch.is_empty():
		return
	var av: Variant = _catch.get("actor")
	if not is_instance_valid(av):
		_catch.clear()
		return
	var a := av as Soldier
	if a == null or not a.vitals.is_up() or a.global_position.distance_to(global_position) > CATCH_M or spooked_s > 0.0:
		if is_instance_valid(a):
			_tell(a, "It shied away")
		_catch.clear()
		return
	if Soldier._now() >= float(_catch.until):
		_catch.clear()
		if a.inventory.count_of(ROPE) <= 0:
			_tell(a, "No rope")
			return
		a.inventory.remove_one(ROPE)
		tamed = true
		home = global_position
		_wander_to = null
		Rpg.xp(a, "fieldcraft", CATCH_XP)
		_tell(a, "Caught: the horse is yours (Left Ctrl on it to ride, tie or feed it)")
		_publish_state(true)


## Host: the cart takes `h` in its shafts (or the nearest free horse within HITCH_M). "" or why not.
func server_hitch(h: Mount = null) -> String:
	if mount_type != CART or wrecked:
		return "Not a cart"
	if is_instance_valid(_partner):
		return "A horse is already in the shafts"
	if h == null:
		var best := INF
		for n in get_tree().get_nodes_in_group(GROUP_MOUNTS):
			var m := n as Mount
			if m and m.mount_type == HORSE and m.tamed and not m.wrecked and m.rider() == null and not is_instance_valid(m._partner):
				var d := m.global_position.distance_to(global_transform * VehicleSpecs.vec(mspec.get("hitch"), Vector3(0, 0, -2.6)))
				if d < HITCH_M and d < best:
					best = d
					h = m
	if h == null:
		return "No horse of ours by the shafts"
	if not h.tamed or h.wrecked or h.rider() != null:
		return "That horse can't be hitched"
	h.tied = false
	h.minder = null
	_attach(h)
	_publish_state(true)
	h._publish_state(true)
	return ""


func _attach(h: Mount) -> void:
	_partner = h
	h._partner = self
	_hitch_id = h.vehicle_id
	h._hitch_id = vehicle_id
	h.linear_velocity = Vector3.ZERO
	h.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	h.freeze = true
	add_collision_exception_with(h)
	h.add_collision_exception_with(self)


## Host: the horse out of the shafts (it stands where it was).
func server_unhitch() -> void:
	var h := _partner
	if not is_instance_valid(h):
		_partner = null
		_hitch_id = ""
		return
	_partner = null
	_hitch_id = ""
	h._partner = null
	h._hitch_id = ""
	remove_collision_exception_with(h)
	h.remove_collision_exception_with(self)
	if not h.wrecked:
		h.freeze = false
	h._publish_state(true)
	_publish_state(true)


## A saved hitch comes back once both are in the zone.
func _resolve_hitch() -> void:
	if _hitch_id == "" or is_instance_valid(_partner) or mount_type != CART:
		return
	var layer := get_parent() as VehicleLayer
	var found: Vehicle = layer.find(_hitch_id) if layer else null
	var h := found as Mount
	if h and not h.wrecked:
		_attach(h)
	elif h == null:
		return
	else:
		_hitch_id = ""


# --- The menu (InteractionMenu's "mount" kind) ------------------------------------------------------

func action_point() -> Vector3:
	var size := VehicleArt.size_m(model)
	return global_position + Vector3.UP * minf(size.y * 0.7, 1.4)


## Its entries for `actor` (InteractionMenu: {"id", "label", "disabled", "call"}); each sends the
## host request_action, which checks it again.
func interaction_actions(actor: Soldier) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null or seat_of(actor) >= 0:
		return out
	var st := mount_state()
	var dead := wrecked
	var t := String(st.get("type", mount_type))
	if dead:
		out.append(_entry(&"check", "Check", ""))
		return out
	if t == HORSE and not bool(st.get("tamed", true)):
		var why := ""
		if actor.inventory.count_of(ROPE) <= 0:
			why = "Needs a rope"
		elif not Rpg.gate(actor, "fieldcraft", CATCH_FIELDCRAFT):
			why = "Needs fieldcraft %d" % CATCH_FIELDCRAFT
		out.append(_entry(&"catch", "Catch it (rope, %d s)" % int(CATCH_S), why))
		out.append(_entry(&"feed", "Feed (oats)", "" if actor.inventory.count_of(FEED_ITEM) > 0 else "No oats"))
		return out
	match t:
		HORSE:
			out.append(_entry(&"ride", "Ride", _block_text(actor)))
			out.append(_entry(&"feed", "Feed (oats)", "" if actor.inventory.count_of(FEED_ITEM) > 0 or _pack_count(FEED_ITEM) > 0 else "No oats"))
			out.append(_entry(&"water", "Water it", "" if _water_near() or _water_items(actor) > 0 or _pack_count(&"water_bottle") > 0 else "No water"))
			if bool(st.get("tied", false)):
				out.append(_entry(&"untie", "Untie", ""))
				out.append(_entry(&"stay", "Stay with the horses (a companion)", ""))
			else:
				out.append(_entry(&"tie", "Tie it here", "" if String(st.get("hitch", "")) == "" else "In the shafts"))
		BICYCLE:
			if bool(st.get("fallen", false)):
				out.append(_entry(&"stand_up", "Stand it up", ""))
			else:
				out.append(_entry(&"ride", "Ride", _block_text(actor)))
			if bool(st.get("flat", false)):
				out.append(_entry(&"fix_tyre", "Fix the tyre (inner tube)", "" if actor.inventory.count_of(TUBE) > 0 else "Needs an inner tube"))
		CART:
			out.append(_entry(&"drive", "Drive the cart", "" if String(st.get("hitch", "")) != "" else "No horse in the shafts"))
			out.append(_entry(&"ride_along", "Sit on the bench", ""))
			if String(st.get("hitch", "")) == "":
				out.append(_entry(&"hitch", "Hitch a horse", ""))
			else:
				out.append(_entry(&"unhitch", "Unhitch the horse", ""))
	out.append(_entry(&"mount_up", "Everyone mount up", "", "More"))
	out.append(_entry(&"check", "Check", "", "More"))
	return out


func _entry(id: StringName, label: String, disabled: String, group := "") -> Dictionary:
	var e := {"id": id, "label": label, "disabled": disabled, "call": func() -> void: request_action.rpc_id(1, String(id))}
	if group != "":
		e["group"] = group
	return e


func _block_text(actor: Soldier) -> String:
	var st := mount_state()
	if bool(st.get("tied", false)):
		return "Tied: untie it first"
	if String(st.get("hitch", "")) != "" and String(st.get("type", "")) == HORSE:
		return "In the cart's shafts"
	if occupant(0) != null and occupant(0) != actor:
		return "Someone's on it"
	return ""


@rpc("any_peer", "call_local", "reliable")
func request_action(id: String) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor == null or not actor.vitals.is_up():
		return
	if actor.global_position.distance_to(global_position) > REACH_M + VehicleArt.size_m(model).z * 0.5:
		_tell(actor, "Too far")
		return
	_tell(actor, server_action(actor, id))


## Host: `actor` does `id` here. Returns what he's told ("" for nothing).
func server_action(actor: Soldier, id: String) -> String:
	if wrecked and id != "check":
		return "It's dead" if mount_type == HORSE else "It's wrecked"
	match id:
		"ride", "drive":
			server_enter(actor, 0)  # (it says why not)
			return ""
		"ride_along":
			return "" if server_enter(actor, 1) else "No room"
		"catch":
			if mount_type != HORSE or tamed:
				return ""
			if actor.inventory.count_of(ROPE) <= 0:
				return "You need a rope"
			if not Rpg.gate(actor, "fieldcraft", CATCH_FIELDCRAFT):
				return "You don't know horses well enough (fieldcraft %d)" % CATCH_FIELDCRAFT
			if spooked_s > 0.0:
				return "It's bolting"
			_catch = {"actor": actor, "until": Soldier._now() + CATCH_S}
			_wander_to = null
			return "Easy now... (stay close)"
		"feed":
			return server_feed(actor)
		"water":
			return server_water(actor)
		"tie":
			if mount_type != HORSE or is_instance_valid(_partner):
				return ""
			tied = true
			home = global_position
			_publish_state(true)
			return "Tied"
		"untie":
			tied = false
			minder = null
			_publish_state(true)
			return "Untied"
		"stay":
			var mounts := Mounts.of(self)
			return mounts.server_stay(actor, self) if mounts else "Nobody to leave with it"
		"mount_up":
			var mounts := Mounts.of(self)
			return mounts.server_mount_up(actor) if mounts else ""
		"hitch":
			var why := server_hitch()
			return why if why != "" else "Hitched"
		"unhitch":
			server_unhitch()
			return "Unhitched"
		"stand_up":
			fallen = false
			_publish_state(true)
			return ""
		"fix_tyre":
			if not flat:
				return ""
			if actor.inventory.count_of(TUBE) <= 0:
				return "You need an inner tube"
			actor.inventory.remove_one(TUBE)
			flat = false
			_publish_state(true)
			return "Tyre fixed"
		"check":
			return report()
	return ""


## Host: oats from the actor (else the packs): FEED_PER_SACK each, up to full.
func server_feed(actor: Soldier) -> String:
	if mount_type != HORSE:
		return ""
	if feed >= 99.0:
		return "It isn't hungry"
	var given := 0
	while feed < 99.0:
		if actor and actor.inventory.count_of(FEED_ITEM) > 0:
			actor.inventory.remove_one(FEED_ITEM)
		elif not _take_from_packs(FEED_ITEM):
			break
		feed = minf(feed + FEED_PER_SACK, 100.0)
		starving_days = 0.0
		given += 1
	_publish_state(true)
	return "Fed (%d sack%s)" % [given, "" if given == 1 else "s"] if given > 0 else "No oats"


## Host: open water near (full), else the actor's bottles (WATER_PER_L a litre).
func server_water(actor: Soldier) -> String:
	if mount_type != HORSE:
		return ""
	if _water_near():
		water = 100.0
		thirst_days = 0.0
		_publish_state(true)
		return "It drinks its fill"
	var litres := 0.0
	while water < 99.0 and actor:
		var took := false
		for id: StringName in WATER_ITEMS:
			if actor.inventory.count_of(id) > 0 or _pack_count(id) > 0:
				if actor.inventory.count_of(id) > 0:
					actor.inventory.remove_one(id)
				else:
					_take_from_packs(id)  # (the bottles in its packs)
				var item := ItemDB.get_item(id)
				var l := float(item.stats.get("water_l", 1.0)) if item else 1.0
				water = minf(water + l * WATER_PER_L, 100.0)
				litres += l
				took = true
				break
		if not took:
			break
	if litres > 0.0:
		thirst_days = 0.0
	_publish_state(true)
	return "It drinks %.0f L" % litres if litres > 0.0 else "No water"


func _water_items(actor: Soldier) -> int:
	var n := 0
	for id: StringName in WATER_ITEMS:
		n += actor.inventory.count_of(id)
	return n


func _water_near() -> bool:
	var lvl := level()
	var t: Variant = lvl.get(&"terrain") if lvl else null
	if not t is ZoneTerrain or (t as ZoneTerrain).water == null:
		return false
	var w := (t as ZoneTerrain).water
	for dx: float in [-WATER_REACH_M, 0.0, WATER_REACH_M]:
		for dz: float in [-WATER_REACH_M, 0.0, WATER_REACH_M]:
			if w.depth_at(global_position.x + dx, global_position.z + dz) > 0.05:
				return true
	return false


func _pack_count(id: StringName) -> int:
	return cargo_hold.count_of(id) if cargo_hold else 0


func _take_from_packs(id: StringName) -> bool:
	if cargo_hold == null:
		return false
	var list := cargo_hold.entries()
	for i in list.size():
		if StringName(String((list[i] as Dictionary).id)) == id:
			cargo_hold.remove_entry(VehicleCargo.HOLD, i, 1)
			return true
	return false


## How it is, in words (Check).
func report() -> String:
	var st := mount_state()
	var parts := PackedStringArray([display_name()])
	match String(st.get("type", mount_type)):
		HORSE:
			if wrecked:
				return "The horse is dead"
			parts.append("feed %d%%, water %d%%, wind %d%%, %d HP" % [roundi(float(st.feed)), roundi(float(st.water)), roundi(float(st.stamina)), roundi(float(st.hp))])
			if not bool(st.tamed):
				parts.append("wild")
			if bool(st.tied):
				parts.append("tied" + (", minded" if bool(st.get("minded", false)) else ""))
		BICYCLE:
			if bool(st.fallen):
				parts.append("on its side")
			if bool(st.flat):
				parts.append("a flat tyre")
		CART:
			parts.append("a horse in the shafts" if String(st.get("hitch", "")) != "" else "no horse")
	if cargo_hold:
		parts.append("%d L of %d L loaded" % [roundi(cargo_hold.used_litres()), roundi(cargo_hold.capacity_l)])
	return ", ".join(parts)


# --- The rider's controls (local) ---------------------------------------------------------------------

## The rider's gait (host): the wheel's walk or trot, Shift's gallop.
@rpc("any_peer", "call_local", "reliable")
func request_gait(g: int) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor and driver() == actor:
		_gait_choice = clampi(g, Gait.WALK, Gait.GALLOP)


func _local_controls(delta: float) -> void:
	super._local_controls(delta)
	if mount_type == BICYCLE:
		return
	var lvl := level()
	var me := lvl.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if lvl and is_inside_tree() else null
	if me == null or driver() != me or not Vehicle.local_input or not me.is_local():
		return
	var want := Gait.GALLOP if Input.is_action_pressed(&"sprint") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else _local_gait
	if want != _sent_gait:
		_sent_gait = want
		request_gait.rpc_id(1, want)


## The mouse wheel while riding (PlayerInput.wheel_pace): a gait up or down (walk, trot); Shift
## held gallops. Whether it took the wheel.
func local_wheel(steps: int, hud: Node) -> bool:
	if mount_type == BICYCLE:
		return false
	_local_gait = clampi(_local_gait + signi(steps), Gait.WALK, Gait.TROT)
	if hud and hud.has_method(&"flash"):
		hud.call(&"flash", "Gait: %s (Shift: gallop)" % GAIT_NAMES[_local_gait])
	return true


func readout_parts(seat: int) -> Array[Dictionary]:
	var st := mount_state()
	var parts: Array[Dictionary] = [{"text": "%s, %s" % [display_name(), seat_name(seat)], "style": &""}]
	parts.append({"text": "%d km/h" % roundi(absf(forward_speed()) * 3.6), "style": &""})
	var t := String(st.get("type", mount_type))
	if t != BICYCLE:
		parts.append({"text": gait_name(), "style": &""})
	var hst := st
	if t == CART:
		var h := horse()
		hst = h.mount_state() if h else {}
		if hst.is_empty():
			parts.append({"text": "No horse", "style": &"warn"})
	if not hst.is_empty() and t != BICYCLE:
		parts.append({"text": "Wind %d%%" % roundi(float(hst.get("stamina", 100.0))), "style": &"warn" if float(hst.get("stamina", 100.0)) < GALLOP_MIN_STAMINA * 2.0 else &""})
		if float(hst.get("feed", 100.0)) < HUNGRY_BELOW:
			parts.append({"text": "Hungry", "style": &"warn"})
		if float(hst.get("water", 100.0)) < HUNGRY_BELOW:
			parts.append({"text": "Thirsty", "style": &"warn"})
		if bool(hst.get("spooked", false)):
			parts.append({"text": "BOLTING", "style": &"warn"})
	if bool(st.get("flat", false)):
		parts.append({"text": "Flat tyre", "style": &"warn"})
	parts.append({"text": "%s: %s" % [OS.get_keycode_string(GameSettings.key_for(VehicleCamera.ACTION)), "1st person" if VehicleCamera.chase else "3rd person"], "style": &"key"})
	if ControlOptions.get_out_key():
		parts.append({"text": "%s: get off" % ControlOptions.get_out_key_name(), "style": &"key"})
	return parts


# --- Every peer: the look ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if hull == null or not is_instance_valid(hull.art):
		return
	var st := mount_state()
	var art := hull.art
	var lying := wrecked or bool(st.get("fallen", false))
	if lying:
		art.rotation = Vector3(0.0, 0.0, PI * 0.5)  # on its side
		art.position = Vector3(0.0, VehicleArt.size_m(model).x * 0.5, 0.0)
		return
	art.rotation = Vector3.ZERO
	var speed := absf(forward_speed())
	if mount_type == BICYCLE or speed < STILL_MS:
		art.position = Vector3.ZERO
		return
	var g := int(st.get("gait", Gait.WALK))
	var freq := [4.0, 7.0, 9.0][clampi(g, 0, 2)] as float
	var amp := [0.015, 0.04, 0.06][clampi(g, 0, 2)] as float
	_bob_t += delta * freq
	art.position = Vector3(0.0, absf(sin(_bob_t)) * amp, 0.0)


# --- Replication and the save ------------------------------------------------------------------------------

func _publish_state(now := false) -> void:
	super._publish_state(now)
	if now and not mspec.is_empty():
		var st := net_state.duplicate()
		st["mount"] = _state_out()
		net_state = st



func to_save() -> Dictionary:
	var out := super.to_save()
	out["mount"] = {"tamed": tamed, "tied": tied, "feed": feed, "water": water, "stamina": stamina, "hp": health,
		"starving": starving_days, "thirst": thirst_days, "fallen": fallen, "flat": flat, "hitch": _hitch_id,
		"home": [home.x, home.y, home.z], "died_of": String(get_meta(&"died_of", ""))}
	return out


func from_save(data: Dictionary) -> void:
	super.from_save(data)
	var m: Dictionary = data.get("mount", {}) if data.get("mount") is Dictionary else {}
	if m.is_empty():
		home = _spawn_xform.origin
		return
	tamed = bool(m.get("tamed", tamed))
	tied = bool(m.get("tied", false))
	feed = clampf(float(m.get("feed", 100.0)), 0.0, 100.0)
	water = clampf(float(m.get("water", 100.0)), 0.0, 100.0)
	stamina = clampf(float(m.get("stamina", 100.0)), 0.0, 100.0)
	health = float(m.get("hp", health))
	starving_days = float(m.get("starving", 0.0))
	thirst_days = float(m.get("thirst", 0.0))
	fallen = bool(m.get("fallen", false))
	flat = bool(m.get("flat", false))
	_hitch_id = String(m.get("hitch", ""))
	var h: Array = m.get("home", [])
	home = Vector3(float(h[0]), float(h[1]), float(h[2])) if h.size() == 3 else _spawn_xform.origin
	if String(m.get("died_of", "")) != "":
		set_meta(&"died_of", String(m.died_of))
	_publish_state(true)
