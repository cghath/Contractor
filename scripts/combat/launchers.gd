class_name Launchers
extends Node
## Shoulder-fired anti-armour launchers (wave 5, V2): AT4, RPG-7, Javelin, MAAWS, NLAW, SMAW.
## One node per level, "Launchers", on every peer (CompoundLevel adds it, like Charges).
##
## A launcher is an item of type "launcher" in the soldier's "launcher" slot (key 3 brings it
## up). Its state holds the round loaded ({"round": warhead id, "" empty}); without one it
## holds its stats' "loaded" (a disposable's own round, or nothing). Rounds are ammo items
## naming their warhead (data/warheads.json, Warheads); a reloadable launcher takes the ones
## its stats' "accepts" lists, a disposable is spent when fired.
##
## The host decides everything: server_fire (a player's request_fire, or the AI) checks the
## launcher, a Javelin's lock, spends the round, throws the backblast
## (Warheads.server_backblast) and launches a LauncherProjectile on every peer; the host flies
## it (motor, gravity, guidance, arming) and sends its track; where it ends the warhead goes
## off (Warheads.server_burst: vehicles, structures, people) and every peer sees the burst.
## Craters are voxel edits, so late joiners get them with the edit log; a joiner also gets the
## rounds still in flight. server_reload is timed (the item's reload_s, slowed by wounds).
## The M320 under a rifle (Underbarrel) fires its 40 mm grenades through the same flight
## (server_launch, request_fire_underbarrel); a smoke grenade ends in a cloud, not a burst.

const SLOT := &"launcher"
## The host sends each round's position this often (s).
const TRACK_S := 0.1
## Proposed: after a shot the shooter is busy this long (recoil, lowering the tube).
const FIRE_BUSY_S := 1.0
## Don't trust a far-off eye (as Soldier._server_fire).
const AIM_TRUST_M := 1.0
## Proposed: a Javelin's lock holds while the target is within this angle of the aim (the
## seeker's track gate).
const LOCK_CONE_DEG := 6.0
## The tube rides on the firing shoulder this far right of and below the eye.
const SHOULDER_RIGHT_M := 0.1
const SHOULDER_DOWN_M := 0.1
## NLAW: its average speed, for the lead on a moving target (proposed).
const NLAW_LEAD_MPS := 190.0
## How often every peer looks for soldiers carrying a launcher to draw (LauncherRig).
const RIG_SCAN_S := 0.25
## Host: how many finished rounds `results` keeps (tests and tools).
const RESULTS_KEPT := 64

var level: Node3D
## Every peer: id -> LauncherProjectile in flight.
var projectiles: Dictionary = {}
## Every peer: rounds seen launched, backblasts and ends ({"id", "w", "pos", "how": "burst",
## "dud", "lost" or "smoke": an M320 smoke grenade's cloud}), for tests and the HUD.
var launched := 0
var backblasts := 0
var ends: Array[Dictionary] = []
## Host: what each round did when it ended: id -> {"how", "position", "direction",
## "top_attack", "max_height", "burst" (Warheads.server_burst's result), "shooter"}; and the
## latest shot's backblast (Warheads.server_backblast's result) and projectile id.
var results: Dictionary = {}
var last_backblast: Dictionary = {}
var last_id := 0
var _next_id := 1
var _track_cd := 0.0
var _rig_cd := 0.0
var _reload_serial := {}  # host: soldier instance id -> the reload in progress


func _init() -> void:
	name = "Launchers"


func _ready() -> void:
	level = get_parent() as Node3D
	Net.peer_joined.connect(_on_peer_joined)


## The launchers node of the level `from` is in (or null).
static func of(from: Node) -> Launchers:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(^"Launchers") as Launchers if lvl else null


# --- Items (every peer) ---------------------------------------------------------------------

static func is_launcher(item: ItemData) -> bool:
	return item != null and item.type == "launcher"


## The launcher `s` carries (its "launcher" slot), or null.
static func launcher_of(s: Soldier) -> ItemData:
	var id: StringName = s.inventory.slots.get(SLOT, &"") if s else &""
	return ItemDB.get_item(id) if id != &"" else null


## The warhead loaded in a launcher `item` with `state` (&"" when empty).
static func loaded_warhead(item: ItemData, state: Dictionary) -> StringName:
	if item == null:
		return &""
	if state.has("round"):
		return StringName(state.round)
	return StringName(item.stats.get("loaded", ""))


## The warhead loaded in the launcher `s` carries (&"" for none or empty).
static func loaded_of(s: Soldier) -> StringName:
	return loaded_warhead(launcher_of(s), s.inventory.state_of(SLOT)) if s else &""


## The round items a launcher takes, in the order its "accepts" lists their warheads.
static func round_items(item: ItemData) -> Array[StringName]:
	var out: Array[StringName] = []
	if item == null:
		return out
	for w: String in item.stats.get("accepts", []):
		for id: StringName in ItemDB.all_ids():
			var r := ItemDB.get_item(id)
			if r.type == "ammo" and String(r.stats.get("warhead", "")) == w:
				out.append(id)
	return out


## The round item that holds warhead `w` (&"" if none).
static func round_item_for(w: StringName) -> StringName:
	for id: StringName in ItemDB.all_ids():
		var r := ItemDB.get_item(id)
		if r.type == "ammo" and StringName(r.stats.get("warhead", "")) == w:
			return id
	return &""


## The round items for the launcher `s` carries that they have with them.
static func carried_rounds(s: Soldier) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in round_items(launcher_of(s)):
		if s.inventory.count_of(id) > 0:
			out.append(id)
	return out


## The round the next reload loads: `preferred` if it's carried and fits; else the first
## carried round when empty, or the next kind after the loaded one (R swaps HEAT for HE).
## &"" when there is nothing (else) to load.
static func next_round(s: Soldier, preferred: StringName = &"") -> StringName:
	var item := launcher_of(s)
	if item == null or item.stats.get("disposable", false):
		return &""
	var carried := carried_rounds(s)
	if preferred != &"" and preferred in carried:
		return preferred
	var current := loaded_of(s)
	for id in carried:
		if current == &"" or StringName(ItemDB.get_item(id).stats.get("warhead", "")) != current:
			return id
	return &""


## The attack modes a launcher has (Javelin: top, direct; NLAW: ota, da), first the default.
static func modes(item: ItemData) -> PackedStringArray:
	return PackedStringArray(item.stats.get("modes", [])) if item else PackedStringArray()


## A warhead's short name for messages ("PG-7V HEAT").
static func warhead_name(w: StringName) -> String:
	return String(Warheads.data(w).get("name", String(w))).get_slice(" (", 0)


## The world-space box around a vehicle's (or any body's) collision shapes: where a Javelin
## aims (the roof's middle) and the seeker frames.
static func hull_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	# A body's shapes are its direct children; hit-zone bodies on the vehicles layer under it
	# count too (a soldier riding along doesn't).
	var owners: Array[Node] = [node]
	for child in node.get_children():
		if child is CollisionObject3D and (child as CollisionObject3D).collision_layer & Vehicle.LAYER:
			owners.append(child)
	for owner_node in owners:
		for child in owner_node.get_children():
			var shape := child as CollisionShape3D
			if shape == null or shape.shape == null or shape.disabled:
				continue
			var local: AABB
			if shape.shape is BoxShape3D:
				var size := (shape.shape as BoxShape3D).size
				local = AABB(-size * 0.5, size)
			else:
				local = shape.shape.get_debug_mesh().get_aabb()
			var global := shape.global_transform * local
			box = global if first else box.merge(global)
			first = false
	if first:
		return AABB(node.global_position - Vector3(1, 0, 1), Vector3(2, 2, 2))
	return box


# --- Host: firing -----------------------------------------------------------------------------

## A player asks to fire the launcher they carry from `origin` along `dir` in attack `mode`
## ("" for the default) at `target_path` (a Javelin's locked vehicle, from the level; empty
## for none). Any peer calls it (rpc_id 1).
@rpc("any_peer", "call_local", "reliable")
func request_fire(origin: Vector3, dir: Vector3, mode: String, target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor == null:
		return
	var target: Node3D = null
	if not target_path.is_empty():
		target = Vehicle.find_on(level.get_node_or_null(target_path))  # only ever a vehicle (a lock, a lead)
	var why := server_fire(actor, origin, dir, mode, target)
	if why != "" and not actor.is_ai():
		actor._client_message.rpc_id(actor.owner_peer(), why)


## A player asks to reload the launcher they carry (with `round_id`, or the next round).
@rpc("any_peer", "call_local", "reliable")
func request_reload(round_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor:
		server_reload(actor, round_id)


## A player asks to fire the M320 under the rifle in their hands from `origin` along `dir`
## (Underbarrel.server_fire). Any peer calls it (rpc_id 1).
@rpc("any_peer", "call_local", "reliable")
func request_fire_underbarrel(origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor == null:
		return
	var why := Underbarrel.server_fire(actor, origin, dir)
	if why != "" and not actor.is_ai():
		actor._client_message.rpc_id(actor.owner_peer(), why)


## A player asks to load the M320 under the rifle in their hands with `round_id` (or the next
## grenade: Underbarrel.next_round).
@rpc("any_peer", "call_local", "reliable")
func request_reload_underbarrel(round_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender()
	if actor and Underbarrel.server_reload(actor, round_id) < 0.0 and not actor.is_ai():
		actor._client_message.rpc_id(actor.owner_peer(), "No 40 mm grenades to load" if Underbarrel.carried_rounds(actor).is_empty() else "Can't load now")


func _sender() -> Soldier:
	var lvl := level as CompoundLevel
	if lvl == null:
		return null
	var sender := multiplayer.get_remote_sender_id()
	return lvl.players.get_node_or_null(str(sender if sender != 0 else 1)) as Soldier


## Host only. `s` fires the launcher they carry from `origin` (their eye) along `dir`, in
## attack `mode` ("" for its default), at `target` (a Javelin needs a locked vehicle; an NLAW
## leads one if given). Returns "" when it fired (last_id is the round), else why not.
func server_fire(s: Soldier, origin: Vector3, dir: Vector3, mode := "", target: Node3D = null) -> String:
	if not multiplayer.is_server():
		return "Not the host"
	if s == null or not s.vitals.is_up() or s.inventory.hands != &"" or s.carry_mode != &"" or s.respawn_state == Soldier.RESPAWN_WAITING:
		return "Can't fire now"
	if is_instance_valid(s.vehicle):
		return "Get out to fire it"  # riding: the seat's gun instead (as Soldier._server_fire)
	if not Soldier.usable_point(origin) or not Soldier.usable_direction(dir):
		return "Can't fire now"
	var item := launcher_of(s)
	if item == null:
		return "No launcher"
	var now := Soldier._now()
	if now < s._server_busy_until - 0.1:
		return "Busy"
	var w := loaded_of(s)
	var d := Warheads.data(w)
	if d.is_empty():
		return "Empty - R to load" if not carried_rounds(s).is_empty() else "No rounds"
	dir = dir.normalized()
	if origin.distance_to(s.camera.global_position) > AIM_TRUST_M:
		origin = s.camera.global_position
	var all_modes := modes(item)
	if not mode in all_modes:
		mode = all_modes[0] if not all_modes.is_empty() else ""
	var guidance := String(d.get("guidance", ""))
	if guidance == "javelin":
		var why := lock_problem(s, origin, dir, target, item)
		if why != "":
			return why
	s.server_end_spawn_protection()  # firing ends spawn protection (Soldier)
	# Spend the round: a disposable tube is thrown away, a reloadable one is empty.
	if item.stats.get("disposable", false):
		s.inventory.unequip(SLOT)
	else:
		s.inventory.set_slot_state(SLOT, {"round": ""})
	s._server_busy_until = now + FIRE_BUSY_S
	var right := dir.cross(Vector3.UP).normalized() if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var shoulder := origin + right * SHOULDER_RIGHT_M * (-1.0 if s.left_handed else 1.0) + Vector3.DOWN * SHOULDER_DOWN_M
	var length := float((item.stats.get("size_m", [0, 0, 1.0]) as Array)[2])
	var rear := shoulder - dir * (length * 0.5 + 0.05)
	var muzzle := shoulder + dir * (length * 0.5 + 0.1)
	var blast: Dictionary = item.stats.get("backblast", {})
	last_backblast = Warheads.server_backblast(level as CompoundLevel, s, rear, -dir, blast)
	_client_backblast.rpc(rear, -dir, float(blast.get("injury_m", 10.0)))
	var p := server_launch(s, w, muzzle, dir * float(d.get("speed_mps", 100.0)), mode)
	if p:
		match guidance:
			"javelin":
				p.target = target
				p.javelin_start(muzzle)
			"nlaw":
				p.nlaw_start(muzzle, _nlaw_line(muzzle, dir, target))
	print("[launchers] %s fired %s (%s%s) from (%.1f, %.1f, %.1f)" % [s.display_name(), item.name, warhead_name(w),
		", " + mode if mode != "" else "", origin.x, origin.y, origin.z])
	PeopleLayer.server_noise(s, origin, PeopleLayer.BLAST_HEARD_M)  # people nearby hear it
	return ""


## Host only. Launches a round of warhead `w` fired by `s` from `muzzle` at `vel` (attack
## `mode`, "" for an unguided one) on every peer, never meeting `s` themselves; last_id is
## its id. Returns the host's LauncherProjectile (null if it didn't start). server_fire and
## the M320 (Underbarrel.server_fire) launch through it.
func server_launch(s: Soldier, w: StringName, muzzle: Vector3, vel: Vector3, mode := "") -> LauncherProjectile:
	var id := _next_id
	_next_id += 1
	last_id = id
	_client_launch.rpc({"id": id, "w": String(w), "pos": muzzle, "vel": vel, "mode": mode, "age": 0.0, "flown": 0.0})
	var p := projectiles.get(id) as LauncherProjectile
	if p:
		p.shooter = s
		p.exclude = _rids_of(s)
		p.launch_pos = muzzle
	return p


## Why `s` can't fire a Javelin at `target` from `origin` along `dir` ("" if the lock holds):
## a vehicle that isn't a wreck, within the CLU's lock_range_m, near the aim (LOCK_CONE_DEG)
## and in sight.
func lock_problem(s: Soldier, origin: Vector3, dir: Vector3, target: Node3D, item: ItemData) -> String:
	var v := Vehicle.find_on(target) if target else null
	if v == null or v.wrecked:
		return "No lock"
	var aim := hull_box(v).get_center()
	var to := aim - origin
	if to.length() > float(item.stats.get("lock_range_m", 2500.0)):
		return "Out of range"
	if rad_to_deg(dir.normalized().angle_to(to.normalized())) > LOCK_CONE_DEG:
		return "No lock"
	var query := PhysicsRayQueryParameters3D.create(origin, aim, 1, _rids_of(s))
	var hit := s.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and origin.distance_to(hit.position) < to.length() * 0.95:
		return "No line of sight"
	return ""


## An NLAW's predicted line of sight from `muzzle`: along the aim, or, at a vehicle, at
## where it will be when the missile gets there (its velocity times the flight time).
func _nlaw_line(muzzle: Vector3, dir: Vector3, target: Node3D) -> Vector3:
	var v := Vehicle.find_on(target) if target else null
	if v == null:
		var hit := level.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * 1000.0, Vehicle.LAYER))
		v = Vehicle.find_on(hit.get("collider")) if not hit.is_empty() else null
	if v == null:
		return dir
	var aim := muzzle + dir * muzzle.distance_to(hull_box(v).get_center())
	var t := muzzle.distance_to(aim) / NLAW_LEAD_MPS
	return (aim + v.linear_velocity * t - muzzle).normalized()


## Host only. `s` reloads the launcher they carry with `round_id` (or the next round,
## next_round): it takes the item's reload_s, slowed by wounds, and goes in at the end if
## nothing changed. A loaded round of another kind comes out and back into the kit. Returns
## the seconds it takes, or -1 when there's nothing to load.
func server_reload(s: Soldier, round_id: StringName = &"") -> float:
	if not multiplayer.is_server() or s == null or not s.vitals.is_up():
		return -1.0
	var item := launcher_of(s)
	var now := Soldier._now()
	if item == null or now < s._server_busy_until - 0.1:
		return -1.0
	var choice := next_round(s, round_id)
	if choice == &"":
		return -1.0
	var seconds := float(item.stats.get("reload_s", 4.0)) * s.vitals.reload_mult()
	s._server_busy_until = now + seconds
	var serial := int(_reload_serial.get(s.get_instance_id(), 0)) + 1
	_reload_serial[s.get_instance_id()] = serial
	_finish_reload(s, item.id, s.inventory.slot_revision(SLOT), choice, seconds, serial)
	return seconds


## The round goes in only if the very launcher being reloaded is still on the shoulder: not
## another of the same model picked up meanwhile (`rev`, Inventory.slot_revision; audit A2-02).
func _finish_reload(s: Soldier, launcher_id: StringName, rev: int, choice: StringName, seconds: float, serial: int) -> void:
	await get_tree().create_timer(seconds).timeout
	if not is_instance_valid(s) or int(_reload_serial.get(s.get_instance_id(), 0)) != serial or not s.vitals.is_up() \
			or s.inventory.slots.get(SLOT, &"") != launcher_id or s.inventory.slot_revision(SLOT) != rev:
		return
	var w := StringName(ItemDB.get_item(choice).stats.get("warhead", ""))
	var current := loaded_of(s)
	if current == w or not s.inventory.remove_one(choice):
		return
	s.inventory.set_slot_state(SLOT, {"round": String(w)})
	if current != &"":
		var back := round_item_for(current)  # the round that was in comes out
		if back != &"" and s.inventory.take(back) < 1:
			s._server_spawn_in_front(back)


static func _rids_of(s: Soldier) -> Array[RID]:
	var out: Array[RID] = [s.get_rid()]
	for child in s.get_children():
		if child is CollisionObject3D:
			out.append((child as CollisionObject3D).get_rid())
	var gear := s.get_node_or_null(^"Gear") as GearRig
	if gear:
		out.append_array(gear.armor_rids())
	return out


# --- Host: flight ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or projectiles.is_empty():
		return
	for id: int in projectiles.keys():
		var p := projectiles[id] as LauncherProjectile
		if not is_instance_valid(p):
			projectiles.erase(id)
			continue
		var res := p.server_step(delta)
		if not res.is_empty():
			_server_end(p, res)
	_track_cd -= delta
	if _track_cd <= 0.0:
		_track_cd = TRACK_S
		for id: int in projectiles:
			var p := projectiles[id] as LauncherProjectile
			if is_instance_valid(p):
				_client_track.rpc(id, p.global_position, p.velocity, p.age)


func _server_end(p: LauncherProjectile, res: Dictionary) -> void:
	var lvl := level as CompoundLevel
	var how := "burst"
	var burst := {}
	var pos: Vector3 = res.position
	var dir: Vector3 = res.get("direction", p.velocity.normalized())
	# Whoever fired it may have left (a player who quit) while it flew: a freed shooter must
	# never reach a typed Node argument.
	var shooter: Node = null
	if is_instance_valid(p.shooter):
		shooter = p.shooter
	var collider: Object = res.get("hit") if is_instance_valid(res.get("hit")) else null
	if res.has("dud"):
		how = "dud"  # inside its arming distance: no fuse, just a heavy rocket
		var body := Warheads.body_of(collider)
		var vitals := body.get_node_or_null(^"Vitals") as Vitals if body else null
		if vitals and not vitals.is_dead():
			Harm.note_hit(body, shooter)
			var part: StringName = (collider as Node).get_meta(&"body_part", Vitals.CHEST) if collider is Node else Vitals.CHEST
			vitals.server_hit(part, {"round_class": Vitals.FULL_POWER, "position": pos, "direction": dir, "distance": p.travelled})
	elif res.has("expired"):
		if p.data.get("self_destruct", false):
			burst = Warheads.server_burst(lvl, p.warhead, pos, dir, null, shooter)
		else:
			how = "lost"
	elif String(p.data.get("kind", "")) == "smoke":
		# A smoke grenade (the M320's M714): no burst, a cloud where it lands (SmokeCloud), just
		# off what it met.
		how = "smoke"
		if lvl:
			lvl.server_spawn_smoke(pos - dir * 0.15, String(p.data.get("smoke_colour", "white")))  # (its seed and wind picked here: the same cloud on every peer)
	else:
		burst = Warheads.server_burst(lvl, p.warhead, pos, dir, collider, shooter, bool(res.get("top_attack", false)))
	results[p.id] = {"how": how, "position": pos, "direction": dir, "top_attack": bool(res.get("top_attack", false)),
		"max_height": p.max_height, "burst": burst, "shooter": shooter, "flown": p.travelled, "passed": p.passed.duplicate()}
	while results.size() > RESULTS_KEPT:
		results.erase(results.keys()[0])
	print("[launchers] round %d (%s) %s at (%.1f, %.1f, %.1f) after %.0f m" % [p.id, warhead_name(p.warhead), how, pos.x, pos.y, pos.z, p.travelled])
	_client_end.rpc(p.id, pos, String(p.warhead), how)


func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for id: int in projectiles:
		var p := projectiles[id] as LauncherProjectile
		if is_instance_valid(p):
			_client_launch.rpc_id(peer, {"id": id, "w": String(p.warhead), "pos": p.global_position, "vel": p.velocity,
				"mode": p.mode, "age": p.age, "flown": p.travelled})


# --- Every peer -----------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _client_launch(rec: Dictionary) -> void:
	var id := int(rec.id)
	if projectiles.has(id):
		return
	var p := LauncherProjectile.new()
	p.setup(rec)
	add_child(p)
	p.global_position = rec.pos
	p.look_along(rec.vel)
	projectiles[id] = p
	launched += 1
	if float(rec.get("age", 0.0)) <= 0.0:
		_fireball(rec.pos, 0.6, Color(1.0, 0.8, 0.45), 0.12)  # the launch flash


@rpc("authority", "call_remote", "unreliable_ordered")
func _client_track(id: int, pos: Vector3, vel: Vector3, age: float) -> void:
	var p := projectiles.get(id) as LauncherProjectile
	if is_instance_valid(p):
		p.global_position = pos
		p.velocity = vel
		p.age = age


@rpc("authority", "call_local", "reliable")
func _client_end(id: int, pos: Vector3, w: String, how: String) -> void:
	var p := projectiles.get(id) as LauncherProjectile
	projectiles.erase(id)
	if is_instance_valid(p):
		p.queue_free()
	ends.append({"id": id, "w": w, "pos": pos, "how": how})
	match how:
		"burst":
			var d := Warheads.data(w)
			var kg := maxf(float(d.get("blast_kg", 0.5)), 0.05)
			var thermo := String(d.get("kind", "")) == "thermobaric"
			_fireball(pos, 2.4 * pow(kg, 1.0 / 3.0) * (1.8 if thermo else 1.0), Color(1.0, 0.55, 0.2), 0.5 if thermo else 0.35)
			_dust(pos, Vector3.UP, 2.0 * pow(kg, 1.0 / 3.0), 2.5)
		"dud", "smoke":
			_dust(pos, Vector3.UP, 0.6, 1.2)


## The dust and smoke of a backblast leaving `rear` along `back`, reaching `reach` metres.
@rpc("authority", "call_local", "reliable")
func _client_backblast(rear: Vector3, back: Vector3, reach: float) -> void:
	backblasts += 1
	_fireball(rear, 0.5, Color(1.0, 0.75, 0.4), 0.1)
	_dust(rear, back, minf(reach * 0.2, 5.0), 2.0)


func _process(delta: float) -> void:
	_rig_cd -= delta
	if _rig_cd > 0.0:
		return
	_rig_cd = RIG_SCAN_S
	for n in get_tree().get_nodes_in_group(&"combatants"):
		var s := n as Soldier
		if s and s.inventory.slots.get(SLOT, &"") != &"" and s.get_node_or_null(^"LauncherRig") == null and s.model:
			s.add_child(LauncherRig.new(s))


func _fireball(pos: Vector3, size: float, colour: Color, life: float) -> void:
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
	light.light_energy = 6.0
	light.omni_range = 4.0 + size * 4.0
	ball.add_child(light)
	add_child(ball)
	ball.global_position = pos
	var tween := ball.create_tween().set_parallel()
	tween.tween_property(ball, "scale", Vector3.ONE * size, life)
	tween.tween_property(material, "albedo_color:a", 0.0, life)
	tween.tween_property(light, "light_energy", 0.0, life)
	tween.chain().tween_callback(ball.queue_free)


## A spreading cloud of dust from `pos` along `dir` (a backblast, a burst's smoke).
func _dust(pos: Vector3, dir: Vector3, reach: float, life: float) -> void:
	for i in 5:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.62, 0.57, 0.48, 0.55)
		var sphere := SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.8
		sphere.material = material
		var puff := MeshInstance3D.new()
		puff.mesh = sphere
		add_child(puff)
		puff.global_position = pos
		var spread := Vector3(randf_range(-0.3, 0.3), randf_range(-0.1, 0.3), randf_range(-0.3, 0.3))
		var goal := pos + (dir.normalized() + spread).normalized() * reach * (0.4 + 0.15 * i)
		var tween := puff.create_tween().set_parallel()
		tween.tween_property(puff, "global_position", goal, life * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(puff, "scale", Vector3.ONE * (1.5 + reach * 0.5), life)
		tween.tween_property(material, "albedo_color:a", 0.0, life)
		tween.chain().tween_callback(puff.queue_free)
