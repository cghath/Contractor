// The wild trees' broadleaf crowns and the grass by season, live (SeasonLive -> ZoneScatter
// .set_season_look; plans/fallen-seasons.md). Draws as the scatter's StandardMaterial does (the
// vertex colour times the instance colour, sRGB), then:
// - colour_mix pulls each instance toward one colour of the season's palette (picked by the
//   instance), keeping the mesh's own shading (its brightness over the preset's mean colour);
// - leaf (1 full, 0 bare) shrinks the crown toward pivot (the trunk's top) to min_scale and thins
//   it to a lattice of twigs in bare_colour (discard on a 12 cm world grid, steady as the camera
//   moves, so the far shapes don't shimmer); the grass's leaf flattens it toward the ground instead.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float colour_mix = 0.0;
uniform vec3 palette[5] : source_color;
uniform int palette_n = 1;
uniform vec3 preset_mean : source_color = vec3(0.27, 0.37, 0.18);
uniform float leaf = 1.0;
uniform vec3 pivot = vec3(0.0, 2.6, 0.0);
uniform float min_scale = 0.72;
uniform float thin = 1.0;  // 1: thin to twigs when bare (near crowns); 0: no discard (far blobs, grass)
uniform float bare_tint = 1.0;  // 1: bare goes to bare_colour (crowns, far blobs); 0: not (grass)
uniform vec3 bare_colour : source_color = vec3(0.36, 0.32, 0.27);

varying float v_pick;
varying vec3 v_world;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	float s = mix(min_scale, 1.0, clamp(leaf, 0.0, 1.0));
	VERTEX = pivot + (VERTEX - pivot) * s;
	v_pick = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float mean = max(dot(preset_mean, vec3(0.299, 0.587, 0.114)), 0.001);
	float shade = clamp(lum / mean, 0.4, 1.6);  // the mesh's side shading and the instance's own shade
	if (colour_mix > 0.0) {
		int k = clamp(int(v_pick * float(palette_n)), 0, 4);
		c = mix(c, palette[k] * shade, colour_mix);
	}
	if (leaf < 1.0) {
		// Bare: the crown goes to twig colour and, near, thins (a third of it left at leaf 0).
		float bare = 1.0 - leaf;
		c = mix(c, bare_colour * shade, bare * 0.85 * bare_tint);
		if (thin > 0.0 && hash13(floor(v_world / 0.12)) > mix(1.0, 0.34, bare)) {
			discard;
		}
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
