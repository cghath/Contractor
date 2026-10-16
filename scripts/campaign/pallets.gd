class_name Pallets
extends RefCounted
## Supply pallets, tagged lots and the FOB's own stocks (Captain, 2026-10-15; docs/pallets.md),
## from res://data/pallets.json. In the field there are pallets (fuel, supplies, ammo, parts,
## medical, mixed loads) and abandoned or captured vehicles. A player tags one "to sell" or "for
## <faction>" (PalletField); at extraction every tagged one is hauled home as a LOT (below) and
## shows in the debrief, where the company sells it at the quick price, keeps it in FOB
## storage, gifts it (reputation) or KEEPS it as the FOB's own stocks (fuel, parts, ammo,
## supplies, medical counters in Economy's section, saved with the campaign). Stocks offset
## costs (offset_preview / take_stock: support calls, repairs, field costs) and can be drawn
## into the armory stash (server_draw).
##
## A lot: {"uid", "kind" ("pallet" or "vehicle"), "what" (the pallet kind or the vehicle model),
## "label", "units" {stock kind: n} (a vehicle has none), "value" (cash), "tag" ("sell" or
## "gift"), "faction" (the gift's default), "status" ("pending" in a debrief; then "sold",
## "gifted", "kept", "stored")}.
##
## Host-only (server_*) functions change the campaign; they never run on a client.

const PATH := "res://data/pallets.json"
## What a lot can be turned into.
const ACTIONS: Array[String] = ["sell", "gift", "keep", "store"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Pallets: cannot read %s" % PATH)
			return {"stock_kinds": {}, "kinds": {}}
		_data = parsed
	return _data


static func reload() -> void:
	_data = {}


static func num(key: String, fallback := 0.0) -> float:
	return float(data().get(key, fallback))


## The stock kinds ("fuel", "ammo", "parts", "supplies", "medical"), in file order.
static func stock_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in data().get("stock_kinds", {}):
		out.append(k)
	return out


static func stock_name(kind: String) -> String:
	return String((data().get("stock_kinds", {}) as Dictionary).get(kind, {}).get("name", kind.capitalize()))


static func unit_value(kind: String) -> int:
	return int((data().get("stock_kinds", {}) as Dictionary).get(kind, {}).get("unit_value", 0))


static func offset_per_unit(kind: String) -> int:
	return int((data().get("stock_kinds", {}) as Dictionary).get(kind, {}).get("offset_per_unit", 0))


static func pallet_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in data().get("kinds", {}):
		out.append(k)
	return out


static func kind_def(kind: String) -> Dictionary:
	return (data().get("kinds", {}) as Dictionary).get(kind, {})


static func kind_name(kind: String) -> String:
	return String(kind_def(kind).get("name", kind.capitalize()))


static func kind_colour(kind: String) -> Color:
	return Color(String(kind_def(kind).get("colour", "7a7a7a")))


## The pallets at a module type's site: [{"kind", "x", "z"}] (module space).
static func sites(module_type: String) -> Array:
	var out: Array = []
	for e: Array in (data().get("sites", {}) as Dictionary).get(ZoneModules.base(module_type), []):
		out.append({"kind": String(e[0]), "x": float(e[1]), "z": float(e[2])})
	return out


## The vehicles parked abandoned at a module type's site.
static func site_vehicles(module_type: String) -> Array:
	return (data().get("site_vehicles", {}) as Dictionary).get(ZoneModules.base(module_type), [])


# --- Lots --------------------------------------------------------------------------------

## What pallet `uid` of `kind` holds, the same on every peer: the kind's contents scaled by a
## factor from the file's "variance" range (a hash of the uid): {"units", "value"}.
static func roll(kind: String, uid: String) -> Dictionary:
	var range_: Array = data().get("variance", [0.7, 1.3])
	var rng := RandomNumberGenerator.new()
	rng.seed = uid.hash()
	var factor := lerpf(float(range_[0]), float(range_[1]), rng.randf())
	var units := {}
	var value := 0
	for k: String in kind_def(kind).get("contents", {}):
		var n := maxi(roundi(float(kind_def(kind).contents[k]) * factor), 1)
		units[k] = n
		value += n * unit_value(k)
	return {"units": units, "value": value}


## A pallet's lot (the tag is added by the caller).
static func pallet_lot(kind: String, uid: String) -> Dictionary:
	var r := roll(kind, uid)
	return {"uid": uid, "kind": "pallet", "what": kind, "label": kind_name(kind), "units": r.units, "value": int(r.value),
		"tag": "sell", "faction": "", "status": "pending"}


## A vehicle's lot: by model, a wreck worth "wreck_ratio" of it.
static func vehicle_lot(model: String, wrecked: bool, uid: String, label: String) -> Dictionary:
	var values: Dictionary = data().get("vehicle_values", {})
	var value := int(values.get(model, values.get("default", 10000)))
	if wrecked:
		value = roundi(value * num("wreck_ratio", 0.25))
	return {"uid": uid, "kind": "vehicle", "what": model, "label": label + (" (wreck)" if wrecked else ""), "units": {},
		"value": value, "tag": "sell", "faction": "", "status": "pending"}


## "Fuel drums (fuel 12)" / "Technical (wreck)".
static func lot_text(lot: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in lot.get("units", {}):
		parts.append("%s %d" % [stock_name(k).to_lower(), int(lot.units[k])])
	return "%s%s, worth $%s" % [lot.get("label", "?"), " (%s)" % ", ".join(parts) if not parts.is_empty() else "", DebriefCalc.money(int(lot.get("value", 0)))]


## The quick price at the debrief (`stored` false) or the better one from FOB storage.
static func sell_price(lot: Dictionary, stored := false) -> int:
	return roundi(int(lot.get("value", 0)) * num("sell_stored_ratio" if stored else "sell_now_ratio", 0.5))


## The reputation a gift of this lot earns.
static func gift_rep(lot: Dictionary) -> int:
	return clampi(maxi(int(lot.get("value", 0)) / maxi(int(num("gift_rep_per", 1500)), 1), 1), 1, int(num("gift_rep_max", 8)))


## Whether this lot can be kept as FOB stocks (pallets only; a vehicle waits for the motor pool).
static func can_keep(lot: Dictionary) -> bool:
	return String(lot.get("kind", "")) == "pallet" and not (lot.get("units", {}) as Dictionary).is_empty()


## The factions a lot may be tagged for or gifted to: the employers.
static func gift_factions() -> Array[String]:
	var out: Array[String] = []
	for f: String in MissionRegistry.employers():
		out.append(f)
	return out


## LATER (the sale mission, a hook only): what a fixer would offer for `lot` and how likely
## a betrayal at the meeting point is, from the company's reputation with `fixer` (low rep: the
## fixer may rob the convoy). {"available": false} until the mission exists.
static func sale_offer(lot: Dictionary, fixer: String) -> Dictionary:
	var cfg: Dictionary = data().get("sale_mission", {})
	var rep := Economy.reputation(fixer)
	var risk := clampf(float(int(cfg.get("betrayal_rep", 10)) - rep) / 100.0, 0.0, float(cfg.get("betrayal_max", 0.6)))
	return {"available": false, "fixer": fixer, "price": roundi(int(lot.get("value", 0)) * float(cfg.get("price_ratio", 1.1))), "betrayal_risk": risk}


# --- Stocks: offsets and draws -----------------------------------------------------------------

## How much of `amount` (a cost) the FOB stocks could cover for `context` ("support:<kind>",
## "repair", "field_costs"), without using any up: {"offset", "used" {stock kind: units}}.
## Each kind covers its share of the cost at its "offset_per_unit" and only as many units
## as that takes (rounded up).
static func offset_preview(amount: int, context: String) -> Dictionary:
	var out := {"offset": 0, "used": {}}
	if amount <= 0:
		return out
	var table: Dictionary = data().get("stock_effects", {})
	var shares: Dictionary = {}
	if context.begins_with("support:"):
		shares = (table.get("support", {}) as Dictionary).get(context.trim_prefix("support:"), {})
	else:
		shares = table.get(context, {})
	for k: String in shares:
		var per := offset_per_unit(k)
		var have := Economy.stock(k)
		if per <= 0 or have <= 0:
			continue
		var cover := floori(amount * float(shares[k]))
		var units := mini(ceili(float(cover) / per), have)
		if units <= 0:
			continue
		out.used[k] = units
		out.offset = int(out.offset) + mini(units * per, cover)
	return out


## Host: uses up the stock a preview named ("used").
static func take_stock(used: Dictionary) -> void:
	for k: String in used:
		Economy.server_take_stock(k, int(used[k]))


## Host: draws `units` of a stock kind into the armory stash (the base inbox): "draw" in the
## file says what a unit becomes. Returns "" or why not.
static func server_draw(kind: String, units: int) -> String:
	var items: Array = (data().get("draw", {}) as Dictionary).get(kind, [])
	if items.is_empty():
		return "%s can't be drawn as gear" % stock_name(kind)
	if units <= 0 or Economy.stock(kind) < units:
		return "Not enough %s in stock" % stock_name(kind).to_lower()
	var out: Array = []
	for e: Dictionary in items:
		out.append({"id": String(e.id), "count": int(e.count) * units, "state": {}})
	Economy.server_take_stock(kind, units)
	Economy.bank_items(out, "")
	return ""


# --- Doing something with a lot (host) -----------------------------------------------------------

## Host: does `action` ("sell", "gift", "keep", "store") with `lot`, from a debrief or (`stored`)
## from FOB storage; `faction` is who a gift goes to. Returns "" when done, else why not. The
## caller records the result (status) and, from storage, removes the lot.
static func server_act(lot: Dictionary, action: String, faction := "", stored := false) -> String:
	match action:
		"sell":
			var price := sell_price(lot, stored)
			Economy.add_cash(price, "Sold %s%s" % [lot.get("label", "a lot"), " from storage" if stored else " (quick sale)"])
			Economy.notice.emit("Sold %s for $%s" % [lot.get("label", "a lot"), DebriefCalc.money(price)])
		"gift":
			if faction == "" or MissionRegistry.faction(faction).is_empty():
				return "Pick a faction to gift it to"
			var rep := gift_rep(lot)
			Economy.change_reputation(faction, rep, "gift: %s" % lot.get("label", "a lot"))
			Economy.notice.emit("Gifted %s to %s (+%d reputation)" % [lot.get("label", "a lot"), MissionRegistry.faction_name(faction), rep])
		"keep":
			if not can_keep(lot):
				return "A vehicle can't go into the stocks"
			for k: String in lot.units:
				Economy.server_add_stock(k, int(lot.units[k]))
			Economy.notice.emit("Kept %s for the FOB's stocks" % lot.get("label", "a lot"))
		"store":
			if stored:
				return "Already in storage"
			var copy := (lot as Dictionary).duplicate(true)
			copy["status"] = "stored"
			Economy.server_store_lot(copy)
		_:
			return "Unknown action"
	return ""
