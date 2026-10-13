class_name Supports
extends RefCounted
## The player faction's supports (wave 5b): Blackhawk resupply, transport and extraction (V3)
## and AAVs (V4), called from the command menu's Support entry (0) and run by AI.
##
## WAVE 5B GROUNDWORK. This file is the seam V3 and V4 build against in parallel, so neither
## has to edit the other's files or the same lines of shared ones:
## - Commands: the command menu sends "support:<name>[:arg]" (Soldier._server_squad_command
##   hands every "support:" command here). Each workstream registers its own names with
##   register(); server_command() runs the handler and returns "" or a message for the caller.
## - Origins: where supports come from. The LHD offshore on a coastal zone, the friendly FOB's
##   direction inland (V4 registers them); until one is registered, the map edge nearest the
##   squad's start (origin_for's fallback).
## - Conditions: can_fly() and can_drive_amphibious() are where weather (wave 7) and terrain
##   ground a support. Today they only ask the level.
## Keep these names and signatures; add to them freely.

## Command name -> Callable(caller: Soldier, arg: String, point: Vector3, names: PackedStringArray) -> String
static var _handlers := {}
## Origin kind (&"lhd", &"fob") -> Node3D, on the host.
static var _origins := {}


## Host: `name` (e.g. "resupply", "aav_move") runs `handler` for "support:<name>[:arg]".
static func register(name: String, handler: Callable) -> void:
	_handlers[name] = handler


## Host: run a "support:..." command from `caller` at `point` for the selected `names`.
## Returns "" when it went, or a message for the caller.
static func server_command(caller: Node, cmd: String, point: Vector3, names: PackedStringArray) -> String:
	var parts := cmd.trim_prefix("support:").split(":", true, 1)
	var handler: Callable = _handlers.get(parts[0], Callable())
	if not handler.is_valid():
		return "That support isn't available"
	return String(handler.call(caller, parts[1] if parts.size() > 1 else "", point, names))


## Host: supports of `kind` come from `node` (V4: the LHD, a friendly FOB's gate). A freed node
## drops out by itself.
static func register_origin(kind: StringName, node: Node3D) -> void:
	_origins[kind] = node


## Where a support of `kind` starts (`level`'s coordinates): a registered origin of that kind,
## else the LHD, else the FOB, else a point on the map edge nearest `toward`, `height` metres up.
static func origin_for(level: Node, kind := &"", toward := Vector3.ZERO, height := 120.0) -> Transform3D:
	for k: StringName in [kind, &"lhd", &"fob"]:
		var node: Node3D = _origins.get(k)
		if is_instance_valid(node) and node.is_inside_tree():
			return node.global_transform
	_origins.erase(kind)
	var area := Rect2(-1000, -1000, 2000, 2000)
	if level and level.has_method(&"map_area"):
		area = level.call(&"map_area")
	var p := Vector2(toward.x, toward.z).clamp(area.position, area.end)
	var to_edge := [p.x - area.position.x, area.end.x - p.x, p.y - area.position.y, area.end.y - p.y]
	var side: int = to_edge.find(to_edge.min())
	var edge := [Vector2(area.position.x, p.y), Vector2(area.end.x, p.y), Vector2(p.x, area.position.y), Vector2(p.x, area.end.y)][side] as Vector2
	var at := Vector3(edge.x, height, edge.y)
	var look := Vector3(toward.x, height, toward.z)
	return Transform3D(Basis.looking_at((look - at).normalized() if not look.is_equal_approx(at) else Vector3.FORWARD), at)


## Whether helicopters can fly in `level` now (storms ground them: wave 7 weather answers this
## through the level's "weather_grounds_aircraft" method when it exists).
static func can_fly(level: Node) -> bool:
	return not (level and level.has_method(&"weather_grounds_aircraft") and level.call(&"weather_grounds_aircraft"))


## Whether `level` is a hot zone (transport is hot zones only).
static func is_hot_zone(level: Node) -> bool:
	return level != null and "def" in level and String((level.get(&"def") as Dictionary).get("kind", "")) == "hot"


## Host, tests: forget every handler and origin.
static func reset() -> void:
	_handlers.clear()
	_origins.clear()
