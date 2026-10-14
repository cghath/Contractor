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
## stamped).

static var on := false
## System -> microseconds spent since take() last ran.
static var _costs := {}
## What the last take() handed out (a reader beside the session log: tests/frame_bench.gd).
static var last := {}


## Adds the time since `since_usec` (Time.get_ticks_usec) to `system`.
static func spent(system: StringName, since_usec: int) -> void:
	if on:
		_costs[system] = int(_costs.get(system, 0)) + Time.get_ticks_usec() - since_usec


## What was spent since the last take (system -> microseconds), and starts afresh.
static func take() -> Dictionary:
	var out := _costs
	_costs = {}
	last = out
	return out
