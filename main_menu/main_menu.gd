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

var panel: OptionsPanel

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("07140e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 50
	box.offset_right = -50
	box.offset_top = 80
	box.offset_bottom = -50
	box.add_theme_constant_override("separation", 20)
	add_child(box)

	var title := Label.new()
	title.text = "RETRO ARCADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color("d9a066"))
	box.add_child(title)

	var sub := Label.new()
	sub.text = "5 w 1  •  rev 1.1"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color("4fbf7f"))
	box.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	box.add_child(spacer)

	for g in GAMES:
		var b := Button.new()
		var is_ready: bool = ResourceLoader.exists(g.scene)
		b.text = "%s\n%s" % [g.name, g.sub]
		b.custom_minimum_size = Vector2(0, 122)
		b.disabled = not is_ready
		UiKit.style_button(b, 36)
		if is_ready:
			b.pressed.connect(func(): get_tree().change_scene_to_file(g.scene))
		box.add_child(b)

	var opt := Button.new()
	opt.text = "Opcje"
	opt.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(opt, 34)
	opt.pressed.connect(_open_options)
	box.add_child(opt)

func _open_options() -> void:
	if panel:
		return
	panel = OptionsPanel.new()
	panel.closed.connect(func():
		panel.queue_free()
		panel = null)
	add_child(panel)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if panel:
			panel.queue_free()
			panel = null
		else:
			get_tree().quit()
