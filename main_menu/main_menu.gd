extends Control
## Hub 5 w 1 w stylu retro. Gra jest aktywna, gdy jej scena istnieje - dodanie nowej gry
## to tylko dopisanie sceny pod wskazaną ścieżką (i muzyki w tools/gen_audio.gd).

const GAMES := [
	{"name": "MARBLE MAZE", "scene": "res://games/marble_maze/marble_maze.tscn", "sub": "labirynt + żyroskop", "color": Color("00e5ff")},
	{"name": "PINBALL", "scene": "res://games/pinball/pinball.tscn", "sub": "wkrótce", "color": Color("ff2bd6")},
	{"name": "DIONAKRA", "scene": "res://games/dionakra/dionakra.tscn", "sub": "wkrótce", "color": Color("ffd400")},
	{"name": "SIRTET", "scene": "res://games/sirtet/sirtet.tscn", "sub": "wkrótce", "color": Color("39ff14")},
	{"name": "GRA NR 5", "scene": "res://games/game5/game5.tscn", "sub": "wkrótce", "color": Color("ff8a00")},
]

var panel: OptionsPanel

func _ready() -> void:
	RetroFx.add_background(self, 0.55)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 36
	box.offset_right = -36
	box.offset_top = 60
	box.offset_bottom = -44
	box.add_theme_constant_override("separation", 16)
	add_child(box)

	var title := UiKit.label("RETRO ARCADE", 40, UiKit.C_YELLOW, 8)
	title.add_theme_color_override("font_shadow_color", UiKit.C_MAGENTA)
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiKit.label("WYBIERZ GRĘ", 16, UiKit.C_CYAN, 4)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var blink := create_tween().set_loops()
	blink.tween_property(sub, "modulate:a", 0.25, 0.6)
	blink.tween_property(sub, "modulate:a", 1.0, 0.6)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)

	var idx := 1
	for g in GAMES:
		box.add_child(_cartridge(idx, g))
		idx += 1

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(fill)

	var opt := Button.new()
	opt.text = "OPCJE"
	opt.custom_minimum_size = Vector2(0, 84)
	UiKit.style_button(opt, 24, UiKit.C_MAGENTA)
	opt.pressed.connect(func():
		Audio.play_sfx("click")
		_open_options())
	box.add_child(opt)

	RetroFx.add_crt(self)
	Audio.play_music("menu")

func _cartridge(num: int, g: Dictionary) -> Button:
	var is_ready: bool = ResourceLoader.exists(g.scene)
	var accent: Color = g.color
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 132)
	b.disabled = not is_ready
	UiKit.style_button(b, 16, accent)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 22
	hb.offset_right = -14
	hb.add_theme_constant_override("separation", 22)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := 1.0 if is_ready else 0.4
	var n := UiKit.label("%d" % num, 48, Color(accent.r, accent.g, accent.b, dim))
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(n)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := UiKit.label(g.name, 32, Color(1, 1, 1, dim))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var sb := UiKit.label(g.sub, 16, Color(accent.r, accent.g, accent.b, dim * 0.85))
	sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sb)
	hb.add_child(vb)
	b.add_child(hb)
	if is_ready:
		b.pressed.connect(func():
			Audio.play_sfx("coin")
			get_tree().change_scene_to_file(g.scene))
	return b

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
