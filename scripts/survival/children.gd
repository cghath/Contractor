class_name Children
extends RefCounted
## Children in Contractor: Fallen (call 128; docs/survival_children.md section 1): kids among the
## lone survivors and settlers from the start, in families and alone. A child is a SurvivorPerson
## record with "child": true and an age (CHILD_AGE); their body is child-sized (the model at SCALE,
## the capsule by size_of) and shielded (Vitals.shielded: nothing hurts them on screen).
##
## - They can't fight: no weapons (strip_weapons on the body, give_refused in the talk), never a
##   companion (TalkMenu: no Recruit), never on the guard or in a council vote (Council.factions).
##   Their jobs are light ones from LIGHT_JOBS_AGE: foraging, minding, water (jobs_for).
## - The dead ignore them (ZombieAI._spot and _smell skip a child: ignored_by_dead) unless no adult
##   is within ADULT_M; then one of the dead reaching them (TAKEN_M) means the child is taken
##   offscreen (server_take: the body goes, a journal line, a heavy moodlet for everyone, never a
##   body). With the dead near they flee to the nearest adult, or a building (server_tick).
## - The player can't hurt them: hits are ignored (shielded) and he's told "You don't."
##   (on_harmed, from Harm.note_hit and Melee._hit). Raiders never target a shielded civilian.
## - Care (settlement_hour): food from the stores like anyone, and an adult's CARE_H a day each
##   (the "minding" job); a child who went hungry weighs on every adult ("child_hungry"); fed and
##   minded, "child_safe" holds; a child who saw the dead and ran, "child_saw".
## - Votes (Council): children don't vote; with children in the settlement the council leans to
##   safety (a demand is paid more readily: SAFETY_LEAN), risky questions ("raid" or "risky") need
##   RISKY_SHARE of the weight, and a hungry child turns votes to take more mouths in against.
## - A reason to settle: a world group with children prefers to settle and won't raid
##   (bias_group, from WorldGoals.options); the world's settlers and cultists roll children once
##   (server_roll_world), the lone survivors of a zone have families (server_place_zone) and
##   sometimes an orphan, who asks to come along ("Come with me": a settler, not a companion).
## Every number here is Proposed.

const CHILD_AGE := Vector2i(5, 15)
## Light jobs from this age (foraging, minding, water).
const LIGHT_JOBS_AGE := 12
const LIGHT_JOBS: Array[String] = ["forage", "minding", "water"]
## The child-sized body.
const SCALE := 0.7
## The dead leave a child alone while an adult is within ADULT_M; with none, one reaching
## TAKEN_M takes them. The dead within SCARE_M send them running.
const ADULT_M := 30.0
const TAKEN_M := 2.0
const SCARE_M := 14.0
## Of the lone survivors placed in a zone: the share who have a child with them (a family), and
## the chance a zone has an orphan.
const FAMILY_SHARE := 0.3
const ORPHAN_CHANCE := 0.35
## The world's groups (server_roll_world): the chance a group of a kind has children, and how many.
const GROUP_CHANCE := {"settlers": 0.6, "cultists": 0.3, "scavengers": 0.1}
const GROUP_KIDS := Vector2i(1, 2)
## Care: an adult's hours a day a child needs (the minding job), checked at CARE_CHECK_HOD.
const CARE_H := 2.0
const CARE_CHECK_HOD := 20
## A hungry child (their hunger under this) at the day's check.
const HUNGRY_AT := 35.0
## The council: a demand's "pay" leans this much more with children here; a risky question needs
## this share of the weight to pass; a hungry child turns take-in votes this much against.
const SAFETY_LEAN := 1.5
const RISKY_SHARE := 0.66
const HUNGRY_NO := 4.0
## A world group with children: settle and defend lean this much more; raids are dropped.
const SETTLE_BIAS := 0.35
## "You don't." no oftener than this to a player.
const REFUSE_GAP_S := 3.0
## Foraging and water yields a worked hour.
const FORAGE_PER_H := 0.4
const WATER_PER_H := 0.5
const FORAGE_FINDS: Array[String] = ["wild_berries", "apples", "wild_berries"]

static var _refused := {}


# --- Who's a child ---------------------------------------------------------------------------

static func is_child_rec(rec: Dictionary) -> bool:
	return bool(rec.get("child", false))


## Whether the body `s` is a child's (meta "child", set on every peer).
static func is_child(s: Node) -> bool:
	return s != null and is_instance_valid(s) and bool(s.get_meta(&"child", false))


## The body size multiplier (SoldierMovement's capsule): SCALE for a child.
static func size_of(s: Node) -> float:
	return SCALE if is_child(s) else 1.0


## The opts that make SurvivorPerson.make roll a child of `age` (a place to live is all they want).
static func opts_for(age: int, more := {}) -> Dictionary:
	var o := {"child": true, "age": age, "want": {"kind": "place"}, "disposition": "friendly", "background": "child",
		"traits": [], "loyalty": 60.0, "courage": 20.0}
	o.merge(more, true)
	return o


## A child's jobs: the light ones from LIGHT_JOBS_AGE, none before.
static func jobs_for(rec: Dictionary) -> Array:
	var out: Array = []
	if int(rec.get("age", 0)) >= LIGHT_JOBS_AGE:
		out.append_array(LIGHT_JOBS)
	return out


## Only light jobs for a child (Settlement.server_set_jobs).
static func filter_jobs(rec: Dictionary, jobs: Array) -> Array:
	if not is_child_rec(rec):
		return jobs
	var ok := jobs_for(rec)
	return jobs.filter(func(j: Variant) -> bool: return String(j) in ok)


## The children of the settlement.
static func settlement_children() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in Settlement.settlers():
		if is_child_rec(r):
			out.append(r)
	return out


static func adults(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in list:
		if not is_child_rec(r):
			out.append(r)
	return out


# --- The body (every peer) ----------------------------------------------------------------------

## Host: a child's body: meta, shielded, no weapons, child-sized.
static func dress_body(s: Soldier, rec: Dictionary) -> void:
	if s == null or not is_child_rec(rec):
		return
	s.set_meta(&"child", true)
	if s.vitals:
		s.vitals.shielded = true
	strip_weapons(s)
	apply_look(s, true)


## The look on any peer: the model drawn at SCALE (the capsule follows through size_of).
static func apply_look(s: Node, child: bool) -> void:
	var b := s as Soldier
	if b == null or not child:
		return
	b.set_meta(&"child", true)
	if b.model:
		b.model.child_scale = SCALE  # (CharacterModel.body_scale: joints, gear and hitboxes with it)


## Host: every weapon off a child's body. Returns how many went.
static func strip_weapons(s: Soldier) -> int:
	var n := 0
	for e: Dictionary in Survival.kit_of(s.inventory):
		if is_weapon(ItemDB.get_item(StringName(String(e.get("id", ""))))):
			n += 1
	if n == 0:
		return 0
	var keep: Array = []
	for e: Dictionary in s.inventory.strip():
		if not is_weapon(ItemDB.get_item(StringName(String(e.get("id", ""))))):
			keep.append(e)
	for e: Dictionary in keep:
		s.inventory.take(StringName(String(e.id)), int(e.get("count", 1)), e.get("state", {}))
	return n


static func is_weapon(item: ItemData) -> bool:
	return item != null and (String(item.type) in ["weapon", "launcher", "ammo"] or "melee" in item.tags or "blade" in item.tags)


## Whether giving `item` to `rec` is refused (a weapon to a child).
static func give_refused(rec: Dictionary, item: ItemData) -> bool:
	return is_child_rec(rec) and is_weapon(item)


## Host (Harm.note_hit, Melee._hit): `attacker` hit `victim`. A child: the hit is nothing (their
## body is shielded) and a player is told "You don't.". Returns whether the hit is to be ignored.
static func on_harmed(victim: Node, attacker: Node) -> bool:
	if not is_child(victim):
		return false
	var p := attacker as Soldier
	if p and not p.is_ai():
		var now := Soldier._now()
		if now - float(_refused.get(p.get_instance_id(), -100.0)) >= REFUSE_GAP_S:
			_refused[p.get_instance_id()] = now
			Survival._tell(p, "You don't.")
	return true


## Whether the dead pass `s` by (ZombieAI): any child. (Taken only by server_tick's rule.)
static func ignored_by_dead(s: Node) -> bool:
	return is_child(s)


# --- Host: in the zone ----------------------------------------------------------------------------

## Host (SurvivorsLayer.server_place_zone): families and an orphan among the zone's new lone
## survivors (their own rng: the adults' rolls are unchanged). Returns the children made.
static func server_place_zone(layer: SurvivorsLayer, zone: String, made: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(Survival.state().get("seed", 0)), zone, "children"])
	var kids: Array = []
	for adult: Dictionary in made.duplicate():
		if rng.randf() >= FAMILY_SHARE:
			continue
		var at := SurvivorPerson.pos_of(adult) + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
		var kid := make_child(layer, rng, at, {"family": String(adult.id), "guardian": String(adult.id)})
		adult["family"] = String(adult.id)
		SurvivorPerson.note(kid, "with %s" % String(adult.get("name", "")))
		kids.append(kid)
	if rng.randf() < ORPHAN_CHANCE and not made.is_empty():
		var near: Dictionary = made[rng.randi_range(0, made.size() - 1)]
		var a := rng.randf() * TAU
		var at2 := SurvivorPerson.pos_of(near) + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(30.0, 60.0)
		var orphan := make_child(layer, rng, at2, {"orphan": true})
		SurvivorPerson.note(orphan, "alone, hiding")
		kids.append(orphan)
	return kids


## Host: a child's record placed at `at` in the hosted zone (`more` overrides).
static func make_child(layer: SurvivorsLayer, rng: RandomNumberGenerator, at: Vector3, more := {}) -> Dictionary:
	var rec := SurvivorPerson.make(rng, layer._new_id(), opts_for(rng.randi_range(CHILD_AGE.x, CHILD_AGE.y), more))
	rec.kit = [{"id": "water_bottle", "count": 1}]
	layer._place(rec, layer._zone(), layer._on_nav(at))
	return rec


## Host: a child made here at `at` now (tests, events): their body comes when a player's near.
static func server_add_child(layer: SurvivorsLayer, at: Vector3, more := {}) -> Dictionary:
	var rec := SurvivorPerson.make(layer._rng, layer._new_id(), opts_for(int(more.get("age", 9)), more))
	rec.kit = [{"id": "water_bottle", "count": 1}]
	layer._place(rec, layer._zone(), at)
	if layer._near_player(at, SurvivorsLayer.LIVE_M):
		layer._spawn_person(rec)
	return rec


## Host (SurvivorsLayer.server_recruit / server_settle): `rec` joined; their children go to the
## settlement with them (a companion's child stays at the settlement: they never fight).
static func server_family_follows(layer: SurvivorsLayer, rec: Dictionary) -> int:
	var fam := String(rec.get("family", ""))
	if fam == "" or is_child_rec(rec) or not Settlement.exists():
		return 0
	var n := 0
	for r: Dictionary in SurvivorsLayer.records().values():
		if r == rec or not is_child_rec(r) or String(r.get("family", "")) != fam or String(r.get("status", "")) != "out_there":
			continue
		server_take_in(layer, r)
		n += 1
	return n


## Host: the child `rec` lives at the settlement now ("Come with me", or with their family).
static func server_take_in(layer: SurvivorsLayer, rec: Dictionary) -> void:
	rec["orphan"] = false
	layer.server_settle(rec)
	rec["jobs"] = jobs_for(rec)


## Host, every SurvivorsLayer tick: children with the dead near flee to the nearest adult (or a
## building); one reached with no adult within ADULT_M is taken. Returns the ids taken.
static func server_tick(layer: SurvivorsLayer, dead: Array) -> Array:
	var taken: Array = []
	if dead.is_empty():
		return taken
	var zone := layer._zone()
	for id: String in SurvivorsLayer.records().keys():
		var rec: Dictionary = SurvivorsLayer.records()[id]
		if not is_child_rec(rec) or String(rec.get("zone", "")) != zone or not String(rec.get("status", "")) in ["out_there", "settler"]:
			continue
		var s := layer.body_of(id)
		if s == null or not s.vitals.is_up():
			continue
		var z: Soldier = null
		var zd := INF
		for d: Soldier in dead:
			if not is_instance_valid(d) or not d.vitals.is_up():
				continue
			var dd := d.global_position.distance_to(s.global_position)
			if dd < zd:
				zd = dd
				z = d
		if z == null or zd > SCARE_M:
			continue
		var adult := nearest_adult(layer, s.global_position)
		if adult == null and zd <= TAKEN_M:
			server_take(layer, rec)
			taken.append(id)
			continue
		_flee(layer, s, rec, z.global_position, adult)
	return taken


## The nearest adult on their feet within ADULT_M of `at`: a player, or a living adult's body.
static func nearest_adult(layer: SurvivorsLayer, at: Vector3) -> Soldier:
	var best: Soldier = null
	var bd := ADULT_M
	for p: Soldier in MapNodes.players(layer.level):
		if p.vitals.is_up() and p.global_position.distance_to(at) <= bd:
			best = p
			bd = p.global_position.distance_to(at)
	for id: String in layer._bodies.keys():
		var b := layer.body_of(id)
		if b == null or not b.vitals.is_up() or is_child(b) or b.faction == ZombieAI.INFECTED:
			continue
		var d := b.global_position.distance_to(at)
		if d <= bd:
			best = b
			bd = d
	return best


static func _flee(layer: SurvivorsLayer, s: Soldier, rec: Dictionary, from: Vector3, adult: Soldier) -> void:
	var brain := s.get_node_or_null(NodePath(PeopleLayer.BRAIN)) as CivilianAI
	if brain:
		brain.alarm(from)
		var to := adult.global_position if adult else _nearest_building(layer, s.global_position)
		if to != Vector3.INF:
			brain._hide = to
			brain._has_hide = true
	var now := Moods.now_h()
	if now - float(rec.get("fled_h", -100.0)) >= 12.0:
		rec["fled_h"] = now
		SurvivorPerson.note(rec, "ran from the dead")
		for o: Dictionary in SurvivorsLayer.records().values():
			if String(o.get("status", "")) in ["companion", "settler"] and not is_child_rec(o):
				Moods.add(o, "child_saw")


static func _nearest_building(layer: SurvivorsLayer, at: Vector3) -> Vector3:
	var best := Vector3.INF
	if layer.level == null or not layer.level.has_method(&"modules"):
		return best
	for m: ZoneModule in layer.level.modules():
		if best == Vector3.INF or m.global_position.distance_to(at) < best.distance_to(at):
			best = m.global_position
	return best


## Host: the child `rec` is taken by the dead, offscreen: their body goes (no body is left), the
## record "taken"; a journal line and a heavy moodlet for every companion and settler.
static func server_take(layer: SurvivorsLayer, rec: Dictionary) -> void:
	var id := String(rec.id)
	var s := layer.body_of(id)
	if s:
		layer._forget(s)
		s.queue_free()
	layer._bodies.erase(id)
	rec["status"] = "taken"
	rec["taken_day"] = Survival.day()
	rec["kit"] = []
	SurvivorPerson.note(rec, "taken by the dead")
	for o: Dictionary in SurvivorsLayer.records().values():
		if String(o.get("status", "")) in ["companion", "settler"] and o != rec:
			Moods.add(o, "child_taken:" + id)
			var n: Dictionary = o.get("needs", {})
			if not n.is_empty():
				Nerve.shake(n, "friend_died", o.get("traits", []))
	Survival._journal_line("%s was taken. We never found %s." % [String(rec.get("first", rec.get("name", "The child"))), "her" if String(rec.get("sex", "m")) == "f" else "him"])


# --- Host: the settlement's children ------------------------------------------------------------------

## Host (Settlement.server_hour): care. Through the day the minding job adds hours (mind());
## at CARE_CHECK_HOD each child is checked: hungry weighs on the adults ("child_hungry"), and
## "child_safe" holds while every child is fed and minded.
static func settlement_hour(_st: Settlement, hod: int) -> void:
	var kids := settlement_children()
	var grown := adults(Settlement.settlers())
	if kids.is_empty():
		for r: Dictionary in grown:
			Moods.hold(r, "child_safe", false)
		return
	if hod != CARE_CHECK_HOD:
		return
	server_care_check()


## Host: the day's care check (settlement_hour at CARE_CHECK_HOD). Returns whether all was well.
static func server_care_check() -> bool:
	var kids := settlement_children()
	var grown := adults(Settlement.settlers())
	var d := Settlement.data()
	var care := float(d.get("care_h", 0.0))
	var need := CARE_H * kids.size()
	var all_ok := care >= need - 0.01
	for k: Dictionary in kids:
		if child_hungry(k):
			all_ok = false
			server_child_went_hungry(k)
	if care < need - 0.01 and not kids.is_empty():
		Survival._journal_line("Nobody minded the children today.")
	for r: Dictionary in grown:
		Moods.hold(r, "child_safe", all_ok and not kids.is_empty())
	d["care_h"] = 0.0
	return all_ok


static func child_hungry(k: Dictionary) -> bool:
	var n: Dictionary = k.get("needs", {})
	return not n.is_empty() and float(n.get("hunger", 100.0)) < HUNGRY_AT


## Host: the child `k` went hungry: every adult settler gets "child_hungry".
static func server_child_went_hungry(k: Dictionary) -> void:
	for r: Dictionary in adults(Settlement.settlers()):
		Moods.add(r, "child_hungry")
		Moods.hold(r, "child_safe", false)
	SurvivorPerson.note(k, "went to bed hungry")


## Host: the minding job (SettlementJobs): `hours` of an adult's (or an older child's) care, while
## the children's care today is short. Returns whether there was minding to do.
static func mind(rec: Dictionary, hours: float) -> bool:
	var kids := settlement_children().filter(func(k: Dictionary) -> bool: return k != rec)
	if kids.is_empty():
		return false
	var d := Settlement.data()
	var need := CARE_H * kids.size()
	if float(d.get("care_h", 0.0)) >= need:
		return false
	d["care_h"] = float(d.get("care_h", 0.0)) + hours
	return true


# --- The council (Council) ----------------------------------------------------------------------

## Whether children live at the settlement.
static func any_here() -> bool:
	return not settlement_children().is_empty()


## The lean children put on `rec`'s vote `v` (added to Council.preference's scores).
static func lean(rec: Dictionary, v: Dictionary, score: Dictionary) -> void:
	if is_child_rec(rec) or not any_here():
		return
	var opts: Array = v.options
	var yes := String(opts[0])
	var no := String(opts[1])
	var q: Dictionary = v.question
	match String(q.get("kind", "custom")):
		"demand":
			score[yes] = float(score.get(yes, 0.0)) + SAFETY_LEAN
		"take_in":
			if Moods.has(rec, "child_hungry"):
				score[no] = float(score.get(no, 0.0)) + HUNGRY_NO
		"raid":
			score[no] = float(score.get(no, 0.0)) + SAFETY_LEAN
	if bool(q.get("risky", false)):
		score[no] = float(score.get(no, 0.0)) + SAFETY_LEAN


## Whether vote `v` is risky (a raid, or flagged) with children here: it needs RISKY_SHARE.
static func risky(v: Dictionary) -> bool:
	var q: Dictionary = v.question
	return any_here() and (String(q.get("kind", "")) == "raid" or bool(q.get("risky", false)))


## The result of a risky vote with children here: yes only with RISKY_SHARE of the tally.
static func risky_result(v: Dictionary, tally: Dictionary, result: String) -> String:
	if not risky(v):
		return result
	var opts: Array = v.options
	var yes := String(opts[0])
	if result != yes:
		return result
	var total := 0.0
	for o: String in tally:
		total += float(tally[o])
	return yes if total <= 0.0 or float(tally.get(yes, 0.0)) / total >= RISKY_SHARE else String(opts[1])


# --- The world's groups (WorldGoals) ----------------------------------------------------------------

## Host, once a world (Survival._world_level_ready): the world's settlers, cultists and some
## scavengers have children (their own rng; a group's leader never is one). Returns how many.
static func server_roll_world() -> int:
	if not WorldSim.is_set_up():
		return 0
	var sec := WorldSim.section()
	if bool(sec.get("kids_rolled", false)):
		return 0
	sec["kids_rolled"] = true
	var people := WorldSim.people()
	var n := 0
	var groups: Dictionary = sec.get("groups", {})
	var ids: Array = groups.keys()
	ids.sort()
	for gid: String in ids:
		n += roll_group(groups[gid], people)
	return n


## Some of `g`'s members (not the leader) are children, by GROUP_CHANCE of its kind. Returns how many.
static func roll_group(g: Dictionary, people: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.world_seed(), String(g.get("id", "")), "kids"])
	if rng.randf() >= float(GROUP_CHANCE.get(String(g.get("kind", "")), 0.0)):
		return 0
	var leader := String(g.get("leader", ""))
	var members: Array = (g.get("members", []) as Array).filter(func(id: Variant) -> bool: return String(id) != leader)
	var want := mini(rng.randi_range(GROUP_KIDS.x, GROUP_KIDS.y), members.size() - 1)
	var n := 0
	for i in want:
		var rec: Dictionary = people.get(String(members[members.size() - 1 - i]), {})
		if rec.is_empty():
			continue
		rec["child"] = true
		rec["age"] = rng.randi_range(CHILD_AGE.x, CHILD_AGE.y)
		rec["kit"] = (rec.get("kit", []) as Array).filter(func(e: Dictionary) -> bool: return not is_weapon(ItemDB.get_item(StringName(String(e.get("id", ""))))))
		rec["disposition"] = "friendly"
		n += 1
	if n > 0:
		g["children"] = n
	return n


## How many of `g`'s members are children.
static func count_in(g: Dictionary, people: Dictionary) -> int:
	var n := 0
	for id: Variant in g.get("members", []):
		if is_child_rec(people.get(String(id), {})):
			n += 1
	return n


## WorldGoals.options' hook: a group with children won't raid or hunt the players, and leans to
## settling and defending its home.
static func bias_options(m: WorldModel, g: Dictionary, out: Array) -> void:
	bias_group(g, m.people, out)


static func bias_group(g: Dictionary, people: Dictionary, out: Array) -> void:
	if count_in(g, people) <= 0:
		return
	for i in range(out.size() - 1, -1, -1):
		var o: Dictionary = out[i]
		match String(o.get("kind", "")):
			"raid", "hunt_player":
				out.remove_at(i)
			"settle", "defend":
				o["bias"] = float(o.get("bias", 0.0)) + SETTLE_BIAS


# --- Settlement jobs ------------------------------------------------------------------------------

## The forage job: wild food a worked hour into the stores.
static func forage(st: Settlement, hours: float) -> bool:
	var n := SettlementJobs._acc("forage", FORAGE_PER_H * hours)
	for i in n:
		st.server_put(FORAGE_FINDS[(Survival.day() + i) % FORAGE_FINDS.size()], 1)
	return true


## The water job: water carried from the nearest source (to be boiled: the cook's order).
static func carry_water(st: Settlement, hours: float) -> bool:
	var n := SettlementJobs._acc("water", WATER_PER_H * hours)
	if n > 0:
		st.server_put("dirty_water_bottle", n)
	return true
