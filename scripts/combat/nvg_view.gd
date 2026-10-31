class_name NvgView
extends CanvasLayer
## The local player's view through lowered, powered NVGs (wave 7, S2; Nvg): the world turned
## green and brightened, with grain, inside the tube's field of view (the NVG's "fov_deg"; a
## soft circle, the unaided eye's dim view around it). A full-screen post effect over the 3D
## view and under the HUD; only the wearer's own camera (PlayerInput adds it for the local
## player). Headless-safe: it's a ColorRect with a shader, nothing else.

## The tube's picture: a gain on the light (the image intensifier), its tint, and the grain.
## v0.7.1 (the Captain: "pitch black, I can't see anything with the gen 2s"): the gain is the
## NVG's own (its stats' "gain", by generation; Nvg.gain_of), far above the old flat 3, with
## automatic brightness control as real tubes have: the gain backs off as the whole picture
## brightens (ABC), so a lit street or a flare doesn't white it out. GAIN is the fallback.
const GAIN := 60.0
## ABC: the gain is divided by (1 + the picture's mean light x gain x ABC).
const ABC := 1.5
## Starlight the tube always finds: the darkest of nights isn't drawn black.
const FLOOR := 0.035
const TINT := Color(0.32, 1.0, 0.42)
const GRAIN := 0.12
## Outside the tube: how much of the plain (unaided) view is still seen.
const OUTSIDE := 0.18
## v0.7.1 (the Captain: "we don't want NVGs to only illum a fraction of the screen ... puts
## players at a disadvantage compared to the AI at night"): the picture fills the screen (a
## radius past the corners, with a soft vignette at the edges) whatever the tube's field of view.
const FULL_SCREEN := 2.4
## Flares bloom the tube (AI bar G-24; bloom()): standing in a flare's light washes the picture
## out by BLOOM_LIT x the light, a burning flare in the tube's view by up to BLOOM_SEEN more
## (straight at it, fading to the tube's edge and out to GLARE_M off). The shader lifts the
## gain and whites the picture out by it. Proposed.
const BLOOM_LIT := 0.6
const BLOOM_SEEN := 0.7
const GLARE_M := 700.0

## The intensifier, over the screen behind it (SHADER_HEAD's sampler, SEEN_SCREEN) or over a
## texture drawn on top (SEEN_TEXTURE: scope_material, a magnified optic's picture-in-picture in
## GunSight, seen through the goggles like the rest of the view).
const SHADER_HEAD := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
"""
const SEEN_SCREEN := "texture(screen_tex, SCREEN_UV).rgb"
const SEEN_TEXTURE := "texture(TEXTURE, UV).rgb"
## The picture's mean light (for ABC): the screen copy's smallest mip; a scope's texture has no
## mips, so its picture is taken as dark (full gain).
const MEAN_SCREEN := "dot(textureLod(screen_tex, vec2(0.5), 10.0).rgb, vec3(0.299, 0.587, 0.114))"
const MEAN_TEXTURE := "0.0"
const SHADER := """
uniform float gain = 60.0;
uniform float abc = 1.5;
uniform float floor_light = 0.035;
uniform vec3 tint = vec3(0.32, 1.0, 0.42);
uniform float grain = 0.12;
uniform float tube = 0.6;     // the tube's radius, as a share of half the screen's height
uniform float outside = 0.18;
uniform float aspect = 1.777;
uniform float bloom = 0.0;    // flares (NvgView.bloom): the tube washed out, 0..1

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 seen = SEEN;
	float lum = dot(seen, vec3(0.299, 0.587, 0.114));
	float g = gain / (1.0 + MEAN * gain * abc);
	float lit = 1.0 - exp(-lum * g * (1.0 + bloom * 3.0));
	lit = max(lit, floor_light);
	lit = mix(lit, 1.0, bloom * 0.55);
	float noise = hash(floor(FRAGCOORD.xy * 0.75) + fract(TIME * 7.0) * 113.0) - 0.5;
	lit = clamp(lit + noise * grain, 0.0, 1.0);
	vec2 c = (SCREEN_UV - vec2(0.5)) * vec2(aspect, 1.0) * 2.0;
	float r = length(c);
	float inside = 1.0 - smoothstep(tube * 0.92, tube, r);
	float vignette = 1.0 - 0.35 * smoothstep(min(tube * 0.4, 1.1), min(tube, 2.1), r);
	vec3 green = tint * lit * vignette;
	COLOR = vec4(mix(seen * outside, green, inside), 1.0);
}
"""

var body: Soldier
var rect: ColorRect
var _material: ShaderMaterial


func _init(p_body: Soldier = null) -> void:
	body = p_body
	name = "NvgView"
	layer = -1  # over the 3D view, under the HUD (layer 1) and the menus
	rect = ColorRect.new()
	rect.name = "NvgEffect"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = _make_material(screen_shader_code())
	rect.material = _material
	add_child(rect)
	rect.visible = false


## The intensifier over the screen behind it (this view, and the vehicle HUD's night channel).
static func screen_shader_code() -> String:
	return SHADER_HEAD + SHADER.replace("SEEN", SEEN_SCREEN).replace("MEAN", MEAN_SCREEN)


static func _make_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"gain", GAIN)
	material.set_shader_parameter(&"abc", ABC)
	material.set_shader_parameter(&"floor_light", FLOOR)
	material.set_shader_parameter(&"tint", Vector3(TINT.r, TINT.g, TINT.b))
	material.set_shader_parameter(&"grain", GRAIN)
	material.set_shader_parameter(&"outside", OUTSIDE)
	return material


## The goggles' effect for a texture drawn over the view rather than the screen behind it: a
## magnified optic's picture-in-picture (GunSight), which the HUD draws above this layer. Same
## gain, tint, grain and tube (set_view), with no copy of the screen.
static func scope_material() -> ShaderMaterial:
	return _make_material("shader_type canvas_item;\n" + SHADER.replace("SEEN", SEEN_TEXTURE).replace("MEAN", MEAN_TEXTURE))


## Points `material`'s tube at `body`'s NVG, sized against their real camera, over a screen
## `size` across (the tube is a circle on the screen whatever's drawn under it), at least
## `at_least` (a share of half the screen's height: a scope's eyepiece held up to the goggles
## fills the tube, so its whole lens is seen through it).
static func set_view(material: ShaderMaterial, body: Soldier, size: Vector2, at_least := 0.0) -> void:
	material.set_shader_parameter(&"tube", maxf(FULL_SCREEN, at_least))
	material.set_shader_parameter(&"gain", Nvg.gain_of(body, GAIN))
	material.set_shader_parameter(&"aspect", size.x / size.y if size.y > 0.0 else 16.0 / 9.0)


func _process(_delta: float) -> void:
	update()


## Shows the effect while `body`'s NVG is down and powered, the tube sized to its field of view.
func update() -> void:
	var on := body != null and is_instance_valid(body) and Nvg.is_on(body)
	rect.visible = on
	GearRig.set_iff_nvg(on)  # our side's IFF marks glow under it
	if not on:
		return
	set_view(_material, body, rect.get_viewport_rect().size)
	_material.set_shader_parameter(&"bloom", bloom(body))


## How much flares bloom `body`'s NVG now (0..1; see BLOOM_LIT): the light he stands in, and
## any burning flare within his tube's view.
static func bloom(body: Soldier) -> float:
	if Flares.burning.is_empty() or body == null or not is_instance_valid(body):
		return 0.0
	var eye := body.camera.global_position if body.camera else body.global_position + Vector3.UP * 1.6
	var fwd := -body.camera.global_basis.z if body.camera else -body.global_basis.z
	var half := deg_to_rad(maxf(Nvg.fov_of(body), 1.0) * 0.5)
	var out := Flares.light_at(body.global_position) * BLOOM_LIT
	for f: Dictionary in Flares.burning:
		var to := Flares.position_of(f) - eye
		var d := to.length()
		if d < 0.1 or d > GLARE_M:
			continue
		var off := fwd.angle_to(to / d)
		if off < half:
			out += BLOOM_SEEN * (1.0 - off / half) * (1.0 - d / GLARE_M)
	return clampf(out, 0.0, 1.0)


## The tube's radius as a share of half the screen's height: a tube of `tube_deg` seen by a
## camera of vertical field of view `camera_deg` (1 = the screen's height).
static func tube_radius(tube_deg: float, camera_deg: float) -> float:
	if tube_deg <= 0.0 or camera_deg <= 0.0:
		return 0.0
	return tan(deg_to_rad(tube_deg) * 0.5) / tan(deg_to_rad(camera_deg) * 0.5)
