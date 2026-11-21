class_name SeasonLook
extends RefCounted
## How each season looks on the land (plans/fallen-seasons.md): one place for every seasonal colour
## and amount, read by SeasonLive (the live blend) and through it the ground shader, the grass,
## the wild trees, the water and the falling leaves. Static tables; every number here is Proposed.
##
## Colours are sRGB hex. "tint" multiplies the ground's colour, "dry" pulls it toward the ground
## shader's dry_colour (straw), "grass" replaces the grass carpet's and tufts' colours, "crown" the
## broadleaf crowns' (conifers keep the preset's), "leaf" is how much of a broadleaf crown is
## there (1 full, 0 bare: winter), "leaves" how many falling leaves per second near woods, "bush"
## the scrub's and thickets' colours (they keep their shape and cover: a leafless hedge still hides a
## man) and "reeds" the reed beds' (dead straw in winter).

const LOOKS := {
	"spring": {"tint": "f2f7e8", "dry": 0.0, "grass": ["5f7d35", "6a8a3c", "57712f"],
		"crown": ["6f9440", "7a9e48", "64883a"], "leaf": 0.85, "leaves": 0.0,
		"bush": ["5f7a38", "6a8240", "566e32"], "reeds": ["6f8a3e", "7d9046", "64803a"]},
	"summer": {"tint": "ffffff", "dry": 0.1, "grass": [], "crown": [], "leaf": 1.0, "leaves": 0.0, "bush": [], "reeds": []},
	"autumn": {"tint": "f4ead8", "dry": 0.45, "grass": ["8a7f4a", "7c7444", "93804c"],
		"crown": ["9a5a26", "b07a2e", "8a7a32", "6e7230", "a0442a"], "leaf": 0.7, "leaves": 40.0,
		"bush": ["7a6a3a", "6e6a3c", "856c3a"], "reeds": ["9a8a56", "a08f5a", "8c7e4e"]},
	"winter": {"tint": "d8d6d0", "dry": 0.6, "grass": ["6f6a58", "66604f", "777162"],
		"crown": ["5e5244", "6a5a48"], "leaf": 0.0, "leaves": 0.0,
		"bush": ["5a5240", "625a46", "54503e"], "reeds": ["b8a878", "a8986a", "c2b384"]},
}
## How long the land takes to change when the season turns mid-visit (s).
const BLEND_S := 20.0
## Lowland snow's walking slow (Captain, 2026-11-21: 0.15; the mountain presets keep their 0.25).
const LOWLAND_SNOW_SLOW := 0.15
## The day of winter (1..Seasons.SEASON_DAYS) the ponds and streams take weight from.
const ICE_FROM_DAY := 2


## The look of `season` (summer's if unknown): a copy of its LOOKS entry.
static func of(season: String) -> Dictionary:
	return (LOOKS.get(season, LOOKS.summer) as Dictionary).duplicate(true)


## 0 to 1: how much lowland snow lies in `season` on its day `day` (1..Seasons.SEASON_DAYS).
static func snow(season: String, day: int) -> float:
	if season != "winter":
		return 0.0
	if day <= 1:
		return 0.3  # the first dusting: the ground shows through
	if day < 8:
		return 1.0  # lying white
	# The thaw coming: from day 8 the cover thins to half by the season's last day.
	return lerpf(1.0, 0.5, float(day - 7) / float(Seasons.SEASON_DAYS - 7))


## Whether still water carries weight (walkable ice) in `season` on its day `day`. Steadier than
## Seasons.water_frozen(), which also flips on and off with each night's hard frost: the nav mesh is
## rebaked at every change, so the ice holds from ICE_FROM_DAY to the end of winter.
static func ice(season: String, day: int) -> bool:
	return season == "winter" and day >= ICE_FROM_DAY


## The look's colours as Colors (`key`: "grass" or "crown"); empty means keep the preset's.
static func colours(look: Dictionary, key: String) -> Array[Color]:
	var out: Array[Color] = []
	for c: Variant in look.get(key, []):
		out.append(Color(String(c)))
	return out
