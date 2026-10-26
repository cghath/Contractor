class_name Gunsmith
extends RefCounted
## Gunsmithing, the top of crafting in Contractor: Fallen (call 85; docs/survival_bonds.md,
## survival_rpg.md section 5): a gunsmith bench (build piece "gun_bench") is the station for the
## bench recipes (data/survival_recipes.json station "gun_bench": spare parts, the oil-filter
## suppressor, hand-loaded ammunition with a reloading press, improvised guns) and for its own work:
## strip a broken gun for gun parts (firearms STRIP_LEVEL), rebuild a broken gun from parts
## (REBUILD_LEVEL), zero the sights. A gun made or rebuilt starts at a condition by the smith's
## level over the work's (quality). Improvised guns (tag "improvised": the wear lane wears them
## three times as fast) misfire beyond jams (the round is lost) more as they wear, and a worn-out
## one may blow up in the hands (wounds to the forearms through Body's hands, the gun gone). The
## oil-filter suppressor wears out in CAN_SHOTS shots. The settlement's gunsmith work order: with a
## bench and an armoury rack ("gun_rack") built, a settler with firearms STRIP_LEVEL+ works the
## guns in the settlement's stock overnight. Static, host side; every number is Proposed.

const BENCH := "gun_bench"
const RACK := "gun_rack"
const BENCH_M := 3.0
const STRIP_LEVEL := 7
const REBUILD_LEVEL := 8
const BUILD_LEVEL := 9
const PARTS := &"gun_parts"
const SPARES := &"weapon_parts"
## A made or rebuilt gun's condition: QUALITY_BASE at the work's own level, QUALITY_PER a level
## over it, between QUALITY_MIN and 100.
const QUALITY_BASE := 55.0
const QUALITY_PER := 15.0
const QUALITY_MIN := 30.0
## An improvised gun's misfire a shot: MISFIRE_BASE as new, + MISFIRE_LOW x (wear fraction)^2;
## at 0% BLOW_CHANCE a shot it blows (BLOW_DAMAGE and a wound on each forearm).
const MISFIRE_BASE := 0.02
const MISFIRE_LOW := 0.3
const BLOW_CHANCE := 0.25
const BLOW_DAMAGE := 12.0
const CAN_SHOTS := 60
const STRIP_S := 20.0
const REBUILD_S := 60.0
const ZERO_S := 15.0
## The work order: at ORDER_HOUR (the morning: worked overnight), up to ORDER_GUNS guns.
const ORDER := "gunsmith"
const ORDER_HOUR := 6
const ORDER_GUNS := 2
## Tests: a bench at hand wherever he stands.
static var force_bench := false


# --- The bench ---------------------------------------------------------------------------------

## The built gun benches near `from`'s level (their middles).
static func benches(from: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var b := Builder.find(from)
	if b == null:
		return out
	for id: int in b.pieces:
		if String((b.pieces[id] as Dictionary).get("k", "")) == BENCH and b.is_piece_built(id):
			out.append(b.piece_pos(id))
	return out


static func bench_near(from: Node, at: Vector3) -> bool:
	for p: Vector3 in benches(from):
		if Vector2(p.x, p.z).distance_to(Vector2(at.x, at.z)) <= BENCH_M:
			return true
	return false


## Whether `s` stands at a gun bench.
static func near_bench(s: Soldier) -> bool:
	return force_bench or (s != null and bench_near(s, s.global_position))


## Gun parts a gun strips to (and takes to rebuild): 1 a sidearm, 2 a long gun, 3 a heavy one.
static func parts_for(item: ItemData) -> int:
	if item == null:
		return 0
	if item.slot == &"sidearm":
		return 1
	return 3 if item.mass_kg > 4.5 else 2


## The condition a gun starts at made by a smith of `level` on work of `needed`.
static func quality(level: int, needed: int) -> float:
	return clampf(QUALITY_BASE + QUALITY_PER * float(level - needed), QUALITY_MIN, 100.0)


## Crafting._finish: the made item's state from recipe `r` (a gun's quality by `s`'s level, empty;
## hand-loaded rounds).
static func crafted_state(s: Soldier, r: Dictionary, state: Dictionary) -> Dictionary:
	if bool(r.get("reloaded", false)):
		state.merge(AmmoCondition.reloaded_state(), true)
	if bool(r.get("quality", false)):
		var out: Array = r.get("output", [])
		var item: ItemData = ItemDB.get_item(StringName(String(out[0]))) if not out.is_empty() else null
		if item and int(item.stats.get("tube", 0)) > 0:
			state[Shotguns.TUBE_KEY] = []
		state["rounds"] = 0
		state[Wear.KEY] = quality(Rpg.level(s, String(r.get("line", "firearms"))) if Rpg.active(s) else int(r.get("level", 0)), int(r.get("level", 0)))
	return state


## The firearms level on a person's record (a settler: their skills).
static func rec_level(rec: Dictionary) -> int:
	var sk: Variant = rec.get("skills", {})
	return int((sk as Dictionary).get("firearms", 0)) if sk is Dictionary else 0


## The skill line's words for the character screen.
static func tier_line(level: int) -> String:
	if level >= BUILD_LEVEL:
		return "Gunsmith: strip, rebuild and build (a crude SMG at %d)" % BUILD_LEVEL
	if level >= REBUILD_LEVEL:
		return "Gunsmith: strip and rebuild guns at a gun bench (build a crude SMG at %d)" % BUILD_LEVEL
	if level >= STRIP_LEVEL:
		return "Gunsmith: strip guns, spares, pipe guns, hand-loads (rebuild at %d)" % REBUILD_LEVEL
	return "Gunsmith: from firearms %d at a gun bench" % STRIP_LEVEL


# --- Improvised guns firing (WeaponCondition) ---------------------------------------------------------

## The misfire chance of an improvised gun at condition `c`.
static func misfire_chance(c: float) -> float:
	var t := clampf((100.0 - c) / 100.0, 0.0, 1.0)
	return clampf(MISFIRE_BASE + MISFIRE_LOW * t * t, 0.0, 0.9)


static func _has_round(s: Soldier, slot: StringName, weapon: ItemData) -> bool:
	if Shotguns.is_shotgun(weapon):
		return not Shotguns.list_of(weapon, s.inventory.state_of(slot)).is_empty()
	return s.inventory.rounds_in(slot) > 0


## Host (WeaponCondition.server_blocked), an improvised gun's shot: at 0% it may blow; otherwise a
## misfire (the round lost). True when it doesn't fire.
static func server_improvised(s: Soldier, slot: StringName, weapon: ItemData, st: Dictionary) -> bool:
	if not _has_round(s, slot, weapon):
		return false
	var c := Wear.cond(st)
	var r := Wear.roll()
	if c <= 0.0 and r < BLOW_CHANCE:
		server_blow(s, slot, weapon)
		return true
	if r < misfire_chance(c):
		if Shotguns.is_shotgun(weapon):
			Shotguns.server_take_shell(s.inventory, slot)
		else:
			s.inventory.consume_round(slot)
		s._server_next_shot = Soldier._now() + 0.4
		Wear.tell(s, "Misfire: that round's wasted")
		return true
	return false


## Host: the improvised gun in `slot` blows apart in `s`'s hands: the gun gone, his forearms cut
## and burnt (Body's hands), a hit of trauma.
static func server_blow(s: Soldier, slot: StringName, weapon: ItemData) -> void:
	s.inventory.unequip(slot)
	s.inventory._commit()
	for part: StringName in Body.FROST_PARTS["hands"]:
		var w := s.vitals.server_add_wound(part, "graze", 0.0)
		w["name"] = &"powder burns"
	s.vitals.server_damage(BLOW_DAMAGE)
	s.set_meta(&"gun_blew", Soldier._now())
	Wear.tell(s, "The %s blew apart in your hands" % (weapon.name if weapon else "gun"))
	if Survival.running and not s.is_ai():
		Survival._journal_line("%s's %s blew apart in their hands." % [Survival.survivor_name(s), (weapon.name if weapon else "gun").to_lower()])


## Host (WeaponCondition.on_shot): an improvised suppressor on the gun wears out in CAN_SHOTS.
static func on_shot(s: Soldier, weapon: ItemData, st: Dictionary) -> void:
	var can := Suppressors.mounted(weapon, st)
	if can == null or not can.tags.has("improvised"):
		return
	st["can_shots"] = int(st.get("can_shots", 0)) + 1
	if int(st.can_shots) >= CAN_SHOTS:
		st.erase(Suppressors.STATE_KEY)
		st.erase("can_shots")
		Wear.tell(s, "The %s is shot through" % can.name.to_lower())


# --- The bench's work (host) -----------------------------------------------------------------------------

## The bench's menu entries for BuildPiece (via Infrastructure.piece_menu): [[id, label, what]].
static func bench_menu(rec: Dictionary) -> Array:
	if String(rec.get("k", "")) != BENCH:
		return []
	var out: Array = [[&"gs_strip", "Strip a broken gun for parts", "gs_strip"], [&"gs_rebuild", "Rebuild the broken gun", "gs_rebuild"],
		[&"gs_zero", "Zero the sights", "gs_zero"]]
	for id: String in Crafting.recipes():
		var r: Dictionary = Crafting.recipe(id)
		if String(r.get("station", "")) == BENCH:
			out.append([StringName("gs_craft_" + id), "Make: %s" % String(r.get("name", id)), "gs_craft:" + id])
	return out


## Builder's piece_act (via Infrastructure.server_piece_act): "?" when it isn't the bench's.
static func server_bench_act(_b: Builder, s: Soldier, _id: int, what: String) -> String:
	if not what.begins_with("gs_"):
		return "?"
	if what.begins_with("gs_craft:"):
		return Crafting.server_craft(s, what.trim_prefix("gs_craft:"))
	match what:
		"gs_strip":
			return server_strip(s)
		"gs_rebuild":
			return server_rebuild(s)
		"gs_zero":
			return server_zero(s)
	return "?"


## A broken gun `s` carries to strip: [where, slot or container, index] (["", ...] none). In a
## weapon slot first, then stowed.
static func _broken(s: Soldier) -> Array:
	var slot := WeaponCondition.broken_gun(s)
	if slot != &"":
		return ["slot", slot, -1]
	for c: StringName in s.inventory.search_containers():
		var list: Array = s.inventory.containers.get(c, [])
		for i in list.size():
			var e: Dictionary = list[i]
			if WeaponCondition.is_gun(ItemDB.get_item(StringName(String(e.id)))) and WeaponCondition.is_broken(e.get("state", {})):
				return ["stowed", c, i]
	return ["", &"", -1]


## Host: `s` strips a broken gun at the bench (firearms STRIP_LEVEL): STRIP_S, then the gun's gone
## and its gun parts (parts_for) are in his kit. "" when it started, else why not.
static func server_strip(s: Soldier, instant := false) -> String:
	var why := _bench_problem(s, STRIP_LEVEL)
	var at := _broken(s)
	if why == "" and String(at[0]) == "":
		why = "No broken gun to strip"
	if why != "":
		Wear.tell(s, why)
		return why
	var done := func() -> void:
		var now := _broken(s)
		if String(now[0]) == "":
			return
		var id := &""
		if String(now[0]) == "slot":
			id = StringName(String(s.inventory.unequip(now[1]).get("id", "")))
		else:
			id = StringName(String(s.inventory.remove_entry(now[1], int(now[2]), 1).get("id", "")))
		var n := parts_for(ItemDB.get_item(id))
		_give(s, PARTS, n)
		Rpg.xp(s, "firearms", 8.0, STRIP_LEVEL)
		Wear.tell(s, "Stripped: %d gun parts" % n)
	Wear.timed(s, STRIP_S, "Stripping the gun", done, instant)
	return ""


## Host: `s` rebuilds the broken gun in a weapon slot at the bench (firearms REBUILD_LEVEL) from
## parts_for gun parts and one spare parts kit: REBUILD_S, then it's at its quality.
static func server_rebuild(s: Soldier, instant := false) -> String:
	var why := _bench_problem(s, REBUILD_LEVEL)
	var slot := WeaponCondition.broken_gun(s)
	var gun: ItemData = ItemDB.get_item(StringName(s.inventory.slots.get(slot, &""))) if slot != &"" else null
	if why == "" and gun == null:
		why = "No broken gun in hand or slung to rebuild"
	if why == "" and s.inventory.count_of(PARTS) < parts_for(gun):
		why = "Needs %d gun parts" % parts_for(gun)
	if why == "" and s.inventory.count_of(SPARES) < 1:
		why = "Needs a weapon parts kit"
	if why != "":
		Wear.tell(s, why)
		return why
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev or s.inventory.count_of(PARTS) < parts_for(gun) or not s.inventory.remove_one(SPARES):
			Wear.tell(s, "Something's missing")
			return
		for i in parts_for(gun):
			s.inventory.remove_one(PARTS)
		var st := Wear.slot_state_rw(s.inventory, slot)
		Wear.set_cond(st, maxf(Wear.cond(st), quality(Rpg.level(s, "firearms") if Rpg.active(s) else REBUILD_LEVEL, REBUILD_LEVEL)))
		st.erase("jammed")
		s.inventory._commit()
		Rpg.xp(s, "firearms", 15.0, REBUILD_LEVEL)
		Wear.tell(s, "Rebuilt: %d%%" % roundi(Wear.cond(st)))
	Wear.timed(s, REBUILD_S, "Rebuilding the gun", done, instant)
	return ""


## Host: `s` zeroes the sights of the gun in his hands at the bench (firearms STRIP_LEVEL): the
## gun's state carries the day it was zeroed (the aim effect: later).
static func server_zero(s: Soldier, instant := false) -> String:
	var why := _bench_problem(s, STRIP_LEVEL)
	var slot := s.active_slot
	var gun := s.active_weapon()
	if why == "" and not WeaponCondition.is_gun(gun):
		why = "Hold the gun to zero"
	if why != "":
		Wear.tell(s, why)
		return why
	var rev := s.inventory.slot_revision(slot)
	var done := func() -> void:
		if s.inventory.slot_revision(slot) != rev:
			return
		var st := Wear.slot_state_rw(s.inventory, slot)
		st["zeroed"] = Survival.day()
		s.inventory._commit()
		Rpg.xp(s, "firearms", 4.0, STRIP_LEVEL)
		Wear.tell(s, "Zeroed")
	Wear.timed(s, ZERO_S, "Zeroing the sights", done, instant)
	return ""


static func _bench_problem(s: Soldier, level: int) -> String:
	if not near_bench(s):
		return "At a gun bench"
	if not Rpg.gate(s, "firearms", level):
		return "Needs firearms %d" % level
	return ""


static func _give(s: Soldier, id: StringName, n: int) -> void:
	var got := s.inventory.take(id, n)
	if got < n:
		var lvl := CompoundLevel.current(s)
		if lvl:
			lvl.server_spawn_dropped(id, n - got, s.global_position + Vector3.UP * 0.4)


# --- The settlement's gunsmith work order ------------------------------------------------------------

static func order() -> Dictionary:
	var d := Settlement.data()
	if not d.get(ORDER) is Dictionary:
		d[ORDER] = {}
	return d[ORDER]


static func order_on() -> bool:
	return Settlement.exists() and bool(order().get("on", false))


## Host (the settlement screen's order): the gunsmith order on or off. "" or why not.
static func server_set_order(on: bool) -> String:
	if not Settlement.exists():
		return "No settlement"
	order()["on"] = on
	Survival._journal_line("Work order: %s." % ("work the guns in the armoury overnight" if on else "the gunsmith's order lifted"))
	return ""


## The settler who'd do it: the best firearms of STRIP_LEVEL+ ({} none).
static func smith() -> Dictionary:
	var best: Dictionary = {}
	for r: Dictionary in Settlement.settlers():
		if rec_level(r) >= STRIP_LEVEL and String(r.get("break", "")) == "" and (best.is_empty() or rec_level(r) > rec_level(best)):
			best = r
	return best


## Host (Settlement.server_hour): at ORDER_HOUR, with the order on, a bench and an armoury rack built
## and a smith, up to ORDER_GUNS worn or broken guns in stock are worked to the smith's quality (a
## broken one takes its gun parts from the stock and needs REBUILD_LEVEL). Returns how many.
static func settlement_hour(_st: Settlement, hod: int) -> int:
	if hod != ORDER_HOUR or not order_on():
		return 0
	var d := Settlement.data()
	if int(d.get("gun_benches", 0)) <= 0 or int(d.get("gun_racks", 0)) <= 0:
		return 0
	var who := smith()
	if who.is_empty():
		return 0
	var lvl := rec_level(who)
	var worked := 0
	var guns: Array[Dictionary] = []
	for key: String in Settlement.stores():
		for e: Dictionary in Settlement._entries(key):
			var item := ItemDB.get_item(StringName(String(e.id)))
			if WeaponCondition.is_gun(item) and e.get("state") is Dictionary and (e.state as Dictionary).has(Wear.KEY) and Wear.cond(e.state) < 99.5:
				guns.append(e)
	for e: Dictionary in guns:
		if worked >= ORDER_GUNS:
			break
		var item := ItemDB.get_item(StringName(String(e.id)))
		var st: Dictionary = e.state
		var to := quality(lvl, STRIP_LEVEL)
		if WeaponCondition.is_broken(st):
			if lvl < REBUILD_LEVEL or Settlement.count(String(PARTS)) < parts_for(item):
				continue
			Settlement.server_take(String(PARTS), parts_for(item))
			to = quality(lvl, REBUILD_LEVEL)
		Wear.set_cond(st, maxf(Wear.cond(st), to))
		st.erase("jammed")
		worked += 1
	if worked > 0:
		order()["done"] = int(order().get("done", 0)) + worked
		order()["last_day"] = Survival.day()
		SurvivorPerson.note(who, "worked %d gun%s overnight" % [worked, "" if worked == 1 else "s"])
		Survival._journal_line("%s worked the guns overnight: %d repaired." % [String(who.get("first", who.get("name", ""))), worked])
	return worked
