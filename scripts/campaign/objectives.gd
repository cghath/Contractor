class_name Objectives
extends Node
## The objectives of the contracts in the current deployment (wave 4, W10): host-owned,
## replicated to every peer and late joiner, shown in the HUD list (ObjectivesPanel) and on
## the map (markers()). It lives under the Contracts autoload (/root/Contracts/Objectives).
##
## An objective is a JSON-safe Dictionary: "oid", "cid" (its contract), "kind" (KINDS),
## "text", "state" (ACTIVE, DONE, FAILED), "optional", "bonus_share", "progress" (a short
## readout), "pos" ([x, y, z] for the map) and "params" (from the module's site).
##
## How each kind completes (the hooks other parts call are on this node, host only):
## - CLEAR_AREA: no hostile left standing in "rect" ([x, z, w, d] metres). Checked here
##   twice a second once the level is up; armed once a hostile has been seen there (or after
##   "clear_arm_timeout_s" with none), so it can't complete before the enemy spawns.
## - EXTRACT_ITEM: an item in "items" (or tagged one of "tags") is carried out:
##   server_items_out(items), from extraction (Contracts.server_end_deployment) or a mid-zone
##   loot evacuation.
## - DELIVER_HVT: server_hvt_delivered(hvt_id, alive) (the people agent's HVT calls it);
##   server_hvt_lost(hvt_id) fails it.
## - DESTROY_CACHE: the voxels in "box" ([[x, y, z], [x, y, z]] metres) are mostly gone
##   (less than "cache_destroyed_share" of the site's authored "voxels" left; frags and
##   explosives carve them), or server_cache_destroyed(cache_id), or a charge placed with
##   server_place_charge. The share is measured against the authored count, never against
##   what stands at deploy: a zone keeps its voxel damage, so a cache box already carved
##   (blown on an earlier contract and saved) must not count as destroyed on the next one.
##   With no "voxels" in the site, or a box already under the threshold when it is first
##   read, the voxel check stays off and only the hook or a charge completes it (a world or
##   4B pass that restores a zone rebuilds the cache).

signal changed

const ACTIVE := "active"
const DONE := "done"
const FAILED := "failed"
const CLEAR_AREA := "clear_area"
const EXTRACT_ITEM := "extract_item"
const DELIVER_HVT := "deliver_hvt"
const DESTROY_CACHE := "destroy_cache"
const KINDS: Array[String] = [CLEAR_AREA, EXTRACT_ITEM, DELIVER_HVT, DESTROY_CACHE]
## The breaching charge item that destroys a cache when placed on it.
const CHARGE_ITEM := &"breaching_charge"
const POLL_S := 0.5

## Every objective of the deployment (every peer; the host's is the truth).
var list: Array = []
var _poll := 0.0
var _armed := {}       # host: oid -> true once a CLEAR_AREA has seen a hostile (or timed out)
var _first_poll := {}  # host: oid -> msec it was first checked
var _cache_off := {}   # host: oid -> true when the voxel check is off (no baseline, or carved before deploy)


## Objectives from a contract's templates, placed at its module's sites. Sites are in the
## module's own metres; `origin` is where the module sits in the level (a streamed module in
## a world-scale zone), added to every position, rect and box.
static func from_contract(contract: Dictionary, origin := Vector3.ZERO) -> Array:
	var out: Array = []
	var module_id := String(contract.get("module", ""))
	var templates: Array = contract.get("objectives", [])
	for i in templates.size():
		var t: Dictionary = templates[i]
		var site := placed_site(MissionRegistry.site(module_id, String(t.get("site", ""))), origin)
		var obj := {
			"oid": "%s_o%d" % [contract.get("cid", "c"), i + 1], "cid": contract.get("cid", ""), "kind": t.get("kind", ""),
			"text": t.get("text", ""), "state": ACTIVE, "optional": bool(t.get("optional", false)),
			"bonus_share": float(t.get("bonus_share", 0.0)), "progress": "", "params": site, "pos": site_pos(site),
		}
		out.append(obj)
	return out


## A site moved by `origin` (metres).
static func placed_site(site: Dictionary, origin: Vector3) -> Dictionary:
	var out := site.duplicate(true)
	if origin == Vector3.ZERO:
		return out
	var shift := func(p: Array) -> Array: return [float(p[0]) + origin.x, float(p[1]) + origin.y, float(p[2]) + origin.z]
	if out.has("pos"):
		out.pos = shift.call(out.pos)
	if out.has("rect"):
		var r: Array = out.rect
		out.rect = [float(r[0]) + origin.x, float(r[1]) + origin.z, r[2], r[3]]
	if out.has("box"):
		out.box = [shift.call(out.box[0]), shift.call(out.box[1])]
	return out


## Where a site sits on the map: a rect's or box's centre, or its "pos".
static func site_pos(site: Dictionary) -> Array:
	if site.has("pos"):
		return (site.pos as Array).duplicate()
	if site.has("rect"):
		var r: Array = site.rect
		return [float(r[0]) + float(r[2]) * 0.5, 0.0, float(r[1]) + float(r[3]) * 0.5]
	if site.has("box"):
		var a: Array = site.box[0]
		var b: Array = site.box[1]
		return [(float(a[0]) + float(b[0])) * 0.5, (float(a[1]) + float(b[1])) * 0.5, (float(a[2]) + float(b[2])) * 0.5]
	return [0.0, 0.0, 0.0]


func _ready() -> void:
	Net.peer_joined.connect(_on_peer_joined)


# --- Reading (every peer) ----------------------------------------------------------------

func get_objective(oid: String) -> Dictionary:
	for o: Dictionary in list:
		if o.oid == oid:
			return o
	return {}


func for_contract(cid: String) -> Array:
	return list.filter(func(o: Dictionary) -> bool: return o.cid == cid)


func active() -> Array:
	return list.filter(func(o: Dictionary) -> bool: return o.state == ACTIVE)


## Whether every required objective of a contract is done.
func contract_done(cid: String) -> bool:
	var mine := for_contract(cid).filter(func(o: Dictionary) -> bool: return not o.optional)
	return not mine.is_empty() and mine.all(func(o: Dictionary) -> bool: return o.state == DONE)


## Map markers for the map agent: {"oid", "pos": Vector3, "text", "state", "kind", "optional"}.
func markers() -> Array:
	var out: Array = []
	for o: Dictionary in list:
		var p: Array = o.get("pos", [0, 0, 0])
		out.append({"oid": o.oid, "pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "text": o.text, "state": o.state,
			"kind": o.kind, "optional": o.optional})
	return out


## One line per objective, for the HUD and the debrief.
static func line(o: Dictionary) -> String:
	var mark: String = {"active": "[ ]", "done": "[x]", "failed": "[-]"}.get(o.get("state", ""), "[ ]")
	var progress := String(o.get("progress", ""))
	return "%s %s%s%s" % [mark, o.get("text", ""), " (%s)" % progress if progress != "" and o.get("state") == ACTIVE else "",
		" FAILED" if o.get("state") == FAILED else ""]


# --- Host --------------------------------------------------------------------------------

## Host: the deployment's objectives (replaces any before).
func server_begin(objectives: Array) -> void:
	list = objectives.duplicate(true)
	_armed.clear()
	_first_poll.clear()
	_cache_off.clear()
	_commit()


## Host: adds objectives (a contract taken mid-deployment).
func server_add(objectives: Array) -> void:
	list.append_array(objectives.duplicate(true))
	_commit()


## Host: no deployment, no objectives.
func server_clear() -> void:
	list = []
	_commit()


## Host: puts back the objectives of a saved deployment (Contracts, on campaign load).
func server_restore(objectives: Array) -> void:
	list = objectives.duplicate(true)
	_armed.clear()
	_first_poll.clear()
	_cache_off.clear()
	_commit(false)


func server_set_state(oid: String, state: String, progress := "") -> void:
	var o := get_objective(oid)
	if o.is_empty() or (o.state == state and o.progress == progress):
		return
	o.state = state
	o.progress = progress
	if state != ACTIVE:
		print("[objectives] %s: %s" % [state, o.text])
	_commit()


## Host: every objective of a contract still open fails (voided, aborted, lapsed).
func server_fail_contract(cid: String) -> void:
	for o: Dictionary in for_contract(cid):
		if o.state == ACTIVE:
			o.state = FAILED
	_commit()


## Host: items carried out (extraction, or loot evacuated mid-zone): [{"id", "count"}].
## Completes EXTRACT_ITEM objectives they satisfy.
func server_items_out(items: Array) -> void:
	for o: Dictionary in active():
		if o.kind != EXTRACT_ITEM:
			continue
		for entry: Dictionary in items:
			if item_matches(o.params, StringName(entry.get("id", ""))):
				server_set_state(o.oid, DONE)
				break


static func item_matches(params: Dictionary, item_id: StringName) -> bool:
	if String(item_id) in params.get("items", []):
		return true
	var item: ItemData = ItemDB.get_item(item_id) if ItemDB.has_item(item_id) else null
	if item:
		for tag: Variant in params.get("tags", []):
			if String(tag) in item.tags:
				return true
	return false


## Host: an HVT was delivered (to extraction or a vehicle seat that extracts). An HVT
## objective with that "hvt" id (or none) completes, or fails if they arrive dead.
func server_hvt_delivered(hvt_id: String, alive := true) -> void:
	for o: Dictionary in active():
		if o.kind == DELIVER_HVT and String(o.params.get("hvt", hvt_id)) == hvt_id:
			server_set_state(o.oid, DONE if alive else FAILED)


## Host: an HVT died or got away for good.
func server_hvt_lost(hvt_id: String) -> void:
	for o: Dictionary in active():
		if o.kind == DELIVER_HVT and String(o.params.get("hvt", hvt_id)) == hvt_id:
			server_set_state(o.oid, FAILED)


## Host: a cache was destroyed (by whatever means the caller saw).
func server_cache_destroyed(cache_id: String) -> void:
	for o: Dictionary in active():
		if o.kind == DESTROY_CACHE and String(o.params.get("cache", cache_id)) == cache_id:
			server_set_state(o.oid, DONE)


## Host: `soldier` places a breaching charge on the cache of objective `oid`: it must carry
## one and stand within "charge_reach_m" of the cache. After "charge_fuse_s" the charge goes
## off (a frag blast plus a wide carve) and the cache counts as destroyed. Returns whether
## the charge was placed.
func server_place_charge(soldier: Soldier, oid: String) -> bool:
	var o := get_objective(oid)
	if o.is_empty() or o.kind != DESTROY_CACHE or o.state != ACTIVE or soldier == null:
		return false
	var box := _box_of(o)
	var centre := box.get_center()
	var reach := MissionRegistry.setting_f("charge_reach_m", 3.0) + box.size.length() * 0.5
	if soldier.global_position.distance_to(centre) > reach or not soldier.inventory.remove_one(CHARGE_ITEM):
		return false
	o.progress = "charge set"
	_commit()
	get_tree().create_timer(MissionRegistry.setting_f("charge_fuse_s", 5.0)).timeout.connect(_detonate.bind(oid, centre))
	return true


func _detonate(oid: String, centre: Vector3) -> void:
	var level := CompoundLevel.current(self)
	if level:
		Throwables.server_detonate(level, "frag", centre)
		level.voxel_world.server_blast(centre, MissionRegistry.setting_f("charge_radius_m", 1.6))
	var o := get_objective(oid)
	if not o.is_empty() and o.state == ACTIVE:
		server_set_state(oid, DONE)


static func _box_of(o: Dictionary) -> AABB:
	var b: Array = o.params.get("box", [[0, 0, 0], [0, 0, 0]])
	var a := Vector3(float(b[0][0]), float(b[0][1]), float(b[0][2]))
	var c := Vector3(float(b[1][0]), float(b[1][1]), float(b[1][2]))
	return AABB(a.min(c), (c - a).abs())


func _process(delta: float) -> void:
	if list.is_empty() or not multiplayer.is_server():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_S
	# Any level in the "level" group with a voxel_world will do (the compound, a zone level).
	var level := get_tree().get_first_node_in_group(&"level")
	if level == null:
		return
	var world := level.get(&"voxel_world") as VoxelWorld
	for o: Dictionary in active():
		match o.kind:
			CLEAR_AREA:
				_check_clear(o)
			DESTROY_CACHE:
				if world:
					_check_cache(o, world)


## Hostiles still standing in a CLEAR_AREA's rect.
func hostiles_in(o: Dictionary) -> int:
	var r: Array = o.params.get("rect", [0, 0, 0, 0])
	var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var n := 0
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s and s.faction == &"hostile" and not s.is_queued_for_deletion() and s.vitals.is_up() \
				and rect.has_point(Vector2(s.global_position.x, s.global_position.z)):
			n += 1
	return n


func _check_clear(o: Dictionary) -> void:
	var left := hostiles_in(o)
	if left > 0:
		_armed[o.oid] = true
	elif Time.get_ticks_msec() - int(_first_poll.get(o.oid, Time.get_ticks_msec())) > MissionRegistry.setting_f("clear_arm_timeout_s", 20.0) * 1000.0:
		_armed[o.oid] = true
	if not _first_poll.has(o.oid):
		_first_poll[o.oid] = Time.get_ticks_msec()
	if not _armed.has(o.oid):
		return
	if left == 0:
		server_set_state(o.oid, DONE)
	else:
		server_set_state(o.oid, ACTIVE, "%d hostile%s left" % [left, "" if left == 1 else "s"])


## Solid voxels in `box` (metres, level space), or -1 while that part of the world can't be
## read yet. The authored "voxels" of a cache site is this count on the pristine module.
static func solid_count(world: VoxelWorld, box: AABB) -> int:
	var begin := Vector3i((world.to_local(box.position) / VoxelWorld.VOXEL_SIZE).round())
	var end := Vector3i((world.to_local(box.end) / VoxelWorld.VOXEL_SIZE).round())
	var size := (end - begin).abs()
	if size.x * size.y * size.z <= 0 or not world.is_area_readable(AABB(Vector3(begin), Vector3(size))):
		return -1
	var solid := 0
	for b: int in world.solid_voxels(begin, size):
		solid += b
	return solid


func _check_cache(o: Dictionary, world: VoxelWorld) -> void:
	if _cache_off.has(o.oid):
		return
	var full := int(o.params.get("voxels", 0))
	if full <= 0:
		_cache_off[o.oid] = true  # no authored baseline: the hook or a charge only
		return
	var solid := solid_count(world, _box_of(o))
	if solid < 0:
		return
	var share := float(solid) / float(full)
	var threshold := MissionRegistry.setting_f("cache_destroyed_share", 0.4)
	if not _first_poll.has(o.oid):
		_first_poll[o.oid] = Time.get_ticks_msec()
		if share < threshold:
			# Carved before this deployment (the zone kept its damage): the voxels can't tell.
			_cache_off[o.oid] = true
			print("[objectives] %s: the cache site is already %d%% gone; only a charge or the hook completes it" % [o.text, 100 - roundi(share * 100.0)])
			return
	if share < threshold:
		server_set_state(o.oid, DONE)
	elif share < 0.999 and o.progress != "charge set":
		server_set_state(o.oid, ACTIVE, "%d%% intact" % roundi(minf(share, 1.0) * 100.0))


# --- Replication -------------------------------------------------------------------------

func _commit(save := true) -> void:
	changed.emit()
	if not multiplayer.is_server():
		return
	if save:
		Contracts.store_objectives(list)
	if _online():
		_sync.rpc(list)


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server() and not list.is_empty():
		_sync.rpc_id(id, list)


@rpc("authority", "call_remote", "reliable")
func _sync(objectives: Array) -> void:
	list = objectives
	changed.emit()


func _online() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
