class_name FirstHour
extends RefCounted
## The first hour of Contractor: Fallen (docs/survival_firsthour.md; after the Captain's first
## playtest: a huge sandbox with no direction loses a player). Not a tutorial: a first-day thread,
## contextual control hints once each (FieldHints), a softer first night, and "what now".
##
## - The thread: the cold open's note ends with a postscript pointing at three nearby things, each
##   a journal line and a map mark that completes on doing it and pays a little (XP, a steadier
##   nerve, an item): WATER (drink or fill a bottle at the farm's well, or any water), A WEAPON
##   better than the knife (a crowbar, machete or hatchet put in a marked shed up the track; any
##   non-knife melee weapon carried counts), SHELTER (board up the farmhouse: a shutter, door, gate
##   or fence, or SHELTER_BLOCKS blocks, built within SHELTER_M of it; planks and a hammer are left
##   by the stove). On day 2 a VOICE on the farm's old set: a lone survivor (want: a bed with walls)
##   placed by a landmark and marked; recruiting them completes it. Nothing forces the order, and
##   ignoring it costs nothing.
## - Hints (FieldHints): the host sees the situation (an unaware zombie within SILENT_HINT_M, a
##   melee weapon up, the first dusk, a container in reach, loose rounds with their magazine, an
##   injury, a companion, building materials carried, hunger or thirst low) and tells the owner,
##   once a session; the owner shows it once per profile, with his own key names.
## - The first night (pacing): at a "dead" option below High no horde forms (the pressure's horde,
##   a siege, a horde walking in) until the first night is over (day 2's FIRST_NIGHT_END_H), and
##   the dead's night pace bonus (ZombieAI.NIGHT_WALK_MULT) ramps over the first two nights
##   (NIGHT_SHARE); High keeps the hard first night.
## - Now: the journal's front page lists the open goals (now_lines) and the nearest landmark not
##   yet visited (unvisited_line); the map draws unvisited landmarks as "?" (visited: within
##   VISIT_M, kept in the map section's "visited" so every peer draws the same).
## State: Survival.state()["first_hour"]: {"home", "well", "well_prop", "shed", "weapon",
## "goals": {id: {"open", "done", "day"}}, "voice_pid"}. Host-side, static. Every number Proposed.

const KEY := "first_hour"
const GOALS: Array[String] = ["water", "weapon", "shelter", "voice"]
const TITLES := {"water": "Water", "weapon": "Something better than the knife", "shelter": "Board up the farmhouse",
	"voice": "The voice on the radio"}
## What each open goal says on the journal's front page.
const TODO := {"water": "Drink or fill a bottle at the well in the yard (look at it, %s)",
	"weapon": "The barn (or the shed) has tools: find a real weapon",
	"shelter": "Board up the farmhouse before dark: planks and a hammer by the stove (%s build mode)",
	"voice": "Someone answered on the old set: find them near %s"}
## What doing it pays (XP line and amount, nerve steadied, an item) and the journal line.
const REWARDS := {
	"water": {"xp": ["fieldcraft", 30.0], "nerve": 8.0, "item": ["water_tablets", 2],
		"line": "Water from the well. Tastes of iron. There were purification tablets in the pump box."},
	"weapon": {"xp": ["melee", 30.0], "nerve": 8.0, "item": ["whetstone", 1],
		"line": "Found something with reach. A whetstone was in the shed too."},
	"shelter": {"xp": ["building", 40.0], "nerve": 10.0, "item": ["canned_meat", 1],
		"line": "Boarded up. It won't stop a crowd but it'll stop one. Found a tin behind the old boards."},
	"voice": {"xp": ["fieldcraft", 20.0], "nerve": 12.0, "item": [],
		"line": "Not alone any more. %s is with us."},
}
const WELL_SHAPES: Array[String] = ["well", "cistern", "trough", "windpump"]
const WELL_FIND_M := 250.0
const WELL_PICK_M := 3.0
const WELL_FALLBACK := Vector3(7.0, 0.0, 5.0)
const SHED_KINDS: Array[String] = ["barn", "farmhouse", "farm", "garage"]
const SHED_M := Vector2(40.0, 400.0)
const SHED_FALLBACK_M := 80.0
const WEAPONS: Array[String] = ["crowbar", "machete", "hatchet"]
const BUILD_KIT: Array = [["hammer", 1], ["planks", 4]]
const SHELTER_M := 20.0
const SHELTER_PIECES: Array[String] = ["shutter", "door", "gate", "hatch", "fence"]
const SHELTER_BLOCKS := 2
const VOICE_DAY := 2
const VOICE_HOUR := 9.0
const VOICE_M := Vector2(150.0, 450.0)
const VOICE_FALLBACK_M := 220.0
## Pacing: the first night lasts until this hour of day 2; the night pace bonus's share on nights
## 1 and 2 (night 3 on: all of it).
const FIRST_NIGHT_END_H := 6.0
const NIGHT_SHARE: Array[float] = [0.0, 0.5]
## A landmark counts as visited within this.
const VISIT_M := 35.0
## Hints' situations.
const SILENT_HINT_M := 15.0
const CONTAINER_HINT_M := 3.0
const LOW_NEED := 40.0

## The start farmstead (the Captain: "at the spawn there is nothing": a new world put him at a bare
## zone edge): the start zone gets a farm landmark site (BuildingGen.site "farm": a farmhouse you can
## enter and board, a barn, silos, a fenced pen with a trough, a well in the yard) FARM_IN_M in
## from its first insertion point, clear of the zone's sites; the insertion moves to the
## farmhouse's front door, outside. Its boxes (FARM_BOXES) are WorldCaches rolled once (FoundLoot
## thins a first roll: searched-feeling, not empty; no guns).
const HOME_ID := "farm_home"
const FARM_IN_M := 70.0
const FARM_CLEAR_M := 160.0
const FARM_BOXES: Array = [
	{"uid": "farm_pantry", "label": "Pantry shelf", "where": "inside", "at": [1.2, 0.0, -1.5],
		"items": [["canned_meat", 1], ["beans_tin", 2], ["water_bottle", 1], ["cloth_rag", 3]]},
	{"uid": "farm_dresser", "label": "Dresser", "where": "inside", "at": [-1.8, 0.0, -2.0],
		"items": [["cloth_rag", 4], ["pressure_bandage", 1], ["candles", 1]]},
	{"uid": "farm_toolbox", "label": "Tool chest", "where": "barn", "at": [1.5, 0.0, 0.0],
		"items": [["planks", 3], ["cable_ties", 2], ["cloth_rag", 2], ["wood_stick", 2]]},
]
## Proposed (the Captain, 2026-10-26: "zombies should be nearly non existent out in the wild and
## near AI farms"): the open country's pace of the dead by the days (OPEN_RAMP: [from day, share of
## the full pace]) and the zone's tier (+OPEN_TIER_STEP a tier); from OPEN_LATE_DAY (or a zone
## OPEN_LATE_TIER out) the open keeps Survival.OPEN_DEAD_LATE about a survivor. Within QUIET_M of a
## place living people hold (a lone survivor's home, a world group's home or place in this zone)
## the dead neither come about a survivor nor drift in on their own (sieges, hordes and noise still
## bring them).
const OPEN_RAMP: Array = [[1, 0.5], [3, 0.75], [7, 1.0]]
const OPEN_TIER_STEP := 0.25
const OPEN_LATE_DAY := 7
const OPEN_LATE_TIER := 2
const QUIET_M := 150.0
const QUIET_REFRESH_S := 2.0

## Host: hints already sent this session, profile -> {id: true}.
static var _sent := {}
## Host: the living's quiet places in the hosted zone (x, z), refreshed every QUIET_REFRESH_S.
static var _quiet: Array[Vector2] = []
static var _quiet_at := -100.0


# --- The start farmstead --------------------------------------------------------------------------

## The start zone's def with its farmstead: a farm landmark module (HOME_ID) near the first
## insertion point and the insertion at its front door; "farmstead" in the def says where things
## are ({"pos", "door", "inside", "well", "barn", "seed"}, x/z in zone metres). The same every time.
static func farmstead(def: Dictionary, world_seed: int) -> Dictionary:
	var ins: Array = def.get("insertion", [])
	if ins.is_empty():
		return def
	var mods: Array = def.get("modules", [])
	for m: Dictionary in mods:
		if String(m.get("id", "")) == HOME_ID:
			return def
	var p0 := Vector2(float(ins[0][0]), float(ins[0][1]))
	var seed_v := absi(hash(["farmstead", world_seed, String(def.get("id", ""))])) % 100000
	var site := BuildingGen.site("farm", seed_v, BuildingGen.INTACT, 0)
	var half: Vector2 = site.half
	var inward := (-p0).normalized() if p0.length() > 1.0 else Vector2(0, -1)
	var centre := Vector2.INF
	for k in 8:
		var c := p0 + inward * (FARM_IN_M + maxf(half.x, half.y) + k * 30.0)
		var clear := true
		for m: Dictionary in mods:
			var mp: Array = m.get("pos", [0.0, 0.0])
			if Vector2(float(mp[0]), float(mp[1])).distance_to(c) < FARM_CLEAR_M + maxf(half.x, half.y):
				clear = false
				break
		if clear:
			centre = c.snapped(Vector2(1.0, 1.0))
			break
	if centre == Vector2.INF:
		return def
	mods.append({"id": HOME_ID, "type": "%sfarm#%d#%d#0" % [ZoneModules.LANDMARK, seed_v, BuildingGen.INTACT], "pos": [centre.x, centre.y]})
	def["modules"] = mods
	var house: Dictionary = (site.buildings as Array)[0]
	var fd: Variant = BuildingGen.front_door(house.data)
	var origin: Vector3 = house.origin
	var hsize: Vector2 = (house.data as Dictionary).size
	var door3 := origin + (BuildingGen._rot(fd as Vector3, int(house.turn)) if fd is Vector3 else Vector3(0, 0, hsize.y * 0.5))
	var out3 := door3 + BuildingGen._rot(Vector3(0, 0, 1.6), int(house.turn))
	var in3 := door3 + BuildingGen._rot(Vector3(0, 0, -1.6), int(house.turn))
	var well := Vector2(origin.x + hsize.x * 0.5 + 4.0, hsize.y * 0.5 + 3.0)
	var barn_d: Dictionary = (site.buildings as Array)[1] if (site.buildings as Array).size() > 1 else house
	var barn: Vector3 = barn_d.origin
	var door := centre + Vector2(out3.x, out3.z)
	ins[0] = [snappedf(door.x, 0.1), snappedf(door.y, 0.1)]
	def["insertion"] = ins
	def["farmstead"] = {"pos": [centre.x, centre.y], "door": [door.x, door.y], "inside": [centre.x + in3.x, centre.y + in3.z],
		"well": [centre.x + well.x, centre.y + well.y], "barn": [centre.x + barn.x, centre.y + barn.z], "seed": seed_v}
	return def


## The hosted level's farmstead record ({} outside the start zone or without one).
static func farm_of(level: Node) -> Dictionary:
	var zl := level as ZoneLevel
	if zl == null:
		return {}
	var f: Variant = zl.def.get("farmstead", {})
	return f if f is Dictionary else {}


## A farmstead point (`key` of farm_of) on the level's ground, or null.
static func farm_point(level: Node, key: String, offset := Vector3.ZERO) -> Variant:
	var f := farm_of(level)
	var zl := level as ZoneLevel
	if zl == null or not f.has(key):
		return null
	var a: Array = f[key]
	return zl.ground_point(Vector3(float(a[0]) + offset.x, 0.0, float(a[1]) + offset.z))


## Host: the start zone is up: the farmstead's boxes (once each; the zone save keeps what's taken).
static func server_level_ready(level: SurvivalLevel) -> void:
	_quiet_at = -100.0
	var f := farm_of(level)
	var spawner_node: Variant = level.get(&"cache_spawner")
	if f.is_empty() or not spawner_node is MultiplayerSpawner:
		return
	var spawner := spawner_node as MultiplayerSpawner
	var holder := spawner.get_node_or_null(spawner.spawn_path)
	for b: Dictionary in FARM_BOXES:
		var uid := String(b.uid)
		if holder and holder.get_node_or_null(NodePath(uid)) != null:
			continue
		var off: Array = b.at
		var at: Variant = farm_point(level, String(b.where), Vector3(float(off[0]), 0.0, float(off[2])))
		if not at is Vector3:
			continue
		var cache := spawner.spawn({"uid": uid, "pos": (at as Vector3) + Vector3.UP * 0.05, "yaw": 0.0, "label": String(b.label)}) as WorldCache
		if cache:
			var items: Array = []
			for e: Array in b.items:
				if ItemDB.get_item(StringName(String(e[0]))) != null:
					items.append({"id": String(e[0]), "count": int(e[1])})
			cache.server_fill(items)


# --- The dead's density -------------------------------------------------------------------------

## The open country's pace of the dead now (1 the full pace): the days ramp, the zone's tier, the
## "dead" option.
static func open_pace() -> float:
	var share := 1.0
	for r: Array in OPEN_RAMP:
		if Survival.day() >= int(r[0]):
			share = float(r[1])
	share += OPEN_TIER_STEP * FoundLoot.zone_tier()
	return share * Survival.option_mult("dead")


## Whether the open country keeps the later count of the dead (the days, a far zone).
static func open_late() -> bool:
	return Survival.day() >= OPEN_LATE_DAY or FoundLoot.zone_tier() >= OPEN_LATE_TIER


## The places living people hold in the hosted zone (x, z): lone survivors' homes, world groups'
## homes and the places they hold (host; refreshed every QUIET_REFRESH_S).
static func quiet_places() -> Array[Vector2]:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _quiet_at < QUIET_REFRESH_S:
		return _quiet
	_quiet_at = now
	_quiet.clear()
	var zone := String(Survival.state().get("zone", ""))
	for rec: Variant in (Survival.state().get("people", {}) as Dictionary).values():
		if rec is Dictionary and String((rec as Dictionary).get("status", "")) == "out_there" and String((rec as Dictionary).get("zone", "")) == zone:
			var h: Variant = (rec as Dictionary).get("home", (rec as Dictionary).get("pos", []))
			if h is Array and (h as Array).size() >= 3:
				_quiet.append(Vector2(float(h[0]), float(h[2])))
	var groups: Dictionary = WorldSim.section().get("groups", {})
	for g: Variant in groups.values():
		if not g is Dictionary or not bool((g as Dictionary).get("alive", true)) or ((g as Dictionary).get("members", []) as Array).is_empty():
			continue
		var home: Variant = (g as Dictionary).get("home", {})
		if home is Dictionary and String((home as Dictionary).get("zone", "")) == zone and (home as Dictionary).get("pos") is Array:
			var hp: Array = (home as Dictionary).pos
			if hp.size() >= 2:
				_quiet.append(Vector2(float(hp[0]), float(hp[hp.size() - 1])))
	var zd: Dictionary = (WorldSim.section().get("zones", {}) as Dictionary).get(zone, {})
	for pl: Variant in zd.get("places", []):
		if pl is Dictionary and String((pl as Dictionary).get("holder", "")) != "":
			var g2: Dictionary = groups.get(String((pl as Dictionary).holder), {})
			if not g2.is_empty() and bool(g2.get("alive", true)) and not (g2.get("members", []) as Array).is_empty() and (pl as Dictionary).get("pos") is Array:
				var pp: Array = (pl as Dictionary).pos
				_quiet.append(Vector2(float(pp[0]), float(pp[pp.size() - 1])))
	return _quiet


## Whether `pos` (Vector3, or Vector2 x/z) is within QUIET_M of a place living people hold.
static func in_quiet(pos: Variant) -> bool:
	var at := Vector2((pos as Vector3).x, (pos as Vector3).z) if pos is Vector3 else (pos as Vector2)
	for q: Vector2 in quiet_places():
		if q.distance_to(at) <= QUIET_M:
			return true
	return false


static func data() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


# --- Pacing -------------------------------------------------------------------------------------

## Whether the first nights are softened (the "dead" option below High).
static func softened() -> bool:
	return Survival.option("dead") != "high"


## Whether it's still the first day or night (day 1, or day 2 before FIRST_NIGHT_END_H).
static func first_night() -> bool:
	var d := Survival.day()
	return d <= 1 or (d == 2 and Survival.hour() < FIRST_NIGHT_END_H)


## Whether a horde may form now (the pressure's, a siege's, one walking in).
static func horde_allowed() -> bool:
	return not softened() or not first_night()


## Which night it is (the evening of day N and the small hours after it are night N).
static func night_index() -> int:
	return Survival.day() if Survival.hour() >= 12.0 else Survival.day() - 1


## The share of the dead's night pace bonus that applies tonight (ZombieAI.pace).
static func night_bonus_share() -> float:
	if not softened():
		return 1.0
	var n := night_index()
	if n <= 1:
		return NIGHT_SHARE[0]
	if n == 2:
		return NIGHT_SHARE[1]
	return 1.0


# --- The thread ---------------------------------------------------------------------------------

## Host: a new world's first-day thread (ColdOpen.server_begin, once): the well, the shed and its
## weapon, the build kit by the stove, the marks and the journal. Returns the note's postscript.
static func server_begin(level: SurvivalLevel, home: Vector3, gift: Array) -> String:
	var d := data()
	if d.has("goals"):
		return ""
	var st := Survival.state()
	var zone := String(st.get("zone", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["first_hour", int(st.get("seed", 0))])
	var well_v: Variant = farm_point(level, "well")
	if well_v == null:
		well_v = find_well(level, home)
	var well := level.ground_point(home + WELL_FALLBACK) if well_v == null else (well_v as Vector3)
	var barn_v: Variant = farm_point(level, "barn")
	var shed := (barn_v as Vector3) if barn_v is Vector3 else _shed_spot(level, home, rng)
	var inside_v: Variant = farm_point(level, "inside")
	var stove := (inside_v as Vector3) if inside_v is Vector3 else home
	var gift_ids: Array[String] = []
	for e: Array in gift:
		gift_ids.append(String(e[0]))
	var weapon := ""
	for w: String in WEAPONS:
		if not w in gift_ids and ItemDB.get_item(StringName(w)) != null:
			weapon = w
			break
	if weapon != "":
		level.server_spawn_dropped(StringName(weapon), 1, shed + Vector3.UP * 0.5)
	var k := 0
	for e: Array in BUILD_KIT:
		if ItemDB.get_item(StringName(String(e[0]))) != null:
			level.server_spawn_dropped(StringName(String(e[0])), int(e[1]), stove + Vector3(-1.0 - 0.5 * k, 0.5, -1.0))
			k += 1
	d.merge({"home": _arr(home), "well": _arr(well), "well_prop": well_v != null, "shed": _arr(shed), "weapon": weapon, "voice_pid": "",
		"goals": {"water": {"open": true, "done": false}, "weapon": {"open": true, "done": false}, "shelter": {"open": true, "done": false},
			"voice": {"open": false, "done": false}}}, true)
	SurvivalMap.server_add_mark(zone, well, "The well (water)", "goal")
	SurvivalMap.server_add_mark(zone, shed, "The barn (tools)" if barn_v is Vector3 else "The shed (tools)", "goal")
	SurvivalMap.server_add_mark(zone, home + Vector3(0.0, 0.0, 3.0), "Board up the farmhouse", "goal")
	Survival._journal_line("Three things before dark, the way the note has it: water from the well, something better than this knife from the shed, and boards over the windows.")
	SessionLog.note("survival: first hour: well %s (%s), shed %s with %s" % [str(well), "a well" if well_v != null else "fallback", str(shed), weapon])
	return "P.S. The well in the yard still draws. Tools in the %s. Planks by the stove: board the windows before dark, they come at night." % ("barn" if barn_v is Vector3 else "shed up the track")


## The nearest well, cistern, trough or windpump prop within WELL_FIND_M of `home`, or null.
static func find_well(level: ZoneLevel, home: Vector3) -> Variant:
	if level == null or level.scatter == null:
		return null
	var best: Variant = null
	var best_d := WELL_FIND_M
	for it: Dictionary in level.scatter.items:
		if int(it.get("kind", -1)) != ZoneScatter.Kind.PROP or not String(it.get("shape", "")) in WELL_SHAPES:
			continue
		var p: Vector3 = it.pos
		var dd := Vector2(p.x - home.x, p.z - home.z).length()
		if dd < best_d:
			best_d = dd
			best = p
	return best


static func _shed_spot(level: SurvivalLevel, home: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var zone := String(Survival.state().get("zone", ""))
	var best := Vector2.INF
	var best_d := INF
	for l: Dictionary in Landmarks.of(zone):
		if not String(l.get("kind", "")) in SHED_KINDS:
			continue
		var p: Vector2 = l.pos
		var dd := p.distance_to(Vector2(home.x, home.z))
		if dd >= SHED_M.x and dd <= SHED_M.y and dd < best_d:
			best_d = dd
			best = p
	if best_d == INF:
		var a := rng.randf() * TAU
		return level.ground_point(home + Vector3(cos(a), 0.0, sin(a)) * SHED_FALLBACK_M)
	return level.ground_point(Vector3(best.x + 3.0, home.y, best.y + 3.0))


static func goal(id: String) -> Dictionary:
	return (data().get("goals", {}) as Dictionary).get(id, {})


static func is_done(id: String) -> bool:
	return bool(goal(id).get("done", false))


static func is_open(id: String) -> bool:
	var g := goal(id)
	return bool(g.get("open", false)) and not bool(g.get("done", false))


## Host: goal `id` done by `s` (or the first player): the reward, the journal, a line for all.
## Returns whether it completed now.
static func server_complete(level: Node, id: String, s: Soldier = null) -> bool:
	if not is_open(id):
		return false
	var g := goal(id)
	g["done"] = true
	g["day"] = Survival.day() + Survival.hour() / 24.0
	if s == null and level:
		for p: Soldier in MapNodes.players(level):
			if not p.is_ai():
				s = p
				break
	var r: Dictionary = REWARDS.get(id, {})
	if s:
		var xp: Array = r.get("xp", [])
		if xp.size() == 2:
			Rpg.xp(s, String(xp[0]), float(xp[1]))
		Nerve.settle(Survival.needs_of(s), float(r.get("nerve", 0.0)))
		var item: Array = r.get("item", [])
		if item.size() == 2 and ItemDB.get_item(StringName(String(item[0]))) != null:
			var got := s.inventory.take(StringName(String(item[0])), int(item[1]))
			if got < int(item[1]) and level is CompoundLevel:
				(level as CompoundLevel).server_spawn_dropped(StringName(String(item[0])), int(item[1]) - got, s.global_position + Vector3.UP * 0.5)
	var line := String(r.get("line", ""))
	if id == "voice":
		var rec: Dictionary = (Survival.state().get("people", {}) as Dictionary).get(String(data().get("voice_pid", "")), {})
		line = line % String(rec.get("first", rec.get("name", "Someone")))
	if line != "":
		Survival._journal_line(line)
	if level:
		for p: Soldier in MapNodes.players(level):
			Survival._tell(p, "Done: %s" % String(TITLES.get(id, id)))
	SessionLog.note("survival: first hour: %s done" % id)
	return true


## Host: someone drank or filled a bottle (Fieldwork's drink and fill).
static func server_on_water(s: Soldier) -> void:
	server_complete(CompoundLevel.current(s), "water", s)


## Whether `s` carries a melee weapon better than a knife.
static func has_better_weapon(s: Soldier) -> bool:
	for e: Dictionary in Survival.kit_of(s.inventory):
		var item := ItemDB.get_item(StringName(String(e.get("id", ""))))
		if MeleeWeapons.is_melee(item) and not "knife" in item.tags:
			return true
	return false


## Whether the farmhouse is boarded: a shutter, door, gate, hatch or fence built within SHELTER_M
## of it, or SHELTER_BLOCKS blocks.
static func shelter_built(level: Node) -> bool:
	var b := Builder.of(level)
	if b == null or not data().has("home"):
		return false
	var home := _v3(data().home)
	for id: int in b.pieces:
		var rec: Dictionary = b.pieces[id]
		if String(rec.get("k", "")) in SHELTER_PIECES and b.is_piece_built(id):
			var c := Vector3i(int(rec.c[0]), int(rec.c[1]), int(rec.c[2]))
			if BuildPieces.cell_centre(c).distance_to(home) <= SHELTER_M:
				return true
	var n := 0
	for c: Vector3i in b.blocks:
		if b.is_built(c) and BuildPieces.cell_centre(c).distance_to(home) <= SHELTER_M:
			n += 1
			if n >= SHELTER_BLOCKS:
				return true
	return false


## Host: day 2's voice on the farm's old set: a lone survivor placed by a landmark, marked.
static func server_start_voice(level: SurvivalLevel) -> Dictionary:
	var d := data()
	if not d.has("goals") or bool(goal("voice").get("open", false)) or is_done("voice"):
		return {}
	var layer := SurvivorsLayer.find(level)
	if layer == null:
		return {}
	var home := _v3(d.home)
	var zone := String(Survival.state().get("zone", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["first_hour_voice", int(Survival.state().get("seed", 0))])
	var spots: Array[Vector2] = []
	for l: Dictionary in Landmarks.of(zone):
		var p: Vector2 = l.pos
		var dd := p.distance_to(Vector2(home.x, home.z))
		if dd >= VOICE_M.x and dd <= VOICE_M.y:
			spots.append(p)
	var at := Vector3.ZERO
	if spots.is_empty():
		var a := rng.randf() * TAU
		at = level.ground_point(home + Vector3(cos(a), 0.0, sin(a)) * VOICE_FALLBACK_M)
	else:
		var p2: Vector2 = spots[rng.randi() % spots.size()]
		at = level.ground_point(Vector3(p2.x + 5.0, home.y, p2.y + 5.0))
	var rec := layer.server_add_person(at, {"want": {"kind": "place"}, "disposition": "friendly", "traits": ["kind", "loyal"]})
	d["voice_pid"] = String(rec.get("id", ""))
	(goal("voice") as Dictionary)["open"] = true
	var near := Landmarks.nearest_name(at, zone)
	d["voice_near"] = near
	SurvivalMap.server_add_mark(zone, at, "The voice on the radio (%s)" % String(rec.get("first", "")), "radio")
	Survival._journal_line("Day 2. The old set in the kitchen crackled: %s, alone, holed up near %s, asking if anyone is out there. %s said they'd wait." % [
		String(rec.get("name", "someone")), near if near != "" else "the farm", "She" if String(rec.get("sex", "m")) == "f" else "He"])
	for p: Soldier in MapNodes.players(level):
		Survival._tell(p, "The old radio in the kitchen crackles: someone's out there")
	var sm := SurvivalMap.of(level)
	if sm:
		sm.server_changed()
	return rec


## Host, every survival tick (Survival._process): the goals that complete by being so, day 2's
## voice, the landmarks visited, the hints.
static func server_tick(level: SurvivalLevel) -> void:
	if level == null:
		return
	var d := data()
	if d.has("goals"):
		for p: Soldier in MapNodes.players(level):
			if not p.is_ai() and is_open("weapon") and has_better_weapon(p):
				server_complete(level, "weapon", p)
		if is_open("shelter") and shelter_built(level):
			server_complete(level, "shelter")
		if not bool(goal("voice").get("open", false)) and not is_done("voice") and (Survival.day() > VOICE_DAY or (Survival.day() == VOICE_DAY and Survival.hour() >= VOICE_HOUR)):
			server_start_voice(level)
		if is_open("voice"):
			var rec: Dictionary = (Survival.state().get("people", {}) as Dictionary).get(String(d.get("voice_pid", "")), {})
			if String(rec.get("status", "")) in ["companion", "settler"]:
				server_complete(level, "voice")
	_visit(level)
	_hint_tick(level)


# --- Now: the journal's front page and the map's "?" ----------------------------------------------

## The open goals as the journal's front page lines.
static func now_lines() -> Array:
	var out: Array = []
	if not data().has("goals"):
		return out
	for id: String in GOALS:
		if not is_open(id):
			continue
		var t := String(TODO.get(id, ""))
		match id:
			"water":
				t = t % FieldHints.key_name("context")
			"shelter":
				t = t % FieldHints.key_name("build_mode")
			"voice":
				t = t % String(data().get("voice_near", "the mark"))
		out.append("%s: %s" % [String(TITLES[id]), t])
	var done := GOALS.filter(func(g: String) -> bool: return is_done(g)).size()
	if done > 0:
		out.append("%d of %d done" % [done, GOALS.size()])
	return out


## The landmarks of `zone` visited (name -> day), as this peer sees the map.
static func visited(zone: String) -> Dictionary:
	var all: Variant = SurvivalMap.view().get("visited", {})
	if not all is Dictionary:
		return {}
	var z: Variant = (all as Dictionary).get(zone, {})
	return z if z is Dictionary else {}


static func is_visited(zone: String, name: String) -> bool:
	return visited(zone).has(name)


## The landmark of `zone` nearest `from` not yet visited: {"name", "m", "side"} or {}.
static func nearest_unvisited(zone: String, from: Vector3) -> Dictionary:
	var at := Vector2(from.x, from.z)
	var best := {}
	var best_d := INF
	var seen := visited(zone)
	for l: Dictionary in Landmarks.of(zone):
		if seen.has(String(l.name)):
			continue
		var dd := (l.pos as Vector2).distance_to(at)
		if dd < best_d:
			best_d = dd
			best = {"name": String(l.name), "m": dd, "side": Landmarks.side_of((l.pos as Vector2) - at)}
	return best


## "Not yet seen: the water tower, 420 m north" ("" when every landmark is visited).
static func unvisited_line(zone: String, from: Vector3) -> String:
	var n := nearest_unvisited(zone, from)
	if n.is_empty():
		return ""
	return "Nearest place not yet seen: %s, %d m %s" % [String(n.name), snappedi(int(n.m), 10), String(n.side)]


## Host: landmarks within VISIT_M of a survivor become visited (the map's section, sent on).
static func _visit(level: SurvivalLevel) -> void:
	var zone := String(Survival.state().get("zone", ""))
	if zone == "":
		return
	var sec := SurvivalMap.section()
	if not sec.get("visited") is Dictionary:
		sec["visited"] = {}
	var all: Dictionary = sec.visited
	if not all.get(zone) is Dictionary:
		all[zone] = {}
	var seen: Dictionary = all[zone]
	var fresh := false
	for p: Soldier in MapNodes.players(level):
		if not p.vitals.is_up():
			continue
		var at := Vector2(p.global_position.x, p.global_position.z)
		for l: Dictionary in Landmarks.of(zone):
			if not seen.has(String(l.name)) and (l.pos as Vector2).distance_to(at) <= VISIT_M:
				seen[String(l.name)] = Survival.day() + Survival.hour() / 24.0
				fresh = true
	if fresh:
		var sm := SurvivalMap.of(level)
		if sm:
			sm.server_changed()


# --- Water at the well ------------------------------------------------------------------------------

## The water source at `at` the thread knows ("well" at the farm's well or a well-like prop within
## WELL_PICK_M; "" none).
static func source_at(level: Node, at: Vector3) -> String:
	if not at.is_finite():
		return ""
	var d := data()
	if d.has("well") and Vector2(at.x, at.z).distance_to(_v2(d.well)) <= WELL_PICK_M:
		return "well"
	var zl := level as ZoneLevel
	if zl == null or zl.scatter == null:
		return ""
	for it: Dictionary in zl.scatter.items:
		if int(it.get("kind", -1)) == ZoneScatter.Kind.PROP and String(it.get("shape", "")) in WELL_SHAPES:
			var p: Vector3 = it.pos
			if Vector2(p.x - at.x, p.z - at.z).length() <= WELL_PICK_M:
				return "well"
	return ""


## The water's quality at `source` here: the farm's well is dirty while the cold open's "well gone
## bad" holds; else WaterWorks'.
static func quality(source: String, at: Vector3) -> String:
	var d := data()
	if source == "well" and bool(Survival.state().get("well_bad", false)) and d.has("well") and Vector2(at.x, at.z).distance_to(_v2(d.well)) <= WELL_PICK_M + 2.0:
		return "dirty" if WaterWorks.quality(source) != "" else ""
	return WaterWorks.quality(source, String(Survival.state().get("zone", "")))


# --- Hints (FieldHints) -------------------------------------------------------------------------------

## Host: each human survivor's situations; a hint not yet sent this session goes to his owner.
static func _hint_tick(level: SurvivalLevel) -> void:
	for p: Soldier in MapNodes.players(level):
		if p.is_ai() or not p.vitals.is_up():
			continue
		var prof := Survival.profile_of(p)
		if not _sent.get(prof) is Dictionary:
			_sent[prof] = {}
		var sent: Dictionary = _sent[prof]
		for id: String in FieldHints.ORDER:
			if sent.has(id) or not situation(level, p, id):
				continue
			sent[id] = true
			Survival.server_hint(p, id)


## Host: whether hint `id`'s situation holds for `s` now.
static func situation(level: SurvivalLevel, s: Soldier, id: String) -> bool:
	match id:
		"silent_kill":
			for z: Soldier in Survival.zombies(level):
				var brain := ZombieAI.of(z)
				if brain and z.vitals.is_up() and brain.unaware() and z.global_position.distance_to(s.global_position) <= SILENT_HINT_M:
					return true
		"melee":
			return MeleeWeapons.is_melee(s.active_weapon())
		"night":
			return DayNight.night_of(Survival.hour()) > 0.5
		"container":
			for c: Node in s.get_tree().get_nodes_in_group(WorldCache.GROUP):
				if c is Node3D and (c as Node3D).global_position.distance_to(s.global_position) <= CONTAINER_HINT_M:
					return true
		"load_mags":
			return _rounds_and_mag(s)
		"injury":
			return Assists.hint_for(s) != ""
		"companion":
			var layer := SurvivorsLayer.find(level)
			return layer != null and not layer.companions().is_empty()
		"build_kit":
			for mat: String in BuildPieces.MATERIALS:
				if s.inventory.count_of(StringName(String((BuildPieces.MATERIALS[mat] as Dictionary).get("item", "")))) > 0:
					return true
		"hungry":
			var n := Survival.needs_of(s)
			return float(n.get("hunger", 100.0)) < LOW_NEED or float(n.get("thirst", 100.0)) < LOW_NEED
	return false


## Whether `s` carries loose rounds and a magazine of the same calibre.
static func _rounds_and_mag(s: Soldier) -> bool:
	var loose := {}
	var mags := {}
	for e: Dictionary in Survival.kit_of(s.inventory):
		var item := ItemDB.get_item(StringName(String(e.get("id", ""))))
		if item == null or item.type != "ammo":
			continue
		var cal := String(item.stats.get("calibre", ""))
		if bool(item.stats.get("loose", false)):
			loose[cal] = true
		elif item.stats.has("rounds"):
			mags[cal] = true
	for cal: String in loose:
		if mags.has(cal):
			return true
	return false


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _v2(a: Variant) -> Vector2:
	var v := _v3(a)
	return Vector2(v.x, v.z)


# --- Noise draws the dead that are there (the Captain: "guns shouldn't pull zombies constantly") --

## Proposed: a noise raises the zone's pressure only by the population it can draw on: a site's
## share by its base type (SITE_NOISE; DEAD_NEAR's bigger sites more) within DRAW_SITE_M, a nest
## within DRAW_SITE_M, else OPEN_NOISE_SHARE; nothing in a quiet place. The crowd heads drift to
## the pressure point only from within DRIFT_REACH_M of it, and a shot pulls the heads within its
## heard radius + HEARD_MARGIN_M straight at it. A horde forms only with a town, city, village or a
## nest within HORDE_SITE_M of the point. New dead about a survivor are capped per CELL_M area per
## world hour (AREA_CAP_OPEN in the open; at a site twice its dead_near).
const SITE_NOISE := {"city": 1.0, "town": 1.0, "village": 0.8, "compound": 0.6, "hq": 0.6, "qrf_base": 0.6, "outpost": 0.5,
	"checkpoint": 0.5, "farm": 0.3}
const OPEN_NOISE_SHARE := 0.08
const DRAW_SITE_M := 300.0
const DRIFT_REACH_M := 300.0
const HEARD_MARGIN_M := 50.0
const HORDE_SITES: Array[String] = ["city", "town", "village"]
const HORDE_SITE_M := 400.0
const AREA_CAP_OPEN := 2


## The share of a noise's pressure at `pos` (1 a town; OPEN_NOISE_SHARE the open; 0 a quiet place).
static func noise_share(level: ZoneLevel, pos: Vector3) -> float:
	if in_quiet(pos):
		return 0.0
	var best := OPEN_NOISE_SHARE
	if level:
		for m: ZoneModule in level.modules():
			if m.module_id == HOME_ID:
				continue
			var base := ZoneModules.base(String(m.type))
			if SITE_NOISE.has(base) and Vector2(m.global_position.x - pos.x, m.global_position.z - pos.z).length() <= DRAW_SITE_M:
				best = maxf(best, float(SITE_NOISE[base]))
	for rec: Variant in DeadNests.all().values():
		if rec is Dictionary and int((rec as Dictionary).get("n", 0)) > 0:
			var d := DeadNests.door(rec)
			if Vector2(d.x - pos.x, d.z - pos.z).length() <= DRAW_SITE_M:
				best = 1.0
	return best


## Whether a horde may form at `point`: a town, city or village site or a nest within HORDE_SITE_M.
static func horde_source_near(level: ZoneLevel, point: Vector3) -> bool:
	if level:
		for m: ZoneModule in level.modules():
			if ZoneModules.base(String(m.type)) in HORDE_SITES and Vector2(m.global_position.x - point.x, m.global_position.z - point.z).length() <= HORDE_SITE_M:
				return true
	for rec: Variant in DeadNests.all().values():
		if rec is Dictionary and int((rec as Dictionary).get("n", 0)) > 0:
			var d := DeadNests.door(rec)
			if Vector2(d.x - point.x, d.z - point.z).length() <= HORDE_SITE_M:
				return true
	return false
