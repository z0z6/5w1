extends Node3D
## PMUJ ELDOOD - czerwona kulka podskakuje po elementach elektronicznych w górę płytki. Sterowanie: przechył
## telefonu (jak w Marble Maze) albo przyciski < >. Platformy: zwykłe, ruchome, kruche, ze sprężyną; wirusy
## (skocz na nie z góry), power-upy. Plansza zawija się na bokach, kamera przewija płytkę w górę.

const FIELD := 5.0
const BALL_R := 0.3
const GRAV := 26.0
const JUMP := 14.5
const SPRING_V := 24.0
const CAM_FOV := 40.0
const PLAT_W := 1.8
const PLAT_H := 0.5
const PU := {
	"shield": {"name": "TARCZA", "desc": "odporność na wirusy 8 s", "good": true, "dur": 8.0, "col": Color(0.4, 0.7, 1.0), "shape": "insul"},
	"fan": {"name": "ŚMIGŁO", "desc": "lot w górę 3 s", "good": true, "dur": 3.0, "col": Color(0.85, 1.0, 0.2), "shape": "scan"},
	"life": {"name": "ZWORKA", "desc": "ratunek przed upadkiem", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.35), "shape": "batt"},
	"wide": {"name": "SZEROKIE PLATFORMY", "desc": "12 s", "good": true, "dur": 12.0, "col": Color(0.75, 0.9, 1.0), "shape": "big"},
	"rev": {"name": "ODWROTNA POLARYZACJA", "desc": "sterowanie odwrócone 8 s", "good": false, "dur": 8.0, "col": Color(0.85, 0.35, 1.0), "shape": "rev"},
	"narrow": {"name": "WĄSKIE PLATFORMY", "desc": "10 s", "good": false, "dur": 10.0, "col": Color(1.0, 0.45, 0.1), "shape": "small"},
}

var root: Node3D
var kit: PcbKit
var fx: Fx
var camera: Camera3D
var board_mesh: MeshInstance3D
var board_w := 12.2
var board_d := 24.0
var ppu := 65.0
var vp := Vector2(720, 1600)
var view_half := 12.0
var cam_z := 0.0
var cam_dist := 17.0
var arcs: Array = []
var arc_idx := 0
var world: Node3D
var rails: Array = []
var rails_z := 6.0
var protos: Dictionary = {}

var ball: Node3D
var ball_mat: ShaderMaterial
var ball_light: OmniLight3D
var bx := 0.0
var bz := 0.0
var vx := 0.0
var vz := 0.0
var platforms: Array = []
var enemies: Array = []
var gen_z := 0.0
var height := 0.0
var bonus := 0
var state := "play"
var calib := 0.0
var btn_dir := 0
var saved := false
var charge := 0.0
var charge_goal := 1.0
var fan_t := 0.0
var t_game := 0.0
var fx_t := {"shield": 0.0, "wide": 0.0, "narrow": 0.0, "rev": 0.0}
var overlay: Control
var panel: Control
var spin := 0.0

var ui: CanvasLayer
var lbl_score: Label
var lbl_info: Label
var lbl_fx: RichTextLabel
var lbl_toast: Label
var toast_tw: Tween
var fx_text_cache := "?"

func _ready() -> void:
	root = Node3D.new()
	add_child(root)
	kit = PcbKit.new(root)
	fx = Fx.new(self, kit.mats.spark)
	fx.spark_parent = root
	fx.pulse_leds(kit.mats.led)
	_setup_environment()
	_setup_camera()
	board_mesh = kit.add_board(board_w, board_d, Vector2(FIELD + 1.3, 1000.0), 9191)
	for i in 6:
		arcs.append(Discharger.new(root))
	world = Node3D.new()
	root.add_child(world)
	_build_protos()
	_build_ball()
	_setup_ui()
	Audio.play_music("skok")
	_new_game()
	get_tree().create_timer(0.8).timeout.connect(func(): _calibrate(true))

# ------------------------------------------------------ środowisko, kamera
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
	env.ambient_light_energy = 0.6
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
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAM_FOV
	add_child(camera)
	var w := FIELD * 2.0 + 2.6
	vp = get_viewport().get_visible_rect().size
	var half_tan := tan(deg_to_rad(CAM_FOV / 2.0))
	cam_dist = (w / 2.0) / half_tan + 0.7
	var plane_w := 2.0 * cam_dist * half_tan
	ppu = vp.x / plane_w
	view_half = vp.y / ppu / 2.0
	board_w = maxf(w, plane_w * 1.1)
	board_d = maxf(24.0, view_half * 2.0 * 1.2)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.position = Vector3(0, cam_dist, 0)

# ---------------------------------------------------------------- modele
func _bm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

func _pm(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_protos() -> void:
	# platformy zwykłe: 3 wyglądy; ruchome: przekaźnik; kruche: popękany tantal
	for look in 3:
		var n := Node3D.new()
		kit.begin_part(Vector3.ZERO, 0.0)
		match look:
			0:  # rząd układów z nóżkami
				kit.box(kit.mats.chip, Vector3(PLAT_W, 0.3, 0.5), Vector3(0, 0.15, 0))
				for i in 7:
					kit.box(kit.mats.silver, Vector3(0.08, 0.05, 0.1), Vector3(-0.78 + i * 0.26, 0.08, 0.28))
					kit.box(kit.mats.silver, Vector3(0.08, 0.05, 0.1), Vector3(-0.78 + i * 0.26, 0.08, -0.28))
				kit.box(kit.mats.chip_mark, Vector3(0.1, 0.02, 0.1), Vector3(-0.78, 0.31, -0.12))
			1:  # radiator
				kit.box(kit.mats.alu, Vector3(PLAT_W, 0.1, 0.5), Vector3(0, 0.05, 0))
				for i in 9:
					kit.box(kit.mats.alu, Vector3(0.09, 0.26, 0.46), Vector3(-0.78 + i * 0.195, 0.2, 0))
			_:  # listwa goldpin
				kit.box(kit.mats.black, Vector3(PLAT_W, 0.25, 0.5), Vector3(0, 0.125, 0))
				for i in 9:
					kit.cyl(kit.mats.gold, 0.05, 0.14, Vector3(-0.78 + i * 0.195, 0.3, 0.0), 8)
		kit.flush(n)
		protos["n%d" % look] = n
	var mv := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mats.relay, Vector3(PLAT_W, 0.3, 0.5), Vector3(0, 0.15, 0))
	kit.box(kit.mats.white, Vector3(1.0, 0.02, 0.26), Vector3(0, 0.31, 0))
	kit.cyl(kit.mats.led[1], 0.08, 0.1, Vector3(-0.8, 0.34, 0), 8)
	kit.cyl(kit.mats.led[1], 0.08, 0.1, Vector3(0.8, 0.34, 0), 8)
	kit.flush(mv)
	protos["move"] = mv
	var br := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mat(Color(0.55, 0.4, 0.12), 0.1, 0.6), Vector3(PLAT_W, 0.3, 0.5), Vector3(0, 0.15, 0))
	kit.box(kit.mats.black, Vector3(0.7, 0.02, 0.06), Vector3(-0.2, 0.31, 0.05))
	kit.box(kit.mats.black, Vector3(0.06, 0.02, 0.36), Vector3(0.3, 0.31, 0.0))
	kit.box(kit.mats.black, Vector3(0.5, 0.02, 0.05), Vector3(0.55, 0.31, -0.12))
	kit.flush(br)
	protos["break"] = br
	var sp := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	for i in 4:
		kit.torus(kit.mats.gold, 0.1, 0.24, Vector3(0, 0.05 + i * 0.09, 0))
	kit.flush(sp)
	protos["spring"] = sp

func _build_ball() -> void:
	ball = Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	mi.mesh = sm
	ball_mat = (kit.mats.ball as ShaderMaterial).duplicate() as ShaderMaterial
	ball_mat.set_shader_parameter("charge", 0.3)
	mi.material_override = ball_mat
	mi.name = "Mesh"
	ball.add_child(mi)
	ball_light = OmniLight3D.new()
	ball_light.position = Vector3(0, 1.2, 0)
	ball_light.omni_range = 3.5
	ball_light.light_energy = 0.35
	ball_light.light_color = Color(1.0, 0.3, 0.22)
	ball.add_child(ball_light)
	# śmigło
	var prop := Node3D.new()
	prop.name = "Prop"
	for k in 2:
		var bl := _pm(prop, _bm(Vector3(1.1, 0.03, 0.12)), kit.mats.silver, Vector3(0, 0.42, 0))
		bl.rotation.y = k * PI / 2.0
	prop.visible = false
	ball.add_child(prop)
	var sh := MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = 0.6
	shm.height = 1.2
	sh.mesh = shm
	var shmat := kit.mat(Color(0.3, 0.7, 1.0, 0.25), 0.0, 0.3, Color(0.3, 0.7, 1.0), 1.4)
	shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.material_override = shmat
	sh.name = "Shield"
	sh.visible = false
	ball.add_child(sh)
	root.add_child(ball)

# ------------------------------------------------------------------- gra
func _new_game() -> void:
	for p in platforms:
		(p.node as Node).queue_free()
	for e in enemies:
		(e.node as Node).queue_free()
	platforms.clear()
	enemies.clear()
	for c in world.get_children():
		c.queue_free()
	for r in rails:
		(r.node as Node).queue_free()
	rails.clear()
	rails_z = 8.0
	if panel:
		panel.queue_free()
		panel = null
	state = "play"
	height = 0.0
	bonus = 0
	saved = false
	fan_t = 0.0
	t_game = 0.0
	for k in fx_t:
		fx_t[k] = 0.0
	bx = 0.0
	bz = 0.0
	vx = 0.0
	vz = -JUMP
	cam_z = -2.0
	# platforma startowa i pierwsze platformy
	_add_platform(0.0, 0.9, 0, true)
	gen_z = 0.9
	_generate(cam_z - view_half - 6.0)
	_ensure_rails()

func _difficulty() -> float:
	return clampf(height / 320.0, 0.0, 1.0)

func _generate(until_z: float) -> void:
	# Główna ścieżka: platformy zwykłe / ruchome z odstępem zawsze w zasięgu skoku (szczyt skoku ~4.0).
	# Kruche platformy są tylko dodatkiem w połowie odstępu (nie można się od nich odbić).
	while gen_z > until_z:
		var d := _difficulty()
		var gap := randf_range(1.5, lerpf(2.6, 3.4, d))
		var prev_z := gen_z
		gen_z -= gap
		var kind := 1 if randf() < 0.1 + 0.2 * d else 0
		_add_platform(randf_range(-FIELD + 1.0, FIELD - 1.0), gen_z, kind, false)
		if gap > 1.9 and randf() < 0.1 + 0.3 * d:
			_add_platform(randf_range(-FIELD + 1.0, FIELD - 1.0), prev_z - gap * randf_range(0.35, 0.65), 2, false)

func _add_platform(x: float, z: float, kind: int, start: bool) -> void:
	var key := "n%d" % (randi() % 3)
	if kind == 1:
		key = "move"
	elif kind == 2:
		key = "break"
	var node := Node3D.new()
	node.add_child((protos[key] as Node3D).duplicate())
	world.add_child(node)
	var p := {"node": node, "x": x, "base_x": x, "z": z, "kind": kind, "phase": randf() * TAU, "amp": randf_range(1.0, 2.0),
		"spd": randf_range(1.0, 1.8), "item": "", "item_node": null, "broken": false, "w": PLAT_W}
	if kind == 0 and not start:
		var r := randf()
		if r < 0.08:
			p.item = "spring"
			var sn := (protos["spring"] as Node3D).duplicate() as Node3D
			sn.position = Vector3(randf_range(-0.5, 0.5), 0.3, 0)
			node.add_child(sn)
			p.item_node = sn
		elif r < 0.13:
			var types: Array = PU.keys()
			var pt: String = types[randi() % types.size()]
			if not PU[pt].good and randf() < 0.5:
				pt = ["shield", "fan", "life", "wide"][randi() % 4]
			var info: Dictionary = PU[pt]
			var pn := PickupKit.build(kit, info.shape, Vector3.ZERO, info.col, info.good)
			pn.position = Vector3(randf_range(-0.5, 0.5), 0.2, 0)
			node.add_child(pn)
			p.item = pt
			p.item_node = pn
		elif r < 0.13 + 0.03 + 0.08 * _difficulty() and z < -12.0:
			_add_enemy(x + randf_range(-0.6, 0.6), z - 0.9)
	node.position = Vector3(x, 0, z)
	platforms.append(p)

func _add_enemy(x: float, z: float) -> void:
	var node := (_enemy_proto() as Node3D)
	world.add_child(node)
	node.position = Vector3(x, 0, z)
	enemies.append({"node": node, "x": x, "z": z, "base_x": x, "phase": randf() * TAU})

func _enemy_proto() -> Node3D:
	var n := Node3D.new()
	var col := Color(1.0, 0.2, 0.8)
	var body := kit.mat(Color(col.r * 0.3, col.g * 0.3, col.b * 0.3), 0.2, 0.4, col, 1.2)
	var eye := kit.mat(Color(1, 1, 1), 0.0, 0.3, Color(1, 1, 1), 3.0)
	var sm := SphereMesh.new()
	sm.radius = 0.36
	sm.height = 0.72
	_pm(n, sm, body, Vector3(0, 0.34, 0))
	for k in 8:
		var a := k * TAU / 8.0
		var sp := _pm(n, _bm(Vector3(0.07, 0.07, 0.3)), body, Vector3(cos(a) * 0.42, 0.3, sin(a) * 0.42))
		sp.rotation.y = -a
	_pm(n, _bm(Vector3(0.12, 0.06, 0.1)), eye, Vector3(-0.12, 0.62, -0.1))
	_pm(n, _bm(Vector3(0.12, 0.06, 0.1)), eye, Vector3(0.12, 0.62, -0.1))
	return n

func _ensure_rails() -> void:
	var top := cam_z - view_half - 8.0
	while rails_z > top:
		var band := Node3D.new()
		root.add_child(band)
		var z0 := rails_z
		for k in 10:
			var z := z0 - k
			for sgn in [-1, 1]:
				kit.begin_part(Vector3(sgn * (FIELD + 0.5), 0, z), 0.0)
				kit.part(int(kit._hash2(sgn * 3.0 + z, z * 5.0 + 2.0) * 12.0) % 12, k)
		kit.flush(band)
		rails.append({"node": band, "z": z0 - 5.0})
		rails_z -= 10.0
	for k in range(rails.size() - 1, -1, -1):
		if rails[k].z > cam_z + view_half + 14.0:
			(rails[k].node as Node).queue_free()
			rails.remove_at(k)

# --------------------------------------------------------------- sterowanie
func _calibrate(quiet := false) -> void:
	if OS.has_feature("mobile"):
		calib = Input.get_gravity().x
	if not quiet:
		Audio.play_sfx("calib")
		_toast("SKALIBROWANO", true)

func _read_input() -> float:
	var a := float(btn_dir)
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		a -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		a += 1.0
	if OS.has_feature("mobile"):
		var t := -(Input.get_gravity().x - calib) / 9.81
		if Settings.invert_x:
			t = -t
		t *= Settings.sensitivity
		if absf(t) > 0.03:
			a += clampf(t * 2.6, -1.4, 1.4)
	if fx_t.rev > 0.0:
		a = -a
	return clampf(a, -1.4, 1.4)

# ------------------------------------------------------------------ fizyka
func _physics_process(delta: float) -> void:
	for k in fx_t:
		if fx_t[k] > 0.0 and state == "play":
			fx_t[k] = maxf(0.0, fx_t[k] - delta)
	if state != "play":
		return
	t_game += delta
	# poziome
	vx = lerpf(vx, _read_input() * 7.5, 1.0 - exp(-delta * 9.0))
	var prev_z := bz
	bx += vx * delta
	if bx > FIELD + 0.2:
		bx = -FIELD - 0.2
	elif bx < -FIELD - 0.2:
		bx = FIELD + 0.2
	# pionowe
	if fan_t > 0.0:
		fan_t -= delta
		vz = lerpf(vz, -10.0, 1.0 - exp(-delta * 8.0))
		if fan_t <= 0.0:
			vz = -4.0
	else:
		vz += GRAV * delta
	vz = clampf(vz, -30.0, 22.0)
	bz += vz * delta
	_update_platforms(delta, prev_z)
	_update_enemies(delta, prev_z)
	# wysokość i kamera
	height = maxf(height, -bz)
	var target := bz - 2.2
	if target < cam_z:
		cam_z = lerpf(cam_z, target, 1.0 - exp(-delta * 8.0))
	camera.position = Vector3(0, cam_dist, cam_z)
	board_mesh.position = Vector3(0, -0.1, cam_z)
	(kit.mats.pcb as ShaderMaterial).set_shader_parameter("scroll", Vector2(0, cam_z))
	_generate(cam_z - view_half - 6.0)
	_ensure_rails()
	# usuwanie poniżej ekranu
	for k in range(platforms.size() - 1, -1, -1):
		if platforms[k].z > cam_z + view_half + 3.0:
			(platforms[k].node as Node).queue_free()
			platforms.remove_at(k)
	for k in range(enemies.size() - 1, -1, -1):
		if enemies[k].z > cam_z + view_half + 3.0:
			(enemies[k].node as Node).queue_free()
			enemies.remove_at(k)
	# upadek
	if bz > cam_z + view_half + 1.0:
		_fall()
	_update_visuals(delta)
	_update_charge(delta)

func _land(p: Dictionary) -> void:
	if p.kind == 2:
		p.broken = true
		Audio.play_sfx("crack")
		Settings.vibrate(15)
		var node: Node3D = p.node
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "position:z", p.z + 3.0, 0.8).set_ease(Tween.EASE_IN)
		tw.tween_property(node, "rotation:y", 1.2, 0.8)
		tw.tween_property(node, "scale", Vector3.ZERO, 0.8)
		fx.sparks(Vector3(p.x, 0.3, p.z), 8)
		return
	vz = -JUMP
	if p.item == "spring":
		vz = -SPRING_V
		Audio.play_sfx("spring")
		Settings.vibrate(20)
		fx.sparks(Vector3(p.x, 0.4, p.z), 10)
	else:
		Audio.play_sfx("bounce", -4.0, randf_range(0.95, 1.1))
	var node2: Node3D = p.node
	node2.scale = Vector3(1.0, 0.8, 1.0)
	create_tween().tween_property(node2, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	var mesh: Node3D = ball.get_node("Mesh")
	mesh.scale = Vector3(1.25, 0.8, 1.25)
	create_tween().tween_property(mesh, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK)

func _update_platforms(delta: float, prev_z: float) -> void:
	for p in platforms:
		var wmul := 1.0
		if fx_t.wide > 0.0:
			wmul = 1.45
		elif fx_t.narrow > 0.0:
			wmul = 0.62
		p.w = PLAT_W * wmul
		if p.kind == 1:
			p.x = clampf(p.base_x + sin(t_game * p.spd + p.phase) * p.amp, -FIELD + 1.0, FIELD - 1.0)
		if not p.broken:
			(p.node as Node3D).position = Vector3(p.x, 0, p.z)
			(p.node as Node3D).scale.x = wmul if (p.node as Node3D).scale.y > 0.99 else (p.node as Node3D).scale.x
		# lądowanie: tylko przy spadaniu, gdy dolna krawędź kulki przekracza górną krawędź platformy
		if vz > 0.0 and fan_t <= 0.0 and not p.broken:
			var top: float = p.z - PLAT_H / 2.0
			if prev_z + BALL_R <= top + 0.05 and bz + BALL_R >= top and absf(bx - p.x) < p.w / 2.0 + BALL_R * 0.4:
				bz = top - BALL_R
				_land(p)
				if p.kind == 2:
					continue
		# przedmioty na platformie
		if p.item != "" and p.item != "spring" and p.item_node != null:
			var it: Node3D = p.item_node
			var body := it.get_node_or_null("Body")
			if body:
				(body as Node3D).rotation.y += delta * 2.5
			if Vector2(bx - p.x - it.position.x, bz - p.z).length() < 0.75:
				_collect(p)

func _update_enemies(delta: float, prev_z: float) -> void:
	for k in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[k]
		e.x = e.base_x + sin(t_game * 0.9 + e.phase) * 0.7
		(e.node as Node3D).position = Vector3(e.x, 0, e.z)
		(e.node as Node3D).rotation.y += delta * 1.2
		if Vector2(bx - e.x, bz - e.z).length() < 0.62:
			if vz > 0.0 and prev_z < e.z - 0.05:
				# skok na wirusa z góry
				bonus += 200
				vz = -JUMP * 1.05
				Audio.play_sfx("hit")
				Settings.vibrate(25)
				fx.sparks(Vector3(e.x, 0.4, e.z), 24, true)
				fx.light_flash(Vector3(e.x, 0, e.z), Color(1.0, 0.4, 0.9), 2.5)
				(e.node as Node).queue_free()
				enemies.remove_at(k)
			elif fx_t.shield > 0.0:
				fx.sparks(Vector3(e.x, 0.4, e.z), 16, true)
				Audio.play_sfx("tink")
				(e.node as Node).queue_free()
				enemies.remove_at(k)
			else:
				_game_over("ZAINFEKOWANY")
				return

func _collect(p: Dictionary) -> void:
	var type: String = p.item
	var info: Dictionary = PU[type]
	var good: bool = info.good
	(p.item_node as Node).queue_free()
	p.item_node = null
	p.item = ""
	fx.sparks(Vector3(p.x, 0.4, p.z), 20, true)
	fx.light_flash(Vector3(p.x, 0, p.z), Color(0.4, 1.0, 0.6) if good else Color(1.0, 0.3, 0.2), 2.5)
	Audio.play_sfx("pu_good" if good else "pu_bad")
	Settings.vibrate(25)
	match type:
		"fan":
			fan_t = 3.0
			Audio.play_sfx("fan")
		"life":
			saved = true
		_:
			fx_t[type] = float(info.dur)
			if type == "wide":
				fx_t.narrow = 0.0
			elif type == "narrow":
				fx_t.wide = 0.0
	_toast("%s\n%s" % [info.name, info.desc], good)

func _fall() -> void:
	if saved:
		saved = false
		vz = -22.0
		bz = cam_z + view_half - 1.0
		Audio.play_sfx("spring")
		fx.sparks(Vector3(bx, 0.3, bz), 30, true)
		_toast("ZWORKA URATOWAŁA KULKĘ!", true)
		return
	_game_over("SPADŁEŚ")

func _game_over(reason: String) -> void:
	if state == "over":
		return
	state = "over"
	var sc := _score()
	var high := Save.get_int("pmuj", "high", 0)
	var record := sc > high
	if record:
		Save.set_int("pmuj", "high", sc)
	Audio.play_sfx("drain")
	Settings.vibrate(70)
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.0, 0.1, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -270
	box.offset_bottom = 270
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)
	var t := UiKit.label(reason, 40, UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := UiKit.label("WYNIK %d\nWYSOKOŚĆ %d m" % [sc, int(height)], 24, UiKit.C_YELLOW, 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	var hs := UiKit.label("NOWY REKORD!" if record else "REKORD: %d" % high, 16, UiKit.C_GREEN if record else UiKit.C_CYAN, 6)
	hs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hs)
	box.add_child(_panel_btn("NOWA GRA", UiKit.C_GREEN, _new_game))
	box.add_child(_panel_btn("MENU", UiKit.C_CYAN, _go_menu))
	ui.add_child(panel)

func _panel_btn(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(b, 24, col)
	b.pressed.connect(func():
		Audio.play_sfx("coin")
		cb.call())
	return b

func _score() -> int:
	return int(height * 10.0) + bonus

# ----------------------------------------------------- wizualizacja kulki i efekty
func _update_visuals(delta: float) -> void:
	ball.position = Vector3(bx, BALL_R, bz)
	spin += delta * 3.0
	var mesh: Node3D = ball.get_node("Mesh")
	mesh.rotation.z -= vx * delta * 0.4
	mesh.rotation.x += vz * delta * 0.3
	var prop: Node3D = ball.get_node("Prop")
	prop.visible = fan_t > 0.0
	prop.rotation.y += delta * 40.0
	(ball.get_node("Shield") as Node3D).visible = fx_t.shield > 0.0
	for a in arcs:
		(a as Discharger).update(delta)

func _update_charge(delta: float) -> void:
	if not Settings.effects:
		ball_mat.set_shader_parameter("charge", 0.2)
		return
	charge += delta * (0.4 + absf(vz) * 0.03)
	var c := clampf(charge / charge_goal, 0.0, 1.0)
	ball_mat.set_shader_parameter("charge", 0.35 + 0.65 * c)
	ball_light.light_energy = (0.45 + c * 0.7) * randf_range(0.75, 1.35)
	if charge >= charge_goal:
		var best: Dictionary = {}
		var bd := 3.4
		for p in platforms:
			var d := Vector2(p.x - bx, p.z - bz).length()
			if d < bd and d > 0.9 and not p.broken:
				bd = d
				best = p
		if not best.is_empty():
			charge = 0.0
			charge_goal = randf_range(0.7, 1.4)
			var to := Vector3(best.x, 0.4, best.z)
			_arc(Vector3(bx, 0.3, bz), to, 0.4)
			fx.sparks(to, 14)
			fx.light_flash(to, Color(0.6, 0.9, 1.0), 2.5)
			Audio.play_sfx("discharge", -4.0, randf_range(0.9, 1.15))
			Settings.vibrate(8)
			bonus += 10
			ball_mat.set_shader_parameter("flash", 1.0)
			create_tween().tween_method(func(v: float): ball_mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.5)

func _arc(from: Vector3, to: Vector3, dur := 0.4) -> void:
	if not Settings.effects:
		return
	var d: Discharger = arcs[arc_idx]
	arc_idx = (arc_idx + 1) % arcs.size()
	var m := Marker3D.new()
	root.add_child(m)
	m.position = from
	get_tree().create_timer(0.8, false).timeout.connect(m.queue_free)
	d.fire(m, to, dur)

# --------------------------------------------------------------------------------- UI
func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 14
	top.offset_right = -14
	top.offset_top = 22
	top.offset_bottom = 88
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
	lbl_info.position = Vector2(20, 100)
	ui.add_child(lbl_info)
	lbl_fx = RichTextLabel.new()
	lbl_fx.bbcode_enabled = true
	lbl_fx.fit_content = true
	lbl_fx.scroll_active = false
	lbl_fx.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_fx.position = Vector2(20, 128)
	lbl_fx.custom_minimum_size = Vector2(672, 40)
	lbl_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_fx.add_theme_font_size_override("normal_font_size", 16)
	lbl_fx.add_theme_constant_override("outline_size", 6)
	lbl_fx.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_fx)
	lbl_toast = UiKit.label("", 24, Color.WHITE, 10)
	lbl_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_toast.offset_top = 250
	lbl_toast.offset_bottom = 380
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.modulate.a = 0.0
	ui.add_child(lbl_toast)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 14
	bottom.offset_right = -14
	bottom.offset_top = -140
	bottom.offset_bottom = -28
	bottom.add_theme_constant_override("separation", 12)
	ui.add_child(bottom)
	bottom.add_child(_dir_btn("<", -1))
	var cal := _btn("KALIBR.", func(): _calibrate(false))
	cal.custom_minimum_size = Vector2(190, 0)
	bottom.add_child(cal)
	bottom.add_child(_dir_btn(">", 1))

func _dir_btn(text: String, d: int) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(b, 40, UiKit.C_CYAN)
	b.button_down.connect(func():
		if overlay == null:
			btn_dir = d)
	b.button_up.connect(func():
		if btn_dir == d:
			btn_dir = 0)
	return b

func _btn(text: String, cb: Callable, snd := "click") -> Button:
	var b := Button.new()
	b.text = text
	UiKit.style_button(b, 16, UiKit.C_CYAN)
	b.pressed.connect(func():
		Audio.play_sfx(snd)
		cb.call())
	return b

func _toast(text: String, good: bool) -> void:
	lbl_toast.text = text
	lbl_toast.add_theme_color_override("font_color", Color("7dffb0") if good else Color("ff6a5a"))
	if toast_tw:
		toast_tw.kill()
	lbl_toast.modulate.a = 1.0
	toast_tw = create_tween()
	toast_tw.tween_interval(2.0)
	toast_tw.tween_property(lbl_toast, "modulate:a", 0.0, 0.5)

func _process(_d: float) -> void:
	lbl_score.text = str(_score())
	lbl_info.text = "WYSOKOŚĆ %d m   REKORD %d" % [int(height), Save.get_int("pmuj", "high", 0)]
	var parts := PackedStringArray()
	if saved:
		parts.append("[color=#7dffb0]ZWORKA[/color]")
	for k in fx_t:
		if fx_t[k] > 0.0:
			var info: Dictionary = PU[k]
			parts.append("[color=%s]%s %d s[/color]" % ["#7dffb0" if info.good else "#ff6a5a", info.name, ceili(fx_t[k])])
	var txt := "   ".join(parts)
	if txt != fx_text_cache:
		fx_text_cache = txt
		lbl_fx.text = txt

func _open_options() -> void:
	if overlay:
		return
	btn_dir = 0
	var p := OptionsPanel.new()
	p.closed.connect(_close_overlay)
	overlay = p
	ui.add_child(p)
	get_tree().paused = true

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null
	get_tree().paused = false

func _go_menu() -> void:
	Audio.play_music("menu")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if overlay:
			_close_overlay()
		else:
			_go_menu()
