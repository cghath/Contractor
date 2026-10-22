class_name SidePicture
extends RefCounted
## What one side knows (docs/combined_arms.md 3.2, phase B1): contact reports that reach it over
## the radio after the sender's delay, merged into entries that age, and its own vehicles and
## groups by Blue Force Tracker. Nothing here reads a true position: every entry is built from
## reports, and every report says who sent it (the fairness rule: tests/side_command_test.gd
## traces every entry and every map marker back to a report in `received`).
##
## A report: {"id", "kind" (KINDS), "count", "pos": Vector3, "unc0" (m when seen: by how it was
## seen, base_uncertainty_m), "heading" (degrees, 0 north), "speed" (m/s), "seen_at",
## "reported_at" (when it reached the picture), "by" (the group or player that sent it),
## "confidence" (0..1), "source" ("squad", "tag", "report", "lase", "lookout", "alert"), and
## optionally "cp" (EnemyCommand's fog: what the sender thought it was worth), "noise" (heard
## only: kept in `received` for EnemyCommand, never an entry) and "tag_names" (a tag's target).
##
## An entry: {"id", "kind", "count", "pos", "unc", "unc_at" (the uncertainty then; it grows from
## there: uncertainty()), "heading", "speed", "seen_at", "reported_at", "by", "confidence",
## "reports": [report ids, the freshest last], "tag" (from a player's tag), "tag_names", "rev"}.
##
## - Latency: submit() with the sender's delay (delay_s: by side profile and the reporter's
##   skill, x comms_down_mult with comms down); a report whose sender dies before it's due dies
##   with him (`alive`).
## - Merging: a report joins an entry of its kind within merge_m (infantry 25, vehicles 60) seen
##   in the last merge_window_s: count the higher, position the fresher, uncertainty the smaller.
##   Candidates come from a hash_m spatial hash (3.8: 64 m).
## - Ageing: uncertainty grows from the sighting (1.5 m/s infantry, 5 vehicles, capped at 600);
##   an entry goes drop_s after its last report (10 min, 15 for vehicles); band(): fresh, aged,
##   stale (30 s, 3 min).
## - BFT: `bft` holds the side's own vehicles (true positions while their radio works, grey and
##   frozen once it's out) and its groups by their last sitrep.
## Pure apart from the data file: the host's owner (SideIntel, EnemyCommand) passes the time.
## Every number in data/side_picture.json, Proposed.

const PATH := "res://data/side_picture.json"
const INFANTRY_KINDS: Array[String] = ["inf", "mg", "at", "sniper"]
const VEHICLE_KINDS: Array[String] = ["soft_vehicle", "light_armour", "ifv", "mbt", "static_gun", "mortar", "air"]
const BANDS: Array[String] = ["fresh", "aged", "stale"]
## Drop this many reports at a time once `received` is over its cap (pruning is a copy).
const PRUNE_BATCH := 32
## A full picture looks this far down its entries for the one to drop.
const DROP_SAMPLE := 8

static var _data := {}

var side: StringName
## The latency profile (data "latency_s" key): regular, concord, irregular, insurgent.
var profile := "insurgent"
## The side's net is down (dead relay, a jammer; the hostile's mast: Alert.comms_down): new
## reports take comms_down_mult longer.
var comms_down := false
var comms_why := ""
var entries: Array[Dictionary] = []
## Every report that reached the picture, oldest first (kept log_keep_s, at most max_log).
var received: Array[Dictionary] = []
## Reports on their way: {"due", "report", "alive": Callable}.
var pending: Array[Dictionary] = []
## Blue Force Tracker: key -> {"key", "what": "vehicle" or "group", "pos", "at", "grey", "label"}.
var bft := {}
## Most reports kept in `received` (0: data max_log). EnemyCommand keeps more: its fog read every
## report of the last LKP_FRESH_S before B1, and still does.
var max_received := 0
## Bumped on any change to `entries` (SideIntel sends only what changed).
var revision := 0
## The last step()'s cost (µs): the budget is 0.3 ms per side.
var step_usec := 0
var _hash := {}  # Vector2i cell -> Array[Dictionary] entries
var _next_report := 1
var _next_entry := 1
# The data's numbers, read once (the merge and the step run often).
var _merge_inf := 25.0
var _merge_veh := 60.0
var _window := 60.0
var _rate_inf := 1.5
var _rate_veh := 5.0
var _cap := 600.0
var _drop_inf := 600.0
var _drop_veh := 900.0
var _cell_m := 64.0
var _max_entries := 64
var _keep_s := 900.0
var _vehicle := {}


func _init(p_side: StringName = &"friendly", p_profile := "") -> void:
	side = p_side
	profile = p_profile if p_profile != "" else profile_of(p_side)
	_merge_inf = merge_m("inf")
	_merge_veh = merge_m("mbt")
	_window = num("merge_window_s", 60.0)
	_rate_inf = _by_class("uncertainty_mps", "inf", 1.5)
	_rate_veh = _by_class("uncertainty_mps", "mbt", 5.0)
	_cap = num("uncertainty_max_m", 600.0)
	_drop_inf = drop_s("inf")
	_drop_veh = drop_s("mbt")
	_cell_m = num("hash_m", 64.0)
	_max_entries = int(num("max_entries", 64))
	_keep_s = num("log_keep_s", 900.0)
	for k in VEHICLE_KINDS:
		_vehicle[k] = true


# --- Data ----------------------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		_data = parsed if parsed is Dictionary else {"_missing": true}
	return _data


static func num(key: String, fallback := 0.0) -> float:
	return float(data().get(key, fallback))


static func _by_class(key: String, kind: String, fallback: float) -> float:
	var table: Dictionary = data().get(key, {})
	return float(table.get("vehicle" if is_vehicle_kind(kind) else "infantry", fallback))


## The latency profile of a faction (a factions.json id, or "friendly"/"hostile").
static func profile_of(faction: StringName) -> String:
	return String((data().get("faction_profile", {}) as Dictionary).get(String(faction), "insurgent"))


## Seconds from a sighting to the picture: lerp(slow, fast) by `skill` 0..1 (the reporting
## leader's skill; an insurgent's discipline), x under_fire_mult under fire where the profile has
## one, x comms_down_mult with comms down.
static func delay_s(p_profile: String, skill: float, under_fire := false, p_comms_down := false) -> float:
	var table: Dictionary = data().get("latency_s", {})
	var p: Dictionary = table.get(p_profile, table.get("insurgent", {"slow": 60.0, "fast": 15.0}))
	var d := lerpf(float(p.get("slow", 60.0)), float(p.get("fast", 15.0)), clampf(skill, 0.0, 1.0))
	if under_fire:
		d *= float(p.get("under_fire_mult", 1.0))
	if p_comms_down:
		d *= num("comms_down_mult", 3.0)
	return d


## Whether a side's groups carry a radio set without one in their kit (profile "issued").
static func issued_radio(p_profile: String) -> bool:
	return bool(((data().get("latency_s", {}) as Dictionary).get(p_profile, {}) as Dictionary).get("issued", false))


static func is_vehicle_kind(kind: String) -> bool:
	return kind in VEHICLE_KINDS


static func merge_m(kind: String) -> float:
	return _by_class("merge_m", kind, 25.0)


static func drop_s(kind: String) -> float:
	return _by_class("drop_s", kind, 600.0)


## Uncertainty (m) `age` s after it was `unc` m, for `kind`.
static func uncertainty_after(kind: String, unc: float, age: float) -> float:
	return minf(unc + _by_class("uncertainty_mps", kind, 1.5) * maxf(age, 0.0), num("uncertainty_max_m", 600.0))


## "fresh", "aged" or "stale" for a sighting `age` s old.
static func band_of(age: float) -> String:
	var bands: Dictionary = data().get("bands_s", {})
	if age < float(bands.get("fresh", 30.0)):
		return "fresh"
	if age < float(bands.get("aged", 180.0)):
		return "aged"
	return "stale"


## The base uncertainty of a report by how it was seen (base_uncertainty_m key).
static func base_uncertainty(how: String) -> float:
	return float((data().get("base_uncertainty_m", {}) as Dictionary).get(how, 10.0))


# --- Reports -------------------------------------------------------------------------------------

## A report from a sender, reaching the picture `delay` s after `now` (at once for 0). `alive`
## (optional): asked when it comes due; false and it never got out. A report gets its id when it
## arrives (ids rise through `received`): returns it, or 0 while it's on its way.
func submit(report: Dictionary, now: float, delay := 0.0, alive := Callable()) -> int:
	var r := _normalise(report, now)
	if delay <= 0.0:
		_deliver(r, now)
		return int(r.id)
	pending.append({"due": now + delay, "report": r, "alive": alive})
	return 0


## This side's delay for a report by a sender of `skill` (its profile, its comms).
func delay_for(skill: float, under_fire := false) -> float:
	return delay_s(profile, skill, under_fire, comms_down)


func _normalise(report: Dictionary, now: float) -> Dictionary:
	var r := report.duplicate()
	r["kind"] = String(r.get("kind", "inf")) if String(r.get("kind", "inf")) in INFANTRY_KINDS + VEHICLE_KINDS else "inf"
	r["count"] = maxi(int(r.get("count", r.get("seen", 1))), 1)
	var pos: Variant = r.get("pos", Vector3.ZERO)
	r["pos"] = pos if pos is Vector3 else Vector3(float(pos.x), 0.0, float(pos.y)) if pos is Vector2 else Vector3.ZERO
	r["seen_at"] = float(r.get("seen_at", now))
	r["unc0"] = float(r.get("unc0", base_uncertainty("seen")))
	r["heading"] = float(r.get("heading", 0.0))
	r["speed"] = float(r.get("speed", 0.0))
	r["by"] = String(r.get("by", ""))
	r["confidence"] = clampf(float(r.get("confidence", 1.0)), 0.0, 1.0)
	r["source"] = String(r.get("source", "squad"))
	return r


func _deliver(r: Dictionary, now: float) -> void:
	r["id"] = _next_report
	_next_report += 1
	r["reported_at"] = now
	received.append(r)
	if bool(r.get("noise", false)):
		return  # heard, not seen: EnemyCommand's fog reads it, the picture has no entry for it
	_merge(r, now)


## Delivers what's due, drops what's aged out and prunes `received`. Call it every tick (cheap).
func step(now: float) -> void:
	var t0 := Time.get_ticks_usec()
	if not pending.is_empty():
		var still: Array[Dictionary] = []
		for p: Dictionary in pending:
			if now < float(p.due):
				still.append(p)
				continue
			var alive: Callable = p.alive
			if alive.is_valid() and not bool(alive.call()):
				continue  # the sender went down first: it never got out
			_deliver(p.report, now)
		pending = still
	var gone := false
	for e: Dictionary in entries:
		if now - float(e.reported_at) > (_drop_veh if _vehicle.has(e.kind) else _drop_inf):
			gone = true
			break
	if gone:
		var kept: Array[Dictionary] = []
		for e: Dictionary in entries:
			if now - float(e.reported_at) > (_drop_veh if _vehicle.has(e.kind) else _drop_inf):
				_hash_remove(e)
				revision += 1
			else:
				kept.append(e)
		entries = kept
	_prune_log(now)
	step_usec = Time.get_ticks_usec() - t0


func _prune_log(now: float) -> void:
	var most := max_received if max_received > 0 else int(num("max_log", 512))
	if received.is_empty() or (received.size() < most + PRUNE_BATCH and now - float(received[0].reported_at) <= _keep_s + 60.0):
		return  # pruned in batches: a slice copies the log
	var cut := 0
	while cut < received.size() and (now - float(received[cut].reported_at) > _keep_s or received.size() - cut > most):
		cut += 1
	if cut == 0:
		return
	var first_kept := int(received[cut].id) if cut < received.size() else _next_report
	received = received.slice(cut)
	for e: Dictionary in entries:  # an entry's oldest reports may go; its freshest never does
		var ids: Array = e.reports
		while ids.size() > 1 and int(ids[0]) < first_kept:
			ids.pop_front()


# --- Merging -------------------------------------------------------------------------------------

func _merge(r: Dictionary, now: float) -> void:
	var kind: String = r.kind
	var veh := _vehicle.has(kind)
	var reach := _merge_veh if veh else _merge_inf
	var pos: Vector3 = r.pos
	var best: Dictionary = {}
	var best_d := INF
	var cx := floori(pos.x / _cell_m)
	var cz := floori(pos.z / _cell_m)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell: Variant = _hash.get(Vector2i(cx + dx, cz + dz))
			if cell == null:
				continue
			for e: Dictionary in cell:
				if e.kind != kind or now - float(e.seen_at) > _window:
					continue
				var ep: Vector3 = e.pos
				var d := Vector2(ep.x - pos.x, ep.z - pos.z).length()
				if d <= reach and d < best_d:
					best = e
					best_d = d
	var unc_r := minf(float(r.unc0) + (_rate_veh if veh else _rate_inf) * maxf(now - float(r.seen_at), 0.0), _cap)
	if best.is_empty():
		if entries.size() >= _max_entries:
			_drop_oldest()
		var e := {"id": _next_entry, "side": String(side), "kind": kind, "count": int(r.count), "pos": r.pos, "unc": unc_r, "unc_at": now,
			"heading": r.heading, "speed": r.speed, "seen_at": r.seen_at, "reported_at": now, "by": r.by, "confidence": r.confidence,
			"reports": [int(r.id)], "tag": r.source == "tag", "tag_names": (r.get("tag_names", []) as Array).duplicate(), "rev": 1}
		_next_entry += 1
		entries.append(e)
		_hash_add(e)
	else:
		var unc_e := uncertainty(best, now)
		best.count = maxi(int(best.count), int(r.count))
		if float(r.seen_at) >= float(best.seen_at):  # position the fresher
			_hash_remove(best)
			best.pos = r.pos
			_hash_add(best)
			best.seen_at = r.seen_at
			best.heading = r.heading
			best.speed = r.speed
			best.by = r.by
		best.unc = minf(unc_e, unc_r)  # uncertainty the smaller
		best.unc_at = now
		best.reported_at = now
		best.confidence = maxf(float(best.confidence), float(r.confidence))
		(best.reports as Array).append(int(r.id))
		if r.source == "tag":
			best.tag = true
			for n: Variant in r.get("tag_names", []):
				if not (best.tag_names as Array).has(n):
					(best.tag_names as Array).append(n)
		best.rev = int(best.rev) + 1
	revision += 1


## Full: the least lately reported of the longest-standing DROP_SAMPLE entries goes (entries are
## in the order they were made, so those are the old ones; a scan of all of them per new entry
## cost more than the rest of the merge).
func _drop_oldest() -> void:
	var at := -1
	var oldest := INF
	for i in mini(entries.size(), DROP_SAMPLE):
		var t := float(entries[i].reported_at)
		if t < oldest:
			oldest = t
			at = i
	if at >= 0:
		_hash_remove(entries[at])
		entries.remove_at(at)


## An entry's uncertainty (m) at `now`.
func uncertainty(e: Dictionary, now: float) -> float:
	return minf(float(e.unc) + (_rate_veh if _vehicle.has(e.kind) else _rate_inf) * maxf(now - float(e.unc_at), 0.0), _cap)


## An entry's band at `now`.
func band(e: Dictionary, now: float) -> String:
	return band_of(now - float(e.seen_at))


## The entry with id `id`, or {}.
func entry(id: int) -> Dictionary:
	for e: Dictionary in entries:
		if int(e.id) == id:
			return e
	return {}


## The report with id `id` in `received`, or {}.
func report(id: int) -> Dictionary:
	var lo := 0
	var hi := received.size() - 1
	while lo <= hi:  # ids rise through `received`
		var mid := (lo + hi) / 2
		var at := int(received[mid].id)
		if at == id:
			return received[mid]
		if at < id:
			lo = mid + 1
		else:
			hi = mid - 1
	return {}


## Fairness: whether `e` traces back to reports: each of its report ids is in `received`, and its
## position is its freshest report's.
func traces(e: Dictionary) -> bool:
	var ids: Array = e.get("reports", [])
	if ids.is_empty():
		return false
	var freshest: Dictionary = {}
	for id: int in ids:
		var r := report(id)
		if r.is_empty():
			return false
		if freshest.is_empty() or float(r.seen_at) >= float(freshest.seen_at):
			freshest = r
	return (freshest.pos as Vector3).is_equal_approx(e.pos)


## Entries within `radius` of `at` (flat), any band.
func entries_near(at: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in entries:
		if _flat(e.pos, at) <= radius:
			out.append(e)
	return out


# --- Blue Force Tracker ---------------------------------------------------------------------------

## One of the side's vehicles: with a working radio its true position (a real system), else grey
## where it was last tracked.
func bft_vehicle(key: String, pos: Vector3, label: String, radio_ok: bool, now: float) -> void:
	var b: Dictionary = bft.get(key, {})
	if radio_ok or b.is_empty():
		bft[key] = {"key": key, "what": "vehicle", "pos": pos, "at": now, "grey": not radio_ok, "label": label}
	else:
		b.grey = true


## One of the side's groups by its sitrep.
func bft_group(key: String, pos: Vector3, label: String, now: float) -> void:
	bft[key] = {"key": key, "what": "group", "pos": pos, "at": now, "grey": false, "label": label}


## Drops BFT tracks not in `keep` (gone, wrecked, wiped out).
func bft_keep(keep: Dictionary) -> void:
	for k: String in bft.keys():
		if not keep.has(k):
			bft.erase(k)


# --- The hash ------------------------------------------------------------------------------------

func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_m), floori(pos.z / _cell_m))


func _hash_add(e: Dictionary) -> void:
	var c := _cell(e.pos)
	if not _hash.has(c):
		_hash[c] = []
	(_hash[c] as Array).append(e)


func _hash_remove(e: Dictionary) -> void:
	var c := _cell(e.pos)
	var cell: Variant = _hash.get(c)
	if cell == null:
		return
	for i in (cell as Array).size():
		if is_same(cell[i], e):  # by identity: Array.erase compares dictionaries by content
			(cell as Array).remove_at(i)
			break
	if (cell as Array).is_empty():
		_hash.erase(c)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
