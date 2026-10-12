class_name Vehicle
extends RigidBody3D
## A vehicle: ground vehicles players or AI drive, and the AI-flown helicopters (wave 5).
##
## WAVE 5 GROUNDWORK STUB. This file fixes the API the wave 5 workstreams build against:
## V1 (vehicle core) fills it in (driving, seats, cargo, hit zones, hull carving, wrecks);
## V2 (anti-armor) calls server_take_hit from its rounds; V3 (helicopter supports) and V4
## (AAVs, LHD, motor pool) build on V1's finished class. Keep these names and signatures;
## add to them freely.
##
## Host authoritative like everything shared: the host simulates the body and decides hits,
## seats and cargo; clients send driving input and see the replicated state. A late joiner
## gets every vehicle's model, scheme, transform, seats, damage and cargo.
##
## The look is Captain's VehicleArt (scripts/art/vehicle_art.gd): `model` is one of
## VehicleArt.MODELS, `scheme` one of its schemes ("" = the model's first).

## Layer 7 ("vehicles"): hulls. Rounds (Ballistics.MASK), blasts and charges should meet it;
## a vehicle meets the world, other vehicles, soldiers and ragdolls (layer 6: a vehicle that
## hits a settled body calls Ragdoll.unfreeze() on it so it is pushed, not driven through).
const LAYER := 1 << 6
const MASK := 1 | (1 << 4) | Ragdoll.LAYER | LAYER  # world, movers, ragdolls, vehicles
const GROUP := &"vehicles"

## Hit kinds a `server_take_hit` dictionary names in "kind". Small arms come from Ballistics
## ("kinetic", with the round's id and energy); V2's launchers send the rest.
const KINETIC := &"kinetic"            # bullets: armour class decides bounce or penetrate
const HEAT := &"heat"                  # shaped charge: penetrates by "penetration_mm"
const TANDEM_HEAT := &"tandem_heat"    # defeats reactive armour first
const HE := &"he"                      # blast and fragments: light vehicles, crews outside
const HEDP := &"hedp"                  # both, weaker at each
const THERMOBARIC := &"thermobaric"    # overpressure: crews and structures, little armour
const TOP_ATTACK := &"top_attack"      # Javelin, NLAW overfly: hits the roof's armour

## Hit zones V1 models (names, so other code can ask about them).
const ZONE_HULL := &"hull"
const ZONE_ENGINE := &"engine"
const ZONE_WHEELS := &"wheels"   # or tracks
const ZONE_CREW := &"crew"
const ZONE_CARGO := &"cargo"
const ZONE_ROTOR := &"rotor"     # helicopters

signal seats_changed
signal damaged(zone: StringName, hit: Dictionary)
signal destroyed(vehicle: Vehicle)

## Which VehicleArt model and paint scheme (set before the vehicle enters the tree).
@export var model := "matv"
@export var scheme := ""
## Owning side (the same faction names soldiers use), for AI and supports.
@export var faction := &"player"
## Stable id within a zone: saves, wrecks and the motor pool find a vehicle by it.
var vehicle_id := ""
## True once destroyed: it stays as a wreck (saved with the zone).
var wrecked := false


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER
	collision_mask = MASK


## The vehicle a collider belongs to (a hull, a hit-zone shape or a child of one), or null.
static func find_on(node: Object) -> Vehicle:
	var n := node as Node
	for i in 6:
		if n == null:
			return null
		if n is Vehicle:
			return n
		n = n.get_parent()
	return null


## Host: a hit on this vehicle. `hit` holds at least "kind" (one of the kinds above),
## "position" and "direction" (world space), and "shooter" (a node or null); kinetic hits add
## "round" (the rounds.json id), "energy_j" and "level" (Ballistics.LEVELS); launcher hits
## add "penetration_mm" and "blast_kg" (TNT equivalent). Returns {"stopped": bool,
## "zone": StringName, "penetrated": bool}: a round that isn't stopped flies on into the
## cabin (the caller carries on with it, e.g. into the crew's hitboxes).
func server_take_hit(hit: Dictionary) -> Dictionary:
	damaged.emit(ZONE_HULL, hit)
	return {"stopped": true, "zone": ZONE_HULL, "penetrated": false}


## The seats: an Array of {"name": String, "kind": "driver"|"gunner"|"passenger"|"pilot",
## "occupant": Soldier or null}. V1 builds them per model.
func seats() -> Array:
	return []


## Host: put `soldier` in seat `index` (-1: the first free one). Returns whether it worked.
func server_enter(_soldier: Node, _index := -1) -> bool:
	return false


## Host: take `soldier` out of the vehicle to a safe spot beside it.
func server_exit(_soldier: Node) -> void:
	pass


## The soldiers aboard.
func occupants() -> Array:
	return []


## The cargo stash (an Inventory) or null when the vehicle carries none.
func cargo() -> Node:
	return null


## JSON-safe state for the zone save and the motor pool (model, scheme, transform, damage,
## cargo, wrecked); from_save restores it.
func to_save() -> Dictionary:
	return {"id": vehicle_id, "model": model, "scheme": scheme, "faction": String(faction), "wrecked": wrecked}


func from_save(data: Dictionary) -> void:
	vehicle_id = String(data.get("id", vehicle_id))
	model = String(data.get("model", model))
	scheme = String(data.get("scheme", scheme))
	faction = StringName(data.get("faction", faction))
	wrecked = bool(data.get("wrecked", false))
