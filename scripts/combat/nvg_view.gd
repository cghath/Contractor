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

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
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
	vec3 seen = texture(screen_tex, SCREEN_UV).rgb;
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
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter(&"gain", GAIN)
	_material.set_shader_parameter(&"tint", Vector3(TINT.r, TINT.g, TINT.b))
	_material.set_shader_parameter(&"grain", GRAIN)
	_material.set_shader_parameter(&"outside", OUTSIDE)
	rect.material = _material
	add_child(rect)
	rect.visible = false


func _process(_delta: float) -> void:
	update()


## Shows the effect while `body`'s NVG is down and powered, the tube sized to its field of view.
func update() -> void:
	var on := body != null and is_instance_valid(body) and Nvg.is_on(body)
	rect.visible = on
	GearRig.set_iff_nvg(on)  # our side's IFF marks glow under it
	if not on:
		return
	var cam_fov := body.camera.fov if body.camera else 75.0
	_material.set_shader_parameter(&"tube", tube_radius(Nvg.fov_of(body), cam_fov))
	var size := rect.get_viewport_rect().size
	_material.set_shader_parameter(&"aspect", size.x / size.y if size.y > 0.0 else 16.0 / 9.0)


## The tube's radius as a share of half the screen's height: a tube of `tube_deg` seen by a
## camera of vertical field of view `camera_deg` (1 = the screen's height).
static func tube_radius(tube_deg: float, camera_deg: float) -> float:
	if tube_deg <= 0.0 or camera_deg <= 0.0:
		return 0.0
	return tan(deg_to_rad(tube_deg) * 0.5) / tan(deg_to_rad(camera_deg) * 0.5)
