class_name FaceRig
extends Node
## A soldier's face at work (CharacterModel.face; FaceArt draws it): his own head, and the eyes,
## mouth and brows as small meshes of their own on it, swapped whole for a state (Captain,
## 2026-10-20: expressions are cheap swaps, not per-voxel animation). Cosmetic, worked out on
## every peer from what each already knows (vitals, carries, aiming, callouts), so all see much
## the same face; blinks and glances are each peer's own.
##
## - Eyes blink (every BLINK_S, for BLINK_SHUT_S), look where he looks (up and down with his
##   aim past what the head turns, and glance about when he isn't aiming), and close when he's
##   unconscious or dead.
## - Expressions (FaceArt): NEUTRAL; STRAIN when hurt (Vitals.pain), down, or carrying or
##   dragging someone; SHOUT while he calls out (CharacterModel.shout, from Callouts.play);
##   SLACK when out cold or dead, and gasping when winded.
##
## His head is built on a worker (VoxelArt.build_async): until it is, the head shows nothing of
## its own and the moving parts wait.

## Seconds between blinks (a random span each time) and how long the lids stay down.
const BLINK_S := Vector2(2.2, 6.0)
const BLINK_SHUT_S := 0.14
## Seconds between glances while not aiming, and the chance a glance is to the side.
const GLANCE_S := Vector2(1.2, 3.6)
const GLANCE_SIDE := 0.45
## The eyes look up or down once the aim is this far (radians) past what the head turns.
const GAZE_PITCH := 0.1
## Pain (Vitals.pain) that sets the jaw, and that narrows the eyes too.
const STRAIN_PAIN := 0.3
const SQUINT_PAIN := 0.65
## Breathing this hard (CharacterModel.breath_rate) he gasps, mouth open.
const GASP_RATE := 1.35
## The moving parts aren't drawn past this (m): a few pixels there, and five draws a body.
const DETAIL_M := 30.0
## The face is worked out this often (s) at most.
const TICK_S := 0.05

const PARTS: Array[String] = ["eye_l", "eye_r", "mouth", "brow_l", "brow_r"]

var model: CharacterModel
var head_model := ""
var palette := ""
var digits := ""
var female := false
var thick := 1
## Now: the eyes' state (FaceArt.eye: "c" shut, "h" half, else the gaze's two digits) and the
## expression.
var eye_state := "11"
var expression := FaceArt.NEUTRAL
var _parts: Dictionary = {}  # PARTS -> MeshInstance3D
var _ready_built := false
var _rng := RandomNumberGenerator.new()
var _blink_in := 3.0
var _shut_for := 0.0
var _glance_in := 2.0
var _glance := 1
var _tick := 0.0


## Puts `face` (a SoldierLook code) on `m`'s head: its own head mesh and the moving parts, built
## on a worker; the head draws nothing until they're ready.
func setup(m: CharacterModel, face: String) -> void:
	model = m
	female = m.body == VoxelArt.FEMALE
	head_model = SoldierLook.head_model(face, m.body)
	digits = head_model.get_slice(":", 1)
	palette = SoldierLook.palette(face)
	thick = absi(hash(face)) % 3 if not female else 0  # brows: thin, middling, bushy
	_rng.seed = hash(face) ^ int(m.get_instance_id())
	_blink_in = _rng.randf_range(BLINK_S.x, BLINK_S.y)
	var head := m.head
	head.set_meta(&"voxel_model", head_model)  # BodyDeform carves this one
	head.set_meta(&"voxel_variant", palette)
	var mi := head.get_child(0) as MeshInstance3D
	_ready_built = false
	mi.mesh = null
	var origins := FaceArt.feature_origins(digits, female)
	for part in PARTS:
		var inst: MeshInstance3D = _parts.get(part)
		if inst == null or not is_instance_valid(inst):
			inst = MeshInstance3D.new()
			inst.name = "Face_" + part
			inst.material_override = VoxelArt._get_material()
			inst.visibility_range_end = DETAIL_M
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(inst)
			_parts[part] = inst
		inst.layers = m.render_layers
		inst.position = origins[part]
		inst.mesh = null
	_try_ready()


## Every model this face may draw: its head, the eyes' states, and the mouth and brows in each
## expression.
func all_models() -> Array:
	var out: Array = [head_model]
	for state: String in eye_states():
		out.append("eye:%s:%s" % [state, "f" if female else "m"])
	for e in FaceArt.EXPRESSIONS:
		var f := FaceArt.feature_models(digits, female, "11", e, thick)
		out.append_array([f.mouth, f.brow_l, f.brow_r])
	return out


static func eye_states() -> Array[String]:
	var out: Array[String] = ["c", "h"]
	for gx in 3:
		for gy in 3:
			out.append("%d%d" % [gx, gy])
	return out


## Whether the face's own meshes are built and on (tests wait for this).
func is_built() -> bool:
	return _ready_built


func _try_ready() -> void:
	if _ready_built or model == null:
		return
	if not VoxelArt.build_async(all_models(), palette):
		return
	_ready_built = true
	(model.head.get_child(0) as MeshInstance3D).mesh = VoxelArt.mesh(head_model, palette)
	_apply(true)


func _process(delta: float) -> void:
	if model == null or not is_instance_valid(model):
		return
	if not _ready_built:
		_try_ready()
		return
	_tick += delta
	if _tick < TICK_S:
		return
	var dt := _tick
	_tick = 0.0
	_think(dt)
	_apply(false)


## Works out the eyes' state and the expression from the body's state.
func _think(dt: float) -> void:
	var body := model.get_parent()
	var vitals: Vitals = body.get_node_or_null(^"Vitals") as Vitals if body else null
	var out := vitals != null and (vitals.is_dead() or vitals.is_unconscious())
	if out:
		eye_state = "c"
		expression = FaceArt.SLACK
		return
	var pain := vitals.pain() if vitals else 0.0
	var down := vitals != null and not vitals.is_up()
	var carry := String(model.carry_net.get("mode", ""))
	if model.shouting():
		expression = FaceArt.SHOUT
	elif pain >= STRAIN_PAIN or down or carry == String(CharacterModel.CARRY) or carry == String(CharacterModel.DRAG):
		expression = FaceArt.STRAIN
	elif model.breath_rate >= GASP_RATE:
		expression = FaceArt.SLACK
	else:
		expression = FaceArt.NEUTRAL
	# Blinks.
	_blink_in -= dt
	_shut_for -= dt
	if _blink_in <= 0.0:
		_shut_for = BLINK_SHUT_S
		_blink_in = _rng.randf_range(BLINK_S.x, BLINK_S.y)
	if _shut_for > 0.0:
		eye_state = "c"
		return
	if pain >= SQUINT_PAIN and expression != FaceArt.SHOUT:
		eye_state = "h"
		return
	# Gaze: up or down with the aim past the head's share of it (CharacterModel draws the head
	# at 0.8 of look_pitch, and dips it to the sights), across in glances.
	var past := model.look_pitch * 0.2 + (CharacterModel.AIM_HEAD_DIP if model.aiming else 0.0)
	var gy := 2 if past > GAZE_PITCH else (0 if past < -GAZE_PITCH else 1)
	_glance_in -= dt
	if model.aiming:
		_glance = 1
	elif _glance_in <= 0.0:
		_glance_in = _rng.randf_range(GLANCE_S.x, GLANCE_S.y)
		_glance = (0 if _rng.randf() < 0.5 else 2) if _rng.randf() < GLANCE_SIDE else 1
	eye_state = "%d%d" % [_glance, gy]


## Swaps the parts' meshes to the state (only those that changed, unless `all`).
func _apply(all: bool) -> void:
	var want := FaceArt.feature_models(digits, female, eye_state, expression, thick)
	for part in PARTS:
		var inst: MeshInstance3D = _parts.get(part)
		if inst == null or not is_instance_valid(inst):
			continue
		var name: String = want[part]
		if all or inst.get_meta(&"model", "") != name:
			inst.set_meta(&"model", name)
			inst.mesh = VoxelArt.mesh(name, palette)
