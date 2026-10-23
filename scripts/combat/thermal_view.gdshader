// The thermal channel's look (ThermalView, combined arms A4): a full-screen pass over the frame
// the sight's camera drew. Hot bodies carry their heat in the magenta channel (ThermalView's
// additive overlays: red and blue over green); the cold world is squeezed into a dark band by
// `ambient` (the ground's grey by the time of day), the sky (bluer than anything) darker still,
// and the heat comes out bright on top. Polarity 2 (black-hot) flips it. A little grain and a
// soft edge, as a real imager has.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform int polarity = 1;
uniform float ambient = 0.3;
uniform float grain = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float heat = clamp(min(c.r, c.b) - c.g, 0.0, 1.0);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float sky = clamp((c.b - max(c.r, c.g)) * 3.0, 0.0, 0.85);
	float cold = (0.06 + ambient * (0.35 + 0.65 * lum)) * (1.0 - sky);
	float v = max(cold, smoothstep(0.05, 0.9, heat));
	v += (hash(SCREEN_UV * 731.0 + TIME) - 0.5) * grain;
	if (polarity == 2) {
		v = 1.0 - v;
	}
	vec2 d = SCREEN_UV - vec2(0.5);
	v *= 1.0 - smoothstep(0.42, 0.75, length(d));
	COLOR = vec4(vec3(clamp(v, 0.0, 1.0)), 1.0);
}
