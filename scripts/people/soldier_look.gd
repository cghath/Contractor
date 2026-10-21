class_name SoldierLook
extends RefCounted
## Who a soldier (or any person on the voxel body) is to look at: skin, hair and eye colour,
## hair style, beard, the shape of the face, and build and height (Captain, 2026-10-20: real
## faces and a different person in every uniform). The uniform stays the faction's (VoxelArt
## VARIANTS); this is only the person in it.
##
## A look is rolled from a seed by nationality (Soldier.nation, Names): a nation's soldiers look
## like that nation's people, so an American squad is mixed, a Chinese one East Asian, and the
## region's insurgents bearded. It travels as a short code (Soldier.face, CharacterModel.face)
## in the spawn data, the body record and the replicated state, so every peer and every reload
## draws the same person; a roster member's seed is rolled once at hiring (Roster.ensure_identity),
## so they keep their face for the whole campaign.
##
## The code: "<skin>:<hair>:<eye>:<shape>:<build>:<height>": three hex colours, the shape's
## eight digits (SHAPE_KEYS: hair style, beard, jaw, chin, nose, brow ridge, cheekbones, ears),
## the build (SLIM, AVERAGE, HEAVY) and the height in thousandths of the body's own.
##
## All the shares below are proposed: rough mixes for each force, not census figures.

const SHAPE_KEYS: Array[String] = ["hair", "beard", "jaw", "chin", "nose", "brow", "cheek", "ears"]
## The head drawn when no look is set (older saves, tests): a short crop, clean-shaven, every
## feature middling.
const DEFAULT_SHAPE := "20111000"
const DEFAULT_FEMALE_SHAPE := "00111000"
const DEFAULT := "c8996f:3b2a1d:4a3020:%s:1:1000" % DEFAULT_SHAPE

## Builds: girth across the trunk (CharacterModel.girth), the limbs following part of the way.
const SLIM := 0
const AVERAGE := 1
const HEAVY := 2
const BUILD_GIRTH: Array[float] = [0.95, 1.0, 1.07]
## Heights: a normal spread round each nation's average, never past HEIGHT_SPREAD either way.
const HEIGHT_SD := 0.028
const HEIGHT_SPREAD := 0.06

## Male hair styles (shape digit 0), and female ones (all kept short of a helmet's rim).
const BUZZ := 0
const CREW := 1      # faded sides, a little more on top
const CROP := 2
const LONG_TOP := 3
const SHAVED := 4
const RECEDING := 5
const BUN := 0
const BRAID := 1
const PONYTAIL := 2
const PIXIE := 3
## Beards (shape digit 1; men only).
const CLEAN := 0
const STUBBLE := 1
const MOUSTACHE := 2
const SHORT_BEARD := 3
const FULL_BEARD := 4
const GOATEE := 5

## Skin tones by group, light to dark (hex).
const SKINS := {
	"eur": ["f0d2bd", "e8c2a4", "ddb08f", "d09e7c", "c38f6c"],
	"med": ["d6a77f", "c99a6e", "bd8a5f", "b07a52", "a06c45"],
	"sas": ["b9835a", "a3714b", "8d5f3d", "7a4f32"],
	"afr": ["8d5b3e", "7a4a30", "6b3f27", "5a3320", "4a2a1a"],
	"eas": ["f0d0b0", "e6c19c", "dab087", "c99f78"],
}
## Hair colours by group: [hex, share].
const HAIR := {
	"eur": [["161210", 0.1], ["2e2018", 0.33], ["4a3222", 0.24], ["6e4c30", 0.12], ["8f6e45", 0.09], ["b8955e", 0.07], ["7a3a1e", 0.05]],
	"med": [["141110", 0.5], ["2a1d15", 0.4], ["4a3222", 0.1]],
	"sas": [["120f0e", 0.8], ["2a1d15", 0.2]],
	"afr": [["0f0d0c", 0.9], ["1f1712", 0.1]],
	"eas": [["0f0e0e", 0.85], ["231a14", 0.15]],
}
## Greying (salt and pepper, then grey) for this share of each group.
const GREY: Array[String] = ["5e5852", "8a857e"]
const GREY_SHARE := 0.08
## Eye colours (iris) by group.
const EYES := {
	"eur": [["4a6a8a", 0.28], ["6a7480", 0.1], ["4f6a3c", 0.12], ["6b5a32", 0.15], ["4a3020", 0.35]],
	"med": [["3b2416", 0.65], ["6b5a32", 0.22], ["4f6a3c", 0.08], ["4a6a8a", 0.05]],
	"sas": [["2e1c12", 0.85], ["4a3020", 0.15]],
	"afr": [["24160e", 0.9], ["3b2416", 0.1]],
	"eas": [["24160e", 0.85], ["3b2416", 0.15]],
}
## Which groups a nation's people come from (Names.POOLS keys; "insurgent" is the region's own).
const NATION_GROUPS := {
	"US": [["eur", 0.58], ["med", 0.19], ["afr", 0.13], ["eas", 0.06], ["sas", 0.04]],
	"UK": [["eur", 0.82], ["sas", 0.09], ["afr", 0.05], ["med", 0.02], ["eas", 0.02]],
	"CA": [["eur", 0.7], ["eas", 0.1], ["sas", 0.08], ["med", 0.07], ["afr", 0.05]],
	"RU": [["eur", 0.92], ["med", 0.06], ["eas", 0.02]],
	"CN": [["eas", 1.0]],
	"IR": [["med", 0.9], ["eur", 0.1]],
	"insurgent": [["med", 0.55], ["sas", 0.45]],
}
const DEFAULT_GROUPS := [["eur", 0.5], ["med", 0.5]]
## Men's hair styles and beards by nation: shares in the order of the constants above.
const HAIR_STYLES := {
	"contractor": [0.2, 0.2, 0.3, 0.15, 0.1, 0.05],
	"RU": [0.4, 0.2, 0.25, 0.0, 0.1, 0.05],
	"CN": [0.35, 0.3, 0.35, 0.0, 0.0, 0.0],
	"IR": [0.2, 0.1, 0.4, 0.2, 0.0, 0.1],
	"insurgent": [0.1, 0.0, 0.3, 0.4, 0.1, 0.1],
}
const FEMALE_HAIR_STYLES: Array[float] = [0.4, 0.2, 0.25, 0.15]
const BEARDS := {
	"contractor": [0.3, 0.25, 0.05, 0.22, 0.12, 0.06],
	"RU": [0.55, 0.3, 0.1, 0.05, 0.0, 0.0],
	"CN": [0.85, 0.15, 0.0, 0.0, 0.0, 0.0],
	"IR": [0.15, 0.35, 0.1, 0.3, 0.1, 0.0],
	"insurgent": [0.0, 0.1, 0.0, 0.25, 0.6, 0.05],
}
## Noses by group: small, straight, large, broad.
const NOSES := {
	"eur": [0.3, 0.45, 0.2, 0.05], "med": [0.15, 0.35, 0.4, 0.1], "sas": [0.2, 0.4, 0.3, 0.1],
	"afr": [0.2, 0.2, 0.0, 0.6], "eas": [0.5, 0.1, 0.0, 0.4],
}
## Builds (slim, average, heavy) and the average height (a share of the model's own: 1.80 m a
## man, CharacterModel.FEMALE_SCALE of it a woman) by nation.
const BUILDS := {"insurgent": [0.45, 0.45, 0.1], "IR": [0.3, 0.5, 0.2]}
const DEFAULT_BUILDS: Array[float] = [0.25, 0.5, 0.25]
const MEAN_HEIGHT := {"US": 1.0, "UK": 0.99, "CA": 0.995, "RU": 0.985, "CN": 0.965, "IR": 0.975, "insurgent": 0.955}


## A look for someone of `nation` with body type `body` (VoxelArt.MALE, FEMALE), the same every
## time for the same `seed`. `skin` (hex) keeps a skin tone already chosen (a civilian's bare
## hands, PersonLook) instead of rolling one.
static func make(seed: int, nation: String, body: String, skin := "") -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var female := body == VoxelArt.FEMALE
	var group := String(_pick_pair(rng, NATION_GROUPS.get(nation, DEFAULT_GROUPS)))
	var tones: Array = SKINS[group]
	var skin_hex := skin if skin != "" else String(tones[rng.randi_range(0, tones.size() - 1)])
	var hair := String(_pick_pair(rng, HAIR[group]))
	if rng.randf() < GREY_SHARE and not female:
		hair = GREY[rng.randi_range(0, GREY.size() - 1)]
	var eye := String(_pick_pair(rng, EYES[group]))
	var kind := nation if HAIR_STYLES.has(nation) else "contractor"
	var digits := [
		_pick(rng, FEMALE_HAIR_STYLES if female else HAIR_STYLES[kind]),
		0 if female else _pick(rng, BEARDS[kind]),
		rng.randi_range(0, 2),                       # jaw: narrow, middling, square
		_pick(rng, [0.25, 0.5, 0.25]),              # chin: receding, middling, strong
		_pick(rng, NOSES[group]),
		0 if female else _pick(rng, [0.6, 0.4]),    # brow ridge: soft, heavy
		_pick(rng, [0.5, 0.5]),                     # cheekbones: flat, high
		_pick(rng, [0.8, 0.2]),                     # ears: flat, standing out
	]
	var build := _pick(rng, BUILDS.get(nation, DEFAULT_BUILDS))
	var height := float(MEAN_HEIGHT.get(nation, 0.99)) + clampf(rng.randfn(0.0, HEIGHT_SD), -HEIGHT_SPREAD, HEIGHT_SPREAD)
	return "%s:%s:%s:%s:%d:%d" % [skin_hex, hair, eye, "".join(digits.map(func(d: int) -> String: return str(d))), build, roundi(height * 1000.0)]


## A seed from words that name a person (their callsign, name, nationality): the same on every peer.
static func seed_of(words: Array) -> int:
	return hash("look:" + ":".join(words.map(func(w: Variant) -> String: return str(w))))


## Whether `code` is a look code (make()).
static func valid(code: String) -> bool:
	var f := code.split(":")
	return f.size() == 6 and f[3].length() == SHAPE_KEYS.size() and f[3].is_valid_int() and f[4].is_valid_int() and f[5].is_valid_int()


## A look code's parts: "skin", "hair", "eye" (hex), "shape" (the digits), each SHAPE_KEYS digit
## by name ("hair_style" for the hair's), "build" and "height". An invalid code reads as DEFAULT.
static func parse(code: String) -> Dictionary:
	if not valid(code):
		code = DEFAULT
	var f := code.split(":")
	var out := {"skin": f[0], "hair": f[1], "eye": f[2], "shape": f[3], "build": clampi(f[4].to_int(), SLIM, HEAVY),
		"height": clampf(f[5].to_int() / 1000.0, 0.85, 1.15)}
	for i in SHAPE_KEYS.size():
		out["hair_style" if SHAPE_KEYS[i] == "hair" else SHAPE_KEYS[i]] = f[3].substr(i, 1).to_int()
	return out


## The head model for `code` on body type `body` ("head:<shape>", "head_f:<shape>").
static func head_model(code: String, body: String) -> String:
	var shape := String(parse(code).shape) if valid(code) else (DEFAULT_FEMALE_SHAPE if body == VoxelArt.FEMALE else DEFAULT_SHAPE)
	return "%s:%s" % [VoxelArt.body_part("head", body), shape]


## The colour scheme the head and face are built in (VoxelArt "face:<skin>:<hair>:<eye>").
static func palette(code: String) -> String:
	var p := parse(code)
	return "%s%s:%s:%s" % [VoxelArt.FACE_PREFIX, p.skin, p.hair, p.eye]


## How tall the body is drawn, as a share of its type's own size.
static func height_of(code: String) -> float:
	return float(parse(code).height) if valid(code) else 1.0


## How broad the trunk is drawn (BUILD_GIRTH).
static func girth_of(code: String) -> float:
	return BUILD_GIRTH[int(parse(code).build)] if valid(code) else 1.0


## An index into `shares` by weight.
static func _pick(rng: RandomNumberGenerator, shares: Array) -> int:
	var total := 0.0
	for s: float in shares:
		total += s
	var roll := rng.randf() * total
	for i in shares.size():
		roll -= float(shares[i])
		if roll <= 0.0 and float(shares[i]) > 0.0:
			return i
	return shares.size() - 1


## The first of a [value, share] pair picked by share.
static func _pick_pair(rng: RandomNumberGenerator, pairs: Array) -> Variant:
	var shares: Array = pairs.map(func(p: Array) -> float: return float(p[1]))
	return pairs[_pick(rng, shares)][0]
