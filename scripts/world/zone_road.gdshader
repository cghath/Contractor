// The roads (ZoneRoads): the vertex colour is the surface's (asphalt, the preset's dirt, concrete),
// UV is (across from the road's middle, m; along it, m), UV2 is (its half-width, m; what it is:
// 0 asphalt with markings, 1 dirt, 2 concrete, 3 plain asphalt, 4 an island's grass, 5 paint).
// Near the camera it's drawn in the ground's block style (0.25 m blocks, each its own shade), so it
// matches the terrain and the voxel buildings; markings are worn, dirt has ruts and a grassy crown.
// All procedural: no textures.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float seed_offset = 0.0;
uniform vec3 verge_colour : source_color = vec3(0.42, 0.42, 0.26);
uniform vec3 line_colour : source_color = vec3(0.86, 0.85, 0.80);
uniform float dash_m = 12.0;
uniform float dash_share = 0.45;

varying vec3 w_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz + vec2(seed_offset, seed_offset * 0.37);
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(60.0, 120.0, dist);
	int look = int(round(UV2.y));
	float hw = UV2.x;
	float u = UV.x;
	float v = UV.y;
	vec3 col = to_linear(COLOR.rgb);
	float wear = vnoise(p / 7.0) * 0.6 + vnoise(p / 1.7) * 0.4;
	float rough = 0.92;

	if (look == 0 || look == 3) {
		// Asphalt: repaired patches, the wheel tracks a touch darker and smoother.
		col *= mix(0.92, 1.07, vnoise(p / 11.0));
		col *= mix(1.0, 1.12, smoothstep(0.72, 0.78, vnoise(p / 5.3 + 4.0)) * 0.6);
		float lane = abs(abs(u) - hw * 0.5);
		float tracks = 1.0 - smoothstep(0.35, 0.75, abs(lane - 0.85));
		col *= mix(1.0, 0.9, tracks * 0.6);
		rough = mix(0.9, 0.78, tracks * 0.5);
		if (look == 0) {
			// Markings: a dashed centre line and solid edge lines, worn in places.
			float centre = (1.0 - smoothstep(0.06, 0.09, abs(u))) * step(fract(v / dash_m), dash_share);
			float edge = 1.0 - smoothstep(0.06, 0.09, abs(abs(u) - (hw - 0.35)));
			float paint = max(centre, edge) * smoothstep(0.18, 0.45, wear) * step(abs(u), hw);
			col = mix(col, line_colour * mix(0.8, 1.0, wear), paint * 0.85);
			rough = mix(rough, 0.6, paint);
		}
		// The verge: the last half-metre and the skirt go dusty toward the ground.
		col = mix(col, verge_colour * 0.8, smoothstep(hw - 0.1, hw + 0.4, abs(u)) * 0.6);
	} else if (look == 1) {
		// Dirt: two ruts, a grassy crown between them, the edges fraying into the verge.
		float ruts = 1.0 - smoothstep(0.25, 0.55, abs(abs(u) - 0.9));
		col *= mix(1.0, 0.82, ruts);
		float crown = (1.0 - smoothstep(0.15, 0.45, abs(u))) * smoothstep(0.35, 0.65, vnoise(p / 2.3));
		col = mix(col, verge_colour, crown * 0.55);
		float fray = smoothstep(hw - 0.9 + vnoise(p / 1.3) * 0.6, hw + 0.3, abs(u));
		col = mix(col, verge_colour, fray * 0.75);
		col *= mix(0.9, 1.08, vnoise(p / 6.0));
		rough = 1.0;
	} else if (look == 2) {
		// Concrete: slabs with darker joints, stained.
		vec2 slab = fract(w_pos.xz / 1.2);
		float joint = max(1.0 - smoothstep(0.0, 0.03, min(slab.x, 1.0 - slab.x)), 1.0 - smoothstep(0.0, 0.03, min(slab.y, 1.0 - slab.y)));
		col *= mix(1.0, 0.78, joint * near);
		col *= mix(0.9, 1.05, wear);
		rough = 0.88;
	} else if (look == 4) {
		// An island's grass.
		col *= mix(0.82, 1.1, vnoise(p * 1.7)) * mix(0.9, 1.05, wear);
		rough = 1.0;
	} else {
		// Paint (a mini roundabout's dome).
		col *= mix(0.85, 1.0, wear);
		rough = 0.65;
	}

	// The ground's block style near the camera: each 0.25 m block its own shade, and stones.
	vec2 bid = floor(p / 0.25);
	col *= mix(1.0, 1.0 + (hash12(bid + seed_offset) - 0.5) * 0.1, near);
	float speck_near = 1.0 - smoothstep(14.0, 26.0, dist);
	if (speck_near > 0.0) {
		vec2 sg = floor(p / 0.1);
		float sp = step(0.95, hash12(sg + seed_offset + 3.0));
		col *= mix(1.0, mix(0.75, 1.2, hash12(sg + 41.0)), sp * speck_near * 0.6);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
