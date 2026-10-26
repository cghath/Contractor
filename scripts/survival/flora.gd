class_name Flora
extends RefCounted
## Regrowth over a world's months (docs/survival_nature.md; call 104): grass through the asphalt,
## roads and yards closing in, the longer a world runs the more abandoned it looks. regrowth(day) is
## the share of the way to fully overgrown (1 - exp(-day / days), data/survival_flora.json); the
## zone reads it on the host (server_apply) and sends it to every peer (Nature), and ZoneScatter's
## ground cover takes it: grass_now more tufts (up to grass_max_x) and road_now of the tufts that
## would keep off a road growing on it. The settlement's walked paths stay clear: within its radius
## (clear_circles) no extra growth. Every number here is Proposed.

## What ZoneScatter's ground cover reads (every peer; 1 and 0 outside survival: nothing changes).
static var grass_now := 1.0
static var road_now := 0.0
## [[x, z, r]] circles kept clear (the settlement's paths).
static var clear_circles: Array = []


static func spec() -> Dictionary:
	return Nature.flora().get("regrowth", {})


## The share of the way to overgrown after `day` world days (0 .. 1, rising).
static func regrowth(day: int) -> float:
	return 1.0 - exp(-float(maxi(day, 0)) / maxf(float(spec().get("days", 120.0)), 1.0))


## The grass's multiplier on day `day` (1 .. grass_max_x).
static func grass_x(day: int) -> float:
	return 1.0 + (float(spec().get("grass_max_x", 1.8)) - 1.0) * regrowth(day)


## The share of a road's ground growing over on day `day`.
static func road_share(day: int) -> float:
	return float(spec().get("road_share_max", 0.6)) * regrowth(day)


## Whether (x, z) is kept clear (a settlement's walked ground).
static func path_clear(x: float, z: float) -> bool:
	for c: Array in clear_circles:
		var dx := x - float(c[0])
		var dz := z - float(c[1])
		if dx * dx + dz * dz <= float(c[2]) * float(c[2]):
			return true
	return false


## Host: today's regrowth and the settlement's clear circle, here and on the peers.
static func server_apply(_level: Node) -> void:
	var circles: Array = []
	if Settlement.exists() and Settlement.zone() == Nature.zone():
		var p := Settlement.pos()
		circles.append([p.x, p.z, Settlement.radius()])
	set_now(grass_x(Survival.day()), road_share(Survival.day()), circles)


static func set_now(grass: float, road: float, circles: Array) -> void:
	grass_now = grass
	road_now = road
	clear_circles = circles


## Off survival: nothing grows over.
static func reset() -> void:
	set_now(1.0, 0.0, [])
