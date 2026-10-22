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
##
## One 12-gauge system (Captain, 2026-10-21: "we have standard and hi brass and breaching rounds
## for the skeleton key", "standard and hi brass work in all shotguns, breaching rounds work in the
## 1014 and the skeleton key", "add a choke as an upgrade for the 870"): every 12 gauge fires
## through here, tube-fed or not (is_shotgun: stats.shells, the shells it takes). Three shells:
## Standard 00 buck, Hi-brass magnum buck (more and faster pellets, a wider pattern, recoil_mult)
## and Breaching (stats.breach: _server_breach), the last only where a gun lists it (the M1014, the
## Skeleton Key); a gun refuses a shell it doesn't list (takes): it won't load, and why_not() says
## why. What holds shells keeps them as a list under LIST_KEY in its item state: the gun's tube, a
## speed loader (stats.shell its default fill) or a Saiga-12 magazine (both "holders"), so each
## shell fires as what it is wherever it went. A gun with stats.loader takes a carried speed
## loader's shells in one push (stats.reload_s) when its tube has room for LOADER_MIN_ROOM or more.
## A choke (GunAttachments' "choke" mount, the 870's) narrows the pattern by its pellet_spread_mult.
## The Skeleton Key is an underbarrel 12 gauge (GunAttachments underbarrel, stats.underbarrel_shotgun):
## its tube rides in the gun's state under the mount (key_state), and the underbarrel key switches
## the trigger to it as to the M320 (server_fire_key, server_load with the Key).

const TUBE_KEY := "tube"
## Every shell holder keeps its shells under this key (a tube's, a loader's, a magazine's).
const LIST_KEY := TUBE_KEY
const STANDARD := &"shells_12g_buck"
const HI_BRASS := &"shells_12g_hibrass"
const BREACHING := &"shells_12g_breach"
## A speed loader goes in at one push when the tube has at least this much room.
const LOADER_MIN_ROOM := 2
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


## A 12 gauge that fires through here: a gun with stats.shells, tube-fed or from a magazine.
static func is_shotgun(weapon: ItemData) -> bool:
	return weapon != null and weapon.type == "weapon" and weapon.stats.has("shells")


## A speed loader or a magazine that holds a list of 12 gauge shells.
static func is_holder(item: ItemData) -> bool:
	return item != null and item.type == "ammo" and item.stats.has("shells") and not bool(item.stats.get("loose", false))


## The Skeleton Key and its kind: an underbarrel 12 gauge.
static func is_key(item: ItemData) -> bool:
	return item != null and item.type == GunAttachments.TYPE and bool(item.stats.get("underbarrel_shotgun", false))


## Whether `holder` (a gun, the Key, a loader or magazine) takes `shell`.
static func takes(holder: ItemData, shell: StringName) -> bool:
	return holder != null and shell in shells_of(holder)


## Why `holder` won't take `shell` ("" if it does).
static func why_not(holder: ItemData, shell: StringName) -> String:
	if takes(holder, shell):
		return ""
	var s := ItemDB.get_item(shell) if ItemDB.has_item(shell) else null
	if s and bool(s.stats.get("breach", false)):
		return "Breaching rounds only fit the M1014 and the Skeleton Key"
	return "The %s doesn't take %s" % [holder.name if holder else "gun", s.name if s else String(shell)]


## A holder's default shell (what it comes full of): stats.shell, else stats.ammo; a Saiga's its
## magazine's.
static func default_shell(item: ItemData) -> StringName:
	if item == null:
		return &""
	var id := StringName(String(item.stats.get("shell", item.stats.get("ammo", ""))))
	var ammo := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	if ammo and is_holder(ammo):
		return default_shell(ammo)
	return id


## A loader or magazine fresh from the box: full of its default shell.
static func full_holder_state(item: ItemData) -> Dictionary:
	var t: Array = []
	for i in item.magazine_rounds():
		t.append(String(default_shell(item)))
	return {"rounds": t.size(), LIST_KEY: t}


## The shells in item state `state` of `item` (a holder or a magazine-fed gun), first in first; an
## old state with only a count (or none: a full one) reads as that many of its default shell.
static func list_of(item: ItemData, state: Dictionary) -> Array:
	if state.has(LIST_KEY):
		return tube_of(state)
	var full := item.magazine_rounds() if item and item.type == "ammo" else 0
	var t: Array = []
	for i in int(state.get("rounds", full)):
		t.append(String(default_shell(item)))
	return t


## The pattern's spread multiplier for `weapon` with state `state`: a choke's pellet_spread_mult.
static func spread_mult(weapon: ItemData, state: Dictionary) -> float:
	var choke := GunAttachments.mounted(weapon, state, GunAttachments.CHOKE)
	return float(choke.stats.get("pellet_spread_mult", 1.0)) if choke else 1.0


## Shells `inv` carries that `weapon` (a 12 gauge, or the Key) takes: loose, and in the holders
## that feed it (its stats.loader, or its stats.ammo magazine).
static func spare_shells(inv: Inventory, weapon: ItemData) -> int:
	var n := 0
	for shell in shells_of(weapon):
		n += inv.count_of(shell)
	var feeds := [String(weapon.stats.get("loader", "")), String(weapon.stats.get("ammo", ""))]
	for c in inv.search_containers():
		for entry: Dictionary in inv.containers[c]:
			var item := ItemDB.get_item(entry.id)
			if is_holder(item) and String(entry.id) in feeds:
				for shell: Variant in list_of(item, entry.get("state", {})):
					if takes(weapon, StringName(String(shell))):
						n += int(entry.count)
	return n


## How many shells the tube holds.
static func capacity(weapon: ItemData) -> int:
	return int(weapon.stats.get("tube", 0)) if weapon else 0


## The shells in a tube weapon's item state, first loaded first (the last fires next).
static func tube_of(state: Dictionary) -> Array:
	var t: Variant = state.get(TUBE_KEY, [])
	return t if t is Array else []


## The shell kinds a gun, the Key or a holder takes (stats.shells, else its stats.ammo).
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

## Host only. Takes the next shell out of the 12 gauge in `slot` (the whole snapshot goes out:
## the list changed, not just a count). Returns it, or &"" when it's empty.
static func server_take_shell(inv: Inventory, slot: StringName) -> StringName:
	var state := inv.state_of(slot).duplicate(true)
	var gun := ItemDB.get_item(inv.slots.get(slot, &"")) if inv.slots.get(slot, &"") != &"" else null
	var t := (tube_of(state) if state.has(LIST_KEY) else list_of(gun, state)).duplicate()
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
static func server_fire(s: Soldier, muzzle: Vector3, dir: Vector3, weapon: ItemData, shell: StringName, spread := 1.0) -> Dictionary:
	stop_load(s)  # firing stops a load
	last_results = []
	last_dirs = []
	var item := ItemDB.get_item(shell) if ItemDB.has_item(shell) else null
	var lvl := CompoundLevel.current(s)
	var first := {}
	if item and bool(item.stats.get("breach", false)) and takes(weapon, shell):
		var breach := _server_breach(s, lvl, muzzle, dir)
		if not breach.is_empty():
			last_results.append(breach)
			last_dirs.append(dir)
			_pump(s)
			return breach
	var shot := shot_item(weapon, shell)
	var count := int(item.stats.get("pellets", 1)) if item else 1
	for d in pellet_dirs(dir, count, float(item.stats.get("pellet_spread_deg", 0.0)) * spread if item else 0.0):
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


## The kick of the next shell out of `weapon` with item state `state`: a hi-brass shell's
## recoil_mult (1 for anything else). Read before the shot goes (PlayerInput).
static func recoil_of(weapon: ItemData, state: Dictionary) -> float:
	if not is_shotgun(weapon) and not is_key(weapon):
		return 1.0
	var t := tube_of(state) if state.has(LIST_KEY) else list_of(weapon, state)
	var shell := ItemDB.get_item(StringName(String(t.back()))) if not t.is_empty() and ItemDB.has_item(StringName(String(t.back()))) else null
	return float(shell.stats.get("recoil_mult", 1.0)) if shell else 1.0


## The pump worked after the shot: its sound, on every peer.
static func _pump(s: Soldier) -> void:
	var tree := s.get_tree()
	if tree == null:
		return
	tree.create_timer(PUMP_AFTER_S).timeout.connect(func() -> void:
		if is_instance_valid(s) and s.is_inside_tree():
			Sfx.server_play(&"reload_pump", s.global_position + Vector3.UP * 1.3))


# --- The Skeleton Key -----------------------------------------------------------------------

## The Skeleton Key under `weapon` with item state `state` (null: none).
static func key_on(weapon: ItemData, state: Dictionary) -> ItemData:
	var on := GunAttachments.mounted(weapon, state, GunAttachments.UNDERBARREL) if weapon and weapon.type == "weapon" else null
	return on if is_key(on) else null


## The Skeleton Key under the gun `s` has in hand (null for none).
static func key_of(s: Soldier) -> ItemData:
	return key_on(s.active_weapon(), s.inventory.state_of(s.active_slot)) if s and s.inventory else null


## The Key's tube in gun state `state` (it comes full of its stats.ammo until fired or loaded).
static func key_list(key: ItemData, state: Dictionary) -> Array:
	var own := GunAttachments.mounted_state(state, GunAttachments.UNDERBARREL)
	return tube_of(own) if own.has(LIST_KEY) else tube_of(full_state(key))


## Gun state `state` of `weapon` with the Key's tube set to `list`.
static func with_key_list(weapon: ItemData, state: Dictionary, list: Array) -> Dictionary:
	var own := GunAttachments.mounted_state(state, GunAttachments.UNDERBARREL).duplicate(true)
	own[LIST_KEY] = list
	own["rounds"] = list.size()
	return GunAttachments.with_mounted(state, GunAttachments.UNDERBARREL, GunAttachments.mounted_id(weapon, state, GunAttachments.UNDERBARREL), own)


## The tube a load fills: the gun in `slot`'s own, or with `key` the Skeleton Key's under it.
static func _tube_item(s: Soldier, slot: StringName, key: bool) -> ItemData:
	var id: StringName = s.inventory.slots.get(slot, &"")
	var gun := ItemDB.get_item(id) if id != &"" else null
	if key:
		return key_on(gun, s.inventory.state_of(slot))
	return gun if is_tube(gun) else null


static func _tube_list(s: Soldier, slot: StringName, key: bool) -> Array:
	var state := s.inventory.state_of(slot)
	if key:
		return key_list(key_on(ItemDB.get_item(s.inventory.slots[slot]), state), state)
	return tube_of(state)


static func _set_tube(s: Soldier, slot: StringName, key: bool, list: Array) -> void:
	var state := s.inventory.state_of(slot).duplicate(true)
	if key:
		s.inventory.set_slot_state(slot, with_key_list(ItemDB.get_item(s.inventory.slots[slot]), state, list))
		return
	state[TUBE_KEY] = list
	state["rounds"] = list.size()
	s.inventory.set_slot_state(slot, state)


## Host only. `s` fires the Skeleton Key under the gun in their hands from `origin` (their eye)
## along `dir`: its next shell, as any 12 gauge's (server_fire), heard and seen as a shot. Returns
## "" when it fired, else why not.
static func server_fire_key(s: Soldier, origin: Vector3, dir: Vector3) -> String:
	if s == null or not s.multiplayer.is_server():
		return "Not the host"
	if not s.vitals.is_up() or s.inventory.hands != &"" or s.carry_mode != &"" or s.respawn_state == Soldier.RESPAWN_WAITING:
		return "Can't fire now"
	if is_instance_valid(s.vehicle):
		return "Get out to fire it"
	if not Soldier.usable_point(origin) or not Soldier.usable_direction(dir):
		return "Can't fire now"
	var key := key_of(s)
	if key == null:
		return "No Skeleton Key on it"
	var now := Soldier._now()
	if now < s._server_busy_until - 0.1 or now < float(s.get_meta(&"key_next_shot", 0.0)):
		return "Busy"
	var slot := s.active_slot
	var list := key_list(key, s.inventory.state_of(slot)).duplicate()
	if list.is_empty():
		return "Empty - R to load" if spare_shells(s.inventory, key) > 0 else "No shells for it"
	var shell := StringName(String(list.pop_back()))
	_set_tube(s, slot, true, list)
	s.set_meta(&"key_next_shot", now + 60.0 / float(key.stats.get("rpm", 50)))
	s.server_end_spawn_protection()
	dir = dir.normalized()
	if origin.distance_to(s.camera.global_position) > 1.0:
		origin = s.camera.global_position
	var right := dir.cross(Vector3.UP).normalized() if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var muzzle := Soldier.muzzle_point(origin, dir, false, s.left_handed, s.is_aiming) - right.cross(dir).normalized() * Underbarrel.BORE_BELOW_M
	if not s.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, muzzle, 1, [s.get_rid()])).is_empty():
		muzzle = origin
	var result := server_fire(s, muzzle, dir, key, shell)
	var end: Variant = result.get("position")
	var point: Vector3 = end if end is Vector3 else origin + dir * 60.0
	s.last_shot_at = now
	s.last_shot_suppressed = false
	s.last_shot_to = point
	Sfx.server_shot(muzzle, point, String(key.stats.get("sound", "shotgun")))
	var lvl := CompoundLevel.current(s)
	if lvl:
		var launch: Variant = result.get("launch")  # the path it flew, as Soldier's shots pass it (CompoundLevel.show_tracer)
		lvl.show_tracer.rpc(muzzle, launch if launch is Vector3 and end is Vector3 else Vector3.ZERO, Ballistics.round_id(shot_item(key, shell)),
			point, false, Tracer.Kind.BALL)
		if String(result.get("result", "none")) != "none":
			lvl.show_impact.rpc(result.position, result.normal, result.result)
	PeopleLayer.server_noise(s, origin)
	if s.faction != &"hostile":
		Alert.server_noise(s, origin, Alert.SHOT, false)
	SquadAI.server_heard_shot(s, origin, false)
	return ""


# --- Host: loading --------------------------------------------------------------------------

## Host only. `s` loads the tube of the gun in `slot` (with `key`, the Skeleton Key under it):
## a carried speed loader (the gun's stats.loader) in one push, stats.reload_s, when the tube has
## LOADER_MIN_ROOM or more room and the loader holds shells it takes; else shell by shell with
## `preferred` shells (or the first kind carried: load_choice), stats.shell_s each slowed by
## wounds, until the tube's full or the shells run out; firing, going down or another gun there
## stops it. Returns the seconds the first step takes, or -1 when there's nothing to load.
static func server_load(s: Soldier, slot: StringName, preferred: StringName = &"", key := false) -> float:
	var item := _tube_item(s, slot, key) if s else null
	if item == null or not s.vitals.is_up():
		return -1.0
	var room := capacity(item) - _tube_list(s, slot, key).size()
	if room <= 0:
		return -1.0
	var serial := int(_load_serial.get(s.get_instance_id(), 0)) + 1
	var loader := _loader_for(s.inventory, item) if not key and room >= LOADER_MIN_ROOM else {}
	if not loader.is_empty():
		_load_serial[s.get_instance_id()] = serial
		var push := float(item.stats.get("reload_s", 3.0)) * s.vitals.reload_mult()
		s._server_busy_until = Soldier._now() + push
		_push_loader(s, slot, s.inventory.slots[slot], s.inventory.slot_revision(slot), push, serial)
		return push
	if load_choice(item, s.inventory, preferred) == &"":
		return -1.0
	_load_serial[s.get_instance_id()] = serial
	var each := float(item.stats.get("shell_s", 0.5)) * s.vitals.reload_mult()
	_load_shells(s, slot, s.inventory.slots[slot], s.inventory.slot_revision(slot), preferred, each, serial, key)
	return each


## The carried speed loader for `gun` with the most shells it takes ({} for none): {"container",
## "index"}.
static func _loader_for(inv: Inventory, gun: ItemData) -> Dictionary:
	var id := StringName(String(gun.stats.get("loader", "")))
	if id == &"" or not ItemDB.has_item(id):
		return {}
	var holder := ItemDB.get_item(id)
	var best := {}
	var most := 0
	for c in inv.search_containers():
		var list: Array = inv.containers[c]
		for i in list.size():
			if list[i].id != id:
				continue
			var n := list_of(holder, list[i].get("state", {})).filter(func(x: Variant) -> bool: return takes(gun, StringName(String(x)))).size()
			if n > most:
				most = n
				best = {"container": c, "index": i}
	return best


## A speed loader's shells into the tube in one push, after `seconds`: as many as fit, those the
## gun takes (the rest stay in the loader, which goes back where it was).
static func _push_loader(s: Soldier, slot: StringName, gun_id: StringName, rev: int, seconds: float, serial: int) -> void:
	s.set_meta(&"loading_shells", serial)
	Sfx.server_play(&"reload_shell", s.global_position + Vector3.UP)
	await s.get_tree().create_timer(seconds).timeout
	if not is_instance_valid(s):
		return
	if int(s.get_meta(&"loading_shells", -1)) == serial:
		s.remove_meta(&"loading_shells")
	if int(_load_serial.get(s.get_instance_id(), 0)) != serial or not s.vitals.is_up() \
			or s.inventory.slots.get(slot, &"") != gun_id or s.inventory.slot_revision(slot) != rev:
		return
	var gun := ItemDB.get_item(gun_id)
	var at := _loader_for(s.inventory, gun)
	if at.is_empty():
		return
	var entry: Dictionary = s.inventory.containers[at.container][at.index]
	var holder := ItemDB.get_item(entry.id)
	var shells := list_of(holder, entry.get("state", {})).duplicate()
	var tube := tube_of(s.inventory.state_of(slot)).duplicate()
	var kept: Array = []
	while not shells.is_empty():
		var shell := String(shells.pop_back())
		if tube.size() < capacity(gun) and takes(gun, StringName(shell)):
			tube.append(shell)
		else:
			kept.push_front(shell)
	s.inventory.remove_entry(at.container, at.index)
	var left := {"rounds": kept.size(), LIST_KEY: kept}
	if not s.inventory.insert_entry(at.container, {"id": entry.id, "count": 1, "state": left}) and s.inventory.take(entry.id, 1, left) < 1:
		s._server_spawn_in_front(entry.id)  # (no room anywhere: on the ground in front)
	_set_tube(s, slot, false, tube)
	Sfx.server_play(&"reload_shell", s.global_position + Vector3.UP)


## Whether a load is under way for `s` (tests, the HUD).
static func loading(s: Soldier) -> bool:
	return s != null and s.has_meta(&"loading_shells")


## Host only. Stops the load under way for `s`, if any (it stops at the next shell).
static func stop_load(s: Soldier) -> void:
	if s:
		_load_serial[s.get_instance_id()] = int(_load_serial.get(s.get_instance_id(), 0)) + 1


static func _load_shells(s: Soldier, slot: StringName, gun_id: StringName, rev: int, preferred: StringName, each: float, serial: int, key := false) -> void:
	s.set_meta(&"loading_shells", serial)
	while true:
		await s.get_tree().create_timer(each).timeout
		if not is_instance_valid(s):
			return
		if int(_load_serial.get(s.get_instance_id(), 0)) != serial or not s.vitals.is_up() \
				or s.inventory.slots.get(slot, &"") != gun_id or s.inventory.slot_revision(slot) != rev:
			break
		var item := _tube_item(s, slot, key)
		if item == null:
			break  # the Key came off meanwhile
		var shell := load_choice(item, s.inventory, preferred)
		var t := _tube_list(s, slot, key).duplicate()
		if shell == &"" or t.size() >= capacity(item) or not s.inventory.remove_one(shell):
			break
		t.append(String(shell))
		_set_tube(s, slot, key, t)
		Sfx.server_play(&"reload_shell", s.global_position + Vector3.UP)
		if t.size() >= capacity(item) or load_choice(item, s.inventory, preferred) == &"":
			break
	if int(s.get_meta(&"loading_shells", -1)) == serial:
		s.remove_meta(&"loading_shells")
