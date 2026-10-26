class_name FallenBell
extends StaticBody3D
## A bell a survivor can ring (docs/survival_events.md; call 124's "a church bell rung as a lure:
## the player can ring one too"): one at each church, village or town square of a survival zone
## (at most MAX_PER_ZONE), the same path on every peer (FallenBell.place_all from SurvivalLevel's
## _ready, so its RPC reaches the host). Ringing it (the interaction menu's "Ring the bell") is
## WorldEvents.server_ring: the dead hear it for a long way, the zone's pressure climbs, the journal
## and the companions remember who did it. A cooldown keeps it from being spammed. Proposed numbers.

const HOLDER := "FallenBells"
const BELL_TYPES: Array[String] = ["church", "village", "town"]
const MAX_PER_ZONE := 2
const REACH_M := 2.5
const COOLDOWN_S := 30.0
const SIZE := Vector3(0.6, 0.7, 0.6)

var place_name := "the church"
var _at := Vector3.ZERO
var _placed := false
var _last := -1000.0


## Every peer, in SurvivalLevel._ready: the zone's bells under a "FallenBells" node.
static func place_all(level: ZoneLevel) -> Node3D:
	var holder := Node3D.new()
	holder.name = HOLDER
	var spots: Array = []
	for m: Dictionary in level.def.get("modules", []):
		var base := ZoneModules.base(String(m.get("type", "")))
		if base in BELL_TYPES and spots.size() < MAX_PER_ZONE:
			var p: Array = m.get("pos", [0.0, 0.0])
			spots.append([base, Vector3(float(p[0]), 0.0, float(p[1]))])
	for i in spots.size():
		var bell := FallenBell.new()
		bell.name = "Bell%d" % i
		bell.place_name = "the %s" % ("church" if String(spots[i][0]) == "church" else "chapel by the %s" % ("square" if String(spots[i][0]) == "town" else "village"))
		bell._at = (spots[i][1] as Vector3) + Vector3(4.0, 0.0, 4.0)
		bell.position = bell._at
		holder.add_child(bell)
	level.add_child(holder)
	return holder


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
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = SIZE.x * 0.5
	cyl.height = SIZE.y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7a5a2a")
	mat.metallic = 0.6
	cyl.material = mat
	mesh.mesh = cyl
	mesh.position.y = SIZE.y * 0.5 + 1.2
	add_child(mesh)
	var post := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(0.12, 1.9, 0.12)
	post.mesh = pbox
	post.position.y = 0.95
	add_child(post)


## The ground isn't there on the first frame: the bell settles onto it once it is.
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
	return "Bell"


func action_point() -> Vector3:
	return global_position + Vector3.UP * 1.6


func in_reach(actor: Node3D) -> bool:
	return actor != null and actor.global_position.distance_to(global_position) <= REACH_M + 1.0


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var me := self
	return [{"id": &"ring_bell", "label": "Ring the bell (it calls the dead)", "disabled": "" if in_reach(actor as Node3D) else "Too far", "target": self,
		"call": func() -> void: me.request_ring()}]


## Any peer: ring it.
func request_ring() -> void:
	if multiplayer.is_server():
		_server_ring(multiplayer.get_unique_id())
	else:
		_rpc_ring.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ring() -> void:
	if multiplayer.is_server():
		_server_ring(multiplayer.get_remote_sender_id())


## Host: peer `peer`'s survivor rings it (in reach, not on cooldown). Returns the journal line.
func _server_ring(peer: int) -> String:
	var level := CompoundLevel.current(self)
	var actor: Soldier = level.players.get_node_or_null(str(peer)) as Soldier if level else null
	if actor == null or not in_reach(actor):
		return ""
	return server_ring_by(actor)


## Host: `actor` rings it (tests call this straight).
func server_ring_by(actor: Soldier) -> String:
	var now := Soldier._now()
	if now - _last < COOLDOWN_S:
		Survival._tell(actor, "The bell's still humming")
		return ""
	_last = now
	var level := CompoundLevel.current(self)
	var line := WorldEvents.server_ring(level, actor, global_position, place_name)
	Survival._tell(actor, "The bell rings out. Everything for a mile heard it.")
	return line
