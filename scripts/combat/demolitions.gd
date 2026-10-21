class_name Demolitions
extends Node
## The player's demolitions (Captain's list, 2026-10-20, "Not built yet: Weapons and items"):
## demo blocks and det cord, firing devices (a clacker on a wire, a radio remote), thermite,
## claymores, pressure AP mines and chem lights. Every item is data (data/items.json: its stats'
## "place" kind, "arm" modes and numbers, all Proposed); this node places, arms, fires and shows
## them. It learns from how milsims handle placed explosives (a ghost on the surface, then an arming
## choice) and builds on the breaching charge's placing (Charges).
##
## - Demo block ("demo"): placed on a surface or on a target (a vehicle, a fuel store, a mast, a
##   wall), within PLACE_REACH_M. Armed on a timer ("timer:N"), on a detonator ("remote": fired by
##   whoever placed it squeezing a clacker or keying a radio remote within its range), or on det
##   cord ("cord": tied to the placer's nearest block or claymore within the cord's "link_m", one
##   coil each; when any one of a chain goes off, the whole chain goes). Its blast: a big carve in
##   the voxels ("carve_m"), overpressure and fragments on people (Warheads.server_people with the
##   block's "blast_kg"), a hit on the vehicle it's on ("contact_mult" times its blast: a charge in
##   contact couples into a hull far better than a burst beside it) and a lesser one on vehicles
##   close by, and the objectives hear of it like a charge (Objectives.server_charge_blast: a
##   sabotage target or cache it's on is destroyed).
## - Thermite ("thermite"): placed like a block; lights after "fuse_s" and burns "burn_s" (a bright
##   flickering light and a hiss on every peer), then whatever it's on is done for: a vehicle's
##   engine burnt out and the vehicle on fire (Vehicle.server_set_zone, server_start_fire: its
##   public API), a static gun wrecked (its hull), a cache or sabotage target destroyed. People
##   within "burn_m" are burnt; the blast is small.
## - Claymore ("claymore"): set on the ground facing where the placer looks; fired by a detonator
##   ("remote"), by anyone walking into its tripwire ("trip": "trip_w_m" wide, "trip_out_m" in front,
##   live after "arm_s"), or on det cord. Its fragments fly in a fan ("cone_deg" wide, "up_deg"
##   up and down) out to "frag_m" in front (Warheads.frag_body: walls, armour and bodies stop them);
##   behind and beside it only the blast close by. Friendly fire on.
## - AP mine ("mine"): buried in the ground in front of the placer; live after "arm_s", then a foot
##   within "trigger_m" (friend or foe) or a vehicle's footprint over it sets it off: the leg that
##   stepped on it is wrecked, people close by take its blast and fragments, a vehicle its blast.
##   Our side's mines and claymores are marked on the map (MapMarkers, "field"); hazards() lists
##   them for the AI (avoiding them is F-120).
## - Chem light ("chemlight", a throwable): thrown or lobbed like a grenade (Grenade), it lies where
##   it stops (or rides whoever it landed on) and glows in its colour for "life_min" minutes, much
##   brighter through night vision (glow(): NVG_GAIN); an IR one shows only through night vision.
##
## One node per level, "Demolitions", on every peer (CompoundLevel._ready). The host decides
## everything; every peer and late joiner builds the same records (records, _client_add). What's
## placed is saved with the zone (GameState.demolitions: to_save, server_restore) and put back when
## the squad returns. Item models are placeholder boxes in make_visual (the art pass can replace them).

const NODE_NAME := "Demolitions"
const GROUP := &"demolitions"
const PLACE_REACH_M := 2.5
## Mines and claymores need ground this flat (the surface normal's y).
const FLAT_Y := 0.7
## Picking a placed item up again: within this of it.
const PICKUP_M := 2.5
## Kinds (an item's stats "place"; a chem light's "throwable").
const DEMO := "demo"
const THERMITE := "thermite"
const CLAYMORE := "claymore"
const MINE := "mine"
const CHEMLIGHT := "chemlight"
## Arming modes (an item's stats "arm"): "timer:<seconds>", REMOTE, CORD, TRIP, PRESSURE.
const REMOTE := "remote"
const CORD := "cord"
const TRIP := "trip"
const PRESSURE := "pressure"
const DET_CORD := &"det_cord"
## Kinds det cord ties together.
const LINKABLE: Array[String] = [DEMO, CLAYMORE]
## Host: triggers (tripwires, mines) are checked this often.
const TICK_S := 0.1
## Proposed: a tripwire catches a body within this of the wire (flat), a vehicle's footprint grown
## by this sets off a mine under it.
const TRIP_CATCH_M := 0.35
const WHEEL_MARGIN_M := 0.2
## Proposed: vehicles near a demo block's burst (not the one it's on) take its blast falling off
## to nothing at this distance.
const NEAR_VEHICLE_M := 4.0
## Chem lights (Proposed): their light, and how much brighter through night vision (an image
## intensifier makes a glow stick a beacon). They dim over their last FADE_S.
const GLOW_ENERGY := 0.6
const GLOW_RANGE_M := 3.5
const NVG_GAIN := 4.0
const NVG_RANGE_MULT := 2.5
const FADE_S := 60.0
const GLOW_COLOURS := {"green": Color(0.35, 1.0, 0.45), "red": Color(1.0, 0.22, 0.15), "blue": Color(0.3, 0.55, 1.0),
	"yellow": Color(1.0, 0.9, 0.3), "ir": Color(0.85, 1.0, 0.85)}
## Thermite's light while it burns (every peer).
const BURN_ENERGY := 7.0
const BURN_RANGE_M := 10.0
## Its hiss (Sfx "thermite", 2 s) plays again this often while it burns.
const HISS_S := 1.9

## Every peer: id -> {"id", "item", "kind", "path" (the node it rides, from the level; "" for the
## level), "xform" (its transform in that node, packed), "world" (its world transform when placed),
## "arm", "link" (the id it's corded to, ""), "by" (who placed it), "burning", "life_s" (a chem
## light's left when sent), "burn_s" (a burning thermite's left when sent)}.
var records: Dictionary = {}
## Host: what went off, in order: {"id", "item", "kind", "pos", "by"} (tests, the session log).
var fired: Array[Dictionary] = []

var level: Node3D
var _next_id := 1
var _tick := 0.0
var _due := {}       # host: id -> time a timer fires or a thermite lights
var _burn_end := {}  # host: id -> time a burning thermite is done
var _arms_at := {}   # host: id -> time a mine or tripwire goes live
var _expire := {}    # host: id -> time a chem light goes out
var _owner := {}     # host: id -> owner key (owner_key) of who placed it
var _faction := {}   # host: id -> the placer's faction
var _placer := {}    # host: id -> the placer's node (Harm: whose blast)
var _markers := {}   # host: id -> map marker id
var _last_pos := {}  # host: id -> where it was last seen (what it rode may be gone)
var _received := {}  # every peer: id -> local time its record arrived (chem lights: life left)


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	level = get_parent() as Node3D
	add_to_group(GROUP)
	Net.peer_joined.connect(_on_peer_joined)


## The demolitions node of the level `from` is in (or null).
static func of(from: Node) -> Demolitions:
	var lvl := CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Demolitions if lvl else null


# --- What an item is (pure) ----------------------------------------------------------------

## The kind of item `id` (DEMO, THERMITE, CLAYMORE, MINE, CHEMLIGHT), or "".
static func kind_of(id: StringName) -> String:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	if item == null:
		return ""
	if item.stats.has("place"):
		return String(item.stats.place)
	return CHEMLIGHT if String(item.stats.get("throwable", "")) == CHEMLIGHT else ""


## Whether `id` is placed with the placing ghost (G): a block, thermite, a claymore or a mine.
static func is_placeable(id: StringName) -> bool:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	return item != null and item.stats.has("place")


## Whether `id` is a firing device (a clacker, a radio remote).
static func is_detonator(id: StringName) -> bool:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	return item != null and item.stats.has("detonator")


## The arming modes item `id` offers, in the order R cycles them ([""] for none: thermite).
static func arm_modes(id: StringName) -> Array[String]:
	var out: Array[String] = []
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	for m: Variant in (item.stats.get("arm", []) if item else []):
		out.append(String(m))
	if out.is_empty():
		out.append("")
	return out


## A timer mode's seconds ("timer:30" -> 30), or -1 for any other mode.
static func timer_s(mode: String) -> float:
	return float(mode.get_slice(":", 1)) if mode.begins_with("timer:") else -1.0


## How arming mode `mode` reads on the HUD.
static func arm_label(mode: String) -> String:
	if mode.begins_with("timer:"):
		return "timer %d s" % roundi(timer_s(mode))
	return {REMOTE: "detonator (clacker or remote)", CORD: "det cord to your nearest charge", TRIP: "tripwire",
		PRESSURE: "pressure", "": "lights on a short fuse"}.get(mode, mode)


## Who owns what `s` places (the detonator it may fire): a player's peer, an AI's node name.
static func owner_key(s: Node) -> String:
	return String(s.name) if s else ""


## Whether a fragment flying along `to` from a claymore facing `forward` is in its fan:
## within `cone_deg` across (flat) and `up_deg` up or down.
static func in_cone(forward: Vector3, to: Vector3, cone_deg: float, up_deg: float) -> bool:
	var flat_f := Vector3(forward.x, 0.0, forward.z)
	var flat_t := Vector3(to.x, 0.0, to.z)
	if flat_f.length() < 0.01 or flat_t.length() < 0.01:
		return false
	if rad_to_deg(flat_f.angle_to(flat_t)) > cone_deg * 0.5:
		return false
	return absf(rad_to_deg(atan2(to.y, flat_t.length()))) <= up_deg


## A chem light of item `id`'s light for a viewer whose NVG is `nvg_on`, `left_s` seconds from
## going out: {"visible", "energy", "range", "colour"}. Through night vision it's NVG_GAIN times
## brighter and reaches NVG_RANGE_MULT further; an IR one shows only then.
static func glow(id: StringName, nvg_on: bool, left_s := INF) -> Dictionary:
	var item := ItemDB.get_item(id) if ItemDB.has_item(id) else null
	var colour_name := String(item.stats.get("glow", "green")) if item else "green"
	var ir := colour_name == "ir"
	var fade := clampf(left_s / FADE_S, 0.3, 1.0) if left_s < FADE_S else 1.0
	return {"visible": nvg_on or not ir, "energy": GLOW_ENERGY * fade * (NVG_GAIN if nvg_on else 1.0),
		"range": GLOW_RANGE_M * (NVG_RANGE_MULT if nvg_on else 1.0), "colour": GLOW_COLOURS.get(colour_name, Color.WHITE)}


# --- Where it goes (every peer: the ghost; the host: the check) -----------------------------

## Where `actor` can put item `id` looking from `from` along `dir`: Charges.placement's
## {"ok", "pos", "normal", "target", "why"}, with a mine or claymore wanting flat ground (not a
## person or a vehicle).
static func placement(actor: Soldier, from: Vector3, dir: Vector3, id: StringName) -> Dictionary:
	var spot := Charges.placement(actor, from, dir)
	var kind := kind_of(id)
	var on: Node = spot.target
	if spot.ok and on != null and (on == actor or on.get_parent() == actor):
		spot.ok = false  # his own helmet or gear (looking up, or down at his kit)
		spot.why = "Not on yourself"
	elif spot.ok and (kind == MINE or kind == CLAYMORE):
		if spot.target != null:
			spot.ok = false
			spot.why = "Set it on the ground"
		elif (spot.normal as Vector3).y < FLAT_Y:
			spot.ok = false
			spot.why = "Needs flat ground"
	return spot


## Item `id`'s transform at `spot` (placement) for a placer looking along `look`: a block or
## thermite flat against the surface (Charges.surface_transform); a claymore standing on the
## ground facing the look; a mine buried flush with the ground.
static func place_transform(id: StringName, spot: Dictionary, look: Vector3) -> Transform3D:
	var kind := kind_of(id)
	var pos: Vector3 = spot.pos
	var normal: Vector3 = spot.normal
	if kind != MINE and kind != CLAYMORE:
		return Charges.surface_transform(pos, normal, look)
	var t := Charges.surface_transform(pos, normal, look)
	t.origin = pos
	return t


# --- Host ---------------------------------------------------------------------------------

## A player asks to place item `id` looking from `from` along `dir`, armed `arm` (one of its
## arm_modes). The host checks it again from their body. Any peer calls it (rpc_id 1).
@rpc("any_peer", "call_local", "reliable")
func request_place(id: String, from: Vector3, dir: Vector3, arm: String) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender_body()
	var item := StringName(id)
	if actor == null or not is_placeable(item) or not actor.vitals.is_up() or actor.inventory.count_of(item) <= 0 or actor.carry_mode != &"":
		return
	if not arm in arm_modes(item):
		return
	if not Soldier.usable_point(from) or from.distance_to(actor.camera.global_position) > 1.0:
		from = actor.camera.global_position  # don't trust a far-off eye
	if not Soldier.usable_direction(dir):
		return
	var spot := placement(actor, from, dir, item)
	if not spot.ok:
		_tell(actor, String(spot.why))
		return
	var xform := place_transform(item, spot, dir)
	var why := place_problem(actor, item, xform.origin, arm)
	if why != "":
		_tell(actor, why)
		return
	server_place(actor, item, xform, spot.target, arm)


## Why `by` can't place `item` at `at` armed `arm` (""): det cord wants a coil and one of their
## blocks or claymores within its reach.
func place_problem(by: Soldier, item: StringName, at: Vector3, arm: String) -> String:
	if arm != CORD:
		return ""
	if by == null or by.inventory.count_of(DET_CORD) <= 0:
		return "No det cord"
	if nearest_linkable(by, at) == "":
		return "No charge of yours within %d m to tie it to" % roundi(link_m())
	return ""


## How far one coil of det cord reaches (its stats' "link_m").
static func link_m() -> float:
	return float(ItemDB.get_item(DET_CORD).stats.get("link_m", 15.0)) if ItemDB.has_item(DET_CORD) else 15.0


## Host: the id of `by`'s nearest block or claymore within link_m of `at`, or "".
func nearest_linkable(by: Node, at: Vector3) -> String:
	var best := ""
	var best_d := link_m()
	var key := owner_key(by)
	for id: String in records:
		if not String(records[id].kind) in LINKABLE or String(_owner.get(id, "")) != key:
			continue
		var d := position_of(id).distance_to(at)
		if d <= best_d:
			best = id
			best_d = d
	return best


## Host only. Puts one of `by`'s `item` (taken from their kit; with `by` null nobody's) at `xform`
## (world), riding `target` (null: the world), armed `arm` ("timer:N", REMOTE, CORD, TRIP,
## PRESSURE; thermite and chem lights take ""). Returns its id, or "" if it can't.
func server_place(by: Soldier, item: StringName, xform: Transform3D, target: Node3D = null, arm := "") -> String:
	if not multiplayer.is_server() or kind_of(item) == "":
		return ""
	var link := ""
	if arm == CORD:
		link = nearest_linkable(by, xform.origin) if by else ""
		if link == "" or (by and by.inventory.count_of(DET_CORD) <= 0):
			return ""
	if by and not by.inventory.remove_one(item):
		return ""
	if by and arm == CORD:
		by.inventory.remove_one(DET_CORD)
	var id := _new_id()
	var rec := _make_record(id, item, xform, target, arm, link, by.display_name() if by else "")
	_owner[id] = owner_key(by)
	_faction[id] = String(by.faction) if by else ""
	_placer[id] = by
	_arm_timers(id, rec)
	_client_add.rpc(rec)
	_mark(id)
	var what := ItemDB.get_item(item).name
	print("[demolitions] %s: %s placed by %s on %s, %s" % [id, what, rec.by, rec.path if rec.path != "" else "the world", arm_label(arm)])
	if by and not by.is_ai():
		var note := "%s set: %s" % [what, arm_label(arm)]
		if _arms_at.has(id):
			note += ", live in %d s" % roundi(float(_arms_at[id]) - _now())
		_tell(by, note)
	return id


## Host only. A thrown chem light `item` came to rest at `pos` (Throwables, from Grenade), on
## `target` if it landed on someone or something that moves. Returns its id.
func server_add_chemlight(item: StringName, pos: Vector3, target: Node3D = null) -> String:
	if not multiplayer.is_server() or kind_of(item) != CHEMLIGHT:
		return ""
	var id := _new_id()
	var xform := Transform3D(Basis(Vector3.UP, randf() * TAU), pos + Vector3.UP * 0.012)
	var rec := _make_record(id, item, xform, target, "", "", "")
	_arm_timers(id, rec)
	_client_add.rpc(rec)
	return id


func _new_id() -> String:
	var id := "D%d" % _next_id
	_next_id += 1
	while records.has(id):
		id = "D%d" % _next_id
		_next_id += 1
	return id


func _make_record(id: String, item: StringName, xform: Transform3D, target: Node3D, arm: String, link: String, by: String) -> Dictionary:
	var path := ""
	var local := xform
	if target and is_instance_valid(target) and level.is_ancestor_of(target):
		path = str(level.get_path_to(target))
		local = target.global_transform.affine_inverse() * xform
	var rec := {"id": id, "item": String(item), "kind": kind_of(item), "path": path, "xform": Charges._pack(local),
		"world": Charges._pack(xform), "arm": arm, "link": link, "by": by, "burning": false}
	var stats := ItemDB.get_item(item).stats
	if rec.kind == CHEMLIGHT:
		rec["life_s"] = float(stats.get("life_min", 30.0)) * 60.0
	return rec


## Host: the clocks a new (or restored) record runs on.
func _arm_timers(id: String, rec: Dictionary, left := -1.0) -> void:
	var stats := ItemDB.get_item(StringName(String(rec.item))).stats
	var now := _now()
	match String(rec.kind):
		THERMITE:
			if bool(rec.get("burning", false)):
				_burn_end[id] = now + (left if left >= 0.0 else float(stats.get("burn_s", 8.0)))
			else:
				_due[id] = now + (left if left >= 0.0 else float(stats.get("fuse_s", 3.0)))
		CHEMLIGHT:
			_expire[id] = now + (left if left >= 0.0 else float(rec.get("life_s", 1800.0)))
		_:
			var t := timer_s(String(rec.arm))
			if t >= 0.0:
				_due[id] = now + (left if left >= 0.0 else t)
			elif String(rec.arm) in [TRIP, PRESSURE]:
				_arms_at[id] = now + (left if left >= 0.0 else float(stats.get("arm_s", 10.0)))


## Host: our side's mines and claymores go on the map.
func _mark(id: String) -> void:
	var rec: Dictionary = records.get(id, {})
	if rec.is_empty() or not String(rec.kind) in [MINE, CLAYMORE] or String(_faction.get(id, "")) != "friendly":
		return
	var markers := MapNodes.markers(self)
	if markers == null:
		return
	var p := position_of(id)
	_markers[id] = markers.server_add({"kind": "point", "points": PackedVector2Array([Vector2(p.x, p.z)]),
		"text": "Our %s" % ("mine" if rec.kind == MINE else "claymore"), "colour": "orange", "channel": "field", "author": 0})


func _unmark(id: String) -> void:
	var marker := int(_markers.get(id, 0))
	_markers.erase(id)
	var markers := MapNodes.markers(self)
	if marker != 0 and markers:
		markers.server_remove(marker)


## Host only. Whether mine or tripwire `id` is live yet.
func is_live(id: String) -> bool:
	return records.has(id) and _arms_at.has(id) and _now() >= float(_arms_at[id])


## Host only. Where `id` is now (it may have moved with what it rides).
func position_of(id: String) -> Vector3:
	var node := get_node_of(id)
	if node:
		return node.global_position
	if _last_pos.has(id):
		return _last_pos[id]
	var w: Array = records.get(id, {}).get("world", [])
	return Charges._unpack(w).origin if w.size() == 12 else Vector3.ZERO


## Host only. `id`'s world transform now.
func transform_of(id: String) -> Transform3D:
	var node := get_node_of(id)
	if node:
		return node.global_transform
	var t := Charges._unpack(records.get(id, {}).get("world", []))
	if _last_pos.has(id):
		t.origin = _last_pos[id]
	return t


## The chain `id` is in through det cord (it first), every id once.
func chain(id: String) -> Array[String]:
	var out: Array[String] = []
	if not records.has(id):
		return out
	var queue: Array[String] = [id]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		if at in out:
			continue
		out.append(at)
		var link := String(records[at].get("link", ""))
		if link != "" and records.has(link) and not link in out:
			queue.append(link)
		for other: String in records:
			if String(records[other].get("link", "")) == at and not other in out:
				queue.append(other)
	return out


## A player squeezes their firing device `detonator` (G with it picked). Any peer (rpc_id 1).
@rpc("any_peer", "call_local", "reliable")
func request_fire(detonator: String) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender_body()
	if actor == null or not actor.vitals.is_up():
		return
	var n := server_fire_remote(actor, StringName(detonator))
	if n < 0:
		return
	_tell(actor, "Fired: %d charge%s" % [n, "" if n == 1 else "s"] if n > 0 else "Nothing of yours on a detonator within %d m" % roundi(detonator_range(StringName(detonator))))


## How far firing device `id` reaches (its stats' "range_m").
static func detonator_range(id: StringName) -> float:
	return float(ItemDB.get_item(id).stats.get("range_m", 50.0)) if ItemDB.has_item(id) else 0.0


## Host only. `by` fires `detonator` (they must carry it): every charge of theirs armed REMOTE
## within its range goes off, with its chain. Returns how many went (chains counted), -1 if they
## don't carry it.
func server_fire_remote(by: Soldier, detonator: StringName) -> int:
	if not multiplayer.is_server() or by == null or not is_detonator(detonator) or by.inventory.count_of(detonator) <= 0:
		return -1
	Sfx.server_play(&"clacker", by.global_position + Vector3.UP * 1.2)
	var reach := detonator_range(detonator)
	var key := owner_key(by)
	var go: Array[String] = []
	for id: String in records:
		if String(records[id].arm) == REMOTE and String(_owner.get(id, "")) == key and position_of(id).distance_to(by.global_position) <= reach:
			go.append(id)
	var n := 0
	for id in go:
		if records.has(id):
			n += server_detonate(id)
	return n


## Host only. `id` goes off, and with it everything corded to it. `stepper` is who stepped on a
## mine (their leg takes it). Returns how many went.
func server_detonate(id: String, stepper: Node3D = null) -> int:
	if not multiplayer.is_server() or not records.has(id):
		return 0
	var lvl := level as CompoundLevel
	var going: Array[Dictionary] = []
	for member in chain(id):
		var rec: Dictionary = records[member]
		var node := get_node_of(member)
		going.append({"rec": rec, "xform": transform_of(member), "rides": node.get_parent() if node else null,
			"placer": _placer.get(member), "stepper": stepper if member == id else null})
		_forget(member)
		_client_remove.rpc(member)
	for g: Dictionary in going:
		var rec: Dictionary = g.rec
		var shooter: Node = g.placer if is_instance_valid(g.placer) else null
		var xform: Transform3D = g.xform
		fired.append({"id": rec.id, "item": rec.item, "kind": rec.kind, "pos": xform.origin, "by": rec.by})
		print("[demolitions] %s (%s) went off at (%.1f, %.1f, %.1f)" % [rec.id, rec.item, xform.origin.x, xform.origin.y, xform.origin.z])
		if lvl == null:
			continue
		match String(rec.kind):
			DEMO:
				_blast_demo(lvl, rec, xform, g.rides, shooter)
			CLAYMORE:
				_fire_claymore(lvl, rec, xform, shooter)
			MINE:
				_fire_mine(lvl, rec, xform, g.stepper, shooter)
	return going.size()


## Host: drops `id` from every host-side table (not the peers' records: _client_remove does that).
func _forget(id: String) -> void:
	_due.erase(id)
	_burn_end.erase(id)
	_arms_at.erase(id)
	_expire.erase(id)
	_owner.erase(id)
	_faction.erase(id)
	_placer.erase(id)
	_last_pos.erase(id)
	_unmark(id)


func _stats(rec: Dictionary) -> Dictionary:
	return ItemDB.get_item(StringName(String(rec.item))).stats


func _blast_data(stats: Dictionary, frags := true) -> Dictionary:
	return {"kind": "he", "blast_kg": float(stats.get("blast_kg", 0.5)), "frag_m": float(stats.get("frag_m", 0.0)) if frags else 0.0,
		"frag_wounds": stats.get("frag_wounds", [1, 3])}


func _blast_demo(lvl: CompoundLevel, rec: Dictionary, xform: Transform3D, rides: Node, shooter: Node) -> void:
	var stats := _stats(rec)
	var pos := xform.origin
	var kg := float(stats.get("blast_kg", 1.5))
	lvl.show_explosion.rpc(pos)
	lvl.server_blast(pos, float(stats.get("carve_m", 1.8)))
	Warheads.server_people(lvl, pos + xform.basis.y * 0.1, _blast_data(stats), shooter)
	var on := Vehicle.find_on(rides) if rides else null
	_hit_vehicles(pos, kg, float(stats.get("contact_mult", 4.0)), on, shooter)
	Contracts.objectives.server_charge_blast(pos)  # a sabotage target or cache it's on
	_heard(lvl, pos, 1.5)


func _fire_claymore(lvl: CompoundLevel, rec: Dictionary, xform: Transform3D, shooter: Node) -> void:
	var stats := _stats(rec)
	var centre := xform.origin + xform.basis.y * 0.15
	var forward := -xform.basis.z
	var reach := float(stats.get("frag_m", 50.0))
	var wounds: Array = stats.get("frag_wounds", [3, 10])
	lvl.show_explosion.rpc(centre)
	lvl.server_blast(centre, 0.3)
	Warheads.server_people(lvl, centre, _blast_data(stats, false), shooter)  # the blast all round, close in
	var aboard := Warheads.vehicle_occupants(get_tree())
	for n in Throwables.combatants(get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals == null or vitals.is_dead() or aboard.has(body):
			continue
		var to := Throwables.body_point(body) - centre
		var d := to.length()
		if d > reach or not in_cone(forward, to, float(stats.get("cone_deg", 60.0)), float(stats.get("up_deg", 20.0))):
			continue
		Warheads.frag_body(body, vitals, centre, d, reach, Vector2i(int(wounds[0]), int(wounds[1])), shooter, 2)
		if body.has_method(&"suppress"):
			body.suppress(1.0, centre)
	_heard(lvl, centre, 1.0)


func _fire_mine(lvl: CompoundLevel, rec: Dictionary, xform: Transform3D, stepper: Node3D, shooter: Node) -> void:
	var stats := _stats(rec)
	var pos := xform.origin
	lvl.show_explosion.rpc(pos)
	lvl.server_blast(pos, 0.5)
	var skip: Array = []
	var vitals := stepper.get_node_or_null(^"Vitals") as Vitals if stepper else null
	if vitals and not vitals.is_dead():
		# The foot on it: the leg is wrecked from below (the rest of the blast as for anyone).
		var left := stepper.to_local(pos).x < 0.0
		Harm.note_hit(stepper, shooter)
		vitals.server_hit(Vitals.SHIN_L if left else Vitals.SHIN_R, {"round_class": Vitals.FULL_POWER, "position": pos, "direction": Vector3.UP, "distance": 0.0})
		vitals.server_hit(Vitals.THIGH_L if left else Vitals.THIGH_R, {"round_class": Vitals.FRAGMENT, "position": pos, "direction": Vector3.UP, "distance": 0.3})
	Warheads.server_people(lvl, pos + Vector3.UP * 0.1, _blast_data(stats), shooter, skip)
	var car := stepper as Vehicle
	if car:
		car.server_take_hit({"kind": Vehicle.HE, "position": pos, "direction": Vector3.UP, "blast_kg": float(stats.get("blast_kg", 0.2)) * 2.0, "shooter": shooter})
	_heard(lvl, pos, 1.0)


## Host: a block's burst at `pos` (`kg` TNT) on the vehicles: the one it's set `on` takes
## `contact` times it, others within NEAR_VEHICLE_M a share falling off with distance.
func _hit_vehicles(pos: Vector3, kg: float, contact: float, on: Vehicle, shooter: Node) -> void:
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		var v := n as Vehicle
		if v == null or not is_instance_valid(v) or v.is_queued_for_deletion():
			continue
		var into := (v.global_transform * v.center_of_mass - pos).normalized()
		if v == on:
			v.server_take_hit({"kind": Vehicle.HE, "position": pos, "direction": into, "blast_kg": kg * contact, "shooter": shooter})
			continue
		var d := footprint_distance(v, pos)
		if d < NEAR_VEHICLE_M:
			var share := 1.0 - d / NEAR_VEHICLE_M
			v.server_take_hit({"kind": Vehicle.HE, "position": pos, "direction": into, "blast_kg": kg * share * share, "shooter": shooter})


## How far `pos` is from vehicle `v`'s box (its art's size about its origin, on the ground).
static func footprint_distance(v: Vehicle, pos: Vector3) -> float:
	var size := VehicleArt.size_m(v.model)
	var box := AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)
	var local := v.to_local(pos)
	return local.distance_to(local.clamp(box.position, box.end))


## Host: the bang heard (people, the enemy's alert) and felt (players' view shake).
func _heard(lvl: CompoundLevel, pos: Vector3, loudness: float) -> void:
	PeopleLayer.server_noise(lvl, pos, PeopleLayer.BLAST_HEARD_M * loudness)
	Alert.server_noise(lvl, pos, Alert.BLAST)
	var radius := 20.0 + 15.0 * loudness
	for player in lvl.players.get_children():
		var d := (player as Node3D).global_position.distance_to(pos)
		if d < radius and multiplayer.has_multiplayer_peer():
			player._client_shake.rpc_id(player.name.to_int(), 1.0 - d / radius)


## Host: thermite `id` lights.
func _ignite(id: String) -> void:
	_due.erase(id)
	var rec: Dictionary = records[id]
	var burn := float(_stats(rec).get("burn_s", 8.0))
	rec.burning = true
	_burn_end[id] = _now() + burn
	_client_burn.rpc(id, burn)
	var pos := position_of(id)
	_hiss(id)
	print("[demolitions] %s: thermite lit at (%.1f, %.1f, %.1f)" % [id, pos.x, pos.y, pos.z])


## Host: burning thermite `id`'s hiss, again every HISS_S while it burns.
func _hiss(id: String) -> void:
	if not records.has(id) or not is_inside_tree():
		return
	Sfx.server_play(&"thermite", position_of(id))
	get_tree().create_timer(HISS_S).timeout.connect(_hiss.bind(id))


## Host: thermite `id` has burnt through: what it's on is done for.
func _thermite_done(id: String) -> void:
	var rec: Dictionary = records[id]
	var stats := _stats(rec)
	var node := get_node_of(id)
	var rides: Node = node.get_parent() if node else null
	var pos := position_of(id)
	var shooter: Node = _placer.get(id) if is_instance_valid(_placer.get(id)) else null
	_forget(id)
	_client_remove.rpc(id)
	fired.append({"id": id, "item": rec.item, "kind": rec.kind, "pos": pos, "by": rec.by})
	var lvl := level as CompoundLevel
	var vehicle := Vehicle.find_on(rides) if rides else null
	if vehicle == null:
		for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
			if n is Vehicle and footprint_distance(n as Vehicle, pos) <= 0.3:
				vehicle = n as Vehicle
				break
	if vehicle and not vehicle.wrecked:
		if vehicle.kind == Vehicle.STATIC:
			vehicle.server_set_zone(Vehicle.ZONE_HULL, 0.0)  # a static gun: its works burnt through
		else:
			vehicle.server_set_zone(Vehicle.ZONE_ENGINE, 0.0)
			vehicle.server_start_fire()
		print("[demolitions] %s: thermite burnt through %s" % [id, vehicle.name])
	if lvl == null:
		return
	lvl.server_blast(pos, 0.35)
	var burn_m := float(stats.get("burn_m", 1.2))
	for n in Throwables.combatants(get_tree()):
		var body := n as Node3D
		var vitals := body.get_node_or_null(^"Vitals") as Vitals
		if vitals and not vitals.is_dead() and Throwables.body_point(body).distance_to(pos) <= burn_m + 0.6:
			Harm.note_hit(body, shooter)
			vitals.server_burn(0.15)
	Warheads.server_people(lvl, pos, _blast_data(stats, false), shooter)
	Contracts.objectives.server_charge_blast(pos)  # a cache or sabotage target it's on


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or records.is_empty():
		return
	var now := _now()
	for id: String in _due.keys():
		if not records.has(id):
			_due.erase(id)
		elif now >= float(_due[id]):
			if String(records[id].kind) == THERMITE:
				_ignite(id)
			else:
				server_detonate(id)
	for id: String in _burn_end.keys():
		if records.has(id) and now >= float(_burn_end[id]):
			_thermite_done(id)
	for id: String in _expire.keys():
		if records.has(id) and now >= float(_expire[id]):
			server_remove(id)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK_S
	for id: String in records:
		var node := get_node_of(id)
		if node:
			_last_pos[id] = node.global_position
	server_check_triggers()


## Host only. One look at every live mine and tripwire: anyone (friend or foe: friendly fire is
## on) on a mine or in a wire, or a vehicle over a mine, sets it off.
func server_check_triggers() -> void:
	var live: Array[String] = []
	for id: String in _arms_at:
		if is_live(id):
			live.append(id)
	if live.is_empty():
		return
	var bodies: Array[Soldier] = []
	for n in Throwables.combatants(get_tree()):
		var s := n as Soldier
		if s and not s.vitals.is_dead() and Vehicle.ride_of(s) == null:
			bodies.append(s)
	var vehicles := get_tree().get_nodes_in_group(Vehicle.GROUP)
	for id in live:
		if not records.has(id):
			continue
		var rec: Dictionary = records[id]
		var stats := _stats(rec)
		var t := transform_of(id)
		if String(rec.arm) == PRESSURE:
			var r := float(stats.get("trigger_m", 0.45))
			for s in bodies:
				if _flat(s.global_position, t.origin) <= r and absf(s.global_position.y - t.origin.y) < 0.8:
					server_detonate(id, s)
					break
			if not records.has(id):
				continue
			for v: Node in vehicles:
				var car := v as Vehicle
				if car and car.kind != Vehicle.STATIC and footprint_distance(car, t.origin + Vector3.UP * 0.05) <= WHEEL_MARGIN_M:
					server_detonate(id, car)
					break
		elif String(rec.arm) == TRIP:
			var wire := tripwire(t, stats)
			for s in bodies:
				if _flat_to_segment(s.global_position, wire[0], wire[1]) <= TRIP_CATCH_M and absf(s.global_position.y - t.origin.y) < 1.0:
					print("[demolitions] %s: %s walked into the tripwire" % [id, s.display_name()])
					server_detonate(id)
					break


## A claymore at `t`'s tripwire, ends in the world: "trip_w_m" wide across its front,
## "trip_out_m" out.
static func tripwire(t: Transform3D, stats: Dictionary) -> Array[Vector3]:
	var forward := -t.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var across := forward.cross(Vector3.UP).normalized()
	var mid := t.origin + forward * float(stats.get("trip_out_m", 2.0))
	var half := float(stats.get("trip_w_m", 4.0)) * 0.5
	return [mid - across * half, mid + across * half]


## Host only. Takes `id` away with nothing set off (picked up, or a chem light gone out).
func server_remove(id: String) -> void:
	if not records.has(id):
		return
	for other: String in records:
		if String(records[other].get("link", "")) == id:
			records[other].link = ""  # its det cord comes away with it
			_client_unlink.rpc(other)
	_forget(id)
	_client_remove.rpc(id)


## A player picks up placed item `id` (the interaction menu). Any peer (rpc_id 1).
@rpc("any_peer", "call_local", "reliable")
func request_pickup(id: String) -> void:
	if not multiplayer.is_server():
		return
	var actor := _sender_body()
	if actor:
		_tell(actor, server_pickup(actor, id))


## Host only. `actor` takes placed item `id` back into their kit: within PICKUP_M, never a
## lit thermite or a chem light. Returns what they're told.
func server_pickup(actor: Soldier, id: String) -> String:
	if not records.has(id) or actor == null or not actor.vitals.is_up():
		return "It's gone"
	var rec: Dictionary = records[id]
	if String(rec.kind) == CHEMLIGHT or bool(rec.get("burning", false)) or _burn_end.has(id):
		return "You can't pick that up"
	if position_of(id).distance_to(actor.global_position + Vector3.UP * 0.9) > PICKUP_M + 0.9:
		return "Too far away"
	var item := StringName(String(rec.item))
	if actor.inventory.take(item) < 1:
		return "No room for it"
	server_remove(id)
	return "Picked up the %s" % ItemDB.get_item(item).name


## Host only (F-120: for the AI): the armed mines and claymores placed by `faction`'s side, as
## {"id", "kind", "pos", "radius" (keep this far off), "forward" (a claymore's facing)}.
func hazards(faction: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in records:
		var rec: Dictionary = records[id]
		if not String(rec.kind) in [MINE, CLAYMORE] or StringName(String(_faction.get(id, ""))) != faction:
			continue
		var t := transform_of(id)
		var stats := _stats(rec)
		var radius := float(stats.get("trigger_m", 0.45)) + 1.0 if rec.kind == MINE else float(stats.get("trip_out_m", 2.0)) + 1.0
		out.append({"id": id, "kind": String(rec.kind), "pos": t.origin, "radius": radius, "forward": -t.basis.z})
	return out


# --- The zone save (host) -------------------------------------------------------------------

## Host only. Everything placed, for GameState.save_zone: each record with its world transform
## now, what it rides (a vehicle's id; things on people aren't kept), the clocks left and who
## owns it.
func to_save() -> Array:
	var out: Array = []
	var now := _now()
	for id: String in records:
		var rec: Dictionary = records[id]
		var node := get_node_of(id)
		var rides: Node = node.get_parent() if node else null
		var vehicle := Vehicle.find_on(rides) if rides and rides != level else null
		if rides and rides != level and vehicle == null:
			continue  # on a person: not kept
		var left := -1.0
		for clock: Dictionary in [_due, _burn_end, _expire, _arms_at]:
			if clock.has(id):
				left = maxf(float(clock[id]) - now, 0.0)
		out.append({"id": id, "item": String(rec.item), "world": Charges._pack(transform_of(id)), "arm": String(rec.arm),
			"link": String(rec.get("link", "")), "by": String(rec.get("by", "")), "burning": bool(rec.get("burning", false)),
			"left_s": left, "owner": String(_owner.get(id, "")), "faction": String(_faction.get(id, "")),
			"vehicle_id": vehicle.vehicle_id if vehicle else ""})
	return out


## Whether `r` is a saved record (to_save): a known item that places, a finite transform.
static func save_ok(r: Variant) -> bool:
	if typeof(r) != TYPE_DICTIONARY or typeof(r.get("id")) != TYPE_STRING or typeof(r.get("item")) != TYPE_STRING:
		return false
	if kind_of(StringName(String(r.item))) == "" or typeof(r.get("world")) != TYPE_ARRAY or (r.world as Array).size() != 12:
		return false
	return (r.world as Array).all(func(v: Variant) -> bool: return GameState.is_number(v) and is_finite(float(v))) \
		and GameState.is_number(r.get("left_s", -1.0))


## Host only. Puts back what the zone save holds (GameState.demolitions), each on the vehicle it
## rode when that's here (else where it was), its clocks running on from where they stopped.
func server_restore(from_save: Variant = null) -> int:
	if not multiplayer.is_server():
		return 0
	var saved: Array = from_save if from_save is Array else GameState.demolitions
	var n := 0
	var later: Array = []
	for r: Variant in saved:
		if not save_ok(r) or records.has(String(r.id)):
			continue
		var vid := String(r.get("vehicle_id", ""))
		var vehicle := _vehicle_by_id(vid) if vid != "" else null
		if vid != "" and vehicle == null:
			later.append(r)  # its vehicle isn't back yet (the range parks its vehicles after the bodies)
			continue
		_restore_one(r, vehicle)
		n += 1
	if not later.is_empty():
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			for r: Dictionary in later:
				if not records.has(String(r.id)):
					_restore_one(r, _vehicle_by_id(String(r.vehicle_id))))
	if n > 0:
		print("[demolitions] %d placed items put back from the zone save" % n)
	return n


func _restore_one(r: Dictionary, vehicle: Vehicle) -> void:
	var id := String(r.id)
	var item := StringName(String(r.item))
	var xform := Charges._unpack(r.world)
	var rec := _make_record(id, item, xform, vehicle, String(r.get("arm", "")), String(r.get("link", "")), String(r.get("by", "")))
	rec.burning = bool(r.get("burning", false))
	var left := float(r.get("left_s", -1.0))
	if rec.kind == CHEMLIGHT and left >= 0.0:
		rec.life_s = left
	_owner[id] = String(r.get("owner", ""))
	_faction[id] = String(r.get("faction", ""))
	_arm_timers(id, rec, left)
	if rec.burning:
		rec["burn_s"] = maxf(left, 0.0)
	var num := String(id).trim_prefix("D").to_int()
	_next_id = maxi(_next_id, num + 1)
	_client_add.rpc(rec)
	_mark(id)


func _vehicle_by_id(vid: String) -> Vehicle:
	for n in get_tree().get_nodes_in_group(Vehicle.GROUP):
		if n is Vehicle and (n as Vehicle).vehicle_id == vid:
			return n as Vehicle
	return null


# --- Every peer ---------------------------------------------------------------------------

## `id`'s node on this peer (or null).
func get_node_of(id: String) -> Node3D:
	var rec: Dictionary = records.get(id, {})
	if rec.is_empty():
		return null
	var parent := level.get_node_or_null(NodePath(String(rec.path))) if String(rec.path) != "" else level
	var node := parent.get_node_or_null(NodePath("Placed_" + id)) if parent else null
	if node == null:
		node = level.get_node_or_null(NodePath("Placed_" + id))
	return node as Node3D


@rpc("authority", "call_local", "reliable")
func _client_add(rec: Dictionary) -> void:
	var id := String(rec.id)
	records[id] = rec
	_received[id] = _now()
	var parent: Node3D = level
	var xform := Charges._unpack(rec.world)
	if String(rec.path) != "":
		var target := level.get_node_or_null(NodePath(String(rec.path))) as Node3D
		if target:
			parent = target
			xform = Charges._unpack(rec.xform)
	var old := get_node_of(id)
	if old:
		old.free()
	var node := Placed.new()
	node.id = id
	node.item = StringName(String(rec.item))
	node.kind = String(rec.kind)
	node.name = "Placed_" + id
	if node.kind == CHEMLIGHT:
		node.life_until = _now() + float(rec.get("life_s", 1800.0))
	node.add_child(make_visual(node.item, false, rec))
	parent.add_child(node)
	node.transform = xform
	if String(rec.get("link", "")) != "":
		var other := get_node_of(String(rec.link))
		if other:
			node.add_child(cord_line(node.global_position, other.global_position))
	if bool(rec.get("burning", false)):
		node.set_burning(true, float(rec.get("burn_s", 8.0)))


@rpc("authority", "call_local", "reliable")
func _client_remove(id: String) -> void:
	var node := get_node_of(id)
	if node:
		node.queue_free()
	records.erase(id)
	_received.erase(id)


@rpc("authority", "call_local", "reliable")
func _client_burn(id: String, burn_s: float) -> void:
	if records.has(id):
		records[id].burning = true
	var node := get_node_of(id) as Placed
	if node:
		node.set_burning(true, burn_s)


@rpc("authority", "call_local", "reliable")
func _client_unlink(id: String) -> void:
	if records.has(id):
		records[id].link = ""
	var node := get_node_of(id)
	var cord := node.get_node_or_null(^"DetCord") if node else null
	if cord:
		cord.queue_free()


func _on_peer_joined(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var now := _now()
	for id: String in records:
		var r: Dictionary = records[id].duplicate(true)
		r.world = Charges._pack(transform_of(id))
		if _expire.has(id):
			r.life_s = maxf(float(_expire[id]) - now, 0.0)
		if _burn_end.has(id):
			r.burn_s = maxf(float(_burn_end[id]) - now, 0.0)
		_client_add.rpc_id(peer, r)


func _sender_body() -> Soldier:
	var lvl := level as CompoundLevel
	var sender := multiplayer.get_remote_sender_id()
	return lvl.players.get_node_or_null(str(sender if sender != 0 else 1)) as Soldier if lvl else null


func _tell(s: Soldier, text: String) -> void:
	if s and not s.is_ai() and text != "" and multiplayer.has_multiplayer_peer():
		s._client_message.rpc_id(s.owner_peer(), text)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _flat_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := clampf((p2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Looks ---------------------------------------------------------------------------------

## The look of item `id` (placeholder boxes; the art pass can replace this one function): an
## olive demo block with its cap and a light (red: on a timer; green: on a detonator), a grey
## thermite can, a claymore on its legs (its tripwire too, when it has one), a mine's lid just
## showing above the ground, a chem light's glowing stick with its light ("Glow"). `ghost`: the
## see-through placing ghost (tint_ghost colours it). `rec`: the placed record (its arming).
static func make_visual(id: StringName, ghost := false, rec := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Look"
	var kind := kind_of(id)
	var arm := String(rec.get("arm", ""))
	match kind:
		DEMO:
			_box(root, "Block", Vector3(0.28, 0.05, 0.07), Vector3(0, -0.005, 0), Color(0.82, 0.8, 0.66))
			_box(root, "Wrap", Vector3(0.285, 0.052, 0.02), Vector3(0, -0.005, 0), Color(0.36, 0.38, 0.26))
			_box(root, "Cap", Vector3(0.012, 0.012, 0.05), Vector3(0.09, 0.025, 0.0), Color(0.7, 0.6, 0.35))
			if not ghost and arm != CORD:
				_light_dot(root, Vector3(0.0, 0.026, 0.02), Color(0.2, 1.0, 0.25) if arm == REMOTE else Color(1.0, 0.1, 0.05))
		THERMITE:
			_box(root, "Can", Vector3(0.065, 0.14, 0.065), Vector3(0, 0.04, 0), Color(0.55, 0.56, 0.55))
			_box(root, "Band", Vector3(0.067, 0.02, 0.067), Vector3(0, 0.07, 0), Color(0.7, 0.15, 0.1))
			_box(root, "Lever", Vector3(0.012, 0.1, 0.02), Vector3(0.036, 0.05, 0), Color(0.4, 0.42, 0.4))
		CLAYMORE:
			_box(root, "Body", Vector3(0.22, 0.085, 0.035), Vector3(0, 0.12, 0), Color(0.33, 0.36, 0.22))
			_box(root, "Face", Vector3(0.2, 0.07, 0.004), Vector3(0, 0.12, -0.019), Color(0.28, 0.3, 0.18))
			for x: float in [-0.08, 0.08]:
				_box(root, "Leg", Vector3(0.01, 0.08, 0.01), Vector3(x, 0.04, 0.012), Color(0.25, 0.25, 0.22))
			if not ghost and arm == TRIP:
				var stats := ItemDB.get_item(id).stats
				var out := float(stats.get("trip_out_m", 2.0))
				var w := float(stats.get("trip_w_m", 4.0))
				_box(root, "Tripwire", Vector3(w, 0.004, 0.004), Vector3(0, 0.12, -out), Color(0.6, 0.6, 0.55))
				_box(root, "TripLead", Vector3(0.004, 0.004, out), Vector3(0, 0.12, -out * 0.5), Color(0.6, 0.6, 0.55))
		MINE:
			_box(root, "Mine", Vector3(0.08, 0.04, 0.08), Vector3(0, -0.012, 0), Color(0.5, 0.47, 0.33))
			_box(root, "Plate", Vector3(0.04, 0.004, 0.04), Vector3(0, 0.009, 0), Color(0.3, 0.3, 0.26))
		CHEMLIGHT:
			var g := glow(id, false)
			var stick := _box(root, "Stick", Vector3(0.15, 0.016, 0.016), Vector3.ZERO, (g.colour as Color).darkened(0.3))
			if not ghost:
				var m := stick.material_override as StandardMaterial3D
				m.emission_enabled = true
				m.emission = g.colour
				m.emission_energy_multiplier = 1.5 if g.visible else 0.0
				var light := OmniLight3D.new()
				light.name = "Glow"
				light.light_color = g.colour
				light.light_energy = g.energy
				light.omni_range = g.range
				light.visible = g.visible
				light.position = Vector3.UP * 0.05
				root.add_child(light)
		_:
			_box(root, "Box", Vector3(0.1, 0.1, 0.1), Vector3.ZERO, Color.GRAY)
	if ghost:
		tint_ghost(root, true)
	return root


## Colours a placing ghost: green where it can go, red where it can't.
static func tint_ghost(ghost: Node3D, ok: bool) -> void:
	for n in ghost.find_children("*", "MeshInstance3D", true, false):
		var m := (n as MeshInstance3D).material_override as StandardMaterial3D
		if m == null:
			continue
		m.albedo_color = Color(0.4, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.3, 0.3, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


## A det cord line from `from` to `to` (world), drawn in the world (top level).
static func cord_line(from: Vector3, to: Vector3) -> Node3D:
	var line := MeshInstance3D.new()
	line.name = "DetCord"
	var mesh := BoxMesh.new()
	var length := maxf(from.distance_to(to), 0.01)
	mesh.size = Vector3(0.008, 0.008, length)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.75, 0.2)
	mesh.material = m
	line.mesh = mesh
	line.top_level = true
	var mid := (from + to) * 0.5
	var up := Vector3.UP if absf((to - from).normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	line.transform = Transform3D(Basis.looking_at(to - from if length > 0.01 else Vector3.FORWARD, up), mid)
	return line


static func _box(root: Node3D, part: String, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	var inst := MeshInstance3D.new()
	inst.name = part
	inst.mesh = mesh
	inst.material_override = m
	inst.position = at
	root.add_child(inst)
	return inst


static func _light_dot(root: Node3D, at: Vector3, colour: Color) -> void:
	var dot := _box(root, "Light", Vector3(0.012, 0.006, 0.012), at, colour)
	var m := dot.material_override as StandardMaterial3D
	m.emission_enabled = true
	m.emission = colour


## A placed item's node on every peer: its look, its chem light's glow (brighter through the
## local player's night vision) or its thermite's fire, and "Pick up" in the interaction menu.
class Placed extends Node3D:
	var id := ""
	var item: StringName
	var kind := ""
	## A chem light: the local time it goes out.
	var life_until := 0.0
	var burning := false
	var nvg_on := false
	var _look_s := 0.0
	var _fire: OmniLight3D
	var _sparks: CPUParticles3D

	func _ready() -> void:
		if kind == Demolitions.CHEMLIGHT:
			update_glow()
		else:
			add_to_group(InteractionMenu.INTERACTABLES)

	func interaction_actions(_actor: Node) -> Array[Dictionary]:
		return [{"id": &"pick_up_placed", "label": "Pick up the %s" % ItemDB.get_item(item).name, "disabled": "It's burning" if burning else "",
			"target": self, "call": _pick_up}]

	func _pick_up() -> void:
		var demolitions := Demolitions.of(self)
		if demolitions:
			demolitions.request_pickup.rpc_id(1, id)

	func action_point() -> Vector3:
		return global_position + Vector3.UP * 0.06

	func _process(delta: float) -> void:
		if kind == Demolitions.CHEMLIGHT:
			_look_s -= delta
			if _look_s <= 0.0:
				_look_s = 0.25
				update_glow()
		elif burning and _fire:
			_fire.light_energy = Demolitions.BURN_ENERGY * randf_range(0.6, 1.2)

	## The glow as the local player sees it now (their NVG down or not).
	func update_glow() -> void:
		var viewer := MapNodes.local_player(self)
		nvg_on = viewer != null and Nvg.is_on(viewer)
		var g := Demolitions.glow(item, nvg_on, life_until - Demolitions._now())
		var light := find_child("Glow", true, false) as OmniLight3D
		if light:
			light.visible = g.visible
			light.light_energy = g.energy
			light.omni_range = g.range
		var stick := find_child("Stick", true, false) as MeshInstance3D
		if stick and stick.material_override is StandardMaterial3D:
			(stick.material_override as StandardMaterial3D).emission_energy_multiplier = (4.0 if nvg_on else 1.5) if g.visible else 0.0

	## Thermite: lit (a white-hot flickering light, sparks) for `seconds`.
	func set_burning(on: bool, seconds: float) -> void:
		burning = on
		if not on or _fire:
			return
		_fire = OmniLight3D.new()
		_fire.name = "Fire"
		_fire.light_color = Color(1.0, 0.75, 0.45)
		_fire.light_energy = Demolitions.BURN_ENERGY
		_fire.omni_range = Demolitions.BURN_RANGE_M
		_fire.position = Vector3.UP * 0.15
		add_child(_fire)
		_sparks = CPUParticles3D.new()
		_sparks.name = "Sparks"
		_sparks.amount = 40
		_sparks.lifetime = 0.6
		_sparks.direction = Vector3.UP
		_sparks.spread = 60.0
		_sparks.initial_velocity_min = 1.0
		_sparks.initial_velocity_max = 3.0
		_sparks.scale_amount_min = 0.02
		_sparks.scale_amount_max = 0.04
		var spark := BoxMesh.new()
		spark.size = Vector3.ONE
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.5)
		spark.material = m
		_sparks.mesh = spark
		_sparks.position = Vector3.UP * 0.12
		add_child(_sparks)
		_sparks.emitting = true
		get_tree().create_timer(maxf(seconds, 0.1)).timeout.connect(func() -> void:
			if is_instance_valid(_sparks):
				_sparks.emitting = false)
