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
	dim.color = Color(0.0, 0.03, 0.02, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 50
	box.offset_right = -50
	box.offset_top = 90
	box.offset_bottom = -60
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var title := Label.new()
	title.text = "OPCJE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("d9a066"))
	box.add_child(title)

	_toggle(box, "Wibracje", "vibration")
	_toggle(box, "Efekty (iskry, prąd, zwarcia)", "effects")
	_toggle(box, "Odwróć oś X (lewo / prawo)", "invert_x")
	_toggle(box, "Odwróć oś Y (góra / dół)", "invert_y")
	_toggle(box, "Pokaż dane czujnika", "show_debug")

	var sens := Label.new()
	sens.add_theme_font_size_override("font_size", 30)
	sens.text = "Czułość przechyłu: %.2f" % Settings.sensitivity
	box.add_child(sens)
	var sl := HSlider.new()
	sl.min_value = 0.5
	sl.max_value = 1.6
	sl.step = 0.05
	sl.value = Settings.sensitivity
	sl.custom_minimum_size = Vector2(0, 60)
	sl.value_changed.connect(func(v: float):
		Settings.sensitivity = v
		sens.text = "Czułość przechyłu: %.2f" % v)
	sl.drag_ended.connect(func(_changed: bool): Settings.save())
	box.add_child(sl)

	var test := Button.new()
	test.text = "Test wibracji"
	test.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(test, 32)
	test.pressed.connect(func(): Settings.vibrate(80))
	box.add_child(test)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var ok := Button.new()
	ok.text = "Gotowe"
	ok.custom_minimum_size = Vector2(0, 110)
	UiKit.style_button(ok, 40)
	ok.pressed.connect(_close)
	box.add_child(ok)

func _toggle(parent: Node, text: String, key: String) -> void:
	# Duży przycisk-przełącznik, czytelny na telefonie: zielony = włączone
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = Settings.get(key)
	b.custom_minimum_size = Vector2(0, 84)
	UiKit.style_button(b, 30)
	var on := StyleBoxFlat.new()
	on.bg_color = Color("1b8a50")
	on.border_color = Color("c98a4a")
	on.set_border_width_all(3)
	on.set_corner_radius_all(12)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	_set_toggle_text(b, text, b.button_pressed)
	b.toggled.connect(func(v: bool):
		_set_toggle_text(b, text, v)
		_on_toggle(key, v))
	parent.add_child(b)

func _set_toggle_text(b: Button, text: String, on: bool) -> void:
	b.text = "%s:  %s" % [text, "WŁ" if on else "WYŁ"]

func _on_toggle(key: String, value: bool) -> void:
	Settings.set(key, value)
	Settings.save()
	if key == "vibration" and value:
		Settings.vibrate(40)

func _close() -> void:
	Settings.save()
	closed.emit()
