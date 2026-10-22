// A zone's rivers, streams, lakes and ponds (ZoneWater): a translucent surface whose ripples
// are blocky (value noise on a ripple_m grid, the voxel look of the ground and the modules),
// carried downstream at the current's speed (UV.y is metres downstream, UV2.x the current in m/s;
// 0 in still water, where they only shimmer), darker and less see-through where it's deep (the
// scene's depth behind it), with a pale fringe where it meets the bank. Seen from above and below.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform vec3 shallow_colour : source_color = vec3(0.33, 0.43, 0.35);
uniform vec3 deep_colour : source_color = vec3(0.10, 0.19, 0.20);
uniform vec3 foam_colour : source_color = vec3(0.72, 0.74, 0.68);
uniform float deep_m = 2.2;
uniform float ripple_m = 0.5;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 w_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Blocky value noise: one value per cell, eased only a little between cells.
float block(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = smoothstep(0.35, 0.65, f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float speed = UV2.x;
	float flowing = step(0.001, speed);
	// Ripples across the water (world x) and along it (UV.y downstream), drifting with the current;
	// still water shimmers in place.
	vec2 p = vec2(w_pos.x, mix(w_pos.z, UV.y, flowing)) / ripple_m;
	vec2 drift = vec2(TIME * 0.05 * (1.0 - flowing), TIME * speed / ripple_m);
	float n1 = block(p - drift);
	float n2 = block(p * 0.37 + vec2(13.1, 7.7) - drift * 0.6 + vec2(-TIME * 0.03, TIME * 0.02));
	float e = 0.08;
	float nx = block(p + vec2(e, 0.0) - drift) - n1;
	float nz = block(p + vec2(0.0, e) - drift) - n1;
	NORMAL_MAP = normalize(vec3(-nx * 1.6 + (n2 - 0.5) * 0.3, -nz * 1.6, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	// How much water is behind this pixel (m), from the depth buffer.
	float scene = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
	behind.xyz /= behind.w;
	float thick = clamp(VERTEX.z - behind.z, 0.0, 50.0);
	float deep = clamp(thick / deep_m, 0.0, 1.0);
	vec3 colour = mix(shallow_colour, deep_colour, deep) * (0.94 + 0.12 * n2);
	float foam = (1.0 - smoothstep(0.03, 0.22, thick)) * (0.55 + 0.45 * n1);
	ALBEDO = mix(colour, foam_colour, foam * 0.6);
	ALPHA = clamp(mix(0.55, 0.93, deep) + foam * 0.2, 0.0, 0.96);
	ROUGHNESS = 0.07 + 0.1 * n2;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
