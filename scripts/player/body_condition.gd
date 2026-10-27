class_name BodyCondition
extends Node3D
## How the casualty's state shows on the body itself, voxel by voxel (each 0.5 cm voxel of the
## model takes one colour, so it stays in the model's grain):
## - Burns (WoundModel.burn, the share of the body burned): patches of skin and cloth scorched
##   and charred, raw red at the skin's edges, the dressed share under pale burn dressings.
## - Pallor: skin greys as blood is lost (from 15% lost, ashen by 45%). Not on the dead: the
##   overlay is a second pass on every part, and corpses can be many.
## - Blue lips: the mouth and lip voxels go blue-grey when SpO2 is under WoundModel's
##   SPO2_BLUE_LIPS (Vitals.signs' "Blue lips").
## - Coughing blood (blast lung, a lung filling with blood): blood at the mouth and down the chin.
## - Shivering (hypothermic): the body's meshes tremble.
## Burns, pallor and lips are a material overlay on the body part meshes (CharacterModel's
## VoxelArt meshes, their vertex colours unchanged, and the face's moving parts); it is only set
## while there's something to show. Each mesh's overlay knows the skin, lips, hair and eyes of
## the colour scheme it was built in (a face's own: FaceRig's palette, not the uniform's
## default), so only skin and lips change and hair, brows and eyes never do (Captain,
## 2026-10-21: "hair blues/gets pallor when it shouldnt"). Everything follows replicated state (Vitals), so every peer shows the same. Created
## by WoundMarks.

const PALLOR_FROM := 0.85  # blood fraction where the skin starts to pale
const PALLOR_FULL := 0.55
const SHIVER_M := 0.0018
const SHIVER_HZ := 13.0
const MOUTH_BLOOD := [Color("7d130f"), Color("5a0c09"), Color("8e1a12")]
const CELL := 0.005

var model: CharacterModel
var vitals: Vitals
var body := ""
var _materials: Dictionary = {}  # colour scheme -> its overlay ShaderMaterial
var _overlaid: Array[MeshInstance3D] = []
var _pallor := 0.0
var _burn := 0.0
var _blue := false
var _shivering := false
var _mouth_blood := false
var _rest_positions: Dictionary = {}  # MeshInstance3D -> its position before shivering
var _time := 0.0
var _mouth_mesh: MultiMeshInstance3D
var _mouth_drawn := false
static var _shader: Shader

const SHADER := """
shader_type spatial;
render_mode cull_back;

uniform float burn = 0.0;
uniform float dressed = 0.0;
uniform float pallor = 0.0;
uniform float blue = 0.0;
uniform float seed = 0.0;
uniform float unit_m = 0.005;
uniform vec3 skin;
uniform vec3 skin_shade;
uniform vec3 mouth;
uniform vec3 lip;
uniform vec3 lip_shade;
uniform vec3 hair;
uniform vec3 eye;
uniform vec3 camo[4];
// Set per mesh (set_instance_shader_parameter): 1 on the head and the face's parts. Lips and
// the mouth are only matched there (v0.7.1, the Captain: "people turning blue where they
// aren't supposed to, including their uniform": the mouth colour, skin darkened 35%, sat within
// the match of camo tones like 7d6447, so the uniform went blue with the lips).
instance uniform float face_part = 0.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13) + seed);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// The palette's colours are exact (VoxelArt: no per-voxel jitter), so the match is tight: at
// 0.03 the mouth colour caught camo and gear tones and the uniform went blue (v0.7.1).
bool near(vec3 a, vec3 b) {
	return distance(a, b) < 0.012;
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	// The voxel this fragment is on (half a voxel in from its face): one colour per voxel.
	vec3 cell = floor(local_pos - local_normal * 0.5);
	vec3 metres = cell * unit_m;
	vec3 base = COLOR.rgb;
	bool kept = near(base, hair) || near(base, eye);  // hair, brows and eyes never pale or blue
	for (int i = 0; i < 4; i++) {
		kept = kept || distance(base, camo[i]) < 0.012;  // nor the uniform's own camo
	}
	bool is_skin = !kept && (near(base, skin) || near(base, skin_shade));
	bool is_lip = !kept && face_part > 0.5 && (near(base, mouth) || near(base, lip) || near(base, lip_shade));
	vec3 col = base;
	bool changed = false;
	if (burn > 0.0) {
		// Patches about 10 cm across; the share of voxels under the threshold tracks the burn.
		float n = value_noise(metres * 9.0) * 0.65 + value_noise(metres * 23.0) * 0.35;
		float threshold = 0.22 + burn * 0.62;
		if (n < threshold) {
			float speck = hash(cell);
			if (n > threshold - 0.035) {
				col = is_skin ? vec3(0.55, 0.16, 0.11) : base * 0.45;  // singed, raw at the skin
			} else if (value_noise(metres * 5.0 + 7.0) < dressed) {
				col = vec3(0.86, 0.85, 0.80) * (0.92 + speck * 0.08);  // a burn dressing over it
			} else if (speck < 0.45) {
				col = vec3(0.07, 0.055, 0.045);  // charred
			} else if (is_skin) {
				col = speck < 0.8 ? vec3(0.25, 0.10, 0.07) : vec3(0.45, 0.12, 0.08);
			} else {
				col = base * 0.22 + vec3(0.08, 0.05, 0.03);  // scorched cloth
			}
			changed = true;
			is_skin = false;
			is_lip = false;
		}
	}
	if (is_lip && blue > 0.0) {
		col = mix(col, vec3(0.36, 0.40, 0.55), blue);
		changed = true;
	} else if ((is_skin || is_lip) && pallor > 0.0) {
		float grey = dot(col, vec3(0.3, 0.55, 0.15));
		col = mix(col, vec3(grey * 0.97, grey * 0.97, grey * 0.99), pallor * 0.7);  // ashen, never blue: only the lips go blue
		changed = true;
	}
	if (!changed) {
		discard;
	}
	ALBEDO = to_linear(col);
	ROUGHNESS = 0.85;
}
"""


func setup(p_model: CharacterModel, p_vitals: Vitals, p_body: String) -> void:
	model = p_model
	vitals = p_vitals
	body = p_body
	vitals.changed.connect(_refresh)
	set_process(false)
	_refresh()


## How pale the skin is drawn (0..1).
func pallor() -> float:
	return _pallor


## The burned share drawn (0..1).
func burn() -> float:
	return _burn


func lips_blue() -> bool:
	return _blue


func shivering() -> bool:
	return _shivering


func mouth_blood() -> bool:
	return _mouth_blood


## The body meshes the overlay is on now (tests).
func overlaid() -> Array[MeshInstance3D]:
	return _overlaid.filter(func(m: Variant) -> bool: return is_instance_valid(m))  # (untyped: a freed mesh fails a typed argument before the check)


func _refresh() -> void:
	if not is_instance_valid(vitals) or not is_instance_valid(model):
		return
	var m := vitals._m()
	var dead := vitals.is_dead()
	_pallor = 0.0 if dead else clampf((PALLOR_FROM - vitals.blood_fraction()) / (PALLOR_FROM - PALLOR_FULL), 0.0, 1.0)
	_burn = clampf(vitals.burn_share(), 0.0, 1.0)
	_blue = not dead and not m.arrest and vitals.spo2() < WoundModel.SPO2_BLUE_LIPS or (m.arrest and not dead)
	var fluid := 0.0
	for which: StringName in WoundModel.LUNGS:
		fluid = maxf(fluid, float(m.lung_fluid[which]))
	_mouth_blood = not dead and (vitals.has_blast_lung() or fluid >= 0.3)
	var shiver := not dead and vitals.hypothermic()
	if shiver != _shivering:
		_shivering = shiver
		if not shiver:
			_still()
		set_process(shiver)
	_set_overlay()
	_draw_mouth()


func _set_overlay() -> void:
	var needed := _burn > 0.0 or _pallor > 0.0 or _blue
	if not needed:
		for mesh: MeshInstance3D in overlaid():
			if mesh.material_overlay in _materials.values():
				mesh.material_overlay = null
		_overlaid.clear()
		return
	var m := vitals._m()
	var needed_dressings := m.burn_dressings + m.burn_dressings_needed()
	for mesh: MeshInstance3D in overlay_meshes():
		var material := _material_for(scheme_of(mesh))
		if mesh.material_overlay == null or (mesh.material_overlay in _materials.values() and mesh.material_overlay != material):
			mesh.material_overlay = material  # (a face built since keeps its own scheme's)
		if mesh not in _overlaid:
			_overlaid.append(mesh)
			mesh.set_instance_shader_parameter(&"face_part", 1.0 if _on_head(mesh) else 0.0)
	for material: ShaderMaterial in _materials.values():
		material.set_shader_parameter(&"burn", _burn)
		material.set_shader_parameter(&"dressed", float(m.burn_dressings) / needed_dressings if needed_dressings > 0 else 0.0)
		material.set_shader_parameter(&"pallor", _pallor)
		material.set_shader_parameter(&"blue", 1.0 if _blue else 0.0)


## Whether `mesh` hangs off the head part (its voxels, the face's moving parts).
func _on_head(mesh: Node) -> bool:
	var head := model.part_node(Vitals.HEAD)
	return head != null and (mesh == head or head.is_ancestor_of(mesh))


## The colour scheme `mesh` was built in: its part pivot's (VoxelArt.instance, FaceRig: a face's
## palette), else the body's.
func scheme_of(mesh: Node) -> String:
	var n := mesh
	while n != null and n != model:
		if n.has_meta(&"voxel_variant"):
			return String(n.get_meta(&"voxel_variant"))
		n = n.get_parent()
	return model.variant


## The overlay for colour scheme `scheme`: its skin, lips, hair and eyes.
func _material_for(scheme: String) -> ShaderMaterial:
	if _materials.has(scheme):
		return _materials[scheme]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var material := ShaderMaterial.new()
	material.shader = _shader
	var spec := VoxelArt.spec(scheme)
	var skin := Color(spec.get("skin", "c8996f"))
	material.set_shader_parameter(&"skin", _rgb(skin))
	material.set_shader_parameter(&"skin_shade", _rgb(skin.darkened(0.15)))
	material.set_shader_parameter(&"mouth", _rgb(skin.darkened(0.35)))
	material.set_shader_parameter(&"lip", _rgb(skin.lerp(Color("9a4a44"), 0.3).darkened(0.12)))
	material.set_shader_parameter(&"lip_shade", _rgb(skin.lerp(Color("9a4a44"), 0.2)))
	material.set_shader_parameter(&"hair", _rgb(Color(spec.get("hair", "3b2a1d"))))
	material.set_shader_parameter(&"eye", _rgb(Color(spec.get("eye", "1c1c1c"))))
	var camo := PackedVector3Array()
	for c: Variant in spec.get("camo", []):
		var tone: Color = c if c is Color else Color(str(c))  # (hex strings; a civilian scheme's are Colors)
		if camo.size() < 4 and _rgb(tone).distance_to(_rgb(skin)) > 0.06:  # (a scheme whose camo is its skin, the test dummy's, keeps its skin)
			camo.append(_rgb(tone))
	while camo.size() < 4:
		camo.append(Vector3(-9, -9, -9))
	material.set_shader_parameter(&"camo", camo)
	material.set_shader_parameter(&"seed", float(hash(model.get_parent().name if model.get_parent() else model.name) % 1000) / 37.0)
	material.set_shader_parameter(&"unit_m", VoxelArt.BODY_VOXEL / VoxelArt.BODY_SUB)
	_materials[scheme] = material
	return material


## What the overlay goes on: the body's meshes (body_meshes) and the face's moving parts
## (FaceRig's Face_* meshes on the head's mesh: the mouth's lips go blue with the rest).
func overlay_meshes() -> Array[MeshInstance3D]:
	var out := body_meshes()
	var head := model.part_node(Vitals.HEAD)
	if head:
		for mi: Node in head.get_children():
			for part: Node in mi.get_children():
				if part is MeshInstance3D and String(part.name).begins_with("Face_"):
					out.append(part)
	return out


static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## The body's own meshes: each part's VoxelArt mesh, plus any other plain mesh hung straight
## on a part (fingers), never gear or the marks' MultiMeshes.
func body_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var seen := {}
	for part: StringName in [Vitals.HEAD, Vitals.CHEST, Vitals.UPPER_ARM_L, Vitals.UPPER_ARM_R, Vitals.FOREARM_L,
			Vitals.FOREARM_R, Vitals.THIGH_L, Vitals.THIGH_R, Vitals.SHIN_L, Vitals.SHIN_R]:
		var bone := model.part_node(part)
		if bone == null or seen.has(bone):
			continue
		seen[bone] = true
		for child: Node in bone.get_children():
			if child is MeshInstance3D:
				out.append(child)
	return out


## Blood at the mouth: on the lips and running from the corners down the chin.
func _draw_mouth() -> void:
	if _mouth_blood == _mouth_drawn:
		return
	_mouth_drawn = _mouth_blood
	if not _mouth_blood:
		if _mouth_mesh:
			_mouth_mesh.multimesh.visible_instance_count = 0
		return
	var head := model.part_node(Vitals.HEAD)
	if head == null:
		return
	if _mouth_mesh == null or not is_instance_valid(_mouth_mesh):
		_mouth_mesh = BodyDevices.multimesh_instance(32)
		_mouth_mesh.name = "MouthBlood"
		_mouth_mesh.layers = model.render_layers
		head.add_child(_mouth_mesh, true)
	var pivot := BodyVolume.pivot_at(Vitals.HEAD, body)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cells: Array = []
	for i in 6:  # across the lips
		var x := pivot.x + (i - 2.5) * CELL
		cells.append(Vector3(x, pivot.y + 0.1 + (CELL if i % 2 == 0 else 0.0), 0.0))
	for side: float in [-1.0, 1.0]:  # from the corners down the chin
		var x := pivot.x + side * 0.028
		for i in (8 if side > 0 else 5):
			cells.append(Vector3(x + rng.randf_range(-0.003, 0.003), pivot.y + 0.1 - i * CELL, 0.0))
	var mm := _mouth_mesh.multimesh
	var n := 0
	for c: Vector3 in cells:
		var s: Variant = BodyVolume.surface(Vitals.FACE, Vector3(c.x, c.y, pivot.z), Vector3.FORWARD, 0.2, body)
		if not s is Vector3 or n >= mm.instance_count:
			continue
		var p: Vector3 = Vector3(s) + Vector3.FORWARD * 0.002 - pivot
		mm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(CELL, CELL, CELL * 1.2)), p))
		mm.set_instance_color(n, MOUTH_BLOOD[rng.randi() % MOUTH_BLOOD.size()])
		n += 1
	mm.visible_instance_count = n


## Shivering: the trunk, head and arms tremble a little, each out of step.
func _process(delta: float) -> void:
	_time += delta
	var i := 0
	for mesh: MeshInstance3D in body_meshes():
		if not _rest_positions.has(mesh):
			_rest_positions[mesh] = mesh.position
		var phase := _time * SHIVER_HZ * TAU + i * 1.7
		mesh.position = Vector3(_rest_positions[mesh]) + Vector3(sin(phase), sin(phase * 1.31 + 0.5), cos(phase * 0.87)) * SHIVER_M
		i += 1


func _still() -> void:
	for mesh: Variant in _rest_positions:
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).position = _rest_positions[mesh]
	_rest_positions.clear()
