extends Vitals
## Test double for the armor test: records every impact and hit, then lets Vitals handle
## them as usual.

var impacts: Array[Dictionary] = []
var hits: Array[Dictionary] = []


func server_impact(part: StringName, round_class: StringName, distance: float, energy_j := -1.0) -> void:
	impacts.append({"part": part, "round_class": round_class, "distance": distance, "energy_j": energy_j})
	super(part, round_class, distance, energy_j)


func server_hit(part: StringName, hit: Dictionary) -> void:
	hits.append({"part": part, "hit": hit})
	super(part, hit)
