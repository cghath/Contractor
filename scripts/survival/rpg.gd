class_name Rpg
extends Node
## Contractor: Fallen's RPG layer (docs/survival_rpg.md; calls 11, 16, 17, 82-84): the twelve
## skill lines (RpgLines) levelled by doing, the survivor level with a perk pick per level
## (Perks), the background and flaws chosen at creation (Backgrounds), and the gates and effects
## the other systems read. Host-authoritative: everything lives in the survivor record
## (Survival.survivor_of(s)["rpg"]), so it saves with the world and permadeath wipes it (the new
## survivor's record has none). The owner gets a copy (_client_rpg) for his character screen and
## the parts he simulates (the load he carries).
##
## Static API (the other lanes call these): xp(s, line, amount), level(s, line),
## gate(s, line, needed), and the effect reads (carry_bonus_kg, step_noise_mult,
## build_time_mult, medical_sees, ...). Inert outside survival and for the AI (companions' lines
## come with the people lane): levels read 0, gates pass, multipliers are 1.
##
## One instance lives under the Survival autoload (Survival._ready) for the RPCs and the tick.

signal changed  # this peer's own survivor's lines, perks or creation changed (my)

const KEY := "rpg"
const TICK_S := 1.0
const SYNC_S := 2.0

## Proposed XP for each kind of doing (the at/below/above rule scales them: RpgLines.task_mult).
const XP_MELEE_HIT := 2.0
const XP_MELEE_KILL := 6.0
const XP_PARRY := 4.0
const XP_SILENT_KILL := 15.0
const XP_SILENT_MELEE := 3.0
const XP_TREAT := 8.0
const XP_SEARCH := 4.0
const XP_SPRINT_PER_M := 1.0 / 50.0  # fitness: 1 XP per 50 m run
const XP_LOAD_PER_M := 1.0 / 100.0  # fitness: 1 XP per 100 m with a heavy load (Needs.HEAVY_KG)
const XP_DRIVE_PER_M := 1.0 / 100.0  # driving: 1 XP per 100 m at the wheel
const XP_UNSEEN_S := 0.1  # stealth: a second unseen with the dead about (6 XP a minute)
const UNSEEN_M := 20.0
const MAX_STEP_M := 30.0  # a tick's move past this is a teleport (a respawn), not a run

## Proposed: how hard each treatment is, as a medical level (the at/below/above rule).
const TREAT_LEVEL := {"tourniquet": 1, "pressure_bandage": 1, "gauze_pack": 1, "hemostatic_gauze": 2, "splint": 3, "sam_splint": 3,
	"suture_kit": 3, "chest_seal": 2, "npa": 2, "iv_kit": 6, "io_kit": 6, "surgery_kit_5": 5}

## The doc's gates (section 6) for the treatments and reads other lanes call by name.
const GATES := {
	"read_bleeding": ["medical", 2], "read_infection": ["medical", 4], "full_diagnosis": ["medical", 7],
	"stitch": ["medical", 3], "remove_fragment": ["medical", 5], "set_bone": ["medical", 6], "amputate": ["medical", 8], "cure_chain": ["medical", 9],
	"build_tier_2": ["building", 2], "build_tier_3": ["building", 4], "build_steel": ["building", 6], "load_numbers": ["building", 3], "templates": ["building", 5],
	"fit_battery": ["mechanics", 1], "fit_tyre": ["mechanics", 2], "engine": ["mechanics", 4], "rebuild_wreck": ["mechanics", 6], "dam": ["mechanics", 9],
	"heavy_swing": ["melee", 2], "silent_kill_any_blade": ["melee", 4], "two_handed_mastery": ["melee", 6],
	"reload_ammo": ["firearms", 7], "suppressor": ["firearms", 6],
	"horses": ["fieldcraft", 3], "tracking": ["fieldcraft", 3], "mushrooms": ["fieldcraft", 4], "weather": ["fieldcraft", 5],
	"masking": ["stealth", 4], "crawl_among": ["stealth", 7],
}

## Owner: his own survivor's view (lines, levels, perks, background, flaws, owed picks).
var my := {}
var _tick := 0.0
var _sync := 0.0
var _dirty := {}  # host: soldier instance id -> Soldier, records changed since the last sync


func _init() -> void:
	name = "Rpg"


static func net() -> Rpg:
	return Survival.get_node_or_null(^"Rpg") as Rpg


## Whether `s` has an RPG record: a player's survivor in a running survival world.
static func active(s: Soldier) -> bool:
	return s != null and is_instance_valid(s) and Survival.running and not s.is_ai()


static func fresh() -> Dictionary:
	return {"lines": {}, "earned": 0.0, "perks": [], "granted": [], "background": "", "flaws": [], "read": [], "tally": {}}


# --- The record ---------------------------------------------------------------------------

## Host: `s`'s RPG record (in the survivor record). A first survivor (generation 1) gets the
## world's creation choice (Survival options "survivor"); a newcomer after a death starts blank.
static func data(s: Soldier) -> Dictionary:
	var rec := Survival.survivor_of(s)
	if not (rec.get(KEY, null) is Dictionary):
		var d := fresh()
		rec[KEY] = d
		var choice: Variant = (Survival.state().get("options", {}) as Dictionary).get("survivor", {})
		if int(rec.get("generation", 1)) <= 1 and choice is Dictionary and not (choice as Dictionary).is_empty():
			apply_creation(d, choice)
	return rec[KEY]


## What `s`'s RPG reads come from: the host's record, the owner's copy, else nothing.
static func view(s: Soldier) -> Dictionary:
	if not active(s):
		return {}
	if not s.is_inside_tree() or s.multiplayer.is_server():
		return data(s)
	var n := net()
	return n.my if n and s.owner_peer() == s.multiplayer.get_unique_id() else {}


## Puts a creation `choice` (Backgrounds) on a fresh record `d`; an invalid one gives a blank
## slate. Returns the problem, or "".
static func apply_creation(d: Dictionary, choice: Dictionary) -> String:
	var why := Backgrounds.problem(choice)
	if why != "":
		d["creation_problem"] = why
		return why
	d.background = String(choice.get("background", ""))
	d.flaws = (choice.get("flaws", []) as Array).duplicate()
	var bg: Dictionary = Backgrounds.ALL.get(d.background, {})
	if bg.has("perk"):
		d.granted = [String(bg.perk)]
	var lines: Dictionary = d.lines
	var start := Backgrounds.start_levels(choice)
	for line: String in start:
		lines[line] = RpgLines.xp_for(int(start[line]))
	return ""


static func _levels_of(d: Dictionary) -> Dictionary:
	var out := {}
	var lines: Dictionary = d.get("lines", {})
	for line: String in RpgLines.LINES:
		out[line] = RpgLines.level_of(float(lines.get(line, 0.0)))
	return out


static func _all_perks(d: Dictionary) -> Array:
	return (d.get("perks", []) as Array) + (d.get("granted", []) as Array)


## A line's level, 0-10 (0 outside survival and for the AI).
static func level(s: Soldier, line: String) -> int:
	var d := view(s)
	if d.is_empty():
		return 0
	if d.has("levels"):
		return int((d.levels as Dictionary).get(line, 0))
	return RpgLines.level_of(float((d.get("lines", {}) as Dictionary).get(line, 0.0)))


## A line's XP total.
static func line_xp(s: Soldier, line: String) -> float:
	return float((view(s).get("lines", {}) as Dictionary).get(line, 0.0))


## Whether `s` is at least `needed` in `line` (true outside survival and for the AI).
static func gate(s: Soldier, line: String, needed: int) -> bool:
	return not active(s) or level(s, line) >= needed


## A named gate from GATES ("stitch", "heavy_swing", "build_tier_2", ...).
static func can(s: Soldier, what: String) -> bool:
	var g: Array = GATES.get(what, [])
	return g.is_empty() or gate(s, String(g[0]), int(g[1]))


## The survivor level (call 83): from the XP earned by doing (a background's start doesn't count).
static func survivor_level(s: Soldier) -> int:
	return RpgLines.survivor_level_of(float(view(s).get("earned", 0.0)))


## Perk picks owed (a level without its pick yet).
static func picks_owed(s: Soldier) -> int:
	return maxi(0, survivor_level(s) - (view(s).get("perks", []) as Array).size())


static func has_perk(s: Soldier, id: String) -> bool:
	return id in _all_perks(view(s))


static func has_flaw(s: Soldier, id: String) -> bool:
	return id in (view(s).get("flaws", []) as Array)


## Host: `amount` XP in `line` for `s` for a task of `task_level` (-1: at his level), through the
## at/below/above rule, his flaws (slow learner) and perks (quick study). Returns the XP gained.
static func xp(s: Soldier, line: String, amount: float, task_level := -1) -> float:
	if not active(s) or amount <= 0.0 or not line in RpgLines.LINES or (s.is_inside_tree() and not s.multiplayer.is_server()):
		return 0.0
	var d := data(s)
	var lines: Dictionary = d.lines
	var before := RpgLines.level_of(float(lines.get(line, 0.0)))
	var level_before := RpgLines.survivor_level_of(float(d.earned))
	var gain := amount * RpgLines.task_mult(before, task_level) * Backgrounds.fx(d.flaws, "xp") * Perks.fx(_all_perks(d), "xp")
	lines[line] = float(lines.get(line, 0.0)) + gain
	d.earned = float(d.earned) + gain
	var after := RpgLines.level_of(float(lines[line]))
	var n := net()
	if n:
		n._dirty[s.get_instance_id()] = s
	if after > before:
		_levelled(s, line, after)
	if RpgLines.survivor_level_of(float(d.earned)) > level_before:
		Survival._tell(s, "You feel more sure of yourself: a perk to pick (the character screen)")
		server_sync(s)
	return gain


## Host (tests, dev): sets `line` to exactly `n`'s XP.
static func set_level(s: Soldier, line: String, n: int) -> void:
	if not active(s):
		return
	var d := data(s)
	(d.lines as Dictionary)[line] = RpgLines.xp_for(n)
	server_sync(s)


static func _levelled(s: Soldier, line: String, n: int) -> void:
	var next := RpgLines.next_unlock(line, n - 1)
	var what := (": " + String(next[1])) if not next.is_empty() and int(next[0]) == n else ""
	Survival._journal_line("%s is %s %d%s." % [Survival.survivor_name(s), line, n, what])
	Survival._tell(s, "%s %d%s" % [line.capitalize(), n, what])
	server_sync(s)


## Host: `s` takes perk `id` (one owed pick, its needs met). "" or why not.
static func server_pick_perk(s: Soldier, id: String) -> String:
	if not active(s):
		return "No survivor"
	var d := data(s)
	if picks_owed(s) <= 0:
		return "No perk to pick yet"
	if id in _all_perks(d):
		return "Already has it"
	if not Perks.allowed(id, _levels_of(d)):
		return "Needs %s" % [(Perks.info(id).get("needs", {}) as Dictionary)] if Perks.ALL.has(id) else "No perk %s" % id
	(d.perks as Array).append(id)
	Survival._journal_line("%s: %s." % [Survival.survivor_name(s), String(Perks.info(id).name).to_lower()])
	server_sync(s)
	return ""


## Host: sends `s`'s record to his owner (and refreshes what it changes on the body: the load).
static func server_sync(s: Soldier) -> void:
	if not active(s) or not s.is_inside_tree():
		return
	var n := net()
	if n == null:
		return
	n._dirty.erase(s.get_instance_id())
	var d := data(s)
	var v := d.duplicate(true)
	v["levels"] = _levels_of(d)
	v["survivor_level"] = RpgLines.survivor_level_of(float(d.earned))
	v["name"] = Survival.survivor_name(s)
	refresh_load(s)
	var peer := s.owner_peer()
	if peer == s.multiplayer.get_unique_id():
		n._client_rpg(v)
	elif peer in s.multiplayer.get_peers():
		n._client_rpg.rpc_id(peer, v)


## Host: a survivor came into the world (Survival.server_survivor_joined): his record (the
## creation applied on a first join) to his owner.
static func server_joined(s: Soldier) -> void:
	if active(s):
		data(s)
		server_sync(s)


@rpc("authority", "call_remote", "reliable")
func _client_rpg(v: Dictionary) -> void:
	my = v.duplicate(true)
	var level_node := CompoundLevel.current(self)
	if level_node and not multiplayer.is_server():
		var me := level_node.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier
		if me:
			refresh_load(me)
	changed.emit()


## The load he feels (Soldier._on_inventory_changed reads carry_bonus_kg and speed_mult), redone
## only when those changed (it re-emits the loadout).
static func refresh_load(s: Soldier) -> void:
	var now := [carry_bonus_kg(s), speed_mult(s)]
	if s.get_meta(&"rpg_load", [0.0, 1.0]) != now:
		s.set_meta(&"rpg_load", now)
		s._on_inventory_changed()


## Owner: asks the host for perk `id` (the character screen).
func request_pick(id: String) -> void:
	if multiplayer.is_server():
		var me := _my_soldier()
		if me:
			var why := server_pick_perk(me, id)
			if why != "":
				Survival._tell(me, why)
	else:
		_server_pick.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _server_pick(id: String) -> void:
	var level_node := CompoundLevel.current(self)
	if level_node == null:
		return
	var s := level_node.players.get_node_or_null(str(multiplayer.get_remote_sender_id())) as Soldier
	if s:
		var why := server_pick_perk(s, id)
		if why != "":
			Survival._tell(s, why)


func _my_soldier() -> Soldier:
	var level_node := CompoundLevel.current(self)
	return level_node.players.get_node_or_null(str(multiplayer.get_unique_id())) as Soldier if level_node else null


# --- Effects (section 1's unlocks; Proposed numbers) -------------------------------------

## Kilograms carried free of the load's penalty: FITNESS_KG a fitness level (call 16) and perks.
const FITNESS_KG := 3.0


static func carry_bonus_kg(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 0.0
	return FITNESS_KG * level(s, "fitness") + Perks.fx(_all_perks(d), "carry_kg")


## The body's speed from the flaws (a bad knee).
static func speed_mult(s: Soldier) -> float:
	var d := view(s)
	return 1.0 if d.is_empty() else Backgrounds.fx(d.get("flaws", []), "speed")


## How far his footsteps carry (Survival._footsteps): STEALTH_STEP less a stealth level (to
## STEALTH_STEP_MIN), a perk, a flaw (clumsy).
const STEALTH_STEP := 0.05
const STEALTH_STEP_MIN := 0.5


static func step_noise_mult(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 1.0
	return maxf(STEALTH_STEP_MIN, 1.0 - STEALTH_STEP * level(s, "stealth")) * Perks.fx(_all_perks(d), "step_noise") * Backgrounds.fx(d.get("flaws", []), "step_noise")


## How long his builds take (the building lane): -6% a building level (section 1), perks.
const BUILD_PER_LEVEL := 0.06


static func build_time_mult(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 1.0
	return maxf(0.3, 1.0 - BUILD_PER_LEVEL * level(s, "building")) * Perks.fx(_all_perks(d), "build_time")


## How long his searches take: -4% a scavenging level, the scrounger perk.
static func search_time_mult(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 1.0
	return maxf(0.4, 1.0 - 0.04 * level(s, "scavenging")) * Perks.fx(_all_perks(d), "search_time")


## A swing's stamina: -5% a melee level (to half), the brawler perk.
static func melee_stamina_mult(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 1.0
	return maxf(0.5, 1.0 - 0.05 * level(s, "melee")) * Perks.fx(_all_perks(d), "melee_stamina")


## The parry window: PARRY_WIDER from melee 3, the cool head perk.
const PARRY_WIDER := 1.5


static func parry_window_mult(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 1.0
	return (PARRY_WIDER if level(s, "melee") >= 3 else 1.0) * Perks.fx(_all_perks(d), "parry")


## How fast the cold gets in (Needs.context_of "cold_mult"): flaws (thin-skinned), perks (thick
## skin), fitness 3 (cold resistance: COLD_FIT).
const COLD_FIT := 0.9


static func cold_mult(s: Soldier) -> float:
	var d := view(s)
	if d.is_empty():
		return 1.0
	return Backgrounds.fx(d.get("flaws", []), "cold") * Perks.fx(_all_perks(d), "cold") * (COLD_FIT if level(s, "fitness") >= 3 else 1.0)


## What his eyes make of a body (the body screen lane): 0 a novice ("hurt, bleeding"), 1 a medic
## (bleeding classes, from medical 2), 2 a doctor (everything, from medical 7). Everyone outside
## survival reads as a doctor (the campaign's medical menu is unchanged).
static func medical_sees(s: Soldier) -> int:
	if not active(s):
		return 2
	var m := level(s, "medical")
	return 2 if m >= 7 else (1 if m >= 2 else 0)


## Never wakes to the noise ring (SurvivalSleep can read it).
static func heavy_sleeper(s: Soldier) -> bool:
	return Backgrounds.has_flag(view(s).get("flaws", []), "heavy_sleeper")


## The silent kill's blade (call 89): a knife at any level, any other blade from melee 4.
static func silent_blade_ok(s: Soldier, weapon: ItemData) -> bool:
	if MeleeWeapons.blade_carried(s) or (weapon != null and weapon.tags.has("knife")):
		return true
	return MeleeWeapons.is_blade(weapon) and can(s, "silent_kill_any_blade")


# --- XP sources (hooked a line each from melee, the medical log, the loot search) ---------

## Host: a melee blow of `attacker` landed on `victim` (Melee._hit): a hit, or a kill.
static func on_melee_hit(attacker: Soldier, victim: Soldier) -> void:
	if active(attacker) and victim != null:
		xp(attacker, "melee", XP_MELEE_KILL if victim.vitals.is_dead() else XP_MELEE_HIT)


static func on_parry(defender: Soldier) -> void:
	xp(defender, "melee", XP_PARRY)


static func on_silent_kill(s: Soldier) -> void:
	xp(s, "stealth", XP_SILENT_KILL)
	xp(s, "melee", XP_SILENT_MELEE)


## Host: a treatment done (Soldier._log_care "done"): medical XP by how hard it was.
static func on_treated(s: Soldier, item_id: StringName) -> void:
	xp(s, "medical", XP_TREAT, int(TREAT_LEVEL.get(String(item_id), 1)))


## Host: a search finished (Soldier._loot_session_ok): scavenging XP.
static func on_searched(s: Soldier, _target: Node) -> void:
	xp(s, "scavenging", XP_SEARCH)


## Host: a book read (an item with stats.book {line, xp, max_level}): its XP once per survivor,
## only while the line is under max_level. "" or why not. (The inventory's Read action: later.)
static func server_read(s: Soldier, item_id: StringName) -> String:
	var item := ItemDB.get_item(item_id)
	if not active(s) or item == null or not item.stats.has("book"):
		return "Nothing to read"
	var book: Dictionary = item.stats.book
	var d := data(s)
	if String(item_id) in (d.read as Array):
		return "Already read it"
	var line := String(book.get("line", ""))
	if level(s, line) >= int(book.get("max_level", 3)):
		return "Nothing new in it"
	(d.read as Array).append(String(item_id))
	xp(s, line, float(book.get("xp", 60.0)))
	return ""


## Teaching (survival_people.md section 5): a companion with a line 2 above the student. Stub
## until companions are people: "" when it would go, else why not; no XP yet.
static func server_teach(teacher: Soldier, student: Soldier, line: String) -> String:
	if level(teacher, line) < level(student, line) + 2:
		return "The teacher needs to be 2 levels above"
	return "Teaching comes with the companions"


# --- The tick: fitness, stealth, driving --------------------------------------------------

func _process(delta: float) -> void:
	if not Survival.running or not multiplayer.is_server():
		return
	_tick += delta
	_sync += delta
	if _tick >= TICK_S:
		var dt := _tick
		_tick = 0.0
		var level_node := CompoundLevel.current(self)
		if level_node is SurvivalLevel:
			for s: Soldier in MapNodes.players(level_node):
				server_tick(s, dt, Survival.zombies(level_node))
	if _sync >= SYNC_S:
		_sync = 0.0
		for id: int in _dirty.keys():
			var s: Soldier = _dirty[id]
			_dirty.erase(id)
			if is_instance_valid(s):
				server_sync(s)


## Host: `dt` seconds of `s`'s doing: metres run or carried heavy (fitness), driven (driving),
## time unseen with the dead about (stealth).
static func server_tick(s: Soldier, dt: float, dead: Array) -> void:
	if not active(s) or not s.vitals.is_up():
		if s.has_meta(&"rpg_at"):
			s.remove_meta(&"rpg_at")
		return
	var at := s.global_position
	var was: Variant = s.get_meta(&"rpg_at", null)
	s.set_meta(&"rpg_at", at)
	var moved := 0.0
	if was is Vector3:
		moved = Vector2(at.x - (was as Vector3).x, at.z - (was as Vector3).z).length()
		if moved > MAX_STEP_M:
			moved = 0.0
	if is_instance_valid(s.vehicle):
		if s.vehicle.driver() == s and moved > 0.0:
			xp(s, "driving", moved * XP_DRIVE_PER_M)
		return
	if moved > 0.0:
		var run := s.want_sprint and s.velocity.length() > 3.0  # (as Needs.context_of reads a run on the host)
		var gain := (moved * XP_SPRINT_PER_M if run else 0.0) + (moved * XP_LOAD_PER_M if s.load_kg > Needs.HEAVY_KG else 0.0)
		if gain > 0.0:
			xp(s, "fitness", gain)
	var near := 0
	for z: Soldier in dead:
		if not is_instance_valid(z) or not z.vitals.is_up() or z.global_position.distance_to(at) > UNSEEN_M:
			continue
		var brain := ZombieAI.of(z)
		if brain == null or not brain.unaware():
			return  # one of them knows he's there
		near += 1
	if near > 0:
		xp(s, "stealth", XP_UNSEEN_S * dt)
