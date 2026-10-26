class_name BuildIntegrity
extends RefCounted
## Structural integrity of the builds (docs/survival_building.md §3, calls 39 and 71: "real load
## with cracks and a warning"). Pure: solve() takes a cluster of finished blocks and gives back
## each one's state, on any thread (Builder runs it on the WorkerThreadPool through a Job and
## applies the result on the main thread; BuildMode's ghost runs it at once on a small cluster).
##
## The model:
## - Ground: a block that rests on the terrain or on the zone's own buildings (Builder.grounded)
##   is held by the ground.
## - Support flows from the ground up and sideways through touching blocks: a shortest path
##   where a step up or down costs V_COST and a step sideways H_COST, so a block's distance
##   says how many blocks out (h) it sits from a supported column, then how high. h over its
##   material's span (BuildPieces.MATERIALS) fails: a wood beam reaches 3 blocks out, brick 4,
##   sandbags only stack.
## - Load: every block's own mass (its material's, times its shape's share) goes down the
##   support paths to the ground, split evenly between the neighbours that hold it (those one
##   step nearer the ground on a shortest path). A block whose load passes its capacity (the
##   material's, times its shape's share, times its hp: damage lowers it) fails.
## - A block no path reaches is FREE: nothing holds it, it falls at once. One that fails is
##   OVER: it cracks and falls after Builder.CRACK_S. AMBER warns: at AMBER_AT of capacity.

const H_COST := 1000
const V_COST := 1
const AMBER_AT := 0.7  # Proposed
## Damage never takes a block's capacity below this share of a whole one's (it falls when its
## hp is gone: Builder).
const MIN_HP := 0.05
enum State { OK, AMBER, OVER, FREE }
const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]


## A finished block's entry in a cluster: [material key, shape share, hp 0-1, grounded].
static func entry(mat: String, frac: float, hp: float, grounded: bool) -> Array:
	return [mat, frac, hp, grounded]


static func mass_of(e: Array) -> float:
	return float(BuildPieces.MATERIALS[e[0]].mass) * float(e[1])


static func capacity_of(e: Array) -> float:
	return float(BuildPieces.MATERIALS[e[0]].cap) * float(e[1]) * maxf(float(e[2]), MIN_HP)


## Solves a cluster: `cells` maps Vector3i -> entry(). Returns Vector3i -> {"state": State,
## "ratio": load / capacity, "h": blocks out from a supported column (-1 when free), "load",
## "cap"}.
static func solve(cells: Dictionary) -> Dictionary:
	var dist := {}
	var heap: Array = []
	for c: Vector3i in cells:
		if bool(cells[c][3]):
			dist[c] = 0
			_push(heap, [0, c])
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var d := int(top[0])
		var c: Vector3i = top[1]
		if d > int(dist[c]):
			continue
		for dir in DIRS:
			var n := c + dir
			if not cells.has(n):
				continue
			var nd := d + (V_COST if dir.y != 0 else H_COST)
			if nd < int(dist.get(n, 1 << 60)):
				dist[n] = nd
				_push(heap, [nd, n])
	var order: Array = dist.keys()
	order.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return int(dist[a]) > int(dist[b]))
	var loads := {}
	for c: Vector3i in order:
		loads[c] = mass_of(cells[c])
	for c: Vector3i in order:
		var held_by: Array[Vector3i] = []
		for dir in DIRS:
			var n := c + dir
			if dist.has(n) and int(dist[n]) + (V_COST if dir.y != 0 else H_COST) == int(dist[c]):
				held_by.append(n)
		if held_by.is_empty():
			continue  # grounded: the ground takes it
		var share := float(loads[c]) / held_by.size()
		for n in held_by:
			loads[n] = float(loads[n]) + share
	var out := {}
	for c: Vector3i in cells:
		var e: Array = cells[c]
		var cap := capacity_of(e)
		if not dist.has(c):
			out[c] = {"state": State.FREE, "ratio": INF, "h": -1, "load": mass_of(e), "cap": cap}
			continue
		var h := int(dist[c]) / H_COST
		var ratio := float(loads[c]) / cap
		var state := State.OK
		if h > int(BuildPieces.MATERIALS[e[0]].span) or ratio >= 1.0:
			state = State.OVER
		elif ratio >= AMBER_AT:
			state = State.AMBER
		out[c] = {"state": state, "ratio": ratio, "h": h, "load": float(loads[c]), "cap": cap}
	return out


## The ghost's colour for a state (BuildMode): green, amber, red.
static func colour(state: int) -> Color:
	match state:
		State.OK:
			return Color(0.35, 0.85, 0.4, 0.4)
		State.AMBER:
			return Color(0.95, 0.7, 0.2, 0.45)
	return Color(0.9, 0.3, 0.25, 0.45)


static func state_name(state: int) -> String:
	return ["green", "amber", "red", "red"][clampi(state, 0, 3)]


# A binary min-heap of [distance, cell].
static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if int(heap[parent][0]) <= int(heap[i][0]):
			break
		var t: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = t
		i = parent


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < heap.size() and int(heap[l][0]) < int(heap[m][0]):
			m = l
		if r < heap.size() and int(heap[r][0]) < int(heap[m][0]):
			m = r
		if m == i:
			break
		var t: Array = heap[m]
		heap[m] = heap[i]
		heap[i] = t
		i = m
	return top


## A solve on a worker thread (WorkerThreadPool): Builder starts one with a cluster's copy and
## picks the result up on the main thread once done().
class Job:
	extends RefCounted
	var cells: Dictionary
	var result := {}
	var task := -1

	func _init(p_cells: Dictionary) -> void:
		cells = p_cells

	func start() -> void:
		task = WorkerThreadPool.add_task(_run, false, "build integrity")

	func _run() -> void:
		result = BuildIntegrity.solve(cells)

	func done() -> bool:
		return task < 0 or WorkerThreadPool.is_task_completed(task)

	## Waits for it (at once when done()) and returns the result.
	func finish() -> Dictionary:
		if task >= 0:
			WorkerThreadPool.wait_for_task_completion(task)
			task = -1
		return result
