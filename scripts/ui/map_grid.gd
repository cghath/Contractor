class_name MapGrid
extends RefCounted
## Arma-style grid references for a level's map_area() (a Rect2 in metres on the ground:
## x along x, y along z).
##
## North is -z. The grid's origin is the map area's south-west corner (its smallest x and
## largest z), so eastings count east from the west edge and northings count north from the
## south edge, as on an Arma map. A reference gives the same number of digits per axis:
## 3 per axis ("012 034", Arma's 6-digit grid) names a 100 m square, 4 per axis
## ("0123 0345", 8-digit) a 10 m square and 5 per axis a 1 m square.

## Digits per axis the game uses by default (a 10 m square), and the coarse one (100 m).
const FINE_DIGITS := 4
const COARSE_DIGITS := 3
const MIN_DIGITS := 1
const MAX_DIGITS := 5


## Size of one grid square, in metres, for `digits` per axis (3 -> 100 m, 4 -> 10 m).
static func square_m(digits: int) -> float:
	return pow(10.0, 5 - clampi(digits, MIN_DIGITS, MAX_DIGITS))


## Metres east of the west edge and north of the south edge for a ground point (x, z).
static func to_grid_m(point: Vector2, area: Rect2) -> Vector2:
	return Vector2(point.x - area.position.x, area.end.y - point.y)


## The ground point (x, z) for metres east and north of the grid origin.
static func from_grid_m(grid_m: Vector2, area: Rect2) -> Vector2:
	return Vector2(area.position.x + grid_m.x, area.end.y - grid_m.y)


## The grid reference of a ground point (x, z): "easting northing", `digits` per axis, zero
## padded ("0123 0456"). Points west or south of the map clamp to 0.
static func grid_ref(point: Vector2, area: Rect2, digits := FINE_DIGITS) -> String:
	var d := clampi(digits, MIN_DIGITS, MAX_DIGITS)
	var square := square_m(d)
	var g := to_grid_m(point, area)
	var top := int(pow(10.0, d)) - 1
	var e := clampi(floori(g.x / square), 0, top)
	var n := clampi(floori(g.y / square), 0, top)
	return "%s %s" % [_padded(e, d), _padded(n, d)]


## The grid reference of a world position (Vector3, using x and z).
static func grid_ref_3d(pos: Vector3, area: Rect2, digits := FINE_DIGITS) -> String:
	return grid_ref(Vector2(pos.x, pos.z), area, digits)


## The centre of the square a reference names, as a ground point (x, z), or null if `ref`
## isn't a grid reference. Takes "0123 0456", "0123-0456" or "01230456" (split in half).
static func parse(ref: String, area: Rect2) -> Variant:
	var digits := ""
	var parts := PackedStringArray()
	for chunk in ref.strip_edges().replace("-", " ").replace(",", " ").split(" ", false):
		parts.append(chunk)
	if parts.size() == 1:
		digits = parts[0]
		if digits.length() % 2 != 0:
			return null
		parts = PackedStringArray([digits.substr(0, digits.length() / 2), digits.substr(digits.length() / 2)])
	if parts.size() != 2 or parts[0].length() != parts[1].length() or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	var d := parts[0].length()
	if d < MIN_DIGITS or d > MAX_DIGITS or parts[0].begins_with("-") or parts[1].begins_with("-"):
		return null
	var square := square_m(d)
	var g := Vector2((parts[0].to_int() + 0.5) * square, (parts[1].to_int() + 0.5) * square)
	return from_grid_m(g, area)


## Grid line spacing (metres) for a map drawn at `px_per_m`, so lines stay at least
## `min_px` apart: 1, 10, 100 or 1000 m.
static func line_spacing(px_per_m: float, min_px := 40.0) -> float:
	var spacing := 1.0
	while spacing * px_per_m < min_px and spacing < 1000.0:
		spacing *= 10.0
	return spacing


## Digits per axis worth showing at a spacing (10 m squares -> 4, 100 m -> 3...).
static func digits_for_spacing(spacing_m: float) -> int:
	return clampi(5 - roundi(log(maxf(spacing_m, 1.0)) / log(10.0)), MIN_DIGITS, MAX_DIGITS)


## The label of grid line `index` (counted from the origin) at `spacing_m`: the easting or
## northing digits of the square that starts on that line ("012").
static func line_label(index: int, spacing_m: float) -> String:
	var d := digits_for_spacing(spacing_m)
	return _padded(maxi(index, 0), d)


static func _padded(value: int, digits: int) -> String:
	return str(value).pad_zeros(digits)
