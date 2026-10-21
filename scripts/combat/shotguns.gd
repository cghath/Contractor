class_name Shotguns
extends RefCounted
## Tube-fed pump shotguns (Captain's list for cghath, 2026-10-20: "a shotgun", a breacher learning
## from the M870 and M1014 kind). A weapon with stats.tube keeps its shells in its item state as
## a list, "tube" (shell item ids, the last one the next to fire, as a real tube feeds), with
## "rounds" = how many, so everything that counts rounds (the HUD, the AI, net_ammo) still does.
## It comes full of its stats.ammo (ItemData.default_state).
##
## Firing (Soldier._server_fire: server_take_shell, then server_fire): the next shell's round
## flies through the real ballistics (Ballistics.fire): buckshot is its stats.pellets pellets of
## its pellet_round, each along its own line inside pellet_spread_deg of the aim (pellet_dirs);
## a slug is one round. A breaching round that meets a wood or sheet-metal door or wall within
## BREACH_REACH_M blows a hole through it, the way a breaching charge does on a smaller scale
## (CompoundLevel.server_blast by the materials' blast share: concrete only chips), and one that
## meets a locked box shoots its lock off (WorldCache.unlocked); anything else it meets as a
## weak, short-ranged round. The pump: fire mode "pump" fires once a pull, and the weapon's rpm
## is the time to work it (its sound a moment after the shot).
##
## Loading (R: Soldier._server_load_shells, server_load): shell by shell, stats.shell_s each
## (slowed by wounds), of the kind picked (the underbarrel key cycles stats.shells in
## PlayerInput), else the first kind carried; it goes on until the tube is full or the shells
## run out, and firing, going down, or another gun in hand stops it. Every number proposed.

const TUBE_KEY := "tube"
## Proposed: a breaching round opens what it meets this close (m), with a hole this wide (m).
const BREACH_REACH_M := 2.5
const BREACH_RADIUS_M := 0.4
## What a breaching round can open: the world (voxels, terrain) and boxes (WorldCache).
const BREACH_MASK := 1
## The pump's sound comes this long after the shot (s).
const PUMP_AFTER_S := 0.35

## Host: every pellet's (or the slug's) result of the latest shot (Ballistics.fire), its
## directions, and the latest breach ({"position", "what": "wall" or "lock"}); tests read them.
static var last_results: Array = []
static var last_dirs: Array[Vector3] = []
static var last_breach: Dictionary = {}
static var _shots := {}  # "weapon|round" -> the ItemData the ballistics fire
static var _load_serial := {}  # host: soldier instance id -> the load in progress
static var _rng := RandomNumberGenerator.new()


static func is_tube(weapon: ItemData) -> bool:
	return weapon != null and weapon.type == "weapon" and int(weapon.stats.get("tube", 0)) > 0


## How many shells the tube holds.
static func capacity(weapon: ItemData) -> int:
	return int(weapon.stats.get("tube", 0)) if weapon else 0


## The shells in a tube weapon's item state, first loaded first (the last fires next).
static func tube_of(state: Dictionary) -> Array:
	var t: Variant = state.get(TUBE_KEY, [])
	return t if t is Array else []


## The shell kinds a tube weapon takes (stats.shells, else its stats.ammo).
static func shells_of(weapon: ItemData) -> Array[StringName]:
	var out: Array[StringName] = []
	if weapon == null:
		return out
	for id: Variant in weapon.stats.get("shells", [weapon.stats.get("ammo", "")]):
		if ItemDB.has_item(StringName(String(id))):
			out.append(StringName(String(id)))
	return out


## A tube weapon fresh from the box: full of its stats.ammo.
static func full_state(weapon: ItemData) -> Dictionary:
	var shell := String(weapon.stats.get("ammo", ""))
	var t: Array = []
	for i in capacity(weapon):
		t.append(shell)
	return {"rounds": t.size(), TUBE_KEY: t}


## The shell that fires next from a tube weapon with item state `state` (&"" when empty).
static func next_shell(state: Dictionary) -> StringName:
	var t := tube_of(state)
	return StringName(String(t.back())) if not t.is_empty() else &""


## The shell kind after `current` in `weapon`'s stats.shells that `inv` carries (the
## underbarrel key's pick; `current` again if it's the only one, the first kind with none).
static func next_pick(weapon: ItemData, current: StringName, inv: Inventory) -> StringName:
	var kinds := shells_of(weapon)
	if kinds.is_empty():
		return &""
	var start := kinds.find(current)
	for step in range(1, kinds.size() + 1):
		var id := kinds[(start + step) % kinds.size()]
		if inv == null or inv.count_of(id) > 0:
			return id
	return kinds[0] if current == &"" else current


## The shell kind a load puts in: `preferred` if carried, else the first kind carried (&"").
static func load_choice(weapon: ItemData, inv: Inventory, preferred: StringName = &"") -> StringName:
	var kinds := shells_of(weapon)
	if preferred in kinds and inv.count_of(preferred) > 0:
		return preferred
	for id in kinds:
		if inv.count_of(id) > 0:
			return id
	return &""


## The ItemData the ballistics fire for one round of `shell` from `weapon`: the weapon's with
## the shell's round (a pellet's for buckshot); its own muzzle velocity, the barrel's other stats.
static func shot_item(weapon: ItemData, shell: StringName) -> ItemData:
	var s := ItemDB.get_item(shell) if ItemDB.has_item(shell) else null
	var round_id := String(s.stats.get("pellet_round", s.stats.get("round", ""))) if s else ""
	var key := "%s|%s" % [weapon.id, round_id]
	if _shots.has(key):
		return _shots[key]
	var item := ItemData.new()
	item.id = weapon.id
	item.name = weapon.name
	item.type = weapon.type
	item.slot = weapon.slot
	item.volume_l = weapon.volume_l
	item.mass_kg = weapon.mass_kg
	item.tags = weapon.tags
	item.stats = weapon.stats.duplicate(true)
	item.stats["round"] = round_id
	item.stats.erase("muzzle_velocity_mps")  # each shell's own
	_shots[key] = item
	return item


## `count` directions inside a cone of `spread_deg` (half-angle) round `dir`, spread evenly over
## its disc: a buckshot pattern. One is the aim itself.
static func pellet_dirs(dir: Vector3, count: int, spread_deg: float, rng: RandomNumberGenerator = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	dir = dir.normalized()
	if count <= 1 or spread_deg <= 0.0:
		out.append(dir)
		return out
	var r := rng if rng else _rng
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()
	for i in count:
		var off := deg_to_rad(spread_deg) * sqrt(r.randf())
		var turn := r.randf() * TAU
		var axis := (side * cos(turn) + up * sin(turn)).normalized()
		out.append(dir.rotated(axis.cross(dir).normalized(), off).normalized())
	return out


# --- Host: firing ---------------------------------------------------------------------------

## Host only. Takes the next shell out of the tube weapon in `slot` (the whole snapshot goes
## out: the tube's list changed, not just a count). Returns it, or &"" when the tube is empty.
static func server_take_shell(inv: Inventory, slot: StringName) -> StringName:
	var state := inv.state_of(slot).duplicate(true)
	var t := tube_of(state).duplicate()
	if t.is_empty():
		return &""
	var shell := StringName(String(t.pop_back()))
	state[TUBE_KEY] = t
	state["rounds"] = t.size()
	inv.set_slot_state(slot, state)
	return shell


## Host only. `s` fires `shell` from the shotgun `weapon` from `muzzle` along `dir` (the
## shell's already out of the tube: server_take_shell). Returns the shot's result for its
## effects (the first pellet's, or a breach's: {"result", "position", "normal"}); every
## pellet's is in last_results. It stops a load under way and works the pump.
static func server_fire(s: Soldier, muzzle: Vector3, dir: Vector3, weapon: ItemData, shell: StringName) -> Dictionary:
	stop_load(s)  # firing stops a load
	last_results = []
	last_dirs = []
	var item := ItemDB.get_item(shell) if ItemDB.has_item(shell) else null
	var lvl := CompoundLevel.current(s)
	var first := {}
	if item and bool(item.stats.get("breach", false)):
		var breach := _server_breach(s, lvl, muzzle, dir)
		if not breach.is_empty():
			last_results.append(breach)
			last_dirs.append(dir)
			_pump(s)
			return breach
	var shot := shot_item(weapon, shell)
	var count := int(item.stats.get("pellets", 1)) if item else 1
	for d in pellet_dirs(dir, count, float(item.stats.get("pellet_spread_deg", 0.0)) if item else 0.0):
		var result := Ballistics.fire(s, muzzle, d, shot)
		last_results.append(result)
		last_dirs.append(d)
		if first.is_empty():
			first = result
		elif lvl and String(result.get("result", "none")) != "none":
			lvl.show_impact.rpc(result.position, result.normal, result.result)  # (the first pellet's: Soldier._server_fire)
	_pump(s)
	return first


## A breaching round's door, wall or lock within BREACH_REACH_M of `muzzle` along `dir`: blows
## a hole or shoots the lock off. Its result ({} when it met nothing it opens: a plain shot).
static func _server_breach(s: Soldier, lvl: CompoundLevel, muzzle: Vector3, dir: Vector3) -> Dictionary:
	if lvl == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * BREACH_REACH_M, BREACH_MASK, [s.get_rid()])
	var hit := s.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var cache := hit.collider as WorldCache
	if cache:
		if not cache.is_locked():
			return {}
		cache.unlocked = true  # its lock shot off: it opens for anyone now
		last_breach = {"position": hit.position, "what": "lock"}
		print("[shotguns] %s shot the lock off %s" % [s.display_name(), cache.display_name()])
		return {"result": "world", "position": hit.position, "normal": hit.normal}
	if VoxelWorld.find_on(hit.collider) == null:
		return {}  # the ground: nothing to open
	lvl.server_blast(hit.position + dir * 0.05, BREACH_RADIUS_M)  # (concrete only chips: its blast share)
	last_breach = {"position": hit.position, "what": "wall"}
	PeopleLayer.server_noise(lvl, hit.position)
	print("[shotguns] %s breached at (%.1f, %.1f, %.1f)" % [s.display_name(), hit.position.x, hit.position.y, hit.position.z])
	return {"result": "world", "position": hit.position, "normal": hit.normal}


## The pump worked after the shot: its sound, on every peer.
static func _pump(s: Soldier) -> void:
	var tree := s.get_tree()
	if tree == null:
		return
	tree.create_timer(PUMP_AFTER_S).timeout.connect(func() -> void:
		if is_instance_valid(s) and s.is_inside_tree():
			Sfx.server_play(&"reload_pump", s.global_position + Vector3.UP * 1.3))


# --- Host: loading --------------------------------------------------------------------------

## Host only. `s` loads the tube weapon in `slot` shell by shell with `preferred` shells (or
## the first kind carried: load_choice), stats.shell_s each slowed by wounds, until the tube's
## full or the shells run out; firing, going down or another gun there stops it. Returns the
## seconds the first shell takes, or -1 when there's nothing to load.
static func server_load(s: Soldier, slot: StringName, preferred: StringName = &"") -> float:
	var id: StringName = s.inventory.slots.get(slot, &"") if s else &""
	var weapon := ItemDB.get_item(id) if id != &"" else null
	if not is_tube(weapon) or not s.vitals.is_up() or tube_of(s.inventory.state_of(slot)).size() >= capacity(weapon):
		return -1.0
	if load_choice(weapon, s.inventory, preferred) == &"":
		return -1.0
	var serial := int(_load_serial.get(s.get_instance_id(), 0)) + 1
	_load_serial[s.get_instance_id()] = serial
	var each := float(weapon.stats.get("shell_s", 0.5)) * s.vitals.reload_mult()
	_load_shells(s, slot, id, s.inventory.slot_revision(slot), preferred, each, serial)
	return each


## Whether a load is under way for `s` (tests, the HUD).
static func loading(s: Soldier) -> bool:
	return s != null and s.has_meta(&"loading_shells")


## Host only. Stops the load under way for `s`, if any (it stops at the next shell).
static func stop_load(s: Soldier) -> void:
	if s:
		_load_serial[s.get_instance_id()] = int(_load_serial.get(s.get_instance_id(), 0)) + 1


static func _load_shells(s: Soldier, slot: StringName, gun_id: StringName, rev: int, preferred: StringName, each: float, serial: int) -> void:
	var weapon := ItemDB.get_item(gun_id)
	s.set_meta(&"loading_shells", serial)
	while true:
		await s.get_tree().create_timer(each).timeout
		if not is_instance_valid(s):
			return
		if int(_load_serial.get(s.get_instance_id(), 0)) != serial or not s.vitals.is_up() \
				or s.inventory.slots.get(slot, &"") != gun_id or s.inventory.slot_revision(slot) != rev:
			break
		var shell := load_choice(weapon, s.inventory, preferred)
		var state := s.inventory.state_of(slot).duplicate(true)
		var t := tube_of(state).duplicate()
		if shell == &"" or t.size() >= capacity(weapon) or not s.inventory.remove_one(shell):
			break
		t.append(String(shell))
		state[TUBE_KEY] = t
		state["rounds"] = t.size()
		s.inventory.set_slot_state(slot, state)
		Sfx.server_play(&"reload_shell", s.global_position + Vector3.UP)
		if t.size() >= capacity(weapon) or load_choice(weapon, s.inventory, preferred) == &"":
			break
	if int(s.get_meta(&"loading_shells", -1)) == serial:
		s.remove_meta(&"loading_shells")
