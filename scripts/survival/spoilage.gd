class_name Spoilage
extends RefCounted
## Food going off in Contractor: Fallen (docs/survival_hands.md; calls 23-26, 96): a perishable
## (raw meat and fish, fresh produce, cooked meals, fat: a food item whose spoils_days is at most
## PERISH_MAX_DAYS) carries `fresh_until`, the world hour it turns stale, in its entry's state:
## stamped fresh when it's made (butchered, caught, picked, crafted: made_state; anything new to a
## kit unstamped counts as made) and, for food found lying in the world, rolled by where it lay
## (found_state, where_at: a powered fridge keeps it fresh, a warm house has it half gone, outdoors
## mostly gone; the loot code calls it when it seeds food, which none does yet). Its stages: fresh
## (FRESH_SHARE of its life), stale (the rest: half the food, a small risk) and spoiled (a quarter of
## the food and a good chance of food poisoning: Needs' "food_poisoning"). The season sets the pace
## (Seasons.spoil_mult: summer twice as fast, winter half); the settlement's larder is slowed by a
## cold store (COLD) or an ice box with ice in stock, stopped by a powered fridge. Salting, smoking and
## drying are recipes that turn fresh food into cured food with a long life. The host steps the
## stamps by whole world hours (a stamp moves out by the hours the cold saved, or in by the hours the
## heat cost), so stacks made together stay one stack; `stage` rides along for the peers' readout
## ("fresh", "going off", "spoiled"). The settlement's larder (server_larder_hour) throws spoiled stock
## out as a loss and keeps each store oldest first, so the cook uses the oldest first.
## Every number here is Proposed.

const KEY := "fresh_until"
const STAGE := "stage"
## A food item that keeps longer than this (tins, rations, honey) never gets a stamp.
const PERISH_MAX_DAYS := 100.0
## The share of a food's life it is fresh; the rest it is stale; then spoiled.
const FRESH_SHARE := 0.6
## Food values eaten stale and spoiled, and the chance of food poisoning.
const STALE_FOOD := 0.5
const SPOILED_FOOD := 0.25
const STALE_RISK := 0.05
const SPOILED_RISK := 0.6
## Found food: the share of its life left by where it was [min, max].
const FOUND := {"fridge": [1.0, 1.0], "indoors": [0.3, 0.7], "outdoors": [0.0, 0.4]}
## The larder's pace in the settlement's cold pieces (a powered fridge stops it).
const COLD := {"cold_store": 0.5, "ice_box": 0.25}
## An ice box out of winter melts a block of ice in this many world days.
const ICE_DAYS := 2.0
## Words for the stages.
const WORDS := {"fresh": "fresh", "stale": "going off", "spoiled": "spoiled"}

## Tests: a roll to use instead of randf() (-1: Needs.force_roll, then real).
static var force_roll := -1.0
## Tests: hold the kit step (the test steps it itself).
static var tick_off := false
static var _acc := {}  # player name -> world hours not yet stepped
static var _real := 0.0


static func perishable(item: ItemData) -> bool:
	return item != null and item.type == "consumable" and "food" in item.tags and item.stats.has("spoils_days") and float(item.stats.spoils_days) <= PERISH_MAX_DAYS


## The food's whole life in world hours (fresh and stale), at the base pace.
static func life_h(item: ItemData) -> float:
	return float(item.stats.get("spoils_days", 1.0)) * 24.0


static func now_h() -> float:
	return Moods.now_h()


## `state` stamped for `item` with `share` of its life left (1: made just now). In place; returned.
static func stamp(item: ItemData, state: Dictionary, share := 1.0) -> Dictionary:
	if not perishable(item):
		return state
	var life := life_h(item)
	var fu := now_h() - (1.0 - clampf(share, 0.0, 1.0)) * life + FRESH_SHARE * life
	state[KEY] = snappedf(fu, 1.0)  # (whole hours: what's made together stacks together)
	state[STAGE] = stage(item, state)
	return state


## A state for `id` made now (butchered, caught, picked, crafted): `state` with a fresh stamp, or as
## it was for anything that doesn't spoil.
static func made_state(id: StringName, state := {}) -> Dictionary:
	var item := ItemDB.get_item(id)
	if not perishable(item) or (state.has(KEY)):
		return state
	return stamp(item, state.duplicate(true), 1.0)


## "fresh", "stale" or "spoiled" (or "" for what doesn't spoil or has no stamp yet).
static func stage(item: ItemData, state: Dictionary) -> String:
	if not perishable(item) or not state.has(KEY):
		return ""
	var t := now_h()
	var fu := float(state[KEY])
	if t < fu:
		return "fresh"
	if t < fu + (1.0 - FRESH_SHARE) * life_h(item):
		return "stale"
	return "spoiled"


## The stage as this peer knows it: the host reads the clock, a peer the stage the host wrote.
static func stage_known(item: ItemData, state: Dictionary) -> String:
	if Survival.running:
		return stage(item, state)
	return String(state.get(STAGE, ""))


## The inventory's freshness word ("fresh", "going off", "spoiled"; "" for none).
static func tag(item: ItemData, state: Dictionary) -> String:
	return String(WORDS.get(stage_known(item, state), ""))


## How much of the food's values a meal of it gives.
static func nutrition_mult(item: ItemData, state: Dictionary) -> float:
	match stage(item, state):
		"stale":
			return STALE_FOOD
		"spoiled":
			return SPOILED_FOOD
	return 1.0


static func _roll() -> float:
	if force_roll >= 0.0:
		return force_roll
	return Needs.force_roll if Needs.force_roll >= 0.0 else randf()


## Host (Needs.eat): `item` with `state` eaten into body `n`: stale or spoiled food may start food
## poisoning (Needs' sickness, unless he's already sick). Returns "food_poisoning" or "".
static func on_eaten(n: Dictionary, item: ItemData, state: Dictionary) -> String:
	var st := stage(item, state)
	var chance := SPOILED_RISK if st == "spoiled" else (STALE_RISK if st == "stale" else 0.0)
	if chance <= 0.0 or not (n.get("sick", {}) as Dictionary).is_empty():
		return ""
	if _roll() >= chance:
		return ""
	n["sick"] = {"id": "food_poisoning", "left_h": float(Needs.SICKNESS.food_poisoning.hours), "onset_h": Needs.ONSET_H, "from": "spoiled"}
	return "food_poisoning"


## The season's pace (1 spring and autumn, 2 in summer, 0.5 in winter).
static func season_rate() -> float:
	return 1.0 / maxf(0.05, Seasons.spoil_mult())


## `hours` world hours pass for `state` going off at `rate` (1 the base pace, 0 stopped): its stamp
## moves out by what the cold saved (in by what the heat cost). Returns whether its stage changed.
static func step_state(item: ItemData, state: Dictionary, hours: float, rate: float) -> bool:
	if not perishable(item) or not state.has(KEY) or hours <= 0.0:
		return false
	var before := String(state.get(STAGE, ""))
	state[KEY] = float(state[KEY]) + hours * (1.0 - rate)
	state[STAGE] = stage(item, state)
	return before != String(state[STAGE])


## The share of its life a found food has left, by where it was (FOUND).
static func found_share(where: String, roll := -1.0) -> float:
	var r: Array = FOUND.get(where, FOUND.outdoors)
	var t := roll if roll >= 0.0 else randf()
	return lerpf(float(r[0]), float(r[1]), t)


## The state for found food `id` (the loot code's call when it puts food in the world: none does
## yet) by where it lies: "fridge", "indoors" or "outdoors" (where_at). `roll` 0..1 (-1 random).
static func found_state(id: StringName, where: String, roll := -1.0, state := {}) -> Dictionary:
	var item := ItemDB.get_item(id)
	if not perishable(item):
		return state
	return stamp(item, state.duplicate(true), found_share(where, roll))


## Where food at `pos` lies: "fridge" (in the settlement with a powered fridge), "indoors" or
## "outdoors".
static func where_at(world: World3D, pos: Vector3) -> String:
	if Settlement.exists() and Infrastructure.fridge_on() and pos.distance_to(Settlement.pos()) <= Settlement.radius():
		return "fridge"
	if world and Throwables.indoors(world, pos):
		return "indoors"
	return "outdoors"


## Where `s` is for food he finds: "fridge" (in the settlement with a powered fridge), "indoors" or
## "outdoors".
static func where_of(s: Soldier) -> String:
	if Settlement.exists() and Infrastructure.fridge_on() and s.global_position.distance_to(Settlement.pos()) <= Settlement.radius():
		return "fridge"
	if s.is_inside_tree() and Throwables.indoors(s.get_world_3d(), s.global_position):
		return "indoors"
	return "outdoors"


# --- The kit (host) -------------------------------------------------------------------------------

## Host (Fieldwork.server_tick): `world_h` world hours of `s`'s food: a perishable new to his kit
## with no stamp is stamped fresh (made just now), the rest goes off at the season's pace.
## Returns how many entries changed.
static func server_step_kit(s: Soldier, world_h: float) -> int:
	var inv := s.inventory
	if inv == null:
		return 0
	var changed := 0
	var rate := season_rate()
	for c: StringName in inv.search_containers():
		for e: Dictionary in inv.containers.get(c, []):
			var item := ItemDB.get_item(StringName(String(e.id)))
			if not perishable(item):
				continue
			var st: Dictionary = (e.get("state", {}) as Dictionary).duplicate(true)
			if not st.has(KEY):
				stamp(item, st, 1.0)  # (new to the kit unstamped: made just now; found food comes stamped: found_state)
				e["state"] = st
				changed += 1
			elif world_h > 0.0:
				var before := float(st[KEY])
				step_state(item, st, world_h, rate)
				if not is_equal_approx(before, float(st[KEY])) or String((e.state as Dictionary).get(STAGE, "")) != String(st[STAGE]):
					e["state"] = st
					changed += 1
	if changed > 0:
		inv._commit()
	return changed


## Host: the players' food, every Fieldwork tick (`dt` real seconds; the stamps by whole world hours).
static func server_tick(players: Array, dt: float) -> void:
	if tick_off:
		return
	var h := Wear.hours_in(dt)
	for s: Soldier in players:
		if s == null or not is_instance_valid(s) or s.inventory == null:
			continue
		var key := String(s.name)
		var acc := float(_acc.get(key, 0.0)) + h
		var whole := floorf(acc)
		_acc[key] = acc - whole
		server_step_kit(s, whole)  # (0 hours still stamps what's new)


# --- The larder (the settlement's stores) --------------------------------------------------------

## The larder's pace now: the season's, slowed by the settlement's cold pieces (a powered fridge
## stops it; an ice box needs ice in stock out of winter).
static func larder_rate() -> float:
	if not Settlement.exists():
		return season_rate()
	var d := Settlement.data()
	if int(d.get("fridges", 0)) > 0 and Infrastructure.fridge_on():
		return 0.0
	var x := 1.0
	if int(d.get("ice_boxes", 0)) > 0 and (Seasons.current() == "winter" or Settlement.count("ice_block") > 0):
		x = float(COLD.ice_box)
	elif int(d.get("cold_stores", 0)) > 0:
		x = float(COLD.cold_store)
	return season_rate() * x


static func larder() -> Dictionary:
	var d := Settlement.data()
	if not d.get("larder") is Dictionary:
		d["larder"] = {"lost": 0, "today": 0, "day": Survival.day(), "ice_h": 0.0}
	return d["larder"]


## Host (Settlement.server_hour): an hour of the larder: unstamped stock stamped fresh (made at
## home), the rest going off at larder_rate; spoiled stock thrown out as a loss; the ice melting;
## every store oldest first. Returns how many items were lost.
static func server_larder_hour(st: Settlement, hours := 1.0) -> int:
	if not Settlement.exists():
		return 0
	var rate := larder_rate()
	var lost := 0
	var stores := Settlement.stores()
	for key: String in stores:
		var list: Array = stores[key]
		var i := 0
		while i < list.size():
			var e: Dictionary = list[i]
			var item := ItemDB.get_item(StringName(String(e.id)))
			if not perishable(item):
				i += 1
				continue
			var stt: Dictionary = e.get("state", {}) as Dictionary
			if not stt.has(KEY):
				stt = stamp(item, stt.duplicate(true), 1.0)
				e["state"] = stt
			else:
				step_state(item, stt, hours, rate)
			if stage(item, stt) == "spoiled":
				lost += int(e.get("count", 1))
				list.remove_at(i)
				continue
			i += 1
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _older(a, b))
	var l := larder()
	if int(l.get("day", 0)) != Survival.day():
		if int(l.get("today", 0)) > 0:
			Survival._journal_line("%d of the settlement's food went off and was thrown out." % int(l.today))
		l["day"] = Survival.day()
		l["today"] = 0
	l["lost"] = int(l.get("lost", 0)) + lost
	l["today"] = int(l.get("today", 0)) + lost
	_melt(hours)
	return lost


## Entries oldest first: a stamped one by its stamp, the rest after.
static func _older(a: Dictionary, b: Dictionary) -> bool:
	var fa := float((a.get("state", {}) as Dictionary).get(KEY, INF))
	var fb := float((b.get("state", {}) as Dictionary).get(KEY, INF))
	return fa < fb


## The ice boxes' ice out of winter: a block every ICE_DAYS per box.
static func _melt(hours: float) -> void:
	var boxes := int(Settlement.data().get("ice_boxes", 0))
	if boxes <= 0 or Seasons.current() == "winter" or Settlement.count("ice_block") <= 0:
		return
	var l := larder()
	l["ice_h"] = float(l.get("ice_h", 0.0)) + hours * boxes
	while float(l.ice_h) >= ICE_DAYS * 24.0:
		l.ice_h = float(l.ice_h) - ICE_DAYS * 24.0
		Settlement.server_take("ice_block", 1)


## How many items of stock the larder has lost, all told.
static func lost() -> int:
	return int(larder().get("lost", 0)) if Settlement.exists() else 0
