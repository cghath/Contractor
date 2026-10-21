class_name Underbarrel
extends RefCounted
## The M320 under a rifle (Captain's list for cghath, 2026-10-20: "an M320 underbarrel grenade
## launcher"). It's a GunAttachments underbarrel item with stats.launcher: it goes on a railed
## rifle as a grip does (not on a machine gun or a sniper rifle: stats.not_fits), and its own
## item state ({"round": warhead id}) rides in the gun's (GunAttachments.mounted_state), so the
## grenade in it stays loaded on and off the gun, dropped, stowed, looted, saved and replicated.
##
## The player switches the trigger to it with the underbarrel key (Controls.KEYS
## weapon_underbarrel, 4; Soldier.underbarrel_up, owner-side like the fire mode) and back; Fire
## then lobs the grenade (Launchers.request_fire_underbarrel -> server_fire) and R loads one by
## hand (request_reload_underbarrel -> server_reload: its reload_s, slowed by wounds; one of the
## other kind already in comes out into the kit). The grenade flies the launchers' own flight
## (Launchers.server_launch, LauncherProjectile: the warhead's speed_mps out of the muzzle,
## gravity, no motor), so it arcs: aim high for range. 40 mm HE (M406) goes off through
## Warheads.server_burst (blast, fragments, a small crater) once past its arming_m, and short of
## it hits like a stone (Launchers' dud); smoke (M714) puts a cloud where it lands (SmokeCloud).
## The AI doesn't use it yet (docs/audits/followups.md F-130). Every number proposed
## (data/items.json, data/warheads.json).

const MOUNT := GunAttachments.UNDERBARREL
## Proposed: after a shot the shooter is busy this long (the kick, back onto the rifle).
const FIRE_BUSY_S := 0.6
## The launcher's bore sits this far under the rifle's.
const BORE_BELOW_M := 0.07

static var _reload_serial := {}  # host: soldier instance id -> the load in progress


## The grenade launcher on `weapon` with item state `state` (null: none, or not a launcher).
static func launcher_of(weapon: ItemData, state: Dictionary) -> ItemData:
	if weapon == null or weapon.type != "weapon":
		return null
	var on := GunAttachments.mounted(weapon, state, MOUNT)
	return on if on != null and bool(on.stats.get("launcher", false)) else null


## The grenade launcher under the gun `s` has in hand (null for none).
static func on_gun(s: Soldier) -> ItemData:
	if s == null or s.inventory == null:
		return null
	return launcher_of(s.active_weapon(), s.inventory.state_of(s.active_slot))


## The warhead loaded in the launcher of a gun with item state `state` (&"" when empty).
static func loaded(state: Dictionary) -> StringName:
	return StringName(String(GunAttachments.mounted_state(state, MOUNT).get("round", "")))


## The warhead loaded in the launcher under the gun `s` has in hand (&"" for none or empty).
static func loaded_of(s: Soldier) -> StringName:
	return loaded(s.inventory.state_of(s.active_slot)) if on_gun(s) != null else &""


## A gun's item state `state` with warhead `w` in its launcher (&"" to empty it).
static func with_round(weapon: ItemData, state: Dictionary, w: StringName) -> Dictionary:
	var own := GunAttachments.mounted_state(state, MOUNT).duplicate(true)
	if w == &"":
		own.erase("round")
	else:
		own["round"] = String(w)
	return GunAttachments.with_mounted(state, MOUNT, GunAttachments.mounted_id(weapon, state, MOUNT), own)


## The grenade items for the launcher under `s`'s gun that they carry, in its accepts order.
static func carried_rounds(s: Soldier) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Launchers.round_items(on_gun(s)):
		if s.inventory.count_of(id) > 0:
			out.append(id)
	return out


## The grenade the next load puts in: `preferred` if carried; else the first carried when
## empty, or the next kind after the one loaded (R again swaps HE for smoke). &"" for none.
static func next_round(s: Soldier, preferred: StringName = &"") -> StringName:
	if on_gun(s) == null:
		return &""
	var carried := carried_rounds(s)
	if preferred != &"" and preferred in carried:
		return preferred
	var current := loaded_of(s)
	for id in carried:
		if current == &"" or StringName(ItemDB.get_item(id).stats.get("warhead", "")) != current:
			return id
	return &""


## Host only. `s` fires the launcher under the gun in their hands from `origin` (their eye)
## along `dir`. Returns "" when it fired (Launchers.last_id is the grenade), else why not.
static func server_fire(s: Soldier, origin: Vector3, dir: Vector3) -> String:
	if s == null or not s.multiplayer.is_server():
		return "Not the host"
	if not s.vitals.is_up() or s.inventory.hands != &"" or s.carry_mode != &"" or s.respawn_state == Soldier.RESPAWN_WAITING:
		return "Can't fire now"
	if is_instance_valid(s.vehicle):
		return "Get out to fire it"
	if not Soldier.usable_point(origin) or not Soldier.usable_direction(dir):
		return "Can't fire now"
	var weapon := s.active_weapon()
	var slot := s.active_slot
	var gl := on_gun(s)
	if gl == null:
		return "No grenade launcher on it"
	var now := Soldier._now()
	if now < s._server_busy_until - 0.1:
		return "Busy"
	var w := loaded_of(s)
	var d := Warheads.data(w)
	if d.is_empty():
		return "Empty - R to load" if not carried_rounds(s).is_empty() else "No 40 mm grenades"
	var launchers := Launchers.of(s)
	if launchers == null:
		return "Not here"
	dir = dir.normalized()
	if origin.distance_to(s.camera.global_position) > Launchers.AIM_TRUST_M:
		origin = s.camera.global_position
	s.server_end_spawn_protection()  # firing ends spawn protection (Soldier)
	s.inventory.set_slot_state(slot, with_round(weapon, s.inventory.state_of(slot), &""))
	s._server_busy_until = now + FIRE_BUSY_S
	# Out of the launcher's muzzle, under the rifle's (and from the eye with the muzzle in a wall,
	# as Soldier._server_fire does).
	var right := dir.cross(Vector3.UP).normalized() if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var muzzle := Soldier.muzzle_point(origin, dir, false, s.left_handed, s.is_aiming) - right.cross(dir).normalized() * BORE_BELOW_M
	var wall_q := PhysicsRayQueryParameters3D.create(origin, muzzle, 1, [s.get_rid()])
	if not s.get_world_3d().direct_space_state.intersect_ray(wall_q).is_empty():
		muzzle = origin
	launchers.server_launch(s, w, muzzle, dir * float(d.get("speed_mps", 76.0)))
	s.last_shot_at = now
	s.last_shot_suppressed = false
	Sfx.server_shot(muzzle, muzzle + dir * 30.0, "grenade_launcher")
	PeopleLayer.server_noise(s, origin)  # people nearby hear it
	if s.faction != &"hostile":
		Alert.server_noise(s, origin, Alert.SHOT, false)  # hot zones: the enemy hears it
	SquadAI.server_heard_shot(s, origin, false)
	print("[underbarrel] %s fired the %s (%s) from (%.1f, %.1f, %.1f)" % [s.display_name(), gl.name, Launchers.warhead_name(w), origin.x, origin.y, origin.z])
	return ""


## Host only. `s` loads the launcher under the gun in their hands with `round_id` (or the next
## grenade, next_round): it takes the launcher's reload_s, slowed by wounds, and the grenade
## goes in at the end if it's still the same gun in hand with the launcher on it. Returns the
## seconds it takes, or -1 when there's nothing to load (or they can't now).
static func server_reload(s: Soldier, round_id: StringName = &"") -> float:
	if s == null or not s.multiplayer.is_server() or not s.vitals.is_up() or s.inventory.hands != &"":
		return -1.0
	var gl := on_gun(s)
	var now := Soldier._now()
	if gl == null or now < s._server_busy_until - 0.1:
		return -1.0
	var choice := next_round(s, round_id)
	if choice == &"":
		return -1.0
	var seconds := float(gl.stats.get("reload_s", 3.0)) * s.vitals.reload_mult()
	s._server_busy_until = now + seconds
	var serial := int(_reload_serial.get(s.get_instance_id(), 0)) + 1
	_reload_serial[s.get_instance_id()] = serial
	var slot := s.active_slot
	Sfx.server_play(&"reload_bolt_back", s.global_position + Vector3.UP)  # the breech swung open
	_finish_reload(s, slot, s.inventory.slots.get(slot, &""), s.inventory.slot_revision(slot), choice, seconds, serial)
	return seconds


static func _finish_reload(s: Soldier, slot: StringName, gun_id: StringName, rev: int, choice: StringName, seconds: float, serial: int) -> void:
	await s.get_tree().create_timer(seconds).timeout
	if not is_instance_valid(s) or int(_reload_serial.get(s.get_instance_id(), 0)) != serial or not s.vitals.is_up() \
			or s.inventory.slots.get(slot, &"") != gun_id or s.inventory.slot_revision(slot) != rev:
		return
	var weapon := ItemDB.get_item(gun_id)
	var state := s.inventory.state_of(slot)
	if launcher_of(weapon, state) == null:
		return  # it came off meanwhile
	var w := StringName(ItemDB.get_item(choice).stats.get("warhead", ""))
	var current := loaded(state)
	if current == w or not s.inventory.remove_one(choice):
		return
	s.inventory.set_slot_state(slot, with_round(weapon, s.inventory.state_of(slot), w))
	Sfx.server_play(&"reload_bolt_fwd", s.global_position + Vector3.UP)  # and shut
	if current != &"":
		var back := Launchers.round_item_for(current)  # the grenade that was in comes out
		if back != &"" and s.inventory.take(back) < 1:
			s._server_spawn_in_front(back)
