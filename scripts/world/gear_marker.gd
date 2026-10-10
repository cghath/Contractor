class_name GearMarker
extends Label3D
## Floating label over a dead player's gear, visible through walls. It removes itself once
## nothing is left on the ground near it.

const RADIUS := 3.0
const CHECK_S := 1.0
## Items reach clients a moment after the marker; don't judge before they've arrived.
const GRACE_S := 3.0

var _age := 0.0
var _next_check := GRACE_S


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0015
	font_size = 28
	outline_size = 8
	modulate = Color("ffd166")


func _process(delta: float) -> void:
	_age += delta
	if _age < _next_check:
		return
	_next_check = _age + CHECK_S
	var ground := global_position - Vector3.UP * 1.6
	for item in get_tree().get_nodes_in_group(WorldItem.GROUP):
		if (item as Node3D).global_position.distance_to(ground) <= RADIUS:
			return
	queue_free()
