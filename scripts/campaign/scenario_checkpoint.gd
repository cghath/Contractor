class_name ScenarioCheckpoint
extends RefCounted
## Serializable scenario state, with stable identities rather than references to a retired level.

static func capture(run: Dictionary, previous := {}) -> Dictionary:
	var out := {}
	for key: String in run:
		if key not in ["vehicles", "crew", "ambush", "waves", "wreck", "route", "group"]:  # ("group": the convoy as the Virtualizer tracks it)
			out[key] = run[key]
	if run.has("route"):
		out["route"] = _points(run.route)
	for key: String in ["crew", "ambush", "waves"]:
		if run.has(key):
			out[key] = _actors(run[key], previous.get(key, []))
	if run.has("wreck") and is_instance_valid(run.wreck):
		out["wreck"] = (run.wreck as Vehicle).to_save()
	if run.has("vehicles"):
		out["vehicles"] = []
		for i in (run.vehicles as Array).size():
			var e: Dictionary = run.vehicles[i]
			var old: Dictionary = previous.get("vehicles", [])[i] if i < (previous.get("vehicles", []) as Array).size() else {}
			var v := e.v as Vehicle if is_instance_valid(e.v) else null
			var saved := {"cargo": e.cargo, "crate": e.crate, "out": e.out, "hit": e.hit, "down": e.get("down", false),
				"vehicle": v.to_save() if v and not v.is_queued_for_deletion() else {}, "crew": _actors(e.crew, old.get("crew", [])), "seats": []}
			for s: Variant in e.crew:
				saved.seats.append(v.seat_of(s) if v and is_instance_valid(s) else -1)
			if v and v.ai:
				saved["drive"] = {"path": _points(v.ai.path), "index": v.ai.index, "active": v.ai.active, "speed": v.ai.cruise_ms}
			out.vehicles.append(saved)
	return out


static func _points(points: PackedVector3Array) -> Array:
	var out := []
	for p: Vector3 in points:
		out.append([p.x, p.y, p.z])
	return out


static func _route(points: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Array in points:
		out.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return out


static func _actors(actors: Array, previous: Array) -> Array:
	var out := []
	for i in actors.size():
		var s := actors[i] as Soldier if is_instance_valid(actors[i]) else null
		if s == null or s.is_queued_for_deletion():
			var absent: Dictionary = previous[i].duplicate(true) if i < previous.size() else {}
			absent["absent"] = true  # carried out or removed: do not manufacture a replacement
			out.append(absent)
			continue
		if s.body_uid == "":
			s.body_uid = GameState.new_uid()
		var people := PeopleLayer.find(s)
		var brain := SquadAI.of(s)
		out.append({"body": s.body_record(), "name": String(s.name), "person": people.state_of(s).duplicate(true) if people else {},
			"vitals": var_to_str(s.vitals.server_snapshot()), "dead": s.vitals.is_dead(),
			"combat": brain.combat if brain else 0.4, "discipline": brain.discipline if brain else 0.5})
	return out


static func restore(scenario: MissionScenario, saved: Dictionary) -> Dictionary:
	var run := saved.duplicate(true)
	if run.has("route"):
		run.route = _route(run.route)
	for key: String in ["crew", "ambush", "waves"]:
		if run.has(key):
			run[key] = _restore_actors(scenario, run[key])
	if run.has("wreck"):
		run.wreck = _vehicle(scenario, run.wreck)
	if run.has("vehicles"):
		for e: Dictionary in run.vehicles:
			var v := _vehicle(scenario, e.vehicle)
			e["v"] = v
			e.crew = _restore_actors(scenario, e.crew)
			if v == null:
				continue
			for i in (e.crew as Array).size():
				var s := e.crew[i] as Soldier
				var seat := int(e.seats[i])
				if s and s.vitals.is_up() and seat >= 0 and v.occupant(seat) == null:
					v.server_enter(s, seat)
			AavGunner.attach(v)
			v.damaged.connect(scenario._on_convoy_hit.bind(e))
			var drive: Dictionary = e.get("drive", {})
			if not drive.is_empty() and bool(drive.active) and not bool(e.out) and not bool(e.down):
				v.server_follow_path(_route(drive.path), float(drive.speed) * 3.6)
				v.ai.index = int(drive.index)
			e.erase("vehicle")
	return run


static func _vehicle(scenario: MissionScenario, record: Dictionary) -> Vehicle:
	if record.is_empty():
		return null
	var layer := scenario.level.get_node_or_null(^"Vehicles") as VehicleLayer
	if layer == null:
		return null
	var v := layer.find(String(record.id))
	return v if v else layer.server_spawn(String(record.model), Transform3D.IDENTITY, String(record.get("scheme", "")),
		StringName(String(record.faction)), String(record.id), record)


static func _restore_actors(scenario: MissionScenario, records: Array) -> Array:
	var out := []
	var people := PeopleLayer.find(scenario)
	for record: Dictionary in records:
		var body: Dictionary = record.get("body", {})
		var state: Dictionary = record.get("person", {})
		var s: Soldier
		for n: Node in scenario.get_tree().get_nodes_in_group(&"combatants") + scenario.get_tree().get_nodes_in_group(Soldier.DEAD_GROUP):
			if n is Soldier and not n.is_queued_for_deletion() and String(body.get("uid", "")) != "" and (n as Soldier).body_uid == String(body.uid):
				s = n as Soldier
				break
		if s == null and people and String(state.get("hvt_id", "")) != "":
			s = people.hvt(String(state.hvt_id))
		var delivered := People.is_delivered(String(state.get("hvt_id", "")))
		if s == null and not record.get("absent", false) and not body.is_empty() and not state.get("delivered", false) and not delivered:
			if bool(record.get("dead", false)):
				s = scenario.level.server_spawn_body(body)
			elif people and not state.is_empty():
				s = people.server_spawn_person({"name": record.name, "kind": state.kind, "side": state.side,
					"hvt_id": state.get("hvt_id", ""), "label": body.label, "pos": MissionScenario._p3(body.pos)})
			else:
				s = scenario._convoy_soldier({}, ("Scenario_" + String(body.uid)).validate_node_name(), MissionScenario._p3(body.pos), float(record.get("combat", 0.4)),
					{"pos": MissionScenario._p3(body.pos), "variant": body.variant, "body": body.get("body", ""), "faction": body.faction,
					"person_name": body.get("person_name", ""), "discipline": float(record.get("discipline", 0.5))})
			if s:
				s.body_uid = String(body.uid)
				s.rotation.y = float(body.get("rot_y", 0.0))
				s.inventory.net_state = GameState.from_json(body.get("gear", {}))
				var vitals: Variant = str_to_var(String(record.get("vitals", "")))
				if vitals is Dictionary and not bool(record.get("dead", false)):
					s.vitals.server_restore(vitals)
				if people and not state.is_empty():
					people.server_set_state(s, state)
		out.append(s)
	return out
