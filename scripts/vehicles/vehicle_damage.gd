class_name VehicleDamage
extends RefCounted
## How a hit on a vehicle comes out (wave 5, host side, pure: no nodes): which hit zone it
## meets, whether its armour stops it, and how much damage gets through. Vehicle.server_take_hit
## applies the result.
##
## Kinetic rounds go by vehicle threat tier (VehicleSpecs.round_tier) against the zone's armour
## class (Captain, decided: small calibre doesn't defeat vehicle armour; 7.62x54R and up can
## penetrate or disable): a tier above what the class resists goes through, losing the class's
## loss_j of energy; anything else glances off and does no damage. Shaped charges (HEAT,
## tandem HEAT, top attack) go by penetration_mm against the class's rha_mm (roof_mm from
## above); reactive armour ("era") eats ERA_MM of a single HEAT jet, never a tandem one's.
## HE, HEDP and thermobaric hit by blast_kg times the class's blast share. Every number here
## is Proposed.

## Kilojoules of damage a penetrating kinetic round does: the energy the armour took from it,
## plus SPENT_SHARE of what it carried on with, times TIER_MULT by tier (bigger rounds wreck
## more than their energy says).
const SPENT_SHARE := 0.25
const TIER_MULT: Array[float] = [1.0, 1.5, 2.5, 4.0]
## A HEAT jet through the armour: BASE plus PER_BLAST_KG per kg of the warhead's explosive
## (PG-7V about 0.73 kg), plus PER_EXCESS_MM per mm of penetration left over.
const HEAT_BASE_KJ := 40.0
const HEAT_PER_BLAST_KG := 100.0
const HEAT_PER_EXCESS_MM := 0.05
## A warhead that didn't get through: its blast against the outside (times the class's blast).
const HEAT_STOPPED_PER_KG := 15.0
## HE and thermobaric blasts: kJ per kg of explosive (times the class's blast share);
## thermobaric hits crews more and armour less.
const HE_PER_KG := 60.0
const THERMOBARIC_PER_KG := 35.0
## Reactive armour: millimetres a single HEAT jet loses to it.
const ERA_MM := 300.0
## Share of a hit's damage the hull takes as well as its zone (the hull at 0: destroyed).
const HULL_SHARE := 0.5
## Chance a penetrating hit starts a fire, by zone (kinetic, then shaped charge).
const FIRE_CHANCE := {&"fuel": [0.12, 0.6], &"engine": [0.03, 0.3], &"crew": [0.0, 0.15], &"cargo": [0.0, 0.15], &"hull": [0.0, 0.1]}
## A shaped charge's jet that gets through throws spall at the crew this far round its hole.
const SPALL_RADIUS_M := 2.5
## Hits from steeper than this (direction's y) count as from above (roof armour).
const FROM_ABOVE_Y := -0.6

const KINDS_HEAT: Array[StringName] = [&"heat", &"tandem_heat", &"top_attack"]


## The zone at `local` (vehicle frame, metres) on a model's spec: {"zone", "armour", "hp_kj",
## "era"}; the hull with the model's default armour where no zone box holds it.
static func zone_at(spec: Dictionary, local: Vector3) -> Dictionary:
	for z: Dictionary in spec.get("zones", []):
		if VehicleSpecs.box(z.box).grow(0.05).has_point(local):
			return {"zone": StringName(z.zone), "armour": String(z.get("armour", spec.get("default_armour", "soft"))),
				"hp_kj": float(z.get("hp_kj", 50.0)), "era": bool(z.get("era", spec.get("default_era", false)))}
	return {"zone": Vehicle.ZONE_HULL, "armour": String(spec.get("default_armour", "soft")),
		"hp_kj": float(spec.get("hp", {}).get("hull", 100.0)), "era": bool(spec.get("default_era", false))}


## Resolves a hit (the dictionary Vehicle.server_take_hit takes) on the zone `zone`
## (zone_at). `local_dir` is the round's direction in the vehicle's frame. Returns
## {"stopped", "penetrated", "damage_kj", "energy_left" (kinetic), "fire_chance", "spall",
## "crew_blast" (thermobaric: overpressure inside)}.
static func resolve(hit: Dictionary, zone: Dictionary, local_dir: Vector3) -> Dictionary:
	var kind := StringName(hit.get("kind", Vehicle.KINETIC))
	var cls := VehicleSpecs.armour(zone.armour)
	var out := {"stopped": true, "penetrated": false, "damage_kj": 0.0, "energy_left": 0.0, "fire_chance": 0.0, "spall": false, "crew_blast": 0.0}
	var from_above := kind == Vehicle.TOP_ATTACK or local_dir.y < FROM_ABOVE_Y
	var chances: Array = FIRE_CHANCE.get(zone.zone, [0.0, 0.0])
	match kind:
		Vehicle.KINETIC:
			var tier := VehicleSpecs.round_tier(StringName(hit.get("round", "")))
			var energy := float(hit.get("energy_j", 0.0))
			if tier <= int(cls.resists) or energy <= 0.0:
				return out  # glances off: a scuff, no damage
			var loss := float(cls.loss_j)
			out.damage_kj = (minf(energy, loss) + SPENT_SHARE * maxf(energy - loss, 0.0)) / 1000.0 * TIER_MULT[clampi(tier, 0, TIER_MULT.size() - 1)]
			out.energy_left = maxf(energy - loss, 0.0)
			out.penetrated = true
			out.stopped = out.energy_left <= 0.0
			out.fire_chance = float(chances[0])
		Vehicle.HEAT, Vehicle.TANDEM_HEAT, Vehicle.TOP_ATTACK:
			var pen := float(hit.get("penetration_mm", 0.0))
			var armour_mm := float(cls.roof_mm if from_above else cls.rha_mm)
			if zone.era and kind != Vehicle.TANDEM_HEAT:
				armour_mm += ERA_MM
			var blast := float(hit.get("blast_kg", 0.0))
			if pen > armour_mm:
				out.penetrated = true
				out.damage_kj = HEAT_BASE_KJ + HEAT_PER_BLAST_KG * blast + HEAT_PER_EXCESS_MM * (pen - armour_mm)
				out.fire_chance = float(chances[1])
				out.spall = true
			else:
				out.damage_kj = HEAT_STOPPED_PER_KG * blast * float(cls.blast)
		Vehicle.HE, Vehicle.HEDP, Vehicle.THERMOBARIC:
			var blast := float(hit.get("blast_kg", 0.0))
			var per := THERMOBARIC_PER_KG if kind == Vehicle.THERMOBARIC else HE_PER_KG
			out.damage_kj = per * blast * float(cls.blast)
			var pen := float(hit.get("penetration_mm", 0.0))
			if kind == Vehicle.HEDP and pen > float(cls.roof_mm if from_above else cls.rha_mm):
				out.penetrated = true
				out.damage_kj += HEAT_BASE_KJ * 0.5
				out.spall = true
				out.fire_chance = float(chances[1]) * 0.5
			if kind == Vehicle.THERMOBARIC:
				out.crew_blast = clampf(float(cls.blast) * 2.0, 0.0, 1.0)  # through hatches and vision blocks
			elif float(cls.blast) >= 0.8:
				out.fire_chance = maxf(out.fire_chance, float(chances[1]) * 0.5)  # soft-skinned: fuel and engine catch
	return out
