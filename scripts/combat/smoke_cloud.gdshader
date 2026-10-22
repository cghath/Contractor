// A smoke cloud's boxes (SmokeCloud): one box per claimed cell of its grid, the voxel style.
// INSTANCE_CUSTOM.w is the cell's state: 0 still changing (.x its smoke at the step before, .y at
// this step; 1 = full), 1 settled in the cloud's body (`core`: before, now), 2 settled in its
// outer layer (`rim`), 3 gone; .z is its shade. Each box is as opaque as its cell's smoke over
// one cell (the optical depth SmokeCloud's sight checks use: sigma_cell at full), eased between
// the two steps by `blend`. Only front faces draw (one face per cell a view ray crosses); a full
// cell is opaque, so its depth pre-pass hides the boxes behind it. A cell with next to no smoke
// folds its box away.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_lambert, specular_disabled;

uniform vec3 tint : source_color = vec3(0.8, 0.82, 0.82);
uniform float blend = 1.0;
uniform float sigma_cell = 5.0;
uniform vec2 core = vec2(0.0);
uniform vec2 rim = vec2(0.0);

varying float v_alpha;
varying float v_shade;

void vertex() {
	vec2 smoke = INSTANCE_CUSTOM.xy;
	if (INSTANCE_CUSTOM.w > 2.5) {
		smoke = vec2(0.0);
	} else if (INSTANCE_CUSTOM.w > 1.5) {
		smoke = rim;
	} else if (INSTANCE_CUSTOM.w > 0.5) {
		smoke = core;
	}
	float rho = mix(smoke.x, smoke.y, clamp(blend, 0.0, 1.0));
	v_alpha = 1.0 - exp(-sigma_cell * max(rho, 0.0));
	v_shade = INSTANCE_CUSTOM.z;
	if (v_alpha < 0.02) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = tint * v_shade;
	ALPHA = v_alpha;
	ROUGHNESS = 1.0;
}
