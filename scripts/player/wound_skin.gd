class_name WoundSkin
extends RefCounted
## Wounds painted into the body's own 0.5 cm voxels (Captain, 2026-10-26: "i want the visible
## wounds to get better and blood to stop floating too"): each wounded part's mesh is drawn a
## second time ("WoundSkin", a child of the part's mesh, so it moves, poses, widens with the
## build and shivers with it) by a shader that recolours whole voxels and discards the rest. So
## nothing it draws can stand off the skin. Per wound spot (WoundMarks): the hole's dark core;
## round it torn cloth (pale frayed threads and blood) or, on bare skin, a raw red rim; the trail
## the blood ran down with gravity; and the soak, spreading through the cloth with the blood lost
## there (no cap: a big bleed soaks on into the next part, Captain's call), wet red-black while it
## bleeds, drying brown over DRY_S once it stops. Bruises (armour stops and blunt injuries) go
## purple on bare skin only. Reduced gore: holes smaller, no torn flesh or cloth, shorter trails.
## Inside each cavity BodyDeform carved (the entry's channel, the blown-out exit) the walls show what
## the round hit (WoundMarks' TISSUE_*): torn muscle, bone shards where it broke a bone, a lung, the
## heart, the brain, the bowel. Nothing is laid on top of the body (Captain, 2026-10-27: wounds
## "must not add voxels on top of the character model").
## Drawn within RANGE_M of the view (the Captain's calls: 40 m, then out to 80 m on the part's far
## stand-in mesh, VoxelArt's "LodFar", past the fine mesh's range).
##
## Spots and bruises are in the rest pose (BodyMap's frame), shared by every part, so a soak or a
## trail that runs past its own part goes onto the next part's mesh too.

const RANGE_M := 80.0
## How far round the path a cavity's walls are (m): an entry's channel, an exit's blown-out crater.
const CAVITY_ENTRY_M := 0.015
const CAVITY_EXIT_M := 0.03
## Organ tissue shows this far in along the path (m), past the muscle.
const ORGAN_FROM_M := 0.03
const MAX_SPOTS := 12
const MAX_BRUISES := 6
## How long a stopped bleed takes to dry from wet red-black to brown.
const DRY_S := 300.0
## Soak reach (m) for the blood lost at a spot (L): a graze's few mL a palm, a litre most of a
## trouser leg (it runs further down than across: STRETCH_DOWN, see the shader).
const SOAK_BASE_M := 0.015
const SOAK_PER_L := 0.22
const SOAK_POWER := 0.6
const STRETCH_DOWN := 1.6
## Bare skin doesn't soak like cloth: blood on it runs, and pools only this much round the hole.
const SKIN_SOAK := 0.2
## The trail down the skin: TRAIL_BASE_M once it bleeds, longer with the blood lost.
const TRAIL_BASE_M := 0.04
const TRAIL_PER_L := 0.5
const TRAIL_MAX_M := 0.8
## A spot on the trunk soaks no further than this behind the hole's own plane (the back stays
## clean of a chest wound).
const BEHIND_M := 0.1
## Cloth wicking stops short at what doesn't soak it up: the belt, knee pads, boot tops (rest-pose
## heights). A soak reaches past one only BARRIER_PASS as far.
const BARRIERS := [1.0, 0.465, 0.4, 0.17]
const BARRIER_PASS := 0.35
## Reduced gore: holes this much smaller, trails this much shorter.
const REDUCED_HOLE := 0.7
const REDUCED_TRAIL := 0.6

const SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, shadows_disabled;

uniform vec3 skin;
uniform vec3 skin_shade;
uniform float seed = 0.0;
uniform float torn = 1.0;
uniform float bare = 0.0;  // 1 on the head: lips, stubble and all take blood as skin does
uniform int spot_count = 0;
// Per spot, in this mesh's own units (sub-voxels): centre and the hole's core radius (0: no
// hole on this mesh); the way down and the soak's reach; the skin's outward and how far behind
// it the soak goes; the trail's length, wetness (1 wet .. 0 dried), exit (1) and a salt.
uniform vec4 spot_a[12];
uniform vec4 spot_b[12];
uniform vec4 spot_n[12];
uniform vec4 spot_c[12];
// The cavity: the way in along the round's path and how deep it goes; what's inside (tissue),
// where along the path a broken bone is (< 0: none) and the cavity's radius.
uniform vec4 spot_i[12];
uniform vec4 spot_j[12];
uniform float unit = 200.0;  // mesh units a metre
uniform int barrier_count = 0;
uniform float barrier_y[4];  // heights in this mesh's units (BARRIERS)
uniform int bruise_count = 0;
// Per bruise: centre and radius; strength and age (0 fresh .. 1 old).
uniform vec4 bruise_a[6];
uniform vec4 bruise_b[6];

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	VERTEX += NORMAL * 0.02;  // a hair over the part's own faces (0.1 mm): never under them
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

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 cell = floor(local_pos - local_normal * 0.5);  // one colour per voxel
	vec3 p = cell + 0.5;
	vec3 base = COLOR.rgb;  // the palette's own colours (as BodyCondition reads them)
	bool is_skin = bare > 0.5 || distance(base, skin) < 0.012 || distance(base, skin_shade) < 0.012;
	float speck = hash(cell);
	int mark = 0;  // 1 soak, 2 trail, 3 torn, 4 core
	float soak = 0.0;
	float wet = 0.0;
	// Inside a cavity: what the round tore through, at the depth it's at.
	bool in_cavity = false;
	vec3 inside = vec3(0.0);
	for (int i = 0; i < spot_count && !in_cavity; i++) {
		vec4 ci = spot_i[i];
		vec4 cj = spot_j[i];
		if (cj.z <= 0.0) {
			continue;
		}
		vec3 v = p - spot_a[i].xyz;
		float t = dot(v, ci.xyz);
		float lateral = length(v - ci.xyz * t);
		if (t < 0.8 || t > ci.w - 1.0 || lateral > cj.z * (1.0 - 0.3 * clamp(t / max(ci.w, 0.001), 0.0, 1.0)) + 1.2) {
			continue;
		}
		float streak = fract(dot(p, vec3(0.17, 0.61, 0.23)) * 0.5);
		if (torn <= 0.0) {
			inside = vec3(0.25, 0.04, 0.035) * (0.85 + speck * 0.3);  // reduced gore: dark, nothing shown
		} else if (cj.y >= 0.0 && abs(t - cj.y) < 0.015 * unit && speck < 0.5) {
			inside = speck < 0.25 ? vec3(0.90, 0.87, 0.78) : vec3(0.74, 0.69, 0.58);  // bone shards
		} else if (cj.x > 0.5 && t > ORGAN_FROM * unit) {
			int tissue = int(cj.x + 0.5);
			if (tissue == 1) {
				inside = speck < 0.5 ? vec3(0.80, 0.47, 0.47) : vec3(0.58, 0.24, 0.26);  // lung
			} else if (tissue == 2) {
				inside = speck < 0.5 ? vec3(0.42, 0.06, 0.06) : vec3(0.30, 0.03, 0.04);  // heart
			} else if (tissue == 3) {
				inside = speck < 0.5 ? vec3(0.83, 0.62, 0.55) : vec3(0.68, 0.44, 0.40);  // bowel
			} else if (tissue == 4) {
				inside = speck < 0.5 ? vec3(0.74, 0.60, 0.58) : vec3(0.56, 0.43, 0.43);  // brain
			} else {
				inside = vec3(0.22, 0.03, 0.03) * (0.85 + speck * 0.3);  // clotted round a torn vessel
			}
		} else {
			inside = streak < 0.5 ? vec3(0.55, 0.10, 0.09) : vec3(0.33, 0.04, 0.04);  // torn muscle
		}
		in_cavity = true;
	}
	if (in_cavity) {
		ALBEDO = to_linear(inside * (0.9 + 0.2 * hash(cell + 3.0)));
		ROUGHNESS = 0.45;
		SPECULAR = 0.35;
	} else {
	for (int i = 0; i < spot_count; i++) {
		vec4 a = spot_a[i];
		vec4 b = spot_b[i];
		vec4 n = spot_n[i];
		vec4 c = spot_c[i];
		vec3 v = p - a.xyz;
		float d = length(v);
		float jitter = hash(cell + vec3(float(i) * 13.1));
		if (a.w > 0.0) {
			float core = a.w * (c.z > 0.5 ? 0.7 + 0.6 * jitter : 0.85 + 0.3 * jitter);  // an exit's ragged
			if (d < core) {
				mark = 4;
				wet = max(wet, c.y);
				break;
			}
			if (torn > 0.0 && d < a.w + (c.z > 0.5 ? 2.5 : 1.6) + jitter * 1.2) {
				mark = max(mark, 3);
				wet = max(wet, c.y);
				continue;
			}
		}
		if (dot(v, n.xyz) < -n.w) {
			continue;  // behind the hole's plane (the far side of the trunk)
		}
		float along = dot(v, b.xyz);
		vec3 lat = v - b.xyz * along;
		float lateral = length(lat);
		// The trail: down from the hole, narrowing, a little wavy.
		float width = 1.6 + 1.2 * (1.0 - clamp(along / max(c.x, 0.001), 0.0, 1.0)) + jitter * 0.8;
		float wiggle = (value_noise(p * 0.25 + c.w) - 0.5) * 2.0;
		if (along > 0.0 && along < c.x * (0.85 + 0.3 * value_noise(p * 0.5 + c.w)) && abs(lateral + wiggle) < width * (is_skin ? 0.7 : 1.0)) {
			mark = max(mark, 2);
			soak = 1.0;
			wet = max(wet, c.y);
			continue;
		}
		// On bare skin it runs in thin streams either side too, shorter.
		if (is_skin && along > 0.0 && along < c.x * (0.45 + 0.3 * value_noise(p * 0.7 + c.w + 5.0)) && abs(lateral - 3.5 + wiggle * 0.6) < 0.9) {
			mark = max(mark, 2);
			soak = 1.0;
			wet = max(wet, c.y);
			continue;
		}
		// The soak: further down than across, its edge ragged.
		float s = along > 0.0 ? along / STRETCH : along / 0.45;
		float de = sqrt(lateral * lateral + s * s);
		// Cloth wicks: fast near the hole, the wet edge ragged and slower further out; it stops
		// short at the belt, knee pads and boot tops.
		float reach = b.w * (is_skin ? SKIN_SOAK : 1.0) * (0.72 + 0.56 * value_noise(p * 0.3 + c.w));
		for (int k = 0; k < barrier_count; k++) {
			if ((p.y - barrier_y[k]) * (a.y - barrier_y[k]) < 0.0) {
				reach *= BARRIER_PASS;
			}
		}
		if (de < reach) {
			mark = max(mark, 1);
			soak = max(soak, 1.0 - de / reach);
			wet = max(wet, c.y);
		}
	}
	vec3 col = base;
	if (mark == 4) {
		col = vec3(0.10, 0.02, 0.015) * (0.8 + speck * 0.4);
	} else if (mark == 3) {
		if (is_skin) {
			col = speck < 0.5 ? vec3(0.42, 0.08, 0.06) : vec3(0.30, 0.05, 0.04);  // raw at the edge
		} else if (speck < 0.45) {
			col = min(base * 1.3 + vec3(0.09, 0.08, 0.06), vec3(0.85));  // frayed threads
		} else {
			col = mix(vec3(0.20, 0.08, 0.05), vec3(0.24, 0.035, 0.025), wet);
		}
	} else if (mark > 0) {
		// Darkest where it's soaked through (near the hole, the low side), lighter at the wet edge.
		float k = mark == 2 ? 0.9 : 0.35 + 0.6 * smoothstep(0.0, 0.7, soak);
		vec3 blood = is_skin ? mix(vec3(0.27, 0.07, 0.045), vec3(0.47, 0.06, 0.05), wet)
			: mix(vec3(0.22, 0.11, 0.07), vec3(0.27, 0.035, 0.03), wet);  // dried brown .. wet maroon
		col = mix(base, blood, k) * (0.94 + speck * 0.12);
	} else if (is_skin) {
		float bruise = 0.0;
		float age = 0.0;
		for (int i = 0; i < bruise_count; i++) {
			float d = length(p - bruise_a[i].xyz) / max(bruise_a[i].w, 0.001);
			float e = (1.0 - d * (0.8 + 0.4 * value_noise(p * 0.4 + float(i)))) * bruise_b[i].x;
			if (e > bruise) {
				bruise = e;
				age = bruise_b[i].y;
			}
		}
		if (bruise <= 0.0) {
			discard;
		}
		// Darker, redder skin; a little blue-grey as it ages (Captain, 2026-10-27: "too purple").
		vec3 tint = mix(base * vec3(0.72, 0.52, 0.50), base * vec3(0.62, 0.55, 0.60), age);
		col = mix(base, tint, clamp(bruise * 1.2, 0.0, 0.6));
	} else {
		discard;
	}
	ALBEDO = to_linear(col);
	ROUGHNESS = mark == 0 ? 0.85 : mix(0.85, 0.55, wet);  // wet blood shines a little
	SPECULAR = 0.35;
	}
}
"""

var model: CharacterModel
var body := ""
var _materials: Dictionary = {}  # bone -> ShaderMaterial
var _drawn: Dictionary = {}  # bone (or a face part's mesh) -> its WoundSkin MeshInstance3D
var _wanted: Dictionary = {}  # bone -> true: painted, or to be once it has a mesh again
static var _shader: Shader


func _init(p_model: CharacterModel, p_body: String) -> void:
	model = p_model
	body = p_body


## The parts a bone carries: one per bone, the one whose pivot and box stand for it.
const BONE_PARTS: Array[StringName] = [&"head", &"chest", &"upper_arm_l", &"upper_arm_r", &"forearm_l", &"forearm_r",
	&"thigh_l", &"thigh_r", &"shin_l", &"shin_r"]


## Which bones a spot on each bone can soak or run on to: its own and those joined to it (a left
## thigh's blood never crosses to the right leg).
const JOINED := {
	&"head": [&"chest"],
	&"chest": [&"head", &"upper_arm_l", &"upper_arm_r", &"thigh_l", &"thigh_r"],
	&"upper_arm_l": [&"chest", &"forearm_l"], &"upper_arm_r": [&"chest", &"forearm_r"],
	&"forearm_l": [&"upper_arm_l"], &"forearm_r": [&"upper_arm_r"],
	&"thigh_l": [&"chest", &"shin_l"], &"thigh_r": [&"chest", &"shin_r"],
	&"shin_l": [&"thigh_l"], &"shin_r": [&"thigh_r"],
}


## The bone part (BONE_PARTS) body part `part` is drawn on.
static func bone_part(part: StringName) -> StringName:
	match BodyMap.segment_of(part):
		&"torso":
			return &"chest"
		&"head":
			return &"head"
	return part


## Where each bone's mesh is in the rest pose (its part's box, the whole segment for the trunk
## and the head), for which spots reach it.
static func rest_box(part: StringName) -> AABB:
	var box: Array = BodyMap.SEGMENTS[BodyMap.segment_of(part)] if BodyMap.SEGMENTS.has(BodyMap.segment_of(part)) else BodyMap.PART_BOXES[part][0]
	return AABB(Vector3(box[0]) - Vector3(box[1]) * 0.5, Vector3(box[1]))


## How far a spot's paint can reach from its centre (m).
static func reach_of(spot: Dictionary) -> float:
	return maxf(maxf(float(spot.core) * 2.0 + 0.015, float(spot.soak) * STRETCH_DOWN), float(spot.trail) + 0.03)


## Paints `spots` and `bruises` (rest pose, see WoundMarks._skin_spots) on every part they reach;
## a part with none loses its paint. `full` is the gore level (false: reduced).
func paint(spots: Array, bruises: Array, full: bool) -> void:
	if not is_instance_valid(model):
		return
	for part: StringName in BONE_PARTS:
		var bone := model.part_node(part)
		if bone == null:
			continue
		var box := rest_box(part).grow(0.01)
		var mine: Array = []
		for s: Dictionary in spots:
			var own := bone_part(StringName(s.part))
			if own != part and part not in JOINED.get(own, []):
				continue
			var reach := reach_of(s)
			if own == part or box.grow(reach).has_point(s.at):
				mine.append(s)
		# Its own holes first, then the biggest soaks from elsewhere.
		mine.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ah := box.has_point(a.at)
			var bh := box.has_point(b.at)
			return ah and not bh if ah != bh else float(a.soak) > float(b.soak))
		mine.resize(mini(mine.size(), MAX_SPOTS))
		var near: Array = bruises.filter(func(b: Dictionary) -> bool: return box.grow(float(b.r)).has_point(b.at))
		near.resize(mini(near.size(), MAX_BRUISES))
		_paint_bone(part, bone, mine, near, full)


## The part's own mesh on `bone` (its first MeshInstance3D), or null.
static func mesh_of(bone: Node3D) -> MeshInstance3D:
	for child: Node in bone.get_children():
		if child is MeshInstance3D:
			return child
	return null


## The rest-pose (unwidened) transform of a part's mesh on its bone (CharacterModel._apply_girth
## keeps it in the "base" meta).
static func base_of(mi: MeshInstance3D) -> Transform3D:
	if mi.has_meta(&"base"):
		var base: Array = mi.get_meta(&"base")
		return Transform3D(Basis.from_scale(base[1]), base[0])
	return mi.transform


func _paint_bone(part: StringName, bone: Node3D, spots: Array, bruises: Array, full: bool) -> void:
	if spots.is_empty() and bruises.is_empty():
		_wanted.erase(bone)
	else:
		_wanted[bone] = true
	var mi := mesh_of(bone)
	if mi == null or mi.mesh == null:
		_hide(bone)
		return
	var to_mesh := base_of(mi).affine_inverse()
	_paint_mesh(bone, mi, to_mesh, part, spots, bruises, full)
	# Past the fine mesh's range, its 1 cm stand-in (VoxelArt "LodFar") painted the same.
	var far := bone.get_node_or_null(^"LodFar") as MeshInstance3D
	if far and far.mesh:
		_paint_mesh(far, far, far.transform.affine_inverse(), part, spots, bruises, full)
	# The face's moving parts (FaceRig: lips, brows, eyelids) on the head's mesh: blood runs on
	# over them as over the rest of the face.
	for face: Node in mi.get_children():
		if face is MeshInstance3D and String(face.name).begins_with("Face_") and (face as MeshInstance3D).mesh:
			var f := face as MeshInstance3D
			_paint_mesh(f, f, f.transform.affine_inverse() * to_mesh, part, spots, bruises, full)


func _hide(key: Node3D) -> void:
	var skin := _skin_of(key)
	if skin and is_instance_valid(skin):
		skin.visible = false


## Paints `spots` and `bruises` on mesh `mi` (its skin kept under `key`), `to_mesh` taking a point
## in its part's bone space (rest pose, less the pivot) into the mesh's own.
func _paint_mesh(key: Node3D, mi: MeshInstance3D, to_mesh: Transform3D, part: StringName, spots: Array, bruises: Array, full: bool) -> void:
	var skin := _skin_of(key)
	if spots.is_empty() and bruises.is_empty():
		_hide(key)
		return
	if skin == null or not is_instance_valid(skin) or skin.get_parent() != mi:
		if skin and is_instance_valid(skin):
			skin.queue_free()
		skin = MeshInstance3D.new()
		skin.name = "WoundSkin"
		skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(skin)
		_drawn[key] = skin
	skin.visible = true
	_sync(skin, mi)
	var material: ShaderMaterial = _materials.get(key)
	if material == null:
		material = _new_material(key)
		_materials[key] = material
	skin.material_override = material
	var unit := 1.0 / to_mesh.basis.inverse().get_scale().x  # mesh units a metre
	var pivot := BodyVolume.pivot_at(part, body)
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var n := PackedVector4Array()
	var c := PackedVector4Array()
	var ci := PackedVector4Array()
	var cj := PackedVector4Array()
	for s: Dictionary in spots:
		var at: Vector3 = to_mesh * (Vector3(s.at) - pivot)
		var down: Vector3 = (to_mesh.basis * Vector3(s.down)).normalized()
		var out: Vector3 = (to_mesh.basis * Vector3(s.n)).normalized()
		var hole := float(s.core) * (1.0 if full else REDUCED_HOLE)
		var trail := float(s.trail) * (1.0 if full else REDUCED_TRAIL)
		var behind := BEHIND_M if BodyMap.segment_of(StringName(s.part)) != StringName(s.part) else 1.0
		a.append(Vector4(at.x, at.y, at.z, hole * unit))
		b.append(Vector4(down.x, down.y, down.z, float(s.soak) * unit))
		n.append(Vector4(out.x, out.y, out.z, behind * unit))
		c.append(Vector4(trail * unit, float(s.wet), 1.0 if s.exit else 0.0, float(s.salt)))
		var inside: Dictionary = s.get("inside", {})
		if inside.is_empty() or bone_part(StringName(s.part)) != part:
			ci.append(Vector4.ZERO)
			cj.append(Vector4.ZERO)  # (a cavity only in its own part)
		else:
			var way: Vector3 = (to_mesh.basis * Vector3(inside.way)).normalized()
			ci.append(Vector4(way.x, way.y, way.z, float(inside.deep) * unit))
			var bone_t := float(inside.bone_t)
			cj.append(Vector4(float(inside.tissue), bone_t * unit if bone_t >= 0.0 else -1.0, (CAVITY_EXIT_M if s.exit else CAVITY_ENTRY_M) * unit, 0.0))
	while a.size() < MAX_SPOTS:
		for arr: PackedVector4Array in [a, b, n, c, ci, cj]:
			arr.append(Vector4.ZERO)
	var ba := PackedVector4Array()
	var bb := PackedVector4Array()
	for br: Dictionary in bruises:
		var at: Vector3 = to_mesh * (Vector3(br.at) - pivot)
		ba.append(Vector4(at.x, at.y, at.z, float(br.r) * unit))
		bb.append(Vector4(float(br.s), float(br.age), 0.0, 0.0))
	while ba.size() < MAX_BRUISES:
		ba.append(Vector4.ZERO)
		bb.append(Vector4.ZERO)
	material.set_shader_parameter(&"spot_count", spots.size())
	material.set_shader_parameter(&"spot_a", a)
	material.set_shader_parameter(&"spot_b", b)
	material.set_shader_parameter(&"spot_n", n)
	material.set_shader_parameter(&"spot_c", c)
	material.set_shader_parameter(&"spot_i", ci)
	material.set_shader_parameter(&"spot_j", cj)
	material.set_shader_parameter(&"unit", unit)
	material.set_shader_parameter(&"bruise_count", bruises.size())
	material.set_shader_parameter(&"bruise_a", ba)
	material.set_shader_parameter(&"bruise_b", bb)
	material.set_shader_parameter(&"torn", 1.0 if full else 0.0)
	material.set_shader_parameter(&"bare", 1.0 if part == &"head" else 0.0)
	var barriers := PackedFloat32Array()
	for y: float in BARRIERS:
		barriers.append((to_mesh * (Vector3(0.0, y, 0.0) - Vector3(0.0, pivot.y, 0.0))).y if part != &"head" else -1e6)
	material.set_shader_parameter(&"barrier_count", barriers.size())
	material.set_shader_parameter(&"barrier_y", barriers)


## Keeps a painted skin on its part's mesh as drawn now: the hand's pose swapped in, a carved
## part's own mesh (BodyDeform), the near/far LOD range. True when a part's mesh was rebuilt
## under its paint (the head's when a helmet tucks the hair, FaceRig): it wants painting again.
func sync() -> bool:
	var again := false
	for bone: Variant in _wanted.keys():
		if not is_instance_valid(bone):
			_wanted.erase(bone)
			continue
		var mi := mesh_of(bone)
		var skin := _skin_of(bone)
		if mi != null and mi.mesh != null and (skin == null or not is_instance_valid(skin) or skin.get_parent() != mi):
			again = true
	for key: Variant in _drawn.keys():
		var skin := _skin_of(key)
		if not is_instance_valid(key) or skin == null:
			_drawn.erase(key)
			_materials.erase(key)
			continue
		var mi: MeshInstance3D = key if key is MeshInstance3D else mesh_of(key)
		if mi != null and skin.get_parent() == mi:
			_sync(skin, mi)
	return again


static func _sync(skin: MeshInstance3D, mi: MeshInstance3D) -> void:
	if skin.mesh != mi.mesh:
		skin.mesh = mi.mesh
	skin.layers = mi.layers
	var end := RANGE_M if mi.visibility_range_end <= 0.0 else minf(RANGE_M, mi.visibility_range_end)
	if skin.visibility_range_end != end:
		skin.visibility_range_end = end
	if skin.visibility_range_begin != mi.visibility_range_begin:
		skin.visibility_range_begin = mi.visibility_range_begin  # (the far stand-in's paint starts where it does)


## The painted skins now (tests): bone -> MeshInstance3D, visible ones only.
func drawn() -> Dictionary:
	var out := {}
	for bone: Variant in _drawn:
		var skin := _skin_of(bone)
		if is_instance_valid(bone) and skin != null and skin.visible:
			out[bone] = skin
	return out


## The skin painted for `key` (a bone, a face part's or far stand-in's mesh), or null (none, or
## freed with the mesh it was on: a far stand-in dropped when its part was carved).
func _skin_of(key: Variant) -> MeshInstance3D:
	var skin: Variant = _drawn.get(key)
	return skin if is_instance_valid(skin) else null


func material_of(bone: Node3D) -> ShaderMaterial:
	return _materials.get(bone)


func clear() -> void:
	for skin: Variant in _drawn.values():
		if is_instance_valid(skin):
			(skin as MeshInstance3D).visible = false


func _new_material(bone: Node3D) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER.replace("STRETCH", "%.2f" % STRETCH_DOWN).replace("SKIN_SOAK", "%.2f" % SKIN_SOAK).replace("BARRIER_PASS", "%.2f" % BARRIER_PASS) 			.replace("ORGAN_FROM", "%.3f" % ORGAN_FROM_M)
	var material := ShaderMaterial.new()
	material.shader = _shader
	var scheme := model.variant  # the scheme it was built in: its part's, a face's own palette (BodyCondition.scheme_of)
	var n: Node = bone
	while n != null and n != model:
		if n.has_meta(&"voxel_variant"):
			scheme = String(n.get_meta(&"voxel_variant"))
			break
		n = n.get_parent()
	var spec := VoxelArt.spec(scheme)
	var skin := Color(spec.get("skin", "c8996f"))
	material.set_shader_parameter(&"skin", Vector3(skin.r, skin.g, skin.b))
	var shade := skin.darkened(0.15)
	material.set_shader_parameter(&"skin_shade", Vector3(shade.r, shade.g, shade.b))
	material.set_shader_parameter(&"seed", float(hash(model.get_parent().name if model.get_parent() else model.name) % 1000) / 37.0)
	return material
