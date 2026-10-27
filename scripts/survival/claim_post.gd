class_name ClaimPost
extends StaticBody3D
## A post by the door of a place left to the dead (docs/survival_people.md "Holding or fleeing",
## call 143): where the players claim it ("Claim this place": Holding.server_claim) and, once it's
## theirs, take what's left there, make it the safehouse or move the settlement there (a council
## question when there's one already). Made on every peer from the map's marks (sync: an
## "abandoned" or "claimed" mark with a "place" key, in the zone played), so a joiner sees them
## too; the actions go to the host through the Settlement node (Settlement.ask "claim").

const HOLDER := "ClaimPosts"
const KINDS: Array[String] = ["abandoned", "claimed"]
const REACH_M := 3.0
const SIZE := Vector3(0.3, 1.4, 0.3)
const OFFSET := Vector3(1.5, 0.0, 1.5)  # (beside the door, not in it)

var key := ""
var kind := "abandoned"
var title := ""
var _at := Vector3.ZERO
var _placed := false


## Every peer (SurvivalLevel._ready): the posts' holder, kept in step with the map's marks.
static func install(level: Node) -> Node3D:
	var holder := Node3D.new()
	holder.name = HOLDER
	level.add_child(holder)
	var map := level.get_node_or_null(NodePath(SurvivalMap.NODE_NAME)) as SurvivalMap
	if map:
		map.changed.connect(func() -> void: sync(holder))
	sync.call_deferred(holder)
	return holder


## The posts under `holder` made, moved on or removed to match the marks of the zone played.
static func sync(holder: Node3D) -> void:
	if holder == null or not is_instance_valid(holder) or not holder.is_inside_tree():
		return
	var want := {}
	for m: Variant in SurvivalMap.marks(SurvivalMap.current_zone()):
		if not m is Dictionary:
			continue
		var md: Dictionary = m
		if String(md.get("kind", "")) in KINDS and String(md.get("place", "")) != "":
			want[String(md.place)] = md
	for c: Node in holder.get_children():
		var p := c as ClaimPost
		if p and not want.has(p.key):
			p.queue_free()
	for k: String in want:
		var md: Dictionary = want[k]
		var nm := "Post_%d" % absi(hash(k))
		var p := holder.get_node_or_null(NodePath(nm)) as ClaimPost
		if p == null or p.is_queued_for_deletion():
			p = ClaimPost.new()
			p.name = nm
			p.key = k
			var xz := SurvivalMap.mark_pos(md)
			p._at = Vector3(xz.x, 0.0, xz.y) + OFFSET
			p.position = p._at
			holder.add_child(p)
		p.kind = String(md.get("kind", "abandoned"))
		p.title = String(md.get("text", ""))


## The post for place `key` under `level` (or null).
static func of(level: Node, key: String) -> ClaimPost:
	var holder: Node = level.get_node_or_null(HOLDER) if level else null
	return holder.get_node_or_null(NodePath("Post_%d" % absi(hash(key)))) as ClaimPost if holder else null


func _ready() -> void:
	add_to_group(InteractionMenu.INTERACTABLES)
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	shape.shape = box
	shape.position.y = SIZE.y * 0.5
	add_child(shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6b4f32")
	var post := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.1, SIZE.y, 0.1)
	pbox.material = mat
	post.mesh = pbox
	post.position.y = SIZE.y * 0.5
	add_child(post)
	var board := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.5, 0.3, 0.04)
	bbox.material = mat
	board.mesh = bbox
	board.position.y = SIZE.y - 0.2
	add_child(board)


## The ground isn't there on the first frame: the post settles onto it once it is.
func _process(_delta: float) -> void:
	if _placed:
		set_process(false)
		return
	var level := CompoundLevel.current(self) as ZoneLevel
	if level == null:
		return
	var g := level.ground_point(_at)
	if g != Vector3.ZERO or Engine.get_process_frames() > 600:
		global_position = g
		_placed = true


func display_name() -> String:
	return title if title != "" else "A place left to the dead"


func action_point() -> Vector3:
	return global_position + Vector3.UP * 1.3


func in_reach(actor: Node3D) -> bool:
	return actor != null and actor.global_position.distance_to(global_position) <= REACH_M + 1.0


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var me := self
	var why := "" if in_reach(actor as Node3D) else "Too far"
	var out: Array[Dictionary] = []
	if kind == "abandoned":
		out.append({"id": &"claim_place", "label": "Claim this place", "disabled": why, "target": self, "call": func() -> void: me.request("claim")})
	else:
		out.append({"id": &"claim_take", "label": "Take what's left here", "disabled": why, "target": self, "call": func() -> void: me.request("take")})
		out.append({"id": &"claim_safehouse", "label": "Make this our safehouse", "disabled": why, "target": self, "call": func() -> void: me.request("safehouse")})
		out.append({"id": &"claim_settle", "label": "Make this our settlement", "disabled": why, "target": self, "call": func() -> void: me.request("settlement"),
			"group": InteractionMenu.MORE})
	return out


## Any peer: ask the host to do `what` here ("claim", "take", "safehouse", "settlement").
func request(what: String) -> void:
	var lvl := CompoundLevel.current(self)
	var st: Settlement = Settlement.install(lvl) if lvl else null
	if st:
		st.ask("claim", [key, what])
