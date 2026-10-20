class_name UiKit
extends RefCounted
## Wspólny wygląd przycisków (motyw PCB) dla menu, opcji i gier.

static func style_button(b: Button, font_size := 30) -> void:
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("0d3a24") if state != "pressed" else Color("14583a")
		if state == "disabled":
			sb.bg_color = Color("0a1d14")
		sb.border_color = Color("c98a4a") if state != "disabled" else Color("4a3a28")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
