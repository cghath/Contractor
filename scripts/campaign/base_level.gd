class_name BaseLevel
extends CompoundLevel
## The company's base hub (wave 4) as its own little level: a walkable FOB inside a HESCO
## perimeter, where the company lives between deployments. It is a CompoundLevel (players, items,
## AI and bodies spawn and replicate the same way, and Soldier finds it with CompoundLevel.current),
## with no hostiles and no zone loot. The FOB itself (terminals, stash, delivery, muster line,
## its voxels) is BaseFob, shared with the base zone (BaseZoneLevel, docs/linked_zones.md LZ-1);
## this level stays as the fallback (and the suites' base) until the base zone is proven.
## Campaign state is BaseHub's; the FOB only shows it and reads the stash back.

const BASE_SPAWNS := BaseFob.BASE_SPAWNS
const MUSTER_ORIGIN := BaseFob.MUSTER_ORIGIN
const MUSTER_STEP := BaseFob.MUSTER_STEP
const MUSTER_ROWS := BaseFob.MUSTER_ROWS
const MUSTER_PER_ROW := BaseFob.MUSTER_PER_ROW
const MUSTER_MAX := BaseFob.MUSTER_MAX
const DELIVERY := BaseFob.DELIVERY
const TERMINALS := BaseFob.TERMINALS
const PERIMETER_HALF := BaseFob.PERIMETER_HALF
const GATE_HALF := BaseFob.GATE_HALF

var fob: BaseFob


func _ready() -> void:
	super._ready()
	fob = BaseFob.make(self, Vector3.ZERO, false)


func is_base() -> bool:
	return true


## Whether the FOB's voxels are up (the muster line waits for them).
func fob_ready() -> bool:
	return voxel_world.is_built()


func next_spawn_point() -> Vector3:
	_spawn_index += 1
	return fob.spawn_point(_spawn_index)


## What a joining client loads to play here (LevelSwitch).
func level_info() -> Dictionary:
	return {"level": "base"}


## The map of the hub covers the FOB inside its HESCO perimeter.
func map_area() -> Rect2:
	return Rect2(-PERIMETER_HALF, -PERIMETER_HALF, PERIMETER_HALF * 2.0, PERIMETER_HALF * 2.0)


## Host: the hub comes up with the stash, the host's player and the muster line. No zone save
## (the hub's state is the campaign's), no hostiles.
func _on_hosted() -> void:
	GameState.looted.clear()
	GameState.dropped.clear()
	GameState.voxel_edits.clear()
	GameState.bodies.clear()
	server_spawn_stash(BaseHub.stash())
	player_roles[1] = Roles.local_choice
	_add_player(1)
	NavBuilder.build(self)
	if voxel_world.is_built():
		_on_built()
	else:
		voxel_world.structures_built.connect(_on_built, CONNECT_ONE_SHOT)


func _on_built() -> void:
	server_show_roster()
	BaseHub.server_level_ready(self)


# --- The FOB's public face (BaseFob) ------------------------------------------------------

func server_spawn_stash(stash: Array) -> void:
	fob.server_spawn_stash(stash)


func server_collect_stash() -> Array:
	return fob.server_collect_stash()


func server_deliver(id: StringName, count: int, state := {}) -> void:
	fob.server_deliver(id, count, state)


func server_show_roster() -> void:
	fob.server_show_roster()


func server_read_muster_gear() -> Dictionary:
	return fob.server_read_muster_gear()


func muster_soldier(mid: String) -> Soldier:
	return fob.muster_soldier(mid)


func _build_structures() -> void:
	for b: Array in BaseFob.structure_boxes():
		voxel_world.add_box_m(b[0], b[1], b[2])
