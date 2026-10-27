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
const ARC_PERIOD := 3.2     # okres zwarcia [s]
const ARC_ACTIVE := 0.9     # czas trwania łuku [s]
const ARC_WARN := 0.8       # ostrzeżenie przed łukiem [s]
const SHORT_PENALTY := 2.0  # kara czasowa za porażenie [s]
const CONDUCTIVE := [1, 2, 3, 4, 5, 8, 11]   # rodzaje ścian, na które chętnie przeskakują wyładowania
const BUS_PALETTES := [
	[Color(1.0, 0.85, 0.4), Color(1.0, 0.6, 0.15)],
	[Color(1.0, 0.78, 0.3), Color(0.95, 0.5, 0.1)],
	[Color(1.0, 0.9, 0.55), Color(1.0, 0.7, 0.2)],
]
const TRACE_PPU := 44.0     # rozdzielczość tekstury ścieżek [px / jednostkę]
const TRACE_CELL := 5       # rozmiar komórki trasowania [px]
# Power-upy: good = pomaga (zielona obwódka), !good = przeszkadza (czerwona)
const PU := {
	"jumper": {"name": "ZWORKA", "desc": "uratuje Cię przed jedną dziurą", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.9)},
	"insul": {"name": "IZOLATOR", "desc": "odporność na zwarcia 13 s", "good": true, "dur": 13.0, "col": Color(0.4, 0.7, 1.0)},
	"heat": {"name": "RADIATOR", "desc": "kulka hamuje - łatwiej sterować 10 s", "good": true, "dur": 10.0, "col": Color(0.75, 0.9, 1.0)},
	"scan": {"name": "SKANER", "desc": "pokazuje drogę do CPU 8 s", "good": true, "dur": 8.0, "col": Color(0.85, 1.0, 0.2)},
	"batt": {"name": "BATERIA", "desc": "-4 s z czasu", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.35)},
	"surge": {"name": "PRZEPIĘCIE", "desc": "kulka przyspiesza 10 s", "good": false, "dur": 10.0, "col": Color(1.0, 0.25, 0.1)},
	"rev": {"name": "ODWROTNA POLARYZACJA", "desc": "sterowanie odwrócone 9 s", "good": false, "dur": 9.0, "col": Color(0.85, 0.35, 1.0)},
	"emi": {"name": "ZAKŁÓCENIA", "desc": "szarpie kulką 10 s", "good": false, "dur": 10.0, "col": Color(1.0, 0.6, 0.1)},
	"mine": {"name": "MINA", "desc": "wstrząs i +3 s kary", "good": false, "dur": 0.0, "col": Color(1.0, 0.1, 0.15)},
}

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
var kit: PcbKit

var ox := 0.0
var oz := 0.0
var wall_kinds := {}
var solid: Array = []
var bus_mats: Array = []
var powerups: Array = []
var fx := {"insul": 0.0, "heat": 0.0, "scan": 0.0, "surge": 0.0, "rev": 0.0, "emi": 0.0}
var jumper := false
var jumper_ms := -10000
var emi_timer := 0.0
var emi_buzz := 0.0
var scan_timer := 0.0
var path_mi: MeshInstance3D
var ball_mat: ShaderMaterial
var shield: MeshInstance3D
var ball_light: OmniLight3D
var charge := 0.0
var charge_goal := 1.0
var corona_t := 0.0
var ball_arc: Node3D
var arc_segs: Array = []
var arc_jit: Array = []
var arc_mat: StandardMaterial3D
var arc_time := 0.0
var arc_reroll := 0.0
var arc_target := Vector3.ZERO
var lbl_fx: RichTextLabel
var lbl_toast: Label
var toast_tw: Tween
var fx_text_cache := "?"

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
	get_tree().create_timer(0.8).timeout.connect(func(): _calibrate(true))
	_schedule_ambient()
	Audio.play_music("marble")

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
	var ballm := ShaderMaterial.new()
	ballm.shader = load("res://common/shaders/ball.gdshader")
	mats.ball = ballm
	var busm := ShaderMaterial.new()
	busm.shader = load("res://common/shaders/bus.gdshader")
	mats.bus = busm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(3.2, 2.8, 0.5)
	mats.path = pm
	var shm := StandardMaterial3D.new()
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.albedo_color = Color(0.3, 0.7, 1.0, 0.4)
	shm.emission_enabled = true
	shm.emission = Color(0.3, 0.7, 1.0)
	shm.emission_energy_multiplier = 1.6
	mats.shield = shm
	mats.silver = _mat(Color(0.52, 0.54, 0.58), 1.0, 0.45)
	mats.ferrite = _mat(Color(0.17, 0.16, 0.18), 0.3, 0.6)
	mats.relay = _mat(Color(0.08, 0.22, 0.62), 0.1, 0.35)
	mats.white = _mat(Color(0.9, 0.9, 0.86), 0.0, 0.6)
	mats.tantal = _mat(Color(0.92, 0.62, 0.08), 0.1, 0.5)
	mats.resistor = _mat(Color(0.72, 0.62, 0.42), 0.0, 0.6)
	mats.red_part = _mat(Color(0.6, 0.08, 0.08), 0.1, 0.4)
	mats.ribbon = _mat(Color(0.055, 0.04, 0.025), 0.0, 0.75)
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
	sp.albedo_color = Color(3.0, 3.0, 3.0)
	mats.spark = sp
	var sm := ShaderMaterial.new()
	sm.shader = load("res://common/shaders/pcb.gdshader")
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
	spark_mesh.radius = 0.055
	spark_mesh.height = 0.11
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
		l.omni_range = 4.0
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
	p.amount = int(amount * 1.5)
	p.lifetime = 1.3 if big else 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0 if big else 75.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 7.5 if big else 5.5
	p.gravity = Vector3(0, -5, 0)
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
	l.light_energy = energy * 1.4
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)

func _rand_color() -> Color:
	return Color.from_hsv(randf(), 0.55, 1.0)

func _schedule_ambient() -> void:
	# Losowe "zwarcia" na elementach płytki + drobna wibracja, gdy są blisko kulki
	get_tree().create_timer(randf_range(1.0, 3.0)).timeout.connect(_ambient_short)

func _ambient_short() -> void:
	if state == "play" and Settings.effects and not spark_spots.is_empty() and ball != null and overlay == null:
		var spot: Vector3 = spark_spots[randi() % spark_spots.size()]
		_sparks(spot, 22)
		_light_flash(spot, _rand_color(), 2.4)
		var d := Vector2(spot.x - ball.global_position.x, spot.z - ball.global_position.z).length()
		if d < 6.0:
			Audio.play_sfx("spark", -4.0 - d * 2.0, randf_range(0.85, 1.25))
		if d < 4.0:
			Settings.vibrate(10)
	_schedule_ambient()

# ------------------------------------------------------------------------ UI
func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	lbl_info = Label.new()
	lbl_info.position = Vector2(20, 54)
	lbl_info.add_theme_font_size_override("font_size", 16)
	lbl_info.add_theme_color_override("font_color", Color("e8c9a0"))
	lbl_info.add_theme_constant_override("outline_size", 8)
	lbl_info.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_info)

	lbl_fx = RichTextLabel.new()
	lbl_fx.bbcode_enabled = true
	lbl_fx.fit_content = true
	lbl_fx.scroll_active = false
	lbl_fx.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_fx.position = Vector2(20, 90)
	lbl_fx.custom_minimum_size = Vector2(672, 40)
	lbl_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_fx.add_theme_font_size_override("normal_font_size", 16)
	lbl_fx.add_theme_constant_override("outline_size", 6)
	lbl_fx.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_fx)

	lbl_toast = Label.new()
	lbl_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_toast.offset_top = 230
	lbl_toast.offset_bottom = 330
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.add_theme_font_size_override("font_size", 24)
	lbl_toast.add_theme_constant_override("outline_size", 10)
	lbl_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.modulate.a = 0.0
	ui.add_child(lbl_toast)

	lbl_dbg = Label.new()
	lbl_dbg.position = Vector2(20, 130)
	lbl_dbg.add_theme_font_size_override("font_size", 16)
	lbl_dbg.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lbl_dbg.add_theme_constant_override("outline_size", 6)
	lbl_dbg.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_dbg)

	lbl_msg = Label.new()
	lbl_msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_font_size_override("font_size", 40)
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	hb.add_child(_btn("MENU", _go_menu, "back"))
	hb.add_child(_btn("KALIBR.", _calibrate))
	hb.add_child(_btn("POZIOMY", _open_levels))
	hb.add_child(_btn("OPCJE", _open_options))
	_apply_options()

func _btn(text: String, cb: Callable, snd := "click") -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(b, 16, UiKit.C_CYAN)
	b.pressed.connect(func():
		Audio.play_sfx(snd)
		cb.call())
	return b

func _apply_options() -> void:
	for m in bus_mats:
		(m as ShaderMaterial).set_shader_parameter("anim", 1.0 if Settings.effects else 0.0)
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
	Audio.set_roll(0.0)
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
	dim.color = Color(0.03, 0.0, 0.1, 0.94)
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
	var title := UiKit.label("POZIOMY", 40, UiKit.C_YELLOW, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		UiKit.style_button(b, 24, UiKit.C_CYAN)
		b.pressed.connect(func():
			Audio.play_sfx("click")
			_close_overlay()
			_load_level(i))
		gc.add_child(b)
	var close := Button.new()
	close.text = "ZAMKNIJ"
	close.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(close, 24, UiKit.C_GREEN)
	close.pressed.connect(func():
		Audio.play_sfx("back")
		_close_overlay())
	box.add_child(close)
	_show_overlay(root)

# ------------------------------------------------------------- budowa poziomu
func _load_level(n: int) -> void:
	level = n
	state = "play"
	elapsed = 0.0
	tilt = Vector2.ZERO
	lbl_msg.text = ""
	fx = {"insul": 0.0, "heat": 0.0, "scan": 0.0, "surge": 0.0, "rev": 0.0, "emi": 0.0}
	jumper = false
	charge = 0.0
	arc_time = 0.0
	if level_root:
		level_root.queue_free()
	level_root = Node3D.new()
	add_child(level_root)
	kit = PcbKit.new(level_root)

	grid = MazeLevels.get_level(n)
	rows = grid.size()
	cols = (grid[0] as String).length()
	holes.clear()
	hazards.clear()
	spark_spots.clear()
	batches.clear()
	wall_kinds.clear()
	bus_mats.clear()
	powerups.clear()
	solid = []
	for gy in rows:
		var srow := []
		var sline: String = grid[gy]
		for gx in cols:
			srow.append(1 if sline[gx] == "#" else 0)
		solid.append(srow)

	var walls_body := StaticBody3D.new()
	walls_body.physics_material_override = _phys(0.4, 0.3)
	level_root.add_child(walls_body)

	ox = -cols * CELL / 2.0 + CELL / 2.0
	oz = -rows * CELL / 2.0 + CELL / 2.0
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
	kit.flush(level_root)
	spark_spots.append_array(kit.spark_spots)
	_spawn_ball()
	_place_powerups()
	_apply_options()
	_update_ui()
	Audio.play_sfx("level")

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
	wall_kinds[Vector2i(x, z)] = kind
	kit.begin_part(p, 0.0)
	kit.part(kind, x + z)
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
	_sparks(pos + Vector3(0, 0.2, 0), 24)
	_light_flash(pos, _rand_color(), 3.0)
	if ball != null:
		var d := Vector2(pos.x - ball.global_position.x, pos.z - ball.global_position.z).length()
		if d < 7.0:
			Audio.play_sfx("buzz", -3.0 - d * 1.5, randf_range(0.9, 1.1))
		if d < 3.5:
			Settings.vibrate(10)

func _shock(h: Dictionary) -> void:
	_shock_at(h.pos, SHORT_PENALTY, "ZWARCIE!  +%d s" % int(SHORT_PENALTY))

func _shock_at(pos: Vector3, penalty: float, text: String, snd := "shock") -> void:
	last_shock_ms = Time.get_ticks_msec()
	Audio.play_sfx(snd)
	var dir := ball.global_position - pos
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	dir = dir.normalized()
	ball.linear_velocity = dir * 5.0
	elapsed += penalty
	_sparks(ball.global_position, 40, true)
	_light_flash(ball.global_position, Color(1.0, 0.9, 0.5), 3.5)
	Settings.vibrate(45)
	_flash(text, 0.7)

# --- płytka i dekoracje ----------------------------------------------------------
func _add_board() -> void:
	var w := board_w
	var d := board_d
	var mw := cols * CELL + MARGIN * 2.0   # rozmiar samego labiryntu z ramką
	var md := rows * CELL + MARGIN * 2.0
	var pcb_mat := mats.pcb as ShaderMaterial
	pcb_mat.set_shader_parameter("trace_tex", _make_trace_texture(w, d))
	pcb_mat.set_shader_parameter("board_size", Vector2(w, d))
	pcb_mat.set_shader_parameter("maze_half", Vector2(cols * CELL / 2.0 + MARGIN, rows * CELL / 2.0 + MARGIN))
	var pcb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.2, d)
	pcb.mesh = bm
	pcb.position = Vector3(0, -0.1, 0)
	pcb.material_override = mats.pcb
	level_root.add_child(pcb)
	var occ := _add_buses(mw, md)
	kit.add_decor(mw, md, occ, board_w, board_d)

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

func _add_decor(mw: float, md: float, occ: Dictionary) -> void:
	# Elementy poza labiryntem - tylko wizualne, bez kolizji.
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
	ball_mat = mats.ball
	ball_mat.set_shader_parameter("charge", 0.3)
	ball_mat.set_shader_parameter("flash", 0.0)
	mi.material_override = ball_mat
	ball.add_child(mi)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.4, 0)
	glow.omni_range = 4.0
	glow.light_energy = 0.35
	glow.light_color = Color(1.0, 0.3, 0.22)
	ball.add_child(glow)
	ball_light = glow
	# bańka izolatora
	shield = MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = BALL_R * 1.55
	shm.height = BALL_R * 3.1
	shm.radial_segments = 24
	shm.rings = 12
	shield.mesh = shm
	shield.material_override = mats.shield
	shield.visible = false
	ball.add_child(shield)
	level_root.add_child(ball)
	_make_ball_arc()
	_make_path_node()
	ball.global_position = start_pos + Vector3(0, BALL_R + 0.02, 0)
	ball.body_entered.connect(_on_ball_hit)

func _on_ball_hit(_b: Node) -> void:
	if prev_speed > 2.5:
		Settings.vibrate(int(clampf(prev_speed * 4.0, 10.0, 40.0)))
		Audio.play_sfx("hit", linear_to_db(clampf(prev_speed / 8.0, 0.15, 1.0)), randf_range(0.85, 1.2))
		var now := Time.get_ticks_msec()
		if prev_speed > 3.0 and now - last_hit_ms > 150:
			last_hit_ms = now
			_sparks(ball.global_position, 16)
			_light_flash(ball.global_position, _rand_color(), 2.0)

# ------------------------------------------------------------- sterowanie
func _calibrate(quiet := false) -> void:
	if OS.has_feature("mobile"):
		var g := Input.get_gravity()
		calib = Vector2(g.x, g.y)
	_flash("SKALIBROWANO", 0.8)
	if not quiet:
		Audio.play_sfx("calib")

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
	if fx.rev > 0.0:
		t = -t
	t *= Settings.sensitivity
	t = t.limit_length(0.6)
	if t.length() < 0.02:
		t = Vector2.ZERO
	return t

func _process(delta: float) -> void:
	# Wizualny przechył planszy: obracamy kamerę przeciwnie do przechyłu
	cam_rig.rotation = Vector3(-tilt.y * 0.3, 0.0, tilt.x * 0.3)
	if fx.emi > 0.0:
		cam_rig.position = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.06
	else:
		cam_rig.position = Vector3.ZERO
	_update_hazards(delta)
	_update_ball_arc(delta)
	_animate_powerups(delta)
	_update_fx_text()
	if state == "play":
		_update_ui()
	if lbl_dbg.visible:
		var g := Input.get_gravity()
		lbl_dbg.text = "g=(%.1f, %.1f, %.1f)  tilt=(%.2f, %.2f)" % [g.x, g.y, g.z, tilt.x, tilt.y]

func _physics_process(delta: float) -> void:
	if state != "play" or ball == null:
		Audio.set_roll(0.0)
		return
	elapsed += delta
	tilt = tilt.lerp(_read_tilt(), 1.0 - exp(-delta * 14.0))
	var mul := _tick_effects(delta)
	ball.apply_central_force(Vector3(tilt.x, 0.0, tilt.y) * TILT_FORCE * mul * ball.mass)
	prev_speed = ball.linear_velocity.length()
	Audio.set_roll(prev_speed)

	var bp := ball.global_position
	var b2 := Vector2(bp.x, bp.z)
	if bp.y < -3.0:
		_reset_ball()
		return
	var now := Time.get_ticks_msec()
	for h in holes:
		if b2.distance_to(Vector2(h.x, h.z)) < HOLE_R:
			if jumper:
				_jumper_save(h)
			elif now - jumper_ms > 700:
				_fall_into(h)
				return
			break
	# porażenie łukiem
	if now - last_shock_ms > 900 and fx.insul <= 0.0:
		for hz in hazards:
			if hz.arc.visible:
				var hp: Vector3 = hz.pos
				if b2.distance_to(Vector2(hp.x, hp.z)) < 0.55:
					_shock(hz)
					break
	_collect_powerups(b2)
	_update_charge(delta)
	if b2.distance_to(Vector2(goal_pos.x, goal_pos.z)) < 0.3 and prev_speed < 7.0:
		_win()

func _fall_into(h: Vector3) -> void:
	state = "falling"
	Settings.vibrate(60)
	Audio.play_sfx("hole")
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
	Audio.set_roll(0.0)
	Audio.play_sfx("win")
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
	Audio.set_roll(0.0)
	Audio.play_music("menu")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if overlay:
			_close_overlay()
		else:
			_go_menu()

# =============================================================== magistrale
func _add_buses(mw: float, md: float) -> Dictionary:
	# Wiązki równoległych ścieżek poza labiryntem, podłączone do ścian przez sloty.
	var occ := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = level * 31 + 7
	for side in [-1, 1]:
		var xi := 1
		while xi < cols - 1:
			if rng.randf() < 0.3:
				xi += 1
				continue
			var wc: int = [1, 1, 2, 2, 3][rng.randi() % 5]
			if xi + wc > cols - 1:
				break
			_make_bus(side, xi, wc, rng, occ)
			xi += wc + rng.randi_range(1, 2)
	return occ

func _make_bus(side: int, xi: int, wc: int, rng: RandomNumberGenerator, occ: Dictionary) -> void:
	var cx := ox + (xi + (wc - 1) / 2.0) * CELL
	var z_wall := oz if side < 0 else oz + (rows - 1) * CELL
	var z0 := z_wall + side * 1.0                # zewnętrzna krawędź slotu
	var avail := board_d / 2.0 - absf(z0) - 0.3
	if avail < 2.0:
		return
	var length := minf(rng.randf_range(3.0, 11.0), avail)
	var chip := length < avail - 1.2
	var z_end := z0 + side * length
	var half := wc * CELL / 2.0

	# slot (gniazdo) przy ścianie: czarna obudowa, złote styki, zatrzaski, dioda
	_b_box(mats.black, Vector3(wc * CELL - 0.06, 0.2, 0.46), Vector3(cx, 0.1, z_wall + side * 0.73))
	_b_box(mats.gold, Vector3(wc * CELL - 0.3, 0.215, 0.1), Vector3(cx, 0.1075, z_wall + side * 0.9))
	_b_box(mats.silver, Vector3(0.14, 0.24, 0.5), Vector3(cx - half + 0.1, 0.12, z_wall + side * 0.73))
	_b_box(mats.silver, Vector3(0.14, 0.24, 0.5), Vector3(cx + half - 0.1, 0.12, z_wall + side * 0.73))
	_b_cyl(mats.led[rng.randi() % 3], 0.07, 0.1, Vector3(cx, 0.22, z_wall + side * 0.62), 8)
	spark_spots.append(Vector3(cx, 0.25, z_wall + side * 0.75))

	# parametry wiązki: szyna zasilania / magistrala danych / cienka wiązka
	var lanes := wc * 9
	var pitch := 0.1
	var lane_w := 0.06
	if rng.randi() % 2 == 0:
		lanes = wc * 12
		pitch = 0.075
		lane_w = 0.045
	# nieprzezroczysty podkład pod przewodami: zakrywa ścieżki i pady płytki w tym miejscu
	_b_box(mats.ribbon, Vector3(wc * CELL - 0.06, 0.004, length), Vector3(cx, 0.002, z0 + side * length / 2.0))
	var mi := MeshInstance3D.new()
	mi.mesh = _bus_mesh(cx, z0, side, lanes, pitch, lane_w, length)
	var m := (mats.bus as ShaderMaterial).duplicate() as ShaderMaterial
	var pal: Array = BUS_PALETTES[rng.randi() % BUS_PALETTES.size()]
	m.set_shader_parameter("glow_a", pal[0])
	m.set_shader_parameter("glow_b", pal[1])
	m.set_shader_parameter("speed", rng.randf_range(1.0, 2.5))
	m.set_shader_parameter("intensity", rng.randf_range(0.6, 1.1))
	m.set_shader_parameter("dir", 1.0 if rng.randf() < 0.5 else -1.0)
	m.set_shader_parameter("anim", 1.0 if Settings.effects else 0.0)
	mi.material_override = m
	level_root.add_child(mi)
	bus_mats.append(m)

	# układ na końcu magistrali
	var tail := 0.0
	if chip:
		var zc := z_end + side * 0.7
		var w := wc * CELL + 0.3
		_b_box(mats.chip, Vector3(w, 0.14, 1.2), Vector3(cx, 0.07, zc))
		_b_box(mats.silver, Vector3(w + 0.2, 0.04, 0.12), Vector3(cx, 0.03, z_end + side * 0.08))
		_b_box(mats.chip_mark, Vector3(0.14, 0.015, 0.14), Vector3(cx - w / 2.0 + 0.2, 0.15, zc - side * 0.4))
		spark_spots.append(Vector3(cx, 0.2, zc))
		tail = 1.4

	# zajęte komórki - dekoracje ich nie nadpiszą
	var za := roundi(minf(z0, z_end + side * tail))
	var zb := roundi(maxf(z0, z_end + side * tail))
	for xc in range(xi, xi + wc):
		var gx := roundi(ox + xc * CELL)
		for gz in range(za, zb + 1):
			occ[Vector2i(gx, gz)] = true

func _bus_mesh(cx: float, z0: float, side: int, lanes: int, pitch: float, lane_w: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z1 := z0 + side * length
	for i in lanes:
		var x := cx + (i - (lanes - 1) / 2.0) * pitch
		var xa := x - lane_w / 2.0
		var xb := x + lane_w / 2.0
		var corners := [Vector3(xa, 0.006, z0), Vector3(xb, 0.006, z0), Vector3(xb, 0.006, z1), Vector3(xa, 0.006, z1)]
		var uvs := [Vector2(0, i), Vector2(0, i + 0.999), Vector2(length, i + 0.999), Vector2(length, i)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(corners[idx])
	return st.commit()

# ============================================== ładunki elektrostatyczne kulki
func _cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi((pos.x - ox) / CELL), 0, cols - 1), clampi(roundi((pos.z - oz) / CELL), 0, rows - 1))

func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(ox + c.x * CELL, 0.0, oz + c.y * CELL)

func _make_ball_arc() -> void:
	ball_arc = Node3D.new()
	ball_arc.visible = false
	level_root.add_child(ball_arc)
	arc_mat = StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.albedo_color = Color(1.5, 2.4, 2.8)
	arc_segs.clear()
	arc_jit.clear()
	for i in 7:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.035, 1.0)
		mi.mesh = bm
		mi.material_override = arc_mat
		ball_arc.add_child(mi)
		arc_segs.append(mi)
		arc_jit.append(Vector3.ZERO)

func _update_charge(delta: float) -> void:
	if not Settings.effects:
		ball_mat.set_shader_parameter("charge", 0.2)
		ball_arc.visible = false
		return
	charge += delta * (0.4 + prev_speed * 0.18)
	var c := clampf(charge / charge_goal, 0.0, 1.0)
	ball_mat.set_shader_parameter("charge", 0.35 + 0.65 * c)
	ball_light.light_energy = (0.45 + c * 0.7) * randf_range(0.75, 1.35)
	# korona: drobne iskry wokół kulki, gdy jest mocno naładowana i się toczy
	corona_t -= delta
	if corona_t <= 0.0 and c > 0.4 and prev_speed > 0.8:
		corona_t = randf_range(0.15, 0.4)
		_sparks(ball.global_position + Vector3(0, 0.2, 0), 5)
	if charge >= charge_goal and arc_time <= 0.0:
		var tp := _pick_wall_target()
		if tp != Vector3.INF:
			_discharge(tp)

func _wall_hit_point(wp: Vector3, bp: Vector3) -> Vector3:
	var toward := Vector3(bp.x - wp.x, 0.0, bp.z - wp.z).normalized()
	return wp + Vector3(0, 0.45, 0) + toward * 0.45

func _pick_wall_target() -> Vector3:
	var bp := ball.global_position
	var c := _cell_of(bp)
	var cands: Array = []
	var total := 0.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var cc := Vector2i(c.x + dx, c.y + dy)
			if cc.x < 0 or cc.y < 0 or cc.x >= cols or cc.y >= rows:
				continue
			if (grid[cc.y] as String)[cc.x] != "#":
				continue
			var wp := _cell_pos(cc)
			var d := Vector2(wp.x - bp.x, wp.z - bp.z).length()
			if d > 3.2 or d < 0.6:
				continue
			var w := 1.0 / (d * d)
			if int(wall_kinds.get(cc, 0)) in CONDUCTIVE:
				w *= 3.0
			cands.append([wp, w])
			total += w
	if cands.is_empty():
		return Vector3.INF
	var r := randf() * total
	for e in cands:
		r -= float(e[1])
		if r <= 0.0:
			return _wall_hit_point(e[0], bp)
	return _wall_hit_point(cands[0][0], bp)

func _discharge(tp: Vector3) -> void:
	arc_target = tp
	arc_time = 0.45
	arc_reroll = 0.0
	charge = 0.0
	charge_goal = randf_range(0.6, 1.2)
	_sparks(tp, 24)
	_light_flash(tp, Color(0.6, 0.9, 1.0), 3.0)
	Settings.vibrate(10)
	Audio.play_sfx("discharge", -4.0, randf_range(0.9, 1.15))
	var tw := create_tween()
	tw.tween_method(func(v: float): ball_mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.6)

func _update_ball_arc(delta: float) -> void:
	if ball_arc == null or ball == null:
		return
	if arc_time <= 0.0:
		ball_arc.visible = false
		return
	arc_time -= delta
	ball_arc.visible = true
	if arc_reroll <= 0.0:
		arc_reroll = 0.04
		for i in arc_jit.size():
			arc_jit[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.16
		var c := _rand_color()
		arc_mat.albedo_color = Color(c.r * 2.0 + 0.6, c.g * 2.0 + 0.6, c.b * 2.0 + 0.6)
	arc_reroll -= delta
	var a := ball.global_position
	var n := arc_segs.size()
	var prev := a
	for i in n:
		var nxt := a.lerp(arc_target, float(i + 1) / n)
		if i < n - 1:
			nxt += arc_jit[i]
		_place_segment(arc_segs[i], prev, nxt)
		prev = nxt

func _place_segment(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var seg_len := d.length()
	if seg_len < 0.001:
		seg.visible = false
		return
	seg.visible = true
	var dn := d / seg_len
	var up := Vector3.UP if absf(dn.y) < 0.98 else Vector3.RIGHT
	seg.transform = Transform3D(Basis.looking_at(dn, up) * Basis.from_scale(Vector3(1, 1, seg_len)), (a + b) / 2.0)

# ====================================================================== power-upy
func _make_path_node() -> void:
	path_mi = MeshInstance3D.new()
	path_mi.material_override = mats.path
	path_mi.visible = false
	level_root.add_child(path_mi)

func _place_powerups() -> void:
	if level < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := _cell_of(start_pos)
	var g := _cell_of(goal_pos)
	var cand: Array[Vector2i] = []
	for y in rows:
		var line: String = grid[y]
		for x in cols:
			if line[x] != ".":
				continue
			if absi(x - s.x) + absi(y - s.y) < 4 or absi(x - g.x) + absi(y - g.y) < 3:
				continue
			cand.append(Vector2i(x, y))
	var count := clampi(1 + floori(level / 4.0), 1, 5)
	var good_types := ["jumper", "insul", "heat", "scan", "batt"]
	var bad_types := ["surge", "rev", "emi", "mine"]
	for i in count:
		if cand.is_empty():
			break
		var idx := rng.randi() % cand.size()
		var c: Vector2i = cand[idx]
		cand.remove_at(idx)
		var type: String
		if rng.randf() < 0.6:
			type = good_types[rng.randi() % good_types.size()]
		else:
			type = bad_types[rng.randi() % bad_types.size()]
		var pos := _cell_pos(c)
		var node := _build_pickup(type, pos)
		level_root.add_child(node)
		powerups.append({"type": type, "pos": pos, "node": node})

func _build_pickup(type: String, pos: Vector3) -> Node3D:
	var info: Dictionary = PU[type]
	var col: Color = info.col
	var root := Node3D.new()
	root.position = pos
	# podstawka: zielona = pomaga, czerwona = przeszkadza
	var ring_col := Color(0.2, 1.0, 0.4) if info.good else Color(1.0, 0.15, 0.1)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.26
	rm.outer_radius = 0.36
	rm.rings = 20
	rm.ring_segments = 8
	ring.mesh = rm
	ring.material_override = _mat(_scale(ring_col, 0.3), 0.0, 0.4, ring_col, 2.5)
	ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.38, 0)
	root.add_child(body)
	var mat := _mat(_scale(col, 0.4), 0.2, 0.3, col, 2.2)
	match type:
		"jumper":
			_pu_mesh(body, _box_mesh(Vector3(0.36, 0.16, 0.16)), mat, Vector3.ZERO)
			_pu_mesh(body, _box_mesh(Vector3(0.08, 0.12, 0.08)), mats.black, Vector3(-0.1, -0.12, 0))
			_pu_mesh(body, _box_mesh(Vector3(0.08, 0.12, 0.08)), mats.black, Vector3(0.1, -0.12, 0))
		"insul":
			var sm := SphereMesh.new()
			sm.radius = 0.17
			sm.height = 0.34
			_pu_mesh(body, sm, mat, Vector3.ZERO)
		"heat":
			for i in 3:
				_pu_mesh(body, _box_mesh(Vector3(0.38, 0.05, 0.38)), mat, Vector3(0, -0.1 + i * 0.1, 0))
		"scan":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.1
			tm.outer_radius = 0.2
			tm.rings = 20
			tm.ring_segments = 8
			_pu_mesh(body, tm, mat, Vector3.ZERO)
		"batt":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.12
			cm.bottom_radius = 0.12
			cm.height = 0.3
			cm.radial_segments = 12
			_pu_mesh(body, cm, mat, Vector3.ZERO)
			_pu_mesh(body, _box_mesh(Vector3(0.1, 0.05, 0.1)), mats.silver, Vector3(0, 0.17, 0))
		"surge":
			var pm := CylinderMesh.new()
			pm.top_radius = 0.22
			pm.bottom_radius = 0.22
			pm.height = 0.3
			pm.radial_segments = 3
			_pu_mesh(body, pm, mat, Vector3.ZERO)
		"rev":
			var dm := CylinderMesh.new()
			dm.top_radius = 0.24
			dm.bottom_radius = 0.24
			dm.height = 0.12
			dm.radial_segments = 4
			_pu_mesh(body, dm, mat, Vector3.ZERO)
		"emi":
			for i in 3:
				var sm2 := SphereMesh.new()
				sm2.radius = 0.08
				sm2.height = 0.16
				_pu_mesh(body, sm2, mat, Vector3(cos(i * TAU / 3.0) * 0.14, 0, sin(i * TAU / 3.0) * 0.14))
		_:  # mina
			var sm3 := SphereMesh.new()
			sm3.radius = 0.15
			sm3.height = 0.3
			_pu_mesh(body, sm3, mat, Vector3.ZERO)
			for ax in 3:
				var sz := Vector3(0.5, 0.05, 0.05)
				var sp := _pu_mesh(body, _box_mesh(sz), mat, Vector3.ZERO)
				sp.rotation = [Vector3(0, 0, 0), Vector3(0, PI / 2, 0), Vector3(0, 0, PI / 2)][ax]
	return root

func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _pu_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _animate_powerups(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var i := 0
	for pu in powerups:
		var body: Node3D = (pu.node as Node3D).get_node("Body")
		body.position.y = 0.38 + sin(t * 3.0 + i) * 0.05
		body.rotation.y += delta * 2.0
		i += 1

func _collect_powerups(b2: Vector2) -> void:
	for i in range(powerups.size() - 1, -1, -1):
		var pu: Dictionary = powerups[i]
		var pp: Vector3 = pu.pos
		if b2.distance_to(Vector2(pp.x, pp.z)) < 0.5:
			powerups.remove_at(i)
			_collect(pu)

func _collect(pu: Dictionary) -> void:
	var type: String = pu.type
	var info: Dictionary = PU[type]
	(pu.node as Node3D).queue_free()
	var pos: Vector3 = pu.pos
	var good: bool = info.good
	_sparks(pos + Vector3(0, 0.3, 0), 24, true)
	_light_flash(pos, Color(0.4, 1.0, 0.6) if good else Color(1.0, 0.3, 0.2), 2.5)
	Settings.vibrate(25)
	if type != "mine":
		Audio.play_sfx("pu_good" if good else "pu_bad")
	match type:
		"jumper":
			jumper = true
		"batt":
			elapsed = maxf(0.0, elapsed - 4.0)
		"mine":
			_shock_at(ball.global_position, 3.0, "MINA!  +3 s", "mine")
		_:
			fx[type] = float(info.dur)
	if type == "scan":
		scan_timer = 0.0
		Audio.play_sfx("scan", -2.0)
	_toast("%s\n%s" % [info.name, info.desc], good)

func _toast(text: String, good: bool) -> void:
	lbl_toast.text = text
	lbl_toast.add_theme_color_override("font_color", Color("7dffb0") if good else Color("ff6a5a"))
	if toast_tw:
		toast_tw.kill()
	lbl_toast.modulate.a = 1.0
	toast_tw = create_tween()
	toast_tw.tween_interval(2.8)
	toast_tw.tween_property(lbl_toast, "modulate:a", 0.0, 0.5)

func _jumper_save(h: Vector3) -> void:
	jumper = false
	jumper_ms = Time.get_ticks_msec()
	Audio.play_sfx("jumper")
	var dir := ball.global_position - h
	dir.y = 0.0
	if dir.length() < 0.05:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	ball.linear_velocity = dir.normalized() * 5.0
	_sparks(h + Vector3(0, 0.2, 0), 30, true)
	_light_flash(h, Color(0.3, 1.0, 0.9), 3.0)
	Settings.vibrate(30)
	_toast("ZWORKA uratowała kulkę!", true)

func _tick_effects(delta: float) -> float:
	for k in fx:
		if fx[k] > 0.0:
			fx[k] = maxf(0.0, fx[k] - delta)
	var mul := 1.0
	var damp := 0.25
	if fx.heat > 0.0:
		mul *= 0.9
		damp = 1.4
	if fx.surge > 0.0:
		mul *= 1.7
		damp = 0.05
	ball.linear_damp = damp
	if fx.emi > 0.0:
		emi_timer -= delta
		if emi_timer <= 0.0:
			emi_timer = 0.12
			var v := Vector2.from_angle(randf() * TAU) * 0.35
			ball.apply_central_impulse(Vector3(v.x, 0.0, v.y))
		emi_buzz -= delta
		if emi_buzz <= 0.0:
			emi_buzz = 0.35
			Settings.vibrate(10)
			Audio.play_sfx("emi", -6.0, randf_range(0.8, 1.3))
	shield.visible = fx.insul > 0.0
	if fx.scan > 0.0:
		scan_timer -= delta
		if scan_timer <= 0.0:
			scan_timer = 0.4
			_update_scan_path()
		path_mi.visible = true
	else:
		path_mi.visible = false
	return mul

func _update_scan_path() -> void:
	var ci := _cell_of(ball.global_position)
	var gc := _cell_of(goal_pos)
	var blocked := {}
	for h in holes:
		blocked[_cell_of(h)] = true
	var prev := MazeLevels._bfs(solid, cols, rows, ci, gc, blocked)
	if not prev.has(gc):
		path_mi.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := gc
	var n := 0
	while c != ci and n < 500:
		var m := CylinderMesh.new()
		m.top_radius = 0.13
		m.bottom_radius = 0.13
		m.height = 0.03
		m.radial_segments = 8
		m.rings = 1
		st.append_from(m, 0, Transform3D(Basis.IDENTITY, _cell_pos(c) + Vector3(0, 0.03, 0)))
		c = prev[c]
		n += 1
	path_mi.mesh = st.commit()

func _update_fx_text() -> void:
	var parts := PackedStringArray()
	if jumper:
		parts.append("[color=#7dffb0]ZWORKA[/color]")
	for k in fx:
		if fx[k] > 0.0:
			var info: Dictionary = PU[k]
			var colr := "#7dffb0" if info.good else "#ff6a5a"
			parts.append("[color=%s]%s %d s[/color]" % [colr, info.name, ceili(fx[k])])
	var txt := "   ".join(parts)
	if txt != fx_text_cache:
		fx_text_cache = txt
		lbl_fx.text = txt

# ================================================ spójne ścieżki PCB (tekstura)
# Trasowanie "Manhattan": długie ścieżki ze ściętymi narożnikami (45°), często w wiązkach
# równoległych, każda zakończona padem - dzięki temu układ wygląda na spójny, bez ślepych uliczek.
# Kanały tekstury: R = ścieżka, G = pad, B = otwór w padzie.
func _make_trace_texture(w_units: float, d_units: float) -> ImageTexture:
	var wpx := clampi(int(ceil(w_units * TRACE_PPU)), 64, 4096)
	var hpx := clampi(int(ceil(d_units * TRACE_PPU)), 64, 4096)
	var img := Image.create_empty(wpx, hpx, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = level * 977 + 5
	var gw := wpx / TRACE_CELL
	var gh := hpx / TRACE_CELL
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var pads: Array[Vector2i] = []
	var nets := int(gw * gh / 160.0)
	var half_x := (cols * CELL / 2.0 + MARGIN) * TRACE_PPU / TRACE_CELL
	var half_y := (rows * CELL / 2.0 + MARGIN) * TRACE_PPU / TRACE_CELL
	for n in nets:
		var k: int = [1, 1, 2, 3, 4, 6][rng.randi() % 6]        # ile równoległych ścieżek
		var cur := Vector2i(rng.randi_range(6, gw - 7), rng.randi_range(6, gh - 7))
		# w obrębie labiryntu zostaje tylko ~20% startów -> rzadka sieć, nie przeszkadza w śledzeniu kulki
		if absf(cur.x - gw / 2.0) < half_x and absf(cur.y - gh / 2.0) < half_y and rng.randf() > 0.2:
			continue
		var d := rng.randi() % 4
		var pts: Array[Vector2i] = [cur]
		for r in rng.randi_range(2, 5):
			var run := rng.randi_range(14, 46)
			var nxt := cur + dirs[d] * run
			nxt.x = clampi(nxt.x, 5, gw - 6)
			nxt.y = clampi(nxt.y, 5, gh - 6)
			if absi(nxt.x - cur.x) + absi(nxt.y - cur.y) < 12:
				break
			pts.append(nxt)
			cur = nxt
			d = (d + (1 if rng.randf() < 0.5 else 3)) % 4
		if pts.size() < 2:
			continue
		var spacing := 2 if rng.randf() < 0.7 else 3
		for j in k:
			var off := (j - (k - 1) / 2.0) * spacing
			var pv := _offset_polyline(pts, off)
			_draw_poly(img, pv, 3, 2 * TRACE_CELL)
			pads.append(pv[0])
			pads.append(pv[pv.size() - 1])
			# przelotki w zakrętach co jakiś czas
			if pv.size() > 2 and rng.randf() < 0.25:
				pads.append(pv[1 + rng.randi() % (pv.size() - 2)])
	for pc in pads:
		_draw_pad(img, pc)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# przesunięcie łamanej o off komórek w bok (kąty proste) -> wierzchołki w pikselach
func _offset_polyline(pts: Array[Vector2i], off: float) -> Array[Vector2i]:
	var n := pts.size()
	var normals: Array[Vector2] = []
	for i in n - 1:
		var v := Vector2(signi(pts[i + 1].x - pts[i].x), signi(pts[i + 1].y - pts[i].y))
		normals.append(Vector2(-v.y, v.x))
	var out: Array[Vector2i] = []
	for i in n:
		var o := Vector2.ZERO
		if i == 0:
			o = normals[0]
		elif i == n - 1:
			o = normals[n - 2]
		else:
			o = normals[i - 1] + normals[i]
		var p := Vector2(pts[i]) + o * off
		out.append(Vector2i(roundi(p.x * TRACE_CELL + TRACE_CELL / 2.0), roundi(p.y * TRACE_CELL + TRACE_CELL / 2.0)))
	return out

func _draw_poly(img: Image, pv: Array[Vector2i], t: int, chamfer: int) -> void:
	var path: Array[Vector2i] = [pv[0]]
	for i in range(1, pv.size() - 1):
		var a := pv[i - 1]
		var p := pv[i]
		var b := pv[i + 1]
		var da := Vector2i(signi(p.x - a.x), signi(p.y - a.y))
		var db := Vector2i(signi(b.x - p.x), signi(b.y - p.y))
		var la := absi(p.x - a.x) + absi(p.y - a.y)
		var lb := absi(b.x - p.x) + absi(b.y - p.y)
		if la > 2 * chamfer and lb > 2 * chamfer:
			path.append(p - da * chamfer)
			path.append(p + db * chamfer)
		else:
			path.append(p)
	path.append(pv[pv.size() - 1])
	for i in path.size() - 1:
		_draw_seg(img, path[i], path[i + 1], t)

func _draw_seg(img: Image, a: Vector2i, b: Vector2i, t: int) -> void:
	var col := Color(1, 0, 0)
	if a.x == b.x or a.y == b.y:
		img.fill_rect(Rect2i(mini(a.x, b.x) - t / 2, mini(a.y, b.y) - t / 2, absi(a.x - b.x) + t, absi(a.y - b.y) + t), col)
		return
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for s in steps + 1:
		var x := a.x + roundi(float(b.x - a.x) * s / steps)
		var y := a.y + roundi(float(b.y - a.y) * s / steps)
		img.fill_rect(Rect2i(x - t / 2, y - t / 2, t, t), col)

func _draw_pad(img: Image, c: Vector2i) -> void:
	_disc(img, c, 5, Color(1, 1, 0))
	_disc(img, c, 2, Color(1, 1, 1))

func _disc(img: Image, c: Vector2i, r: int, col: Color) -> void:
	for dy in range(-r, r + 1):
		var dx := int(sqrt(float(r * r - dy * dy)))
		img.fill_rect(Rect2i(c.x - dx, c.y + dy, 2 * dx + 1, 1), col)
