class_name LootStates
extends RefCounted
## Loot that shows its state, for Contractor: Fallen (docs/survival_events.md; call 125). Host only,
## static; the zone's record in Survival.state()["loot_states"][zone] ({"locked": {cache uid: key
## home uid}, "keys_placed", "hidden": [{"uid", "pos", "clue", "clue_pos", "landmark", "marked"}]}),
## each cache's own state in the zone save (WorldCache.to_save: searched, searched_day, refills, pried).
##
## - Picked over: a container searched once (opened: WorldCache.server_open_for) looks it (lid up,
##   dull) on every peer and after a reload.
## - Hidden caches with clues: HIDDEN per zone by the seed, half-buried off a site, the richest loot
##   (RICH_WEIGHTS, two rolls); a note lies at another site naming the landmark nearest the cache and
##   the paces and side from it; picking the note up marks the cache's ground on the map.
## - Locked containers: up to MAX_LOCKED of a zone's boxes (LOCK_SHARE each) need their key (an "Old
##   Key", fallen_key, with "opens" its uid), put in another box of the zone; or a crowbar pries one
##   open: PRY_S and loud (PRY_NOISE_M, PRY_PRESSURE).
## - Refill only where people pass: a searched box gets a fresh small roll after REFILL_DAYS (/ the
##   "loot" option) only in a zone with living people (a world group or lone survivor in it), or the
##   settlement's zone while a settler has the scavenge job; the dead's empty quarters stay empty.
## Every number is Proposed.

const KEY := "loot_states"
const KEY_ITEM := &"fallen_key"
const PRY_TOOLS: Array[StringName] = [&"crowbar"]
const PRY_S := 6.0
const PRY_NOISE_M := 45.0
const PRY_PRESSURE := 4.0
const LOCK_SHARE := 0.25
const MAX_LOCKED := 2
const HIDDEN := Vector2i(1, 3)
const HIDDEN_LABEL := "Hidden cache"
const HIDDEN_FROM_SITE_M := Vector2(25.0, 45.0)
const RICH_WEIGHTS := {"uncommon": 1, "rare": 2}
const RICH_ROLLS := 2
const REFILL_DAYS := 3.0
## A box holding this many entries or more doesn't refill (it hasn't been emptied).
const REFILL_FULL := 2
## How far off (m) the map's mark for a found clue may be from the cache.
const CLUE_MARK_SPREAD_M := 12.0
const HIDDEN_PREFIX := "fhid_"
const CLUE_PREFIX := "fclue_"


static func section() -> Dictionary:
	var st := Survival.state()
	if not st.get(KEY) is Dictionary:
		st[KEY] = {}
	return st[KEY]


static func zone_rec(zone: String) -> Dictionary:
	var s := section()
	if not s.get(zone) is Dictionary:
		s[zone] = {}
	var r: Dictionary = s[zone]
	if not r.get("locked") is Dictionary:
		r["locked"] = {}
	return r


static func caches(level: Node) -> Array:
	var out: Array = []
	if level == null or not level.is_inside_tree():
		return out
	for c: Node in level.get_tree().get_nodes_in_group(WorldCache.GROUP):
		if c is WorldCache and level.is_ancestor_of(c) and not c.is_queued_for_deletion():
			out.append(c)
	out.sort_custom(func(a: WorldCache, b: WorldCache) -> bool: return a.uid < b.uid)
	return out


static func cache_by_uid(level: Node, uid: String) -> WorldCache:
	for c: WorldCache in caches(level):
		if c.uid == uid:
			return c
	return null


static func now() -> float:
	return Survival.day() + Survival.hour() / 24.0


# --- The zone comes up -----------------------------------------------------------------------------

## Host, once a survival zone is up and its boxes are out (SurvivalLevel._on_hosted): the hidden
## caches and their clues, the locks and their keys, the refill of boxes people passed.
static func server_zone_hosted(level: ZoneLevel) -> void:
	if level == null or not level.multiplayer.is_server():
		return
	var zone := String(Survival.state().get("zone", ""))
	server_place_hidden(level, zone)
	server_place_locks(level, zone)
	server_refill(level, zone)


## The hidden caches of `zone` (rolled once: HIDDEN by the seed, off its sites) and their clues.
static func server_place_hidden(level: ZoneLevel, zone: String) -> Array:
	var rec := zone_rec(zone)
	if not rec.get("hidden") is Array:
		rec["hidden"] = _roll_hidden(level, zone)
	var out: Array = []
	var hot := String(level.def.get("kind", "")) == "hot"
	for h: Dictionary in rec.hidden:
		var p: Array = h.pos
		var cache := cache_by_uid(level, String(h.uid))
		if cache == null and level.cache_spawner:
			cache = level.cache_spawner.spawn({"uid": String(h.uid), "pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "yaw": 0.0, "label": HIDDEN_LABEL}) as WorldCache
			if cache:
				cache.server_fill(rich_loot(String(h.uid), hot))
		if cache:
			out.append(cache)
		var clue_uid := String(h.clue)
		if not GameState.is_looted(clue_uid) and level.items.get_node_or_null(NodePath(clue_uid)) == null:
			var cp: Array = h.clue_pos
			level.spawn_item(&"handwritten_note", 1, Vector3(float(cp[0]), float(cp[1]) + 0.4, float(cp[2])), clue_uid, {"text": String(h.text), "clue": String(h.uid)})
	return out


static func _roll_hidden(level: ZoneLevel, zone: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(Survival.state().get("seed", 0)), zone, "hidden"])
	var sites: Array = []
	for m: ZoneModule in level.modules():
		sites.append(m.global_position)
	if sites.is_empty():
		for pt: Vector3 in level.insertion_points():
			sites.append(pt)
	var out: Array = []
	if sites.is_empty():
		return out
	var n := rng.randi_range(HIDDEN.x, HIDDEN.y)
	for i in n:
		var site: Vector3 = sites[rng.randi_range(0, sites.size() - 1)]
		var a := rng.randf() * TAU
		var at := level.ground_point(site + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(HIDDEN_FROM_SITE_M.x, HIDDEN_FROM_SITE_M.y))
		var other: Vector3 = sites[(sites.find(site) + 1 + rng.randi_range(0, maxi(0, sites.size() - 2))) % sites.size()]
		var clue_at := level.ground_point(other + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0)))
		var lm := Landmarks.nearest(at, zone)
		var lm_name := String(lm.get("name", "the road"))
		var text := clue_text(at, lm, rng)
		out.append({"uid": "%s%s_%d" % [HIDDEN_PREFIX, zone, i], "pos": [at.x, at.y, at.z], "clue": "%s%s_%d" % [CLUE_PREFIX, zone, i],
			"clue_pos": [clue_at.x, clue_at.y, clue_at.z], "landmark": lm_name, "text": text})
	return out


## A clue's words: the landmark nearest the cache and the paces from it (a pace ~PACE_M, rounded to
## 5): "...: 40 paces north and 15 east of the water tower. Under the loose earth."
const PACE_M := 0.75


static func clue_text(at: Vector3, landmark: Dictionary, rng: RandomNumberGenerator) -> String:
	var lm_name := String(landmark.get("name", ""))
	if lm_name == "" or not landmark.get("pos") is Vector2:
		return "We buried what we couldn't carry, a little way off the road. Come back for it."
	var d := Vector2(at.x, at.z) - (landmark.pos as Vector2)
	var ns := roundi(absf(d.y) / PACE_M / 5.0) * 5
	var ew := roundi(absf(d.x) / PACE_M / 5.0) * 5
	var openers: Array[String] = ["We buried what we couldn't carry", "Left the good stuff in the ground", "Our stash, if we don't come back"]
	return "%s: %d paces %s and %d %s of %s. Under the loose earth." % [openers[rng.randi_range(0, openers.size() - 1)], ns,
		"north" if d.y < 0.0 else "south", ew, "east" if d.x > 0.0 else "west", lm_name]


## Where a clue's words point (the landmark's point plus the paces), on `zone`'s ground (x, z); null
## if it names nothing known there.
static func clue_target(text: String, zone: String) -> Variant:
	var step := {"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0)}
	for l: Dictionary in Landmarks.of(zone):
		if not text.ends_with(" of %s. Under the loose earth." % String(l.name)):
			continue
		var words := text.split(" ")
		var at: Vector2 = l.pos
		for i in words.size():
			if words[i] == "paces" and i >= 1 and i + 4 < words.size():
				at += (step.get(words[i + 1], Vector2.ZERO) as Vector2) * words[i - 1].to_int() * PACE_M
				at += (step.get(words[i + 4], Vector2.ZERO) as Vector2) * words[i + 3].to_int() * PACE_M
		return at
	return null


## A hidden cache's loot: RICH_ROLLS rolls of the field cache's table at RICH_WEIGHTS (the richest
## boxes in a zone), the same every time.
static func rich_loot(uid: String, hot: bool) -> Array:
	var pool: Dictionary = (WorldValuables.loot_data().get("pools", {}) as Dictionary).get("field_cache", {})
	var table := String(pool.get("table", ""))
	var out: Array = []
	if table == "":
		return out
	for i in RICH_ROLLS:
		out.append_array(WorldValuables.roll_box(table, RICH_WEIGHTS, "%s|rich%d" % [uid, i], hot).items)
	return out


## The locks of `zone` (rolled once) applied to its boxes; each lock's key put in another box the
## first time (the zone save keeps it there after).
static func server_place_locks(level: ZoneLevel, zone: String) -> Array:
	var rec := zone_rec(zone)
	var all := caches(level)
	if not bool(rec.get("locks_rolled", false)):
		rec["locks_rolled"] = true
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(Survival.state().get("seed", 0)), zone, "locks"])
		var open: Array = all.filter(func(c: WorldCache) -> bool: return lockable(c))
		for c: WorldCache in open:
			if (rec.locked as Dictionary).size() >= MAX_LOCKED:
				break
			if rng.randf() < LOCK_SHARE:
				(rec.locked as Dictionary)[c.uid] = ""
		for uid: String in (rec.locked as Dictionary).keys():
			var homes: Array = open.filter(func(c: WorldCache) -> bool: return c.uid != uid and not (rec.locked as Dictionary).has(c.uid))
			if homes.is_empty():
				continue
			var home: WorldCache = homes[rng.randi_range(0, homes.size() - 1)]
			home.server_seed([{"id": String(KEY_ITEM), "count": 1, "state": {"opens": uid}}])
			(rec.locked as Dictionary)[uid] = home.uid
	var out: Array = []
	for uid: String in (rec.locked as Dictionary).keys():
		var c := cache_by_uid(level, uid)
		if c:
			c.key_id = KEY_ITEM
			c.unlocked = bool((GameState.caches.get(uid, {}) as Dictionary).get("unlocked", false))
			out.append(c)
	return out


## Whether `c` may be locked: an ordinary box (not a strongbox, a live event's, a hidden cache).
static func lockable(c: WorldCache) -> bool:
	return c.key_id == &"" and not c.hidden and not c.uid.begins_with(WorldEvents.CACHE_PREFIX) and not c.uid.begins_with(HIDDEN_PREFIX)


# --- Keys and the pry ------------------------------------------------------------------------------

## Whether `actor` carries the key made for `cache` (a fallen_key whose "opens" is its uid).
static func has_key_for(actor: Soldier, cache: WorldCache) -> bool:
	if actor == null:
		return false
	for c: StringName in actor.inventory.containers:
		for e: Dictionary in actor.inventory.containers[c]:
			if StringName(String(e.get("id", ""))) == KEY_ITEM and String((e.get("state", {}) as Dictionary).get("opens", "")) == cache.uid:
				return true
	return false


static func has_pry_tool(actor: Soldier) -> bool:
	if actor == null:
		return false
	var inv := actor.inventory
	for t: StringName in PRY_TOOLS:
		if inv.count_of(t) > 0 or inv.slots.values().has(t) or inv.hands == t:
			return true
	return false


## Host: `actor` sets a crowbar to the locked `cache`: loud at once (the dead hear it), open after
## `seconds` if he's still at it. Returns why not ("" started).
static func server_start_pry(cache: WorldCache, actor: Soldier, seconds := PRY_S) -> String:
	if cache == null or actor == null or not cache.is_locked():
		return "It isn't locked"
	if not has_pry_tool(actor):
		return "You need a crowbar"
	if not cache.in_reach(actor):
		return "Too far away"
	var level := CompoundLevel.current(cache)
	_pry_noise(level, cache)
	Survival._tell(actor, "You set the crowbar to it...")
	if seconds <= 0.0:
		_pried(cache, actor)
	else:
		cache.get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if is_instance_valid(cache) and is_instance_valid(actor) and cache.in_reach(actor) and actor.vitals.is_up():
				_pried(cache, actor)
			elif is_instance_valid(actor):
				Survival._tell(actor, "You let the crowbar go"))
	return ""


static func _pried(cache: WorldCache, actor: Soldier) -> void:
	cache.unlocked = true
	cache.pried = true
	_pry_noise(CompoundLevel.current(cache), cache)
	Survival._tell(actor, "The lock gives with a crack")


static func _pry_noise(level: Node, cache: WorldCache) -> void:
	if level == null:
		return
	Survival.server_noise(level, cache.global_position, PRY_NOISE_M, 0.7)
	if level is ZoneLevel:
		Survival._raise_pressure(level, cache.global_position, PRY_PRESSURE)


# --- Searching and refilling -------------------------------------------------------------------------

## Host: `cache` opened by `actor` the first time since it was last stocked: picked over from now on;
## a live event's cache tells WorldEvents (a claim, a robbery).
static func server_on_open(cache: WorldCache, actor: Soldier) -> void:
	cache.searched = true
	cache.searched_day = now() if Survival.running else 0.0
	if cache.uid.begins_with(WorldEvents.CACHE_PREFIX) and Survival.running:
		WorldEvents.server_cache_opened(cache, actor)
	if cache.hidden and Survival.running:
		Intel.journal("%s dug up a hidden cache." % Survival.survivor_name(actor) if actor else "Someone dug up a hidden cache.", "loot")


## Whether people pass through `zone` (its boxes refill): a living world group or lone survivor in
## it, or it's the settlement's zone and a settler scavenges. The dead's empty quarters: no.
static func people_pass(zone: String) -> bool:
	for g: Dictionary in WorldSim.groups_in(zone):
		if not (g.get("members", []) as Array).is_empty() or String(g.get("kind", "")) == "lone":
			return true
	if Settlement.exists() and Settlement.zone() == zone:
		for rec: Dictionary in WorldSim.people().values():
			if String(rec.get("status", "")) == "settler" and "scavenge" in Settlement.jobs_of(rec):
				return true
	return false


## Host: the searched, emptied boxes of `zone` (in `level`) restocked when REFILL_DAYS (/ the loot
## option) have passed and people pass there; never a hidden cache, a live event's or a locked one.
## `at` is the world day to judge by (now). Returns how many refilled.
static func server_refill(level: Node, zone: String, at := -1.0) -> int:
	if at < 0.0:
		at = now()
	if not people_pass(zone):
		return 0
	var days := REFILL_DAYS / maxf(0.1, Survival.option_mult("loot"))
	var n := 0
	for c: WorldCache in caches(level):
		if not c.searched or c.hidden or c.is_locked() or c.uid.begins_with(WorldEvents.CACHE_PREFIX) or c.uid.begins_with(HIDDEN_PREFIX):
			continue
		if at - c.searched_day < days or c.cargo_hold.entries().size() >= REFILL_FULL:
			continue
		c.refills += 1
		c.server_seed(WorldValuables.pool_roll("field_cache", "%s|refill%d|%d" % [c.uid, c.refills, int(Survival.state().get("seed", 0))], false).items)
		c.searched = false
		c.searched_day = at
		n += 1
	return n


## Host, every couple of seconds (CoopFallen's tick): a clue note picked up marks its cache's ground
## on the map (once) and goes in the journal.
static func server_tick(level: Node) -> void:
	var zone := String(Survival.state().get("zone", ""))
	var rec: Dictionary = section().get(zone, {})
	for h: Dictionary in rec.get("hidden", []):
		if bool(h.get("marked", false)) or not GameState.is_looted(String(h.clue)):
			continue
		h["marked"] = true
		var p: Array = h.pos
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([String(h.uid), "mark"])
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.0, CLUE_MARK_SPREAD_M)
		var m := SurvivalMap.server_add_mark(zone, [float(p[0]) + off.x, float(p[2]) + off.y], "A cache? (a note)", "note")
		m["teller"] = "a note"
		Intel.journal("A note: \"%s\"" % String(h.text), "loot", "a note")
		Intel._server_map_changed()
	if level == null:
		return
