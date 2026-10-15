// A zone's sky with far ridges on the horizon (ZoneLevel, for a preset with a "backdrop"):
// the procedural sky's gradient and sun, plus two bands of low-poly ridges and mesas all round
// (straight edges between seeded knots, a nearer darker band and a farther, taller, hazier
// one), so a flat zone's horizon has a silhouette instead of a hard line of ground against the
// sky (Captain, 2026-10-14: the salt flats were "an actual eye sore"). Part of the sky, so it
// is always beyond the zone, never clipped by the far plane, and costs a few ops a pixel.
shader_type sky;

uniform vec3 sky_top : source_color = vec3(0.30, 0.46, 0.68);
uniform vec3 sky_horizon : source_color = vec3(0.76, 0.75, 0.71);
uniform float sky_curve = 0.15;
uniform float sun_angle_max = 20.0;
uniform float sun_curve = 0.15;
uniform vec3 ridge_colour : source_color = vec3(0.54, 0.52, 0.47);
// Elevation of each band's lowest and highest knots (degrees above the horizon).
uniform vec2 near_deg = vec2(0.25, 1.1);
uniform vec2 far_deg = vec2(0.6, 2.4);
uniform float seed = 0.0;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// The band's top (radians) at azimuth `az`: `knots` knots round the horizon, straight between
// them (low-poly), some low gaps, some flat-topped mesas.
float ridge(float az, float knots, vec2 lo_hi, float salt) {
	float u = (az / 6.2831853 + 0.5) * knots;
	float k = floor(u);
	float f = u - k;
	float a = hash11(mod(k, knots) * 1.37 + salt);
	float b = hash11(mod(k + 1.0, knots) * 1.37 + salt);
	float swell = hash11(floor(mod(k, knots) / 6.0) * 3.1 + salt * 2.0);
	a = min(a * mix(0.35, 1.0, swell), 0.82);
	b = min(b * mix(0.35, 1.0, hash11(floor(mod(k + 1.0, knots) / 6.0) * 3.1 + salt * 2.0)), 0.82);
	float t = mix(a, b, f) / 0.82;
	return radians(mix(lo_hi.x, lo_hi.y, t));
}

void sky() {
	float el = asin(clamp(EYEDIR.y, -1.0, 1.0));
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = 1.0 - v_angle / 1.5707963;
	vec3 col = mix(sky_horizon, sky_top, clamp(1.0 - pow(1.0 - clamp(c, 0.0, 1.0), 1.0 / sky_curve), 0.0, 1.0));
	if (LIGHT0_ENABLED) {
		float sun_angle = acos(clamp(dot(LIGHT0_DIRECTION, EYEDIR), -1.0, 1.0));
		float max_r = radians(sun_angle_max);
		if (sun_angle < LIGHT0_SIZE) {
			col = LIGHT0_COLOR * LIGHT0_ENERGY;
		} else if (sun_angle < max_r) {
			float c2 = (sun_angle - LIGHT0_SIZE) / (max_r - LIGHT0_SIZE);
			col = mix(LIGHT0_COLOR * LIGHT0_ENERGY, col, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0));
		}
	}
	float az = atan(EYEDIR.x, EYEDIR.z);
	// Far band: taller, mostly haze. Near band: lower, a little darker. Below the horizon: haze.
	float far_top = ridge(az, 90.0, far_deg, seed + 7.0);
	float near_top = ridge(az + 0.4, 140.0, near_deg, seed + 19.0);
	if (el < far_top) {
		col = mix(sky_horizon, ridge_colour, 0.38 * smoothstep(-0.002, far_top, el) + 0.1);
	}
	if (el < near_top) {
		col = mix(sky_horizon, ridge_colour, 0.55 + 0.2 * smoothstep(0.0, near_top, el));
	}
	if (el < 0.0) {
		col = mix(col, sky_horizon, smoothstep(0.0, -0.02, el));
	}
	COLOR = col;
}
