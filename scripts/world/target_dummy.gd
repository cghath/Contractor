class_name TargetDummy
extends StaticBody3D
## Armored target for testing plates and weapons. Uses the same Inventory, Vitals and
## GearRig as players, so whatever works on a dummy works on a squadmate later.

@export var loadout: PackedStringArray
@export var respawn_seconds := 3.0

@onready var inventory: Inventory = $Inventory
@onready var vitals: Vitals = $Vitals
@onready var gear: GearRig = $Gear
@onready var label: Label3D = $Label


func _ready() -> void:
	if multiplayer.is_server():
		for id in loadout:
			inventory.take(StringName(id))
	vitals.died.connect(_on_died)
	vitals.changed.connect(_update_label)
	_update_label()


func _update_label() -> void:
	var lines := PackedStringArray(["HP %d" % vitals.health])
	var armor := gear.armor_summary("\n")
	if armor != "":
		lines.append(armor)
	label.text = "\n".join(lines)


func _on_died() -> void:
	await get_tree().create_timer(respawn_seconds).timeout
	vitals.server_reset_health()
