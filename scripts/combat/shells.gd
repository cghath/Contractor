class_name Shells
extends RefCounted
## The projectiles ArmourModel resolves against vehicle plates (combined arms A1,
## docs/combined_arms.md 2.3.1): gun rounds from res://data/shells.json, launcher rockets and
## missiles from data/warheads.json (Warheads), read through one shell() in one shape. A
## warhead's penetration_mm is its pen_ce for a shaped charge and its blast_kg its he_kg, so
## the two files never repeat a number. A bullet Ballistics fires is found by its round id
## (round_id in shells.json). Every number is Proposed. Read-only after the first load.

const PATH := "res://data/shells.json"

## The kinds by threat column (docs/combined_arms.md 2.3.2): KE rounds read a plate's ke_mm,
## shaped charges its ce_mm, HE rounds punch by their filling against its physical thickness.
## hedp and amp are a shaped charge with a real filling: their CE part goes first.
const KE_KINDS: Array[String] = ["apfsds", "apds", "ap", "api", "efp", "canister"]
const CE_KINDS: Array[String] = ["heat", "tandem_heat", "hedp", "amp"]
const HE_KINDS: Array[String] = ["he", "hei", "thermobaric"]

static var _shells: Dictionary = {}   # id -> row as normalised by _norm
static var _by_round: Dictionary = {} # rounds.json id -> shell id
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("shells")) != TYPE_DICTIONARY:
		push_error("Shells: %s is missing or not valid JSON" % PATH)
		return
	for id: String in parsed.shells:
		var row: Dictionary = parsed.shells[id]
		_shells[StringName(id)] = _norm(StringName(id), row)
		if row.has("round_id"):
			_by_round[StringName(row.round_id)] = StringName(id)


## Shell `id` (a shells.json id or a warheads.json id) in ArmourModel's shape, or {}: "id",
## "kind", "calibre_mm", "pen_ke" (the table), "pen_ce", "he_kg", "normalise_deg",
## "ricochet_deg", "overmatch", "fuze", "arming_m", "module_dmg", "rocket", "incendiary",
## "spall", plus the row's own keys.
static func shell(id: Variant) -> Dictionary:
	_load()
	var key := StringName(id)
	if _shells.has(key):
		return _shells[key]
	var w := Warheads.data(key)
	if w.is_empty():
		return {}
	var row := w.duplicate()
	var kind := String(w.get("kind", "he"))
	if kind in CE_KINDS:
		row["pen_ce"] = float(w.get("penetration_mm", 0.0))
	row["he_kg"] = float(w.get("blast_kg", 0.0))
	_shells[key] = _norm(key, row)
	return _shells[key]


## The shell a Ballistics round (data/rounds.json id) is, or "" when it has no vehicle numbers
## (pistol and rifle rounds: they stay on VehicleDamage's tiers).
static func for_round(round_id: Variant) -> StringName:
	_load()
	return _by_round.get(StringName(round_id), &"")


## Every shells.json id (warheads are Warheads.ids()).
static func ids() -> Array:
	_load()
	var out: Array = []
	for id: StringName in _shells:
		if Warheads.data(id).is_empty():
			out.append(id)
	return out


## Penetration (mm RHA at 0 degrees) of a KE `shell` at `range_m`, from its pen_ke table.
static func pen_ke(shell: Dictionary, range_m: float) -> float:
	var table: Array = shell.get("pen_ke", [])
	if table.is_empty():
		return 0.0
	if range_m <= float(table[0][0]):
		return float(table[0][1])
	for i in range(1, table.size()):
		var r1 := float(table[i][0])
		if range_m <= r1:
			var r0 := float(table[i - 1][0])
			return lerpf(float(table[i - 1][1]), float(table[i][1]), (range_m - r0) / maxf(r1 - r0, 0.001))
	return float(table[-1][1])


static func _norm(id: StringName, row: Dictionary) -> Dictionary:
	var out := row.duplicate()
	out["id"] = id
	var kind := String(row.get("kind", "he"))
	out["kind"] = kind
	out["calibre_mm"] = float(row.get("calibre_mm", 0.0))
	out["pen_ce"] = float(row.get("pen_ce", 0.0))
	out["he_kg"] = float(row.get("he_kg", 0.0))
	out["overmatch"] = float(row.get("overmatch", 3.0))
	out["normalise_deg"] = float(row.get("normalise_deg", 0.0))
	out["arming_m"] = float(row.get("arming_m", 0.0))
	out["module_dmg"] = float(row.get("module_dmg", 0.0))
	out["rocket"] = bool(row.get("rocket", false))
	out["incendiary"] = bool(row.get("incendiary", false))
	if not row.has("fuze"):
		out["fuze"] = {"kind": "none"} if kind in KE_KINDS else ({"kind": "piezo"} if kind in CE_KINDS else {"kind": "pd"})
	return out
