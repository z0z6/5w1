class_name RetroFx
extends RefCounted
## Tło "synthwave" (gwiazdy, słońce, góry, siatka) i nakładka CRT (linie skanowania, winieta).

static func add_background(parent: Control, dim := 1.0) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/retro_bg.gdshader")
	m.set_shader_parameter("dim", dim)
	r.material = m
	parent.add_child(r)
	r.resized.connect(func(): m.set_shader_parameter("rect_size", r.size))
	m.set_shader_parameter("rect_size", Vector2(720, 1280))
	return r

static func add_crt(parent: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/crt.gdshader")
	r.material = m
	layer.add_child(r)
	parent.add_child(layer)
	return layer
