class_name BloodStain
extends MeshInstance3D
## Blood that landed on something (Captain, 2026-10-26: blood dripping onto helmets and
## backpacks should "stain those items" rather than "float in the air/stay stacked" on them):
## the thing's own mesh drawn a second time, a child of it, recolouring the voxels where drops
## fell and discarding the rest, so a stain sits in the item's surface, moves with it and can
## never stack up or hang off it. A drop stains the faces that look up the way it fell, in a
## short column under where it met the thing's collider (a collider's box stands off the mesh;
## the column finds the surface under it). Wet red, drying brown over WoundSkin.DRY_S; each
## stain goes after LIFE_S. One per mesh, shared by everyone who bleeds on it; MAX entries, a
## drop near an old one widening it instead.

const MAX := 12
const LIFE_S := 420.0
const GRAIN_M := 0.005  # stains keep to 0.5 cm voxels on any mesh
const RADIUS_M := 0.012
const MAX_RADIUS_M := 0.05
const DEPTH_M := 0.08  # how far under the hit point the column looks for the surface
const MERGE_M := 0.02

const SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, shadows_disabled;

uniform float grain = 1.0;  // mesh units in a 0.5 cm voxel
uniform int count = 0;
// Per stain, in this mesh's units: where the drop met it and its radius; the way it fell and
// the column's depth; wetness (1 wet .. 0 dry).
uniform vec4 stain_a[12];
uniform vec4 stain_b[12];
uniform float stain_wet[12];

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	VERTEX += NORMAL * 0.0002 / max(length(MODEL_MATRIX[0].xyz), 0.0001);  // 0.2 mm over its faces
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 cell = floor((local_pos - local_normal * 0.25 * grain) / grain);
	vec3 p = (cell + 0.5) * grain;
	float best = 0.0;
	float wet = 0.0;
	for (int i = 0; i < count; i++) {
		vec3 down = stain_b[i].xyz;
		if (dot(normalize(local_normal), -down) < 0.25) {
			continue;  // only faces the drop fell onto
		}
		vec3 v = p - stain_a[i].xyz;
		float along = dot(v, down);
		if (along < -stain_b[i].w * 0.4 || along > stain_b[i].w) {
			continue;
		}
		float r = stain_a[i].w * (0.75 + 0.5 * hash(cell + float(i)));
		float lateral = length(v - down * along);
		if (lateral < r) {
			float k = 1.0 - lateral / r;
			if (k > best) {
				best = k;
				wet = stain_wet[i];
			}
		}
	}
	if (best <= 0.0) {
		discard;
	}
	vec3 base = COLOR.rgb;
	vec3 blood = mix(vec3(0.20, 0.09, 0.055), vec3(0.30, 0.03, 0.025), wet);
	vec3 col = mix(base, blood, 0.55 + 0.4 * smoothstep(0.0, 0.5, best)) * (0.93 + hash(cell) * 0.14);
	ALBEDO = to_linear(col);
	ROUGHNESS = mix(0.85, 0.55, wet);
	SPECULAR = 0.35;
}
"""

static var _shader: Shader
var _stains: Array[Dictionary] = []  # {"at", "down" (mesh-local), "r" (m), "made"}
var _material: ShaderMaterial


## The stain on mesh `target`, made the first time (null for a mesh that can't take one).
static func on(target: MeshInstance3D) -> BloodStain:
	if target == null or target.mesh == null or target is BloodStain:
		return null
	var stain := target.get_node_or_null(^"BloodStain") as BloodStain
	if stain == null:
		stain = BloodStain.new()
		stain.name = "BloodStain"
		target.add_child(stain)
		stain._setup(target)
	return stain


## The mesh under `holder` (itself or any mesh below it) nearest world point `at`, past none of
## the marks drawn on bodies; null if it has none within `reach`.
static func mesh_near(holder: Node, at: Vector3, reach := 0.25) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_d := reach
	var meshes: Array[Node] = holder.find_children("*", "MeshInstance3D", true, false)
	if holder is MeshInstance3D:
		meshes.append(holder)
	for node: Node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi is BloodStain or mi.name in [&"WoundSkin", &"LodFar"] \
				or mi.get_parent() is BloodStain or String(mi.get_parent().name) == "LodFar":
			continue
		var box := mi.global_transform * mi.get_aabb()
		var d := _distance_to_box(box, at)
		if d < best_d:
			best_d = d
			best = mi
	return best


static func _distance_to_box(box: AABB, p: Vector3) -> float:
	var q := p.clamp(box.position, box.end)
	return q.distance_to(p)


func _setup(target: MeshInstance3D) -> void:
	mesh = target.mesh
	layers = target.layers
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = WoundSkin.RANGE_M
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = _shader
	material_override = _material
	var timer := Timer.new()
	timer.wait_time = 10.0
	timer.autostart = true
	timer.timeout.connect(_refresh)
	add_child(timer)


## A drop that fell along world `fall` met this mesh's thing at world point `at`.
func add(at: Vector3, fall: Vector3, big := false) -> void:
	var parent := get_parent() as MeshInstance3D
	if parent == null:
		return
	if mesh != parent.mesh:
		mesh = parent.mesh  # (a carved part's own mesh since)
	var to_local := parent.global_transform.affine_inverse()
	var local: Vector3 = to_local * at
	var down: Vector3 = (to_local.basis * (fall.normalized() if fall.length() > 0.001 else Vector3.DOWN)).normalized()
	var radius := RADIUS_M * (1.6 if big else 1.0)
	for s: Dictionary in _stains:
		if (s.at as Vector3).distance_to(local) * _unit_m() < MERGE_M:
			s.r = minf(float(s.r) + radius * 0.35, MAX_RADIUS_M)
			s.made = WoundMarks._now()
			_refresh()
			return
	if _stains.size() >= MAX:
		_stains.pop_front()
	_stains.append({"at": local, "down": down, "r": radius, "made": WoundMarks._now()})
	_refresh()


## Stains on this mesh now (tests): [{"at" (world), "r" (m)}].
func stains() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parent := get_parent() as Node3D
	for s: Dictionary in _stains:
		out.append({"at": parent.global_transform * Vector3(s.at), "r": float(s.r)})
	return out


## Metres in one of the mesh's own units.
func _unit_m() -> float:
	var parent := get_parent() as Node3D
	return parent.global_basis.get_scale().x if parent else 1.0


func _refresh() -> void:
	var now := WoundMarks._now()
	_stains = _stains.filter(func(s: Dictionary) -> bool: return now - float(s.made) < LIFE_S)
	visible = not _stains.is_empty()
	var unit := 1.0 / maxf(_unit_m(), 0.000001)
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var wet := PackedFloat32Array()
	for s: Dictionary in _stains:
		var at: Vector3 = s.at
		var down: Vector3 = s.down
		a.append(Vector4(at.x, at.y, at.z, float(s.r) * unit))
		b.append(Vector4(down.x, down.y, down.z, DEPTH_M * unit))
		wet.append(clampf(1.0 - (now - float(s.made)) / WoundSkin.DRY_S, 0.0, 1.0))
	while a.size() < MAX:
		a.append(Vector4.ZERO)
		b.append(Vector4.ZERO)
		wet.append(0.0)
	_material.set_shader_parameter(&"grain", GRAIN_M * unit)
	_material.set_shader_parameter(&"count", _stains.size())
	_material.set_shader_parameter(&"stain_a", a)
	_material.set_shader_parameter(&"stain_b", b)
	_material.set_shader_parameter(&"stain_wet", wet)
