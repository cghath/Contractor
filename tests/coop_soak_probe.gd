extends "res://tests/coop_soak.gd"
## The soak bot's rules without the soak: no _ready (nothing starts), and peers other than the
## host's own (1) are stand-in soldiers (tests/coop_soak_checks_test.gd).

var stand_ins := {}


func _ready() -> void:
	pass


func _player(peer: int) -> Soldier:
	if stand_ins.has(peer):
		return stand_ins[peer]
	return super(peer)
