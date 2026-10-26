class_name HeliCrew
extends RefCounted
## The downed helicopter's crew and the enclave's reward (docs/survival_events.md section 1c): the
## crew of a heli_down event are lone survivors at the wreck ("heli_crew", the event in
## "heli_event"). Host; numbers in data/survival_convoy.json "crew" (Proposed).
## - "Come with me" (the talk menu on a crew member out there): they follow as a companion
##   ("heli_escort"), across zones like any companion.
## - Delivered: walked within deliver_m of an enclave post (SurvivorsLayer's tick checks it), or
##   "Radio a pickup" (the talk menu on an escorted one, with a repaired, powered radio carried):
##   they go back to the enclave (Enclave._take_person), its standing with the players + standing
##   each, a reward set (crew "reward" rows, a serum dose at serum_chance) into the deliverer's kit,
##   a journal line and a broadcast (the radio's enclave channel). A dead one's tags ("Take their
##   tags" on the body) count tags_standing at a post or with a pickup call.
## - Left: the enclave reclaims the crew still out there at the window's end (WorldEvents.tick), and
##   a player who came within near_m and left them costs ignore_standing ("near" on the record).

static func cfg() -> Dictionary:
	return FallenConvoy.data().get("crew", {})


static func is_crew(rec: Dictionary) -> bool:
	return bool(rec.get("heli_crew", false))


static func is_escort(rec: Dictionary) -> bool:
	return is_crew(rec) and bool(rec.get("heli_escort", false)) and String(rec.get("status", "")) == "companion"


## The heli_down record that `rec` came down with ({} none).
static func event_of(rec: Dictionary) -> Dictionary:
	var pid := String(rec.get("id", ""))
	for r: Dictionary in WorldEvents.records(WorldSim.section()).values():
		if String(r.get("kind", "")) == "heli_down" and pid in (r.get("crew", []) as Array):
			return r
	return {}


## Host: "Come with me": the crew member `rec` (out there, his body here) follows `by` as a
## companion. Returns the line said ("" when not).
static func server_come(layer: SurvivorsLayer, by: Soldier, rec: Dictionary) -> String:
	if layer == null or not is_crew(rec) or String(rec.get("status", "")) != "out_there":
		return ""
	var body := layer.body_of(String(rec.id))
	var at := body.global_position if body else SurvivorPerson.pos_of(rec)
	if body:
		layer._forget(body)
		body.queue_free()
	layer._bodies.erase(String(rec.id))
	rec["heli_escort"] = true
	var line := String(cfg().get("come", "We'll get you home."))
	SurvivorPerson.note(rec, "went with %s from the wreck" % (Survival.survivor_name(by) if by else "a stranger"))
	Intel.journal("%s, of the helicopter crew, came with us. The enclave wants them back: take them to a post, or radio for a pickup." % String(rec.name), "event")
	var s := layer.server_spawn_companion(rec, at)
	if s and by:
		var brain := SquadAI.of(s)
		if brain:
			brain.on_order(Squad.Order.FOLLOW, by.global_position)
	if s:
		layer.say(s, "Thank you. Get us home.")
	return line


## Host: "Take their tags" on a dead crew member's body: `by`'s profile carries them.
static func server_take_tags(by: Soldier, rec: Dictionary) -> String:
	if not is_crew(rec) or String(rec.get("status", "")) != "dead" or String(rec.get("tags_by", "")) != "":
		return ""
	rec["tags_by"] = Survival.profile_of(by) if by else "player"
	Intel.journal("We took %s's tags off the body. The enclave will want them." % String(rec.name), "event")
	return "Took %s's tags" % String(rec.name)


## Why `by` can't radio a pickup ("" he can).
static func radio_problem(by: Soldier) -> String:
	if by == null or not FallenRadio.has_radio(by):
		return "You need a radio"
	if not bool(FallenRadio.data().get("repaired", false)):
		return "The radio's dead: repair it first"
	if not FallenRadio.powered(by):
		return "The radio needs power"
	if not Enclave.is_set_up() or Enclave.is_broken():
		return "Nobody answers on the enclave's channel"
	return ""


## Host: "Radio a pickup": `by` calls the enclave for the escorted crew near him and any tags he
## carries. Returns the line ("" none to fetch, or why not as the line).
static func server_radio_pickup(layer: SurvivorsLayer, by: Soldier) -> String:
	var why := radio_problem(by)
	if why != "":
		return why
	if layer == null:
		return ""
	var pids: Array = []
	for c: Soldier in layer.companions():
		var r := layer.record_of(c)
		if is_escort(r) and c.global_position.distance_to(by.global_position) <= 30.0:
			pids.append(String(r.id))
	pids.append_array(tags_of(Survival.profile_of(by)))
	if pids.is_empty():
		return ""
	return server_deliver(layer, by, pids, "radio")


## The dead crew whose tags `profile` carries, not yet handed in.
static func tags_of(profile: String) -> Array:
	var out: Array = []
	for id: String in WorldSim.people():
		var r: Dictionary = WorldSim.people()[id]
		if is_crew(r) and String(r.get("tags_by", "")) == profile and profile != "" and not bool(r.get("tags_in", false)):
			out.append(id)
	return out


## Host: crew `pids` (escorted, or dead with tags carried) handed to the enclave by `by` (`how`:
## "enclave" at a post, "radio" a pickup): their records go to the enclave, its standing up, the
## reward into his kit, a journal line and a broadcast. Returns the journal line.
static func server_deliver(layer: SurvivorsLayer, by: Soldier, pids: Array, how := "enclave") -> String:
	var c := cfg()
	var alive: Array = []
	var tags: Array = []
	var names := PackedStringArray()
	var ev := {}
	for pid: String in pids:
		var r: Dictionary = WorldSim.people().get(pid, {})
		if not is_crew(r):
			continue
		if ev.is_empty():
			ev = event_of(r)
		if is_escort(r):
			var body: Soldier = layer.body_of(pid) if layer else null
			if body:
				layer._forget(body)
				body.queue_free()
				layer._bodies.erase(pid)
			r.erase("heli_escort")
			r["heli_home"] = true
			if Enclave.is_set_up():
				Enclave._take_person(r, "brought home from the wreck")
			else:
				r.status = "enclave"
			alive.append(pid)
			names.append(String(r.name))
		elif String(r.get("status", "")) == "dead" and String(r.get("tags_by", "")) != "" and not bool(r.get("tags_in", false)):
			r["tags_in"] = true
			tags.append(pid)
			names.append("%s (tags)" % String(r.name))
	if alive.is_empty() and tags.is_empty():
		return ""
	var gid := Enclave.gid() if Enclave.is_set_up() else String((WorldSim.section().get("goal", {}) as Dictionary).get("evac_group", ""))
	var gain := float(c.get("standing", 15.0)) * alive.size() + float(c.get("tags_standing", 5.0)) * tags.size()
	var sim := WorldSim.get_sim()
	if sim and gid != "":
		sim.server_change_relation(gid, gain, "brought its crew home")
	var got: Array = []
	if not alive.is_empty():
		var id := int(ev.get("id", 0))
		got = FallenConvoy.roll_rows(c.get("reward", []), int(c.get("rolls", 3)) * alive.size(), [WorldSim.world_seed(), id, ",".join(PackedStringArray(alive)), "reward"])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([WorldSim.world_seed(), id, "serum"])
		if rng.randf() < float(c.get("serum_chance", 0.15)) and ItemDB.has_item(&"serum"):
			got.append({"id": "serum", "count": 1})
	for e: Dictionary in got:
		var n := by.inventory.take(StringName(String(e.id)), int(e.count)) if by else 0
		var level: Node = CompoundLevel.current(by) if by else null
		if n < int(e.count) and level is CompoundLevel:
			(level as CompoundLevel).server_spawn_dropped(StringName(String(e.id)), int(e.count) - n, by.global_position + Vector3.UP * 0.4)
	var who := Survival.survivor_name(by) if by else "Someone"
	var fill := {"who": who, "names": ", ".join(names), "zone": RegionMap.zone_name(String(ev.get("zone", ""))) if not ev.is_empty() else "the hills"}
	var key := "radio" if how == "radio" else ("delivered" if not alive.is_empty() else "tags")
	var line := WorldEvents._cap(String(c.get(key, "{who} brought {names} home")).format(fill)) + "."
	if not got.is_empty():
		var parts := PackedStringArray()
		for e: Dictionary in got:
			var item := ItemDB.get_item(StringName(String(e.id)))
			parts.append("%d %s" % [int(e.count), item.name if item else String(e.id)])
		line += " They paid us: %s." % ", ".join(parts)
	Intel.journal(line, "event", who)
	if gid != "":
		FallenStory.event(String(Survival.state().get("zone", "")), "broadcast", [gid], String(c.get("broadcast", "")).format(fill))
	if not ev.is_empty() and String(ev.get("state", "")) == "open" and _crew_left(ev) == 0:
		ev.state = "done"
		ev.outcome = "delivered"
	if by:
		CoopFallen.server_deed(by, "brought the helicopter crew home", 3.0)
	SessionLog.note("survival crew: %s (%s): standing %+.0f, %d reward items" % [line, how, gain, got.size()])
	return line


## How many of `ev`'s crew are still out there or being escorted.
static func _crew_left(ev: Dictionary) -> int:
	var n := 0
	for pid: String in ev.get("crew", []):
		var r: Dictionary = WorldSim.people().get(pid, {})
		if String(r.get("status", "")) == "out_there" or is_escort(r):
			n += 1
	return n


## Host, every SurvivorsLayer tick: players near the crew out there (the record's "near": leaving
## them costs a little), escorted crew or carried tags at an enclave post (delivered).
static func server_tick(layer: SurvivorsLayer) -> void:
	var zone := String(Survival.state().get("zone", ""))
	var players := MapNodes.players(layer.level).filter(func(p: Soldier) -> bool: return p.vitals.is_up())
	if players.is_empty():
		return
	var c := cfg()
	for r: Dictionary in WorldEvents.open(WorldSim.section(), "heli_down"):
		if String(r.zone) != zone or bool(r.get("near", false)):
			continue
		for pid: String in r.get("crew", []):
			var p: Dictionary = WorldSim.people().get(pid, {})
			if String(p.get("status", "")) != "out_there":
				continue
			var body := layer.body_of(pid)
			var at := body.global_position if body else SurvivorPerson.pos_of(p)
			if players.any(func(pl: Soldier) -> bool: return pl.global_position.distance_to(at) <= float(c.get("near_m", 120.0))):
				r["near"] = true
	if not Enclave.is_set_up():
		return
	var reach := float(c.get("deliver_m", 60.0))
	for post: Dictionary in Enclave.posts().values():
		if String(post.get("zone", "")) != zone:
			continue
		var pp: Array = post.get("pos", [0.0, 0.0])
		var at := Vector2(float(pp[0]), float(pp[1]))
		for pl: Soldier in players:
			if Vector2(pl.global_position.x, pl.global_position.z).distance_to(at) > reach:
				continue
			var pids: Array = []
			for cs: Soldier in layer.companions():
				var r := layer.record_of(cs)
				if is_escort(r) and Vector2(cs.global_position.x, cs.global_position.z).distance_to(at) <= reach:
					pids.append(String(r.id))
			pids.append_array(tags_of(Survival.profile_of(pl)))
			if not pids.is_empty():
				server_deliver(layer, pl, pids, "enclave")
