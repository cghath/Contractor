class_name Trees
extends RefCounted
## Trees as a resource (docs/survival_nature.md; call 106; survival_building.md's cut wood): every
## ZoneScatter tree has a species (species_of: a conifer is a pine; the rest oak, birch, apple or
## hedgerow by the data's shares, fixed by where it stands). Felling (server_fell) takes an axe (a
## hatchet HATCHET_X as long) the species' fell_s (oak slow, pine quick), every chop a noise the dead
## hear (Survival.server_noise, the species' noise_m) and the zone's pressure with it; down, it leaves
## a stump (ZoneScatter draws it: redraw_at) and gives planks and green firewood (its state's cut
## day: seasoned after SEASON_DAYS) into the kit or at his feet. The settlement's cut wood
## (WorkOrders) fells the trees near it (settlement_cut) into the stores. Woods regrow: a stump past
## REGROW_DAYS (two seasons) is a tree again (server_regrow). An apple tree in autumn gives apples
## (server_pick_fruit). The felled ones are kept by zone in Survival.state()["nature"]["felled"].
## Every number here is Proposed.

const REACH_M := 3.5
const HATCHET_X := 1.8
const CHOP_S := 2.0
const CHOP_LOUD := 0.35
const SEASON_DAYS := 5
const REGROW_DAYS := 20
const SETTLE_REACH_X := 2.5
const FRUIT_DAYS := 6

## Host: felling under way: tree index -> seconds worked.
static var progress := {}


static func data() -> Dictionary:
	return Nature.flora().get("trees", {})


static func spec(sp: String) -> Dictionary:
	return data().get(sp, {})


## The species of scatter tree `item` ("pine" for a conifer; else by the shares, fixed by its spot).
static func species_of(item: Dictionary) -> String:
	if bool(item.get("conifer", false)):
		return "pine"
	var p: Vector3 = item.pos
	var roll := float(posmod(hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))), 10000)) / 10000.0
	var total := 0.0
	for sp: String in data():
		total += float((data()[sp] as Dictionary).get("share", 0.0))
	var acc := 0.0
	for sp: String in data():
		acc += float((data()[sp] as Dictionary).get("share", 0.0)) / maxf(total, 0.001)
		if roll < acc:
			return sp
	return "oak"


## Seconds of a felling axe to fell `sp`.
static func fell_s(sp: String) -> float:
	return float(spec(sp).get("fell_s", 60.0))


static func felled_rec() -> Dictionary:
	var r := Nature.rec()
	if not r.get("felled") is Dictionary:
		r["felled"] = {}
	var all: Dictionary = r["felled"]
	var z := Nature.zone()
	if not all.get(z) is Dictionary:
		all[z] = {}
	return all[z]


static func is_felled(index: int) -> bool:
	return felled_rec().has(str(index))


static func _scatter(level: Node) -> ZoneScatter:
	var zl := level as ZoneLevel
	return zl.scatter if zl else null


## The tree's item (scatter index `index`), {} if it isn't one.
static func tree(level: Node, index: int) -> Dictionary:
	var sc := _scatter(level)
	if sc == null or index < 0 or index >= sc.items.size() or int(sc.items[index].kind) != ZoneScatter.Kind.TREE:
		return {}
	return sc.items[index]


## The nearest standing tree to `pos` within `r`: its scatter index, -1 none.
static func nearest(level: Node, pos: Vector3, r := REACH_M, standing := true) -> int:
	var sc := _scatter(level)
	if sc == null:
		return -1
	var best := -1
	var best_d := r
	var span := ceili(r / ZoneScatter.CELL_M)
	var c := sc._cell_of(pos.x, pos.z)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for i: int in sc._cells.get(c + Vector2i(dx, dz), []):
				var item: Dictionary = sc.items[i]
				if int(item.kind) != ZoneScatter.Kind.TREE or (standing and item.has("felled")):
					continue
				var d := Vector2((item.pos as Vector3).x - pos.x, (item.pos as Vector3).z - pos.z).length()
				if d <= best_d:
					best_d = d
					best = i
	return best


static func _tool_x(s: Soldier) -> float:
	if Wildlife.carries(s, "axe"):
		return WeaponCondition.tool_mult(s, "axe")  # a worn axe fells slower (call 120)
	if Wildlife.carries(s, "hatchet"):
		return HATCHET_X * WeaponCondition.tool_mult(s, "hatchet")
	return 0.0


## Host: `s` chops `seconds` at tree `index`: the noise of each CHOP_S, and when the species' time
## is done it falls (planks, firewood, a stump). {"why": "" or why not, "done", "left_s", "sp"}.
static func server_fell(s: Soldier, index: int, seconds: float) -> Dictionary:
	var level := CompoundLevel.current(s)
	var item := tree(level, index)
	if item.is_empty() or item.has("felled"):
		return {"why": "No tree there", "done": false}
	var p: Vector3 = item.pos
	if Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length() > REACH_M:
		return {"why": "Too far", "done": false}
	var x := _tool_x(s)
	if x <= 0.0:
		return {"why": "You need an axe or a hatchet", "done": false}
	var sp := species_of(item)
	var d := spec(sp)
	var before := float(progress.get(index, 0.0))
	var after := before + seconds / x
	progress[index] = after
	WeaponCondition.on_chop(s, "axe" if Wildlife.carries(s, "axe") else "hatchet", seconds)  # the edge wears (call 120)
	var chops := maxi(1, floori(after / CHOP_S) - floori(before / CHOP_S))
	if chops > 0:
		Survival.server_noise(s, p, float(d.get("noise_m", 40.0)), CHOP_LOUD)
	var need := fell_s(sp)
	if after < need:
		return {"why": "", "done": false, "left_s": (need - after) * x, "sp": sp}
	progress.erase(index)
	_fall(level, index, sp)
	Wildlife._give(s, &"planks", int(d.get("planks", 0)))
	Wildlife._give(s, &"firewood", int(d.get("firewood", 0)), {"cut_day": Survival.day()})
	Rpg.xp(s, "building", 5.0)
	Survival._tell(s, "The %s comes down." % String(d.get("name", sp)))
	return {"why": "", "done": true, "left_s": 0.0, "sp": sp}


## Host: tree `index` down: a stump on every peer, kept in the save.
static func _fall(level: Node, index: int, sp: String) -> void:
	felled_rec()[str(index)] = {"sp": sp, "day": Survival.day()}
	client_set(level, index, true)
	var nat: Nature = level.get_node_or_null(Nature.NODE_NAME) as Nature if level else null
	if nat:
		nat.server_tree(index, true)


## Host (WorkOrders' cut wood): the settlers cut `planks` planks: the trees near the settlement
## fall for them (their planks on a running tally, firewood into the stores). Returns the trees felled.
static func settlement_cut(st: Settlement, planks: int) -> int:
	if st == null or not st.hosted() or planks <= 0:
		return 0
	var d := Settlement.data()
	var tally := int(d.get("wood_tally", 0))
	var felled := 0
	while tally < planks and felled < 4:
		var i := nearest(st.level, Settlement.pos(), Settlement.radius() * SETTLE_REACH_X)
		if i < 0:
			break
		var sp := species_of(tree(st.level, i))
		_fall(st.level, i, sp)
		Survival.server_noise(st, (tree(st.level, i).pos as Vector3), float(spec(sp).get("noise_m", 40.0)), CHOP_LOUD)
		tally += maxi(int(spec(sp).get("planks", 0)), 1)
		var fw := int(spec(sp).get("firewood", 0))
		if fw > 0:
			st.server_put("firewood", fw, {"cut_day": Survival.day()})
		felled += 1
	d["wood_tally"] = maxi(tally - planks, 0)
	return felled


## Host, every world day: stumps past REGROW_DAYS grow back. Returns how many.
static func server_regrow(level: Node) -> int:
	var rec := felled_rec()
	var n := 0
	for key: String in rec.keys():
		if Survival.day() - int((rec[key] as Dictionary).get("day", 0)) >= REGROW_DAYS:
			rec.erase(key)
			client_set(level, int(key), false)
			var nat: Nature = level.get_node_or_null(Nature.NODE_NAME) as Nature if level else null
			if nat:
				nat.server_tree(int(key), false)
			n += 1
	return n


## Host: the zone's felled trees put on its scatter (the zone comes up).
static func server_apply(level: Node) -> void:
	client_felled(level, felled_list())


static func felled_list() -> Array:
	var out: Array = []
	for key: String in felled_rec():
		out.append(int(key))
	return out


## Every peer: these trees down (and every other one standing).
static func client_felled(level: Node, list: Array) -> void:
	var sc := _scatter(level)
	if sc == null:
		return
	for i in sc.items.size():
		var item: Dictionary = sc.items[i]
		if item.has("felled") and not i in list:
			client_set(level, i, false)
	for i: int in list:
		client_set(level, i, true)


## Every peer: tree `index` felled (a stump) or standing.
static func client_set(level: Node, index: int, felled: bool) -> void:
	var sc := _scatter(level)
	if sc == null or index < 0 or index >= sc.items.size():
		return
	var item: Dictionary = sc.items[index]
	if felled == item.has("felled"):
		return
	if felled:
		item["felled"] = true
	else:
		item.erase("felled")
	sc.redraw_at(item.pos)


## Whether firewood with `state` has seasoned (SEASON_DAYS since it was cut).
static func seasoned(state: Dictionary) -> bool:
	return not state.has("cut_day") or Survival.day() - int(state.cut_day) >= SEASON_DAYS


## Host: `s` picks the apples off apple tree `index` in autumn. Returns how many.
static func server_pick_fruit(s: Soldier, index: int) -> int:
	var level := CompoundLevel.current(s)
	var item := tree(level, index)
	if item.is_empty() or item.has("felled") or species_of(item) != "apple":
		return 0
	var d := spec("apple")
	if not Seasons.current() in (d.get("fruit_seasons", []) as Array):
		return 0
	var picked: Dictionary = Nature.rec().get_or_add("fruit", {})
	var key := "%s:%d" % [Nature.zone(), index]
	if Survival.day() - int(picked.get(key, -999)) < FRUIT_DAYS:
		return 0
	picked[key] = Survival.day()
	var r: Array = d.get("fruit_n", [3, 6])
	var n := randi_range(int(r[0]), int(r[1]))
	Wildlife._give(s, &"apples", n)
	return n
