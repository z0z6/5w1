extends Control
## Hub 5 w 1. Gra jest aktywna, gdy jej scena istnieje - dodanie nowej gry
## to tylko dopisanie sceny pod wskazaną ścieżką.

const GAMES := [
	{"name": "Marble Maze", "scene": "res://games/marble_maze/marble_maze.tscn", "sub": "labirynt  •  żyroskop"},
	{"name": "Pinball", "scene": "res://games/pinball/pinball.tscn", "sub": "wkrótce"},
	{"name": "Dionakra", "scene": "res://games/dionakra/dionakra.tscn", "sub": "wkrótce"},
	{"name": "Sirtet", "scene": "res://games/sirtet/sirtet.tscn", "sub": "wkrótce"},
	{"name": "Gra nr 5", "scene": "res://games/game5/game5.tscn", "sub": "wkrótce"},
]

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("07140e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 50
	box.offset_right = -50
	box.offset_top = 120
	box.offset_bottom = -60
	box.add_theme_constant_override("separation", 26)
	add_child(box)

	var title := Label.new()
	title.text = "RETRO ARCADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("d9a066"))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "5 w 1  •  rev 1.0"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color("4fbf7f"))
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	for g in GAMES:
		var b := Button.new()
		var is_ready: bool = ResourceLoader.exists(g.scene)
		b.text = "%s\n%s" % [g.name, g.sub]
		b.custom_minimum_size = Vector2(0, 150)
		b.disabled = not is_ready
		b.add_theme_font_size_override("font_size", 38)
		_style(b)
		if is_ready:
			b.pressed.connect(func(): get_tree().change_scene_to_file(g.scene))
		box.add_child(b)

func _style(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("0d3a24") if state != "pressed" else Color("14583a")
		if state == "disabled":
			sb.bg_color = Color("0a1d14")
		sb.border_color = Color("c98a4a") if state != "disabled" else Color("4a3a28")
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(14)
		b.add_theme_stylebox_override(state, sb)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
