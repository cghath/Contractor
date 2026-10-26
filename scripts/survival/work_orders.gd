class_name WorkOrders
extends RefCounted
## The settlement's work orders (docs/survival_building.md §6, call 59): "build these
## blueprints", "cut N wood", "make N sandbags", "smoke the meat", "boil water to N", "repair",
## "craft N of a recipe", each with a priority (1 first .. 5) and a count, kept in the
## settlement's record ("orders") and worked by the settlers whose job serves it (KINDS' job:
## SettlementJobs asks work_for first). The planning view (planning) says what's short and who's
## idle. The player can do any of it himself: an order he claims (server_claim) isn't taken over
## for CLAIM_H world hours. Every number here is Proposed.

const KINDS := {
	"build": {"job": "build", "name": "Build the blueprints"},
	"cut_wood": {"job": "build", "name": "Cut wood"},
	"sandbags": {"job": "build", "name": "Fill sandbags"},
	"smoke_meat": {"job": "cook", "name": "Smoke the meat"},
	"boil_water": {"job": "cook", "name": "Boil water to"},
	"repair": {"job": "maintain", "name": "Repair the builds"},
	"craft": {"job": "craft", "name": "Craft"},
	"medical_supplies": {"job": "doctor", "name": "Medical supplies for the clinic"},  # (Clinic: the cabinet low)
}
## Made an hour by one worker: planks cut (a woodpile stub until felling ZoneScatter's trees
## with an axe), sandbags filled (a cloth rag each: the sand is dug on the spot), meat smoked and
## water boiled on a stove, recipes crafted.
const WOOD_PER_H := 3
const SANDBAGS_PER_H := 3
const STOVE_PER_H := 3
const CRAFT_PER_H := 2
const CLAIM_H := 2.0
## Done orders kept on the list (the screen shows them done).
const KEEP_DONE := 6
## The planning view calls food or water short under this many days for the members.
const SHORT_DAYS := 2.0


static func list() -> Array:
	var d := Settlement.data()
	if not d.get("orders") is Array:
		d["orders"] = []
	return d.get("orders", [])


static func get_order(id: int) -> Dictionary:
	for o: Dictionary in list():
		if int(o.id) == id:
			return o
	return {}


## The open orders, by priority then age.
static func open_orders() -> Array:
	var out := list().filter(func(o: Dictionary) -> bool: return String(o.get("state", "open")) == "open")
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.priority) < int(b.priority) or (int(a.priority) == int(b.priority) and int(a.id) < int(b.id)))
	return out


## Host: a new order of `kind` for `count` (a build order with count 0 takes every site there is
## now; boil_water's count is the clean water to have in stock), `priority` 1..5, `extra` (a
## craft's {"recipe": id}). Returns it, or {} when it can't be.
static func server_add(kind: String, count: int, priority := 3, extra := {}) -> Dictionary:
	if not KINDS.has(kind) or not Settlement.exists():
		return {}
	if kind == "craft" and Crafting.recipe(String(extra.get("recipe", ""))).is_empty():
		return {}
	var d := Settlement.data()
	var id := int(d.get("next_order", 1))
	d["next_order"] = id + 1
	var o := {"id": id, "kind": kind, "count": maxi(count, 0), "done": 0, "priority": clampi(priority, 1, 5), "extra": extra.duplicate(true),
		"state": "open", "by": "", "by_until": 0.0, "made_h": Moods.now_h()}
	if kind == "build" and count <= 0:
		var st := _st()
		o["count"] = SettlementJobs.sites(st).size() if st else 0
	list().append(o)
	Survival._journal_line("Work order: %s." % text_of(o))
	return o


static func server_remove(id: int) -> bool:
	var before := list().size()
	Settlement.data()["orders"] = list().filter(func(o: Dictionary) -> bool: return int(o.id) != id)
	return list().size() < before


## Host: the player `profile` does order `id` himself: settlers leave it for CLAIM_H hours.
static func server_claim(id: int, profile: String) -> bool:
	var o := get_order(id)
	if o.is_empty():
		return false
	o["by"] = profile
	o["by_until"] = Moods.now_h() + CLAIM_H
	return true


static func claimed(o: Dictionary) -> bool:
	return String(o.get("by", "")) != "" and float(o.get("by_until", 0.0)) > Moods.now_h()


static func text_of(o: Dictionary) -> String:
	var name := String(KINDS.get(String(o.kind), {}).get("name", String(o.kind)))
	match String(o.kind):
		"cut_wood":
			return "%s: %d planks" % [name, int(o.count)]
		"sandbags", "smoke_meat":
			return "%s: %d" % [name, int(o.count)]
		"boil_water":
			return "%s %d" % [name, int(o.count)]
		"build":
			return "%s (%d)" % [name, int(o.count)]
		"craft":
			var r := Crafting.recipe(String((o.get("extra", {}) as Dictionary).get("recipe", "")))
			return "%s: %d %s" % [name, int(o.count), String(r.get("name", "?"))]
	return name


static func _st() -> Settlement:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.find_child(Settlement.NODE_NAME, true, false) as Settlement if tree else null


## Host: `hours` on the first open, unclaimed order `job` serves. Returns whether it did work.
static func work_for(st: Settlement, job: String, hours: float) -> bool:
	for o: Dictionary in open_orders():
		if String(KINDS[String(o.kind)].job) != job or claimed(o):
			continue
		if work_on(st, o, hours):
			return true
	return false


## Host: `hours` of work on order `o`. Returns whether anything was done.
static func work_on(st: Settlement, o: Dictionary, hours: float) -> bool:
	var h := maxi(1, roundi(hours))
	var left := int(o.count) - int(o.done)
	var stove := int(Settlement.data().get("stoves", 0)) > 0
	match String(o.kind):
		"build":
			return SettlementJobs.build_sites(st, hours)
		"repair":
			var n := SettlementJobs.repair_some(st, hours)
			o["done"] = int(o.done) + n
			return n > 0
		"cut_wood":
			var n := mini(WOOD_PER_H * h, left)
			if n <= 0:
				return false
			Trees.settlement_cut(st, n)  # (the trees near the settlement fall for it: docs/survival_nature.md)
			st.server_put("planks", n)
			o["done"] = int(o.done) + n
			return true
		"sandbags":
			var n := mini(mini(SANDBAGS_PER_H * h, left), Settlement.count("cloth_rag"))
			if n <= 0:
				return false
			Settlement.server_take("cloth_rag", n)
			st.server_put("sandbag", n)
			o["done"] = int(o.done) + n
			return true
		"smoke_meat":
			var n := mini(mini(STOVE_PER_H * h, left), Settlement.count("raw_meat"))
			if n <= 0 or not stove:
				return false
			Settlement.server_take("raw_meat", n)
			st.server_put("smoked_meat", n)
			o["done"] = int(o.done) + n
			return true
		"boil_water":
			var n := mini(mini(STOVE_PER_H * h, int(o.count) - clean_water()), Settlement.count("dirty_water_bottle"))
			if n <= 0 or not stove:
				return false
			Settlement.server_take("dirty_water_bottle", n)
			st.server_put("water_bottle", n, Needs.treat_water({}))
			o["done"] = clean_water()
			return true
		"craft":
			return _craft(st, o, h)
		"medical_supplies":
			return Clinic.work_order(o, hours)
	return false


static func clean_water() -> int:
	var n := 0
	for key: String in Settlement.stores():
		for e: Dictionary in Settlement.stores()[key]:
			var item := ItemDB.get_item(StringName(String(e.id)))
			if item and Settlement.category_of(String(e.id)) == "water" and Needs.quality_of(item, e.get("state", {})) == "clean":
				n += int(e.get("count", 1))
	return n


## The station a recipe needs, here: hands always, a fire is a stove, a workbench tier is a
## workbench (tiers later).
static func station_ok(station: String) -> bool:
	var d := Settlement.data()
	if station == "fire":
		return int(d.get("stoves", 0)) > 0
	if station.begins_with("workbench"):
		return int(d.get("workbenches", 0)) > 0
	return true


static func _craft(st: Settlement, o: Dictionary, h: int) -> bool:
	var r := Crafting.recipe(String((o.get("extra", {}) as Dictionary).get("recipe", "")))
	if r.is_empty() or not station_ok(String(r.get("station", "hands"))):
		return false
	var made := 0
	while made < CRAFT_PER_H * h and int(o.done) < int(o.count):
		var cost: Array = []
		for input: Array in r.get("inputs", []):
			cost.append([String(input[0]), int(input[1])])
		if not Settlement.pay(cost):
			break
		var out: Array = r.get("output", [])
		var state: Dictionary = (r.get("output_state", {}) as Dictionary).duplicate(true)
		if bool(r.get("treat_water", false)):
			state = Needs.treat_water(state)
		st.server_put(String(out[0]), int(out[1]), state)
		o["done"] = int(o.done) + 1
		made += 1
	return made > 0


## Host, every world hour: the counted orders brought up to date and the finished ones closed
## (a journal line); old done orders dropped off the list.
static func server_hour(st: Settlement) -> void:
	for o: Dictionary in list():
		if String(o.get("state", "open")) != "open":
			continue
		match String(o.kind):
			"build":
				if st.hosted():
					o["done"] = maxi(0, int(o.count) - SettlementJobs.sites(st).size())
			"boil_water":
				o["done"] = clean_water()
		if int(o.done) >= int(o.count):
			o["state"] = "done"
			o["done_h"] = Moods.now_h()
			Survival._journal_line("Work order done: %s." % text_of(o))
	var done := list().filter(func(o: Dictionary) -> bool: return String(o.get("state", "")) == "done")
	if done.size() > KEEP_DONE:
		var drop: Array = done.slice(0, done.size() - KEEP_DONE).map(func(o: Dictionary) -> int: return int(o.id))
		Settlement.data()["orders"] = list().filter(func(o: Dictionary) -> bool: return not (int(o.id) in drop))


## The planning view (doc §6): what's short ([text]) and who's idle ([names]).
static func planning(st: Settlement) -> Dictionary:
	var short: Array = []
	var people := st.members().size() if st else Settlement.settlers().size()
	if people > 0:
		var food_days := Settlement.food_kcal() / (Needs.KCAL_DAY * people)
		if food_days < SHORT_DAYS:
			short.append("food (%.1f days)" % food_days)
		var water_days := float(clean_water()) / (Needs.WATER_DAY * people)
		if water_days < SHORT_DAYS:
			short.append("water (%.1f days)" % water_days)
	var stove := int(Settlement.data().get("stoves", 0)) > 0
	for o: Dictionary in open_orders():
		var t := text_of(o)
		match String(o.kind):
			"sandbags":
				if Settlement.count("cloth_rag") < int(o.count) - int(o.done):
					short.append("cloth rags for %s" % t)
			"smoke_meat":
				if not stove:
					short.append("a stove for %s" % t)
				elif Settlement.count("raw_meat") <= 0:
					short.append("raw meat for %s" % t)
			"boil_water":
				if not stove:
					short.append("a stove for %s" % t)
				elif Settlement.count("dirty_water_bottle") <= 0 and clean_water() < int(o.count):
					short.append("water to boil for %s" % t)
			"craft":
				var r := Crafting.recipe(String((o.get("extra", {}) as Dictionary).get("recipe", "")))
				if not station_ok(String(r.get("station", "hands"))):
					short.append("a %s for %s" % [String(r.get("station", "")).replace("_", " "), t])
				for input: Array in r.get("inputs", []):
					if Settlement.count(String(input[0])) < int(input[1]):
						short.append("%s for %s" % [String(input[0]).replace("_", " "), t])
			"build":
				var need := materials_needed(st)
				for id: String in need:
					short.append("%d %s for the blueprints" % [int(need[id]), id.replace("_", " ")])
	var idle: Array = []
	for rec: Dictionary in Settlement.settlers():
		if Settlement.jobs_of(rec).is_empty() or String(rec.get("job_now", "")) == "idle":
			idle.append(String(rec.get("name", "")))
	return {"short": short, "idle": idle}


## The materials the unpaid blueprints still want beyond the stock: {item: count}.
static func materials_needed(st: Settlement) -> Dictionary:
	var want := {}
	var b: Builder = Builder.find(st) if st else null
	if b == null:
		return want
	for site: Array in SettlementJobs.sites(st):
		var cost: Array = []
		if int(site[1]) > 0:
			var prec: Dictionary = b.pieces[int(site[1])]
			if not bool(prec.get("paid", false)):
				cost = BuildPieces.PIECES[String(prec.k)].cost
		else:
			var rec: Dictionary = b.blocks[site[0]]
			if not bool(rec.get("paid", false)):
				cost = BuildPieces.block_cost(String(rec.m), String(rec.s))
		for pair: Array in cost:
			want[String(pair[0])] = int(want.get(String(pair[0]), 0)) + int(pair[1])
	for id: String in want.keys():
		var short := int(want[id]) - Settlement.count(id)
		if short > 0:
			want[id] = short
		else:
			want.erase(id)
	return want
