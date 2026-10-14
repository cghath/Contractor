// The zone ground (ZoneTerrain): the per-vertex palette colour (grass/dry/earth/rock/sand/road,
// one every 4 m) broken up in world space so it stops reading as big smooth blobs:
// - macro patches (~120 m) and mid patches (~14 m) of the preset's dry colour and brightness,
// - fine grain (~1 m, ~0.2 m) near the camera (faded out by detail_end_m), part-faceted normals,
// - rock on steep faces picked per pixel (with layered bands), not only per vertex.
// All procedural (value noise): no textures to load, a handful of ALU ops per pixel.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 dry_colour : source_color = vec3(0.49, 0.47, 0.28);
uniform vec3 rock_colour : source_color = vec3(0.44, 0.42, 0.38);
uniform vec3 earth_colour : source_color = vec3(0.50, 0.43, 0.31);
uniform float seed_offset = 0.0;
uniform float macro_strength = 1.0;
uniform float detail_end_m = 140.0;
uniform float facet_share = 0.4;

varying vec3 w_pos;
varying vec3 w_nrm;

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
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = w_pos.xz + vec2(seed_offset, seed_offset * 0.37);
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(detail_end_m * 0.5, detail_end_m, dist);

	vec3 base = to_linear(COLOR.rgb);
	// Macro and mid patches: two octaves each, rotated so the grid never lines up.
	vec2 q = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p;
	float macro = vnoise(p / 130.0) * 0.6 + vnoise(q / 55.0) * 0.4;
	float mid = vnoise(q / 14.0) * 0.65 + vnoise(p / 6.0) * 0.35;
	float fine = vnoise(p * 1.1) * 0.6 + vnoise(q * 3.3) * 0.4;

	float close = 1.0 - smoothstep(18.0, 45.0, dist);
	float grain = vnoise(p * 4.3) * 0.5 + vnoise(q * 9.7) * 0.5;

	vec3 col = base;
	// Dry patches, darker gravel/earth patches across the macro and mid noise.
	col = mix(col, dry_colour, smoothstep(0.45, 0.85, macro) * 0.45 * macro_strength);
	col = mix(col, earth_colour * 0.85, smoothstep(0.30, 0.05, macro) * 0.55 * macro_strength);
	col = mix(col, earth_colour, smoothstep(0.58, 0.88, mid) * 0.45);
	col *= mix(0.74, 1.14, macro) * mix(0.86, 1.08, mid);
	col *= mix(1.0, mix(0.80, 1.12, fine), near);
	col *= mix(1.0, mix(0.84, 1.10, grain), close);

	// Rock on steep faces, per pixel, with horizontal strata.
	float slope = 1.0 - clamp(w_nrm.y, 0.0, 1.0);
	float rock = smoothstep(0.20, 0.34, slope + (mid - 0.5) * 0.12);
	float strata = vnoise(vec2(w_pos.y * 1.7, p.x * 0.02 + p.y * 0.02));
	vec3 rock_col = rock_colour * mix(0.78, 1.15, strata) * mix(0.92, 1.06, fine);
	col = mix(col, rock_col, rock);

	ALBEDO = col;
	ROUGHNESS = mix(0.97, 0.85, rock);
	SPECULAR = 0.25;

	// Facets: a share of each triangle's own flat normal over the smooth one, so the ground
	// reads low-poly like the soldiers and scatter, and slopes pick up light and shade.
	// (Noise-gradient normal detail was tried: it streaked at grazing angles.)
	vec3 facet = normalize(cross(dFdy(w_pos), dFdx(w_pos)));
	if (facet.y < 0.0) {
		facet = -facet;
	}
	vec3 n = normalize(mix(w_nrm, facet, facet_share));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
