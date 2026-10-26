class_name Settlement
extends Node
## The players' settlement in Contractor: Fallen (docs/survival_building.md §5-7, calls 23, 28,
## 59): the safehouse grown into a place, kept as one record in Survival.state()["settlement"]
## (saved with the world) and run on the host by this node ("Settlement" under the zone being
## played; Survival.server_level_ready installs it, a client's screen makes its own for the RPCs).
##
## - Where: a zone and a spot (the safehouse mark when the start zone is played, or
##   server_found), and RADIUS_M round it: the builds inside are the settlement's.
## - Members: every Person with status "settler" (SurvivorPerson), plus companions when home
##   (within the radius). Settlers live here: they have jobs in priority order ("jobs" on the
##   record), a schedule (sleep by night, meals, work by day, the guard rotation the exception:
##   server_hour), and their needs come out of the stocks (they eat and drink from the stores; a
##   settlement out of food starves them and the moods follow).
## - Stocks (call 59): what's in the stash and pile pieces (their contents live here in
##   "stores" by piece id, since pieces don't carry storage) and the "yard" (what's put down with
##   no stash room), counted by CATEGORIES with a trend over the last day.
## - Beds (bunk pieces), the defence value (walls by tier, gates, lookouts, guards), the noise
##   and light footprint (generators and lamps: call 90's later work reads footprint()), morale
##   (the members' mean mood) and a size cap by beds and food (SIZE_MAX, Proposed 24).
## - The work: SettlementJobs (one world hour of a job), WorkOrders (orders with a count and a
##   priority, the planning view), Council (votes), SettlementScreen (the "[" screen).
## Every number here is Proposed.

const NODE_NAME := "Settlement"
const KEY := "settlement"
const YARD := "yard"
const RADIUS_M := 40.0
const SIZE_MAX := 24
## The cap's food side: as many as the food in stock feeds this many days.
const FOOD_DAYS := 3.0
## How many items a store holds (counts; the yard has no limit).
const STORE_CAP := {"stash": 60, "pile": 300}
const TICK_S := 1.0
const REFRESH_S := 5.0
## Settler bodies: within LIVE_M of a player at home they're bodies, past DESPAWN_M records.
const LIVE_M := 90.0
const DESPAWN_M := 110.0
## Hours missed while the clock jumped (sleep, waiting, a load) run up to this many at once.
const CATCH_UP_H := 72
## The stock categories (doc §5, call 59) and the items that are each (the rest by tag/type).
const CATEGORIES: Array[String] = ["food", "water", "fuel", "firewood", "wood", "scrap", "sand", "brick", "concrete", "steel", "meds", "ammo", "parts"]
const ITEM_CATS := {"planks": "wood", "scrap_sheet": "scrap", "sandbag": "sand", "brick": "brick", "concrete_bag": "concrete",
	"steel_beam": "steel", "wood_stick": "firewood", "firewood": "firewood", "jerrycan": "fuel"}
## The schedule (doc §6): sleep from SLEEP_FROM to SLEEP_TO, meals at MEALS, work the day.
const SLEEP_FROM := 22
const SLEEP_TO := 6
const MEALS: Array[int] = [7, 12, 18]
const WORK_FROM := 7
const WORK_TO := 19
## Eat at a meal under this hunger (or any hour under HUNGRY), drink under DRINK_BELOW.
const EAT_BELOW := 70.0
const HUNGRY := 35.0
const DRINK_BELOW := 60.0
const MEAL_MAX := 3
## The night watch: a guard stands WATCH_SHIFT_H hours a shift; over LONG_WATCH_H a night is
## "too long a watch".
const WATCH_SHIFT_H := 4
const LONG_WATCH_H := 4
## The guard sees the dead coming within this of the settlement; calls out again after this.
const GUARD_SEE_M := 60.0
const CALL_GAP_S := 30.0
## Defence (doc §9's inputs): per full block by material, per piece, per guard on duty.
const DEFENCE_BLOCK := {"wood": 0.2, "scrap": 0.3, "sandbag": 0.4, "brick": 0.6, "concrete": 0.8, "steel": 1.2}
const DEFENCE_PIECE := {"gate": 6.0, "door": 1.0, "shutter": 0.5, "hatch": 0.5, "fence": 1.0, "hesco": 8.0, "wire": 3.0, "lookout": 10.0,
	"spike_pit": 3.0, "bear_trap": 1.0, "drawbridge": 6.0, "corridor_marker": 2.0, "electric_fence": 5.0}  # (phase D: Traps, Infrastructure)
const DEFENCE_GUARD := 10.0
## The footprint (call 90): a running generator is heard this far, a lamp seen this far.
const NOISE_GENERATOR_M := 60.0
const LIGHT_LAMP_M := 15.0
## Jobs liked and hated (moodlets "job_liked"/"job_hated"): by background and by trait.
const LIKES := {"farmer": "farm", "cook": "cook", "nurse": "medic", "paramedic": "medic", "carpenter": "build",
	"hunter": "hunt", "soldier": "guard", "police officer": "guard", "mechanic": "maintain", "electrician": "generator",
	"truck driver": "haul", "student": "scavenge", "teacher": "craft", "shop clerk": "haul"}
const HATES := {"squeamish": ["medic", "hunt"], "timid": ["guard", "scavenge"], "lazy": ["haul", "build"]}
## The first jobs a new settler takes by background (then haul as the fallback).
const FIRST_JOBS := {"farmer": ["farm", "haul"], "cook": ["cook", "haul"], "nurse": ["medic", "cook"], "paramedic": ["medic", "guard"],
	"carpenter": ["build", "maintain"], "hunter": ["hunt", "guard"], "soldier": ["guard", "scavenge"], "police officer": ["guard", "haul"],
	"mechanic": ["maintain", "build"], "electrician": ["generator", "maintain"], "truck driver": ["haul", "scavenge"]}

## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0

var level: CompoundLevel
## Host: the last guard's call (sec), what it said (tests and the screen).
var last_call := ""
var _last_call_at := -1000.0
var _tick := 0.0
var _refresh := 0.0
var _hour := -1
var _hosted_s := 0.0
var _view_cb: Callable  # client: the screen waiting for a view


func _init() -> void:
	name = NODE_NAME


## `level`'s Settlement node, made if it has none (every peer).
static func install(p_level: Node) -> Settlement:
	if p_level == null:
		return null
	var st := p_level.get_node_or_null(NODE_NAME) as Settlement
	if st == null:
		st = Settlement.new()
		st.level = p_level as CompoundLevel
		p_level.add_child(st)
	return st


## The Settlement node of the level `from` is in (null when none).
static func find(from: Node) -> Settlement:
	var lvl: CompoundLevel = CompoundLevel.current(from) if from and from.is_inside_tree() else null
	return lvl.get_node_or_null(NODE_NAME) as Settlement if lvl else null


## The settlement's record ({} before it's founded).
static func data() -> Dictionary:
	var d: Variant = Survival.state().get(KEY)
	return d if d is Dictionary else {}


static func exists() -> bool:
	return not data().is_empty()


## Host: the settlement founded in `zone` at `at` (a new record; an old one is kept, moved).
static func server_found(zone_id: String, at: Vector3) -> Dictionary:
	var d := data()
	if d.is_empty():
		d = {"zone": zone_id, "pos": [0.0, 0.0, 0.0], "radius": RADIUS_M, "founded_day": Survival.day(), "stores": {}, "orders": [],
			"next_order": 1, "history": [], "council": {}, "beds": 0, "defence": 0.0, "footprint": {"noise_m": 0.0, "light_m": 0.0},
			"farm_beds": 0, "stoves": 0, "workbenches": 0, "generators": 0, "watch": {}, "acc": {}}
		Survival.state()[KEY] = d
		Survival._journal_line("We made the safehouse a home.")
	d["zone"] = zone_id
	d["pos"] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
	return d


static func pos() -> Vector3:
	var p: Array = data().get("pos", [0.0, 0.0, 0.0])
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() >= 3 else Vector3.ZERO


static func zone() -> String:
	return String(data().get("zone", ""))


static func radius() -> float:
	return float(data().get("radius", RADIUS_M))


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


# --- Who lives here -------------------------------------------------------------------------

## Every settler's record.
static func settlers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not exists():
		return out
	for rec: Dictionary in SurvivorsLayer.records().values():
		if String(rec.get("status", "")) == "settler":
			out.append(rec)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("settled_h", 0.0)) < float(b.get("settled_h", 0.0)))
	return out


## The members: settlers, and companions at home (in the settlement's zone, within its radius).
func members() -> Array[Dictionary]:
	var out := settlers()
	if not exists():
		return out
	var layer: SurvivorsLayer = SurvivorsLayer.find(self) if is_inside_tree() else null
	for rec: Dictionary in SurvivorsLayer.records().values():
		if String(rec.get("status", "")) != "companion" or String(rec.get("zone", "")) != zone():
			continue
		var body: Soldier = layer.body_of(String(rec.id)) if layer else null
		var at := body.global_position if body else SurvivorPerson.pos_of(rec)
		if at.distance_to(pos()) <= radius():
			out.append(rec)
	return out


static func beds() -> int:
	return int(data().get("beds", 0))


static func free_beds() -> int:
	return maxi(0, beds() - settlers().size())


## The size cap (call 28): beds, the food in stock for FOOD_DAYS, at most SIZE_MAX.
static func size_cap() -> int:
	var fed := floori(food_kcal() / (Needs.KCAL_DAY * FOOD_DAYS))
	return mini(SIZE_MAX, mini(beds(), maxi(fed, settlers().size())))


## Whether a survivor wanting a place can have one here ("" yes, else "place").
static func place_problem() -> String:
	return "" if exists() and free_beds() > 0 and settlers().size() < SIZE_MAX else "place"


## Whether settler `rec` has a bed (the first `beds()` settlers to come do).
static func has_bed(rec: Dictionary) -> bool:
	var list := settlers()
	var i := list.find(rec)
	return i >= 0 and i < beds()


## Host: `rec` lives here now (SurvivorsLayer.server_settle and TalkMenu: a place want met, or
## "Make a settler"): status settler, home at the settlement, jobs by background.
static func server_make_settler(rec: Dictionary, by: Soldier = null) -> void:
	var d := data()
	var was := String(rec.get("status", ""))
	rec["status"] = "settler"
	rec["zone"] = zone()
	rec["settled_h"] = Moods.now_h()
	var i := settlers().size()
	var a := float(i) * 2.4
	var home := pos() + Vector3(cos(a), 0.0, sin(a)) * (3.0 + float(i % 4))
	SurvivorPerson.set_pos(rec, home)
	SurvivorPerson.set_pos(rec, home, "home")
	if not rec.get("jobs") is Array or (rec.jobs as Array).is_empty():
		rec["jobs"] = (FIRST_JOBS.get(String(rec.get("background", "")), ["haul", "scavenge"]) as Array).duplicate()
	if Children.is_child_rec(rec):
		rec["jobs"] = Children.jobs_for(rec)  # light jobs only, from 12 (call 128)
	elif Faith.is_pious(rec) and not "service" in (rec.jobs as Array):
		(rec.jobs as Array).push_front("service")  # the chapel's daily service (call 129)
	rec["job_now"] = ""
	rec["activity"] = "free"
	Moods.add(rec, "joined")
	for o: Dictionary in settlers():
		if o != rec:
			Moods.add(o, "settlement_grew")
	SurvivorPerson.note(rec, "settled at the safehouse" + ((" (brought by %s)" % Survival.survivor_name(by)) if by else ""))
	Survival._journal_line("%s %s." % [String(rec.name), "stays at the settlement now" if was == "companion" else "settled with us"])
	if not d.is_empty():
		d["size_seen"] = settlers().size()


## Host: `rec` leaves the settlement's roll (taken along as a companion: SurvivorsLayer).
static func server_unsettle(rec: Dictionary) -> void:
	rec["status"] = "companion"
	rec["activity"] = ""
	rec["job_now"] = ""
	var n: Dictionary = rec.get("needs", {})
	if not n.is_empty():
		SurvivalSleep.wake(n)


## The job list of `rec` (priority order).
static func jobs_of(rec: Dictionary) -> Array:
	var j: Variant = rec.get("jobs", [])
	return j if j is Array else []


## Host: sets `rec`'s jobs (known ones only, in order).
static func server_set_jobs(rec: Dictionary, jobs: Array) -> void:
	var out: Array = []
	for j: Variant in jobs:
		if String(j) in SettlementJobs.JOBS and not String(j) in out:
			out.append(String(j))
	rec["jobs"] = Children.filter_jobs(rec, out)


## Morale: the members' mean mood (50 with nobody).
func morale() -> float:
	var list := members()
	if list.is_empty():
		return Moods.BASE
	var sum := 0.0
	for r: Dictionary in list:
		sum += Moods.mood(r)
	return sum / list.size()


# --- Stocks ---------------------------------------------------------------------------------

## The stock category of item `id` ("" for none of them: still stored, counted as other).
static func category_of(id: String) -> String:
	if ITEM_CATS.has(id):
		return String(ITEM_CATS[id])
	var item := ItemDB.get_item(StringName(id))
	if item == null:
		return ""
	if "fuel" in item.tags:
		return "fuel"
	if item.type == "medical" or "medical" in item.tags or "drug" in item.tags:
		return "meds"
	if item.type == "ammo" or item.type == "mag":
		return "ammo"
	if id.ends_with("_parts") or item.type == "salvage":
		return "parts"
	if item.stats.has("kcal") and float(item.stats.get("kcal", 0.0)) >= 100.0:
		return "food"
	if item.stats.has("water_l"):
		return "water"
	return ""


## Every store's contents by key (a stash or pile piece's id, or YARD).
static func stores() -> Dictionary:
	var d := data()
	if not d.get("stores") is Dictionary:
		d["stores"] = {}
	return d.get("stores", {})


static func _entries(key: String) -> Array:
	var s := stores()
	if not s.get(key) is Array:
		s[key] = []
	return s[key]


static func _used(key: String) -> int:
	var n := 0
	for e: Dictionary in _entries(key):
		n += int(e.get("count", 1))
	return n


## How many of `id` are in stock.
static func count(id: String) -> int:
	var n := 0
	for key: String in stores():
		for e: Dictionary in _entries(key):
			if String(e.id) == id:
				n += int(e.get("count", 1))
	return n


## How many items of category `cat` are in stock.
static func count_cat(cat: String) -> int:
	var n := 0
	for key: String in stores():
		for e: Dictionary in _entries(key):
			if category_of(String(e.id)) == cat:
				n += int(e.get("count", 1))
	return n


## Every category's count now.
static func stocks() -> Dictionary:
	var out := {}
	for c: String in CATEGORIES:
		out[c] = 0
	for key: String in stores():
		for e: Dictionary in _entries(key):
			var c := category_of(String(e.id))
			if out.has(c):
				out[c] = int(out[c]) + int(e.get("count", 1))
	return out


## The food in stock in kcal (what the cap and the planning view read).
static func food_kcal() -> float:
	var kcal := 0.0
	for key: String in stores():
		for e: Dictionary in _entries(key):
			var item := ItemDB.get_item(StringName(String(e.id)))
			if item and category_of(String(e.id)) == "food":
				kcal += float(item.stats.get("kcal", 0.0)) * int(e.get("count", 1))
	return kcal


## The stores with room, stashes first then piles, then the yard (the keys).
func _store_keys() -> Array[String]:
	var out: Array[String] = []
	var b: Builder = Builder.find(self) if hosted() else null
	for key: String in stores():
		if key != YARD:
			out.append(key)
	if b:
		for kind: String in ["stash", "pile"]:
			for id: int in b.pieces_of(kind):
				if b.piece_pos(id).distance_to(pos()) <= radius() + 4.0 and not str(id) in out:
					out.append(str(id))
					_entries(str(id))
	out.sort_custom(func(x: String, y: String) -> bool: return _cap_of(x) < _cap_of(y))
	out.append(YARD)
	return out


func _cap_of(key: String) -> int:
	if key == YARD:
		return 1 << 30
	var b: Builder = Builder.find(self) if hosted() else null
	var kind := String(b.pieces.get(int(key), {}).get("k", "stash")) if b else String(data().get("store_kinds", {}).get(key, "stash"))
	return int(STORE_CAP.get(kind, 60))


## Host: puts `n` of `id` (with `state`) in stock: the stashes with room first, the rest in the
## yard. Returns how many went in (all of them).
func server_put(id: String, n: int, state := {}) -> int:
	if n <= 0 or not exists():
		return 0
	var left := n
	for key: String in _store_keys():
		var room := _cap_of(key) - _used(key)
		if room <= 0:
			continue
		var put := mini(room, left)
		_add_entry(_entries(key), id, put, state)
		left -= put
		if left <= 0:
			break
	return n - left


static func _add_entry(list: Array, id: String, n: int, state: Dictionary) -> void:
	if state.is_empty():
		for e: Dictionary in list:
			if String(e.id) == id and (e.get("state", {}) as Dictionary).is_empty():
				e["count"] = int(e.get("count", 1)) + n
				return
	var e := {"id": id, "count": n}
	if not state.is_empty():
		e["state"] = state.duplicate(true)
	list.append(e)


## Host: takes up to `n` of `id` out of stock (the yard first). Returns the entries taken
## ([{id, count, state}]).
static func server_take(id: String, n: int) -> Array:
	var out: Array = []
	var keys: Array = [YARD] if stores().has(YARD) else []
	for k: String in stores():
		if k != YARD:
			keys.append(k)
	for key: String in keys:
		var list := _entries(key)
		var i := 0
		while i < list.size() and n > 0:
			var e: Dictionary = list[i]
			if String(e.id) != id:
				i += 1
				continue
			var take := mini(n, int(e.get("count", 1)))
			out.append({"id": id, "count": take, "state": (e.get("state", {}) as Dictionary).duplicate(true)})
			n -= take
			e["count"] = int(e.get("count", 1)) - take
			if int(e.count) <= 0:
				list.remove_at(i)
			else:
				i += 1
	return out


static func taken_count(entries: Array) -> int:
	var n := 0
	for e: Dictionary in entries:
		n += int(e.get("count", 0))
	return n


## Whether the stock covers `cost` ([[item, count], ...]).
static func has_cost(cost: Array) -> bool:
	for pair: Array in cost:
		if count(String(pair[0])) < int(pair[1]):
			return false
	return true


## Host: takes `cost` out of stock if it's all there (Builder's pay callable). Returns whether.
static func pay(cost: Array) -> bool:
	if not has_cost(cost):
		return false
	for pair: Array in cost:
		server_take(String(pair[0]), int(pair[1]))
	return true


## The first item in stock that `pred` (ItemData, id -> bool) takes, or "".
static func first_stocked(pred: Callable) -> String:
	for key: String in stores():
		for e: Dictionary in _entries(key):
			var item := ItemDB.get_item(StringName(String(e.id)))
			if item and bool(pred.call(item, String(e.id))):
				return String(e.id)
	return ""


## The trend of `cat` over the last day (now minus the oldest snapshot within 24 world hours).
static func trend(cat: String) -> int:
	var h: Array = data().get("history", [])
	if h.is_empty():
		return 0
	var now_h := Moods.now_h()
	for snap: Dictionary in h:
		if now_h - float(snap.get("h", 0.0)) <= 24.5:
			return int(stocks().get(cat, 0)) - int((snap.get("s", {}) as Dictionary).get(cat, 0))
	return 0


static func _snapshot() -> void:
	var d := data()
	var h: Array = d.get("history", [])
	h.append({"h": Moods.now_h(), "s": stocks()})
	d["history"] = h.slice(-26)


## Host: `s` stows what he carries that's stock (food, water, materials, meds, ammo, parts) into
## the settlement's stores; he must be within its radius. Returns how many items went in.
func server_stow(s: Soldier) -> int:
	if s == null or not exists() or not hosted() or s.global_position.distance_to(pos()) > radius():
		return 0
	var n := 0
	for c: StringName in s.inventory.search_containers():
		var list: Array = s.inventory.containers.get(c, [])
		var i := list.size() - 1
		while i >= 0:
			var e: Dictionary = list[i]
			if category_of(String(e.id)) != "":
				var cnt := int(e.get("count", 1))
				var got: Dictionary = s.inventory.remove_entry(c, i, cnt)
				if not got.is_empty():
					n += server_put(String(got.id), int(got.get("count", cnt)), got.get("state", {}))
			i -= 1
	return n


## Host: `s` takes `n` of `id` out of stock into his kit (at his feet what won't fit).
func server_take_for(s: Soldier, id: String, n: int) -> int:
	if s == null or not hosted() or s.global_position.distance_to(pos()) > radius():
		return 0
	var got := 0
	for e: Dictionary in server_take(id, n):
		var c := int(e.count)
		var fit := s.inventory.take(StringName(id), c, e.get("state", {}))
		if fit < c and level:
			level.server_spawn_dropped(StringName(id), c - fit, s.global_position + Vector3.UP * 0.3, e.get("state", {}))
		got += c
	return got


# --- The place: beds, defence, footprint -------------------------------------------------------

## Whether the settlement's zone is the one being played here.
func hosted() -> bool:
	return exists() and level != null and String(Survival.state().get("zone", "")) == zone() and Builder.find(self) != null


## Host: beds, the defence's builds, the footprint and the work stations read from the builds
## within the radius (cached in the record: read while the zone isn't played).
func refresh() -> void:
	var b := Builder.find(self)
	if b == null or not hosted():
		return
	var d := data()
	var c := pos()
	var r := radius() + 4.0
	var counts := {}
	var defence := 0.0
	var kinds := {}
	for id: int in b.pieces:
		if not b.is_piece_built(id) or b.piece_pos(id).distance_to(c) > r:
			continue
		var k := String(b.pieces[id].k)
		counts[k] = int(counts.get(k, 0)) + 1
		defence += float(DEFENCE_PIECE.get(k, 0.0))
		if k in ["stash", "pile"]:
			kinds[str(id)] = k
	for cell: Vector3i in b.blocks:
		if not b.is_built(cell) or BuildPieces.cell_centre(cell).distance_to(c) > r:
			continue
		var rec: Dictionary = b.blocks[cell]
		defence += float(DEFENCE_BLOCK.get(String(rec.m), 0.2)) * float(BuildPieces.SHAPES[String(rec.s)].frac) * float(rec.get("hp", 1.0))
	d["beds"] = int(counts.get("bunk", 0))
	d["farm_beds"] = int(counts.get("farm_bed", 0))
	d["stoves"] = int(counts.get("stove", 0))
	d["workbenches"] = int(counts.get("workbench", 0))
	d["generators"] = int(counts.get("generator", 0))
	d["lamps"] = int(counts.get("lamp", 0))
	d["altars"] = int(counts.get("altar", 0))  # the chapel (Faith, call 129)
	d["chapel_benches"] = int(counts.get("chapel_bench", 0))
	d["defence_builds"] = snappedf(defence, 0.1)
	d["store_kinds"] = kinds
	Infrastructure.server_refresh(self, b)  # (phase D: power, what it runs, the lit lamps)
	# A store whose piece is gone: what was in it is in the yard (after the builds came back).
	if _hosted_s > 10.0:
		for key: String in stores().keys():
			if key != YARD and not kinds.has(key):
				for e: Dictionary in _entries(key):
					_add_entry(_entries(YARD), String(e.id), int(e.get("count", 1)), e.get("state", {}))
				stores().erase(key)
	d["footprint"] = footprint()


## The defence value: the builds' (cached) plus DEFENCE_GUARD per guard on duty.
func defence() -> float:
	return float(data().get("defence_builds", 0.0)) + DEFENCE_GUARD * on_watch().size()


## The noise and light footprint (call 90: the map's radius and zone pressure read it later):
## generators heard (when there's fuel in stock), lamps seen (by night).
static func footprint() -> Dictionary:
	var d := data()
	var gens := int(d.get("generators", 0))
	var noise := NOISE_GENERATOR_M * sqrt(float(gens)) if gens > 0 and count_cat("fuel") > 0 else 0.0
	var lit := int(d.get("lamps_lit", d.get("lamps", 0)))  # (phase D: lamps light with power, Infrastructure)
	var light := LIGHT_LAMP_M * sqrt(float(lit)) if lit > 0 else 0.0
	return {"noise_m": snappedf(noise, 0.1), "light_m": snappedf(light, 0.1), "value": snappedf(noise + light, 0.1)}


# --- The host's clock ---------------------------------------------------------------------------

func _ready() -> void:
	if level == null:
		level = get_parent() as CompoundLevel


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not Survival.running:
		return
	if not exists():
		_try_found()
		return
	_tick += delta
	if _tick < TICK_S:
		return
	var dt := _tick
	_tick = 0.0
	if hosted():
		_hosted_s += dt
		_refresh -= dt
		if _refresh <= 0.0:
			_refresh = REFRESH_S
			refresh()
			_settler_bodies()
		server_guard_check()
	var h := floori(Moods.now_h())
	if _hour < 0:
		_hour = h
	elif h > _hour:
		var n := mini(h - _hour, CATCH_UP_H)
		for i in n:
			server_hour(posmod(h - n + 1 + i, 24))
		_hour = h


## Host: the start zone's safehouse becomes the settlement the first time it's played.
func _try_found() -> void:
	var zone_id := String(Survival.state().get("zone", ""))
	if zone_id == "" or zone_id != String(Survival.state().get("start_zone", zone_id)) or not level is ZoneLevel:
		return
	var at := Vector3.INF
	var mark := SurvivalMap.safehouse()
	if not mark.is_empty() and String(mark.get("zone", "")) == zone_id:
		var p2 := SurvivalMap.mark_pos(mark)
		at = level.ground_point(Vector3(p2.x, 0.0, p2.y))
	else:
		var points := (level as ZoneLevel).insertion_points()
		if points.is_empty():
			return
		at = level.ground_point(points[0])
	server_found(zone_id, at)


## Host: settlers near a player at home are bodies (SurvivorsLayer), the rest records.
func _settler_bodies() -> void:
	var layer := SurvivorsLayer.find(self)
	if layer == null:
		return
	var players := MapNodes.players(level)
	for rec: Dictionary in settlers():
		var home := SurvivorPerson.pos_of(rec, "home")
		var d := INF
		for p: Soldier in players:
			d = minf(d, p.global_position.distance_to(home))
		var body := layer.body_of(String(rec.id))
		if body == null and d <= LIVE_M:
			layer.server_settler_body(rec, true)
		elif body and d > DESPAWN_M:
			layer.server_settler_body(rec, false)


# --- An hour of the settlement's life (doc §6: schedules, meals, work) --------------------------

## What `rec` does at hour-of-day `hod`: "sleep", "watch" (the night rota), "work" or "free".
func activity_at(rec: Dictionary, hod: int, watcher: Dictionary) -> String:
	if not watcher.is_empty() and watcher == rec:
		return "watch"
	if hod >= SLEEP_FROM or hod < SLEEP_TO:
		return "free" if float(rec.get("alarm_until_h", -1.0)) > Moods.now_h() else "sleep"
	if hod >= WORK_FROM and hod < WORK_TO:
		return "work"
	return "free"


## The guard on the night watch at `hod` (the rota through every settler with the guard job, a
## shift of WATCH_SHIFT_H each), or {}.
func watcher_at(hod: int) -> Dictionary:
	if not (hod >= SLEEP_FROM or hod < SLEEP_TO):
		return {}
	var guards := settlers().filter(func(r: Dictionary) -> bool: return "guard" in jobs_of(r) and String(r.get("break", "")) == "")
	if guards.is_empty():
		return {}
	var into := posmod(hod - SLEEP_FROM, 24)
	var shift := floori(float(into) / WATCH_SHIFT_H)
	var day_rota := int(data().get("watch", {}).get("rota", 0))
	return guards[(day_rota + shift) % guards.size()]


## Who's on watch now: the night's watcher, or by day the settlers working the guard job.
func on_watch() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in settlers():
		if String(rec.get("activity", "")) == "watch" or (String(rec.get("activity", "")) == "work" and String(rec.get("job_now", "")) == "guard"):
			out.append(rec)
	return out


## Host: one world hour (hour-of-day `hod`) of every settler: their body's hour (Needs) asleep or
## awake, meals and drinks from the stock, the watch, the work (SettlementJobs), the moodlets.
func server_hour(hod: int) -> void:
	if not exists():
		return
	var d := data()
	if hod == SLEEP_TO:
		var w: Dictionary = d.get("watch", {})
		w["rota"] = int(w.get("rota", 0)) + 1
		d["watch"] = w
	var watcher := watcher_at(hod)
	var mult := Survival.option_mult("needs")
	for rec: Dictionary in settlers():
		var n: Dictionary = rec.get("needs", {})
		if n.is_empty():
			n = Needs.fresh()
			rec["needs"] = n
		Needs.ensure(n)
		var bed := has_bed(rec)
		var act := activity_at(rec, hod, watcher)
		if String(rec.get("break", "")) in ["crying", "hiding", "binge"]:
			act = "free"
		var was_asleep := SurvivalSleep.is_asleep(n)
		if act == "sleep":
			n["asleep"] = "bed" if bed else "ground"
		elif was_asleep:
			SurvivalSleep.wake(n)
			Moods.add(rec, "slept_bed" if bed else "slept_ground")
		var night := hod >= SLEEP_FROM or hod < SLEEP_TO
		Needs.step(n, mult, {"indoors": bed, "moving": act in ["work", "watch"], "dark": 1.0 if night else 0.0})
		if act != "sleep":
			_meal(rec, n, hod in MEALS)
		rec["activity"] = act
		if act == "watch":
			rec["watch_h"] = float(rec.get("watch_h", 0.0)) + 1.0
			if float(rec.watch_h) > LONG_WATCH_H:
				Moods.add(rec, "long_watch")
			_job_moodlet(rec, "guard")
		elif act == "work":
			var job := SettlementJobs.work(self, rec, 1.0)
			rec["job_now"] = job
			if job != "idle":
				_job_moodlet(rec, job)
		else:
			rec["job_now"] = ""
		if hod == WORK_FROM:
			rec["watch_h"] = 0.0
		Moods.from_needs(rec, n)
	if hod % 3 == 0:
		_snapshot()
	Council.server_hour(self)
	WorkOrders.server_hour(self)
	Politics.server_hour(self, hod)  # (phase D: factions' moods, theft, splits, pacts)
	Infrastructure.server_hour(self, hod)  # (phase D: batteries, a lit settlement's pull)
	Children.settlement_hour(self, hod)  # the children's care (call 128)
	Faith.settlement_hour(self, hod)  # grace, the vigil, the cultists' rites (call 129)


## A meal (at a meal hour under EAT_BELOW, any hour under HUNGRY) and a drink from the stock:
## a hot meal is "ate_hot", raw meat "ate_raw" (only when there's nothing else).
func _meal(rec: Dictionary, n: Dictionary, meal_hour: bool) -> void:
	var eaten := 0
	while eaten < MEAL_MAX and float(n.get("hunger", 100.0)) < (EAT_BELOW if meal_hour else HUNGRY):
		var id := first_stocked(func(item: ItemData, iid: String) -> bool: return "hot" in item.tags and category_of(iid) == "food")
		if id == "":
			id = first_stocked(func(item: ItemData, iid: String) -> bool: return category_of(iid) == "food" and not bool(item.stats.get("raw", false)))
		if id == "":
			id = first_stocked(func(_item: ItemData, iid: String) -> bool: return category_of(iid) == "food")
		if id == "":
			break
		var got := server_take(id, 1)
		if got.is_empty():
			break
		var item := ItemDB.get_item(StringName(id))
		Needs.eat(n, item, (got[0] as Dictionary).get("state", {}))
		if "hot" in item.tags:
			Moods.add(rec, "ate_hot")
		elif bool(item.stats.get("raw", false)):
			Moods.add(rec, "ate_raw")
		eaten += 1
	var drunk := 0
	while drunk < 2 and float(n.get("thirst", 100.0)) < DRINK_BELOW:
		var w := first_stocked(func(item: ItemData, iid: String) -> bool: return category_of(iid) == "water" and Needs.quality_of(item) == "clean")
		if w == "" and float(n.get("thirst", 100.0)) < 25.0:
			w = first_stocked(func(_item: ItemData, iid: String) -> bool: return category_of(iid) == "water")
		if w == "":
			break
		var got := server_take(w, 1)
		if got.is_empty():
			break
		Needs.eat(n, ItemDB.get_item(StringName(w)), (got[0] as Dictionary).get("state", {}))
		drunk += 1


## A job liked or hated (background and traits): its moodlet for the day.
static func _job_moodlet(rec: Dictionary, job: String) -> void:
	if String(LIKES.get(String(rec.get("background", "")), "")) == job:
		Moods.add(rec, "job_liked")
	for t: String in HATES:
		if SurvivorPerson.has_trait(rec, t) and job in (HATES[t] as Array):
			Moods.add(rec, "job_hated")


# --- The watch (doc §6: a guard calls out the dead and wakes sleepers) ---------------------------

## Host: with someone on watch, one of the dead chasing (anything) within GUARD_SEE_M of the
## settlement has the guard call it out (a line to the players and the journal) and wake every
## sleeper here: settlers (up for the hour) and players asleep or waiting (SurvivalSleep's wake,
## Survival._wake). Returns how many woke.
func server_guard_check() -> int:
	if not hosted():
		return 0
	var guards := on_watch()
	if guards.is_empty():
		return 0
	var seen: Soldier = null
	for z: Soldier in Survival.zombies(level):
		var brain := ZombieAI.of(z)
		if brain and brain.mode == ZombieAI.Mode.CHASE and z.global_position.distance_to(pos()) <= GUARD_SEE_M:
			seen = z
			break
	if seen == null:
		return 0
	var now := Soldier._now()
	var woke := 0
	for rec: Dictionary in settlers():
		var n: Dictionary = rec.get("needs", {})
		if SurvivalSleep.is_asleep(n):
			SurvivalSleep.wake(n)
			rec["alarm_until_h"] = Moods.now_h() + 1.0
			rec["activity"] = "free"
			woke += 1
	for p: Soldier in MapNodes.players(level):
		var pn := Survival.needs_of(p)
		if SurvivalSleep.is_asleep(pn) or SurvivalSleep.is_waiting(pn):
			Survival._wake(p, "watch")
			woke += 1
	if now - _last_call_at >= CALL_GAP_S or woke > 0:
		_last_call_at = now
		var g: Dictionary = guards[0]
		last_call = "%s on watch: the dead, coming from the %s!" % [String(g.get("first", g.get("name", "The guard"))), _bearing(seen.global_position - pos())]
		Survival._journal_line(last_call)
		for p: Soldier in MapNodes.players(level):
			Survival._tell(p, last_call)
		var layer := SurvivorsLayer.find(self)
		var body: Soldier = layer.body_of(String(g.id)) if layer else null
		if body:
			layer.say(body, last_call.get_slice(": ", 1))
	return woke


static func _bearing(v: Vector3) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.z)), 360.0)
	return ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(a / 45.0)) % 8]


# --- The screen's view and actions (any peer -> host) -------------------------------------------

## Host: what the settlement screen shows (SettlementScreen.refresh reads it).
func view() -> Dictionary:
	if not exists():
		return {"exists": false}
	var people: Array = []
	for rec: Dictionary in members():
		people.append({"id": String(rec.id), "name": String(rec.get("name", "")), "status": String(rec.get("status", "")),
			"jobs": jobs_of(rec).duplicate(), "job_now": String(rec.get("job_now", "")), "activity": String(rec.get("activity", "")),
			"mood": snappedf(Moods.mood(rec), 1.0), "band": Moods.band(rec), "bed": has_bed(rec)})
	var st := {}
	var s := stocks()
	for c: String in CATEGORIES:
		st[c] = [int(s.get(c, 0)), trend(c)]
	return {"exists": true, "zone": zone(), "people": people, "stocks": st, "beds": beds(), "free_beds": free_beds(), "cap": size_cap(),
		"defence": snappedf(defence(), 0.1), "footprint": footprint(), "morale": snappedf(morale(), 1.0),
		"orders": WorkOrders.list().duplicate(true), "planning": WorkOrders.planning(self), "votes": Council.open_votes().duplicate(true),
		"challenge": Council.challenge().duplicate(true), "last_call": last_call, "standing": snappedf(Council.standing(self, BaseHub.profile()), 1.0)}


## Any peer: asks the host for the view; `done` gets it.
func ask_view(done: Callable) -> void:
	_view_cb = done
	if multiplayer.is_server():
		done.call(view())
	else:
		_request_view.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_view() -> void:
	if multiplayer.is_server():
		_client_view.rpc_id(multiplayer.get_remote_sender_id(), view())


@rpc("authority", "call_remote", "reliable")
func _client_view(v: Dictionary) -> void:
	if _view_cb.is_valid():
		_view_cb.call(v)


## Any peer: the screen's action (jobs, orders, stow/take, wait, vote) done on the host.
func ask(action: String, args: Array) -> void:
	if multiplayer.is_server():
		server_action(multiplayer.get_unique_id(), action, args)
	else:
		_request_action.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String, args: Array) -> void:
	if multiplayer.is_server():
		server_action(multiplayer.get_remote_sender_id(), action, args)


## Host: peer `peer`'s action. Returns "" or why not.
func server_action(peer: int, action: String, args: Array) -> String:
	var s: Soldier = level.players.get_node_or_null(str(peer)) as Soldier if level else null
	match action:
		"jobs":
			var rec := SurvivorsLayer.record(String(args[0])) if args.size() >= 2 else {}
			if rec.is_empty():
				return "Nobody"
			server_set_jobs(rec, args[1] if args[1] is Array else [])
		"order_add":
			if args.size() < 2:
				return "Bad order"
			var o := WorkOrders.server_add(String(args[0]), int(args[1]), int(args[2]) if args.size() > 2 else 3, args[3] if args.size() > 3 and args[3] is Dictionary else {})
			return "" if not o.is_empty() else "Can't order that"
		"order_remove":
			return "" if WorkOrders.server_remove(int(args[0])) else "No such order"
		"order_claim":
			return "" if s and WorkOrders.server_claim(int(args[0]), Survival.profile_of(s)) else "No such order"
		"stow":
			var n := server_stow(s)
			if s:
				Survival._tell(s, "Stowed %d" % n if n > 0 else "Nothing to stow (or you're away from home)")
		"take":
			if s and args.size() >= 2:
				server_take_for(s, String(args[0]), int(args[1]))
		"wait":
			if s and args.size() >= 1:
				return Survival.server_wait(s, String(args[0]))
		"vote":
			if s and args.size() >= 2:
				return Council.server_choose(int(args[0]), String(args[1]), Survival.profile_of(s))
	return ""
