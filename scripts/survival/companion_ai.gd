class_name CompanionAI
extends Node
## Host-only: what a Contractor: Fallen companion does unasked (docs/survival_people.md section 3,
## call 40), a small node beside the body's SquadAI that nudges it rather than replacing it
## (SquadAI keeps the fighting, cover, self-care of wounds and the squad's orders):
## - their body runs on Needs like a player's (Survival.server_drain every TICK_S): they eat and
##   drink from their kit when low and ask for more when it's gone (a line, then quiet a while);
##   they sleep when tired and safe (the lead asleep, or holding with nothing of the dead near:
##   SurvivalSleep), and wake to a moodlet by where they slept;
## - they call out the dead they see (a bark), pick up food and ammo for their gun lying within
##   LOOT_M when the group is stopped and quiet, and now and then suggest a plan (dusk, a horde);
## - they refuse a bad order (vetoes, from SquadAI.on_order): a move into a horde (HORDE_N of the
##   dead within HORDE_M of the goal, live or in the crowd tier) or anything while in a refusal
##   break, by a roll on loyalty and courage; a second order within SECOND_ORDER_S is obeyed by
##   the loyal (SurvivorPerson.is_loyal) and refused again by the rest.

const NODE_NAME := "CompanionAI"
## Proposed numbers.
const TICK_S := 1.0
const EAT_BELOW := 40.0
const DRINK_BELOW := 40.0
const ASK_GAP_S := 600.0
const SLEEP_BELOW := 30.0
const SLEEP_HOURS := 6.0
const SAFE_M := 30.0
const SPOT_M := 25.0
const SPOT_GAP_S := 15.0
const LOOT_M := 4.0
const LOOT_GAP_S := 6.0
const QUIET_M := 20.0
const PLAN_GAP_S := 420.0
const HORDE_M := 20.0
const HORDE_N := 3
const SECOND_ORDER_S := 60.0
## Tests: a roll to use instead of randf() for the refusal (-1: roll for real).
static var force_roll := -1.0

var rec: Dictionary = {}
var layer: SurvivorsLayer
var body: Soldier

var _tick := 0.0
var _asked_at := -1000.0
var _spotted_at := -1000.0
var _seen := {}
var _loot_at := -1000.0
var _plan_at := 0.0
var _refused_at := -1000.0
var _slept_where := ""


static func of(s: Node) -> CompanionAI:
	return s.get_node_or_null(NODE_NAME) as CompanionAI if s else null


## SquadAI.on_order's hook: whether the companion under `brain` says no to this order.
static func vetoes(brain: Node, order: int, point: Vector3) -> bool:
	var ai: CompanionAI = of(brain.get_parent()) if brain else null
	return ai != null and ai.refuses(order, point)


func _ready() -> void:
	body = get_parent() as Soldier
	_plan_at = Soldier._now() + PLAN_GAP_S * 0.5


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or body == null or rec.is_empty():
		return
	_tick += delta
	if _tick < TICK_S:
		return
	var dt := _tick
	_tick = 0.0
	if body.vitals.is_dead():
		return
	server_step(dt)


## Host: TICK_S of a companion's life.
func server_step(dt: float) -> void:
	var n := Survival.needs_of(body)
	var asleep_before := SurvivalSleep.is_asleep(n)
	if body.vitals.is_up():
		Survival.server_drain(body, dt * SurvivalSleep.body_mult(body))
	if asleep_before and not SurvivalSleep.is_asleep(n):
		Moods.add(rec, "slept_bed" if _slept_where == "bed" else "slept_ground")
	if not body.vitals.is_up():
		return
	var now := Soldier._now()
	var dead := Survival.zombies(CompoundLevel.current(body))
	var near := _nearest(dead)
	_callout(near, now)
	if SurvivalSleep.is_asleep(n):
		return
	Needs.ensure(n)
	if float(n.thirst) < DRINK_BELOW:
		if not _consume(func(item: ItemData) -> bool: return item.stats.has("water_l") and not item.stats.has("kcal")):
			_ask("thirsty", now)
	if float(n.hunger) < EAT_BELOW:
		if not _consume(func(item: ItemData) -> bool: return item.stats.has("kcal")):
			_ask("hungry", now)
	var calm := near == null or near.global_position.distance_to(body.global_position) > QUIET_M
	if calm and float(n.sleep) < SLEEP_BELOW and _may_sleep(near):
		_slept_where = "ground"
		if SurvivalSleep.start(body, n, SLEEP_HOURS, _slept_where, false) == "":
			layer.say(body, "I need to sleep. Wake me if they come.")
	if SurvivalSleep.is_waiting(n):
		return  # waiting with the survivor (call 136): no wandering off to loot or plan
	if calm and _halted() and now - _loot_at >= LOOT_GAP_S:
		_loot_at = now
		_pick_up_near()
	if now >= _plan_at:
		_plan_at = now + PLAN_GAP_S
		_suggest()


func _nearest(dead: Array) -> Soldier:
	var best: Soldier = null
	for z: Soldier in dead:
		if best == null or z.global_position.distance_to(body.global_position) < best.global_position.distance_to(body.global_position):
			best = z
	return best


## A bark for one of the dead newly in sight (once each, SPOT_GAP_S apart).
func _callout(near: Soldier, now: float) -> void:
	if near == null or near.global_position.distance_to(body.global_position) > SPOT_M or _seen.has(near.get_instance_id()):
		return
	_seen[near.get_instance_id()] = true
	if now - _spotted_at < SPOT_GAP_S:
		return
	_spotted_at = now
	layer.say(body, TalkMenu.line_for(rec, "spotted_dead"))


func _ask(topic: String, now: float) -> void:
	if now - _asked_at < ASK_GAP_S:
		return
	_asked_at = now
	if VoiceLines.should_say(rec, topic, VoiceLines.quiet_now()):  # talkativeness; quiet when it's tense (call 76)
		layer.say(body, TalkMenu.line_for(rec, topic))


## Eats or drinks the first thing in the kit `ok` accepts (Consumables, so the food's values go
## into their Needs); true if something went down.
func _consume(ok: Callable) -> bool:
	for c: StringName in body.inventory.search_containers():
		var list: Array = body.inventory.containers[c]
		for i in list.size():
			var item := ItemDB.get_item(StringName(String(list[i].id)))
			if item and item.stats.has("consume") and ok.call(item):
				if Consumables.server_use(body, c, i) == "":
					if bool(item.stats.get("raw", false)) and item.stats.has("kcal"):
						Moods.add(rec, "ate_raw")
					elif "hot" in item.tags or "cooked" in item.tags:
						Moods.add(rec, "ate_hot")
					return true
	return false


## A binge (Moods' break): eats and drinks up to `n` things whatever their needs.
func eat_any(n: int) -> int:
	var done := 0
	for k in n:
		if _consume(func(item: ItemData) -> bool: return item.stats.has("kcal") or item.stats.has("water_l")):
			done += 1
	return done


## Safe to sleep: nothing of the dead within SAFE_M, and the lead asleep or the companion told to hold.
func _may_sleep(near: Soldier) -> bool:
	if near and near.global_position.distance_to(body.global_position) <= SAFE_M:
		return false
	var brain := SquadAI.of(body)
	var lead: Soldier = brain.squad.leader if brain and brain.squad and is_instance_valid(brain.squad.leader) else null
	if lead and Survival.running and lead.has_meta(&"needs") and SurvivalSleep.is_asleep(Survival.needs_of(lead)):
		return true
	return brain != null and brain.order == Squad.Order.HOLD


## The group is stopped: the lead (or this one, holding) isn't moving.
func _halted() -> bool:
	var brain := SquadAI.of(body)
	if brain == null:
		return false
	if brain.order == Squad.Order.HOLD:
		return true
	var lead: Soldier = brain.squad.leader if brain.squad and is_instance_valid(brain.squad.leader) else null
	return lead != null and lead.velocity.length() < 0.3 and body.velocity.length() < 0.5


## Picks up food or ammo for their own gun lying within LOOT_M (one a time).
func _pick_up_near() -> void:
	var lvl := CompoundLevel.current(body)
	if lvl == null:
		return
	var gun := body.active_weapon()
	var ammo := String(gun.stats.get("ammo", "")) if gun else ""
	for n in lvl.items.get_children():
		var it := n as WorldItem
		if it == null or it.is_queued_for_deletion() or it.global_position.distance_to(body.global_position) > LOOT_M:
			continue
		var item := ItemDB.get_item(it.item_id)
		if item == null:
			continue
		var wanted := item.stats.has("kcal") or item.stats.has("water_l") or (ammo != "" and String(item.id) == ammo)
		if not wanted:
			continue
		var taken := body.inventory.take(it.item_id, it.count, it.state)
		if taken > 0:
			body._server_took(it, taken)
			if VoiceLines.should_say(rec, "took_item", VoiceLines.quiet_now()):
				layer.say(body, TalkMenu.line_for(rec, "took_item", {"item": item.name.to_lower()}))
			return


## A plan said out loud now and then: dusk coming, a horde about, or something they know.
func _suggest() -> void:
	var h := Survival.hour()
	var crowd := ZoneDead.of(CompoundLevel.current(body))
	var topic := "plan_idle"
	if crowd and crowd.horde_count() > 0:
		topic = "plan_horde"
	elif h >= 17.0 and h < 20.0:
		topic = "plan_dusk"
	if VoiceLines.should_say(rec, topic, VoiceLines.quiet_now()):
		layer.say(body, TalkMenu.line_for(rec, topic))


## Whether this companion refuses `order` to `point` (vetoes): see the class doc.
func refuses(order: int, point: Vector3) -> bool:
	if order != Squad.Order.MOVE:
		return false
	var broke := String(rec.get("break", "")) == "refusal"
	if not broke and not horde_near(point):
		return false
	var now := Soldier._now()
	var lead := lead_profile()
	if not broke and Relationships.follows_anywhere(rec, lead):
		return false  # a close bond follows into worse odds (call 74)
	if Relationships.refuses_risky(rec, lead):
		_refused_at = now
		layer.say(body, TalkMenu.line_for(rec, "refuse_order"))
		SurvivorPerson.note(rec, "refused an order (no trust)")
		return true  # too little trust for a risky order, loyal or not (call 74)
	if now - _refused_at <= SECOND_ORDER_S:
		if SurvivorPerson.is_loyal(rec):
			_refused_at = -1000.0
			if broke:
				Moods.end_break(rec)
			layer.say(body, TalkMenu.line_for(rec, "obey_grudging"))
			return false
		_refused_at = now
		layer.say(body, TalkMenu.line_for(rec, "refuse_again"))
		return true
	var roll := force_roll if force_roll >= 0.0 else randf()
	if broke or roll < refuse_chance():
		_refused_at = now
		layer.say(body, TalkMenu.line_for(rec, "refuse_order"))
		SurvivorPerson.note(rec, "refused an order")
		return true
	return false


## The profile of the player this companion follows (the squad's lead), else "".
func lead_profile() -> String:
	var brain := SquadAI.of(body)
	var lead: Soldier = brain.squad.leader if brain and brain.squad and is_instance_valid(brain.squad.leader) else null
	return Survival.profile_of(lead) if lead and not lead.is_ai() else ""


## The chance of saying no to a move into a horde (Proposed): high, less for the loyal and the
## brave, more for a new companion who doesn't trust you yet.
func refuse_chance() -> float:
	var loyalty := float(rec.get("loyalty", 0.0))
	var courage := float(rec.get("courage", 0.0))
	return clampf(0.95 - loyalty / 250.0 - courage / 250.0 + (0.1 if loyalty < 30.0 else 0.0), 0.15, 0.95)


## HORDE_N or more of the dead within HORDE_M of `point`, live or in the zone's crowd tier.
func horde_near(point: Vector3) -> bool:
	var n := 0
	for z: Soldier in Survival.zombies(CompoundLevel.current(body)):
		if z.global_position.distance_to(point) <= HORDE_M:
			n += 1
	var crowd := ZoneDead.of(CompoundLevel.current(body))
	if crowd:
		var p2 := Vector2(point.x, point.z)
		for d: Dictionary in crowd.dead:
			if bool(d.get("alive", true)) and (d.pos as Vector2).distance_to(p2) <= HORDE_M:
				n += 1
	return n >= HORDE_N
