class_name Fieldwork
extends RefCounted
## The player's hands on nature in Contractor: Fallen (docs/survival_hands.md; calls 42, 100-107):
## the contextual menu's entries (ContextMenu.classify -> classify, ContextResolver -> options; the
## one key does the first) for what he looks at within reach, carried out on the host (the
## Survival._server_fieldwork request -> server_request) as timed jobs with the hands busy (Wear.timed):
## - a **carcass**: "Butcher the deer" (a blade; butcher_s by species from the fauna data, fieldcraft
##   faster and a better yield; the knife work is heard close by): meat, hide, bone and fat;
## - a **tree**: "Fell the oak" (an axe or a hatchet: Trees.server_fell a chop at a time, each heard),
##   "Gather firewood" (no tool, slow, deadfall: dry wood), "Pick apples" on an apple tree;
## - a **plant**: "Forage <name>" when his eye (fieldcraft, a field guide) tells it from its look-alike,
##   else "Forage (unknown plant)" (Foraging.server_forage after a short pick);
## - **water**: "Fish" (a rod, a net or a hand line: a cast of CAST_S whose bite chance is the nature
##   lane's fish table by water body and season over CAST_H hours), "Cut ice" when it's frozen;
## - **woods or an edge** (a tree near the ground he looks at): "Set a snare", "Check the snare",
##   "Gather firewood".
## Built pieces (BuildPiece's menu -> piece_menu / server_piece_act): the fish trap (catches by the
## world hour by the water it stands in), the smoker and the drying rack (recipe stations: stations_near),
## the clinic's bed and cabinet (Clinic). Every number here is Proposed.

const KINDS: Array[String] = ["carcass", "tree", "plant", "water", "woods"]
## How far from him the spot he looks at may be (the water further: a bank).
const REACH_M := 4.0
const WATER_LOOK_M := 14.0
## A tree within this of the ground looked at: woods or an edge (snares, deadfall).
const WOODS_M := 12.0
const TREE_PICK_M := 2.5
const PLANT_PICK_M := 1.6
## Butchering: fieldcraft takes LEVEL_X a level off the time (to MIN_X), and adds YIELD_X a level
## to the meat; the knife work is heard NOISE_M.
const BUTCHER_LEVEL_X := 0.06
const BUTCHER_MIN_X := 0.5
const YIELD_LEVEL_X := 0.1
const BUTCHER_NOISE_M := 15.0
const BUTCHER_LOUD := 0.15
const FORAGE_S := 4.0
## Fishing: a cast of CAST_S real seconds stands for CAST_H hours of the fish table; a hand line
## fishes LINE_X a rod; through the ice ICE_X.
const CAST_S := 20.0
const CAST_H := 0.5
const LINE_X := 0.6
const ICE_X := 0.3
## Deadfall: FIREWOOD_S, FIREWOOD_N dry firewood, FIREWOOD_PER_DAY gathers a day in a FIREWOOD_CELL_M square.
const FIREWOOD_S := 30.0
const FIREWOOD_N: Array[int] = [1, 2]
const FIREWOOD_PER_DAY := 2
const FIREWOOD_CELL_M := 25.0
## Cutting ice in winter: ICE_S for ICE_N blocks.
const ICE_S := 15.0
const ICE_N := 2
## A fish trap: TRAP_X a rod's catch an hour by the water within TRAP_WATER_M, up to TRAP_MAX.
const TRAP_X := 0.3
const TRAP_MAX := 4
const TRAP_WATER_M := 8.0
## A smoker, a rack or a clinic piece counts within this.
const STATION_M := 3.0
## The pieces this file adds (BuildPieces.PIECES) and the station each is.
const STATIONS := {"smoker": "smoker", "drying_rack": "rack"}

## Tests: a roll to use instead of randf() (-1: roll for real).
static var force_roll := -1.0
static var _trap_h := -1


static func _roll() -> float:
	return force_roll if force_roll >= 0.0 else randf()


static func _level(s: Soldier) -> int:
	return Rpg.level(s, "fieldcraft") if s else 0


# --- What he looks at (every peer) ----------------------------------------------------------------

## The contextual menu's ctx for the ground at `at` that `me` looks at, in a survival zone: a carcass,
## a tree, a plant, water or the woods ({} for none of them: the menu's own ground).
static func classify(me: Soldier, at: Vector3) -> Dictionary:
	if me == null or not at.is_finite():
		return {}
	var lvl := SurvivalLevel.of(me)
	if lvl == null:
		return {}
	var d := Vector2(at.x - me.global_position.x, at.z - me.global_position.z).length()
	if d <= REACH_M:
		var c := carcass_seen(lvl, at, Wildlife.BUTCHER_M)
		if not c.is_empty():
			return {"kind": "carcass", "sp": String(c.sp), "name": String(Wildlife.spec(String(c.sp)).get("name", c.sp))}
		var t := Trees.nearest(lvl, at, TREE_PICK_M)
		if t >= 0:
			var sp := Trees.species_of(lvl.scatter.items[t])
			return {"kind": "tree", "index": t, "sp": sp, "name": String(Trees.spec(sp).get("name", sp))}
		var best := {}
		var best_d := PLANT_PICK_M
		for spot: Dictionary in Foraging.spots_near(lvl, at, PLANT_PICK_M):
			var pd := (spot.pos as Vector3).distance_to(at)
			if pd <= best_d:
				best_d = pd
				best = spot
		if not best.is_empty():
			return {"kind": "plant", "index": int(best.index), "plant": String(best.plant), "label": forage_label(me, String(best.plant))}
	if d <= WATER_LOOK_M:
		var body := water_at(lvl, at)
		if body != "":
			return {"kind": "water", "body": body, "frozen": Seasons.water_frozen() and body != "coast"}
	if d <= REACH_M and Trees.nearest(lvl, at, WOODS_M, false) >= 0:
		return {"kind": "woods"}
	return {}


## The water right at `pos` ("" none): a ZoneWater body's kind or "coast" (the sea).
static func water_at(level: Node, pos: Vector3) -> String:
	var zl := level as ZoneLevel
	if zl == null or zl.terrain == null:
		return ""
	var t := zl.terrain
	if t.water:
		var bi := t.water._water_body_at(Vector2(pos.x, pos.z))
		if bi >= 0 and bi < t.water.bodies.size():
			return String((t.water.bodies[bi] as Dictionary).get("kind", "river"))
	if t.sea_side >= 0 and t.height_at(pos.x, pos.z) < t.sea_level - 0.3:
		return "coast"
	return ""


## A dead animal within `r` of `at` as this peer sees it ({"sp", "pos"}; {} none): the host's records,
## or the rows Nature last sent.
static func carcass_seen(level: Node, at: Vector3, r: float) -> Dictionary:
	var rows: Array = []
	var nat: Nature = level.get_node_or_null(Nature.NODE_NAME) as Nature if level else null
	if Survival.running:  # (the host keeps the records)
		rows = Wildlife.shown_rows()
	elif nat:
		rows = nat.shown
	var names: Array = (Nature.fauna().get("species", {}) as Dictionary).keys()
	var best := {}
	var best_d := r
	for row: Array in rows:
		if bool(row[5]):
			continue
		var p := Vector3(float(row[1]), float(row[2]), float(row[3]))
		var dd := Vector2(p.x - at.x, p.z - at.z).length()
		if dd <= best_d:
			best_d = dd
			best = {"sp": String(names[clampi(int(row[0]), 0, names.size() - 1)]), "pos": p}
	return best


## Whether `s` tells `plant` for what it is: his eye (Foraging.eye) at the plant's own "tell", or at the
## tell of a poison that looks like it (a novice can't tell berries from nightshade either way).
static func knows(s: Soldier, plant: String) -> bool:
	var need := int(Foraging.spec(plant).get("tell", 0))
	var item := String(Foraging.spec(plant).get("item", plant))
	for other: String in Foraging.data():
		if String((Foraging.data()[other] as Dictionary).get("looks_like", "")) == item:
			need = maxi(need, int((Foraging.data()[other] as Dictionary).get("tell", 0)))
	return Foraging.eye(s) >= need


## "Forage Wild Berries", or "Forage (unknown plant)" when he can't tell it apart.
static func forage_label(s: Soldier, plant: String) -> String:
	if not knows(s, plant):
		return "Forage (unknown plant)"
	var id := StringName(String(Foraging.spec(plant).get("item", plant)))
	var name := String(ItemDB.get_item(id).name) if ItemDB.has_item(id) else plant.replace("_", " ")
	return "Forage %s%s" % [name, " (poison)" if Foraging.spec(plant).has("poison") else ""]


## The contextual menu's options for `ctx` (classify's), the first the one key's.
static func options(ctx: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match String(ctx.get("kind", "")):
		"carcass":
			out.append(_o("butcher", "Butcher the %s" % String(ctx.get("name", "carcass"))))
		"tree":
			out.append(_o("fell", "Fell the %s" % String(ctx.get("name", "tree")), str(int(ctx.get("index", -1)))))
			out.append(_o("firewood", "Gather firewood"))
			if String(ctx.get("sp", "")) == "apple":
				out.append(_o("fruit", "Pick apples", str(int(ctx.get("index", -1)))))
		"plant":
			out.append(_o("forage", String(ctx.get("label", "Forage")), str(int(ctx.get("index", -1)))))
		"water":
			if bool(ctx.get("frozen", false)):
				out.append(_o("cut_ice", "Cut ice"))
				out.append(_o("fish", "Fish through the ice"))
			else:
				out.append(_o("fish", "Fish"))
		"wait":  # the ground's own (ContextResolver, call 136): waiting at a safe spot
			for mode: String in SurvivalSleep.WAIT_MODES:
				out.append(_o("wait", String(SurvivalSleep.WAIT_LABELS[mode]), mode))
		"woods":
			out.append(_o("set_snare", "Set a snare"))
			out.append(_o("check_snare", "Check the snare"))
			out.append(_o("firewood", "Gather firewood"))
	return out


static func _o(what: String, label: String, arg := "") -> Dictionary:
	return {"id": "fw_" + what, "label": label, "do": "fieldwork", "what": what, "arg": arg}


# --- The host's side ------------------------------------------------------------------------------

## Host: `s` asked for `what` (options' "what") with `arg` at `at`. "" when it started, else why not.
static func server_request(s: Soldier, what: String, arg: String, at: Vector3) -> String:
	if s == null or not s.vitals.is_up():
		return "Not now"
	if Soldier._now() < s._server_busy_until - 0.1:
		return "Busy"
	match what:
		"butcher":
			return server_butcher(s, Wildlife.carcass_near(at if at.is_finite() else s.global_position, Wildlife.BUTCHER_M + 1.0))
		"fell":
			return server_fell(s, int(arg))
		"fruit":
			var n := Trees.server_pick_fruit(s, int(arg))
			return "" if n > 0 else "No apples on it now"
		"firewood":
			return server_firewood(s)
		"forage":
			return server_forage(s, int(arg))
		"fish":
			return server_cast(s)
		"cut_ice":
			return server_cut_ice(s)
		"set_snare":
			return Wildlife.server_set_snare(s)
		"wait":
			return Survival.server_wait(s, arg if arg in SurvivalSleep.WAIT_MODES else "hour")
		"check_snare":
			var got := Wildlife.server_check_snare(s)
			return "No snare of yours here" if got == "?" else ""
	return "?"


## Seconds to butcher `sp` at fieldcraft `lvl`.
static func butcher_s(sp: String, lvl: int) -> float:
	var base := float(Wildlife.spec(sp).get("butcher_s", 30.0))
	return base * maxf(BUTCHER_MIN_X, 1.0 - BUTCHER_LEVEL_X * lvl)


## The meat's yield at fieldcraft `lvl`.
static func yield_x(lvl: int) -> float:
	return 1.0 + YIELD_LEVEL_X * lvl


## Host: `s` butchers carcass `a`: butcher_s with his hands busy (heard close by), then its yield
## (Wildlife.server_butcher). "" when it started, else why not. `instant`: now (tests).
static func server_butcher(s: Soldier, a: Dictionary, instant := false) -> String:
	var why := Wildlife.butcher_problem(s, a)
	if why != "":
		return why
	var lvl := _level(s)
	var p: Vector2 = a.pos
	Survival.server_noise(s, Vector3(p.x, float(a.get("y", s.global_position.y)), p.y), BUTCHER_NOISE_M, BUTCHER_LOUD)
	a["butchering"] = true
	var done := func() -> void:
		a.erase("butchering")
		var w := Wildlife.server_butcher(s, a, yield_x(lvl))
		if w != "":
			Survival._tell(s, w)
	Wear.timed(s, butcher_s(String(a.sp), lvl), "Butchering", done, instant)
	return ""


## Host: `s` fells tree `index`, a chop at a time (each heard: Trees.server_fell) until it's down, he
## walks off or something stops him. "" when he started, else why not. `instant`: all at once (tests).
static func server_fell(s: Soldier, index: int, instant := false) -> String:
	var level := CompoundLevel.current(s)
	var item := Trees.tree(level, index)
	if item.is_empty() or item.has("felled"):
		return "No tree there"
	var p: Vector3 = item.pos
	if Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length() > Trees.REACH_M:
		return "Get closer to the tree"
	if Trees._tool_x(s) <= 0.0:
		return "You need an axe or a hatchet"
	if instant:
		for i in 1000:
			var r := Trees.server_fell(s, index, Trees.CHOP_S)
			if String(r.get("why", "")) != "" or bool(r.get("done", false)):
				break
		return ""
	_chop(s, index)
	return ""


static func _chop(s: Soldier, index: int) -> void:
	if not is_instance_valid(s) or not s.vitals.is_up():
		return
	var r := Trees.server_fell(s, index, Trees.CHOP_S)
	if String(r.get("why", "")) != "":
		Survival._tell(s, String(r.why))
		return
	if bool(r.get("done", false)) or not s.is_inside_tree():
		return
	s.server_busy(Trees.CHOP_S, "Felling (%d s left)" % ceili(float(r.get("left_s", 0.0))))
	s.get_tree().create_timer(Trees.CHOP_S, false).timeout.connect(func() -> void: _chop(s, index))


static func _firewood_rec() -> Dictionary:
	var r := Nature.rec()
	if not r.get("deadfall") is Dictionary:
		r["deadfall"] = {}
	return r["deadfall"]


## Host: `s` gathers deadfall where he stands (in the woods, no tool): FIREWOOD_S, then dry firewood.
static func server_firewood(s: Soldier, instant := false) -> String:
	var level := CompoundLevel.current(s)
	if Trees.nearest(level, s.global_position, WOODS_M, false) < 0:
		return "No deadfall here: find some trees"
	var p := s.global_position
	var key := "%s:%d:%d:%d" % [Nature.zone(), floori(p.x / FIREWOOD_CELL_M), floori(p.z / FIREWOOD_CELL_M), Survival.day()]
	var rec := _firewood_rec()
	if int(rec.get(key, 0)) >= FIREWOOD_PER_DAY:
		return "You've picked this patch clean today"
	rec[key] = int(rec.get(key, 0)) + 1
	var done := func() -> void:
		var n := randi_range(FIREWOOD_N[0], FIREWOOD_N[1])
		Wildlife._give(s, &"firewood", n)
		Rpg.xp(s, "fieldcraft", 1.0)
		Survival._tell(s, "%d armfuls of dry deadfall." % n)
	Wear.timed(s, FIREWOOD_S, "Gathering deadfall", done, instant)
	return ""


## Host: `s` forages scatter spot `index` (a short pick, then Foraging.server_forage).
static func server_forage(s: Soldier, index: int, instant := false) -> String:
	var level := CompoundLevel.current(s)
	var zl := level as ZoneLevel
	if zl == null or zl.scatter == null or index < 0 or index >= zl.scatter.items.size():
		return "Nothing to pick"
	var item: Dictionary = zl.scatter.items[index]
	var plant := Foraging.plant_of(item)
	if plant == "":
		return "Nothing worth picking here"
	if not Foraging.is_ready(index, plant):
		return "Nothing on it now" if Foraging.in_season(plant, Seasons.current()) else "Not the season for it"
	var done := func() -> void:
		var w := Foraging.server_forage(s, index)
		if w != "":
			Survival._tell(s, w)
	Wear.timed(s, FORAGE_S, "Foraging", done, instant)
	return ""


## The fishing gear `s` has: a net, a rod (1), a hand line (LINE_X); 0 none.
static func gear(s: Soldier) -> float:
	var g := Migration._gear(s)
	if g <= 0.0 and Wildlife.carries(s, "hand_line"):
		g = LINE_X
	return g


## The chance a cast at `body` in `season` gets a bite, with gear `g` at fieldcraft `lvl`
## (`frozen`: through the ice).
static func bite_chance(body: String, season: String, g: float, lvl: int, frozen := false) -> float:
	var rate := Migration.fish_rate(body, season) * g * (1.0 + Migration.FIELDCRAFT_X * lvl)
	if frozen and body != "coast":
		rate *= ICE_X
	return 1.0 - exp(-rate * CAST_H)


## Host: `s` casts at the water by him: CAST_S, then a bite or nothing (land). "" when it started.
static func server_cast(s: Soldier, instant := false, body := "") -> String:
	var g := gear(s)
	if g <= 0.0:
		return "You need a rod, a net or a hand line"
	if body == "":
		body = Migration.water_body_at(CompoundLevel.current(s), s.global_position)
	if body == "":
		return "There's no water to fish here"
	var done := func() -> void:
		land(s, body, g)
	Wear.timed(s, CAST_S, "Fishing", done, instant)
	return ""


## Host: the end of a cast at `body` with gear `g`: a fish into his kit on a bite. Returns 1 or 0.
static func land(s: Soldier, body: String, g: float) -> int:
	var p := bite_chance(body, Seasons.current(), g, _level(s), Seasons.water_frozen())
	if _roll() >= p:
		Survival._tell(s, "Nothing biting.")
		return 0
	var kinds := Migration.fish_species(body)
	var what := String(kinds[randi() % kinds.size()]) if not kinds.is_empty() else "fish"
	Wildlife._give(s, &"raw_fish", 1)
	Rpg.xp(s, "fieldcraft", 2.0)
	Survival._tell(s, "A %s on the line." % what)
	return 1


## Host: `s` cuts ice from frozen water by him (winter): ICE_S, ICE_N blocks.
static func server_cut_ice(s: Soldier, instant := false) -> String:
	var body := Migration.water_body_at(CompoundLevel.current(s), s.global_position)
	if body == "" or body == "coast" or not Seasons.water_frozen():
		return "There's no ice to cut here"
	var done := func() -> void:
		Wildlife._give(s, &"ice_block", ICE_N)
		Survival._tell(s, "%d blocks of ice." % ICE_N)
	Wear.timed(s, ICE_S, "Cutting ice", done, instant)
	return ""


# --- The pieces (Builder) ---------------------------------------------------------------------------

## The settlement's counts of this lane's pieces (Settlement.refresh: `counts` by piece kind).
static func refresh_counts(d: Dictionary, counts: Dictionary) -> void:
	for pair: Array in [["smokers", "smoker"], ["racks", "drying_rack"], ["cold_stores", "cold_store"], ["ice_boxes", "ice_box"],
			["fish_traps", "fish_trap"], ["clinic_beds", "clinic_bed"], ["clinic_cabinets", "clinic_cabinet"], ["clinic_lamps", "clinic_lamp"], ["fridges", "fridge"]]:
		d[String(pair[0])] = int(counts.get(String(pair[1]), 0))


## The stations (Crafting) `s` stands at from the built pieces: "smoker", "rack".
static func stations_near(s: Soldier) -> Array:
	var out: Array = []
	if s == null or not s.is_inside_tree():
		return out
	for node in s.get_tree().get_nodes_in_group(InteractionMenu.INTERACTABLES):
		var bp := node as BuildPiece
		if bp == null or bp.rec.is_empty() or float(bp.rec.get("prog", 0.0)) < 1.0 or bp.global_position.distance_to(s.global_position) > STATION_M:
			continue
		var st := String(STATIONS.get(String(bp.rec.get("k", "")), ""))
		if st != "" and not st in out:
			out.append(st)
	return out


## The built piece `rec`'s own entries for BuildPiece's menu: [[id, label, action], ...].
static func piece_menu(rec: Dictionary) -> Array:
	match String(rec.get("k", "")):
		"fish_trap":
			return [[&"fw_trap", "Empty the fish trap", "fish_trap"]]
		"smoker":
			return [[&"fw_smoke", "Smoke the meat and fish you carry", "smoke"]]
		"drying_rack":
			return [[&"fw_dry", "Hang meat and fish to dry", "dry"]]
		"clinic_bed":
			return [[&"fw_rest", "Rest in the bed (in care)", "clinic_rest"], [&"fw_quarantine", "Quarantine the bitten here", "quarantine"]]
		"clinic_cabinet":
			return [[&"fw_stock", "Stock the cabinet with your meds", "clinic_stock"]]
	return []


## Host: `s` did `what` on piece `id` (Builder's piece_act). "?" when it isn't one of these.
static func server_piece_act(b: Builder, s: Soldier, id: int, what: String) -> String:
	var rec: Dictionary = b.pieces.get(id, {})
	match what:
		"fish_trap":
			var n := int(rec.get("fish", 0))
			if n <= 0:
				return "Nothing in it yet"
			rec["fish"] = 0
			Wildlife._give(s, &"raw_fish", n)
			Survival._tell(s, "%d fish in the trap." % n)
			return ""
		"smoke":
			for r: String in ["smoker_meat", "smoker_fish"]:
				if Crafting.problem(s, r) == "":
					return Crafting.server_craft(s, r)
			return "You need three raw meat or fish and a piece of firewood"
		"dry":
			for r: String in ["dry_meat", "dry_fish"]:
				if Crafting.problem(s, r) == "":
					return Crafting.server_craft(s, r)
			return "You need two raw meat or fish"
		"clinic_rest":
			return Survival.server_sleep(s, 4.0, "bed")
		"quarantine":
			var n := Clinic.server_quarantine_bitten()
			return "" if n > 0 else "No one bitten to put here"
		"clinic_stock":
			var n := Clinic.server_stock(s)
			Survival._tell(s, "%d into the cabinet." % n if n > 0 else "You carry no meds to stock it with")
			return ""
	return "?"


## Host: `hours` world hours of the fish traps in `level` (Builder's pieces): each by the water it stands in.
static func server_traps_hours(level: Node, hours: float) -> int:
	var b: Builder = Builder.find(level) if level else null
	if b == null or hours <= 0.0:
		return 0
	var caught := 0
	for id: int in b.pieces:
		var rec: Dictionary = b.pieces[id]
		if String(rec.get("k", "")) != "fish_trap" or not b.is_piece_built(id) or int(rec.get("fish", 0)) >= TRAP_MAX:
			continue
		var body := String(rec.get("water", ""))
		if body == "":
			body = Migration.water_body_at(level, b.piece_pos(id))
			rec["water"] = body if body != "" else "none"
		if body == "none" or body == "":
			continue
		var chance := 1.0 - exp(-Migration.fish_rate(body, Seasons.current()) * TRAP_X * hours * (ICE_X if Seasons.water_frozen() and body != "coast" else 1.0))
		if _roll() < chance:
			rec["fish"] = int(rec.get("fish", 0)) + 1
			caught += 1
	return caught


# --- The tick (Survival.server_tick_survivors) --------------------------------------------------------

## Host: `dt` real seconds: the players' food (Spoilage), the fish traps by the world hour.
static func server_tick(level: Node, players: Array, dt: float) -> void:
	Spoilage.server_tick(players, dt)
	var h := floori(Moods.now_h())
	if _trap_h >= 0 and h > _trap_h and h - _trap_h <= 12:
		server_traps_hours(level, float(h - _trap_h))
	_trap_h = h
