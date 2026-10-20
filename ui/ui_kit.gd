class_name UiKit
extends RefCounted
## Wspólny, retro wygląd interfejsu (neony na ciemnym fiolecie, kanciaste ramki, pikselowa czcionka).

const C_BG := Color("0a0420")
const C_PANEL := Color("1a0b3d")
const C_CYAN := Color("00e5ff")
const C_MAGENTA := Color("ff2bd6")
const C_YELLOW := Color("ffd400")
const C_GREEN := Color("39ff14")
const C_ORANGE := Color("ff8a00")

static func style_button(b: Button, font_size := 16, accent := C_CYAN) -> void:
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", C_YELLOW)
	b.add_theme_color_override("font_pressed_color", C_YELLOW)
	b.add_theme_color_override("font_disabled_color", Color(0.42, 0.36, 0.6))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_PANEL
		sb.border_color = accent
		sb.shadow_color = Color(0, 0, 0, 0.7)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 5)
		match state:
			"hover":
				sb.bg_color = C_PANEL.lightened(0.12)
			"pressed":
				sb.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35)
				sb.shadow_offset = Vector2(0, 1)
			"disabled":
				sb.bg_color = Color(0.06, 0.03, 0.14)
				sb.border_color = Color(0.25, 0.2, 0.4)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

## Przycisk-przełącznik (zielony, gdy włączony).
static func style_toggle(b: Button, font_size := 16) -> void:
	style_button(b, font_size, C_CYAN)
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.08, 0.38, 0.1)
	on.border_color = C_GREEN
	on.shadow_color = Color(0, 0, 0, 0.7)
	on.shadow_size = 1
	on.shadow_offset = Vector2(0, 1)
	on.set_border_width_all(4)
	on.set_corner_radius_all(0)
	on.content_margin_left = 8
	on.content_margin_right = 8
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)

static func label(text: String, size: int, color: Color, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l
