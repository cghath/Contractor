class_name BodySeason
extends RefCounted
## The seasons on the body (docs/survival_medical.md section 6, call 34): which season it is
## (Survival.season() when the world lane has it, else spring), how hard the cold bites
## (cold_mult), thirst in the heat, food's shelf life, the warmth clothes add (clothing_warmth:
## the worn clothing layers, Clothing), heat
## stroke in summer (heat_gain, the mirror of hypothermia) and frostbite on exposed hands and
## face in winter (Body.server_step adds the wound). Static: the numbers are testable without a body.

const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]
## Proposed: the cold's bite on the warmth store by season (winter's air and wind drain it fast).
## Thirst and food's shelf life are the world lane's (Seasons.SUMMER_THIRST, SUMMER_SPOIL,
## WINTER_SPOIL), by the season given so the body's math stays testable.
const COLD_MULT := {"spring": 1.0, "summer": 0.5, "autumn": 1.2, "winter": 1.8}
## Spring and autumn rain and mud: open wounds dirty faster, hygiene drains faster (Proposed).
const MUD_MULT := {"spring": 1.3, "summer": 1.0, "autumn": 1.3, "winter": 1.0}
## Clothing: the warmth a worn or carried layer adds (0..1 of the cold kept off), at most MAX.
const CLOTHING_MAX := 0.7
## Heat (C per world hour pushed into the core in summer daylight outdoors; Needs cools 0.5 an
## hour back toward normal): the sun, moving, sprinting, being short of water (Proposed).
const HEAT_SUN := 0.45
const HEAT_MOVE := 0.25
const HEAT_SPRINT := 0.5
const HEAT_DRY := 0.3
const HEAT_STROKE_C := 38.8
## Frostbite: winter, outdoors, the core under FROST_C for FROST_H world hours: a wound on the
## hands (without gloves) or the face (without a balaclava or shemagh).
const FROST_C := 35.6
const FROST_H := 4.0
## Tests: the season to use instead of the world's ("" off).
static var force_season := ""


## The season now: forced (tests), the world lane's Survival.season() when it has one, else spring.
static func season() -> String:
	if force_season != "":
		return force_season
	if Survival.has_method("season"):
		var s: Variant = Survival.call("season")
		if s is String and String(s) in SEASONS:
			return String(s)
	return "spring"


static func cold_mult(season_id: String) -> float:
	return float(COLD_MULT.get(season_id, 1.0))


static func thirst_mult(season_id: String) -> float:
	return Seasons.SUMMER_THIRST if season_id == "summer" else 1.0


## Food's shelf life by season (Seasons' numbers: summer half, winter double).
static func spoil_mult(season_id: String) -> float:
	match season_id:
		"summer":
			return Seasons.SUMMER_SPOIL
		"winter":
			return Seasons.WINTER_SPOIL
	return 1.0


static func mud_mult(season_id: String) -> float:
	return float(MUD_MULT.get(season_id, 1.0))


## Days `item` keeps now (its spoils_days by the season: summer halves it), for the spoiling code;
## `in_fridge` (a powered fridge: Infrastructure.fridge_on) stops it.
static func spoils_days(item: ItemData, season_id := "", in_fridge := false) -> float:
	if item == null or not item.stats.has("spoils_days") or (in_fridge and Infrastructure.fridge_on()):
		return INF
	return float(item.stats.spoils_days) * spoil_mult(season_id if season_id != "" else season())


## The warmth `inv`'s clothing adds (0 .. CLOTHING_MAX): what's worn in the clothing slots, dry
## (Clothing.inv_warmth; the body's own reading, wet layers and all, is Clothing.warmth).
static func clothing_warmth(inv: Inventory) -> float:
	return Clothing.inv_warmth(inv) if inv != null else 0.0


## Whether `inv` covers the hands (gloves) and the face (a balaclava or shemagh) against frost.
static func covers(inv: Inventory, what: String) -> bool:
	if inv == null:
		return false
	if Clothing.covers(inv, what):  # gloves worn, a face layer worn (call 132)
		return true
	var ids: Array = ["gloves_tactical"] if what == "hands" else ["balaclava", "shemagh", "gas_mask_gp5", "gas_mask_m50"]
	for id: String in ids:
		if inv.count_of(StringName(id)) > 0:
			return true
	return false


## C per world hour the heat pushes into the core (summer daylight outdoors), from `ctx`
## (Needs.context_of's keys plus "season") and the body `n`.
static func heat_gain(n: Dictionary, ctx: Dictionary) -> float:
	var season_id := String(ctx.get("season", "spring"))
	if season_id != "summer" or bool(ctx.get("indoors", false)) or float(ctx.get("dark", 0.0)) >= 0.4:
		return 0.0
	var g := HEAT_SUN
	if bool(ctx.get("moving", false)):
		g += HEAT_MOVE
	if bool(ctx.get("sprint", false)):
		g += HEAT_SPRINT
	if float(n.get("thirst", 100.0)) < 35.0:
		g += HEAT_DRY
	return g


## Whether the body is in heat stroke.
static func heat_stroke(n: Dictionary) -> bool:
	return float(n.get("warmth", Needs.NORMAL_C)) >= HEAT_STROKE_C and not Body.has_fever(n)
