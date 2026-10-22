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
##   "clear_arm_timeout_s" with none), so it can't complete before the enemy spawns. In a
##   zone the check waits until the site's module has had its garrison (_garrisoned): an
##   unvisited target's empty rect doesn't pay the bonus.
## - EXTRACT_ITEM: an item in "items" (or tagged one of "tags") is carried out:
##   server_items_out(items), from extraction (Contracts.server_end_deployment) or a mid-zone
##   loot evacuation.
## - DELIVER_HVT: server_hvt_delivered(hvt_id, alive) (the people agent's HVT calls it);
##   server_hvt_lost(hvt_id) fails it.
## - DESTROY_CACHE: the voxels in "box" ([[x, y, z], [x, y, z]] metres) are mostly gone
##   (less than "cache_destroyed_share" of the site's authored "voxels" left; frags and
##   explosives carve them; a steel AA gun barely chips), or server_cache_destroyed(cache_id),
##   or a breaching charge going off within "charge_kill_m" of its box (Charges, placed by
##   players anywhere, or server_place_charge). The share is measured against the authored count, never against
##   what stands at deploy: a zone keeps its voxel damage, so a cache box already carved
##   (blown on an earlier contract and saved) must not count as destroyed on the next one.
##   With no "voxels" in the site, or a box already under the threshold when it is first
##   read, the voxel check stays off and only the hook or a charge completes it (a world or
##   4B pass that restores a zone rebuilds the cache).
## - Any kind with "time_limit_s" (hostage rescue, HVT capture, HVT kill): fails when the clock,
##   started when the objective goes live, runs out; DELIVER_HVT, KILL_HVT and EXTRACT_ITEM show
##   the minutes left.
## In a world-scale zone a cache's voxels are its module's ("module_id": world_of).

signal changed

const ACTIVE := "active"
const DONE := "done"
const FAILED := "failed"
const CLEAR_AREA := "clear_area"
const EXTRACT_ITEM := "extract_item"
const DELIVER_HVT := "deliver_hvt"
const DESTROY_CACHE := "destroy_cache"
## Scenario kinds (mission variety, 2026-10-15): MissionScenario plays them in the level and
## marks them done or failed (server_set_state); ScenarioGen builds their "params".
## - CONVOY: an enemy convoy drives "route"; done when every cargo truck is halted (destroyed,
##   disabled or its driver down), failed when one gets out the far end.
## - HOLD_POINT: hold "pos" ("radius" m) for "hold_s" seconds against waves; failed when lost.
## - RESCUE_CREW: the "crew" (people of the downed helicopter); done when "need" of them are out
##   (delivered alive: server_hvt_delivered), failed when too many are lost.
## - RECON_SITE: someone of ours observed "pos" from "observe_m" for "dwell_s" with a line of sight.
## - UNDETECTED (a bonus): done at the end of the deployment unless a hostile was in contact with us.
## - DESTROY_VEHICLES (sabotage: a vehicle park, 2026-10-20): the "vehicles" parked about "pos"
##   (MissionScenario parks them when the contract goes live); done when every one burns, is a
##   wreck or can't drive. server_cache_destroyed("cache" id) completes it too.
## - FIRE_TARGET (the forward observer, 2026-10-20; ObserverMission plays it): the "model" parked
##   at "pos"; done when it's put out of action by a fire mission's rounds (FireSupport), failed
##   when anything else does it.
const CONVOY := "convoy"
const HOLD_POINT := "hold_point"
const RESCUE_CREW := "rescue_crew"
const RECON_SITE := "recon_site"
const UNDETECTED := "undetected"
const DESTROY_VEHICLES := "destroy_vehicles"
## Missions 2 (2026-10-20; docs/missions.md):
## - KILL_HVT: the HVT ("hvt", a person MissionScenario puts there with his guard detail) is
##   dead (server_hvt_lost), or brought out (server_hvt_delivered, alive or not). His proof is
##   an EXTRACT_ITEM with "proof" (his ID papers, "of_hvt"): optional, and its objective's
##   "withheld_share" of the pay is held back when it isn't done (DebriefCalc); bringing him out
##   is proof enough.
## - DESTROY_WRECK (a crash site's bonus): a breaching charge goes off within "radius" of the
##   wreck at "pos" (server_charge_blast).
## - OVERWATCH: a friendly convoy drives "route" past the overwatch position "pos"; done when
##   "need" of its trucks are through, failed when too many are lost (MissionScenario). Its
##   bonuses are OVERWATCH objectives too: "bonus_only" (every truck through) and "held" (ours on
##   the position until it's through).
const KILL_HVT := "kill_hvt"
const DESTROY_WRECK := "destroy_wreck"
const OVERWATCH := "overwatch"
const FIRE_TARGET := "fire_target"
const KINDS: Array[String] = [CLEAR_AREA, EXTRACT_ITEM, DELIVER_HVT, DESTROY_CACHE, CONVOY, HOLD_POINT, RESCUE_CREW, RECON_SITE, UNDETECTED, DESTROY_VEHICLES,
	KILL_HVT, DESTROY_WRECK, OVERWATCH, FIRE_TARGET]
## The breaching charge item that destroys a cache when placed on it.
const CHARGE_ITEM := &"breaching_charge"
const POLL_S := 0.5

## The objective this player picked as the one to work on (ObjectivesPanel's N key): drives
## the HUD hint and marker (ObjectiveHelper). Local to each player; "" lets the helper choose
## the nearest. Objectives themselves stay host-authoritative.
static var chosen_oid := ""

## Every objective of the deployment (every peer; the host's is the truth).
var list: Array = []
var _poll := 0.0
var _armed := {}       # host: oid -> true once a CLEAR_AREA has seen a hostile (or timed out)
var _first_poll := {}  # host: oid -> msec it was first checked
var _cache_off := {}   # host: oid -> true when the voxel check is off (no baseline, or carved before deploy)
var _started := {}     # host: oid -> time (s) its clock started (timed objectives)


## Objectives from a contract's templates, placed at its target module's sites. Sites are in
## the module's own metres; `origin` is where the module sits in the level (a module of a
## world-scale zone: Contracts.module_origin), added to every position, rect and box. What a
## mission puts in the zone goes in "params" for whoever spawns it (PeopleLayer):
## - DELIVER_HVT: "hvt" is the site's HVT id made the contract's own (hvt_id), "person" who
##   they are ("side", "label", "intel" carried, each with its intel id);
## - EXTRACT_ITEM with a "place"d item: "items" is it and "intel_ids" the one the mission
##   gives it (only that piece counts); with "of_hvt": the item the HVT carries;
## - "module_id": the module (its voxel world holds a cache); "time_limit_s" from the type.
static func from_contract(contract: Dictionary, origin := Vector3.ZERO) -> Array:
	var out: Array = []
	var module_type := String(contract.get("module", ""))
	var templates: Array = contract.get("objectives", [])
	var uid := String(contract.get("uid", contract.get("cid", "")))
	for i in templates.size():
		var t: Dictionary = templates[i]
		var oid := "%s_o%d" % [contract.get("cid", "c"), i + 1]
		# A template may carry its own site ("params", in level metres: a recovery contract's
		# squadmate where they were left), else it names one of the module's.
		var site: Dictionary = (t.params as Dictionary).duplicate(true) if t.has("params") \
			else placed_site(MissionRegistry.site(module_type, String(t.get("site", ""))), origin)
		if not t.has("params"):
			if site.has("hvt"):
				site.hvt = hvt_id(String(site.hvt), uid)
				var person: Dictionary = (site.get("person", {}) as Dictionary).duplicate(true)
				person.merge(t.get("person", {}), true)
				var carried: Array = []
				for item: Variant in person.get("intel", []):
					carried.append({"id": String(item), "intel_id": "%s:%s" % [site.hvt, String(item)]})
				person["intel"] = carried
				site["person"] = person
			if t.has("items"):  # the template's own piece the HVT carries (an HVT kill's proof: his ID papers)
				site["items"] = (t.items as Array).duplicate()
				site.erase("tags")
			if bool(t.get("proof", false)):
				site["proof"] = true
			if site.has("of_hvt"):
				var of_id := hvt_id(String(MissionRegistry.site(module_type, String(site.of_hvt)).get("hvt", "")), uid)
				site["intel_ids"] = (site.get("items", []) as Array).map(func(item: Variant) -> String: return "%s:%s" % [of_id, String(item)])
			if t.has("place"):  # the template's own piece there (a story contract's: Story)
				site["place"] = String(t.place)
				site.erase("tags")
				if t.has("name"):
					site["name"] = String(t.name)
			if site.has("place"):
				site["items"] = [String(site.place)]
				site["intel_ids"] = ["intel_%s_o%d" % [uid, i + 1]]
			if contract.has("module_id"):
				site["module_id"] = String(contract.module_id)
			if t.has("site_name"):
				site["name"] = String(t.site_name)  # what the target faction calls it (ContractGen.faction_site_name)
			if t.has("loot_of"):
				site["loot_of"] = String(t.loot_of)  # its goods in a box beside it (PeopleLayer)
		if t.has("time_limit_s"):
			site["time_limit_s"] = float(t.time_limit_s)
		if contract.has("zone_id"):
			site["zone_id"] = String(contract.zone_id)  # where it plays (a multi-zone contract's legs: LZ-7)
		var obj := {
			"oid": oid, "cid": contract.get("cid", ""), "kind": t.get("kind", ""),
			"text": t.get("text", ""), "state": ACTIVE, "optional": bool(t.get("optional", false)),
			"bonus_share": float(t.get("bonus_share", 0.0)), "progress": "", "params": site, "pos": site_pos(site),
		}
		if t.has("withheld_share"):
			obj["withheld_share"] = float(t.withheld_share)  # (missions 2: the pay held back without it, DebriefCalc)
		out.append(obj)
	for k in (contract.get("legs", []) as Array).size():
		out.append_array(leg_objectives(contract, k, Vector3.ZERO, true))
	return out


## A multi-zone contract's leg `k` (LZ-7) as objectives: in its own zone at `origin` (its module's),
## or, `pending`, listed with no place yet (the squad hasn't been there), named by its zone.
static func leg_objectives(contract: Dictionary, k: int, origin: Vector3, pending: bool) -> Array:
	var leg: Dictionary = contract.legs[k]
	var as_contract := {"cid": "%s_l%d" % [contract.get("cid", "c"), k + 1], "uid": "%s_l%d" % [contract.get("uid", contract.get("cid", "")), k + 1],
		"module": leg.module, "module_id": leg.module_id, "objectives": leg.objectives, "zone_id": leg.zone_id}
	var out: Array = from_contract(as_contract, origin)
	for obj: Dictionary in out:
		obj["cid"] = contract.get("cid", "")
		obj["leg"] = k
		obj["text"] = "%s (in %s)" % [obj.text, String(leg.zone_name)]
		if pending:
			obj.params["pending"] = true
			obj["pos"] = []
	return out


## `objectives` less a multi-zone contract's legs not placed yet (LZ-7: what goes live in this
## zone; a leg goes live when the squad walks into its own, Contracts.server_arrived).
static func placed(objectives: Array) -> Array:
	return objectives.filter(func(o: Dictionary) -> bool: return not (o.get("params", {}) as Dictionary).get("pending", false))


## Whether objective `o` plays in the level the session is in now (LZ-7: a leg in another zone
## waits for the squad to walk there).
static func here(o: Dictionary, level: Node) -> bool:
	var params: Dictionary = o.get("params", {})
	if params.get("pending", false):
		return false
	var zid := String(params.get("zone_id", ""))
	if zid == "" or level == null:
		return true
	var def: Variant = level.get(&"def")
	return not def is Dictionary or String((def as Dictionary).get("id", "")) == zid or ((def as Dictionary).get("crossings", []) as Array).is_empty()


## A site's HVT id made a contract's own (each contract has its own person); `uid` "" keeps it.
static func hvt_id(base: String, uid: String) -> String:
	return base if uid == "" or base == "" else "%s_%s" % [base, uid]



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
	add_to_group(MapView.OBJECTIVE_GROUP)  # the deployment's live objectives on the map (map_objectives)
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
	var level := get_tree().get_first_node_in_group(&"level") if is_inside_tree() else null
	for o: Dictionary in list:
		var p: Array = o.get("pos", [0, 0, 0])
		if p.size() < 3 or not here(o, level):
			continue  # (a leg in another zone, LZ-7: no place on this map)
		out.append({"oid": o.oid, "pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "text": o.text, "state": o.state,
			"kind": o.kind, "optional": o.optional})
	return out


## Objective interface for the map (MapView.OBJECTIVE_GROUP): while a deployment is on, its
## objectives that play in the level the session is in now and have a place there (map_list).
## Captain, 2026-10-20 (a manhunt): "both markers show on the first map but not the second map";
## the map showed the briefing's list, the leg next door at the zone's centre and nothing after
## the crossing. The Briefing shows its own until the deployment starts.
func map_objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if list.is_empty() or not Contracts.is_deployed() or not is_inside_tree():
		return out
	out.assign(map_list(list, get_tree().get_first_node_in_group(&"level")))
	return out


## `objectives` as the map shows them in `level` (Briefing's shape: "id", "title", "pos" as a
## Vector2, "radius", "state" "open" / "done" / "failed"): those that play there (here) with a place.
static func map_list(objectives: Array, level: Node) -> Array:
	var out: Array = []
	for o: Dictionary in objectives:
		var p: Array = o.get("pos", [])
		if p.size() < 3 or not here(o, level):
			continue
		out.append({"id": String(o.oid), "title": String(o.text), "pos": Vector2(float(p[0]), float(p[2])), "radius": 6.0,
			"state": {ACTIVE: "open"}.get(String(o.state), String(o.state)), "optional": bool(o.get("optional", false))})
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
	_started.clear()
	_commit()


## Host: objectives that stand in for ones already listed (by "oid": a leg placed once the squad
## walked into its zone, LZ-7) take their places, keeping how far they got.
func server_replace(objectives: Array) -> void:
	for n: Dictionary in objectives:
		for i in list.size():
			if String(list[i].oid) == String(n.oid):
				var keep := String(list[i].state)
				list[i] = n.duplicate(true)
				list[i].state = keep
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
	_started.clear()
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
			if entry_matches(o.params, entry):
				server_set_state(o.oid, DONE)
				break


## Whether a carried-out entry ({"id", "count", "state"}) counts for an EXTRACT_ITEM's `params`:
## its item matches, and when the objective names "intel_ids" (a piece the mission placed) the
## entry is that piece (its state's "intel_id").
static func entry_matches(params: Dictionary, entry: Dictionary) -> bool:
	if not item_matches(params, StringName(entry.get("id", ""))):
		return false
	var ids: Array = params.get("intel_ids", [])
	return ids.is_empty() or String((entry.get("state", {}) as Dictionary).get("intel_id", "")) in ids


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
	_crew_event(hvt_id, true, alive)
	for o: Dictionary in active():
		if o.kind == DELIVER_HVT and String(o.params.get("hvt", hvt_id)) == hvt_id:
			server_set_state(o.oid, DONE if alive else FAILED)
		elif o.kind == KILL_HVT and String(o.params.get("hvt", "")) == hvt_id:
			server_set_state(o.oid, DONE, "brought out")  # the man himself, alive or dead: the kill and its proof
			_proof_in_person(hvt_id)


## Host: an HVT died or got away for good.
func server_hvt_lost(hvt_id: String) -> void:
	_crew_event(hvt_id, false, false)
	for o: Dictionary in active():
		if o.kind == DELIVER_HVT and String(o.params.get("hvt", hvt_id)) == hvt_id:
			server_set_state(o.oid, FAILED)
		elif o.kind == KILL_HVT and String(o.params.get("hvt", "")) == hvt_id:
			server_set_state(o.oid, DONE, "confirmed dead")


## An HVT kill's proof (EXTRACT_ITEM "proof", a piece HVT `hvt_id` carries) is done when the man
## himself is brought out.
func _proof_in_person(hvt_id: String) -> void:
	for o: Dictionary in active():
		if o.kind == EXTRACT_ITEM and bool(o.params.get("proof", false)) \
				and (o.params.get("intel_ids", []) as Array).any(func(id: Variant) -> bool: return String(id).begins_with(hvt_id + ":")):
			server_set_state(o.oid, DONE, "brought him out")


## Host: a downed crew member was delivered (alive: out; dead: lost) or lost (died): RESCUE_CREW
## objectives with that person in their "crew" count them, and finish when enough are out or too
## many are gone.
func _crew_event(hvt_id: String, delivered: bool, alive: bool) -> void:
	for o: Dictionary in active():
		if o.kind != RESCUE_CREW:
			continue
		var crew: Array = (o.params as Dictionary).get("crew", [])
		if not crew.any(func(c: Dictionary) -> bool: return String(c.hvt) == hvt_id):
			continue
		var out: Array = (o.params as Dictionary).get("out", [])
		var lost: Array = (o.params as Dictionary).get("lost", [])
		if hvt_id in out or hvt_id in lost:
			continue
		if delivered and alive:
			out.append(hvt_id)
		else:
			lost.append(hvt_id)
		o.params["out"] = out
		o.params["lost"] = lost
		var need := int(o.params.get("need", crew.size()))
		var progress := "%d of %d out%s" % [out.size(), crew.size(), (", %d lost" % lost.size()) if not lost.is_empty() else ""]
		if out.size() >= need:
			server_set_state(o.oid, DONE, progress)
		elif crew.size() - lost.size() < need:
			server_set_state(o.oid, FAILED, progress)
		else:
			server_set_state(o.oid, ACTIVE, progress)


## Host: the deployment is ending (extraction): a bonus that asked only for the squad to stay
## unseen stands if nobody spotted them (MissionScenario fails it the moment someone does).
func server_deployment_ending() -> void:
	for o: Dictionary in active():
		if o.kind == UNDETECTED:
			server_set_state(o.oid, DONE)


## Host: a cache (or a sabotage target: a vehicle park) was destroyed (by whatever means the caller saw).
func server_cache_destroyed(cache_id: String) -> void:
	for o: Dictionary in active():
		if o.kind in [DESTROY_CACHE, DESTROY_VEHICLES] and String(o.params.get("cache", cache_id)) == cache_id and here(o, CompoundLevel.current(self)):
			server_set_state(o.oid, DONE)


## Host: `soldier` sets a breaching charge against the cache of objective `oid` (a helper for
## the AI and tests; players place theirs freely, Charges): they must carry one and stand
## within "charge_reach_m" of the cache. It goes off after "charge_fuse_s" (Charges) and the
## cache counts as destroyed (server_charge_blast). Returns whether the charge was placed.
func server_place_charge(soldier: Soldier, oid: String) -> bool:
	var o := get_objective(oid)
	if o.is_empty() or o.kind != DESTROY_CACHE or o.state != ACTIVE or soldier == null or not here(o, CompoundLevel.current(self)):
		return false
	var box := _box_of(o)
	var centre := box.get_center()
	var reach := MissionRegistry.setting_f("charge_reach_m", 3.0) + box.size.length() * 0.5
	var charges := Charges.of(self)
	if charges == null or soldier.global_position.distance_to(centre) > reach or soldier.inventory.count_of(CHARGE_ITEM) <= 0:
		return false
	if charges.server_place_at(soldier, Transform3D(Basis.IDENTITY, centre)) == "":
		return false
	o.progress = "charge set"
	_commit()
	return true


## Host (Charges): a charge went off at `pos`. A cache or AA site within "charge_kill_m" of it
## is destroyed.
func server_charge_blast(pos: Vector3) -> void:
	var kill := MissionRegistry.setting_f("charge_kill_m", 1.0)
	var level := CompoundLevel.current(self)
	for o: Dictionary in active():
		if o.kind == DESTROY_WRECK and here(o, level):
			var at: Array = o.params.get("pos", [0, 0, 0])
			if Vector2(pos.x - float(at[0]), pos.z - float(at[2])).length() <= float(o.params.get("radius", 6.0)):
				server_set_state(o.oid, DONE, "wreck destroyed")
			continue
		if o.kind != DESTROY_CACHE or not here(o, level):
			continue  # (a leg's cache in another zone, LZ-7)
		var box := _box_of(o)
		var nearest := pos.clamp(box.position, box.end)
		if nearest.distance_to(pos) <= kill:
			server_set_state(o.oid, DONE)


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
	var level := get_tree().get_first_node_in_group(&"level")
	if level == null:
		return
	for o: Dictionary in active():
		if not here(o, level):
			continue  # a leg in another zone (LZ-7)
		match o.kind:
			CLEAR_AREA:
				_check_clear(o)
			DESTROY_CACHE:
				var world := world_of(level, o)
				if world:
					_check_cache(o, world)
		if (o.params as Dictionary).has("time_limit_s") and o.state == ACTIVE:
			_check_clock(o)


## The voxel world an objective's site is in: its zone module's while that is streamed in
## (null while it isn't), else the level's own (the compound).
static func world_of(level: Node, o: Dictionary) -> VoxelWorld:
	var module_id := String((o.params as Dictionary).get("module_id", ""))
	if module_id != "" and level.has_method(&"get_module"):
		var m: Node = level.call(&"get_module", module_id)
		return m.get(&"voxel_world") as VoxelWorld if m else null
	return level.get(&"voxel_world") as VoxelWorld


## Seconds left on an objective's clock (INF without one). Host.
func time_left(oid: String) -> float:
	var o := get_objective(oid)
	if o.is_empty() or not (o.params as Dictionary).has("time_limit_s"):
		return INF
	var started := float(_started.get(oid, Time.get_ticks_msec() / 1000.0))
	return float(o.params.time_limit_s) - (Time.get_ticks_msec() / 1000.0 - started)


## The clock of a timed objective (hostage, HVT): whole minutes left as its readout (a kind
## with a readout of its own keeps that), and it fails when the time runs out.
func _check_clock(o: Dictionary) -> void:
	if not _started.has(o.oid):
		_started[o.oid] = Time.get_ticks_msec() / 1000.0
	var left := time_left(o.oid)
	if left <= 0.0:
		server_set_state(o.oid, FAILED, "time ran out")
	elif o.kind in [DELIVER_HVT, EXTRACT_ITEM, KILL_HVT]:
		server_set_state(o.oid, ACTIVE, "%d min left" % ceili(left / 60.0))


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
	var virtualizer := Virtualizer.of(self)
	if virtualizer:
		n += virtualizer.count_in(rect, &"hostile")  # a garrison at its posts as a profile is still there
	return n


func _check_clear(o: Dictionary) -> void:
	if not _garrisoned(o):
		return  # nobody has been there yet: an unvisited site isn't a cleared one
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


## Whether a CLEAR_AREA's site has had its garrison put in. In a zone, hostiles come with
## their module when it first streams in (ZoneLevel.garrison_spawned), so until then the site
## is empty because nobody has been near it, not because it was cleared: the check (and its
## arm timeout) waits. A site whose garrison fell on an earlier visit, or whose module holds
## no posts, counts as put in once it streams in, and then completes as clear. Levels without
## streamed garrisons (the compound) have nothing to wait for.
func _garrisoned(o: Dictionary) -> bool:
	var module_id := String((o.params as Dictionary).get("module_id", ""))
	var level := get_tree().get_first_node_in_group(&"level")
	if module_id == "" or level == null or not level.has_method(&"garrison_spawned"):
		return true
	return bool(level.call(&"garrison_spawned", module_id))


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
