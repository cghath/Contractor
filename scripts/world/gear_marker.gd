class_name GearMarker
extends Label3D
## Floating label over a dead player's body, where all their gear still is, visible through
## walls (the handoff's gear marker, until there's a map). It's a child of the body
## (CompoundLevel.server_spawn_body), so it follows the body when it's carried or dragged and
## goes with it; it removes itself once nothing is left on the body.

const GROUP := &"gear_markers"
## Height above the body's origin.
const HEIGHT := 1.6
const CHECK_S := 1.0
## The body's gear reaches clients a moment after the body; don't judge before it has arrived.
const GRACE_S := 3.0

var _age := 0.0
var _next_check := GRACE_S


func _ready() -> void:
	add_to_group(GROUP)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0015
	font_size = 28
	outline_size = 8
	modulate = Color("ffd166")


## The body this marks (its parent), or null.
func body() -> Soldier:
	return get_parent() as Soldier


func _process(delta: float) -> void:
	_age += delta
	if _age < _next_check:
		return
	_next_check = _age + CHECK_S
	var marked := body()
	if marked == null or not marked.has_gear():
		queue_free()
