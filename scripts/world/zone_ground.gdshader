// The zone ground (ZoneTerrain): the per-vertex palette colour (grass/dry/earth/rock/sand/road,
// one every 4 m) broken up in world space so it stops reading as big smooth blobs:
// - macro patches (~120 m) and mid patches (~14 m) of the preset's dry colour and brightness,
// - fine grain (~1 m, ~0.2 m) near the camera (faded out by detail_end_m), part-faceted normals,
// - rock on steep faces picked per pixel (with layered bands), not only per vertex.
// All procedural (value noise): no textures to load, a handful of ALU ops per pixel.
// Salt pans (ZoneTerrain sets these from the preset's "ground"; 0 elsewhere, so other
// presets look as before. Captain, 2026-10-14: the salt flats were "an actual eye sore"):
// - damp_strength: large darker damp patches (~350 m and ~70 m),
// - crust_strength: the crust's polygons (~1.8 m, raised lighter rims) near the camera,
// - track_strength: a few long tyre tracks (two ruts each) across the pan, seen to ~320 m.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 dry_colour : source_color = vec3(0.49, 0.47, 0.28);
uniform vec3 rock_colour : source_color = vec3(0.44, 0.42, 0.38);
uniform vec3 earth_colour : source_color = vec3(0.50, 0.43, 0.31);
uniform float seed_offset = 0.0;
uniform float macro_strength = 1.0;
uniform float detail_end_m = 140.0;
uniform float facet_share = 0.4;
uniform float damp_strength = 0.0;
uniform float crust_strength = 0.0;
uniform float track_strength = 0.0;

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

// The hex grid's cell for p: xy the offset from its centre, zw its id.
vec4 hex_cell(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
}

// Cellular noise: distance to the nearest of a jittered point per cell (x), and that cell's id hash (y).
vec2 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + 19.7));
			float d = length(g + o - f);
			if (d < best) {
				best = d;
				id = hash12(i + g + 7.3);
			}
		}
	}
	return vec2(best, id);
}

// How far from the centre of its hex cell an offset is: 0.5 on the rim.
float hex_rim(vec2 h) {
	h = abs(h);
	return max(dot(h, vec2(0.5, 0.8660254)), h.x);
}

// 0 to 1: how much of a tyre track's two ruts p is on. Track k (seeded) is a long gentle curve
// across the zone, there along part of its length (the noise), its ruts 1.8 m apart.
float track(vec2 p, float k) {
	float a = hash12(vec2(k, seed_offset)) * 3.14159;
	vec2 dir = vec2(cos(a), sin(a));
	vec2 side = vec2(-dir.y, dir.x);
	float along = dot(p, dir);
	float off = dot(p, side) - (hash12(vec2(seed_offset, k)) - 0.5) * 1600.0;
	off -= sin(along / 190.0 + k * 2.3) * 30.0 + sin(along / 61.0 + k) * 4.0;
	float ruts = 1.0 - smoothstep(0.16, 0.34, abs(abs(off) - 0.9));
	return ruts * smoothstep(0.42, 0.55, vnoise(vec2(along / 420.0, k * 7.0)));
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
	col *= mix(0.84, 1.08, macro) * mix(0.90, 1.06, mid);  // (softer: the big smooth blotches read as smears, Captain 2026-10-18)
	col *= mix(1.0, mix(0.80, 1.12, fine), near);
	col *= mix(1.0, mix(0.84, 1.10, grain), close);

	if (damp_strength > 0.0) {
		// Damp patches: the crust darker and a touch greyer where the brine sits under it.
		float damp = vnoise(q / 350.0 + 11.0) * 0.65 + vnoise(p / 70.0 + 5.0) * 0.35;
		col *= mix(vec3(1.0), vec3(0.70, 0.71, 0.73), smoothstep(0.50, 0.78, damp) * damp_strength);
	}
	if (crust_strength > 0.0) {
		// The crust's polygons: a warped hex grid ~1.8 m across, lighter raised rims, each
		// plate its own shade; faded out before it can shimmer.
		float crust_near = 1.0 - smoothstep(30.0, 75.0, dist);
		if (crust_near > 0.0) {
			vec2 cp = p / 1.8 + vec2(vnoise(p * 0.45), vnoise(q * 0.45 + 3.0)) * 0.55;
			vec4 cell = hex_cell(cp);
			float rim = smoothstep(0.40, 0.48, hex_rim(cell.xy));
			float plate = mix(0.93, 1.04, hash12(cell.zw + seed_offset));
			col *= mix(1.0, mix(plate, 1.10, rim), crust_near * crust_strength);
		}
	}
	if (track_strength > 0.0) {
		float track_near = 1.0 - smoothstep(220.0, 320.0, dist);
		if (track_near > 0.0) {
			float on = 0.0;
			for (int k = 0; k < 5; k++) {
				on = max(on, track(p, float(k)));
			}
			col *= mix(1.0, 0.80, on * track_near * track_strength);
		}
	}

	// Near detail, in the buildings' voxel style (Captain, 2026-10-18: the ground "read smooth and
	// smeary" and "the ground art style needs to match the buildings"): the ground is made of
	// square blocks near the camera, the way the walls are made of voxels. Within ~110 m it's
	// quantized to BLOCK_M blocks, each a touch lighter or darker than its neighbours (as a voxel
	// wall's are), the grass clumps and bare soil patches snapped to that grid (blocky edges),
	// square stones on a 10 cm grid within ~25 m, and within ~12 m the 10 cm voxel grid itself.
	const float BLOCK_M = 0.25;
	float grassy = smoothstep(0.0, 0.05, base.g - base.r * 0.92);
	float mid_near = 1.0 - smoothstep(60.0, 110.0, dist);
	if (mid_near > 0.0) {
		vec2 bid = floor(p / BLOCK_M);
		vec2 bp = (bid + 0.5) * BLOCK_M;        // the block's centre: everything below is constant over a block
		vec2 bq = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * bp;
		vec2 c1 = cells(bq / 1.6 + 3.1);
		vec2 c2 = cells(bp / 0.75 + 9.4);
		float clump = step(c1.x, 0.38) * step(0.35, c1.y);
		float bare = step(c2.x, 0.30) * step(0.70, c2.y);
		vec3 grass_col = col * vec3(0.84, 0.94, 0.78) * mix(0.9, 1.05, c1.y);
		vec3 soil_col = mix(col, earth_colour, 0.7) * mix(0.95, 1.12, c2.y);
		col = mix(col, grass_col, clump * grassy * mid_near * 0.85);
		col = mix(col, soil_col, bare * mid_near * mix(0.35, 0.8, grassy));
		col *= mix(1.0, 1.0 + (hash12(bid + seed_offset) - 0.5) * 0.14, mid_near);  // each block its own shade, like a voxel
	}
	float speck_near = 1.0 - smoothstep(14.0, 26.0, dist);
	if (speck_near > 0.0) {
		vec2 sg = floor(p / 0.1);
		float sp = step(0.94, hash12(sg + seed_offset));
		float light = step(0.5, hash12(sg + 41.0));
		col *= mix(1.0, mix(0.66, 1.28, light), sp * speck_near * mix(1.0, 0.55, grassy));  // square stones
	}
	float voxel_near = 1.0 - smoothstep(6.0, 12.0, dist);
	if (voxel_near > 0.0) {
		col *= mix(1.0, 1.0 + (hash12(floor(p / 0.1) + 17.0) - 0.5) * 0.08, voxel_near);  // the 10 cm voxel grid up close
	}

	// Rock on steep faces, per pixel, with horizontal strata. Not on dug earth: GroundCuts gives a
	// crater's or a pit's walls alpha below 1 (the coarse ground's is 1), so they stay soil.
	float slope = 1.0 - clamp(w_nrm.y, 0.0, 1.0);
	float rock = smoothstep(0.20, 0.34, slope + (mid - 0.5) * 0.12) * COLOR.a;
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
