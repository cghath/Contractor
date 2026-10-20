class_name MortarTable
extends RefCounted
## A mortar's firing table (G-25 part d): how far a round goes for a charge and an elevation,
## the way the panel shows it and the host fires it (the same numbers both ends). High-angle fire
## only: ELEVATION_MILS (6400 mils to the circle), and each charge throws the round at a share of
## the top charge's speed (CHARGE_SHARES), the top charge at 800 mils reaching the weapon's max_m.
## No drag (a short-range simplification; Proposed).

const ELEVATION_MILS := Vector2(800.0, 1511.0)
const CHARGE_SHARES: Array[float] = [0.3, 0.45, 0.6, 0.75, 0.88, 1.0]
const G := 9.81


## The charges a mortar `m` (StaticWeapons.KITS[..].mortar) has: 0 to its "charges" (default 4).
static func charges(m: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for c in int(m.get("charges", 4)) + 1:
		out.append(c)
	return out


## The muzzle speed for `charge` (m/s).
static func speed(m: Dictionary, charge: int) -> float:
	var top := sqrt(float(m.max_m) * G)  # 45 degrees, the top charge: the maximum range
	var n := int(m.get("charges", 4))
	var share := CHARGE_SHARES[clampi(roundi(float(charge) / maxf(n, 1) * (CHARGE_SHARES.size() - 1)), 0, CHARGE_SHARES.size() - 1)]
	return top * share


## How far (m, level ground) a round goes at `charge` and `mils` elevation.
static func range_m(m: Dictionary, charge: int, mils: float) -> float:
	var v := speed(m, charge)
	var theta := mils / 6400.0 * TAU
	return v * v * sin(2.0 * theta) / G


## The flat way a bearing (degrees from north, the map's up: -z) points.
static func bearing_dir(bearing_deg: float) -> Vector3:
	var b := deg_to_rad(bearing_deg)
	return Vector3(sin(b), 0.0, -cos(b))
