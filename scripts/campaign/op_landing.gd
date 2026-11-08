class_name OpLanding
extends OpBase
## The beach landing (docs/combined_arms.md 6.4.2; phase D5, cg_brief queue item 3.3). Coast only
## (the type's "region"); the zone's sea is on the friendly edge and the LHD stands off it (D1-2,
## Lhd). H-hour is at dawn: the contract's sky starts the deployment "lead_s" before it (the
## contract's "hour"), H-hour comes when wave 1's first AAV is on the beach, or at lead_s.
##
## - The company starts in its AAVs in the LHD's well deck: as the run starts, wave 1's AAVs come
##   out of the stern gate one after another (Lhd.launch_transform, "stern_step_m" apart), each
##   waiting in the well deck until its men are aboard (they come out on Operations' budget of men a
##   frame, F-468; Captain, 2026-11-08: an AAV never leaves half boarded): the
##   company's "company_aavs" with an allied crew (driver and gunner), the players and the company's
##   own men seated in the back (a player joining before the beach is seated too), and "allied_aavs"
##   with the friendly OOB's wave-0 rifle squads aboard ("carrier": "aav"). Wave 2 ("wave2_aavs",
##   the wave-4 squads) follows "wave2_s" later. Each swims round the hull (AavSupport's swim path:
##   Lhd.approach_point, then the shore) to its own lane ("lane_m" apart round the beach exit) and
##   drives "beach_in_m" up the sand; there the ramp drops: the AI aboard dismounts (players get out
##   themselves), the AAVs stay with their M2s on the beach (AavGunner).
## - Before H-hour (6.4.2): "prep_s" before it, the allied artillery and naval gunfire on the known
##   beach defences only (the enemy's sites within "defence_m" of the beach exits, the OOB's
##   entries marked "known"); "smoke_s" before it, smoke on the beach exits.
## - Phases (data): the beachhead (the company: the left beach exit; the allies: the right one and
##   the bunkers), the harbour and the coastal village (the company: the harbour's quays and sheds),
##   then the beachhead held "hold" minutes against the counterattack (OpBase.counter_step, its
##   axis chosen from the enemy's picture).
## - Fail: wave 1 loses more than "lost_share" of its AAVs before the beach, or the enemy holds the
##   beachhead for "hold_fail_s" with none of ours in it.
## Not built: the host's x4 time afloat out of contact (F-294); troops at the AAV's open hatches
## (the FFV positions: F-295). Numbers in data/operations.json "beach_landing" "landing", Proposed.

const TICK_S := 0.5
const BOARDING := "boarding"  # an AAV's state in the well deck while its crew and squad come out
const RETURN_WAVE_BACK_M := 15.0  # Proposed: a squad brought back on a load (F-481) stands this much further up the sand per wave, so a wave 2 squad doesn't land on a wave 1 squad in the same lane

var _tick_left := 0.0
var _aav := {}  # host: aav id -> Vehicle
var _spawn_queue: Array = []
var _boarding: Array = []  # host: AAVs in the well deck with men still to come out (spawn_step): {"a", "v", "squad", "seats", "n", "riders", "entry", "allied", "i", "made"}


func start() -> void:
	var m := mine()
	if not m.has("waves_aav"):
		var list: Array = []
		var carried: Dictionary = {0: [], 1: []}
		for e: Dictionary in run().get("oob", []):
			if String(e.side) == "friendly" and String(e.get("carrier", "")) == "aav":
				e["by_type"] = true  # (they come in this way, not by Operations' spawner)
				carried[0 if float(e.get("wave_s", 0.0)) <= 0.0 else 1].append(String(e.id))
		var k := 0
		var lanes := int(num("landing", "company_aavs", 2)) + int(num("landing", "allied_aavs", 4))
		for i in int(num("landing", "company_aavs", 2)):
			list.append({"id": "aav%d" % (k + 1), "wave": 1, "role": "company", "entry": "", "state": Operations.PENDING, "lane": k, "lanes": lanes})
			k += 1
		for i in int(num("landing", "allied_aavs", 4)):
			var entry: String = carried[0][i] if i < (carried[0] as Array).size() else ""
			list.append({"id": "aav%d" % (k + 1), "wave": 1, "role": "allied", "entry": entry, "state": Operations.PENDING, "lane": k, "lanes": lanes})
			k += 1
		var w2 := int(num("landing", "wave2_aavs", 2))
		for i in w2:
			var entry: String = carried[1][i] if i < (carried[1] as Array).size() else ""
			list.append({"id": "aav%d" % (k + 1), "wave": 2, "role": "allied", "entry": entry, "state": Operations.PENDING, "lane": i * 2 + 1, "lanes": lanes})
			k += 1
		m["waves_aav"] = list
		m["lost_afloat"] = 0
		m["landed"] = 0
		m["prep"] = false
		m["smoke"] = false
	else:
		for a: Dictionary in m.waves_aav:
			if String(a.state) == BOARDING:
				a.state = Operations.PENDING  # (a loaded save: half boarded, it comes out again from nothing; Operations has its squad's entry pending again)
				a.erase("vid")
			if String(a.state) in ["afloat", "landed"] and String(a.get("vid", "")) != "":
				var layer := VehicleLayer.of(self)
				var v := layer.find(String(a.vid)) if layer else null
				if v:
					_aav[String(a.id)] = v
				elif String(a.state) == "afloat":
					a.state = "landed"  # (a loaded save after the AAVs went: they're ashore)
		_hand_back_carried()
	var lvl := level()
	if lvl:
		var players: Node = lvl.get(&"players")
		if players and not players.child_entered_tree.is_connected(_on_player):
			players.child_entered_tree.connect(_on_player)
	_refresh()


func waves() -> Array:
	return mine().get("waves_aav", [])


func aav_of(id: String) -> Vehicle:
	var v: Variant = _aav.get(id)
	return v as Vehicle if is_instance_valid(v) and not (v as Vehicle).is_queued_for_deletion() else null


## H-hour: wave 1 on the beach, or lead_s into the run (the dawn the deployment started before).
func h_hour() -> bool:
	return int(mine().get("landed", 0)) > 0 or clock() >= num("landing", "lead_s", 600.0)


func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick_left -= dt
	var m := mine()
	if m.is_empty():
		return
	var lead := num("landing", "lead_s", 600.0)
	var t := clock()
	# The waves out of the well deck.
	for a: Dictionary in waves():
		var due := num("landing", "launch_s", 20.0) + (num("landing", "wave2_s", 240.0) if int(a.wave) == 2 else 0.0)
		if String(a.state) == Operations.PENDING and t >= due:
			_launch(a)
			break  # (one a tick)
	# Before H-hour: the fires on the known defences, then smoke on the beach exits.
	if String(run().get("state", "")) == Operations.WAITING or t < lead + 5.0:
		if not bool(m.prep) and t >= lead - num("landing", "prep_s", 120.0):
			m.prep = true
			_prep_fires()
		if not bool(m.smoke) and t >= lead - num("landing", "smoke_s", 30.0):
			m.smoke = true
			_smoke()
	var t1 := Time.get_ticks_usec()
	_watch_aavs()
	var t2 := Time.get_ticks_usec()
	# Phase 3: the counterattack on the beachhead, and holding it.
	var phases: Array = contract().get("phases", [])
	var k := phase()
	if String(run().get("state", "")) == Operations.RUNNING and k == phases.size() - 1:
		var bh := beachhead()
		var axis := ops._axis()
		counter_step("landing", bh, axis, [])
		if held_by_enemy("beachhead", bh, num("landing", "hold_m", 200.0), dt, num("landing", "hold_fail_s", 60.0)):
			note("The enemy took the beachhead back.")
			stall("the beachhead was lost")
	var t3 := Time.get_ticks_usec()
	_refresh()
	cost_us = float(Time.get_ticks_usec() - t0)
	if not heavy and cost_us > worst_us:
		worst_us = cost_us
		worst_what = "waves and fires %d, AAVs %d, beachhead %d, strip %d µs" % [t1 - t0, t2 - t1, t3 - t2, Time.get_ticks_usec() - t3]
	heavy = false


func beachhead() -> Vector3:
	return v3(ops.def.op.get("start", [0, 0]))


## Where AAV `a`'s lane lands: lane_m apart across the axis round the beach exit, beach_in_m up the sand.
func lane_target(a: Dictionary) -> Vector3:
	var axis := ops._axis()
	var left := Vector3(-axis.y, 0, axis.x)
	var off := (float(a.lane) - (float(a.lanes) - 1.0) / 2.0) * num("landing", "lane_m", 70.0)
	return beachhead() + left * off


func _launch(a: Dictionary) -> void:
	var lhd := Lhd.of(self)
	var layer := VehicleLayer.of(self)
	var terrain := _terrain()
	if lhd == null or layer == null or terrain == null:
		return
	var t := lhd.launch_transform()
	var astern := Vector3(lhd.global_basis.z.x, 0.0, lhd.global_basis.z.z).normalized()  # (the ship's bow is -z: out of the gate, further astern each)
	var i := waves().find(a) % maxi(int(a.lanes), 1)
	t.origin += astern * num("landing", "stern_step_m", 14.0) * float(i)
	var v := layer.server_spawn(String(num_s("model", "aav7")), t, "", &"friendly", "")
	heavy = true
	if v == null:
		return
	v.set_meta(&"no_save", true)
	v.set_meta(&"op_aav", String(a.id))
	_aav[String(a.id)] = v
	a["vid"] = v.vehicle_id
	a.state = BOARDING  # (it waits in the well deck for its men: Captain, 2026-11-08)
	AavGunner.attach(v)
	v.destroyed.connect(_on_aav_lost.bind(String(a.id)))
	# The crew: an allied driver and gunner.
	var squad := Squad.new()
	squad.name = ops._fresh_name("AAV")
	squad.faction = &"friendly"
	squad.callsign = "Gator %d" % (waves().find(a) + 1)
	ops.add_child(squad)
	var seats: Array = [OpSupport._seat_of_kind_any(v, Vehicle.DRIVER), int(v.spec.get("gun", {}).get("seat", -1))].filter(func(n: int) -> bool: return n >= 0)
	_boarding.append({"a": a, "v": v, "squad": squad, "seats": seats, "n": 0, "riders": false, "entry": {}, "allied": null, "i": 0, "made": []})


## Host, every frame: the AAVs' men come out on Operations' shared budget, the AAV first (out in
## _launch), its crew, then who rides; it leaves the well deck once they're all aboard.
func spawn_step() -> bool:
	while not _boarding.is_empty():
		var job: Dictionary = _boarding[0]
		var a: Dictionary = job.a
		if not is_instance_valid(job.v) or not is_instance_valid(job.squad) or (job.v as Vehicle).is_queued_for_deletion() or String(a.state) != BOARDING:
			_boarding.pop_front()  # (lost in the well deck: _on_aav_lost said so)
			_abandon(job)
			continue
		var v := job.v as Vehicle
		if not _board_step(job, v):
			return true
		_boarding.pop_front()
		_set_off(a, v)
	return false


## An AAV lost in the well deck: its squad's entry is finished (whoever had come out goes to the
## commander; if nobody had, the squad is gone with its AAV) and its crew's squad goes if nobody
## came out to belong to it, as OpSupport's does.
func _abandon(job: Dictionary) -> void:
	var e := _entry_of(job.a)
	if is_instance_valid(job.allied):
		ops._finish_job({"entry": job.entry, "squad": job.allied, "vehicles": [], "made": job.made})
	elif not e.is_empty() and String(e.state) in [Operations.PENDING, "spawning"]:
		e.state = "gone"
	if int(job.n) == 0 and is_instance_valid(job.squad):
		(job.squad as Squad).queue_free()


## One AAV's men, as many as the frame's budget allows. True once they're all aboard.
func _board_step(job: Dictionary, v: Vehicle) -> bool:
	var a: Dictionary = job.a
	while int(job.n) < (job.seats as Array).size():
		if ops.spawn_men_left() <= 0:
			return false
		var s := ops._spawn_man({"side": "friendly", "kit": ""}, job.squad, int(job.n), v.global_position + Vector3.UP * 3.0)
		var seat: int = job.seats[job.n]
		job.n = int(job.n) + 1
		if s:
			s.set_meta(&"vehicle_crew", v.vehicle_id)
			s.set_meta(&"op_allied", true)
			v.server_enter(s, seat)
	# Who rides: the company (players first; they're here already) or an allied squad.
	if not bool(job.riders):
		job.riders = true
		if String(a.role) == "company":
			for s: Soldier in _company():
				if Vehicle.ride_of(s) == null:
					v.server_enter(s, -1)
		elif String(a.entry) != "":
			_board_allied(job)
	if job.allied == null:
		return true
	var e: Dictionary = job.entry
	while int(job.i) < int(e.men):
		if ops.spawn_men_left() <= 0:
			return false
		var i := int(job.i)
		job.i = i + 1
		var s := ops._spawn_man(e, job.allied, i, v.global_position + Vector3.UP * 3.0 + Vector3.RIGHT * i)
		if s == null:
			continue
		s.set_meta(&"op_group", String(e.id))
		s.set_meta(&"op_allied", true)
		v.server_enter(s, -1)
		(job.made as Array).append(s)
	ops._finish_job({"entry": e, "squad": job.allied, "vehicles": [], "made": job.made})
	return true


## All aboard: out of the stern gate and round the hull for its lane.
func _set_off(a: Dictionary, v: Vehicle) -> void:
	var lhd := Lhd.of(self)
	var terrain := _terrain()
	if lhd == null or terrain == null:
		return
	a.state = "afloat"
	var swim := PackedVector3Array([lhd.approach_point(v.global_position), terrain.shore_point(lane_target(a), -num("landing", "beach_out_m", 40.0)),
		terrain.shore_point(lane_target(a), num("landing", "beach_in_m", 45.0))])
	v.server_follow_path(swim)
	a["path"] = [[swim[1].x, swim[1].z], [swim[2].x, swim[2].z]]
	SessionLog.note("operation %s: %s (wave %d, %s) out of the well deck, swimming for %s" % [ops.cid, String(a.id), int(a.wave), String(a.role), grid_ref(swim[2])])
	if waves().find(a) == 0:
		say("Gator 1: wave 1 is out of the well deck. %d minutes to the beach." % maxi(roundi(v.global_position.distance_to(swim[2]) / 3.6 / 60.0), 1))
	_refresh()


func num_s(key: String, fallback: String) -> String:
	return String(cfg("landing").get(key, fallback))


## The company's people: the players, then its own soldiers (not the allies', crews or civilians).
func _company() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for p: Node in ops._players():
		out.append(p as Soldier)
	for node in get_tree().get_nodes_in_group(&"combatants"):
		var s := node as Soldier
		if s == null or s in out or not s.vitals.is_up() or not (s.faction in [&"friendly", &"player"]) or Person.is_person(s):
			continue
		if s.has_meta(&"op_allied") or s.has_meta(&"allied_element") or s.has_meta(&"vehicle_crew") or s.has_meta(&"op_group"):
			continue
		out.append(s)
	return out


## Allied OOB entry `a.entry`'s squad starts coming out aboard its AAV (Operations' spawner's men,
## its commander's): spawn_step brings them, on the shared budget.
func _board_allied(job: Dictionary) -> void:
	var e := _entry_of(job.a)
	if e.is_empty() or String(e.state) != Operations.PENDING:
		return
	e.state = "spawning"
	var squad := Squad.new()
	squad.name = ops._fresh_name(String(e.callsign))
	squad.faction = &"friendly"
	ops.add_child(squad)
	job.entry = e
	job.allied = squad


## AAV `a`'s squad's OOB entry, {} if it carries none.
func _entry_of(a: Dictionary) -> Dictionary:
	if String(a.entry) != "":
		for x: Dictionary in run().get("oob", []):
			if String(x.id) == String(a.entry):
				return x
	return {}


## A loaded save: a squad whose AAV had left the well deck has nothing to come in by any more (the
## AAV wasn't saved; one still to launch takes its squad as ever), and Operations won't bring out a
## "by_type" group. So it's Operations' now: on the sand of its own lane round the beach exit, at
## once, and from then on where it stands, as any allied group after a load (F-481). Whoever is left
## of it: Operations' save counted its men, and a squad wiped out in the water is "gone" already.
func _hand_back_carried() -> void:
	var terrain := _terrain()
	var inland := num("landing", "beach_in_m", 45.0)
	for a: Dictionary in waves():
		var e := _entry_of(a)
		if e.is_empty() or not String(a.state) in ["afloat", "landed", "lost"] or String(e.state) != Operations.PENDING or not bool(e.get("by_type", false)):
			continue
		var at := lane_target(a)
		if terrain:
			at = terrain.shore_point(at, inland + RETURN_WAVE_BACK_M * (int(a.wave) - 1))
		e.erase("by_type")
		e["wave_s"] = 0.0
		e["pos"] = [snappedf(at.x, 1.0), snappedf(at.z, 1.0)]
		SessionLog.note("operation %s: %s's squad %s back at %s after the load" % [ops.cid, String(a.id), String(e.callsign), grid_ref(at)])


## A player who comes in while wave 1 is boarding or afloat gets a seat in a company AAV.
func _on_player(n: Node) -> void:
	if not _host():
		return
	_seat_player.call_deferred(n)


func _seat_player(n: Node) -> void:
	var s := n as Soldier
	if s == null or not is_instance_valid(s) or Vehicle.ride_of(s) != null:
		return
	for a: Dictionary in waves():
		var v := aav_of(String(a.id))
		if v and String(a.role) == "company" and String(a.state) in ["afloat", BOARDING] and v.server_enter(s, -1):
			SessionLog.note("operation %s: %s seated in %s %s" % [ops.cid, s.name, String(a.id), String(a.state)])
			return


func _on_aav_lost(_v: Vehicle, id: String) -> void:
	var m := mine()
	for a: Dictionary in waves():
		if String(a.id) != id:
			continue
		var afloat := String(a.state) in ["afloat", BOARDING]
		a.state = "lost"
		if afloat and int(a.wave) == 1:
			m["lost_afloat"] = int(m.get("lost_afloat", 0)) + 1
		note("%s (wave %d) was lost %s." % [String(a.id).to_upper(), int(a.wave), "in the water" if afloat else "on the beach"])
		var wave1 := waves().filter(func(x: Dictionary) -> bool: return int(x.wave) == 1).size()
		if int(m.lost_afloat) > wave1 * num("landing", "lost_share", 0.5):
			note("Wave 1 lost %d of its %d AAVs before the beach." % [int(m.lost_afloat), wave1])
			heavy = true
			ops._stall(contract(), phase(), "wave 1 lost more than half its AAVs before the beach")
	_refresh()


## Each AAV afloat that's ashore (on land, its swim done): the ramp drops.
func _watch_aavs() -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var m := mine()
	for a: Dictionary in waves():
		if String(a.state) != "afloat":
			continue
		var v := aav_of(String(a.id))
		if v == null:
			continue
		var p := v.global_position
		var ashore := terrain.height_at(p.x, p.z) > terrain.water_height(p.x, p.z) + 0.2
		var done := not is_instance_valid(v.ai) or not v.ai.active or v.ai.remaining() < 6.0
		if ashore and done:
			_land(a, v)
			m["landed"] = int(m.get("landed", 0)) + 1


func _land(a: Dictionary, v: Vehicle) -> void:
	heavy = true  # (its men out into the world)
	a.state = "landed"
	a["landed_s"] = clock()
	v.server_stop()
	var out := 0
	for s: Soldier in v.occupants():
		if s.has_meta(&"vehicle_crew") or not s.is_ai() or not s.vitals.is_up():
			continue
		v.server_exit(s)
		out += 1
	var wave1_first := waves().filter(func(x: Dictionary) -> bool: return String(x.state) == "landed").size() == 1
	if wave1_first:
		note("Wave 1 hit the beach at %s." % Operations.clock_text(clock()))
		say("Gator: wave 1 on the beach! Ramps down, out, out!")
	for p: Node in ops._players():
		if Vehicle.ride_of(p as Soldier) == v:
			Contracts._notify_all("Ramp down! Out of the AAV!")
			break
	SessionLog.note("operation %s: %s landed at %s, %d dismounted" % [ops.cid, String(a.id), grid_ref(v.global_position), out])


## The known beach defences: the enemy's sites within defence_m of the beach exits, the OOB's "known".
func known_defences() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var reach := num("landing", "defence_m", 900.0)
	var bh := beachhead()
	for m: Dictionary in ops.def.get("modules", []):
		if not ZoneModules.base(String(m.type)) in Operations.ENEMY_SITES:
			continue
		var p := v3(m.pos)
		if Vector2(p.x - bh.x, p.z - bh.z).length() <= reach:
			out.append(p)
	for e: Dictionary in run().get("oob", []):
		if String(e.side) == "hostile" and bool(e.get("known", false)):
			out.append(v3(e.pos))
	return out


func _prep_fires() -> void:
	heavy = true  # (fire missions planned: the guns' cost, once)
	var sup := ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport
	if sup == null:
		return
	var targets := known_defences()
	var hit := 0
	for at: Vector3 in targets.slice(0, int(num("landing", "prep_targets", 4))):
		for unit: String in ["artillery", "naval"]:
			if sup.fire(unit, at, int(num("landing", "prep_rounds", 3)), "he", "before H-hour") == "":
				hit += 1
	note("Before H-hour the guns fired on %d known beach defence%s." % [mini(targets.size(), int(num("landing", "prep_targets", 4))), "" if targets.size() == 1 else "s"])
	say("Thunder 1, Trident 2: preparation fires on the beach defences, two minutes.")
	SessionLog.note("operation %s: prep fires, %d missions on %d targets" % [ops.cid, hit, targets.size()])


func _smoke() -> void:
	heavy = true  # (fire missions planned: the guns' cost, once)
	var sup := ops.get_node_or_null(OpSupport.NODE_NAME) as OpSupport
	if sup == null:
		return
	for sel: String in ["left", "right"]:
		var ex := OpTypes.resolve_extra(ops.def, {"exit": sel})
		if ex.is_empty():
			continue
		var at := v3(ex[0].pos)
		if sup.fire("naval", at, 2, "smoke", "smoke on the beach") != "":
			sup.fire("artillery", at, 2, "smoke", "smoke on the beach")
	say("Trident 2: smoke on the beach.")


func _terrain() -> ZoneTerrain:
	var lvl := level()
	var t: Variant = lvl.get(&"terrain") if lvl else null
	return t as ZoneTerrain if t is ZoneTerrain else null


func strip_line() -> String:
	var aavs: Array = state.get("aavs", [])
	if aavs.is_empty():
		return ""
	var count := func(st: String) -> int: return aavs.filter(func(a: Dictionary) -> bool: return String(a.state) == st).size()
	return "AAVs: %d afloat, %d ashore, %d lost" % [count.call("afloat"), count.call("landed"), count.call("lost")]


func _refresh() -> void:
	var list: Array = []
	for a: Dictionary in waves():
		list.append({"id": String(a.id), "wave": int(a.wave), "role": String(a.role), "state": String(a.state), "vid": String(a.get("vid", ""))})
	var s := {"aavs": list, "lost_afloat": int(mine().get("lost_afloat", 0)), "landed": int(mine().get("landed", 0))}
	if s != state:
		state = s
		publish()
