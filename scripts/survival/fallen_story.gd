class_name FallenStory
extends RefCounted
## The enclave, ARCHE's trail, the bunkers and the cure chain's places on the world sim
## (docs/survival_enclave.md; survival_world.md sections 6-7, survival_medical.md section 3):
## the one place WorldSim calls them from. server_setup runs once a world (WorldSim.server_setup,
## or lazily on the first far tick of a world made before this lane); server_after_step runs on
## the main thread after every far tick, with the model bound to the live world, so its writes
## to the world section are safe there. Their own state lives beside the world section, never
## in it (Survival.state()["enclave"], ["arche"], ["bunkers"], ["cure"]), so a far tick out on
## the worker never overwrites it. world_do / event are for changes made from the players' side
## (a toll paid, a bunker opened) while a tick may be out: through WorldSim.mutate.


## Host, main thread: everything set up on the world `m` (a model bound to the live state).
static func server_setup(m: WorldModel) -> void:
	EnclaveNode.ensure()
	Enclave.server_setup(m)
	Bunkers.server_setup(m)
	ArcheTrail.server_setup(m)
	Cure.server_setup(m)


## Host, main thread, after each far tick (WorldSim._after_step).
static func server_after_step(m: WorldModel) -> void:
	if not Enclave.is_set_up() or not Bunkers.is_set_up() or not ArcheTrail.is_set_up() or not Cure.is_set_up():
		server_setup(m)
	EnclaveNode.ensure()
	Enclave.server_after_step(m)
	Bunkers.server_after_step(m)
	ArcheTrail.server_after_step(m)


## Host: `fn` (taking the world section) now, and again on a far tick's result if one is out.
static func world_do(fn: Callable) -> void:
	var sim := WorldSim.get_sim()
	if sim:
		sim.mutate(fn)
	else:
		fn.call(WorldSim.section())


## Host: an event in the world's pool from the players' side (`extra` merged into it): told to
## the event_added listeners (the radio and intel lanes) and, when near, the journal.
static func event(zone_id: String, kind: String, gids: Array, text: String, place := "", extra := {}) -> Dictionary:
	var made: Array = []
	world_do(func(w: Dictionary) -> void:
		var m := WorldModel.new(w, WorldSim.people(), WorldSim.pressure_section(), WorldSim.world_seed())
		m.now = WorldSim.world_now()
		var e := m.event(zone_id, kind, gids, text, place)
		e.merge(extra, true)
		if made.is_empty():
			made.append(e))
	var out: Dictionary = made[0] if not made.is_empty() else {}
	var sim := WorldSim.get_sim()
	if sim and not out.is_empty():
		sim.event_added.emit(out)
	return out


## A main-thread model bound to the live world (WorldSim.model) for the players' side's calls
## that need people made or killed. Only when no far tick is out (else through world_do).
static func live_model() -> WorldModel:
	return WorldSim.model()


## A deterministic roll for `who`/`why` from the world seed (no tick: the same every time).
static func rng(who: String, why: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.world_seed(), who, why])
	return r


## Every player in the hosted level.
static func players() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	var lvl: CompoundLevel = CompoundLevel.current(tree.root) if tree else null
	var out: Array = []
	if lvl:
		for p: Soldier in MapNodes.players(lvl):
			out.append(p)
	return out


static func tell_all(text: String) -> void:
	for p: Soldier in players():
		Survival._tell(p, text)


## A world zone's first place's position as [x, z] (its centre when it has none).
static func zone_pos(zone_id: String) -> Array:
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone_id, {})
	var places: Array = zd.get("places", [])
	if places.is_empty():
		return [0.0, 0.0]
	var p: Array = (places[0] as Dictionary).get("pos", [0.0, 0.0])
	return [float(p[0]), float(p[1])]


static func zone_name(zone_id: String) -> String:
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone_id, {})
	return String(zd.get("name", RegionMap.zone_name(zone_id)))


## Whether `s` carries at least `n` of `item_id`.
static func has_item(s: Soldier, item_id: String, n := 1) -> bool:
	return s != null and s.inventory != null and s.inventory.count_of(StringName(item_id)) >= n


## Host: takes one `item_id` from `s`; whether it had one.
static func take_one(s: Soldier, item_id: String) -> bool:
	return s != null and s.inventory != null and s.inventory.remove_one(StringName(item_id))
