class_name EnclaveDetachment
extends RefCounted
## The enclave's detachments and patrols (docs/survival_world.md section 6;
## docs/survival_enclave.md): sub-records of the one enclave group. A post holds a place in one
## of the enclave's home zones (the port, the military base); a patrol walks a route of zones
## between them on the far tick. Their members are a share of the group's members (Person
## records, status grouped, in the enclave group); the group's strength, supplies and relations
## are the enclave's own. Static helpers over plain data:
##
## Post { id, kind: "post", name, zone, place, pos: [x, z], members: [person ids], kit: {ammo,
##   fuel, meds} }
## Patrol { id, kind: "patrol", name, members, kit, route: [zone ids, a loop], at: index into
##   route, progress 0-1 toward the next, zone }

## Proposed: a patrol takes this many far ticks a zone (the world sim's TRAVEL_TICKS: 2 h).
const TICKS_A_ZONE := WorldModel.TRAVEL_TICKS
## Proposed: kit a member carries (ammo units, fuel, meds).
const KIT := {"ammo": 6.0, "fuel": 1.0, "meds": 0.5}


static func make_post(id: String, name: String, zone_id: String, place: Dictionary, members: Array) -> Dictionary:
	var p: Array = place.get("pos", [0.0, 0.0])
	return {"id": id, "kind": "post", "name": name, "zone": zone_id, "place": String(place.get("id", "")), "pos": [float(p[0]), float(p[1])],
		"members": members.duplicate(), "kit": kit_for(members.size())}


static func make_patrol(id: String, name: String, route: Array, members: Array) -> Dictionary:
	return {"id": id, "kind": "patrol", "name": name, "members": members.duplicate(), "kit": kit_for(members.size()),
		"route": route.duplicate(), "at": 0, "progress": 0.0, "zone": String(route[0]) if not route.is_empty() else ""}


static func kit_for(n: int) -> Dictionary:
	var out := {}
	for k: String in KIT:
		out[k] = snappedf(float(KIT[k]) * n, 0.1)
	return out


## A loop over `path` (there and back, the ends once): [a, b, c] -> [a, b, c, b].
static func loop_of(path: Array) -> Array:
	var out := path.duplicate()
	for i in range(path.size() - 2, 0, -1):
		out.append(path[i])
	return out


## The route around `home`: out to each link and back ([home, l1, home, l2, ...]).
static func ring_of(home: String, links: Array) -> Array:
	var out: Array = []
	for l: String in links:
		out.append(home)
		out.append(l)
	if out.is_empty():
		out.append(home)
	return out


## One far tick of patrol `p`: a TICKS_A_ZONE share of the way to its route's next zone.
## Returns whether it came into a new zone.
static func step(p: Dictionary) -> bool:
	var route: Array = p.get("route", [])
	if route.size() < 2 or (p.get("members", []) as Array).is_empty():
		return false
	p.progress = float(p.get("progress", 0.0)) + 1.0 / TICKS_A_ZONE
	if float(p.progress) < 1.0:
		return false
	p.progress = 0.0
	p.at = (int(p.get("at", 0)) + 1) % route.size()
	var before := String(p.get("zone", ""))
	p.zone = String(route[int(p.at)])
	return String(p.zone) != before


## Keeps only `keep` (the group's living members) in `d`'s members; returns how many went.
static func prune(d: Dictionary, keep: Dictionary) -> int:
	var before := (d.get("members", []) as Array).size()
	d.members = (d.get("members", []) as Array).filter(func(pid: String) -> bool: return keep.has(pid))
	return before - (d.members as Array).size()


static func size(d: Dictionary) -> int:
	return (d.get("members", []) as Array).size()
