class_name VehicleTurret
extends RefCounted
## A vehicle's turret or gun mount that turns (Captain, 2026-10-13: "turrets must rotate and
## work"): the gunner traverses the ring and elevates the gun with the mouse, within the mount's
## limits and at its speeds, the host owns where it points, and every peer draws it there. The
## turret's mesh, its gun and whoever stands at it turn together, and rounds leave the gun's
## real muzzle along its barrel. The O-GPK turrets on the M-ATV and the MaxxPro, the AAV-7's
## Up-Gunned Weapon Station and a technical's DShK pintle (data/vehicles.json "turret").
##
## The look: VehicleArt draws a model whole; split() then lifts the turret's voxels (above the
## ring, within its radius) and the gun's (its box, by colour) out of the hull's canvas into two
## small canvases of their own, which VehicleArt.instance() meshes as the nodes "Turret" (turns
## about the ring's axis) and "Turret/Gun" (elevates about its trunnion). The turret's glass is
## see-through in their look (P.WINDOW, as the cabins' windows: VehicleInteriors), so the
## gunner sees out through the shield's windows and vision blocks; rounds still meet P.GLASS.
## Rounds meet the parts where they are now (VehicleHull.first_solid); hits on them leave no
## marks yet (the parts are shared meshes).
##
## The numbers, per model in data/vehicles.json "turret" (vehicle frame, metres; the gun's
## muzzle is "gun" "at", at rest):
##   "pivot": [x, y, z]   the ring's axis (x, z) and its top (y): voxels above it within
##                        "radius" of the axis, up to "top", turn with the turret
##   "gun": {"trunnion": [y, z], "box": [x0, y0, z0, x1, y1, z1], "colours": ["gun", ...]}
##                        the gun's voxels (in the box, of these VehicleArt.P colours) elevate
##                        about the trunnion's line (across x)
##   "traverse_deg": [min, max]  left positive; missing: all the way round
##   "elevation_deg": [min, max], "traverse_dps", "elevation_dps"
## Every number there is Proposed.

## Default speeds (degrees a second), when the spec leaves them out.
const TRAVERSE_DPS := 60.0
const ELEVATION_DPS := 40.0
## An AI gunner fires once the barrel is this close to its aim (degrees).
const ON_TARGET_DEG := 3.0

var pivot := Vector3.ZERO
var trunnion := Vector3.ZERO   # a point on the trunnion's line (x is the pivot's)
var muzzle := Vector3.ZERO     # at rest
var full_circle := true
var yaw_min := -PI
var yaw_max := PI
var pitch_min := deg_to_rad(-10.0)
var pitch_max := deg_to_rad(45.0)
var yaw_rate := deg_to_rad(TRAVERSE_DPS)
var pitch_rate := deg_to_rad(ELEVATION_DPS)
## Where it points now (radians, the vehicle's frame: yaw left positive, pitch up positive).
var yaw := 0.0
var pitch := 0.0
## Where it's going (host; and the local gunner's own peer, which runs ahead of the host).
var target_yaw := 0.0
var target_pitch := 0.0


## The turret of a vehicle spec, or null if its gun doesn't turn (no "turret", or no gun).
static func of(spec: Dictionary) -> VehicleTurret:
	var t: Dictionary = spec.get("turret", {})
	var g: Dictionary = spec.get("gun", {})
	if t.is_empty() or g.is_empty() or not g.has("weapon"):
		return null
	var out := VehicleTurret.new()
	out.pivot = VehicleSpecs.vec(t.get("pivot"))
	var gun: Dictionary = t.get("gun", {})
	var tr: Array = gun.get("trunnion", [out.pivot.y, out.pivot.z])
	out.trunnion = Vector3(out.pivot.x, float(tr[0]), float(tr[1]))
	out.muzzle = VehicleSpecs.vec(g.get("at"), out.trunnion + Vector3.FORWARD)
	if t.has("traverse_deg"):
		out.full_circle = false
		out.yaw_min = deg_to_rad(float(t.traverse_deg[0]))
		out.yaw_max = deg_to_rad(float(t.traverse_deg[1]))
	if t.has("elevation_deg"):
		out.pitch_min = deg_to_rad(float(t.elevation_deg[0]))
		out.pitch_max = deg_to_rad(float(t.elevation_deg[1]))
	out.yaw_rate = deg_to_rad(float(t.get("traverse_dps", TRAVERSE_DPS)))
	out.pitch_rate = deg_to_rad(float(t.get("elevation_dps", ELEVATION_DPS)))
	return out


## Sets where to point, inside the limits (the vehicle's frame).
func aim(p_yaw: float, p_pitch: float) -> void:
	target_yaw = clampf(p_yaw, yaw_min, yaw_max) if not full_circle else wrapf(p_yaw, -PI, PI)
	target_pitch = clampf(p_pitch, pitch_min, pitch_max)


## Sets where to point from a direction in the vehicle's frame.
func aim_local(dir: Vector3) -> void:
	var a := VehicleTurret.angles(dir)
	aim(a.x, a.y)


## Turns towards the target at the mount's speeds (all-round mounts the short way).
func step(delta: float) -> void:
	var dy := wrapf(target_yaw - yaw, -PI, PI) if full_circle else target_yaw - yaw
	yaw += clampf(dy, -yaw_rate * delta, yaw_rate * delta)
	if full_circle:
		yaw = wrapf(yaw, -PI, PI)
	else:
		yaw = clampf(yaw, yaw_min, yaw_max)
	pitch = clampf(pitch + clampf(target_pitch - pitch, -pitch_rate * delta, pitch_rate * delta), pitch_min, pitch_max)


## Snaps to the target (a reload, tests).
func settle() -> void:
	yaw = target_yaw
	pitch = target_pitch


## (yaw, pitch) of a direction in the vehicle's frame.
static func angles(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


## The turret's place in the vehicle's frame now (its part turns by this about the pivot).
func turret_transform(p_yaw := NAN) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw if is_nan(p_yaw) else p_yaw), pivot)


## The gun's place in the vehicle's frame now (its part elevates about the trunnion).
func gun_transform(p_yaw := NAN, p_pitch := NAN) -> Transform3D:
	return turret_transform(p_yaw) * Transform3D(Basis(Vector3.RIGHT, pitch if is_nan(p_pitch) else p_pitch), trunnion - pivot)


## The barrel's direction in the vehicle's frame.
func barrel_local() -> Vector3:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD


## The muzzle in the vehicle's frame.
func muzzle_local() -> Vector3:
	return gun_transform() * (muzzle - trunnion)


## A point on the turret at rest (`rest`, e.g. a seat) where it is now.
func carry(rest: Vector3) -> Vector3:
	return turret_transform() * (rest - pivot)


## Whether the barrel points within ON_TARGET_DEG of `dir` (vehicle frame).
func on_target(dir: Vector3, within_deg := ON_TARGET_DEG) -> bool:
	return barrel_local().angle_to(dir) <= deg_to_rad(within_deg)


# --- The look: splitting a model's voxels -----------------------------------------------------

## Lifts the turret's and the gun's voxels out of `c` (a VehicleArt.Canvas, buffer and look)
## into c.parts: [{"name": "Turret"/"Gun", "origin": Vector3i (canvas voxel of the part's
## corner), "size": Vector3i, "buffer", "look" (VoxelBuffers with VehicleArt's 1-voxel
## padding)}]. The turret's glass is see-through in its look. Pure buffer work (worker threads).
static func split(model: String, c: VehicleArt.Canvas) -> void:
	if not VehicleSpecs.has_model(model):
		return
	var spec := VehicleSpecs.spec(model)
	var t: Dictionary = spec.get("turret", {})
	if t.is_empty() or (spec.get("gun", {}) as Dictionary).is_empty():
		return
	var vs := c.vs
	var half_z := c.size.z * vs * 0.5
	var look: VoxelBuffer = c.look if c.look else c.buffer
	var piv := VehicleSpecs.vec(t.get("pivot"))
	var radius := float(t.get("radius", 1.0))
	var top := float(t.get("top", piv.y + 1.0))
	var gun: Dictionary = t.get("gun", {})
	var gun_box := VehicleSpecs.box(gun.get("box", [0, 0, 0, 0, 0, 0]))
	var colours := {}
	for name: String in gun.get("colours", ["gun"]):
		colours[int(VehicleArt.P.get(name.to_upper(), VehicleArt.P.GUN))] = true
	# Voxel ranges to look through (canvas indices).
	var to_v := func(p: Vector3) -> Vector3i:
		return Vector3i(floori(p.x / vs + c.size.x * 0.5), floori(p.y / vs), floori((p.z + half_z) / vs))
	var lo: Vector3i = to_v.call(Vector3(minf(piv.x - radius, gun_box.position.x), minf(piv.y, gun_box.position.y), minf(piv.z - radius, gun_box.position.z)))
	var hi: Vector3i = to_v.call(Vector3(maxf(piv.x + radius, gun_box.end.x), maxf(top, gun_box.end.y), maxf(piv.z + radius, gun_box.end.z))) + Vector3i.ONE
	lo = lo.clamp(Vector3i.ZERO, c.size)
	hi = hi.clamp(Vector3i.ZERO, c.size)
	var turret_cells := {}  # Vector3i -> [buffer value, look value]
	var gun_cells := {}
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			for z in range(lo.z, hi.z):
				var hit := c.buffer.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
				var seen := look.get_voxel(x + 1, y + 1, z + 1, VoxelBuffer.CHANNEL_COLOR)
				if hit == VehicleArt.P.EMPTY and seen == VehicleArt.P.EMPTY:
					continue
				var m := Vector3((x + 0.5 - c.size.x * 0.5) * vs, (y + 0.5) * vs, (z + 0.5) * vs - half_z)
				var cell := Vector3i(x, y, z)
				if gun_box.has_point(m) and (colours.has(hit) or colours.has(seen)):
					gun_cells[cell] = [hit, seen]
				elif m.y >= piv.y and m.y < top and Vector2(m.x - piv.x, m.z - piv.z).length() <= radius:
					turret_cells[cell] = [hit, seen]
	var parts: Array = []
	for pair: Array in [["Turret", turret_cells], ["Gun", gun_cells]]:
		var cells: Dictionary = pair[1]
		if cells.is_empty():
			continue
		var p_lo := Vector3i(1 << 20, 1 << 20, 1 << 20)
		var p_hi := -p_lo
		for cell: Vector3i in cells:
			p_lo = p_lo.min(cell)
			p_hi = p_hi.max(cell)
		var size := p_hi - p_lo + Vector3i.ONE
		var buf := _empty(size)
		var seen_buf := _empty(size)
		for cell: Vector3i in cells:
			var at: Vector3i = cell - p_lo + Vector3i.ONE
			var values: Array = cells[cell]
			buf.set_voxel(int(values[0]), at.x, at.y, at.z, VoxelBuffer.CHANNEL_COLOR)
			var shown := int(values[1])
			if shown == VehicleArt.P.GLASS:
				shown = VehicleArt.P.WINDOW  # the turret's windows and vision blocks: see-through
			seen_buf.set_voxel(shown, at.x, at.y, at.z, VoxelBuffer.CHANNEL_COLOR)
			c.buffer.set_voxel(VehicleArt.P.EMPTY, cell.x + 1, cell.y + 1, cell.z + 1, VoxelBuffer.CHANNEL_COLOR)
			if c.look:
				c.look.set_voxel(VehicleArt.P.EMPTY, cell.x + 1, cell.y + 1, cell.z + 1, VoxelBuffer.CHANNEL_COLOR)
		parts.append({"name": pair[0], "origin": p_lo, "size": size, "buffer": buf, "look": seen_buf})
	c.parts = parts


static func _empty(size: Vector3i) -> VoxelBuffer:
	var b := VoxelBuffer.new()
	b.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_8_BIT)
	b.create(size.x + 2, size.y + 2, size.z + 2)
	b.fill(VehicleArt.P.EMPTY, VoxelBuffer.CHANNEL_COLOR)
	return b


## Where a part's mesh sits under its node (metres): its corner voxel in the vehicle's frame,
## less the node's own place at rest (`node_at`: the pivot or the trunnion).
static func part_offset(part: Dictionary, canvas_size: Vector3i, vs: float, node_at: Vector3) -> Vector3:
	var o: Vector3i = part.origin
	return Vector3((o.x - canvas_size.x * 0.5) * vs, o.y * vs, (o.z - canvas_size.z * 0.5) * vs) - node_at
