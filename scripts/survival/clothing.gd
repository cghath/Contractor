class_name Clothing
extends RefCounted
## Clothing slots and layers of Contractor: Fallen (docs/survival_clothing.md, call 132): what a
## survivor wears in Inventory.CLOTHING_SLOTS (head, face, torso base / mid / outer, hands, legs,
## feet; the carrier, helmet and pack are the slots that were there), each item a "clothing"
## type (or one of the four older items that had a `warmth`: tactical gloves, balaclava,
## shemagh, the enclave's uniform) with stats:
##   layer       the slot it goes in (one of CLOTHING_SLOTS)
##   warmth      0..1 of the cold it keeps off (summed over what's worn, at most BodySeason.CLOTHING_MAX)
##   wet_resist  0..1 of the rain it sheds instead of soaking up
##   noise       a step-noise multiplier (a rain jacket rustles: 1.35; soft sneakers 0.85)
##   camo        a colour/terrain tag ("woodland", "desert", "snow", "urban", "dark", "plain", "bright")
##   pockets     litres it adds to the pockets container
##   durability  how well it stands wear (call 122's wear lane reads it; not used here yet)
##   colour      how it's drawn (ClothingArt)
## Wetness is per layer, on the body (Needs' dictionary, "layer_wet": {slot: {"id", "wet"}}): the
## rain soaks the outer layer first and what it can't hold goes in to the next, then the skin
## (the body's own "wet"); a layer dries over time, much faster by a fire. A wet layer keeps less
## of its warmth. Static: the numbers are testable without a body.

const LAYERS: Array[StringName] = [&"head", &"face", &"torso_base", &"torso_mid", &"torso_outer", &"hands", &"legs", &"feet"]
## The torso's layers, outermost first (the order the rain goes through them).
const TORSO_OUT_IN: Array[StringName] = [&"torso_outer", &"torso_mid", &"torso_base"]
const NAMES := {&"head": "Head", &"face": "Face", &"torso_base": "Base layer", &"torso_mid": "Mid layer", &"torso_outer": "Outer layer",
	&"hands": "Hands", &"legs": "Legs", &"feet": "Feet"}
## Proposed: a soaked layer keeps this share of its warmth less (cotton and wool alike for now).
const WET_WARMTH_LOSS := 0.7
## Proposed: a layer holds rain up to 1.0 (soaked); the share of the rain the skin gets with no
## torso layers is all of it (the body's old model, Needs.WET_RAIN_H an hour).
const DRY_FIRE_MULT := 6.0
const DRY_INDOORS_MULT := 1.5
const FIRE_M := 3.0
## Proposed: camouflage against the terrain for the living's sight (call 122; their sight reads
## camo_mult later): a match hides you, a bright jacket shows you.
const CAMO_MATCH := 0.8
const CAMO_BRIGHT := 1.25
const CAMO_DARK_NIGHT := 0.9
## A fresh survivor's clothes (Proposed): one of each row, by the survivor's seed.
const STARTER := [["tshirt"], ["flannel_shirt", "hoodie", "denim_jacket"], ["jeans", "cargo_pants"], ["sneakers", "work_boots"]]

## Tests (and the host's other modes): clothing goes on when picked up even outside a survival world.
static var force := false


## Whether clothing is worn in this world (a survival world on the host; tests).
static func enabled() -> bool:
	return force or Survival.running


## The clothing slot `item` goes in (its stats' "layer"), or &"".
static func slot_of(item: ItemData) -> StringName:
	if item == null:
		return &""
	var layer := StringName(String(item.stats.get("layer", "")))
	return layer if layer in LAYERS else &""


static func is_clothing(item: ItemData) -> bool:
	return slot_of(item) != &""


## What `inv` wears, slot by slot: [{"slot", "id", "item"}] in LAYERS order.
static func worn(inv: Inventory) -> Array:
	var out: Array = []
	if inv == null:
		return out
	for slot: StringName in LAYERS:
		var id := StringName(inv.slots.get(slot, &""))
		if id != &"" and ItemDB.has_item(id):
			out.append({"slot": slot, "id": id, "item": ItemDB.get_item(id)})
	return out


## The layers Needs.step needs (no ItemData: plain numbers): [{"slot", "id", "warmth", "wet_resist"}].
static func layers(inv: Inventory) -> Array:
	var out: Array = []
	for w: Dictionary in worn(inv):
		var it: ItemData = w.item
		out.append({"slot": w.slot, "id": String(w.id), "warmth": float(it.stats.get("warmth", 0.0)), "wet_resist": float(it.stats.get("wet_resist", 0.0))})
	return out


## The warmth of `lay` (layers()) with the body `n`'s layer wetness: each layer's warmth less
## WET_WARMTH_LOSS of it soaked, summed, at most BodySeason.CLOTHING_MAX.
static func layers_warmth(lay: Array, n: Dictionary = {}) -> float:
	var wet: Dictionary = n.get("layer_wet", {})
	var total := 0.0
	for l: Dictionary in lay:
		var w := float(l.warmth)
		var lw: Dictionary = wet.get(String(l.slot), {})
		if String(lw.get("id", "")) == String(l.id):
			w *= 1.0 - WET_WARMTH_LOSS * clampf(float(lw.get("wet", 0.0)), 0.0, 1.0)
		total += w
	return clampf(total, 0.0, BodySeason.CLOTHING_MAX)


## The warmth `s`'s clothes give now (worn layers, their wetness): what Needs reads.
static func warmth(s: Soldier) -> float:
	if s == null or s.inventory == null:
		return 0.0
	return layers_warmth(layers(s.inventory), s.get_meta(&"needs", {}) as Dictionary)


## The warmth of what `inv` wears, dry (BodySeason.clothing_warmth's answer now).
static func inv_warmth(inv: Inventory) -> float:
	return layers_warmth(layers(inv))


## How wet `s` is: {"skin": 0..1, slot: 0..1 for each worn layer}.
static func wet(s: Soldier) -> Dictionary:
	if s == null:
		return {}
	return wet_of(s.get_meta(&"needs", {}) as Dictionary, s.inventory)


static func wet_of(n: Dictionary, inv: Inventory) -> Dictionary:
	var out := {"skin": float(n.get("wet", 0.0))}
	var lw: Dictionary = n.get("layer_wet", {})
	for w: Dictionary in worn(inv):
		var rec: Dictionary = lw.get(String(w.slot), {})
		out[String(w.slot)] = float(rec.get("wet", 0.0)) if String(rec.get("id", "")) == String(w.id) else 0.0
	return out


## Needs.step's wet part with clothes on (`lay`: layers(); ctx: Needs.context_of's keys plus
## "fire"): wading soaks it all; rain on the outer layer first, what a layer sheds (wet_resist)
## runs off and what it can't hold goes in to the next, then the skin; out of the rain each layer
## and the skin dry (by a fire DRY_FIRE_MULT times faster).
static func step_wet(n: Dictionary, lay: Array, world_h: float, ctx: Dictionary) -> void:
	var lw: Dictionary = n.get("layer_wet", {})
	var kept := {}
	for l: Dictionary in lay:  # a new item in a slot starts dry; layers taken off are forgotten
		var rec: Dictionary = lw.get(String(l.slot), {})
		kept[String(l.slot)] = {"id": String(l.id), "wet": float(rec.get("wet", 0.0)) if String(rec.get("id", "")) == String(l.id) else 0.0}
	n["layer_wet"] = kept
	var indoors := bool(ctx.get("indoors", false))
	var dry := Needs.WET_DRY_H * world_h * (DRY_FIRE_MULT if bool(ctx.get("fire", false)) else 1.0) * (DRY_INDOORS_MULT if indoors else 1.0)
	if float(ctx.get("wading", 0.0)) > Needs.WADE_WET_M:
		for k: String in kept:
			if k != "head" and k != "face":
				kept[k].wet = 1.0
		n.wet = 1.0
		return
	var raining := bool(ctx.get("rain", false)) and not indoors
	var water := Needs.WET_RAIN_H * world_h if raining else 0.0
	var by_slot := {}
	for l: Dictionary in lay:
		by_slot[String(l.slot)] = l
	for slot: StringName in TORSO_OUT_IN:
		var l: Dictionary = by_slot.get(String(slot), {})
		if l.is_empty():
			continue
		var rec: Dictionary = kept[String(slot)]
		if water <= 0.0:
			rec.wet = maxf(0.0, float(rec.wet) - dry)
			continue
		var soak := water * (1.0 - clampf(float(l.wet_resist), 0.0, 1.0))
		var room := 1.0 - float(rec.wet)
		rec.wet = minf(1.0, float(rec.wet) + soak)
		water = maxf(0.0, soak - room)  # what it couldn't hold goes in; what it shed ran off
	for k: String in kept:  # head, face, hands, legs, feet: the rain wets them, they dry
		if StringName(k) in TORSO_OUT_IN:
			continue
		var l2: Dictionary = by_slot.get(k, {})
		var rec2: Dictionary = kept[k]
		if raining:
			rec2.wet = minf(1.0, float(rec2.wet) + Needs.WET_RAIN_H * world_h * (1.0 - clampf(float(l2.get("wet_resist", 0.0)), 0.0, 1.0)))
		else:
			rec2.wet = maxf(0.0, float(rec2.wet) - dry)
	if water > 0.0:
		n.wet = minf(1.0, float(n.get("wet", 0.0)) + water)
	else:
		n.wet = maxf(0.0, float(n.get("wet", 0.0)) - dry)


## Whether `s` stands by a fire: a built stove (WaterWorks.near_fire) or a lit campfire on the
## ground within FIRE_M.
static func near_fire(s: Soldier) -> bool:
	if s == null or not s.is_inside_tree():
		return false
	if WaterWorks.near_fire(s):
		return true
	var level := CompoundLevel.current(s)
	if level and level.items:
		for node in level.items.get_children():
			var wi := node as WorldItem
			if wi and wi.item_id == &"campfire" and not wi.is_queued_for_deletion() and wi.global_position.distance_to(s.global_position) <= FIRE_M:
				return true
	return false


## The step-noise multiplier of what `s` wears (Survival._footsteps): the product of each worn
## item's "noise" (a rain jacket and rain trousers rustle, sneakers are quiet).
static func noise_mult(s: Soldier) -> float:
	if s == null or s.inventory == null:
		return 1.0
	return noise_of(s.inventory)


static func noise_of(inv: Inventory) -> float:
	var m := 1.0
	for w: Dictionary in worn(inv):
		m *= float((w.item as ItemData).stats.get("noise", 1.0))
	return clampf(m, 0.5, 2.0)


## How visible `s` is to the living against `terrain` ("woodland", "desert", "snow", "urban"...):
## the outer torso layer (or the mid, or the base) and the legs; a match hides (CAMO_MATCH each),
## a bright one shows (CAMO_BRIGHT), "dark" helps a little at night. 1.0 is plain. For the
## living's sight (phase D: their senses read it later).
static func camo_mult(s: Soldier, terrain: String, night := false) -> float:
	if s == null or s.inventory == null:
		return 1.0
	return camo_of(s.inventory, terrain, night)


static func camo_of(inv: Inventory, terrain: String, night := false) -> float:
	var m := 1.0
	var top: ItemData = null
	for slot: StringName in TORSO_OUT_IN:
		var id := StringName(inv.slots.get(slot, &""))
		if id != &"" and ItemDB.has_item(id):
			top = ItemDB.get_item(id)
			break
	var legs_id := StringName(inv.slots.get(&"legs", &""))
	for it: ItemData in [top, ItemDB.get_item(legs_id) if legs_id != &"" else null]:
		if it == null:
			continue
		var tag := String(it.stats.get("camo", "plain"))
		if tag == terrain:
			m *= CAMO_MATCH
		elif tag == "bright":
			m *= CAMO_BRIGHT
		elif tag == "dark" and night:
			m *= CAMO_DARK_NIGHT
	return m


## Litres the worn clothes' pockets add (Inventory.capacity of the pockets).
static func pockets_l(inv: Inventory) -> float:
	var total := 0.0
	for slot: StringName in LAYERS:
		var id := StringName(inv.slots.get(slot, &""))
		if id != &"" and ItemDB.has_item(id):
			total += float(ItemDB.get_item(id).stats.get("pockets", 0.0))
	return total


## Whether `inv` covers the hands (gloves worn) or the face (a face layer worn) against frost.
static func covers(inv: Inventory, what: String) -> bool:
	if inv == null:
		return false
	return StringName(inv.slots.get(&"hands" if what == "hands" else &"face", &"")) != &""


## Host: a fresh survivor's clothes on `inv` (STARTER, one of each row by `seed_key`), worn.
static func give_starting_set(inv: Inventory, seed_key: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + "|clothes")
	var was := force
	force = true  # (worn whatever the world: a survivor's own clothes)
	for row: Array in STARTER:
		var id := StringName(String(row[rng.randi_range(0, row.size() - 1)]))
		if ItemDB.has_item(id):
			inv.take(id, 1)
	force = was


## Host: a survivor's body with no clothes on gets a starting set (lone survivors and companions
## whose records came from before clothing: SurvivorsLayer._dress).
static func dress_if_bare(inv: Inventory, seed_key: String) -> void:
	if inv != null and worn(inv).is_empty():
		give_starting_set(inv, seed_key)


## A find of clothes (the "clothes" loot pool): [{"id", "count"}], for the dead's dress lane and
## loot boxes that want one.
static func roll_find(seed_key: String, hot := false) -> Array:
	return WorldValuables.pool_roll("clothes", seed_key, hot).items


## Words for the gear editor and the body screen: "Outer layer: Rain Jacket (soaked)".
static func lines_of(inv: Inventory, n: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var wet := wet_of(n, inv)
	for w: Dictionary in worn(inv):
		var it: ItemData = w.item
		var lw := float(wet.get(String(w.slot), 0.0))
		out.append("%s: %s%s" % [NAMES.get(w.slot, String(w.slot)), it.name, " (soaked)" if lw > 0.5 else (" (damp)" if lw > 0.1 else "")])
	return out
