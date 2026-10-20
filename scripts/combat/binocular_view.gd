class_name BinocularView
extends CanvasLayer
## The local player's view through binoculars (Captain, 2026-10-20: "when are binocs going to be
## usable"): the two-circle frame over the 3D view, with a mil scale in the middle for judging
## range. PlayerInput raises and lowers them (the binoculars key, B on foot) and zooms the camera
## (MAGNIFICATION, relative to the view as optics are: Captain, 2026-10-13); this only draws the
## frame. Under the HUD, over the 3D view, like NvgView.

const SHADER := """
shader_type canvas_item;
uniform float aspect = 1.7777;
uniform float radius = 0.62;
uniform float apart = 0.42;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= aspect;
	float d = min(length(uv - vec2(-apart, 0.0)), length(uv - vec2(apart, 0.0)));
	float edge = smoothstep(radius - 0.012, radius + 0.012, d);
	// The mil scale: a thin horizontal line across the middle, ticks every 10 mils' worth.
	float line = (1.0 - step(0.0025, abs(uv.y))) * (1.0 - step(0.5, abs(uv.x)));
	float ticks = (1.0 - step(0.012, abs(uv.y))) * (1.0 - step(0.5, abs(uv.x))) * (1.0 - step(0.0025, abs(fract(uv.x * 10.0 + 0.5) - 0.5)));
	float mark = max(line, ticks) * (1.0 - edge);
	COLOR = mix(vec4(0.0, 0.0, 0.0, edge * 0.97), vec4(0.05, 0.05, 0.05, 0.85), mark);
}
"""

var rect: ColorRect
var _material: ShaderMaterial


func _init() -> void:
	name = "BinocularView"
	layer = -1
	rect = ColorRect.new()
	rect.name = "BinocularFrame"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	rect.material = _material
	add_child(rect)
	rect.visible = false


## Shows or hides the frame.
func show_frame(on: bool) -> void:
	rect.visible = on
	if on:
		var size := rect.get_viewport_rect().size
		_material.set_shader_parameter(&"aspect", size.x / size.y if size.y > 0.0 else 16.0 / 9.0)
