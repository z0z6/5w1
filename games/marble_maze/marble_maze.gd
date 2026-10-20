extends Node3D
## Marble Maze - chromowana kulka na płytce PCB, sterowanie przechyłem telefonu.
## Plansza jest budowana w całości z kodu (bez zewnętrznych assetów).
## Statyczna geometria jest scalana w kilka mesh-y (po jednym na materiał).

const CELL := 1.0
const WALL_H := 0.7
const BALL_R := 0.35
const TILT_FORCE := 30.0
const MARGIN := 0.7
const CAM_FOV := 40.0
const HOLE_R := 0.3
const ARC_PERIOD := 2.8     # okres zwarcia [s]
const ARC_ACTIVE := 0.7     # czas trwania łuku [s]
const ARC_WARN := 0.6       # ostrzeżenie przed łukiem [s]
const SHORT_PENALTY := 2.0  # kara czasowa za porażenie [s]

var level := 1
var grid: Array = []
var cols := 0
var rows := 0
var start_pos := Vector3.ZERO
var goal_pos := Vector3.ZERO
var holes: Array[Vector3] = []
var hazards: Array = []
var spark_spots: Array[Vector3] = []
var batches := {}

var level_root: Node3D
var ball: RigidBody3D
var cam_rig: Node3D
var camera: Camera3D
var ui: CanvasLayer
var overlay: Control
var lbl_info: Label
var lbl_msg: Label
var lbl_dbg: Label
var board_w := 0.0
var board_d := 0.0

var tilt := Vector2.ZERO
var calib := Vector2.ZERO
var state := "play"
var elapsed := 0.0
var prev_speed := 0.0
var last_hit_ms := 0
var last_shock_ms := -10000
var arc_tick := 0.0
var mats := {}

var spark_mesh: SphereMesh
var spark_grad: Gradient
var spark_curve: Curve
var flash_lights: Array[OmniLight3D] = []
var flash_idx := 0

func _ready() -> void:
	_make_materials()
	_setup_environment()
	_setup_camera()
	_setup_effects()
	_setup_ui()
	_load_level(clampi(Save.get_int("marble", "unlocked", 1), 1, MazeLevels.COUNT))
	get_tree().create_timer(0.8).timeout.connect(_calibrate)
	_schedule_ambient()

# ------------------------------------------------------------------ materiały
func _scale(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)

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
	mats.alu = _mat(Color(0.5, 0.52, 0.56), 0.9, 0.5)
	mats.cap_blue = _mat(Color(0.05, 0.12, 0.35), 0.2, 0.35)
	mats.cap_black = _mat(Color(0.03, 0.03, 0.04), 0.2, 0.4)
	mats.cap_top = _mat(Color(0.5, 0.52, 0.55), 0.8, 0.55)
	mats.gold = _mat(Color(0.95, 0.75, 0.3), 1.0, 0.25)
	mats.black = _mat(Color(0.01, 0.01, 0.01), 0.0, 1.0)
	mats.copper = _mat(Color(0.86, 0.55, 0.30), 1.0, 0.3)
	mats.chrome = _mat(Color(0.95, 0.96, 1.0), 0.95, 0.08)
	mats.silver = _mat(Color(0.52, 0.54, 0.58), 1.0, 0.45)
	mats.ferrite = _mat(Color(0.17, 0.16, 0.18), 0.3, 0.6)
	mats.relay = _mat(Color(0.08, 0.22, 0.62), 0.1, 0.35)
	mats.white = _mat(Color(0.9, 0.9, 0.86), 0.0, 0.6)
	mats.tantal = _mat(Color(0.92, 0.62, 0.08), 0.1, 0.5)
	mats.resistor = _mat(Color(0.72, 0.62, 0.42), 0.0, 0.6)
	mats.red_part = _mat(Color(0.6, 0.08, 0.08), 0.1, 0.4)
	mats.warn = _mat(Color(1.0, 0.8, 0.0), 0.0, 0.5, Color(1.0, 0.7, 0.0), 0.5)
	# Diody LED (3 kolory, każdy pulsuje we własnym rytmie)
	var led_cols := [Color(1.0, 0.15, 0.1), Color(0.1, 1.0, 0.3), Color(0.25, 0.6, 1.0)]
	var leds := []
	for c in led_cols:
		leds.append(_mat(_scale(c, 0.5), 0.0, 0.3, c, 2.0))
	mats.led = leds
	# Iskry: bez cieniowania, kolor z cząsteczki, jasność > 1 => poświata (glow)
	var sp := StandardMaterial3D.new()
	sp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp.vertex_color_use_as_albedo = true
	sp.albedo_color = Color(2.2, 2.2, 2.2)
	mats.spark = sp
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
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.42, 0.55)
	sm.sky_horizon_color = Color(0.55, 0.55, 0.55)
	sm.ground_horizon_color = Color(0.2, 0.2, 0.22)
	sm.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.3
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
	camera.fov = CAM_FOV
	cam_rig.add_child(camera)

func _fit_camera() -> void:
	# Kamera dokładnie z góry; labirynt wypełnia całą szerokość ekranu,
	# a płytka PCB (board_w x board_d) wypełnia resztę ekranu.
	var w := cols * CELL + 0.6
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_tan := tan(deg_to_rad(CAM_FOV / 2.0))
	var dist := (w / 2.0) / half_tan + WALL_H
	var half_w := dist * half_tan
	var half_h := half_w / aspect
	board_w = maxf(cols * CELL + MARGIN * 2.0, half_w * 2.0 * 1.35)
	board_d = maxf(rows * CELL + MARGIN * 2.0, half_h * 2.0 * 1.35)
	camera.position = Vector3(0, dist, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)

# -------------------------------------------------------- efekty (iskry, błyski)
func _setup_effects() -> void:
	spark_mesh = SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	spark_mesh.material = mats.spark
	spark_grad = Gradient.new()
	spark_grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	spark_grad.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	spark_grad.colors = PackedColorArray([
		Color(0.3, 0.9, 1.0), Color(1.0, 0.9, 0.3), Color(1.0, 0.3, 0.9),
		Color(1.0, 1.0, 1.0), Color(1.0, 0.5, 0.15)])
	spark_curve = Curve.new()
	spark_curve.add_point(Vector2(0, 1))
	spark_curve.add_point(Vector2(1, 0))
	for i in 2:
		var l := OmniLight3D.new()
		l.omni_range = 3.0
		l.light_energy = 0.0
		add_child(l)
		flash_lights.append(l)
	# pulsowanie diod LED (współdzielone materiały)
	var i := 0
	for m in mats.led:
		var tw := create_tween().set_loops()
		var t := 0.6 + i * 0.3
		tw.tween_property(m, "emission_energy_multiplier", 4.5, t)
		tw.tween_property(m, "emission_energy_multiplier", 0.3, t)
		i += 1

func _sparks(pos: Vector3, amount := 20, big := false) -> void:
	if not Settings.effects or level_root == null:
		return
	var p := CPUParticles3D.new()
	p.mesh = spark_mesh
	p.amount = amount
	p.lifetime = 0.7 if big else 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0 if big else 75.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 6.0 if big else 4.5
	p.gravity = Vector3(0, -7, 0)
	p.scale_amount_curve = spark_curve
	p.color_initial_ramp = spark_grad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	level_root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

func _light_flash(pos: Vector3, color: Color, energy := 2.5) -> void:
	if not Settings.effects:
		return
	var l := flash_lights[flash_idx]
	flash_idx = (flash_idx + 1) % flash_lights.size()
	l.global_position = pos + Vector3(0, 0.6, 0)
	l.light_color = color
	l.light_energy = energy
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.25)

func _rand_color() -> Color:
	return Color.from_hsv(randf(), 0.55, 1.0)

func _schedule_ambient() -> void:
	# Losowe "zwarcia" na elementach płytki + drobna wibracja, gdy są blisko kulki
	get_tree().create_timer(randf_range(1.0, 3.0)).timeout.connect(_ambient_short)

func _ambient_short() -> void:
	if state == "play" and Settings.effects and not spark_spots.is_empty() and ball != null and overlay == null:
		var spot: Vector3 = spark_spots[randi() % spark_spots.size()]
		_sparks(spot, 14)
		_light_flash(spot, _rand_color(), 1.6)
		var d := Vector2(spot.x - ball.global_position.x, spot.z - ball.global_position.z).length()
		if d < 4.0:
			Settings.vibrate(10)
	_schedule_ambient()

# ------------------------------------------------------------------------ UI
func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	lbl_info = Label.new()
	lbl_info.position = Vector2(24, 50)
	lbl_info.add_theme_font_size_override("font_size", 34)
	lbl_info.add_theme_color_override("font_color", Color("e8c9a0"))
	lbl_info.add_theme_constant_override("outline_size", 8)
	lbl_info.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_info)

	lbl_dbg = Label.new()
	lbl_dbg.position = Vector2(24, 100)
	lbl_dbg.add_theme_font_size_override("font_size", 22)
	lbl_dbg.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lbl_dbg.add_theme_constant_override("outline_size", 6)
	lbl_dbg.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_dbg)

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
	hb.offset_left = 16
	hb.offset_right = -16
	hb.add_theme_constant_override("separation", 10)
	ui.add_child(hb)
	hb.add_child(_btn("Menu", _go_menu))
	hb.add_child(_btn("Kalibruj", _calibrate))
	hb.add_child(_btn("Poziomy", _open_levels))
	hb.add_child(_btn("Opcje", _open_options))
	_apply_options()

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(b, 26)
	b.pressed.connect(cb)
	return b

func _apply_options() -> void:
	(mats.pcb as ShaderMaterial).set_shader_parameter("anim", 1.0 if Settings.effects else 0.0)
	lbl_dbg.visible = Settings.show_debug

func _update_ui() -> void:
	var best := Save.get_best("marble", str(level))
	var best_txt := "--" if best == 0.0 else "%.1f s" % best
	lbl_info.text = "POZIOM %d/%d   %.1f s   rekord: %s" % [level, MazeLevels.COUNT, elapsed, best_txt]

func _flash(text: String, secs := 1.0) -> void:
	lbl_msg.text = text
	get_tree().create_timer(secs).timeout.connect(func():
		if state == "play":
			lbl_msg.text = "")

func _show_overlay(c: Control) -> void:
	overlay = c
	ui.add_child(c)
	get_tree().paused = true

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	get_tree().paused = false
	_apply_options()

func _open_options() -> void:
	if overlay:
		return
	var panel := OptionsPanel.new()
	panel.closed.connect(_close_overlay)
	_show_overlay(panel)

func _open_levels() -> void:
	if overlay:
		return
	var root := Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.03, 0.02, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 80
	box.offset_bottom = -50
	box.add_theme_constant_override("separation", 20)
	root.add_child(box)
	var title := Label.new()
	title.text = "POZIOMY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("d9a066"))
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var gc := GridContainer.new()
	gc.columns = 5
	gc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gc.add_theme_constant_override("h_separation", 12)
	gc.add_theme_constant_override("v_separation", 12)
	scroll.add_child(gc)
	var unlocked := Save.get_int("marble", "unlocked", 1)
	for i in range(1, MazeLevels.COUNT + 1):
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(110, 110)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = i > unlocked
		UiKit.style_button(b, 36)
		b.pressed.connect(func():
			_close_overlay()
			_load_level(i))
		gc.add_child(b)
	var close := Button.new()
	close.text = "Zamknij"
	close.custom_minimum_size = Vector2(0, 100)
	UiKit.style_button(close, 36)
	close.pressed.connect(_close_overlay)
	box.add_child(close)
	_show_overlay(root)

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
	hazards.clear()
	spark_spots.clear()
	batches.clear()

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
				"Z":
					_add_hazard(p, x, z)
	_fit_camera()
	_add_board()
	_flush_batches(level_root)
	_spawn_ball()
	_apply_options()
	_update_ui()

# --- scalanie geometrii: jeden mesh na materiał ---------------------------------
func _batch(mat: Material) -> SurfaceTool:
	if not batches.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[mat] = st
	return batches[mat]

func _b_box(mat: Material, size: Vector3, pos: Vector3) -> void:
	var m := BoxMesh.new()
	m.size = size
	_batch(mat).append_from(m, 0, Transform3D(Basis.IDENTITY, pos))

func _b_cyl(mat: Material, r: float, h: float, pos: Vector3, seg := 14) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_batch(mat).append_from(m, 0, Transform3D(Basis.IDENTITY, pos))

func _b_torus(mat: Material, inner: float, outer: float, pos: Vector3) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 8
	_batch(mat).append_from(m, 0, Transform3D(Basis.IDENTITY, pos))

func _flush_batches(parent: Node3D) -> void:
	for mat in batches:
		var st: SurfaceTool = batches[mat]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		parent.add_child(mi)
	batches.clear()

func _hash2(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)

# --- ściany: 12 rodzajów elementów elektronicznych -------------------------------
func _add_wall(body: StaticBody3D, p: Vector3, x: int, z: int) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(CELL, WALL_H, CELL)
	cs.shape = bs
	cs.position = p + Vector3(0, WALL_H / 2.0, 0)
	body.add_child(cs)
	var kind := int(_hash2(x * 3.0 + 1.0, z * 5.0 + 2.0) * 12.0) % 12
	_wall_part(kind, p, x + z)
	if (x * 7 + z * 3) % 4 == 0:
		spark_spots.append(p + Vector3(0, 0.75, 0))

func _wall_part(kind: int, p: Vector3, variant: int) -> void:
	match kind:
		0:  # układ DIP z nóżkami
			_b_box(mats.chip, Vector3(0.82, 0.5, 0.94), p + Vector3(0, 0.25, 0))
			_b_box(mats.chip_mark, Vector3(0.12, 0.02, 0.12), p + Vector3(-0.25, 0.51, -0.34))
			for i in 5:
				var zz := -0.36 + i * 0.18
				_b_box(mats.silver, Vector3(0.12, 0.05, 0.09), p + Vector3(-0.46, 0.12, zz))
				_b_box(mats.silver, Vector3(0.12, 0.05, 0.09), p + Vector3(0.46, 0.12, zz))
		1:  # radiator
			_b_box(mats.alu, Vector3(0.94, 0.12, 0.94), p + Vector3(0, 0.06, 0))
			for i in 5:
				_b_box(mats.alu, Vector3(0.1, 0.6, 0.9), p + Vector3(-0.38 + i * 0.19, 0.42, 0))
		2:  # kondensator elektrolityczny (niebieski lub czarny)
			var body_mat: Material = mats.cap_blue if variant % 2 == 0 else mats.cap_black
			_b_cyl(body_mat, 0.45, 0.7, p + Vector3(0, 0.35, 0), 20)
			_b_cyl(mats.cap_top, 0.4, 0.02, p + Vector3(0, 0.71, 0), 20)
			_b_box(mats.chip, Vector3(0.5, 0.012, 0.04), p + Vector3(0, 0.725, 0))
			_b_box(mats.chip, Vector3(0.04, 0.012, 0.5), p + Vector3(0, 0.725, 0))
		3:  # listwa goldpin
			_b_box(mats.black, Vector3(0.94, 0.45, 0.94), p + Vector3(0, 0.225, 0))
			for ix in 2:
				for iz in 3:
					_b_cyl(mats.gold, 0.045, 0.2, p + Vector3(-0.2 + ix * 0.4, 0.55, -0.3 + iz * 0.3), 8)
		4:  # dławik toroidalny (miedziane uzwojenie)
			_b_box(mats.black, Vector3(0.94, 0.08, 0.94), p + Vector3(0, 0.04, 0))
			_b_torus(mats.copper, 0.17, 0.47, p + Vector3(0, 0.3, 0))
			_b_torus(mats.copper, 0.17, 0.47, p + Vector3(0, 0.52, 0))
		5:  # rezonator kwarcowy
			_b_box(mats.black, Vector3(0.94, 0.1, 0.94), p + Vector3(0, 0.05, 0))
			_b_box(mats.silver, Vector3(0.52, 0.5, 0.86), p + Vector3(0, 0.35, 0))
			_b_box(mats.chip_mark, Vector3(0.3, 0.01, 0.4), p + Vector3(0, 0.61, 0))
		6:  # transformator z rdzeniem ferrytowym
			_b_box(mats.ferrite, Vector3(0.92, 0.6, 0.92), p + Vector3(0, 0.3, 0))
			_b_box(mats.copper, Vector3(0.95, 0.22, 0.6), p + Vector3(0, 0.34, 0))
			_b_box(mats.gold, Vector3(0.95, 0.04, 0.62), p + Vector3(0, 0.48, 0))
		7:  # przekaźnik
			_b_box(mats.black, Vector3(0.94, 0.08, 0.94), p + Vector3(0, 0.04, 0))
			_b_box(mats.relay, Vector3(0.9, 0.58, 0.72), p + Vector3(0, 0.37, 0))
			_b_box(mats.white, Vector3(0.6, 0.012, 0.4), p + Vector3(0, 0.67, 0))
		8:  # złącze USB / RJ45
			_b_box(mats.silver, Vector3(0.94, 0.62, 0.94), p + Vector3(0, 0.31, 0))
			_b_box(mats.black, Vector3(0.7, 0.3, 0.06), p + Vector3(0, 0.32, 0.46))
			_b_box(mats.gold, Vector3(0.5, 0.04, 0.04), p + Vector3(0, 0.2, 0.49))
		9:  # wskaźnik LED (pulsuje)
			_b_box(mats.black, Vector3(0.94, 0.2, 0.94), p + Vector3(0, 0.1, 0))
			_b_cyl(mats.led[variant % 3], 0.3, 0.4, p + Vector3(0, 0.4, 0), 16)
		10:  # bateria kondensatorów MLCC
			_b_box(mats.black, Vector3(0.94, 0.1, 0.94), p + Vector3(0, 0.05, 0))
			for ix in 2:
				for iz in 2:
					_b_box(mats.tantal, Vector3(0.36, 0.5, 0.36), p + Vector3(-0.22 + ix * 0.44, 0.35, -0.22 + iz * 0.44))
		_:  # tranzystor TO-220 z radiatorkiem
			_b_box(mats.alu, Vector3(0.94, 0.1, 0.94), p + Vector3(0, 0.05, 0))
			_b_box(mats.chip, Vector3(0.6, 0.55, 0.3), p + Vector3(0, 0.37, 0.1))
			_b_box(mats.silver, Vector3(0.6, 0.7, 0.08), p + Vector3(0, 0.4, -0.12))
			for i in 3:
				_b_box(mats.silver, Vector3(0.06, 0.1, 0.2), p + Vector3(-0.2 + i * 0.2, 0.15, 0.4))

# --- start, meta, otwory, zwarcia -------------------------------------------------
func _add_start(p: Vector3) -> void:
	_b_box(mats.gold, Vector3(0.94, 0.03, 0.94), p + Vector3(0, 0.015, 0))
	_b_box(mats.black, Vector3(0.8, 0.035, 0.8), p + Vector3(0, 0.02, 0))

func _add_goal(p: Vector3) -> void:
	_b_box(mats.gold, Vector3(0.94, 0.06, 0.94), p + Vector3(0, 0.03, 0))
	_b_box(mats.black, Vector3(0.7, 0.07, 0.7), p + Vector3(0, 0.035, 0))
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
	_b_cyl(mats.black, HOLE_R + 0.04, 0.02, p + Vector3(0, 0.011, 0), 24)
	_b_torus(mats.copper, HOLE_R + 0.03, HOLE_R + 0.13, p + Vector3(0, 0.02, 0))

func _add_hazard(p: Vector3, gx: int, gz: int) -> void:
	# Pole ostrzegawcze + dwie elektrody; między nimi okresowo przeskakuje łuk.
	_b_box(mats.warn, Vector3(0.94, 0.012, 0.05), p + Vector3(0, 0.006, 0.46))
	_b_box(mats.warn, Vector3(0.94, 0.012, 0.05), p + Vector3(0, 0.006, -0.46))
	var root := Node3D.new()
	root.position = p
	# łuk ma przecinać korytarz poprzecznie
	var line: String = grid[gz]
	if gx > 0 and line[gx - 1] != "#" or gx < cols - 1 and line[gx + 1] != "#":
		root.rotation.y = PI / 2.0
	level_root.add_child(root)
	var em := _mat(Color(0.9, 0.7, 0.3), 1.0, 0.3, Color(1.0, 0.3, 0.1), 1.0)
	em.emission_energy_multiplier = 0.2
	for sgn in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.08
		cm.bottom_radius = 0.08
		cm.height = 0.3
		cm.radial_segments = 10
		e.mesh = cm
		e.material_override = em
		e.position = Vector3(sgn * 0.42, 0.15, 0)
		root.add_child(e)
	var arc := Node3D.new()
	arc.visible = false
	root.add_child(arc)
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = Color(2.2, 2.2, 2.2)
	var segs: Array = []
	for i in 5:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.04, 0.04)
		mi.mesh = bm
		mi.material_override = arc_mat
		arc.add_child(mi)
		segs.append(mi)
	hazards.append({
		"pos": p, "off": hazards.size() * 0.97, "arc": arc, "segs": segs,
		"arc_mat": arc_mat, "em": em, "was": false})
	spark_spots.append(p + Vector3(0, 0.2, 0))

func _reroll_arc(h: Dictionary) -> void:
	var segs: Array = h.segs
	for i in segs.size():
		var s: MeshInstance3D = segs[i]
		s.position = Vector3(-0.4 + i * 0.2, randf_range(0.1, 0.28), randf_range(-0.07, 0.07))
		s.rotation = Vector3(0.0, randf_range(-0.5, 0.5), randf_range(-0.6, 0.6))
	var c := _rand_color()
	(h.arc_mat as StandardMaterial3D).albedo_color = Color(c.r * 2.4, c.g * 2.4, c.b * 2.4)

func _update_hazards(delta: float) -> void:
	if hazards.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	arc_tick -= delta
	var reroll := false
	if arc_tick <= 0.0:
		arc_tick = 0.05
		reroll = true
	for h in hazards:
		var ph := fposmod(t + h.off, ARC_PERIOD)
		var active := ph < ARC_ACTIVE
		var em: StandardMaterial3D = h.em
		if active:
			em.emission_energy_multiplier = 6.0
		elif ph > ARC_PERIOD - ARC_WARN:
			em.emission_energy_multiplier = 0.4 + 3.0 * (ph - (ARC_PERIOD - ARC_WARN)) / ARC_WARN
		else:
			em.emission_energy_multiplier = 0.2
		h.arc.visible = active
		if active and reroll:
			_reroll_arc(h)
		if active and not h.was:
			_on_arc_start(h)
		h.was = active

func _on_arc_start(h: Dictionary) -> void:
	var pos: Vector3 = h.pos
	_sparks(pos + Vector3(0, 0.2, 0), 16)
	_light_flash(pos, _rand_color(), 2.0)
	if ball != null:
		var d := Vector2(pos.x - ball.global_position.x, pos.z - ball.global_position.z).length()
		if d < 3.5:
			Settings.vibrate(10)

func _shock(h: Dictionary) -> void:
	last_shock_ms = Time.get_ticks_msec()
	var pos: Vector3 = h.pos
	var dir := ball.global_position - pos
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	dir = dir.normalized()
	ball.linear_velocity = dir * 5.0
	elapsed += SHORT_PENALTY
	_sparks(ball.global_position, 40, true)
	_light_flash(ball.global_position, Color(1.0, 0.9, 0.5), 3.5)
	Settings.vibrate(45)
	_flash("ZWARCIE!  +%d s" % int(SHORT_PENALTY), 0.7)

# --- płytka i dekoracje ----------------------------------------------------------
func _add_board() -> void:
	var w := board_w
	var d := board_d
	var mw := cols * CELL + MARGIN * 2.0   # rozmiar samego labiryntu z ramką
	var md := rows * CELL + MARGIN * 2.0
	var pcb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.2, d)
	pcb.mesh = bm
	pcb.position = Vector3(0, -0.1, 0)
	pcb.material_override = mats.pcb
	level_root.add_child(pcb)
	_add_decor(mw, md)

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
	lbl.position = Vector3(0, 0.011, md / 2.0 - MARGIN / 2.0)
	level_root.add_child(lbl)

	# Diody LED na marginesie (pulsują wspólnymi materiałami)
	for i in 4:
		_b_cyl(mats.led[i % 3], 0.09, 0.1, Vector3(-mw / 2.0 + 0.5 + i * 0.4, 0.05, -md / 2.0 + MARGIN / 2.0), 10)

func _in_maze(gx: float, gz: float, mw: float, md: float) -> bool:
	return absf(gx) < mw / 2.0 + 0.2 and absf(gz) < md / 2.0 + 0.2

func _free_cells(gx: int, gz: int, n: int, occ: Dictionary, mw: float, md: float, xm: int, zm: int) -> bool:
	for ix in n:
		for iz in n:
			var cx := gx + ix
			var cz := gz + iz
			if occ.has(Vector2i(cx, cz)) or _in_maze(cx, cz, mw, md) or absi(cx) > xm or absi(cz) > zm:
				return false
	return true

func _occupy(gx: int, gz: int, n: int, occ: Dictionary) -> void:
	for ix in n:
		for iz in n:
			occ[Vector2i(gx + ix, gz + iz)] = true

func _add_decor(mw: float, md: float) -> void:
	# Elementy poza labiryntem - tylko wizualne, bez kolizji.
	var occ := {}
	var xm := int(board_w / 2.0)
	var zm := int(board_d / 2.0)
	for gz in range(-zm, zm + 1):
		for gx in range(-xm, xm + 1):
			if occ.has(Vector2i(gx, gz)) or _in_maze(gx, gz, mw, md):
				continue
			var h := _hash2(gx * 1.7 + 3.0, gz * 2.3 + 1.0)
			var pos := Vector3(gx, 0, gz)
			if h < 0.05:
				if _free_cells(gx, gz, 2, occ, mw, md, xm, zm):
					_occupy(gx, gz, 2, occ)
					_decor_qfp(pos + Vector3(0.5, 0, 0.5))
			elif h < 0.10:
				_decor_cap(pos, h)
			elif h < 0.15:
				_decor_soic(pos)
			elif h < 0.20:
				_b_box(mats.black, Vector3(0.7, 0.04, 0.95), pos + Vector3(0, 0.02, 0))
				_b_box(mats.silver, Vector3(0.5, 0.16, 0.8), pos + Vector3(0, 0.12, 0))
			elif h < 0.26:
				for i in 3:
					var zz := -0.3 + i * 0.3
					_b_box(mats.resistor, Vector3(0.3, 0.08, 0.18), pos + Vector3(0, 0.05, zz))
					_b_box(mats.silver, Vector3(0.06, 0.09, 0.2), pos + Vector3(-0.17, 0.05, zz))
					_b_box(mats.silver, Vector3(0.06, 0.09, 0.2), pos + Vector3(0.17, 0.05, zz))
			elif h < 0.30:
				_b_box(mats.black, Vector3(0.9, 0.12, 0.9), pos + Vector3(0, 0.06, 0))
				for ix in 2:
					for iz in 2:
						_b_cyl(mats.gold, 0.045, 0.1, pos + Vector3(-0.2 + ix * 0.4, 0.15, -0.2 + iz * 0.4), 8)
			elif h < 0.34:
				_b_box(mats.white, Vector3(0.34, 0.05, 0.22), pos + Vector3(0, 0.025, 0))
				_b_cyl(mats.led[int(h * 100.0) % 3], 0.11, 0.16, pos + Vector3(0, 0.12, 0), 10)
			elif h < 0.38:
				_b_box(mats.tantal, Vector3(0.4, 0.22, 0.56), pos + Vector3(0, 0.11, 0))
				_b_box(mats.chip, Vector3(0.1, 0.225, 0.58), pos + Vector3(-0.15, 0.11, 0))
			elif h < 0.41:
				_b_cyl(mats.gold, 0.2, 0.3, pos + Vector3(0, 0.15, 0), 6)
				_b_cyl(mats.silver, 0.08, 0.02, pos + Vector3(0, 0.31, 0), 8)
			elif h < 0.44:
				_b_box(mats.red_part, Vector3(0.7, 0.2, 0.5), pos + Vector3(0, 0.1, 0))
				_b_box(mats.silver, Vector3(0.08, 0.04, 0.5), pos + Vector3(0.38, 0.04, 0))

func _decor_qfp(c: Vector3) -> void:
	_b_box(mats.chip, Vector3(1.5, 0.14, 1.5), c + Vector3(0, 0.07, 0))
	_b_box(mats.chip_mark, Vector3(0.14, 0.015, 0.14), c + Vector3(-0.55, 0.15, -0.55))
	_b_box(mats.silver, Vector3(1.72, 0.04, 0.1), c + Vector3(0, 0.03, 0.8))
	_b_box(mats.silver, Vector3(1.72, 0.04, 0.1), c + Vector3(0, 0.03, -0.8))
	_b_box(mats.silver, Vector3(0.1, 0.04, 1.72), c + Vector3(0.8, 0.03, 0))
	_b_box(mats.silver, Vector3(0.1, 0.04, 1.72), c + Vector3(-0.8, 0.03, 0))
	spark_spots.append(c + Vector3(0, 0.2, 0))

func _decor_cap(pos: Vector3, h: float) -> void:
	var m: Material = mats.cap_blue if h < 0.075 else mats.cap_black
	_b_cyl(m, 0.32, 0.32, pos + Vector3(0, 0.16, 0), 16)
	_b_cyl(mats.cap_top, 0.27, 0.02, pos + Vector3(0, 0.33, 0), 16)
	spark_spots.append(pos + Vector3(0, 0.35, 0))

func _decor_soic(pos: Vector3) -> void:
	_b_box(mats.chip, Vector3(0.8, 0.12, 0.5), pos + Vector3(0, 0.06, 0))
	_b_box(mats.chip_mark, Vector3(0.08, 0.015, 0.08), pos + Vector3(-0.3, 0.13, -0.15))
	_b_box(mats.silver, Vector3(0.92, 0.03, 0.08), pos + Vector3(0, 0.02, 0.29))
	_b_box(mats.silver, Vector3(0.92, 0.03, 0.08), pos + Vector3(0, 0.02, -0.29))
	spark_spots.append(pos + Vector3(0, 0.15, 0))

# --- kulka -----------------------------------------------------------------------
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
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.4, 0)
	glow.omni_range = 4.0
	glow.light_energy = 0.35
	ball.add_child(glow)
	level_root.add_child(ball)
	ball.global_position = start_pos + Vector3(0, BALL_R + 0.02, 0)
	ball.body_entered.connect(_on_ball_hit)

func _on_ball_hit(_b: Node) -> void:
	if prev_speed > 2.5:
		Settings.vibrate(int(clampf(prev_speed * 4.0, 10.0, 40.0)))
		var now := Time.get_ticks_msec()
		if prev_speed > 3.0 and now - last_hit_ms > 150:
			last_hit_ms = now
			_sparks(ball.global_position, 10)
			_light_flash(ball.global_position, _rand_color(), 1.2)

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
	_update_hazards(delta)
	if state == "play":
		_update_ui()
	if lbl_dbg.visible:
		var g := Input.get_gravity()
		lbl_dbg.text = "g=(%.1f, %.1f, %.1f)  tilt=(%.2f, %.2f)" % [g.x, g.y, g.z, tilt.x, tilt.y]

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
	# porażenie łukiem
	var now := Time.get_ticks_msec()
	if now - last_shock_ms > 900:
		for hz in hazards:
			if hz.arc.visible:
				var hp: Vector3 = hz.pos
				if b2.distance_to(Vector2(hp.x, hp.z)) < 0.55:
					_shock(hz)
					break
	if b2.distance_to(Vector2(goal_pos.x, goal_pos.z)) < 0.3 and prev_speed < 7.0:
		_win()

func _fall_into(h: Vector3) -> void:
	state = "falling"
	Settings.vibrate(60)
	_sparks(h + Vector3(0, 0.1, 0), 30, true)
	_light_flash(h, Color(1.0, 0.2, 0.1), 3.0)
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
	var unlocked := Save.get_int("marble", "unlocked", 1)
	if level >= unlocked:
		Save.set_int("marble", "unlocked", mini(level + 1, MazeLevels.COUNT))
	var last := level >= MazeLevels.COUNT
	lbl_msg.text = "UKOŃCZONO!\n%.1f s%s" % [elapsed, "\nNOWY REKORD" if record else ""]
	if last:
		lbl_msg.text += "\nWSZYSTKIE POZIOMY!"
	Settings.vibrate(90)
	var gp := goal_pos + Vector3(0, 0.3, 0)
	_sparks(gp, 60, true)
	_light_flash(goal_pos, Color(0.4, 1.0, 0.6), 3.5)
	get_tree().create_timer(0.35).timeout.connect(func():
		_sparks(gp, 50, true)
		_light_flash(goal_pos, Color(1.0, 0.8, 0.3), 3.0))
	await get_tree().create_timer(2.4).timeout
	if not is_inside_tree():
		return
	if last:
		_go_menu()
	else:
		_load_level(level + 1)

func _go_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if overlay:
			_close_overlay()
		else:
			_go_menu()
