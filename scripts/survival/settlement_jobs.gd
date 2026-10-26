class_name SettlementJobs
extends RefCounted
## The settlement's jobs (docs/survival_building.md §6, call 59): one world hour of a settler's
## work, by the jobs they hold in priority order (Settlement "jobs" on the record). The first job
## with something to do takes the hour; with nothing, they're idle (the planning view shows it).
## Work orders (WorkOrders) come first within a job. A job a player is doing isn't taken over:
## a block site he's working (Builder.worked_by_player) and an order he claimed are skipped.
##
## - guard: the watch by day (the defence value counts them; Settlement.server_guard_check
##   calls out the dead and wakes sleepers); the night watch is the rota (Settlement).
## - scavenge: walks the containers (WorldCache) within SCAV_M of the settlement and brings back
##   what it finds into the stores; off the zone (or with none left) an abstract find.
## - farm: a stub until phase D's crops: farm bed pieces yield vegetables.
## - hunt (and fish): a stub yield of raw meat.
## - cook: the cook orders (smoke the meat, boil water) on a stove, else raw meat into hot meals.
## - medic: treats a member's light wound with meds from the stock.
## - build: the build orders (blueprints, cut wood, sandbags), else every blueprint and site in
##   the radius, with materials from the stock (Builder.server_work_from_stock).
## - haul: items lying on the ground in the radius into the stores.
## - maintain: the repair orders, else damaged builds repaired from stock.
## - craft: the craft orders (Crafting's recipes, the workbench and the stove as stations).
## - animals, generator: stubs (the generator burns fuel from the stock: the footprint's noise).
## Every number here is Proposed.

const JOBS: Array[String] = ["guard", "scavenge", "farm", "hunt", "cook", "medic", "build", "haul", "maintain", "craft", "animals", "generator"]
const NAMES := {"guard": "Guard", "scavenge": "Scavenge", "farm": "Farm", "hunt": "Hunt and fish", "cook": "Cook", "medic": "Medic",
	"build": "Build", "haul": "Haul", "maintain": "Maintain", "craft": "Craft", "animals": "Mind the animals", "generator": "Mind the generator"}
## Scavenging: how far the route goes, the chance an hour finds something, what's found off-zone.
const SCAV_M := 150.0
const SCAV_FIND := 0.6
const SCAV_FINDS: Array[String] = ["beans_tin", "water_bottle", "cloth_rag", "planks", "scrap_sheet", "canned_meat", "wood_stick", "pressure_bandage"]
## Yields per worked hour: a farm bed's vegetables, a hunter's meat.
const FARM_PER_BED_H := 0.125
const HUNT_PER_H := 0.25
## Raw meat cooked an hour, and how many hot meals in stock a member is enough.
const COOK_PER_H := 3
const MEALS_PER_MEMBER := 2
## The build job's work an hour, in a player's seconds of building (a world hour is 2 real
## minutes at DAY_MIN 48).
const WORK_S_PER_H := 120.0
## Items hauled an hour; repairs an hour.
const HAUL_PER_H := 12
const REPAIRS_PER_H := 4
## A generator burns a fuel item this many hours.
const FUEL_H := 12.0


## Host: `rec` works `hours` at the settlement `st`: the first of their jobs that has something to
## do. Returns the job worked, or "idle".
static func work(st: Settlement, rec: Dictionary, hours: float) -> String:
	for job: String in Settlement.jobs_of(rec):
		if do_job(st, job, rec, hours):
			return job
	return "idle"


static func do_job(st: Settlement, job: String, rec: Dictionary, hours: float) -> bool:
	match job:
		"guard":
			return true
		"scavenge":
			return scavenge(st, hours)
		"farm":
			return farm(st, hours)
		"hunt":
			return _yield(st, "hunt", HUNT_PER_H * hours * Migration.hunt_x(), "raw_meat")  # (the season's game)
		"cook":
			return WorkOrders.work_for(st, "cook", hours) or cook(st, hours)
		"medic":
			return medic(st, rec)
		"build":
			return WorkOrders.work_for(st, "build", hours) or build_sites(st, hours)
		"haul":
			return haul(st, hours)
		"maintain":
			return WorkOrders.work_for(st, "maintain", hours) or repair_some(st, hours) > 0 or Infrastructure.work_project(st, hours)
		"craft":
			return WorkOrders.work_for(st, "craft", hours)
		"generator":
			return generator(st, hours)
	return false  # (animals: phase D's mounts and pens)


## A running fraction toward whole items (the settlement's "acc").
static func _acc(key: String, add: float) -> int:
	var acc: Dictionary = Settlement.data().get("acc", {})
	var v := float(acc.get(key, 0.0)) + add
	var whole := floori(v)
	acc[key] = v - whole
	Settlement.data()["acc"] = acc
	return whole


static func _yield(st: Settlement, key: String, amount: float, item: String) -> bool:
	var n := _acc(key, amount)
	if n > 0:
		st.server_put(item, n)
	return true


static func scavenge(st: Settlement, hours: float) -> bool:
	var finds := 0
	for i in maxi(1, roundi(hours)):
		if Settlement._roll() >= SCAV_FIND:
			continue
		if st.hosted() and _from_cache(st):
			finds += 1
			continue
		var pick := SCAV_FINDS[mini(SCAV_FINDS.size() - 1, floori(Settlement._roll() * SCAV_FINDS.size()))]
		st.server_put(pick, 1)
		finds += 1
	return true


## One entry from a container (WorldCache) on the route, into the stores. Returns whether.
static func _from_cache(st: Settlement) -> bool:
	for node in st.get_tree().get_nodes_in_group(WorldCache.GROUP):
		var cache := node as WorldCache
		if cache == null or cache.cargo_hold == null or cache.is_locked() or cache.global_position.distance_to(Settlement.pos()) > SCAV_M:
			continue
		var list := cache.cargo_hold.entries()
		if list.is_empty():
			continue
		var e: Dictionary = cache.cargo_hold.remove_entry(VehicleCargo.HOLD, 0, int((list[0] as Dictionary).get("count", 1)))
		if e.is_empty():
			continue
		st.server_put(String(e.id), int(e.get("count", 1)), e.get("state", {}))
		return true
	return false


static func farm(st: Settlement, hours: float) -> bool:
	var beds := int(Settlement.data().get("farm_beds", 0))
	if beds <= 0:
		return false
	var x := Seasons.farm_yield_x(st, beds)  # (phase D: planting and harvest windows, winter's stop)
	if x < 0.0:
		return false
	if x == 0.0:
		return true
	return _yield(st, "farm", beds * FARM_PER_BED_H * hours * x, "vegetables")


static func cook(st: Settlement, hours: float) -> bool:
	if int(Settlement.data().get("stoves", 0)) <= 0:
		return false
	var want := st.members().size() * MEALS_PER_MEMBER - Settlement.count("cooked_meal")
	var n := mini(mini(COOK_PER_H * maxi(1, roundi(hours)), want), Settlement.count("raw_meat"))
	if n <= 0:
		return false
	Settlement.server_take("raw_meat", n)
	st.server_put("cooked_meal", n)
	return true


static func medic(st: Settlement, _rec: Dictionary) -> bool:
	for m: Dictionary in st.members():
		var wounds: Array = m.get("wounds", [])
		if wounds.is_empty():
			continue
		var meds := Settlement.first_stocked(func(item: ItemData, iid: String) -> bool: return Settlement.category_of(iid) == "meds" and item.type == "medical")
		if meds == "":
			return false
		Settlement.server_take(meds, 1)
		wounds.remove_at(0)
		m["wounds"] = wounds
		SurvivorPerson.note(m, "patched up at the settlement")
		return true
	return false


## The unbuilt block sites and blueprints (and upgrades) in the radius, lowest first, and the
## unbuilt pieces: [[cell or null, piece id or -1], ...].
static func sites(st: Settlement) -> Array:
	var b := Builder.find(st)
	var out: Array = []
	if b == null or not st.hosted():
		return out
	var c := Settlement.pos()
	var r := Settlement.radius()
	var cells: Array = []
	for cell: Vector3i in b.blocks:
		var rec: Dictionary = b.blocks[cell]
		if (not b.is_built(cell) or rec.has("up")) and BuildPieces.cell_centre(cell).distance_to(c) <= r:
			cells.append(cell)
	cells.sort_custom(func(x: Vector3i, y: Vector3i) -> bool: return x.y < y.y or (x.y == y.y and BuildPieces.cell_centre(x).distance_to(c) < BuildPieces.cell_centre(y).distance_to(c)))
	for cell: Vector3i in cells:
		out.append([cell, -1])
	for id: int in b.pieces:
		if not b.is_piece_built(id) and b.piece_pos(id).distance_to(c) <= r + 2.0:
			out.append([null, id])
	return out


## Host: an hour of the build job on the sites: WORK_S_PER_H spread over them in order.
## Returns whether any work was done.
static func build_sites(st: Settlement, hours: float) -> bool:
	var b := Builder.find(st)
	if b == null:
		return false
	var left := WORK_S_PER_H * hours * Infrastructure.build_mult()  # (phase D: powered tools)
	var worked := false
	for site: Array in sites(st):
		if left <= 0.0:
			break
		var id := int(site[1])
		if id > 0:
			if b.worked_by_player(Vector3i.ZERO, id):
				continue
			var def: Dictionary = BuildPieces.PIECES[String(b.pieces[id].k)]
			var need := float(def.build_s) * (1.0 - float(b.pieces[id].prog))
			var spend := minf(left, need)
			if b.server_work_piece_from_stock(id, spend, _pay()) == "":
				left -= spend
				worked = true
			continue
		var cell: Vector3i = site[0]
		if b.worked_by_player(cell):
			continue
		var rec: Dictionary = b.blocks[cell]
		var mat := String(rec.get("up", rec.m))
		var prog := float(rec.get("uprog", 0.0)) if rec.has("up") else float(rec.get("prog", 0.0))
		var need := float(BuildPieces.MATERIALS[mat].build_s) * (1.0 - prog)
		var spend := minf(left, need + 0.01)
		var why := b.server_work_from_stock(cell, spend, _pay())
		if why == "" or why == "Nothing holds it yet":
			left -= spend
			worked = true
	return worked


## Host: up to REPAIRS_PER_H damaged blocks and pieces in the radius repaired from stock.
## Returns how many.
static func repair_some(st: Settlement, hours: float) -> int:
	var b := Builder.find(st)
	if b == null or not st.hosted():
		return 0
	var c := Settlement.pos()
	var r := Settlement.radius()
	var n := 0
	var cap := REPAIRS_PER_H * maxi(1, roundi(hours))
	for cell: Vector3i in b.blocks.keys():
		if n >= cap:
			break
		if b.is_built(cell) and float(b.blocks[cell].get("hp", 1.0)) < 0.999 and BuildPieces.cell_centre(cell).distance_to(c) <= r:
			if b.server_repair_from_stock(cell, -1, _pay()):
				n += 1
	for id: int in b.pieces.keys():
		if n >= cap:
			break
		if b.piece_pos(id).distance_to(c) <= r + 2.0 and b.server_repair_from_stock(Vector3i.ZERO, id, _pay()):
			n += 1
	return n


## Host: up to HAUL_PER_H items lying in the radius (WorldItem) carried into the stores.
static func haul(st: Settlement, hours: float) -> bool:
	if not st.hosted():
		return false
	var c := Settlement.pos()
	var r := Settlement.radius()
	var cap := HAUL_PER_H * maxi(1, roundi(hours))
	var moved := 0
	for node in st.get_tree().get_nodes_in_group(&"world_items"):
		if moved >= cap:
			break
		var wi := node as WorldItem
		if wi == null or wi.is_queued_for_deletion() or wi.global_position.distance_to(c) > r or wi.item_id in Crafting.FIRE_ITEMS:
			continue
		if ItemDB.get_item(wi.item_id) == null:
			continue
		st.server_put(String(wi.item_id), wi.count, wi.state)
		GameState.item_taken(wi.uid)
		wi.queue_free()
		moved += 1
	return moved > 0 or Masking.server_bury_some(st, hours)  # (phase D: the dead's bodies buried)


static func generator(_st: Settlement, hours: float) -> bool:
	var d := Settlement.data()
	if int(d.get("generators", 0)) <= 0:
		d["power"] = false
		return false
	var fuel := Settlement.first_stocked(func(_item: ItemData, iid: String) -> bool: return Settlement.category_of(iid) == "fuel")
	if fuel == "":
		d["power"] = false
		return false
	if _acc("fuel", hours / FUEL_H) > 0:
		Settlement.server_take(fuel, 1)
	d["power"] = true
	return true


## The builder's pay callable: a cost taken out of the settlement's stock (Settlement.pay).
static func _pay() -> Callable:
	return func(cost: Array) -> bool: return Settlement.pay(cost)
