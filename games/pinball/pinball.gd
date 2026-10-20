extends Node3D
## Pinball - stół na płytce PCB, czerwona kulka z ładunkiem elektrostatycznym, flippery sterowane dotykiem
## (lewa / prawa połowa ekranu), prawa połowa ładuje sprężynę wyrzutni. Fizyka: Jolt (RigidBody3D, oś Y zablokowana).

const BALL_R := 0.3
const G_TABLE := 5.5                  # "nachylenie stołu": przyspieszenie w dół stołu (+Z)
const MAX_SPEED := 24.0
const CAM_FOV := 40.0
const WALL_H := 0.7
const FLIP_LEN := 1.65
const FLIP_REST := 0.5236             # 30° (czubek w dół)
const FLIP_UP := 0.4887               # 28° (czubek w górę)
const FLIP_SPEED_UP := 16.0
const FLIP_SPEED_DOWN := 12.0
const ARCH_C := Vector2(0.1, -5.1)    # środek łuku (X, Z)
const ARCH_R := 5.35                  # promień osi ściany łuku
const BALL_START := Vector3(4.55, 0.3, 9.76)
const DRAIN_Z := 10.7
const MULT_MAX := 5

const PU := {
	"jumper": {"name": "ZWORKA", "desc": "ratuje kulkę przed odpływem", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.9)},
	"multi": {"name": "MULTIBALL", "desc": "+2 kulki na stole", "good": true, "dur": 0.0, "col": Color(0.4, 1.0, 0.4)},
	"x2": {"name": "PODWÓJNE PUNKTY", "desc": "x2 przez 15 s", "good": true, "dur": 15.0, "col": Color(1.0, 0.85, 0.2)},
	"big": {"name": "DUŻE FLIPERY", "desc": "dłuższe łapy 14 s", "good": true, "dur": 14.0, "col": Color(0.75, 0.9, 1.0)},
	"batt": {"name": "BATERIA", "desc": "+1000 punktów", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.35)},
	"small": {"name": "MAŁE FLIPERY", "desc": "krótsze łapy 12 s", "good": false, "dur": 12.0, "col": Color(1.0, 0.45, 0.1)},
	"emi": {"name": "ZAKŁÓCENIA", "desc": "szarpie kulkami 10 s", "good": false, "dur": 10.0, "col": Color(1.0, 0.6, 0.1)},
	"swap": {"name": "ZAMIANA PRZYCISKÓW", "desc": "lewy i prawy flipper 10 s", "good": false, "dur": 10.0, "col": Color(0.85, 0.35, 1.0)},
	"mine": {"name": "MINA", "desc": "wstrząs i -500 punktów", "good": false, "dur": 0.0, "col": Color(1.0, 0.1, 0.15)},
}
const PU_SPOTS := [
	Vector2(-2.8, -6.2), Vector2(1.8, -6.2), Vector2(-3.0, 2.0), Vector2(2.1, 2.0),
	Vector2(-0.55, 1.8), Vector2(-0.55, 5.2), Vector2(-2.2, -0.6), Vector2(1.1, -0.6),
]
const CONDUCTIVE := [1, 2, 3, 4, 5, 8, 11]

var root: Node3D
var kit: PcbKit
var fx: Fx
var arc: Discharger
var camera: Camera3D
var walls_body: StaticBody3D
var board_w := 12.2
var board_d := 24.0

var balls: Array = []
var flippers: Array = []
var bumpers: Array = []
var targets: Array = []
var lanes: Array = []
var slings: Array = []
var pickups: Array = []
var zap_list: Array[Vector3] = []
var wall_kinds: Array = []

var state := "launch"
var score := 0
var balls_left := 3
var mult := 1
var pull := 0.0
var saver_t := 0.0
var jumper := false
var tilt_t := 0.0
var pu_timer := 6.0
var fx_t := {"x2": 0.0, "big": 0.0, "small": 0.0, "emi": 0.0, "swap": 0.0}
var emi_timer := 0.0
var emi_buzz := 0.0
var touches := {}
var acc_prev := Vector3.ZERO
var nudge_cd := 0.0
var nudges: Array = []
var last_hit_ms := 0
var overlay: Control
var over_panel: Control

var lbl_score: Label
var lbl_info: Label
var lbl_toast: Label
var lbl_hint: Label
var lbl_fx: RichTextLabel
var bar_pull: ColorRect
var bar_bg: ColorRect
var toast_tw: Tween
var fx_text_cache := "?"
var ui: CanvasLayer

func _ready() -> void:
	root = Node3D.new()
	add_child(root)
	kit = PcbKit.new(root)
	fx = Fx.new(self, kit.mats.spark)
	fx.spark_parent = root
	fx.pulse_leds(kit.mats.led)
	_setup_environment()
	_setup_camera()
	_build_table()
	arc = Discharger.new(root)
	_setup_ui()
	_apply_options()
	Audio.play_music("pinball")
	_new_game()
	_schedule_ambient()

# ------------------------------------------------------------ środowisko, kamera
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
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAM_FOV
	add_child(camera)
	var w := 12.2
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_tan := tan(deg_to_rad(CAM_FOV / 2.0))
	var dist := (w / 2.0) / half_tan + WALL_H
	var half_w := dist * half_tan
	var half_h := half_w / aspect
	board_w = maxf(w, half_w * 2.0 * 1.1)
	board_d = maxf(22.0, half_h * 2.0 * 1.1)
	camera.position = Vector3(0.1, dist, 0.0)
	camera.rotation_degrees = Vector3(-90, 0, 0)

func _phys(friction: float, bounce: float) -> PhysicsMaterial:
	var p := PhysicsMaterial.new()
	p.friction = friction
	p.bounce = bounce
	return p

# ------------------------------------------------------------------ budowa stołu
func _build_table() -> void:
	walls_body = StaticBody3D.new()
	walls_body.physics_material_override = _phys(0.2, 0.35)
	root.add_child(walls_body)

	# podłoga (kolizja) + płytka PCB z teksturą
	var floor_body := StaticBody3D.new()
	floor_body.physics_material_override = _phys(0.5, 0.0)
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(16.0, 0.5, 26.0)
	fs.shape = fb
	fs.position = Vector3(0.1, -0.25, 0.0)
	floor_body.add_child(fs)
	root.add_child(floor_body)
	kit.add_board(board_w, board_d, Vector2(6.0, 10.8), 424242)

	# ściany: łuk, boki, wyrzutnia
	var n := 14
	var prev := _arch_pt(PI)
	for i in range(1, n + 1):
		var p := _arch_pt(PI - PI * i / n)
		_wall(prev, p, 0.9, true)
		prev = p
	_wall(Vector2(-5.25, -5.1), Vector2(-5.25, 10.0), 0.9, true)
	_wall(Vector2(5.45, -5.1), Vector2(5.45, 10.0), 0.9, true)
	_wall(Vector2(3.9, -5.5), Vector2(3.9, 10.1), 0.4, false)            # przegroda toru wyrzutni
	_bar(Vector2(3.9, -5.5), Vector2(3.9, 10.1), 0.4, kit.mats.gold, kit.mats.black)
	_wall(Vector2(4.1, 10.35), Vector2(5.0, 10.35), 0.5, false)          # oparcie sprężyny
	_bar(Vector2(4.1, 10.35), Vector2(5.0, 10.35), 0.5, kit.mats.silver, kit.mats.chip)

	# prowadnice wlotowe (lewa i lustrzana prawa względem osi pola gry x = -0.55)
	for side in [1, -1]:
		var a := Vector2(_mx(-4.0, side), 6.2)
		var b := Vector2(_mx(-2.45, side), 8.55)
		_wall(a, b, 0.35, false)
		_bar(a, b, 0.35, kit.mats.silver, kit.mats.chip)
		kit.begin_part(Vector3.ZERO, 0.0)
		kit.cyl(kit.mats.led[0], 0.09, 0.1, Vector3(a.x, 0.55, a.y), 10)

	# slingshoty
	_add_sling([Vector2(-3.7, 3.6), Vector2(-3.7, 5.3), Vector2(-2.3, 5.8)], Vector2(0.84, -0.54))
	_add_sling([Vector2(_mx(-3.7, -1), 3.6), Vector2(_mx(-2.3, -1), 5.8), Vector2(_mx(-3.7, -1), 5.3)], Vector2(-0.84, -0.54))

	# bumpery, cele, tory zwrotne, słupki
	for p in [Vector2(-2.0, -3.6), Vector2(0.9, -3.6), Vector2(-0.55, -1.2)]:
		_add_bumper(p)
	for i in 3:
		_add_target(Vector3(-4.55, 0, -2.2 + i * 1.3), 1)
		_add_target(Vector3(3.45, 0, -2.2 + i * 1.3), -1)
	for x in [-1.3, 0.1, 1.5]:
		_add_lane(Vector3(x, 0, -8.4))
	for x in [-2.0, -0.6, 0.8, 2.2]:
		_add_post(Vector3(x, 0, -8.4))

	# flippery
	flippers.append(_make_flipper(Vector3(_mx(-2.45, 1), 0, 8.65), 1))
	flippers.append(_make_flipper(Vector3(_mx(-2.45, -1), 0, 8.65), -1))

	# wyrzutnia: sprężyna
	_make_plunger()

	# magistrale (nad i pod stołem) + dekoracje
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var occ := {}
	kit.add_bus(-1.4, -10.45, -1, 2, rng, occ, board_d)
	kit.add_bus(1.6, -10.45, -1, 1, rng, occ, board_d)
	kit.add_bus(-3.4, 10.1, 1, 2, rng, occ, board_d)
	kit.add_bus(1.0, 10.1, 1, 2, rng, occ, board_d)
	kit.add_decor(12.0, 21.6, occ, board_w, board_d)
	kit.flush(root)

	# sitodruk
	var lbl := Label3D.new()
	lbl.text = "PINBALL  REV 1.0"
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.9, 0.95, 0.9, 0.7)
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(-0.55, 0.011, 2.9)
	root.add_child(lbl)

func _mx(x: float, side: int) -> float:
	# side = 1: bez zmian, -1: odbicie względem osi pola gry (x = -0.55)
	return x if side == 1 else -1.1 - x

func _arch_pt(a: float) -> Vector2:
	return Vector2(ARCH_C.x + ARCH_R * cos(a), ARCH_C.y - ARCH_R * sin(a))

func _wall(p0: Vector2, p1: Vector2, thick: float, parts: bool) -> void:
	var d := p1 - p0
	var length := d.length()
	var mid := (p0 + p1) / 2.0
	var ang := atan2(-d.y, d.x)         # obrót wokół Y: lokalne +X -> kierunek segmentu
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length + 0.02, WALL_H, thick)
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x, WALL_H / 2.0, mid.y))
	walls_body.add_child(cs)
	if not parts:
		return
	var n := maxi(1, int(round(length / 0.95)))
	for i in n:
		var pos := p0.lerp(p1, (i + 0.5) / n)
		kit.begin_part(Vector3(pos.x, 0, pos.y), ang + PI / 2.0)
		kit.part(int(kit._hash2(pos.x * 3.0 + 1.0, pos.y * 5.0 + 2.0) * 12.0) % 12, i)
		if i % 3 == 0:
			kit.spark_spots.append(Vector3(pos.x, 0.75, pos.y))
			zap_list.append(Vector3(pos.x, 0.45, pos.y))

func _bar(p0: Vector2, p1: Vector2, thick: float, top: Material, base: Material) -> void:
	var d := p1 - p0
	var mid := (p0 + p1) / 2.0
	kit.begin_part(Vector3(mid.x, 0, mid.y), atan2(-d.y, d.x))
	kit.box(base, Vector3(d.length(), 0.5, thick), Vector3(0, 0.25, 0))
	kit.box(top, Vector3(d.length(), 0.04, thick * 0.5), Vector3(0, 0.52, 0))

func _add_post(pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = 0.12
	s.height = WALL_H
	cs.shape = s
	cs.position = Vector3(pos.x, WALL_H / 2.0, pos.z)
	walls_body.add_child(cs)
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.cyl(kit.mats.silver, 0.12, 0.6, Vector3(pos.x, 0.3, pos.z), 10)

func _add_sling(pts: Array, kick_normal: Vector2) -> void:
	var v: Array[Vector2] = []
	for p in pts:
		v.append(p)
	var mat := kit.mat(Color(0.4, 0.04, 0.04), 0.2, 0.4, Color(1.0, 0.2, 0.1), 0.12)
	var m2 := mat.duplicate() as StandardMaterial3D
	m2.cull_mode = BaseMaterial3D.CULL_DISABLED
	# bryła: kolizja + siatka
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var ps := PackedVector3Array()
	for p in v:
		ps.append(Vector3(p.x, 0.0, p.y))
		ps.append(Vector3(p.x, WALL_H, p.y))
	shape.points = ps
	cs.shape = shape
	walls_body.add_child(cs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := v.size()
	for i in range(1, n - 1):
		for k in [0, i, i + 1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(v[k].x, WALL_H, v[k].y))
	var c := Vector2.ZERO
	for p in v:
		c += p
	c /= n
	for i in n:
		var a := v[i]
		var b := v[(i + 1) % n]
		var nn := ((a + b) / 2.0 - c).normalized()
		var nrm := Vector3(nn.x, 0, nn.y)
		var va := Vector3(a.x, 0, a.y)
		var vb := Vector3(b.x, 0, b.y)
		var vah := Vector3(a.x, WALL_H, a.y)
		var vbh := Vector3(b.x, WALL_H, b.y)
		for q in [va, vb, vbh, va, vbh, vah]:
			st.set_normal(nrm)
			st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m2
	root.add_child(mi)
	# strefa kopnięcia wzdłuż przeciwprostokątnej (v[0] -> v[2])
	var a2 := v[0]
	var b2 := v[2]
	var dd := b2 - a2
	kit.begin_part(Vector3((a2.x + b2.x) / 2.0, 0, (a2.y + b2.y) / 2.0), atan2(-dd.y, dd.x))
	kit.box(kit.mats.gold, Vector3(dd.length(), 0.1, 0.12), Vector3(0, WALL_H + 0.05, 0))
	var mid := (a2 + b2) / 2.0 + kick_normal * 0.3
	var area := Area3D.new()
	var acs := CollisionShape3D.new()
	var abs_ := BoxShape3D.new()
	abs_.size = Vector3(dd.length() + 0.2, 0.7, 0.5)
	acs.shape = abs_
	area.transform = Transform3D(Basis(Vector3.UP, atan2(-dd.y, dd.x)), Vector3(mid.x, 0.35, mid.y))
	area.add_child(acs)
	root.add_child(area)
	var sl := {"mat": m2, "normal": Vector3(kick_normal.x, 0, kick_normal.y), "pos": Vector3(mid.x, 0.4, mid.y)}
	slings.append(sl)
	area.body_entered.connect(func(body: Node): _sling_hit(sl, body))
	zap_list.append(Vector3(mid.x, 0.5, mid.y))

func _add_bumper(p: Vector2) -> void:
	var body := StaticBody3D.new()
	body.physics_material_override = _phys(0.1, 0.5)
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = 0.55
	s.height = WALL_H
	cs.shape = s
	cs.position = Vector3(p.x, WALL_H / 2.0, p.y)
	body.add_child(cs)
	root.add_child(body)
	var vis := Node3D.new()
	vis.position = Vector3(p.x, 0, p.y)
	root.add_child(vis)
	_pm(vis, _cyl_mesh(0.72, 0.06), kit.mats.black, Vector3(0, 0.03, 0))
	_pm(vis, _cyl_mesh(0.5, 0.62), kit.mats.cap_blue, Vector3(0, 0.31, 0))
	_pm(vis, _cyl_mesh(0.44, 0.02), kit.mats.cap_top, Vector3(0, 0.63, 0))
	var ring_mat := kit.mat(Color(0.3, 0.1, 0.02), 0.0, 0.3, Color(1.0, 0.55, 0.1), 1.2)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.52
	tm.outer_radius = 0.64
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.12, 0)
	vis.add_child(ring)
	var area := Area3D.new()
	var acs := CollisionShape3D.new()
	var ash := CylinderShape3D.new()
	ash.radius = 0.95
	ash.height = 0.8
	acs.shape = ash
	acs.position = Vector3(p.x, 0.4, p.y)
	area.add_child(acs)
	root.add_child(area)
	var bd := {"pos": Vector3(p.x, 0.4, p.y), "vis": vis, "ring": ring_mat}
	bumpers.append(bd)
	area.body_entered.connect(func(body: Node): _bumper_hit(bd, body))
	zap_list.append(Vector3(p.x, 0.5, p.y))

func _cyl_mesh(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 20
	m.rings = 1
	return m

func _pm(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _add_target(pos: Vector3, dir: int) -> void:
	# układ scalony przy ścianie; dioda od strony pola gry zapala się po trafieniu
	var body := StaticBody3D.new()
	body.physics_material_override = _phys(0.1, 0.45)
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(0.5, 0.6, 0.9)
	cs.shape = s
	cs.position = Vector3(pos.x, 0.3, pos.z)
	body.add_child(cs)
	root.add_child(body)
	var vis := Node3D.new()
	vis.position = pos
	root.add_child(vis)
	_pm(vis, _box_mesh(Vector3(0.5, 0.5, 0.9)), kit.mats.chip, Vector3(0, 0.25, 0))
	_pm(vis, _box_mesh(Vector3(0.1, 0.02, 0.1)), kit.mats.chip_mark, Vector3(-0.15 * dir, 0.51, -0.3))
	var led_mat := kit.mat(Color(0.05, 0.12, 0.05), 0.0, 0.3, Color(0.2, 1.0, 0.3), 0.3)
	_pm(vis, _box_mesh(Vector3(0.08, 0.3, 0.7)), led_mat, Vector3(0.24 * dir, 0.3, 0))
	var area := Area3D.new()
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(0.8, 0.7, 1.1)
	acs.shape = ash
	acs.position = Vector3(pos.x + 0.1 * dir, 0.35, pos.z)
	area.add_child(acs)
	root.add_child(area)
	var td := {"pos": Vector3(pos.x, 0.4, pos.z), "mat": led_mat, "lit": false, "cd": 0, "dir": dir}
	targets.append(td)
	area.body_entered.connect(func(body: Node): _target_hit(td, body))
	zap_list.append(Vector3(pos.x + 0.3 * dir, 0.4, pos.z))

func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _add_lane(pos: Vector3) -> void:
	var mat := kit.mat(Color(0.1, 0.1, 0.02), 0.0, 0.3, Color(1.0, 0.85, 0.2), 0.3)
	var disc := _pm(root, _cyl_mesh(0.3, 0.02), mat, Vector3(pos.x, 0.012, pos.z))
	disc.name = "LaneLed"
	var area := Area3D.new()
	var acs := CollisionShape3D.new()
	var ash := CylinderShape3D.new()
	ash.radius = 0.4
	ash.height = 0.6
	acs.shape = ash
	acs.position = Vector3(pos.x, 0.3, pos.z)
	area.add_child(acs)
	root.add_child(area)
	var ld := {"pos": pos, "mat": mat, "lit": false, "cd": 0}
	lanes.append(ld)
	area.body_entered.connect(func(body: Node): _lane_hit(ld, body))

func _make_flipper(pivot: Vector3, dir: int) -> Dictionary:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.physics_material_override = _phys(0.6, 0.3)
	body.position = pivot
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(FLIP_LEN, 0.6, 0.38)
	cs.shape = bs
	cs.position = Vector3(dir * FLIP_LEN / 2.0, 0.3, 0)
	body.add_child(cs)
	var vis := Node3D.new()
	body.add_child(vis)
	var base := kit.mat(Color(0.08, 0.08, 0.1), 0.6, 0.3)
	_pm(vis, _box_mesh(Vector3(FLIP_LEN, 0.4, 0.38)), base, Vector3(dir * FLIP_LEN / 2.0, 0.2, 0))
	_pm(vis, _box_mesh(Vector3(FLIP_LEN, 0.04, 0.2)), kit.mats.gold, Vector3(dir * FLIP_LEN / 2.0, 0.42, 0))
	_pm(vis, _cyl_mesh(0.26, 0.5), kit.mats.silver, Vector3(0, 0.25, 0))
	var tip := kit.mat(Color(0.3, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.15, 0.1), 1.5)
	_pm(vis, _cyl_mesh(0.14, 0.45), tip, Vector3(dir * (FLIP_LEN - 0.15), 0.25, 0))
	root.add_child(body)
	var rest := -dir * FLIP_REST
	body.rotation.y = rest
	return {"body": body, "vis": vis, "shape": bs, "cs": cs, "dir": dir, "angle": rest,
		"rest": rest, "up": dir * FLIP_UP, "pressed": false, "scale": 1.0}

var plunger_vis: Node3D

func _make_plunger() -> void:
	plunger_vis = Node3D.new()
	plunger_vis.position = Vector3(LANE_CX(), 0, 10.0)
	root.add_child(plunger_vis)
	_pm(plunger_vis, _cyl_mesh(0.18, 0.5), kit.mats.silver, Vector3(0, 0.1, 0.3))
	var spring := kit.mat(Color(0.7, 0.7, 0.75), 1.0, 0.3)
	for i in 5:
		_pm(plunger_vis, _cyl_mesh(0.22, 0.05), spring, Vector3(0, 0.05, 0.55 + i * 0.1))

func LANE_CX() -> float:
	return 4.55

# ------------------------------------------------------------------------- UI
func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 22
	top.offset_bottom = 90
	top.add_theme_constant_override("separation", 10)
	ui.add_child(top)
	var b_menu := _btn("MENU", _go_menu, "back")
	b_menu.custom_minimum_size = Vector2(150, 0)
	top.add_child(b_menu)
	lbl_score = UiKit.label("0", 32, UiKit.C_YELLOW, 8)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lbl_score)
	var b_opt := _btn("OPCJE", _open_options)
	b_opt.custom_minimum_size = Vector2(150, 0)
	top.add_child(b_opt)

	lbl_info = UiKit.label("", 16, Color("e8c9a0"), 6)
	lbl_info.position = Vector2(20, 104)
	ui.add_child(lbl_info)

	lbl_fx = RichTextLabel.new()
	lbl_fx.bbcode_enabled = true
	lbl_fx.fit_content = true
	lbl_fx.scroll_active = false
	lbl_fx.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_fx.position = Vector2(20, 134)
	lbl_fx.custom_minimum_size = Vector2(672, 40)
	lbl_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_fx.add_theme_font_size_override("normal_font_size", 16)
	lbl_fx.add_theme_constant_override("outline_size", 6)
	lbl_fx.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_fx)

	lbl_toast = UiKit.label("", 24, Color.WHITE, 10)
	lbl_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_toast.offset_top = 260
	lbl_toast.offset_bottom = 380
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.modulate.a = 0.0
	ui.add_child(lbl_toast)

	lbl_hint = UiKit.label("", 16, UiKit.C_CYAN, 6)
	lbl_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_hint.offset_top = -150
	lbl_hint.offset_bottom = -100
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lbl_hint)

	bar_bg = ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar_bg.offset_left = 120
	bar_bg.offset_right = -120
	bar_bg.offset_top = -90
	bar_bg.offset_bottom = -60
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar_bg)
	bar_pull = ColorRect.new()
	bar_pull.color = UiKit.C_GREEN
	bar_pull.position = Vector2(4, 4)
	bar_pull.size = Vector2(0, 22)
	bar_pull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar_pull)

func _btn(text: String, cb: Callable, snd := "click") -> Button:
	var b := Button.new()
	b.text = text
	UiKit.style_button(b, 16, UiKit.C_CYAN)
	b.pressed.connect(func():
		Audio.play_sfx(snd)
		cb.call())
	return b

func _apply_options() -> void:
	kit.set_effects(Settings.effects)

func _toast(text: String, good: bool) -> void:
	lbl_toast.text = text
	lbl_toast.add_theme_color_override("font_color", Color("7dffb0") if good else Color("ff6a5a"))
	if toast_tw:
		toast_tw.kill()
	lbl_toast.modulate.a = 1.0
	toast_tw = create_tween()
	toast_tw.tween_interval(2.4)
	toast_tw.tween_property(lbl_toast, "modulate:a", 0.0, 0.5)

func _update_hud() -> void:
	lbl_score.text = str(score)
	lbl_info.text = "KULA %d/3   MNOŻNIK x%d" % [clampi(4 - balls_left, 1, 3), mult]
	var parts := PackedStringArray()
	if jumper:
		parts.append("[color=#7dffb0]ZWORKA[/color]")
	if saver_t > 0.0:
		parts.append("[color=#7dffb0]OCHRONA %d s[/color]" % ceili(saver_t))
	for k in fx_t:
		if fx_t[k] > 0.0:
			var info: Dictionary = PU[k]
			var colr := "#7dffb0" if info.good else "#ff6a5a"
			parts.append("[color=%s]%s %d s[/color]" % [colr, info.name, ceili(fx_t[k])])
	var txt := "   ".join(parts)
	if txt != fx_text_cache:
		fx_text_cache = txt
		lbl_fx.text = txt
	var launching := state == "launch"
	bar_bg.visible = launching
	lbl_hint.visible = launching
	lbl_hint.text = "TRZYMAJ PRAWĄ STRONĘ, PUŚĆ = STRZAŁ"
	bar_pull.size.x = (bar_bg.size.x - 8.0) * pull

# ---------------------------------------------------------------- stan gry
func _new_game() -> void:
	for b in balls:
		(b.node as Node).queue_free()
	balls.clear()
	for p in pickups:
		(p.node as Node).queue_free()
	pickups.clear()
	score = 0
	balls_left = 3
	mult = 1
	jumper = false
	saver_t = 0.0
	tilt_t = 0.0
	for k in fx_t:
		fx_t[k] = 0.0
	_reset_lights()
	if over_panel:
		over_panel.queue_free()
		over_panel = null
	_spawn_lane_ball()

func _reset_lights() -> void:
	for ld in lanes:
		_light_lane(ld, false)
	for td in targets:
		_light_target(td, false)

func _spawn_lane_ball() -> void:
	_spawn_ball(BALL_START)
	state = "launch"
	pull = 0.0

func _spawn_ball(pos: Vector3, vel := Vector3.ZERO) -> Dictionary:
	var rb := RigidBody3D.new()
	rb.mass = 0.5
	rb.continuous_cd = true
	rb.axis_lock_linear_y = true
	rb.linear_damp = 0.02
	rb.angular_damp = 0.5
	rb.physics_material_override = _phys(0.3, 0.25)
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = BALL_R
	cs.shape = ss
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 40
	sm.rings = 20
	mi.mesh = sm
	var bm := (kit.mats.ball as ShaderMaterial).duplicate() as ShaderMaterial
	bm.set_shader_parameter("charge", 0.3)
	mi.material_override = bm
	rb.add_child(mi)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.4, 0)
	glow.omni_range = 4.0
	glow.light_energy = 0.35
	glow.light_color = Color(1.0, 0.3, 0.22)
	rb.add_child(glow)
	root.add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	var d := {"node": rb, "mat": bm, "light": glow, "charge": randf() * 0.4, "goal": randf_range(0.8, 1.6), "speed": 0.0}
	rb.body_entered.connect(func(_b: Node): _ball_hit(d))
	balls.append(d)
	return d

func _launch(power: float) -> void:
	for b in balls:
		var rb: RigidBody3D = b.node
		rb.linear_velocity = Vector3(0, 0, -lerpf(15.0, 27.0, power))
	state = "play"
	saver_t = 8.0
	Audio.play_sfx("launch")
	Settings.vibrate(40)

func _drain(b: Dictionary) -> void:
	balls.erase(b)
	(b.node as Node).queue_free()
	if not balls.is_empty():
		Audio.play_sfx("drain", -4.0)
		return
	if saver_t > 0.0 or jumper:
		if jumper:
			jumper = false
		saver_t = 0.0
		Audio.play_sfx("pu_good")
		_toast("OCHRONA KULKI!\nKULA WRACA", true)
		_spawn_lane_ball()
		return
	Audio.play_sfx("drain")
	Settings.vibrate(60)
	balls_left -= 1
	state = "drain"
	if balls_left <= 0:
		_game_over()
	else:
		await get_tree().create_timer(1.2).timeout
		if is_inside_tree() and state == "drain":
			_spawn_lane_ball()

func _game_over() -> void:
	state = "over"
	var high := Save.get_int("pinball", "high", 0)
	var record := score > high
	if record:
		Save.set_int("pinball", "high", score)
	over_panel = Control.new()
	over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.0, 0.1, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_panel.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -260
	box.offset_bottom = 260
	box.add_theme_constant_override("separation", 26)
	over_panel.add_child(box)
	var t := UiKit.label("KONIEC GRY", 40, UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := UiKit.label("WYNIK\n%d" % score, 32, UiKit.C_YELLOW, 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	var hs := UiKit.label(("NOWY REKORD!" if record else "REKORD: %d" % high), 16, UiKit.C_GREEN if record else UiKit.C_CYAN, 6)
	hs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hs)
	var again := Button.new()
	again.text = "NOWA GRA"
	again.custom_minimum_size = Vector2(0, 100)
	UiKit.style_button(again, 24, UiKit.C_GREEN)
	again.pressed.connect(func():
		Audio.play_sfx("coin")
		_new_game())
	box.add_child(again)
	var menu := Button.new()
	menu.text = "MENU"
	menu.custom_minimum_size = Vector2(0, 80)
	UiKit.style_button(menu, 24, UiKit.C_CYAN)
	menu.pressed.connect(func():
		Audio.play_sfx("back")
		_go_menu())
	box.add_child(menu)
	ui.add_child(over_panel)
	Audio.play_sfx("win" if record else "pu_bad")

func _open_options() -> void:
	if overlay:
		return
	Audio.set_roll(0.0)
	var panel := OptionsPanel.new()
	panel.closed.connect(_close_overlay)
	overlay = panel
	ui.add_child(panel)
	get_tree().paused = true

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	get_tree().paused = false
	_apply_options()

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

# -------------------------------------------------------------- punktacja
func _score(points: int, pos: Vector3, show := true) -> void:
	var p := points * mult * (2 if fx_t.x2 > 0.0 else 1)
	score += p
	if show:
		_popup(pos, str(p))

func _popup(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.006
	l.modulate = Color(1, 0.95, 0.5)
	l.outline_size = 10
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(pos.x, 1.0, pos.z)
	root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:z", pos.z - 0.9, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(l.queue_free)

# ------------------------------------------------------------ zdarzenia stołu
func _ball_dict(body: Node) -> Dictionary:
	for b in balls:
		if b.node == body:
			return b
	return {}

func _bumper_hit(bd: Dictionary, body: Node) -> void:
	var b := _ball_dict(body)
	if b.is_empty():
		return
	var rb: RigidBody3D = b.node
	var bpos: Vector3 = bd.pos
	var dir := rb.global_position - bpos
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	rb.linear_velocity = dir * clampf(rb.linear_velocity.length() * 0.7 + 6.0, 9.0, 16.0)
	_score(100, bd.pos)
	Audio.play_sfx("bumper", 0.0, randf_range(0.9, 1.15))
	Settings.vibrate(18)
	fx.sparks(bd.pos + Vector3(0, 0.3, 0), 16)
	fx.light_flash(bd.pos, Color(1.0, 0.6, 0.2), 2.0)
	var ring: StandardMaterial3D = bd.ring
	ring.emission_energy_multiplier = 7.0
	create_tween().tween_property(ring, "emission_energy_multiplier", 1.2, 0.4)
	var vis: Node3D = bd.vis
	vis.scale = Vector3(1.15, 1.0, 1.15)
	create_tween().tween_property(vis, "scale", Vector3.ONE, 0.2)

func _sling_hit(sl: Dictionary, body: Node) -> void:
	var b := _ball_dict(body)
	if b.is_empty():
		return
	var rb: RigidBody3D = b.node
	var n: Vector3 = sl.normal
	rb.linear_velocity = n * 11.0 + rb.linear_velocity * 0.25
	_score(10, sl.pos, false)
	Audio.play_sfx("sling", 0.0, randf_range(0.9, 1.1))
	Settings.vibrate(14)
	fx.sparks(sl.pos, 8)
	var m: StandardMaterial3D = sl.mat
	m.emission_energy_multiplier = 3.0
	create_tween().tween_property(m, "emission_energy_multiplier", 0.12, 0.3)

func _light_target(td: Dictionary, on: bool) -> void:
	td.lit = on
	var m: StandardMaterial3D = td.mat
	m.emission_energy_multiplier = 3.5 if on else 0.3
	m.emission = Color(1.0, 0.9, 0.2) if on else Color(0.2, 1.0, 0.3)

func _target_hit(td: Dictionary, body: Node) -> void:
	var b := _ball_dict(body)
	var now := Time.get_ticks_msec()
	if b.is_empty() or now - int(td.cd) < 250:
		return
	td.cd = now
	Audio.play_sfx("target", 0.0, randf_range(0.95, 1.1))
	Settings.vibrate(12)
	fx.sparks(td.pos, 10)
	if not td.lit:
		_light_target(td, true)
		_score(250, td.pos)
	else:
		_score(50, td.pos, false)
	var all := true
	for t in targets:
		if not t.lit:
			all = false
	if all:
		_score(2500, td.pos)
		_toast("UKŁAD KOMPLETNY!\n+2500", true)
		saver_t = maxf(saver_t, 10.0)
		Audio.play_sfx("multi")
		Settings.vibrate(60)
		for t in targets:
			_light_target(t, false)

func _light_lane(ld: Dictionary, on: bool) -> void:
	ld.lit = on
	var m: StandardMaterial3D = ld.mat
	m.emission_energy_multiplier = 4.0 if on else 0.3

func _lane_hit(ld: Dictionary, body: Node) -> void:
	var b := _ball_dict(body)
	var now := Time.get_ticks_msec()
	if b.is_empty() or now - int(ld.cd) < 400:
		return
	ld.cd = now
	Audio.play_sfx("rollover")
	if not ld.lit:
		_light_lane(ld, true)
		_score(100, ld.pos)
	var all := true
	for l in lanes:
		if not l.lit:
			all = false
	if all:
		mult = mini(mult + 1, MULT_MAX)
		_score(500, ld.pos)
		_toast("MNOŻNIK x%d" % mult, true)
		Audio.play_sfx("multi", -4.0)
		for l in lanes:
			_light_lane(l, false)

func _ball_hit(d: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var sp: float = d.speed
	if sp > 3.0 and now - last_hit_ms > 70:
		last_hit_ms = now
		Audio.play_sfx("hit", linear_to_db(clampf(sp / 12.0, 0.15, 1.0)), randf_range(0.9, 1.25))
		if sp > 8.0:
			Settings.vibrate(8)

# ------------------------------------------------------------------ power-upy
func _spawn_pickup() -> void:
	var spot: Vector2 = PU_SPOTS[randi() % PU_SPOTS.size()]
	for p in pickups:
		if Vector2(p.pos.x, p.pos.z).distance_to(spot) < 0.8:
			return
	var good_types := ["jumper", "multi", "x2", "big", "batt"]
	var bad_types := ["small", "emi", "swap", "mine"]
	var type: String = good_types[randi() % good_types.size()] if randf() < 0.55 else bad_types[randi() % bad_types.size()]
	var info: Dictionary = PU[type]
	var pos := Vector3(spot.x, 0, spot.y)
	var node := PickupKit.build(kit, type, pos, info.col, info.good)
	root.add_child(node)
	pickups.append({"type": type, "pos": pos, "node": node, "ttl": 16.0})

func _update_pickups(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var i := 0
	for p in pickups:
		var body: Node3D = (p.node as Node3D).get_node("Body")
		body.position.y = 0.38 + sin(t * 3.0 + i) * 0.05
		body.rotation.y += delta * 2.0
		p.ttl -= delta
		(p.node as Node3D).visible = p.ttl > 3.0 or int(t * 6.0) % 2 == 0
		i += 1
	for k in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[k]
		var hit := false
		for b in balls:
			var bp: Vector3 = (b.node as RigidBody3D).global_position
			if Vector2(bp.x, bp.z).distance_to(Vector2(p.pos.x, p.pos.z)) < 0.6:
				hit = true
		if hit:
			pickups.remove_at(k)
			_collect(p)
		elif p.ttl <= 0.0:
			(p.node as Node).queue_free()
			pickups.remove_at(k)

func _collect(p: Dictionary) -> void:
	var type: String = p.type
	var info: Dictionary = PU[type]
	var good: bool = info.good
	(p.node as Node).queue_free()
	var pos: Vector3 = p.pos
	fx.sparks(pos + Vector3(0, 0.3, 0), 24, true)
	fx.light_flash(pos, Color(0.4, 1.0, 0.6) if good else Color(1.0, 0.3, 0.2), 2.5)
	Settings.vibrate(25)
	if type != "mine":
		Audio.play_sfx("pu_good" if good else "pu_bad")
	match type:
		"jumper":
			jumper = true
		"multi":
			Audio.play_sfx("multi")
			for i in 2:
				var a := randf() * TAU
				_spawn_ball(Vector3(-0.55 + cos(a) * 0.6, 0.3, 1.0 + sin(a) * 0.6), Vector3(cos(a), 0, sin(a) - 0.5) * 6.0)
		"batt":
			_score(1000, pos)
		"mine":
			_mine(pos)
		_:
			fx_t[type] = float(info.dur)
			if type == "big":
				fx_t.small = 0.0
			elif type == "small":
				fx_t.big = 0.0
			_apply_flipper_scale()
	_toast("%s\n%s" % [info.name, info.desc], good)

func _mine(pos: Vector3) -> void:
	Audio.play_sfx("mine")
	Settings.vibrate(60)
	score = maxi(0, score - 500)
	fx.sparks(pos + Vector3(0, 0.3, 0), 40, true)
	for b in balls:
		var a := randf() * TAU
		(b.node as RigidBody3D).linear_velocity = Vector3(cos(a), 0, sin(a)) * 9.0

func _apply_flipper_scale() -> void:
	var s := 1.0
	if fx_t.big > 0.0:
		s = 1.35
	elif fx_t.small > 0.0:
		s = 0.7
	for f in flippers:
		if absf(f.scale - s) < 0.001:
			continue
		f.scale = s
		var vis: Node3D = f.vis
		vis.scale = Vector3(s, 1.0, 1.0)
		var bs: BoxShape3D = f.shape
		bs.size.x = FLIP_LEN * s
		(f.cs as CollisionShape3D).position.x = f.dir * FLIP_LEN * s / 2.0

# ------------------------------------------------------------------ sterowanie
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = "L" if e.position.x < get_viewport().get_visible_rect().size.x * 0.5 else "R"
		else:
			touches.erase(e.index)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			touches["m"] = "L" if e.position.x < get_viewport().get_visible_rect().size.x * 0.5 else "R"
		else:
			touches.erase("m")

func _held(side: String) -> bool:
	for v in touches.values():
		if v == side:
			return true
	if side == "L":
		return Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_A)
	return Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_SPACE)

func _tilt() -> void:
	tilt_t = 3.0
	nudges.clear()
	Audio.play_sfx("tilt")
	Settings.vibrate(120)
	_toast("TILT!\nflippery wyłączone", false)

func _check_nudge(delta: float) -> void:
	if not OS.has_feature("mobile"):
		return
	var a := Input.get_accelerometer()
	var jerk := (a - acc_prev).length()
	acc_prev = a
	nudge_cd -= delta
	if jerk > 9.0 and nudge_cd <= 0.0 and state == "play":
		nudge_cd = 0.35
		for b in balls:
			var v := Vector2.from_angle(randf() * TAU) * 1.4
			(b.node as RigidBody3D).apply_central_impulse(Vector3(v.x, 0, v.y))
		var now := Time.get_ticks_msec()
		nudges.append(now)
		nudges = nudges.filter(func(t): return now - int(t) < 4000)
		if nudges.size() >= 4:
			_tilt()

# ------------------------------------------------------------ pętla fizyki
func _physics_process(delta: float) -> void:
	_check_nudge(delta)
	tilt_t = maxf(0.0, tilt_t - delta)
	saver_t = maxf(0.0, saver_t - delta)
	var left := _held("L")
	var right := _held("R")
	if fx_t.swap > 0.0:
		var tmp := left
		left = right
		right = tmp
	if state == "launch":
		# w trakcie ładowania sprężyny prawa strona NIE rusza prawym flipperem
		var charging := _held("R") if fx_t.swap <= 0.0 else _held("L")
		if charging:
			pull = minf(pull + delta, 1.0)
		elif pull > 0.05:
			_launch(pull)
			pull = 0.0
		else:
			pull = 0.0
		if fx_t.swap <= 0.0:
			right = false
		else:
			left = false
	plunger_vis.position.z = 10.0 + pull * 0.8

	_update_flippers(delta, left and tilt_t <= 0.0, right and tilt_t <= 0.0)
	_tick_effects(delta)
	var max_speed := 0.0
	for k in range(balls.size() - 1, -1, -1):
		var b: Dictionary = balls[k]
		var rb: RigidBody3D = b.node
		rb.apply_central_force(Vector3(0, 0, G_TABLE * rb.mass))
		var v := rb.linear_velocity
		if v.length() > MAX_SPEED:
			rb.linear_velocity = v.normalized() * MAX_SPEED
		b.speed = rb.linear_velocity.length()
		max_speed = maxf(max_speed, b.speed)
		var p := rb.global_position
		# brama jednokierunkowa przy wyjściu z toru wyrzutni
		if p.x > 4.15 and p.z < -5.4 and p.z > -7.2 and rb.linear_velocity.z > 0.5 and state != "launch":
			rb.linear_velocity = Vector3(-4.0, 0, rb.linear_velocity.z * 0.3)
		if p.z > DRAIN_Z or absf(p.x) > 8.0 or p.z < -13.0:
			_drain(b)
			continue
		_update_charge(b, delta)
	Audio.set_roll(max_speed if state == "play" else 0.0)
	_update_pickups(delta)
	pu_timer -= delta
	if pu_timer <= 0.0 and state == "play":
		pu_timer = randf_range(9.0, 14.0)
		if pickups.size() < 2:
			_spawn_pickup()
	arc.update(delta)

func _update_flippers(delta: float, left: bool, right: bool) -> void:
	for f in flippers:
		var pressed: bool = left if f.dir == 1 else right
		if pressed and not f.pressed:
			Audio.play_sfx("flipper", 0.0, randf_range(0.95, 1.05))
			Settings.vibrate(8)
		f.pressed = pressed
		var target: float = f.up if pressed else f.rest
		var spd := FLIP_SPEED_UP if pressed else FLIP_SPEED_DOWN
		f.angle = move_toward(f.angle, target, spd * delta)
		(f.body as AnimatableBody3D).rotation.y = f.angle

func _tick_effects(delta: float) -> void:
	var changed := false
	for k in fx_t:
		if fx_t[k] > 0.0:
			fx_t[k] = maxf(0.0, fx_t[k] - delta)
			if fx_t[k] == 0.0 and (k == "big" or k == "small"):
				changed = true
	if changed:
		_apply_flipper_scale()
	if fx_t.emi > 0.0:
		emi_timer -= delta
		if emi_timer <= 0.0:
			emi_timer = 0.15
			for b in balls:
				var v := Vector2.from_angle(randf() * TAU) * 0.5
				(b.node as RigidBody3D).apply_central_impulse(Vector3(v.x, 0, v.y))
		emi_buzz -= delta
		if emi_buzz <= 0.0:
			emi_buzz = 0.4
			Settings.vibrate(10)
			Audio.play_sfx("emi", -6.0, randf_range(0.8, 1.3))
		camera.position.x = 0.1 + randf_range(-0.05, 0.05)
	else:
		camera.position.x = 0.1

func _process(_d: float) -> void:
	_update_hud()

# --------------------------------------------- ładunek elektrostatyczny kulki
func _update_charge(b: Dictionary, delta: float) -> void:
	var mat: ShaderMaterial = b.mat
	if not Settings.effects:
		mat.set_shader_parameter("charge", 0.2)
		return
	b.charge += delta * (0.4 + b.speed * 0.12)
	var c := clampf(b.charge / b.goal, 0.0, 1.0)
	mat.set_shader_parameter("charge", 0.35 + 0.65 * c)
	(b.light as OmniLight3D).light_energy = (0.45 + c * 0.7) * randf_range(0.75, 1.35)
	if b.charge >= b.goal and arc.time <= 0.0:
		var tp := _pick_zap((b.node as RigidBody3D).global_position)
		if tp != Vector3.INF:
			b.charge = 0.0
			b.goal = randf_range(0.6, 1.2)
			arc.fire(b.node, tp)
			fx.sparks(tp, 20)
			fx.light_flash(tp, Color(0.6, 0.9, 1.0), 3.0)
			Audio.play_sfx("discharge", -4.0, randf_range(0.9, 1.15))
			Settings.vibrate(10)
			_score(25, tp, false)
			mat.set_shader_parameter("flash", 1.0)
			create_tween().tween_method(func(v: float): mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.6)

func _pick_zap(bp: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := 3.6
	for _i in 10:
		var t: Vector3 = zap_list[randi() % zap_list.size()]
		var d := Vector2(t.x - bp.x, t.z - bp.z).length()
		if d > 0.8 and d < best_d:
			best_d = d
			best = t
	return best

func _schedule_ambient() -> void:
	get_tree().create_timer(randf_range(1.2, 3.0)).timeout.connect(_ambient_short)

func _ambient_short() -> void:
	if state == "play" and Settings.effects and not kit.spark_spots.is_empty() and overlay == null:
		var spot: Vector3 = kit.spark_spots[randi() % kit.spark_spots.size()]
		fx.sparks(spot, 14)
		fx.light_flash(spot, Fx.rand_color(), 2.0)
		if not balls.is_empty():
			var bp: Vector3 = (balls[0].node as RigidBody3D).global_position
			var d := Vector2(spot.x - bp.x, spot.z - bp.z).length()
			if d < 6.0:
				Audio.play_sfx("spark", -4.0 - d * 2.0, randf_range(0.85, 1.25))
	_schedule_ambient()
