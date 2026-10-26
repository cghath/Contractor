class_name BuildPiece
extends StaticBody3D
## A built piece (BuildPieces.PIECES: a door, stairs, a bunk...) on the build grid, made the
## same on every peer from its Builder record (apply). A site or a blueprint is a see-through
## ghost with no collision until it's built; a door, shutter, hatch or gate swings open (no
## collision then) and shut. In the interaction menu (Left Ctrl, InteractionMenu's OBJECT) it
## offers what can be done with it: open and shut, the locks (call 72: a key or a code), repair
## and dismantle; each goes to the host through Builder.ask.

var builder: Node
var id := 0
var rec: Dictionary = {}
var _shape: CollisionShape3D
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _built_once := false


func _ready() -> void:
	add_to_group(InteractionMenu.INTERACTABLES)
	collision_layer = 1
	collision_mask = 0


## Every peer: the node as record `p_rec` says (its place, look, state).
func apply(p_rec: Dictionary) -> void:
	rec = p_rec
	var kind := String(rec.k)
	var def: Dictionary = BuildPieces.PIECES[kind]
	var rot := int(rec.r)
	var size := Vector3(BuildPieces.piece_size(kind, rot)) * BuildPieces.BLOCK_M
	var base := Vector3(int(rec.c[0]), int(rec.c[1]), int(rec.c[2])) * BuildPieces.BLOCK_M
	position = base + Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	if _mesh == null:
		_build_nodes(def, rot)
	var built := float(rec.prog) >= 1.0 and not bool(rec.get("bp", false))
	var open := built and bool(rec.get("open", false))
	var colour: Color = VoxelWorld.PALETTE[int(BuildPieces.MATERIALS[String(def.mat)].mat)]
	if not built:
		colour = Color(0.4, 0.6, 1.0) if bool(rec.get("bp", false)) else colour
		colour.a = 0.3 + 0.4 * float(rec.prog)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if built else BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = colour
	var solid := built and bool(def.get("solid", true)) and not open
	_shape.set_deferred(&"disabled", not solid)
	# A door swings a quarter turn about its hinge (the footprint's left edge) when open.
	_mesh.rotation.y = PI * 0.5 if open else 0.0


func _build_nodes(def: Dictionary, rot: int) -> void:
	var size := Vector3(BuildPieces.piece_size(String(rec.k), rot)) * BuildPieces.BLOCK_M
	var turned := posmod(rot, 2) == 1
	var look := String(def.get("look", "full"))
	var box := size
	var offset := Vector3(0, size.y * 0.5, 0)
	var thin := 0.08
	match look:
		"panel":  # a board standing at the footprint's back edge
			box = Vector3(thin, size.y, size.z) if turned else Vector3(size.x, size.y, thin)
		"slab":
			box = Vector3(size.x, thin, size.z)
			offset = Vector3(0, size.y - thin * 0.5, 0)
		"frame":
			box = Vector3(size.x, size.y * 0.6, size.z)
			offset = Vector3(0, size.y * 0.3, 0)
	_mat = StandardMaterial3D.new()
	_mesh = MeshInstance3D.new()
	_mesh.material_override = _mat
	add_child(_mesh)
	if look == "steps":
		# A flight of steps rising along the piece's forward axis, each its own box.
		var steps := 8
		var mesh := ArrayMesh.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in steps:
			var b := BoxMesh.new()
			var along := (float(i) + 0.5) / steps
			var h := size.y * (float(i) + 1.0) / steps
			b.size = Vector3(size.x / steps, h, size.z) if turned else Vector3(size.x, h, size.z / steps)
			var at := Vector3((along - 0.5) * size.x, h * 0.5, 0) if turned else Vector3(0, h * 0.5, (along - 0.5) * size.z)
			st.append_from(b, 0, Transform3D(Basis(), at))
		st.commit(mesh)
		_mesh.mesh = mesh
		var shape := ConvexPolygonShape3D.new()
		var lo := -size * 0.5
		var hi := size * 0.5
		shape.points = PackedVector3Array([Vector3(lo.x, 0, lo.z), Vector3(hi.x, 0, lo.z), Vector3(lo.x, 0, hi.z), Vector3(hi.x, 0, hi.z),
			Vector3(hi.x, size.y, hi.z) if turned else Vector3(lo.x, size.y, hi.z), Vector3(hi.x, size.y, lo.z) if turned else Vector3(hi.x, size.y, hi.z)])
		_shape = CollisionShape3D.new()
		_shape.shape = shape
		add_child(_shape)
		return
	var bm := BoxMesh.new()
	bm.size = box
	_mesh.mesh = bm
	_mesh.position = offset
	var shape := BoxShape3D.new()
	shape.size = box
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position = offset
	add_child(_shape)


## The middle of the piece (world).
func centre() -> Vector3:
	return global_position + Vector3.UP * float(BuildPieces.PIECES[String(rec.k)].size[1]) * BuildPieces.BLOCK_M * 0.5


func action_point() -> Vector3:
	return centre()


## The interaction menu's entries (InteractionMenu OBJECT): what `actor` can do with it now.
func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s := actor as Soldier
	if s == null or rec.is_empty():
		return out
	var def: Dictionary = BuildPieces.PIECES[String(rec.k)]
	var built := float(rec.prog) >= 1.0
	var me := self
	var act := func(what: String) -> Callable:
		return func() -> void: Builder.ask(me, "piece_act", [id, what, ""])
	if built and bool(def.get("door", false)):
		var locked := bool(rec.get("locked", false))
		var lock: Dictionary = rec.get("lock", {})
		var b := builder as Builder
		var can := b == null or b.can_unlock(s, id)
		if bool(rec.get("open", false)):
			out.append({"id": &"build_close", "label": "Shut", "disabled": "", "call": act.call("close")})
		else:
			out.append({"id": &"build_open", "label": "Unlock and open" if locked else "Open", "disabled": "" if not locked or can else "Locked", "call": act.call("open")})
		if lock.is_empty():
			out.append({"id": &"build_lock_key", "label": "Fit a key lock", "disabled": "Shut it first" if bool(rec.get("open", false)) else "", "call": act.call("lock_key")})
			out.append({"id": &"build_lock_code", "label": "Fit a code lock", "disabled": "Shut it first" if bool(rec.get("open", false)) else "", "call": act.call("lock_code")})
		elif not locked:
			out.append({"id": &"build_lock", "label": "Lock", "disabled": "" if can else "No key or code", "call": act.call("lock")})
	if built:
		out.append({"id": &"build_repair", "label": "Repair", "disabled": "" if float(rec.hp) < float(def.hp) else "It's sound", "call": act.call("repair")})
	out.append({"id": &"build_dismantle", "label": "Dismantle" if built else "Take the site down", "disabled": "Locked" if bool(rec.get("locked", false)) else "", "call": act.call("dismantle")})
	return out


func display_name() -> String:
	return String(BuildPieces.PIECES[String(rec.k)].name) if not rec.is_empty() else "Piece"
