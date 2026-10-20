extends Control
## Strona startowa w stylu arcade lat 80.: sekwencja "BIOS" -> błysk -> tytuł z dźwiękiem
## -> "DOTKNIJ, ABY ROZPOCZĄĆ" -> menu główne. Dotknięcie w trakcie sekwencji ją pomija.

const MENU_SCENE := "res://main_menu/main_menu.tscn"
const BOOT_LINES := [
	"RETRO-BIOS v1.1",
	"(C) 1986-2026 ARCADE SYSTEMS",
	"",
	"CPU ........... OK",
	"RAM 640K ...... OK",
	"GFX / SND ..... OK",
	"GYRO SENSOR ... OK",
	"CARTRIDGES .... 5",
	"",
	"STARTING SYSTEM_",
]

var state := "boot"          # boot -> title -> done
var skip := false
var bg: ColorRect
var boot_label: Label
var flash: ColorRect
var title_letters: Array[Label] = []
var prompt: Label
var extras: Array[Control] = []

func _ready() -> void:
	set_process(true)
	bg = RetroFx.add_background(self, 1.0)
	bg.modulate.a = 0.0

	boot_label = UiKit.label("", 16, UiKit.C_GREEN)
	boot_label.position = Vector2(32, 70)
	boot_label.add_theme_constant_override("line_spacing", 10)
	add_child(boot_label)

	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	RetroFx.add_crt(self)
	_run_boot()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _run_boot() -> void:
	await _wait(0.35)
	for line in BOOT_LINES:
		if skip or not is_inside_tree():
			break
		for i in range(0, line.length(), 3):
			if skip:
				break
			boot_label.text += line.substr(i, 3)
			await _wait(0.016)
		boot_label.text += "\n"
		Audio.play_sfx("type", -4.0, randf_range(0.9, 1.15))
		await _wait(0.05)
	if not skip and is_inside_tree():
		Audio.play_sfx("boot_ok")
		await _wait(0.4)
	if is_inside_tree():
		_show_title()

func _show_title() -> void:
	if state != "boot":
		return
	state = "title"
	boot_label.visible = false
	flash.color.a = 1.0
	create_tween().tween_property(flash, "color:a", 0.0, 0.5)
	create_tween().tween_property(bg, "modulate:a", 1.0, 0.4)
	Audio.play_music("intro", true)

	var vp := get_viewport_rect().size
	var size_px := 96
	var rows := [
		{"text": "RETRO", "y": vp.y * 0.17, "colors": [Color("ffd400"), Color("ffb000"), Color("ff7a1a"), Color("ff4f6a"), Color("ff2bd6")]},
		{"text": "ARCADE", "y": vp.y * 0.17 + 118.0, "colors": [Color("39ff14"), Color("00ffa0"), Color("00e5ff"), Color("3aa0ff"), Color("7a6bff"), Color("c060ff")]},
	]
	var delay := 0.25
	for row in rows:
		var text: String = row.text
		var x0 := (vp.x - text.length() * size_px) / 2.0
		for i in text.length():
			var l := UiKit.label(text[i], size_px, row.colors[i], 14)
			l.add_theme_color_override("font_shadow_color", Color(0.1, 0.0, 0.25))
			l.add_theme_constant_override("shadow_offset_x", 8)
			l.add_theme_constant_override("shadow_offset_y", 8)
			l.position = Vector2(x0 + i * size_px, -200.0)
			add_child(l)
			title_letters.append(l)
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_property(l, "position:y", float(row.y), 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): Audio.play_sfx("hit", -8.0, randf_range(0.8, 1.3)))
			delay += 0.12
	await _wait(delay + 0.5)
	if not is_inside_tree():
		return
	var sub := UiKit.label("5 GIER W 1", 32, UiKit.C_CYAN, 8)
	sub.modulate.a = 0.0
	add_child(sub)
	sub.position = Vector2((vp.x - sub.get_minimum_size().x) / 2.0, vp.y * 0.17 + 255.0)
	create_tween().tween_property(sub, "modulate:a", 1.0, 0.5)
	extras.append(sub)

	prompt = UiKit.label("DOTKNIJ, ABY ROZPOCZĄĆ", 24, UiKit.C_YELLOW, 8)
	add_child(prompt)
	prompt.position = Vector2((vp.x - prompt.get_minimum_size().x) / 2.0, vp.y * 0.86)
	var blink := create_tween().set_loops()
	blink.tween_property(prompt, "modulate:a", 0.0, 0.0).set_delay(0.55)
	blink.tween_property(prompt, "modulate:a", 1.0, 0.0).set_delay(0.55)

	var foot := UiKit.label("(C) 2026  ARCADE SYSTEMS", 16, Color(0.7, 0.6, 1.0, 0.8))
	add_child(foot)
	foot.position = Vector2((vp.x - foot.get_minimum_size().x) / 2.0, vp.y * 0.93)

func _process(_d: float) -> void:
	# delikatne "falowanie" tytułu
	if state == "title":
		var t := Time.get_ticks_msec() / 1000.0
		for i in title_letters.size():
			var l := title_letters[i]
			if l.position.y > 0.0:
				l.rotation = sin(t * 2.0 + i * 0.7) * 0.025

func _input(e: InputEvent) -> void:
	var pressed := false
	if e is InputEventScreenTouch and e.pressed:
		pressed = true
	elif e is InputEventMouseButton and e.pressed:
		pressed = true
	elif e is InputEventKey and e.pressed:
		pressed = true
	if not pressed:
		return
	if state == "boot":
		skip = true
	elif state == "title" and prompt != null:
		_start()

func _start() -> void:
	state = "done"
	Audio.play_sfx("coin")
	flash.color = Color(1, 1, 1, 0.9)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.35)
	await _wait(0.45)
	if is_inside_tree():
		get_tree().change_scene_to_file(MENU_SCENE)
