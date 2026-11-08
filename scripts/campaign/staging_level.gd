class_name StagingLevel
extends BaseZoneLevel
## The staging FOB as a level (combined arms D8, docs/combined_arms.md 8.1, 8.5): the host's own
## zone, its garrison and patrols as UsField has them, with the company's corner built in it as a
## 30 x 30 m module beside the host's HQ site: a tent with cots, a crate stack with the resupply
## terminal, two parking spots, a radio desk (the ops page, and the board from it). Everything
## else BaseHub expects of a base comes from BaseZoneLevel: a player's spawn inside the corner,
## the muster line (of those who came along), walking out through the crossings, every peer
## loading the same level.
##
## It isn't home: there's no armory or stash (the company's stash stays where it is, untouched:
## server_spawn_stash, server_collect_stash), nothing to hire, no workshop. What the terminal sells
## is left at the crate stack as world items, and what lies about here stays in the zone's own
## save ("staging_<zone>").

const TYPE := "staging"
const MODULE_ID := "staging_corner"
const HALF := Vector2(15.0, 15.0)
## Where the corner goes from the host's HQ site: offsets (m, multiples of the two halves) tried in
## order, the first clear of every other module.
const SIDES: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
## Metres kept between the corner's pad and another module's.
const CLEAR_M := 6.0
const LAYOUT_TERMINALS := [
	[&"ops", Vector3(0.0, 0.1, -11.0), 180.0],  # the radio desk: squad, deploy, the board
	[&"shop", Vector3(9.0, 0.1, -11.0), 180.0],  # the resupply terminal, by the crates
	[&"medbay", Vector3(-8.0, 0.1, -3.5), 0.0],  # the tent's desk
	[&"motor_pool", Vector3(6.0, 0.1, 10.5), 90.0],  # the parking's sign
]
const SPAWNS: Array[Vector3] = [Vector3(-3, 0.1, 3), Vector3(-1, 0.1, 3), Vector3(1, 0.1, 3), Vector3(3, 0.1, 3)]
## The parked vehicles (props: the vehicle itself comes to a deployment's insertion point, as the
## briefing's pool support, or stays here in the books).
const PARKING: Array[Vector3] = [Vector3(10.5, 0.0, 2.0), Vector3(10.5, 0.0, 9.0)]
## Bought kit is laid out from here along +x, in rows of DELIVERY_ROW.
const DELIVERY := Vector3(4.0, 0.3, -7.5)
const DELIVERY_ROW := 6

var _park: Node3D
var _park_models: Array = []
var _delivered := 0


## The level_info def for staging at `zone_id`: the zone as MissionRegistry makes it, with the
## company's corner by its HQ.
static func def_at(zone_id: String) -> Dictionary:
	var def := MissionRegistry.zone_def(zone_id).duplicate(true)
	var at := corner_spot(def)
	(def.modules as Array).append({"id": MODULE_ID, "type": TYPE, "pos": [at.x, at.y]})
	def["kind"] = "staging"
	def["no_pallets"] = true
	return def


## Where the corner stands in `def`: beside its host's HQ site on the first side clear of every
## module (ZoneDef's grid), else as near the zone's middle as that allows.
static func corner_spot(def: Dictionary) -> Vector2:
	var mods: Array = def.get("modules", [])
	var hq := UsField.hq_site(mods)
	var anchor := Vector2.ZERO
	var anchor_half := Vector2(20.0, 20.0)
	for m: Dictionary in mods:
		if String(m.id) == hq:
			anchor = Vector2(float(m.pos[0]), float(m.pos[1]))
			anchor_half = ZoneModules.pad_rect(String(m.type), anchor).size * 0.5
	var taken: Array[Rect2] = []
	for m: Dictionary in mods:
		taken.append(ZoneModules.pad_rect(String(m.type), Vector2(float(m.pos[0]), float(m.pos[1]))).grow(CLEAR_M))
	for ring in 4:
		for s: Vector2 in SIDES:
			var off := Vector2(s.x * (anchor_half.x + HALF.x + CLEAR_M + ring * 24.0), s.y * (anchor_half.y + HALF.y + CLEAR_M + ring * 24.0))
			var p := (anchor + off).snappedf(ZoneDef.GRID_M)
			var rect := Rect2(p - HALF, HALF * 2.0)
			if not taken.any(func(r: Rect2) -> bool: return r.intersects(rect)):
				return p
	return anchor.snappedf(ZoneDef.GRID_M)


## The corner's voxels (module space, metres: [from, to, Mat]): BaseFob's hut for the tent, its
## cots, the crate stack and a low wall of bags along two sides.
static func corner_boxes() -> Array:
	var out: Array = []
	var W := VoxelWorld.Mat.WOOD
	var B := VoxelWorld.Mat.SANDBAG
	BaseFob._hut(out, Vector2(-14.0, -14.0), Vector2(-3.0, -5.0), -9.0, -7.0, VoxelWorld.Mat.TARP)
	for i in 4:
		var x := -13.0 + i * 2.4
		out.append([Vector3(x, 0.0, -13.0), Vector3(x + 0.9, 0.5, -11.0), W])  # a cot
	ZoneModules._crates(out, Vector3(7.0, 0.0, -14.0))
	ZoneModules._crates(out, Vector3(10.0, 0.0, -14.0))
	out.append([Vector3(-1.0, 0.0, -12.5), Vector3(1.0, 0.8, -11.8), W])  # the radio desk's table
	out.append([Vector3(-15.0, 0.0, -15.0), Vector3(15.0, 1.0, -14.5), B])
	out.append([Vector3(-15.0, 0.0, -15.0), Vector3(-14.5, 1.0, 15.0), B])
	return out


## The corner (a BaseFob laid out as LAYOUT_TERMINALS, so BaseHub's muster and spawns just work) and
## its parking; no helipad, no assault of the company's to fight off here.
func _make_fob() -> void:
	var m := get_module(MODULE_ID)
	fob = BaseFob.make(self, m.global_position if m else Vector3.ZERO, true, {
		"terminals": LAYOUT_TERMINALS, "spawns": SPAWNS, "muster_origin": Vector3(-12.0, 0.1, 2.0), "muster_step": Vector3(1.4, 0.0, 0.0),
		"muster_rows": Vector3(0.0, 0.0, 1.8), "muster_per_row": 8, "muster_max": 16, "holds": Rect2(-HALF, HALF * 2.0)})
	_park = Node3D.new()
	_park.name = "StagingPark"
	fob.add_child(_park)
	_refresh_park()
	BaseHub.view_changed.connect(_refresh_park)


func _refresh_park() -> void:
	var models: Array = (BaseHub.view.get("staging", {}) as Dictionary).get("models", [])
	if models == _park_models or _park == null:
		return
	_park_models = models.duplicate()
	for n in _park.get_children():
		n.queue_free()
	for i in mini(models.size(), PARKING.size()):
		var model := String(models[i])
		if VehicleArt.MODELS.has(model):
			var prop := VehicleArt.prop(model)
			prop.position = PARKING[i]
			_park.add_child(prop)


## What a joining client loads to play here (LevelSwitch).
func level_info() -> Dictionary:
	return {"level": "staging", "def": def}


func _physics_process(_delta: float) -> void:
	pass  # (the company's sensors are at its own FOB)


func garrison_size(_module_id: String) -> int:
	return 0  # the host's sites are garrisoned by UsField; the rear of a friendly FOB is quiet


func server_post_guards() -> void:
	pass  # the company's guards stay on its own wire


func _zone_loaded() -> void:
	pass  # (what lies about here isn't stash)


# --- The FOB's public face, without a stash -------------------------------------------------------

func server_spawn_stash(_stash: Array) -> void:
	pass


## The stash as it stands: it's at home, and BaseHub's poll mustn't read it back as empty.
func server_collect_stash() -> Array:
	return Roster.json_safe(BaseHub.stash())


## What the terminal sold is laid out by the crates (it stays in this zone: take it or leave it).
func server_deliver(id: StringName, count: int, state := {}) -> void:
	var at := fob.to_global(DELIVERY + Vector3(float(_delivered % DELIVERY_ROW) * 0.7, 0.0, float((_delivered / DELIVERY_ROW) % 4) * 0.7))
	_delivered += 1
	spawn_item(id, count, at, "staging_d_%d" % Time.get_ticks_usec(), state)
