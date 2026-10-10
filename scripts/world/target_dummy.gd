class_name TargetDummy
extends StaticBody3D
## Armored target for testing plates and weapons. Uses the same Inventory, Vitals and
## GearRig as players, so whatever works on a dummy works on a squadmate later.

@export var loadout: PackedStringArray
## Seconds a dummy stays down (or dead) before it gets back up on its own.
@export var respawn_seconds := 4.0

@onready var model: CharacterModel = $Model

@onready var inventory: Inventory = $Inventory
@onready var vitals: Vitals = $Vitals
@onready var gear: GearRig = $Gear
@onready var label: Label3D = $Label


func _ready() -> void:
	add_to_group(&"combatants")
	if multiplayer.is_server():
		for id in loadout:
			inventory.take(StringName(id))
	vitals.died.connect(_on_died)
	vitals.went_down.connect(_on_died)  # down or dead, a dummy just gets back up later
	vitals.changed.connect(_update_label)
	_update_label()


func _process(_delta: float) -> void:
	CharacterModel.lay_down(self, model, not vitals.is_up())  # down or dead


func _update_label() -> void:
	var status := vitals.condition_text()
	var lines := PackedStringArray([status])
	var armor := gear.armor_summary("\n")
	if armor != "":
		lines.append(armor)
	label.text = "\n".join(lines)


func _on_died() -> void:
	if not multiplayer.is_server():
		return
	await get_tree().create_timer(respawn_seconds).timeout
	if not vitals.is_up():
		vitals.server_reset_health()
