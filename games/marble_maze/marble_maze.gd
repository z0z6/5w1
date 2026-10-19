extends Node3D
## Marble Maze - chromowana kulka na płytce PCB, sterowanie przechyłem telefonu.
## Plansza jest budowana w całości z kodu (bez zewnętrznych assetów).

const CELL := 1.0
const WALL_H := 0.7
const BALL_R := 0.3
const TILT_FORCE := 30.0
const MARGIN := 0.7
const HOLE_R := 0.3

var level := 1
var grid: Array = []
var cols := 0
var rows := 0
var start_pos := Vector3.ZERO
var goal_pos := Vector3.ZERO
var holes: Array[Vector3] = []

var level_root: Node3D
var ball: RigidBody3D
var cam_rig: Node3D
var camera: Camera3D
var lbl_info: Label
var lbl_msg: Label
var btn_axes: Button

var tilt := Vector2.ZERO
var calib := Vector2.ZERO
var state := "play"
var elapsed := 0.0
var prev_speed := 0.0
var mats := {}

func _ready() -> void:
	_make_materials()
	_setup_environment()
	_setup_camera()
	_setup_ui()
	_load_level(1)
	get_tree().create_timer(0.8).timeout.connect(_calibrate)

# ------------------------------------------------------------------ materiały
func _mat(color: Color, metallic := 0.0, rough := 0.5, emis := Color.BLACK, emis_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m

func _make_materials() -> void:
	mats.chip = _mat(Color(0.05, 0.05, 0.06), 0.1, 0.45)
	mats.chip_mark = _mat(Color(0.8, 0.8, 0.8), 0.0, 0.6)
	mats.alu = _mat(Color(0.72, 0.74, 0.78), 1.0, 0.3)
	mats.cap_body = _mat(Color(0.05, 0.12, 0.35), 0.2, 0.35)
	mats.cap_top = _mat(Color(0.8, 0.82, 0.85), 1.0, 0.25)
	mats.gold = _mat(Color(0.95, 0.75, 0.3), 1.0, 0.25)
	mats.black = _mat(Color(0.01, 0.01, 0.01), 0.0, 1.0)
	mats.copper = _mat(Color(0.86, 0.55, 0.30), 1.0, 0.3)
	mats.chrome = _mat(Color(0.92, 0.94, 0.97), 1.0, 0.05)
	mats.silver = _mat(Color(0.8, 0.82, 0.85), 1.0, 0.35)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://games/marble_maze/pcb.gdshader")
	mats.pcb = sm

func _phys(friction: float, bounce: float) -> PhysicsMaterial:
	var p := PhysicsMaterial.new()
	p.friction = friction
	p.bounce = bounce
	return p

# ---------------------------------------------------------- środowisko, kamera
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.025, 0.03)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.55, 0.62, 0.75)
	sm.sky_horizon_color = Color(0.9, 0.85, 0.8)
	sm.ground_horizon_color = Color(0.5, 0.45, 0.4)
	sm.ground_bottom_color = Color(0.08, 0.08, 0.1)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

func _setup_camera() -> void:
	cam_rig = Node3D.new()
	add_child(cam_rig)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 50.0
	cam_rig.add_child(camera)

func _fit_camera() -> void:
	var w := cols * CELL + MARGIN * 2.0 + 0.3
	var h := rows * CELL + MARGIN * 2.0
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_h := tan(deg_to_rad(camera.fov / 2.0))
	var dist := (w / 2.0) / half_h
	dist = maxf(dist, (h / 2.0) / (half_h / aspect))
	dist *= 1.05
	camera.position = Vector3(0, dist, dist * 0.25)
	camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))

# ------------------------------------------------------------------------ UI
func _setup_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	lbl_info = Label.new()
	lbl_info.position = Vector2(24, 50)
	lbl_info.add_theme_font_size_override("font_size", 34)
	lbl_info.add_theme_color_override("font_color", Color("e8c9a0"))
	lbl_info.add_theme_constant_override("outline_size", 8)
	lbl_info.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_info)

	lbl_msg = Label.new()
	lbl_msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 64)
	lbl_msg.add_theme_color_override("font_color", Color("7dffb0"))
	lbl_msg.add_theme_constant_override("outline_size", 12)
	lbl_msg.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lbl_msg)

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hb.offset_top = -120
	hb.offset_bottom = -30
	hb.offset_left = 20
	hb.offset_right = -20
	hb.add_theme_constant_override("separation", 16)
	ui.add_child(hb)

	var b_menu := _btn("Menu")
	b_menu.pressed.connect(_go_menu)
	hb.add_child(b_menu)
	var b_cal := _btn("Kalibruj")
	b_cal.pressed.connect(_calibrate)
	hb.add_child(b_cal)
	btn_axes = _btn("")
	btn_axes.pressed.connect(_cycle_axes)
	hb.add_child(btn_axes)
	_update_axes_label()

func _btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 30)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.22, 0.14, 0.85)
		sb.border_color = Color("c98a4a")
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(12)
		b.add_theme_stylebox_override(st, sb)
	return b

func _update_ui() -> void:
	var best := Save.get_best("marble", str(level))
	var best_txt := "--" if best == 0.0 else "%.1f s" % best
	lbl_info.text = "POZIOM %d   %.1f s   rekord: %s" % [level, elapsed, best_txt]

func _update_axes_label() -> void:
	btn_axes.text = "Osie %s%s" % ["-" if Settings.invert_x else "+", "-" if Settings.invert_y else "+"]

func _cycle_axes() -> void:
	# 4 kombinacje odwrócenia osi (przydatne do dostrojenia czujnika na telefonie)
	var idx := int(Settings.invert_x) * 2 + int(Settings.invert_y)
	idx = (idx + 1) % 4
	Settings.invert_x = idx >= 2
	Settings.invert_y = idx % 2 == 1
	Settings.save()
	_update_axes_label()

func _flash(text: String, secs := 1.0) -> void:
	lbl_msg.text = text
	get_tree().create_timer(secs).timeout.connect(func():
		if state == "play":
			lbl_msg.text = "")

# ------------------------------------------------------------- budowa poziomu
func _load_level(n: int) -> void:
	level = n
	state = "play"
	elapsed = 0.0
	tilt = Vector2.ZERO
	lbl_msg.text = ""
	if level_root:
		level_root.queue_free()
	level_root = Node3D.new()
	add_child(level_root)

	grid = MazeLevels.get_level(n)
	rows = grid.size()
	cols = (grid[0] as String).length()
	holes.clear()

	var walls_body := StaticBody3D.new()
	walls_body.physics_material_override = _phys(0.4, 0.3)
	level_root.add_child(walls_body)

	var ox := -cols * CELL / 2.0 + CELL / 2.0
	var oz := -rows * CELL / 2.0 + CELL / 2.0
	for z in rows:
		var line: String = grid[z]
		for x in cols:
			var p := Vector3(ox + x * CELL, 0, oz + z * CELL)
			match line[x]:
				"#":
					_add_wall(walls_body, p, x, z)
				"S":
					start_pos = p
					_add_start(p)
				"G":
					goal_pos = p
					_add_goal(p)
				"O":
					holes.append(p)
					_add_hole(p)
	_add_board()
	_spawn_ball()
	_fit_camera()
	_update_ui()

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 24
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_wall(body: StaticBody3D, p: Vector3, x: int, z: int) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(CELL, WALL_H, CELL)
	cs.shape = bs
	cs.position = p + Vector3(0, WALL_H / 2.0, 0)
	body.add_child(cs)

	var root := Node3D.new()
	root.position = p
	level_root.add_child(root)
	match (x * 7 + z * 13 + x * z) % 4:
		0:  # układ scalony
			_box(root, Vector3(0.94, 0.55, 0.94), Vector3(0, 0.275, 0), mats.chip)
			_box(root, Vector3(0.14, 0.02, 0.14), Vector3(-0.3, 0.56, -0.3), mats.chip_mark)
		1:  # radiator
			_box(root, Vector3(0.94, 0.12, 0.94), Vector3(0, 0.06, 0), mats.alu)
			for i in 5:
				_box(root, Vector3(0.1, 0.6, 0.9), Vector3(-0.38 + i * 0.19, 0.42, 0), mats.alu)
		2:  # kondensator elektrolityczny
			_cyl(root, 0.45, 0.7, Vector3(0, 0.35, 0), mats.cap_body)
			_cyl(root, 0.4, 0.02, Vector3(0, 0.71, 0), mats.cap_top)
		3:  # listwa goldpin
			_box(root, Vector3(0.94, 0.45, 0.94), Vector3(0, 0.225, 0), mats.black)
			for ix in 2:
				for iz in 2:
					_cyl(root, 0.05, 0.2, Vector3(-0.22 + ix * 0.44, 0.55, -0.22 + iz * 0.44), mats.gold)

func _add_start(p: Vector3) -> void:
	_box(level_root, Vector3(0.9, 0.03, 0.9), p + Vector3(0, 0.015, 0), mats.silver)
	_box(level_root, Vector3(0.6, 0.035, 0.12), p + Vector3(0, 0.02, 0.25), mats.black)

func _add_goal(p: Vector3) -> void:
	_box(level_root, Vector3(0.94, 0.06, 0.94), p + Vector3(0, 0.03, 0), mats.gold)
	_box(level_root, Vector3(0.7, 0.07, 0.7), p + Vector3(0, 0.035, 0), mats.black)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.3
	ring.mesh = tm
	var rm := _mat(Color(0.1, 0.8, 0.4), 0.0, 0.4, Color(0.1, 1.0, 0.4), 2.5)
	ring.material_override = rm
	ring.position = p + Vector3(0, 0.08, 0)
	level_root.add_child(ring)
	var tw := level_root.create_tween().set_loops()
	tw.tween_property(rm, "emission_energy_multiplier", 5.0, 0.8)
	tw.tween_property(rm, "emission_energy_multiplier", 1.0, 0.8)

func _add_hole(p: Vector3) -> void:
	_cyl(level_root, HOLE_R + 0.04, 0.02, p + Vector3(0, 0.011, 0), mats.black)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = HOLE_R + 0.03
	tm.outer_radius = HOLE_R + 0.13
	ring.mesh = tm
	ring.material_override = mats.copper
	ring.position = p + Vector3(0, 0.02, 0)
	level_root.add_child(ring)

func _add_board() -> void:
	var w := cols * CELL + MARGIN * 2.0
	var d := rows * CELL + MARGIN * 2.0
	_box(level_root, Vector3(w, 0.2, d), Vector3(0, -0.1, 0), mats.pcb)

	var body := StaticBody3D.new()
	body.physics_material_override = _phys(0.8, 0.1)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 0.4, d)
	cs.shape = bs
	cs.position = Vector3(0, -0.2, 0)
	body.add_child(cs)
	level_root.add_child(body)

	# Sitodruk
	var lbl := Label3D.new()
	lbl.text = "MARBLE-MAZE  REV 2.1   LVL %02d" % level
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.9, 0.95, 0.9, 0.9)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(0, 0.011, d / 2.0 - MARGIN / 2.0)
	level_root.add_child(lbl)

	# Pulsujące diody LED na marginesie
	var colors := [Color(1, 0.15, 0.1), Color(0.1, 1, 0.3), Color(1, 0.7, 0.1), Color(0.2, 0.6, 1)]
	for i in 4:
		var lm := _mat(colors[i] * 0.4, 0.0, 0.3, colors[i], 3.0)
		var led := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.14
		led.mesh = sm
		led.material_override = lm
		led.position = Vector3(-w / 2.0 + 0.5 + i * 0.4, 0.05, -d / 2.0 + MARGIN / 2.0)
		level_root.add_child(led)
		var tw := level_root.create_tween().set_loops()
		tw.tween_property(lm, "emission_energy_multiplier", 4.5, 0.6 + i * 0.17)
		tw.tween_property(lm, "emission_energy_multiplier", 0.3, 0.6 + i * 0.17)

func _spawn_ball() -> void:
	ball = RigidBody3D.new()
	ball.mass = 0.5
	ball.continuous_cd = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 4
	ball.linear_damp = 0.25
	ball.angular_damp = 0.4
	ball.physics_material_override = _phys(0.7, 0.2)
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = BALL_R
	cs.shape = ss
	ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	mi.mesh = sm
	mi.material_override = mats.chrome
	ball.add_child(mi)
	level_root.add_child(ball)
	ball.global_position = start_pos + Vector3(0, BALL_R + 0.02, 0)
	ball.body_entered.connect(_on_ball_hit)

func _on_ball_hit(_b: Node) -> void:
	if prev_speed > 2.5:
		Settings.vibrate(int(clampf(prev_speed * 4.0, 10.0, 40.0)))

# ------------------------------------------------------------- sterowanie
func _calibrate() -> void:
	if OS.has_feature("mobile"):
		var g := Input.get_gravity()
		calib = Vector2(g.x, g.y)
	_flash("Skalibrowano", 0.8)

func _read_tilt() -> Vector2:
	var t := Vector2.ZERO
	if OS.has_feature("mobile"):
		var g := Input.get_gravity()
		var d := Vector2(g.x, g.y) - calib
		t = Vector2(-d.x, d.y) / 9.81
	else:
		t = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down") * 0.5
	if Settings.invert_x:
		t.x = -t.x
	if Settings.invert_y:
		t.y = -t.y
	t *= Settings.sensitivity
	t = t.limit_length(0.6)
	if t.length() < 0.02:
		t = Vector2.ZERO
	return t

func _process(delta: float) -> void:
	# Wizualny przechył planszy: obracamy kamerę przeciwnie do przechyłu
	cam_rig.rotation = Vector3(-tilt.y * 0.3, 0.0, tilt.x * 0.3)
	if state == "play":
		_update_ui()

func _physics_process(delta: float) -> void:
	if state != "play" or ball == null:
		return
	elapsed += delta
	tilt = tilt.lerp(_read_tilt(), 1.0 - exp(-delta * 14.0))
	ball.apply_central_force(Vector3(tilt.x, 0.0, tilt.y) * TILT_FORCE * ball.mass)
	prev_speed = ball.linear_velocity.length()

	var bp := ball.global_position
	var b2 := Vector2(bp.x, bp.z)
	if bp.y < -3.0:
		_reset_ball()
		return
	for h in holes:
		if b2.distance_to(Vector2(h.x, h.z)) < HOLE_R:
			_fall_into(h)
			return
	if b2.distance_to(Vector2(goal_pos.x, goal_pos.z)) < 0.3 and prev_speed < 7.0:
		_win()

func _fall_into(h: Vector3) -> void:
	state = "falling"
	Settings.vibrate(60)
	ball.freeze = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "global_position", h + Vector3(0, -0.6, 0), 0.35)
	tw.tween_property(ball, "scale", Vector3.ONE * 0.5, 0.35)
	await tw.finished
	if not is_inside_tree():
		return
	_reset_ball()

func _reset_ball() -> void:
	ball.freeze = true
	ball.scale = Vector3.ONE
	ball.global_position = start_pos + Vector3(0, BALL_R + 0.02, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = false
	tilt = Vector2.ZERO
	state = "play"

func _win() -> void:
	state = "won"
	ball.freeze = true
	var tw := create_tween()
	tw.tween_property(ball, "global_position", goal_pos + Vector3(0, BALL_R + 0.05, 0), 0.25)
	var record := Save.submit_time("marble", str(level), elapsed)
	lbl_msg.text = "UKOŃCZONO!\n%.1f s%s" % [elapsed, "\nNOWY REKORD" if record else ""]
	Settings.vibrate(90)
	await get_tree().create_timer(2.2).timeout
	if not is_inside_tree():
		return
	_load_level(level + 1)

func _go_menu() -> void:
	get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_menu()
