class_name NvgView
extends CanvasLayer
## The local player's view through lowered, powered NVGs (wave 7, S2; Nvg): the world turned
## green and brightened, with grain, inside the tube's field of view (the NVG's "fov_deg"; a
## soft circle, the unaided eye's dim view around it). A full-screen post effect over the 3D
## view and under the HUD; only the wearer's own camera (PlayerInput adds it for the local
## player). Headless-safe: it's a ColorRect with a shader, nothing else.

## The tube's picture: a gain on the light (the image intensifier), its tint, and the grain.
const GAIN := 3.0
const TINT := Color(0.32, 1.0, 0.42)
const GRAIN := 0.12
## Outside the tube: how much of the plain (unaided) view is still seen.
const OUTSIDE := 0.18

## The intensifier, over the screen behind it (SHADER_HEAD's sampler, SEEN_SCREEN) or over a
## texture drawn on top (SEEN_TEXTURE: scope_material, a magnified optic's picture-in-picture in
## GunSight, seen through the goggles like the rest of the view).
const SHADER_HEAD := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
"""
const SEEN_SCREEN := "texture(screen_tex, SCREEN_UV).rgb"
const SEEN_TEXTURE := "texture(TEXTURE, UV).rgb"
const SHADER := """
uniform float gain = 3.0;
uniform vec3 tint = vec3(0.32, 1.0, 0.42);
uniform float grain = 0.12;
uniform float tube = 0.6;     // the tube's radius, as a share of half the screen's height
uniform float outside = 0.18;
uniform float aspect = 1.777;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 seen = SEEN;
	float lum = dot(seen, vec3(0.299, 0.587, 0.114));
	float lit = 1.0 - exp(-lum * gain);
	float noise = hash(floor(FRAGCOORD.xy * 0.75) + fract(TIME * 7.0) * 113.0) - 0.5;
	lit = clamp(lit + noise * grain, 0.0, 1.0);
	vec2 c = (SCREEN_UV - vec2(0.5)) * vec2(aspect, 1.0) * 2.0;
	float r = length(c);
	float inside = 1.0 - smoothstep(tube * 0.92, tube, r);
	float vignette = 1.0 - 0.35 * smoothstep(tube * 0.4, tube, r);
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
	_material = _make_material(SHADER_HEAD + SHADER.replace("SEEN", SEEN_SCREEN))
	rect.material = _material
	add_child(rect)
	rect.visible = false


static func _make_material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"gain", GAIN)
	material.set_shader_parameter(&"tint", Vector3(TINT.r, TINT.g, TINT.b))
	material.set_shader_parameter(&"grain", GRAIN)
	material.set_shader_parameter(&"outside", OUTSIDE)
	return material


## The goggles' effect for a texture drawn over the view rather than the screen behind it: a
## magnified optic's picture-in-picture (GunSight), which the HUD draws above this layer. Same
## gain, tint, grain and tube (set_view), with no copy of the screen.
static func scope_material() -> ShaderMaterial:
	return _make_material("shader_type canvas_item;\n" + SHADER.replace("SEEN", SEEN_TEXTURE))


## Points `material`'s tube at `body`'s NVG, sized against their real camera, over a screen
## `size` across (the tube is a circle on the screen whatever's drawn under it), at least
## `at_least` (a share of half the screen's height: a scope's eyepiece held up to the goggles
## fills the tube, so its whole lens is seen through it).
static func set_view(material: ShaderMaterial, body: Soldier, size: Vector2, at_least := 0.0) -> void:
	var cam_fov := body.camera.fov if body.camera else 75.0
	material.set_shader_parameter(&"tube", maxf(tube_radius(Nvg.fov_of(body), cam_fov), at_least))
	material.set_shader_parameter(&"aspect", size.x / size.y if size.y > 0.0 else 16.0 / 9.0)


func _process(_delta: float) -> void:
	update()


func _exit_tree() -> void:
	GearRig.iff_light(false, 0.0)


## Shows the effect while `body`'s NVG is down and powered, the tube sized to its field of view.
func update() -> void:
	var on := body != null and is_instance_valid(body) and Nvg.is_on(body)
	rect.visible = on
	GearRig.iff_light(on, DayNight.darkness_at(body.global_position if on else Vector3.ZERO))  # IFF marks: their glow (friendly ones flare in the tube)
	if not on:
		return
	set_view(_material, body, rect.get_viewport_rect().size)


## The tube's radius as a share of half the screen's height: a tube of `tube_deg` seen by a
## camera of vertical field of view `camera_deg` (1 = the screen's height).
static func tube_radius(tube_deg: float, camera_deg: float) -> float:
	if tube_deg <= 0.0 or camera_deg <= 0.0:
		return 0.0
	return tan(deg_to_rad(tube_deg) * 0.5) / tan(deg_to_rad(camera_deg) * 0.5)
