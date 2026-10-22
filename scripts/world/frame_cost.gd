class_name FrameCost
extends RefCounted
## Where a frame's time goes, by system (research 2026-10-13 B3.4): the hot spots add what they
## spent (spent(), on the main thread), and the session log's perf line names the systems behind
## the worst frame of each minute (SessionLog.perf_line). A class of its own, not the autoload,
## so static code (VoxelArt) and tools can call it too. Off (nothing kept) until `on`.
##   var t := Time.get_ticks_usec()
##   ...the work...
##   FrameCost.spent(&"nav", t)
## Systems so far: "ai" (SquadAI ticks), "nav" (gathering a chunk's geometry), "models" (a voxel
## model built: VoxelArt.mesh), "sfx" (a sound synthesised or waited for), "voxels" (structures
## stamped), "buildings" (Buildings.near's scans).
## Some keys are parts of others, not more time on top: "buildings" is inside "ai" when an AI's
## tick asked (most asks), and "building_probes" (the cells' probes), "building_groups" (spots
## into groups, floors linked), "building_entrances", "building_ports" and "building_rooms" are
## inside "buildings" (so inside "ai" too); "foliage" (ZoneScatter.foliage_least: sight lines
## through the woods) is inside "ai" when an AI's spotting asked. Add up only the top-level ones ("ai", "nav", "sfx",
## "voxels", "models", and "buildings" asked outside an AI tick) for a frame's counted total.

static var on := false
## System -> microseconds spent since take() last ran.
static var _costs := {}


## Adds the time since `since_usec` (Time.get_ticks_usec) to `system`.
static func spent(system: StringName, since_usec: int) -> void:
	if on:
		_costs[system] = int(_costs.get(system, 0)) + Time.get_ticks_usec() - since_usec


## What was spent since the last take (system -> microseconds), and starts afresh.
static func take() -> Dictionary:
	var out := _costs
	_costs = {}
	return out
