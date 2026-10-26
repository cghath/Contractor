class_name Spoilage
extends RefCounted
## Food going off in Contractor: Fallen (docs/survival_hands.md; calls 23-26, 96): a perishable
## (raw meat and fish, fresh produce, cooked meals, fat: a food item whose spoils_days is at most
## PERISH_MAX_DAYS) carries `fresh_until`, the world hour it turns stale, in its entry's state:
## stamped fresh when it's made (butchered, caught, picked, crafted: made_state; anything new to a
## kit unstamped counts as made) and, for food found lying in the world, rolled by where it lay
## (found_state, where_box: a powered fridge keeps it fresh, a dead fridge has it half gone, a warm
## house some, outdoors mostly gone, the season scaling it; FoundLoot seeds boxes and the ground
## through it). Food left lying (dropped, in boxes) ages by the world hours the zone sat unloaded,
## worked out when it loads again (age_dropped, age_box: the cold beside a box slows it). Its stages: fresh
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
## Found food: the share of its life left by where it was [min, max]: a working fridge (in a
## settlement with power), a dead fridge in a house ("fridge_off": half gone), a cold cellar, a warm
## house, outdoors. Out of a working fridge or a cellar the season scales what's gone (SEASONED: a
## summer's pace twice, a winter's half).
const FOUND := {"fridge": [1.0, 1.0], "fridge_off": [0.5, 0.5], "cellar": [0.5, 0.9], "indoors": [0.3, 0.7], "outdoors": [0.0, 0.4]}
const SEASONED: Array[String] = ["fridge_off", "indoors", "outdoors"]
## The foods a house kept in its fridge: found indoors, they were in a dead one ("fridge_off").
const FRIDGE_FOODS: Array[String] = ["milk_carton", "cheese", "eggs", "milk", "raw_meat", "raw_fish", "cooked_meal", "animal_fat"]
## A box this far under the ground beside it is in a cellar (m).
const CELLAR_DEPTH_M := 1.5
## A container within this of a cold store or an ice box keeps its food at that piece's pace (m).
const COLD_NEAR_M := 3.0
## Food left lying (on the ground, in a container) is aged by the world hours since this key's hour
## when the zone loads again (the zone save's records: GameState.dropped, WorldCache.to_save).
const AGED := "aged_h"
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


## The share of its life a found food has left, by where it was (FOUND) and the season's pace
## where the season reaches (SEASONED: summer takes twice what spring would, winter half).
static func found_share(where: String, roll := -1.0) -> float:
	var r: Array = FOUND.get(where, FOUND.outdoors)
	var t := roll if roll >= 0.0 else randf()
	var share := lerpf(float(r[0]), float(r[1]), t)
	if where in SEASONED:
		share = 1.0 - (1.0 - share) * season_rate()
	return clampf(share, 0.0, 1.0)


## The state for found food `id` (the loot code's call when it puts food in the world:
## found_items, FoundLoot.first_roll and ground_state) by where it lies: "fridge", "fridge_off",
## "cellar", "indoors" or "outdoors" (where_box). `roll` 0..1 (-1 random).
static func found_state(id: StringName, where: String, roll := -1.0, state := {}) -> Dictionary:
	var item := ItemDB.get_item(id)
	if not perishable(item):
		return state
	return stamp(item, state.duplicate(true), found_share(where, roll))


## The share of its life `state`'s food has left now (1 just made, 0 spoiled; -1 for none).
static func share_left(item: ItemData, state: Dictionary) -> float:
	if not perishable(item) or not state.has(KEY):
		return -1.0
	var life := life_h(item)
	return clampf((float(state[KEY]) + (1.0 - FRESH_SHARE) * life - now_h()) / life, 0.0, 1.0)


## Where a box (or anything lying) at `pos` in `level` keeps food: "fridge" (in the settlement with a
## powered fridge), "cellar" (CELLAR_DEPTH_M under the ground there), "indoors" or "outdoors".
static func where_box(level: Node, pos: Vector3) -> String:
	if Settlement.exists() and Infrastructure.fridge_on() and pos.distance_to(Settlement.pos()) <= Settlement.radius():
		return "fridge"
	if level is ZoneLevel and pos.y < (level as ZoneLevel).ground_height(pos.x, pos.z) - CELLAR_DEPTH_M:
		return "cellar"
	var n3 := level as Node3D
	if n3 and n3.is_inside_tree() and Throwables.indoors(n3.get_world_3d(), pos):
		return "indoors"
	return "outdoors"


## Found food in `items` ([{"id", "count", "state"?}]) stamped by `where` (a house's fridge foods
## in its dead fridge): each perishable without a stamp gets one, rolled by `rng` (the same box
## rolls the same). Everything else passes as it is. Returns the new list.
static func found_items(items: Array, where: String, rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	for e: Dictionary in items:
		var id := StringName(String(e.get("id", "")))
		var item := ItemDB.get_item(id)
		var st0: Dictionary = e.get("state", {}) as Dictionary
		if not perishable(item) or st0.has(KEY):
			out.append(e)
			continue
		var w := "fridge_off" if where == "indoors" and String(id) in FRIDGE_FOODS else where
		var e2 := e.duplicate(true)
		e2["state"] = found_state(id, w, rng.randf() if rng else -1.0, st0)
		out.append(e2)
	return out


## Host (FoundLoot.first_roll, LootStates' refill): found food in a box at `at` stamped by where the
## box stands (where_box), rolled by its uid.
static func found_in_box(items: Array, at: Node3D) -> Array:
	if not Survival.running or at == null or not at.is_inside_tree():
		return items
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(at.get(&"uid")), "food", int(Survival.state().get("seed", 0))])
	return found_items(items, where_box(CompoundLevel.current(at), at.global_position), rng)


# --- Food left lying (the zone save: stamp-based, aged on load) ----------------------------------

## The pace food keeps at in a container at `pos` in `level`: the season's, slowed by a built cold
## store or ice box within COLD_NEAR_M (an ice box needs ice in the settlement's stock out of winter,
## else it keeps as a cold store), stopped by a working fridge in the settlement.
static func container_rate(level: Node, pos: Vector3) -> float:
	if where_box(level, pos) == "fridge":
		return 0.0
	var x := 1.0
	var b: Builder = Builder.find(level) if level else null
	if b:
		for kind: String in ["ice_box", "cold_store"]:
			for id: int in b.pieces_of(kind):
				if not b.is_piece_built(id) or b.piece_pos(id).distance_to(pos) > COLD_NEAR_M:
					continue
				var iced := Seasons.current() == "winter" or (Settlement.exists() and Settlement.count("ice_block") > 0)
				x = minf(x, float(COLD.ice_box) if kind == "ice_box" and iced else float(COLD.cold_store))
	return season_rate() * x


## `entries` ([{"id", "count", "state"}], in place) aged from world hour `from_h` to now at `rate`
## (the stamp moves out by what the cold saved, in by what the heat cost). Returns how many changed.
static func age_entries(entries: Array, from_h: float, rate: float) -> int:
	var hours := now_h() - from_h
	if hours <= 0.0:
		return 0
	var n := 0
	for e: Dictionary in entries:
		var item := ItemDB.get_item(StringName(String(e.get("id", ""))))
		var st: Dictionary = e.get("state", {}) as Dictionary
		if not perishable(item) or not st.has(KEY):
			continue
		var st2 := st.duplicate(true)
		step_state(item, st2, hours, rate)
		e["state"] = st2
		n += 1
	return n


## Host (GameState.load_zone, survival): the dropped items' food (GameState.dropped records, in
## place) aged by the world hours since each was last saved, at the season's pace. Returns how
## many changed.
static func age_dropped(records: Dictionary) -> int:
	if not Survival.running:
		return 0
	var n := 0
	var now := now_h()
	for uid: String in records:
		var d: Dictionary = records[uid]
		if not d.has(AGED):
			d[AGED] = now
			continue
		var one: Array = [{"id": String(d.get("id", "")), "state": d.get("state", {})}]
		n += age_entries(one, float(d[AGED]), season_rate())
		d["state"] = (one[0] as Dictionary).get("state", {})
		d[AGED] = now
	return n


## Host (GameState.save_zone): every dropped record stamped with the hour it was saved at.
static func stamp_dropped(records: Dictionary) -> void:
	if not Survival.running:
		return
	var now := now_h()
	for uid: String in records:
		var d: Dictionary = records[uid]
		d[AGED] = now


## Host (WorldCache.server_fill, a saved box): its `items` aged since `saved`'s AGED hour at the
## pace by the box `at` (container_rate). Returns the items.
static func age_box(items: Array, saved: Dictionary, at: Node3D) -> Array:
	if not Survival.running or not saved.has(AGED) or at == null or not at.is_inside_tree():
		return items
	age_entries(items, float(saved[AGED]), container_rate(CompoundLevel.current(at), at.global_position))
	return items


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


## How many went off and were thrown out today.
static func lost_today() -> int:
	if not Settlement.exists():
		return 0
	var l := larder()
	return int(l.get("today", 0)) if int(l.get("day", -1)) == Survival.day() else 0


static func _stamp_of(e: Dictionary) -> float:
	return float((e.get("state", {}) as Dictionary).get(KEY, INF))


## The id of the stock that matches `pred` (item, id) whose oldest entry is oldest across every
## store (a perishable by its stamp; what doesn't spoil after), "" none: what the settlers eat first.
static func oldest_stocked(pred: Callable) -> String:
	var best := ""
	var best_fu := INF
	var stores := Settlement.stores()
	for key: String in stores:
		for e: Dictionary in stores[key]:
			var item := ItemDB.get_item(StringName(String(e.id)))
			if item == null or not bool(pred.call(item, String(e.id))):
				continue
			var fu := _stamp_of(e)
			if best == "" or fu < best_fu:
				best = String(e.id)
				best_fu = fu
	return best


## Host: `n` of `id` out of the settlement's stores, the oldest stamps first across every store
## (Settlement.server_take's shape: [{"id", "count", "state"}]).
static func take_oldest(id: String, n: int) -> Array:
	var out: Array = []
	var stores := Settlement.stores()
	while n > 0:
		var best_list: Array = []
		var best_i := -1
		var best_fu := INF
		for key: String in stores:
			var list: Array = stores[key]
			for i in list.size():
				var e: Dictionary = list[i]
				if String(e.id) != id:
					continue
				var fu := _stamp_of(e)
				if best_i < 0 or fu < best_fu:
					best_list = list
					best_i = i
					best_fu = fu
		if best_i < 0:
			break
		var e2: Dictionary = best_list[best_i]
		var take := mini(n, int(e2.get("count", 1)))
		out.append({"id": id, "count": take, "state": (e2.get("state", {}) as Dictionary).duplicate(true)})
		n -= take
		e2["count"] = int(e2.get("count", 1)) - take
		if int(e2.count) <= 0:
			best_list.remove_at(best_i)
	return out


## The settlement's fresh stock of `ids` about to go off: entries whose stamp is within `within_h`
## world hours (or already going off, not spoiled), oldest first ([{"id", "count", "fu"}]).
static func aging_stock(ids: Array, within_h: float) -> Array:
	var out: Array = []
	var now := now_h()
	var stores := Settlement.stores()
	for key: String in stores:
		for e: Dictionary in stores[key]:
			if not String(e.id) in ids:
				continue
			var item := ItemDB.get_item(StringName(String(e.id)))
			var st: Dictionary = e.get("state", {}) as Dictionary
			if not perishable(item) or not st.has(KEY) or stage(item, st) == "spoiled":
				continue
			if float(st[KEY]) - now <= within_h:
				out.append({"id": String(e.id), "count": int(e.get("count", 1)), "fu": float(st[KEY])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fu) < float(b.fu))
	return out
