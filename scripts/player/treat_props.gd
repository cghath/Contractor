class_name TreatProps
extends Node3D
## What a treater works with while treating (CharacterModel's TREAT clip, on every peer, from the
## replicated action_net, so the squad AI's medics show it too): each technique's kit in 0.5 cm
## voxels (ItemArt.Shape, the house style), in the hands (CharacterModel.held_anchor) and, where it
## goes onto the casualty, at the treatment site on the casualty's own body (CharacterModel
## .treat_site: the wound's skin, followed live on the casualty's bone). Through each technique's
## phases (CharacterModel.STRAP_END and the rest, shared with the hands):
## - wrap: the bandage roll shrinks as it unwinds, its tail running to the turns building up on
##   the limb, the pad under the other hand (a burn dressing white, a pelvic binder's handles);
## - pack: the gauze runs off its fold into the wound, then both hands hold pressure on it;
## - tourniquet: the running end pulled round, the band shrinking as the windlass turns (its last
##   turn lands as the clip phase starts: CharacterModel.windlass_angle), then the rod clipped;
## - seal: the backing peeled off, the seal pressed onto the wound;
## - needle: in at the second intercostal space, the stylet out, the catheter hub left;
## - inject: the safety cap pulled, the autoinjector jabbed and held (adenosine: a syringe whose
##   plunger goes down); iv: the catheter slid in along the vein, then taped; io: the driver;
## - fluids: the bag held up, its level from the casualty's running infusion (Vitals.infusion), the
##   line down to the access site; a pressure bag's sleeve and its bulb pumped;
## - splint: shaped into a U between the hands, then on along the limb and wrapped;
## - defib: the AED beside the casualty, pads on, cables, then the shock; clamp (the surgical
##   clamps the surgery kits hold): hemostat and forceps, the kit open beside him; blanket, npa.
## It also drives the casualty's reactions (CharacterModel.treat_react): a wince as a tourniquet
## tightens or a wound is packed, relaxing after morphine, a gasp on decompression, the chest
## going down under CPR, a spasm on the shock.
## Props only show during the clip: what stays on the body after (tourniquets, seals, splints,
## lines, bags) is WoundMarks'. bag_node and bag_fill are here for that.

## A held prop's grip in its hand (CharacterModel.held_anchor space): just off the palm, in the
## curled fingers.
const GRIP := Vector3(0.0, -0.025, 0.03)
## Flat things (pads, seals) pinched by an edge beyond the fingertips.
const PINCH := Vector3(0.0, -0.07, 0.02)
## Ribbons (a bandage's tail, lines, cables) are tiles this long (cm) along the line.
const TILE_CM := 2.0
const MAX_TILES := 80
## Saline primes the line while the bag is hung: this share of it gone by the end of the clip.
const PRIME_SHARE := 0.04
## Fill steps a bag is drawn in.
const FILL_STEPS := 10
## The kit set down beside the casualty (an AED, the surgery roll): this far towards the treater
## from the site and this far to the side of the line between them.
const BESIDE := Vector2(0.45, 0.3)
## Bandage looks: [roll, pad, width (cm)].
const WRAP_LOOK := {
	&"pressure_bandage": [ItemArt.K.CREAM, ItemArt.K.WHITE, 10.0],
	&"burn_dressing": [ItemArt.K.WHITE, ItemArt.K.BLUE, 12.0],
}
## Autoinjector colours: [body, tip, safety cap], as ItemArt's.
const INJECTORS := {
	&"morphine": [ItemArt.K.OD, ItemArt.K.RED, ItemArt.K.YELLOW],
	&"epinephrine": [ItemArt.K.YELLOW, ItemArt.K.ORANGE, ItemArt.K.BLUE],
	&"atropine": [ItemArt.K.GREEN, ItemArt.K.YELLOW, ItemArt.K.WHITE],
}

var model: CharacterModel
## First person: the props on the view's layer too (CharacterModel.set_view_hands).
var view_hands := false

static var _meshes: Dictionary = {}  # key -> [Mesh, origin offset (m), voxel (m)]

var _nodes: Dictionary = {}   # slot -> [key, Node3D]
var _wanted: Dictionary = {}  # slots shown this frame
var _last_u := -1.0           # the clip's progress last frame (one-shot moments)
var _last_n := -1
# This frame's clip: technique, item, seconds in, length, progress, and the site (world space:
# point on the skin, outward normal, limb axis towards the trunk, limb radius, across the limb).
var _tech := &""
var _item := &""
var _t := 0.0
var _s := 1.0
var _u := 0.0
var _p := Vector3.ZERO
var _n := Vector3.UP
var _a := Vector3.UP
var _r := 0.0
var _e := Vector3.RIGHT
var _has_site := false
var _site: Dictionary = {}
var _work := 0   # the working hand (0 right, 1 left), and the helping one (-1: none, one-handed)
var _help := 1
var _sc := 1.0
var _patient: CharacterModel
## The fingers' pose each hand asks for (CharacterModel.set_hand_pose, from the fingers work: &"hold"
## round a roll or a bag, &"pinch" for a needle, a syringe or tape, &"open" (a flat palm) on a
## chest or holding pressure), this frame and
## as last set (&"": the hand's own pose).
var _poses: Array[StringName] = [&"", &""]
var _poses_set: Array[StringName] = [&"", &""]


func _ready() -> void:
	top_level = true
	transform = Transform3D.IDENTITY


## The props for this frame (CharacterModel._process calls it after the arms are posed).
func update(_delta: float) -> void:
	_wanted.clear()
	_poses[0] = &""
	_poses[1] = &""
	var st := model.treat_state()
	if not st.is_empty():
		_read(st)
		_show()
		_last_u = _u
	else:
		_last_u = -1.0
	for i in 2:
		if _poses[i] != _poses_set[i] and model.has_method(&"set_hand_pose"):
			model.call(&"set_hand_pose", i, _poses[i])
		_poses_set[i] = _poses[i]
	for slot: String in _nodes.keys():
		if not _wanted.has(slot):
			var node: Variant = _nodes[slot][1]
			if is_instance_valid(node):
				(node as Node).queue_free()
			_nodes.erase(slot)


## Tests: the props shown now, slot -> key (hand slots start "r:" or "l:", the rest are on the
## casualty or the ground).
func shown() -> Dictionary:
	var out := {}
	for slot: String in _nodes:
		if is_instance_valid(_nodes[slot][1]):
			out[slot] = _nodes[slot][0]
	return out


func _read(st: Dictionary) -> void:
	_tech = st.tech
	_item = st.item
	_t = st.t
	_s = maxf(float(st.s), 0.01)
	_u = st.u
	_work = st.work
	_help = st.help
	_patient = st.patient
	_sc = model.body_scale()
	if int(st.n) != _last_n:
		_last_n = int(st.n)
		_last_u = -1.0
	_site = st.site
	_has_site = not _site.is_empty()
	if _has_site:
		_p = _site.p
		_n = _site.n
		_a = _site.a
		_r = _site.r
	else:
		_p = (_palm(0) + _palm(1)) * 0.5
		_n = model.global_basis.y.normalized()
		_a = -model.global_basis.z.normalized()
		_r = 0.0
	_e = _a.cross(_n)
	_e = _e.normalized() if _e.length() > 0.01 else model.global_basis.x.normalized()


## The clip passed `at` (0..1) since last frame.
func _crossed(at: float) -> bool:
	return _last_u < at and _u >= at


func _show() -> void:
	match _tech:
		&"wrap": _wrap()
		&"pack": _pack()
		&"tourniquet": _tourniquet()
		&"seal": _seal()
		&"needle": _needle()
		&"inject": _inject()
		&"iv": _iv()
		&"io": _io()
		&"cpr": _cpr()
		&"defib": _defib()
		&"clamp": _clamp()
		&"fluids": _fluids()
		&"splint": _splint()
		&"blanket": _blanket()
		&"npa": _npa()


# --- Techniques --------------------------------------------------------------------------

func _wrap() -> void:
	if _item == &"pelvic_binder":
		_binder()
		return
	var look: Array = WRAP_LOOK.get(_item, WRAP_LOOK[&"pressure_bandage"])
	var roll_c: int = look[0]
	var width: float = look[2]
	var radius: float = [1.1, 1.6, 2.1, 2.6][clampi(int((1.0 - _u) * 4.0), 0, 3)]  # unwinding
	var roll := _hand_prop(_work, "roll", "roll|%d|%.1f|%.0f" % [roll_c, radius, width],
		func() -> ItemArt.Shape: return _roll_shape(radius, width, roll_c), null, GRIP, radius / 100.0)
	_world_prop("pad", "pad|%d" % look[1], func() -> ItemArt.Shape: return _pad_shape(look[1]), _on_skin())
	var end := _p + _n * 0.006
	if _r > 0.0:
		var layers := clampi(int(_u * 4.0), 0, 3)  # the turns build up
		if layers > 0:
			var rr := snappedf(_r * 100.0 + 0.5, 0.5)
			_world_prop("turns", "band|%.1f|%.1f|%.0f|%d" % [rr, layers * 0.5, width, roll_c],
				func() -> ItemArt.Shape: return _band_shape(rr, layers * 0.5, width, roll_c), _round_limb())
		end = _onto_limb(_grip_of(roll), 0.01)
	_ribbon("tail", "tile|%d|%.0f" % [roll_c, width], _grip_of(roll), end, roll_c, width)


func _binder() -> void:
	for i: int in [0, 1]:
		var h := _hand_prop(i, "handle", "binder_handle", _binder_handle_shape)
		_ribbon("band_%d" % i, "tile|%d|8" % ItemArt.K.BLACK, _grip_of(h), _p + _n * 0.01, ItemArt.K.BLACK, 8.0)


func _pack() -> void:
	var packing := _u < CharacterModel.PACK_END
	if packing:
		var size: float = [2.0, 3.0, 4.0][clampi(int((1.0 - _u / CharacterModel.PACK_END) * 3.0), 0, 2)]
		var fold := _hand_prop(_work, "gauze", "gauze|%.0f" % size, func() -> ItemArt.Shape: return _gauze_shape(size), null, GRIP, size / 200.0)
		_ribbon("tail", "tile|%d|7" % ItemArt.K.WHITE, _grip_of(fold), _p - _n * 0.01, ItemArt.K.WHITE, 7.0)
		_react(&"wince", 0.45 + 0.4 * absf(sin(_t * 6.0)))  # each push in
	if _u > 0.12:
		_world_prop("wad", "wad", _wad_shape, _on_skin())
	if not packing:  # pressure held: both hands flat on it
		_poses[0] = &"open"
		_poses[1] = &"open"


func _tourniquet() -> void:
	var span := CharacterModel.windlass_span(_s)
	var tight := clampf((_t - span.x) / maxf(span.y - span.x, 0.01), 0.0, 1.0)
	var radius := maxf(_r * 100.0 * (1.0 - 0.08 * tight) + 0.3, 2.0)
	var rr := snappedf(radius, 0.5)
	_world_prop("band", "tq_band|%.1f" % rr, func() -> ItemArt.Shape: return _tq_band_shape(rr), _round_limb())
	var rod := CharacterModel.windlass_rod(_p, _n, _a, CharacterModel.windlass_angle(_t, _s))
	_world_prop("rod", "tq_rod", _tq_rod_shape, Transform3D(_basis_xy(rod.d, _n), rod.c))
	if _t < span.x:  # the running end round the limb and pulled snug
		var end := _hand_prop(_work, "strap", "tq_end", _tq_end_shape)
		_ribbon("tail", "tile|%d|4" % ItemArt.K.BLACK, _grip_of(end), _onto_limb(_grip_of(end), 0.008), ItemArt.K.BLACK, 4.0)
	elif _t < span.y:
		# Tighter every turn, and a sharp pull at the end of each one.
		var turn := fposmod(CharacterModel.windlass_angle(_t, _s) / TAU, 1.0)
		_react(&"wince", 0.3 + 0.6 * tight + 0.25 * smoothstep(0.75, 1.0, turn), _part())


func _seal() -> void:
	if _u < CharacterModel.SEAL_PEEL:
		var holder := _help if _help >= 0 else _work
		_hand_prop(holder, "seal", "seal", _seal_shape, _flat_in(holder), PINCH, 0.012, &"pinch")
		if _help >= 0:
			_hand_prop(_work, "backing", "seal_backing", _backing_shape, _flat_in(_work), PINCH, 0.012, &"pinch")
	else:
		_world_prop("seal", "seal", _seal_shape, _on_skin(0.002))


func _needle() -> void:
	_hand_prop(_work, "needle", "needle", _needle_shape, _basis_z(_n, _a), GRIP, 0.006, &"pinch")  # in, then the stylet back out
	if _u >= CharacterModel.NEEDLE_OUT:
		_world_prop("hub", "cath_hub", _cath_hub_shape, Transform3D(_basis_z(_n, _a), _p))
	if _crossed(CharacterModel.NEEDLE_IN):
		_react(&"gasp", 1.0)  # the trapped air out
	elif _u < CharacterModel.NEEDLE_IN:
		_react(&"wince", 0.35)


func _inject() -> void:
	var syringe := _item == &"adenosine"
	var tip_in := _basis_z(_n, _a)  # the business end (-z) to the skin
	if syringe:
		var push := clampf((_u - CharacterModel.INJECT_JAB) / (CharacterModel.INJECT_AWAY - CharacterModel.INJECT_JAB), 0.0, 1.0)
		var body := _hand_prop(_work, "syringe", "syringe", _syringe_shape, tip_in, GRIP, 0.008, &"pinch")
		_child_prop(body, "plunger", "plunger", _plunger_shape, Vector3(0, 0, (4.0 - 3.0 * push) / 100.0))
		return
	var look: Array = INJECTORS.get(_item, INJECTORS[&"morphine"])
	var pen := _hand_prop(_work, "injector", "injector|%d|%d" % [look[0], look[1]],
		func() -> ItemArt.Shape: return _injector_shape(look[0], look[1]), tip_in, GRIP)
	if _u < CharacterModel.INJECT_CAP * 0.5:
		_child_prop(pen, "cap", "inj_cap|%d" % look[2], func() -> ItemArt.Shape: return _cap_shape(look[2]), Vector3.ZERO)
	elif _u < CharacterModel.INJECT_JAB and _help >= 0:
		_hand_prop(_help, "cap", "inj_cap|%d" % look[2], func() -> ItemArt.Shape: return _cap_shape(look[2]), null, GRIP)
	if _item == &"morphine" and _u >= CharacterModel.INJECT_JAB:
		_react(&"relax", 1.0)


func _iv() -> void:
	var gauge := String(_item).trim_prefix("iv_").to_int()
	var dir := (_a - _n * 0.27).normalized()  # along the vein, towards the heart, into the skin
	if _u < CharacterModel.IV_TAPE:
		_hand_prop(_work, "catheter", "catheter|%d" % gauge, func() -> ItemArt.Shape: return _catheter_shape(gauge), _basis_z(-dir, _n), GRIP, 0.006, &"pinch")
		if _u > CharacterModel.IV_AIM:
			_react(&"wince", 0.25)
	else:
		_world_prop("hub", "iv_hub|%d" % gauge, func() -> ItemArt.Shape: return _iv_hub_shape(gauge), Transform3D(_basis_z(-dir, _n), _p + _n * 0.004))
		_world_prop("tape", "tape", _tape_shape, _on_skin(0.008))
		_poses[0] = &"pinch"
		_poses[1] = &"pinch"


func _io() -> void:
	_hand_prop(_work, "driver", "io_driver", _io_shape, _basis_z(_n, _a), GRIP)


func _cpr() -> void:
	_poses[0] = &"open"
	_poses[1] = &"open"
	_react(&"cpr", CharacterModel.cpr_compression(_t), &"", _n)


func _defib() -> void:
	var aed := _beside("aed", &"defibrillator")
	var pads: Array = _site.get("x", [])
	var top := aed + Vector3.UP * 0.04
	for i in 2:
		var at: Vector3
		if _u < CharacterModel.DEFIB_PADS or pads.size() < 2:
			var hand := _work if i == 0 else _help
			if hand < 0:
				continue
			var pad := _hand_prop(hand, "pad", "aed_pad", _aed_pad_shape, _flat_in(hand), PINCH, 0.012, &"pinch")
			at = _grip_of(pad)
		else:
			var site: Array = pads[i]
			_world_prop("pad_%d" % i, "aed_pad", _aed_pad_shape, Transform3D(_basis_xy(_e, site[1]), site[0]))
			at = site[0]
		_ribbon("cable_%d" % i, "tile|%d|0.5" % ItemArt.K.BLACK, top, at, ItemArt.K.BLACK, 0.5)
	if _crossed(CharacterModel.DEFIB_SHOCK):
		_react(&"spasm", 1.0)


func _clamp() -> void:
	_beside("kit", &"surgery_kit_2")
	var jaws_in := _basis_y_z(-_n, _a)
	_hand_prop(_work, "hemostat", "hemostat", _hemostat_shape, jaws_in, GRIP, 0.006, &"pinch")
	if _help >= 0:
		_hand_prop(_help, "forceps", "forceps", _forceps_shape, jaws_in, GRIP, 0.006, &"pinch")
	_react(&"wince", 0.2)


func _fluids() -> void:
	var vitals := Vitals.find_on(_patient.get_parent()) if is_instance_valid(_patient) else null
	var running: Dictionary = vitals.infusion() if vitals else {}
	var bag_id := _item
	var pressure := _item == &"pressure_bag"
	if pressure:
		bag_id = StringName(running.get("item", &"saline_500"))
	var fill := bag_fill(running) if pressure and not running.is_empty() else 1.0 - PRIME_SHARE * _u  # (a new bag primes the line)
	var hang := _basis_xy(model.global_basis.x.normalized(), Vector3.UP)
	var bag := _hand_prop(_work, "bag", _bag_key(bag_id, fill, pressure), func() -> ItemArt.Shape: return _bag_shape(bag_id, _fill_step(fill), pressure), hang, Vector3(0, -0.04, 0.0))
	var port := bag.global_transform * Vector3(0, -_bag_size(bag_id).y - 0.05, 0)
	if pressure and _help >= 0:
		var bulb := _hand_prop(_help, "bulb", "bulb", _bulb_shape, null, GRIP)
		_ribbon("tube", "tile|%d|0.5" % ItemArt.K.CLEAR, _grip_of(bulb), bag.global_position + Vector3.DOWN * 0.05, ItemArt.K.CLEAR, 0.5)
		_ribbon("line", "tile|%d|0.5" % ItemArt.K.CLEAR, port, _p + _n * 0.01, ItemArt.K.CLEAR, 0.5)
	else:
		_ribbon("line", "tile|%d|0.5" % ItemArt.K.CLEAR, port, _palm(_help) if _help >= 0 else _p + _n * 0.01, ItemArt.K.CLEAR, 0.5)


func _splint() -> void:
	if _u < CharacterModel.SPLINT_SHAPE:  # shaped into a U between the hands
		var curl := clampi(int(_u / CharacterModel.SPLINT_SHAPE * 3.0), 0, 2)
		var right := _palm(0)
		var left := _palm(1) if _help >= 0 else right + model.global_basis.x * -0.16
		var across := (right - left).normalized() if right.distance_to(left) > 0.01 else model.global_basis.x
		var mid := (right + left) * 0.5
		_world_prop("splint", "splint|%d" % curl, func() -> ItemArt.Shape: return _splint_shape(curl),
			Transform3D(_basis_xy(across, model.global_basis.y), mid + model.global_basis.y * -0.02))
		return
	_world_prop("splint", "splint|2", func() -> ItemArt.Shape: return _splint_shape(2), _on_skin(0.004))
	var k := (_u - CharacterModel.SPLINT_SHAPE) / (1.0 - CharacterModel.SPLINT_SHAPE)
	var radius: float = [1.2, 1.8, 2.4][clampi(int((1.0 - k) * 3.0), 0, 2)]
	_hand_prop(_work, "wrap", "roll|%d|%.1f|8" % [ItemArt.K.TAN, radius], func() -> ItemArt.Shape: return _roll_shape(radius, 8.0, ItemArt.K.TAN), null, GRIP, radius / 100.0)
	if _r > 0.0:
		var rr := snappedf(_r * 100.0 + 2.0, 0.5)
		for j in 2:
			if k > 0.3 + 0.35 * j:
				var along := _a * (0.12 if j == 0 else -0.12)
				_world_prop("strap_%d" % j, "band|%.1f|0.5|6|%d" % [rr, ItemArt.K.TAN], func() -> ItemArt.Shape: return _band_shape(rr, 0.5, 6.0, ItemArt.K.TAN),
					Transform3D(_round_limb().basis, _p - _n * _r + along))
	_react(&"wince", 0.25)


func _blanket() -> void:
	var size := clampi(int(_u * 3.0), 0, 2)
	_world_prop("sheet", "foil|%d" % size, func() -> ItemArt.Shape: return _foil_shape(size), _on_skin(0.05))


func _npa() -> void:
	_hand_prop(_work, "npa", "npa", func() -> ItemArt.Shape: return ItemArt._npa(), _basis_z(-_n, _a), GRIP, 0.007, &"pinch")


# --- Helpers: where things go --------------------------------------------------------------

## Flat in hand `i` (world space): facing out of the palm, across the fingers.
func _flat_in(i: int) -> Basis:
	return model.held_anchor(i == 0).global_basis.orthonormalized() * Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)


## The palm of hand `i` (0 right, 1 left), world space.
func _palm(i: int) -> Vector3:
	return model.held_anchor(i == 0).global_position


## A held prop's own origin (its grip), world space.
func _grip_of(node: Node3D) -> Vector3:
	return node.global_position


## Flat on the skin at the site: +y out of it, +z up the limb (towards the trunk).
func _on_skin(lift := 0.0) -> Transform3D:
	return Transform3D(_basis_xy(_e, _n), _p + _n * lift)


## Round the limb at the site: +y along the limb, its centre on the limb's axis.
func _round_limb() -> Transform3D:
	return Transform3D(_basis_xy(_e, _a), _p - _n * _r)  # (+z out through the site)


## The point on the limb's surface (or the site, off the limbs) nearest `from`, `lift` out.
func _onto_limb(from: Vector3, lift: float) -> Vector3:
	if _r <= 0.0:
		return _p + _n * lift
	var centre := _p - _n * _r
	var off := from - centre
	off -= _a * off.dot(_a)
	return centre + (off.normalized() if off.length() > 0.001 else _n) * (_r + lift)


## Where kit set down beside the casualty goes (on the treater's ground), with `item`'s ground
## model there; returns its centre.
func _beside(slot: String, item_id: StringName) -> Vector3:
	var floor_y := model.global_position.y
	var me := model.global_position
	var flat := Vector3(_p.x - me.x, 0.0, _p.z - me.z)
	var toward := flat.normalized() if flat.length() > 0.01 else -model.global_basis.z
	var side := toward.cross(Vector3.UP).normalized()
	var item := ItemDB.get_item(item_id)
	var size := ItemArt.ground_size(item)
	var at := Vector3(_p.x, floor_y, _p.z) - toward * BESIDE.x + side * BESIDE.y + Vector3.UP * size.y * 0.5
	_wanted[slot] = true
	var have: Array = _nodes.get(slot, [])
	var node: Node3D = have[1] if not have.is_empty() and is_instance_valid(have[1]) else null
	if node == null:
		node = ItemArt.ground_node(item)
		node.name = slot
		add_child(node)
		_nodes[slot] = [String(item_id), node]
	_set_layers(node, 1)
	node.global_transform = Transform3D(_basis_xy(side, Vector3.UP), at)
	return at


## Basis with +x along `x` and +y as near `y` as can be (both world directions).
static func _basis_xy(x: Vector3, y: Vector3) -> Basis:
	var bx := x.normalized()
	var by := (y - bx * y.dot(bx))
	by = by.normalized() if by.length() > 0.001 else bx.cross(Vector3.FORWARD).normalized()
	return Basis(bx, by, bx.cross(by))


## Basis with +z along `z` and +y as near `y` as can be.
static func _basis_z(z: Vector3, y: Vector3) -> Basis:
	var bz := z.normalized()
	var by := y - bz * y.dot(bz)
	by = by.normalized() if by.length() > 0.001 else bz.cross(Vector3.RIGHT).normalized()
	return Basis(by.cross(bz), by, bz)


## Basis with +y along `y` exactly and +z as near `z` as can be.
static func _basis_y_z(y: Vector3, z: Vector3) -> Basis:
	var by := y.normalized()
	var bz := z - by * z.dot(by)
	bz = bz.normalized() if bz.length() > 0.001 else by.cross(Vector3.RIGHT).normalized()
	return Basis(by.cross(bz), by, bz)


func _part() -> StringName:
	return StringName(_site.get("part", &""))


func _react(kind: StringName, w: float, part := &"", dir := Vector3.ZERO) -> void:
	if is_instance_valid(_patient):
		_patient.treat_react(kind, w, part, dir)


# --- Helpers: props ---------------------------------------------------------------------------

## A prop in hand `i`'s anchor (CharacterModel.held_anchor): `basis` world-space (its grip at the
## anchor's `grip` point), or null to keep the hand's own axes. `radius`: how far the fingers
## close round it (its "grip" meta, for finger curls); `pose` the fingers' pose for it. Returns
## its node.
func _hand_prop(i: int, slot: String, key: String, build: Callable, basis: Variant = null, grip := GRIP, radius := 0.012, pose := &"hold") -> Node3D:
	_poses[i] = pose
	var anchor := model.held_anchor(i == 0)
	var node := _put(("r:" if i == 0 else "l:") + slot, key, build, anchor)
	node.set_meta(&"grip", radius)
	# The fingers' anchor (CharacterModel.hand_anchor, where they exist) is already the grasp's
	# centre, its +y along what's held: no grip offset, and the props' long axis (x) turned onto y.
	var fingers := model.has_method(&"hand_anchor")
	var at := Vector3.ZERO if fingers else grip
	if basis == null:
		node.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5) if fingers else Basis(), at)
	else:
		node.global_transform = Transform3D((basis as Basis).scaled(Vector3.ONE * _sc), anchor.global_transform * at)
	return node


## A prop on the casualty or the ground, at `xform` (world).
func _world_prop(slot: String, key: String, build: Callable, xform: Transform3D) -> Node3D:
	var node := _put(slot, key, build, self)
	node.global_transform = xform
	return node


## A part of another prop (a plunger, a cap), `at` in its space.
func _child_prop(parent: Node3D, slot: String, key: String, build: Callable, at: Vector3) -> Node3D:
	var node := _put(parent.name + "/" + slot, key, build, parent)
	node.transform = Transform3D(Basis(), at)
	return node


func _put(slot: String, key: String, build: Callable, parent: Node3D) -> Node3D:
	_wanted[slot] = true
	var have: Array = _nodes.get(slot, [])
	if not have.is_empty() and is_instance_valid(have[1]):
		if have[0] == key and (have[1] as Node).get_parent() == parent:
			_set_layers(have[1], _layers_for(parent))
			return have[1]
		(have[1] as Node).queue_free()
	var node := prop_node(key, build)
	node.name = slot.get_slice("/", slot.count("/")).replace(":", "_")
	parent.add_child(node)
	_set_layers(node, _layers_for(parent))
	_nodes[slot] = [key, node]
	return node


## A ribbon of tiles from `a` to `b` (world): a bandage's tail, a line, a cable.
func _ribbon(slot: String, key: String, a: Vector3, b: Vector3, colour: int, width_cm: float) -> void:
	_wanted[slot] = true
	var have: Array = _nodes.get(slot, [])
	var node: MultiMeshInstance3D = have[1] if not have.is_empty() and is_instance_valid(have[1]) else null
	var entry := _mesh(key, func() -> ItemArt.Shape: return _tile_shape(width_cm, colour))
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = slot
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = VoxelArt._get_material()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry[0]
		node.multimesh = mm
		add_child(node)
		_nodes[slot] = [key, node]
	_set_layers(node, 1)
	var line := b - a
	var length := line.length()
	var count := mini(ceili(length / (TILE_CM / 100.0)), MAX_TILES) if length > 0.005 else 0
	var mm2 := node.multimesh
	if mm2.instance_count != count:
		mm2.instance_count = count
	if count == 0:
		return
	var dir := line / length
	var basis := _basis_z(dir, _n if absf(dir.dot(_n)) < 0.95 else _a)
	var voxel: float = entry[2]
	var off: Vector3 = entry[1]
	var step := length / count
	for k in count:
		var at := a + dir * (step * k)
		mm2.set_instance_transform(k, Transform3D(basis, at) * Transform3D(Basis.from_scale(Vector3.ONE * voxel), off))  # (overlapping: no gaps)


func _layers_for(parent: Node) -> int:
	if parent == self:
		return 1
	return model.render_layers | (CharacterModel.VIEW_HANDS_LAYER if view_hands else 0)


static func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D and (node as VisualInstance3D).layers != layers:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children():
		_set_layers(child, layers)


## A prop's node: its voxel mesh (`build`, an ItemArt.Shape written in cm round the prop's own
## origin), built once per key. The node's origin is the shape's origin.
static func prop_node(key: String, build: Callable) -> Node3D:
	var entry := _mesh(key, build)
	var holder := Node3D.new()
	holder.name = key.get_slice("|", 0)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = entry[0]
	mesh_instance.material_override = VoxelArt._get_material()
	mesh_instance.scale = Vector3.ONE * float(entry[2])
	mesh_instance.position = entry[1]
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh_instance)
	return holder


static func _mesh(key: String, build: Callable) -> Array:
	if not _meshes.has(key):
		var shape: ItemArt.Shape = build.call()
		var spec := shape.spec()
		var lo := Vector3(INF, INF, INF)
		for box: Array in shape.boxes:
			var a: Vector3 = (box[0] / shape.res).round()
			var c: Vector3 = (box[1] / shape.res).round()
			if not box[3] and c.x > a.x and c.y > a.y and c.z > a.z:
				lo = lo.min(a)
		if lo.x == INF:
			lo = Vector3.ZERO
		var voxel: float = spec.voxel
		var buffer := VoxelArt._rasterize(spec, "multicam", key.hash())
		_meshes[key] = [ItemArt._get_mesher().build_mesh(buffer, []), lo * voxel, voxel]
	return _meshes[key]


# --- The site --------------------------------------------------------------------------------

## Where treating `part` of `target` with technique `tech` happens, in the rest pose, for the
## clip's action_net "site" (plain data, the same on every peer): "part" (the body part whose bone
## it rides), "p" (the point on the skin, bone-local), "n" (out of the skin there, bone-local), "r"
## (the limb's radius there, m; 0 off the limbs) and "x" (more spots: [point, normal], bone-local:
## the defib's second pad site and so on). The skin is BodyVolume's (the drawn 0.5 cm body):
## - most techniques: the wound on that part (Vitals.wound_list "at", one still bleeding or
##   untreated first), else the part's middle on the side facing the treater;
## - tourniquet: TOURNIQUET_HIGH up the limb from there (high and tight), short of the joint;
## - needle: the second intercostal space, mid-clavicle, on the tension side; cpr, io and defib
##   the sternum (defib pads: upper right chest, lower left ribs); npa the nose; iv the inside of
##   the forearm or lower leg; fluids the line's site (Vitals.access); inject the outer thigh on
##   the treater's side (your own firing side). Off a body lying face down (the front against the
##   ground) the chest spots go on the back instead, where the hands can get at them.
## {} if `target` has no model.
static func rest_site(target: Node3D, part: StringName, tech: StringName, treater: Node3D) -> Dictionary:
	var model := target.get_node_or_null(^"Model") as CharacterModel if is_instance_valid(target) else null
	if model == null or model.torso == null:
		return {}
	var body := model.body
	var vitals := Vitals.find_on(target)
	var site_part := part
	var aim := Vector3.ZERO
	var outward := Vector3.ZERO
	var extra: Array = []
	var chest_front := false
	match tech:
		&"inject":
			var side := 1.0
			if treater == target:
				side = -1.0 if model.left_handed else 1.0
			elif is_instance_valid(treater):
				var right := model.part_node(Vitals.THIGH_R)
				var left := model.part_node(Vitals.THIGH_L)
				if right and left and treater.global_position.distance_to(left.global_position) < treater.global_position.distance_to(right.global_position):
					side = -1.0
			site_part = Vitals.THIGH_R if side > 0.0 else Vitals.THIGH_L
			aim = _box_centre(site_part) + Vector3(0, 0.06, 0)
			outward = Vector3(side, 0, 0)
		&"needle":
			site_part = Vitals.CHEST
			var side := 1.0
			if vitals:
				for w: Dictionary in vitals.wound_list():
					if w.part == Vitals.CHEST and w.get("at") is Vector3:
						side = signf(Vector3(w.at).x) if absf(Vector3(w.at).x) > 0.01 else side
						if w.get("tension", false):
							break
			aim = Vector3(0.09 * side, 1.38, 0)
			outward = Vector3.FORWARD
			chest_front = true
		&"cpr", &"defib", &"io":
			site_part = Vitals.CHEST
			aim = Vector3(0, 1.36 if tech == &"io" else 1.27, 0)
			outward = Vector3.FORWARD
			chest_front = true
			if tech == &"defib":
				extra = [[Vector3(0.1, 1.38, 0), Vector3.FORWARD], [Vector3(-0.13, 1.2, 0), Vector3(-0.6, 0, -0.8).normalized()]]
		&"npa":
			site_part = Vitals.FACE
			aim = Vector3(0, 1.585, 0)
			outward = Vector3.FORWARD
		&"iv", &"fluids":
			if tech == &"fluids" and vitals and not vitals.access().is_empty():
				site_part = StringName(vitals.access().get("part", part))
			if site_part == Vitals.CHEST:  # an IO line: the sternum
				aim = Vector3(0, 1.36, 0)
				chest_front = true
			else:
				aim = _box_centre(site_part) + Vector3(0, -0.03, 0)
			outward = Vector3.FORWARD
	if aim == Vector3.ZERO:  # the wound itself
		var wound: Variant = null
		if vitals:
			for w: Dictionary in vitals.wound_list():
				if w.part == part and w.get("at") is Vector3 and (wound == null or (w.bleeding and not w.treated)):
					wound = w.at
		if wound is Vector3:
			aim = wound
			outward = WoundMarks._outward(part, aim)
		else:
			aim = _box_centre(part)
			outward = _facing(model, part, treater)
	if not BodyVolume.PART_MODELS.has(site_part) or model.part_node(site_part) == null:
		return {}
	var limb := not BodyMap.SEGMENTS.has(BodyMap.segment_of(site_part))
	var pivot := BodyVolume.pivot_at(site_part, body)
	if tech == &"tourniquet" and limb:
		aim.y = minf(aim.y + CharacterModel.TOURNIQUET_HIGH, pivot.y - 0.05)
	if chest_front:
		var bone := model.part_node(site_part)
		if (bone.global_basis * Vector3.FORWARD).y < -0.5:  # lying on his front
			outward = Vector3.BACK
			for spot: Array in extra:
				spot[1] = Vector3(spot[1].x, spot[1].y, -spot[1].z)
	var skin := _skin(site_part, aim, outward, body)
	var r := 0.0
	if limb:
		var centre := _box_centre(site_part)
		r = Vector2(skin.x - centre.x, skin.z - centre.z).length()
	var spots: Array = []
	for spot: Array in extra:
		spots.append([_skin(site_part, spot[0], spot[1], body) - pivot, spot[1]])
	return {"part": site_part, "p": skin - pivot, "n": outward.normalized(), "r": r, "x": spots}


## A rest_site in world space now, on `model` (the patient's).
static func site_world(site: Dictionary, model: CharacterModel) -> Vector3:
	var bone := model.part_node(StringName(site.get("part", &""))) if model else null
	if bone == null:
		return model.global_position if model else Vector3.ZERO
	return bone.global_transform * Vector3(site.p)


## The skin of `part` under rest-pose `aim` looking in along -`outward` (BodyVolume.surface), or
## `aim` itself if there's none.
static func _skin(part: StringName, aim: Vector3, outward: Vector3, body: String) -> Vector3:
	var hit: Variant = BodyVolume.surface(part, aim, outward.normalized(), 0.14, body)
	return hit if hit is Vector3 else aim


static func _box_centre(part: StringName) -> Vector3:
	var boxes: Array = BodyMap.PART_BOXES.get(part, BodyMap.PART_BOXES[Vitals.CHEST])
	return boxes[0][0]


## Out from `part` towards the treater, level across the part (its own space, rest pose); its
## front for yourself.
static func _facing(model: CharacterModel, part: StringName, treater: Node3D) -> Vector3:
	var bone := model.part_node(part)
	if bone == null or not is_instance_valid(treater) or treater == model.get_parent():
		return Vector3.FORWARD
	var local := bone.global_basis.inverse() * (treater.global_position + Vector3.UP * 0.6 - bone.global_position)
	local.y = 0.0
	return local.normalized() if local.length() > 0.01 else Vector3.FORWARD


# --- Bags (also for WoundMarks' hung bags) ----------------------------------------------------

## How full a running bag is (0..1) from Vitals.infusion(): mL left of its mL.
static func bag_fill(infusion: Dictionary) -> float:
	if infusion.is_empty():
		return 1.0
	return clampf(float(infusion.get("left", 0.0)) / maxf(float(infusion.get("ml", 1.0)), 1.0), 0.0, 1.0)


## A hanging IV bag of `item_id` (saline_* or blood_*), `fill` (0..1) full, hung from its
## node's origin (the hanger), ports down; with `pressure`, inside a pressure bag's sleeve.
static func bag_node(item_id: StringName, fill: float, pressure := false) -> Node3D:
	var step := _fill_step(fill)
	return prop_node(_bag_key(item_id, fill, pressure), func() -> ItemArt.Shape: return _bag_shape(item_id, step, pressure))


static func _fill_step(fill: float) -> int:
	return clampi(ceili(clampf(fill, 0.0, 1.0) * FILL_STEPS), 0, FILL_STEPS)


static func _bag_key(item_id: StringName, fill: float, pressure: bool) -> String:
	return "bag|%s|%d|%s" % [item_id, _fill_step(fill), pressure]


static func _bag_ml(item_id: StringName) -> int:
	return maxi(String(item_id).get_slice("_", 1).to_int(), 100)


## A bag's size (m): width, length (hanger to ports), thickness.
static func _bag_size(item_id: StringName) -> Vector3:
	var k := pow(_bag_ml(item_id) / 500.0, 1.0 / 3.0)
	return Vector3(0.12, 0.19, 0.024) * k


# --- Shapes (centimetres, round each prop's own origin) ---------------------------------------
# Hand props: x across the hand, -y along the fingers, +z out of the palm, unless placed with a
# basis of their own (then +z is the way they point: the needle's tip at -z, and so on).

static func _roll_shape(radius: float, width: float, colour: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.X, 0, 0, radius, -width * 0.5, width * 0.5, colour)
	s.cyl(ItemArt.Axis.X, 0, 0, 0.6, -width * 0.5 - 0.01, width * 0.5 + 0.01, ItemArt.K.PAPER, true)  # the core
	return s


static func _tile_shape(width: float, colour: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-width * 0.5, 0, 0, width * 0.5, 0.5, TILE_CM, colour)
	return s


static func _pad_shape(colour: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-4.5, 0, -4, 4.5, 1, 4, colour)
	s.b(-1.5, 1, -1.5, 1.5, 2, 1.5, ItemArt.K.GREY)  # the pressure bar
	return s


## Turns of a bandage (or a splint's strap) round a limb: a band `width` wide round the y axis,
## `radius` (cm) inside, `thick` thick.
static func _band_shape(radius: float, thick: float, width: float, colour: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.ring(ItemArt.Axis.Y, 0, 0, radius + thick, radius, -width * 0.5, width * 0.5, colour)
	return s


static func _binder_handle_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-2.5, -0.6, -0.6, 2.5, 0.7, 0.7, ItemArt.K.BLUE)
	return s


static func _gauze_shape(size: float) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	for i in int(size):  # the z-fold's layers
		s.b(-size * 0.5, -size * 0.5 + i, -2.5, size * 0.5, -size * 0.5 + i + 1, 2.5, ItemArt.K.WHITE if i % 2 == 0 else ItemArt.K.CREAM)
	return s


static func _wad_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-2.5, 0, -2.5, 2.5, 1.0, 2.5, ItemArt.K.WHITE)
	s.b(-1.5, 1.0, -1.5, 1.5, 1.5, 1.5, ItemArt.K.CREAM)
	s.p(-1.0, 0.5, -2.5, 1.0, 1.0, -1.5, ItemArt.K.BLOOD)
	return s


## The tourniquet's band round the limb (y axis), `radius` (cm) inside: the windlass's base plate
## on the outside (+z), the clip up the limb from it, the white time tab below.
static func _tq_band_shape(radius: float) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.ring(ItemArt.Axis.Y, 0, 0, radius + 0.6, radius, -1.9, 1.9, ItemArt.K.BLACK)
	s.b(-2.5, -2.0, radius, 2.5, 2.0, radius + 1.0, ItemArt.K.BLACK)
	s.b(-0.8, 2.0, radius, 0.8, 4.5, radius + 1.8, ItemArt.K.DARK_GREY)
	s.b(-1.5, -3.0, radius + 0.2, 1.5, -2.0, radius + 0.8, ItemArt.K.WHITE)
	return s


static func _tq_rod_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.X, 0, 0, 0.6, -4.5, 4.5, ItemArt.K.BLACK)
	s.cyl(ItemArt.Axis.X, 0, 0, 0.8, -4.5, -3.5, ItemArt.K.DARK_GREY)
	s.cyl(ItemArt.Axis.X, 0, 0, 0.8, 3.5, 4.5, ItemArt.K.DARK_GREY)
	return s


static func _tq_end_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-2, -1.0, -0.3, 2, 5, 0.3, ItemArt.K.BLACK)
	s.b(-2, -3.0, -0.3, 2, -1.0, 0.3, ItemArt.K.RED)  # the red tip, out of the fist
	return s


static func _seal_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-6, 0, -6, 6, 0.5, 6, ItemArt.K.WHITE)
	s.p(-4.5, 0, -4.5, 4.5, 0.5, 4.5, ItemArt.K.CLEAR)
	s.b(-1.2, 0.5, -1.2, 1.2, 1.5, 1.2, ItemArt.K.WHITE)  # the one-way valve
	s.p(-0.5, 1.0, -0.5, 0.5, 1.5, 0.5, ItemArt.K.DARK_GREY)
	return s


static func _backing_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-6, 0, -6, 6, 0.5, 6, ItemArt.K.PAPER)
	s.b(4, 0, 4, 7.5, 0.5, 7.5, ItemArt.K.RED)  # the pull tab
	return s


## A decompression needle by its hub (the origin): 8 cm of steel out to -z, the flash chamber and
## cap behind.
static func _needle_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.3, -8, 0, ItemArt.K.STEEL)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.6, 0, 2, ItemArt.K.GREY_LIGHT)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.8, 2, 4.5, ItemArt.K.CLEAR)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.9, 4.5, 6, ItemArt.K.RED)
	return s


static func _cath_hub_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.6, 0, 1.5, ItemArt.K.GREY_LIGHT)
	return s


## An autoinjector held round its middle (the origin): the tip end at -z, the safety cap end +z.
static func _injector_shape(body: int, tip: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 1.2, -6.5, 6.5, body)
	s.cyl(ItemArt.Axis.Z, 0, 0, 1.25, -6.5, -4.0, tip)
	s.cyl(ItemArt.Axis.Z, 0, 0, 1.5, -1.5, 2.5, ItemArt.K.WHITE, true)
	return s


static func _cap_shape(colour: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 1.0, 6.5, 9.0, colour)
	return s


## A syringe held at its barrel (the origin): needle out to -z; the plunger is its own part.
static func _syringe_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.8, -3, 4, ItemArt.K.CLEAR)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.5, -2, 3, ItemArt.K.RED, true)
	s.b(-1.5, -0.5, 4, 1.5, 0.5, 4.5, ItemArt.K.WHITE)  # finger flange
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.3, -5.5, -3, ItemArt.K.STEEL)
	return s


static func _plunger_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.4, -3.0, 3.5, ItemArt.K.WHITE)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.9, 3.5, 4.0, ItemArt.K.WHITE)
	return s


## An IV catheter by its hub (the origin): the cannula and needle out to -z, the flash chamber
## behind, the hub and wings in the gauge's colour (ItemArt.GAUGE_COLOURS).
static func _catheter_shape(gauge: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	var hub: int = ItemArt.GAUGE_COLOURS.get(gauge, ItemArt.K.GREY)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.35, -4.5, 0, ItemArt.K.CLEAR)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.6, 0, 1.5, hub)
	s.b(-2.0, -0.3, 0.2, 2.0, 0.3, 1.2, hub)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.7, 1.5, 3.5, ItemArt.K.CLEAR)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.8, 3.5, 4.2, ItemArt.K.WHITE)
	return s


static func _iv_hub_shape(gauge: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	var hub: int = ItemArt.GAUGE_COLOURS.get(gauge, ItemArt.K.GREY)
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.6, 0, 1.5, hub)
	s.b(-2.0, -0.3, 0.2, 2.0, 0.3, 1.2, hub)
	return s


static func _tape_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-3, 0, -1.5, 3, 0.5, 1.5, ItemArt.K.WHITE)
	return s


## A sternal IO driver by its T-handle (the origin): the needle out to -z.
static func _io_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.cyl(ItemArt.Axis.Z, 0, 0, 0.3, -3.0, -0.5, ItemArt.K.STEEL)
	s.cyl(ItemArt.Axis.Z, 0, 0, 1.0, -0.5, 1.0, ItemArt.K.BLACK)
	s.b(-4, -0.8, 1.0, 4, 0.8, 2.5, ItemArt.K.BLACK)
	s.p(-1.0, -0.8, 1.0, 1.0, 0.8, 2.5, ItemArt.K.YELLOW)
	return s


static func _aed_pad_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-5, 0, -6.5, 5, 0.5, 6.5, ItemArt.K.WHITE)
	s.p(-3, 0, -4, 3, 0.5, 4, ItemArt.K.GREY_LIGHT)
	s.p(-1.5, 0, -1.5, 1.5, 0.5, 1.5, ItemArt.K.RED)
	return s


## A hemostat by its finger rings (the origin), its jaws out along +y: ItemArt's model (lying
## along z) stood up.
static func _hemostat_shape() -> ItemArt.Shape:
	var s := ItemArt._clamp()
	for box: Array in s.boxes:
		var a := Vector3(box[0].x, box[0].z - 1.5, -box[0].y)
		var c := Vector3(box[1].x, box[1].z - 1.5, -box[1].y)
		box[0] = a.min(c)
		box[1] = a.max(c)
	return s


static func _forceps_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-1.0, 0, -0.25, -0.5, 12, 0.25, ItemArt.K.SILVER)
	s.b(0.5, 0, -0.25, 1.0, 12, 0.25, ItemArt.K.SILVER)
	s.b(-1.0, -1.0, -0.25, 1.0, 0, 0.25, ItemArt.K.STEEL)
	return s


## A hanging bag: the hanger at the origin, the bag down from it (-y), the ports at its bottom;
## the fluid in it `step` of FILL_STEPS full (clear plastic above); in a pressure sleeve with
## `pressure`.
static func _bag_shape(item_id: StringName, step: int, pressure: bool) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	var size := _bag_size(item_id) * 100.0
	var w := size.x
	var l := size.y
	var h := size.z
	var blood := String(item_id).begins_with("blood_")
	s.b(-0.6, -1.0, -0.25, 0.6, 0, 0.25, ItemArt.K.WHITE)  # the hanger tab
	s.prism(ItemArt.Axis.Y, 0, 0, w * 0.5, h * 0.5, h * 0.45, -1.0 - l, -1.0, ItemArt.K.SMOKE_WHITE)
	var level := -1.0 - l + l * float(step) / FILL_STEPS
	if step > 0:
		s.prism(ItemArt.Axis.Y, 0, 0, w * 0.5 - 0.01, h * 0.5 + 0.01, h * 0.45, -1.0 - l, level, ItemArt.K.BLOOD if blood else ItemArt.K.SALINE, true)
	s.p(-w * 0.3, -1.0 - l * 0.7, -h * 0.5 - 0.01, w * 0.3, -1.0 - l * 0.25, -h * 0.5 + 0.5, ItemArt.K.WHITE if blood else ItemArt.K.BLUE)  # the label
	s.cyl(ItemArt.Axis.Y, -w * 0.15, 0, 0.45, -3.5 - l, -1.0 - l, ItemArt.K.WHITE)  # ports
	s.cyl(ItemArt.Axis.Y, w * 0.15, 0, 0.45, -3.0 - l, -1.0 - l, ItemArt.K.BLUE if blood else ItemArt.K.WHITE)
	s.cyl(ItemArt.Axis.Y, -w * 0.15, 0, 0.8, -6.0 - l, -3.5 - l, ItemArt.K.CLEAR)  # the drip chamber
	if pressure:  # the sleeve: a cuff round the bag, its gauge
		s.b(-w * 0.5 - 0.5, -1.0 - l * 0.9, -h * 0.5 - 0.5, w * 0.5 + 0.5, -1.0 - l * 0.15, h * 0.5 + 0.5, ItemArt.K.BLUE)
		s.p(-w * 0.35, -1.0 - l * 0.8, -h * 0.5 - 0.5, w * 0.35, -1.0 - l * 0.3, -h * 0.5, ItemArt.K.NAVY)
		s.cyl(ItemArt.Axis.Z, w * 0.3, -1.0 - l * 0.2, 1.6, h * 0.5 + 0.5, h * 0.5 + 1.5, ItemArt.K.WHITE)
	return s


static func _bulb_shape() -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.lathe(ItemArt.Axis.Y, 0, 0, [[-3.0, 0.6], [-1.5, 1.6], [1.5, 1.6], [3.0, 0.6]], ItemArt.K.BLACK)
	return s


## A SAM-style splint, 11 x 40 cm, lying along z: flat (`curl` 0) to a U (2) whose sides curl
## down (-y) round the limb; orange with blue edges.
static func _splint_shape(curl: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	s.b(-2.5, 0, -20, 2.5, 0.5, 20, ItemArt.K.ORANGE)
	for side: float in [1.0, -1.0]:
		for col in 3:
			var x0 := 2.5 + col
			var drop := -(col + 1) * 0.5 * curl
			var colour := ItemArt.K.BLUE if col == 2 else ItemArt.K.ORANGE
			s.b(x0 * side, drop, -20, (x0 + 1.0) * side, drop + 0.5 + (0.5 * curl if col > 0 else 0.0), 20, colour)
	return s


## A foil blanket opening out: folded (0), half (1), open over the body (2); gold up.
static func _foil_shape(size: int) -> ItemArt.Shape:
	var s := ItemArt.Shape.new()
	var half: Vector2 = [Vector2(8, 10), Vector2(18, 20), Vector2(30, 40)][size]
	s.b(-half.x, 0, -half.y, half.x, 0.5, half.y, ItemArt.K.SILVER)
	s.p(-half.x, 0, -half.y, half.x, 0.5, half.y, ItemArt.K.GOLD)
	return s
