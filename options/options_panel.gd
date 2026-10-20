class_name OptionsPanel
extends Control
## Panel opcji - używany w menu głównym i jako nakładka w grach.
## Każda zmiana jest zapisywana na stałe (Settings.save()).

signal closed

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.0, 0.1, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 36
	box.offset_right = -36
	box.offset_top = 70
	box.offset_bottom = -50
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := UiKit.label("OPCJE", 40, UiKit.C_YELLOW, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	_section(list, "DŹWIĘK")
	_toggle(list, "Muzyka", "music")
	_slider(list, "Głośność muzyki", "music_vol", 0.0, 1.0, 0.05)
	_toggle(list, "Efekty dźwiękowe", "sounds")
	_slider(list, "Głośność efektów", "sfx_vol", 0.0, 1.0, 0.05)
	_section(list, "STEROWANIE")
	_toggle(list, "Odwróć oś X", "invert_x")
	_toggle(list, "Odwróć oś Y", "invert_y")
	_slider(list, "Czułość przechyłu", "sensitivity", 0.5, 1.6, 0.05)
	_toggle(list, "Dane czujnika", "show_debug")
	_section(list, "EFEKTY")
	_toggle(list, "Iskry, prąd, zwarcia", "effects")
	_toggle(list, "Wibracje", "vibration")
	var test := Button.new()
	test.text = "Test wibracji"
	test.custom_minimum_size = Vector2(0, 76)
	UiKit.style_button(test, 16, UiKit.C_MAGENTA)
	test.pressed.connect(func():
		Audio.play_sfx("click")
		Settings.vibrate(80))
	list.add_child(test)

	var ok := Button.new()
	ok.text = "GOTOWE"
	ok.custom_minimum_size = Vector2(0, 96)
	UiKit.style_button(ok, 24, UiKit.C_GREEN)
	ok.pressed.connect(_close)
	box.add_child(ok)

func _section(parent: Node, text: String) -> void:
	var l := UiKit.label("- %s -" % text, 16, UiKit.C_MAGENTA)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 34)
	parent.add_child(l)

func _toggle(parent: Node, text: String, key: String) -> void:
	# Duży przycisk-przełącznik, czytelny na telefonie: zielony = włączone
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = Settings.get(key)
	b.custom_minimum_size = Vector2(0, 76)
	UiKit.style_toggle(b, 16)
	_set_toggle_text(b, text, b.button_pressed)
	b.toggled.connect(func(v: bool):
		_set_toggle_text(b, text, v)
		_on_toggle(key, v))
	parent.add_child(b)

func _set_toggle_text(b: Button, text: String, on: bool) -> void:
	b.text = "%s: %s" % [text, "WŁ" if on else "WYŁ"]

func _on_toggle(key: String, value: bool) -> void:
	Settings.set(key, value)
	Settings.save()
	if key == "music" or key == "sounds":
		Audio.apply_settings()
	Audio.play_sfx("toggle_on" if value else "toggle_off")
	if key == "vibration" and value:
		Settings.vibrate(40)

func _slider(parent: Node, text: String, key: String, lo: float, hi: float, stp: float) -> void:
	var l := UiKit.label("%s: %.2f" % [text, float(Settings.get(key))], 16, Color.WHITE)
	parent.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = stp
	sl.value = float(Settings.get(key))
	sl.custom_minimum_size = Vector2(0, 56)
	sl.value_changed.connect(func(v: float):
		Settings.set(key, v)
		l.text = "%s: %.2f" % [text, v]
		Audio.apply_settings())
	sl.drag_ended.connect(func(_changed: bool):
		Settings.save()
		Audio.play_sfx("click"))
	parent.add_child(sl)

func _close() -> void:
	Audio.play_sfx("back")
	Settings.save()
	closed.emit()
