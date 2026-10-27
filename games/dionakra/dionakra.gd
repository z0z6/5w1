extends Node3D
## Dionakra - kulka, paletka i cegły-elementy elektroniczne na płytce PCB. Fizyka kulki liczona własnym kodem
## (stała prędkość, kąt odbicia zależny od miejsca uderzenia w paletkę). Sterowanie: palec przesuwa paletkę,
## dotknięcie wystrzeliwuje kulkę. Klawiatura: strzałki + spacja.

const FIELD := 5.0                   # połowa szerokości pola gry
const BR_COLS := 10
const BRICK_H := 0.55
const BALL_R := 0.22
const PAD_H := 0.36
const CAM_FOV := 40.0
const HUD_TOP_PX := 230.0
const CTRL_PX := 190.0
const MAX_LEVEL := 30
const BRICK_COL := [Color(0.1, 0.3, 0.9), Color(0.07, 0.07, 0.09), Color(0.0, 0.6, 0.3),
	Color(0.9, 0.65, 0.05), Color(0.75, 0.35, 0.1), Color(0.7, 0.08, 0.1)]
const PU := {
	"wide": {"name": "SZERSZA PALETA", "desc": "15 s", "good": true, "dur": 15.0, "col": Color(0.75, 0.9, 1.0), "shape": "big"},
	"slow": {"name": "SPOWOLNIENIE", "desc": "wolniejsza kulka 12 s", "good": true, "dur": 12.0, "col": Color(0.6, 0.9, 1.0), "shape": "heat"},
	"multi": {"name": "MULTIBALL", "desc": "+2 kulki", "good": true, "dur": 0.0, "col": Color(0.4, 1.0, 0.4), "shape": "multi"},
	"laser": {"name": "WYŁADOWANIA", "desc": "paletka strzela 12 s", "good": true, "dur": 12.0, "col": Color(0.85, 1.0, 0.2), "shape": "scan"},
	"catch": {"name": "MAGNES", "desc": "kulka przykleja się 15 s", "good": true, "dur": 15.0, "col": Color(0.4, 0.7, 1.0), "shape": "insul"},
	"pierce": {"name": "PRZEBICIE", "desc": "kulka przelatuje 8 s", "good": true, "dur": 8.0, "col": Color(1.0, 0.85, 0.2), "shape": "jumper"},
	"life": {"name": "ŻYCIE", "desc": "+1 kulka", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.35), "shape": "batt"},
	"narrow": {"name": "WĄSKA PALETA", "desc": "12 s", "good": false, "dur": 12.0, "col": Color(1.0, 0.45, 0.1), "shape": "small"},
	"fast": {"name": "SZYBKA KULA", "desc": "12 s", "good": false, "dur": 12.0, "col": Color(1.0, 0.25, 0.1), "shape": "surge"},
	"rev": {"name": "ODWROTNA POLARYZACJA", "desc": "sterowanie odwrócone 10 s", "good": false, "dur": 10.0, "col": Color(0.85, 0.35, 1.0), "shape": "rev"},
	"stun": {"name": "ZWARCIE PALETY", "desc": "paletka stoi 1.5 s", "good": false, "dur": 1.5, "col": Color(1.0, 0.1, 0.15), "shape": "mine"},
}

var root: Node3D
var kit: PcbKit
var fx: Fx
var camera: Camera3D
var board_w := 12.2
var board_d := 24.0
var ppu := 65.0
var vp := Vector2(720, 1600)
var z_top := -8.0
var paddle_z := 7.0
var protos: Dictionary = {}
var mark_mat: StandardMaterial3D
var arcs: Array = []
var arc_idx := 0
var bricks_root: Node3D
var misc_root: Node3D

var bricks: Array = []
var brick_grid: Dictionary = {}
var balls: Array = []
var capsules: Array = []
var paddle: Node3D
var pad_vis: Node3D
var paddle_x := 0.0
var target_x := 0.0
var pw := 2.0
var touching := false
var btn_dir := 0
var state := "ready"           # ready / play / end / over
var level := 1
var lives := 3
var score := 0
var combo := 0
var laser_t := 0.0
var fx_t := {"wide": 0.0, "narrow": 0.0, "slow": 0.0, "fast": 0.0, "catch": 0.0, "laser": 0.0, "pierce": 0.0, "rev": 0.0, "stun": 0.0}
var overlay: Control
var result_panel: Control

var ui: CanvasLayer
var lbl_score: Label
var lbl_info: Label
var lbl_fx: RichTextLabel
var lbl_toast: Label
var lbl_hint: Label
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
	_setup_camera_and_layout()
	_build_board()
	_build_protos()
	for i in 8:
		arcs.append(Discharger.new(root))
	bricks_root = Node3D.new()
	root.add_child(bricks_root)
	misc_root = Node3D.new()
	root.add_child(misc_root)
	_build_paddle()
	_setup_ui()
	Audio.play_music("dionakra")
	_start_level(clampi(Save.get_int("dionakra", "unlocked", 1), 1, MAX_LEVEL))
	_schedule_ambient()

# ------------------------------------------------------ środowisko, kamera, układ
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
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

func _setup_camera_and_layout() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAM_FOV
	add_child(camera)
	var w := FIELD * 2.0 + 2.6
	vp = get_viewport().get_visible_rect().size
	var half_tan := tan(deg_to_rad(CAM_FOV / 2.0))
	var dist := (w / 2.0) / half_tan + 0.7
	var plane_w := 2.0 * dist * half_tan
	ppu = vp.x / plane_w
	var half_h := vp.y / ppu / 2.0
	board_w = maxf(w, plane_w * 1.1)
	board_d = maxf(24.0, half_h * 2.0 * 1.1)
	camera.position = Vector3(0, dist, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	z_top = _sy(HUD_TOP_PX) + 1.0                 # wewnętrzna krawędź górnej ściany
	paddle_z = _sy(vp.y - CTRL_PX - 40.0)

func _sy(py: float) -> float:
	return (py - vp.y / 2.0) / ppu

func _screen_x(px: float) -> float:
	return (px - vp.x / 2.0) / ppu

func _build_board() -> void:
	var fh := paddle_z - z_top + 3.0
	kit.add_board(board_w, board_d, Vector2(FIELD + 1.3, fh / 2.0 + 0.5), 4242)
	# ramka: lewa, prawa, góra
	var i := 0
	var z := z_top - 1.0
	var zb := paddle_z + 1.5
	while z <= zb:
		for sgn in [-1, 1]:
			kit.begin_part(Vector3(sgn * (FIELD + 0.5), 0, z), 0.0)
			kit.part(int(kit._hash2(sgn * 3.0 + z, z * 5.0 + 2.0) * 12.0) % 12, i)
			i += 1
		z += 1.0
	for gx in range(-int(FIELD) - 1, int(FIELD) + 2):
		kit.begin_part(Vector3(gx + 0.0, 0, z_top - 0.5), 0.0)
		kit.part(int(kit._hash2(gx * 3.0 + 1.0, 7.0) * 12.0) % 12, i)
		i += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var occ := {}
	kit.add_bus(-2.0, paddle_z + 2.0, 1, 2, rng, occ, board_d)
	kit.add_bus(2.2, paddle_z + 2.0, 1, 2, rng, occ, board_d)
	kit.add_decor(FIELD * 2.0 + 2.6, 2.0 * maxf(absf(z_top), absf(paddle_z)) + 3.0, occ, board_w, board_d)
	kit.flush(root)

# --------------------------------------------------------------- modele cegieł
func _build_protos() -> void:
	mark_mat = kit.mat(Color(1.0, 0.9, 0.3), 0.0, 0.3, Color(1.0, 0.9, 0.3), 3.0)
	var tw := create_tween().set_loops()
	tw.tween_property(mark_mat, "emission_energy_multiplier", 5.5, 0.5)
	tw.tween_property(mark_mat, "emission_energy_multiplier", 1.5, 0.5)
	for c in 6:
		protos["n%d" % c] = _brick_proto(c)
	protos["hard2"] = _hard_proto(false)
	protos["hard1"] = _hard_proto(true)
	protos["steel"] = _steel_proto()
	protos["boom"] = _boom_proto()

func _base(n: Node3D, col: Color, metal := 0.3) -> void:
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mat(col, metal, 0.45), Vector3(0.94, 0.28, 0.5), Vector3(0, 0.14, 0))
	kit.box(kit.mat(col.lightened(0.25), 0.4, 0.35), Vector3(0.72, 0.04, 0.34), Vector3(0, 0.3, 0))

func _brick_proto(c: int) -> Node3D:
	var n := Node3D.new()
	_base(n, BRICK_COL[c])
	match c:
		0:
			kit.box(kit.mats.white, Vector3(0.5, 0.02, 0.1), Vector3(0, 0.33, 0))
		1:
			kit.box(kit.mats.chip_mark, Vector3(0.08, 0.02, 0.08), Vector3(-0.32, 0.33, -0.12))
			for i in 4:
				kit.box(kit.mats.silver, Vector3(0.07, 0.05, 0.1), Vector3(-0.35 + i * 0.23, 0.07, 0.26))
				kit.box(kit.mats.silver, Vector3(0.07, 0.05, 0.1), Vector3(-0.35 + i * 0.23, 0.07, -0.26))
		2:
			kit.cyl(kit.mats.led[1], 0.13, 0.14, Vector3(0, 0.38, 0), 12)
		3:
			kit.box(kit.mats.chip, Vector3(0.1, 0.05, 0.4), Vector3(-0.25, 0.33, 0))
		4:
			kit.box(kit.mats.gold, Vector3(0.6, 0.02, 0.08), Vector3(0, 0.33, 0))
		_:
			kit.box(kit.mats.silver, Vector3(0.08, 0.3, 0.5), Vector3(-0.43, 0.15, 0))
			kit.box(kit.mats.silver, Vector3(0.08, 0.3, 0.5), Vector3(0.43, 0.15, 0))
	kit.flush(n)
	return n

func _hard_proto(damaged: bool) -> Node3D:
	var n := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mats.alu, Vector3(0.94, 0.12, 0.5), Vector3(0, 0.06, 0))
	for i in 6:
		kit.box(kit.mats.alu, Vector3(0.08, 0.26, 0.46), Vector3(-0.37 + i * 0.148, 0.2, 0))
	if damaged:
		kit.box(kit.mats.black, Vector3(0.5, 0.05, 0.06), Vector3(-0.1, 0.33, 0.05))
		kit.box(kit.mats.black, Vector3(0.06, 0.05, 0.3), Vector3(0.2, 0.33, 0.0))
	else:
		kit.box(kit.mats.gold, Vector3(0.9, 0.02, 0.06), Vector3(0, 0.34, 0))
	kit.flush(n)
	return n

func _steel_proto() -> Node3D:
	var n := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mats.black, Vector3(0.94, 0.32, 0.5), Vector3(0, 0.16, 0))
	for i in 7:
		kit.cyl(kit.mats.gold, 0.05, 0.1, Vector3(-0.36 + i * 0.12, 0.37, 0.13), 8)
		kit.cyl(kit.mats.gold, 0.05, 0.1, Vector3(-0.36 + i * 0.12, 0.37, -0.13), 8)
	kit.flush(n)
	return n

func _boom_proto() -> Node3D:
	var n := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mat(Color(0.95, 0.3, 0.05), 0.3, 0.4), Vector3(0.94, 0.3, 0.5), Vector3(0, 0.15, 0))
	kit.box(mark_mat, Vector3(0.7, 0.04, 0.12), Vector3(0, 0.33, 0))
	for i in 3:
		kit.box(kit.mats.warn, Vector3(0.08, 0.03, 0.46), Vector3(-0.38 + i * 0.38, 0.31, 0))
	kit.flush(n)
	return n

# ------------------------------------------------------------------------ paletka
func _build_paddle() -> void:
	paddle = Node3D.new()
	paddle.position = Vector3(0, 0, paddle_z)
	root.add_child(paddle)
	pad_vis = Node3D.new()
	paddle.add_child(pad_vis)
	var base := kit.mat(Color(0.08, 0.08, 0.1), 0.6, 0.3)
	_pm(pad_vis, _bm(Vector3(1.0, 0.34, PAD_H)), base, Vector3(0, 0.17, 0))
	_pm(pad_vis, _bm(Vector3(1.0, 0.04, 0.2)), kit.mats.gold, Vector3(0, 0.36, 0))
	var tip := kit.mat(Color(0.3, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.15, 0.1), 1.5)
	_pm(pad_vis, _bm(Vector3(0.14, 0.4, PAD_H + 0.06)), tip, Vector3(-0.5, 0.2, 0))
	_pm(pad_vis, _bm(Vector3(0.14, 0.4, PAD_H + 0.06)), tip, Vector3(0.5, 0.2, 0))

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

# ----------------------------------------------------------------------- poziomy
func _gen_level(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5381 + n * 131
	var rows := clampi(4 + n / 3, 4, 9)
	var template := (n - 1) % 8
	var list: Array = []
	var cells := {}
	for gy in rows:
		for gx in BR_COLS:
			var m := mini(gx, BR_COLS - 1 - gx)           # symetria lewo-prawo
			var keep := false
			match template:
				0: keep = true
				1: keep = (m + gy) % 2 == 0
				2: keep = float(4 - m) + gy * 1.1 < 5.5
				3: keep = m % 2 == 0 or gy % 3 == 0
				4: keep = m < 2 or gy % 2 == 0
				5: keep = absf(m - 4.5) + absf(gy - (rows - 1) / 2.0) <= rows / 2.0 + 1.2
				6: keep = (m + gy) % 3 != 0
				_: keep = gy == 0 or gy == rows - 1 or m == 0 or (m >= 2 and gy == rows / 2)
			if keep:
				cells[Vector2i(gx, gy)] = {"gx": gx, "gy": gy, "kind": 0, "color": (gy + (m / 2 if template >= 3 else 0)) % 6}
	var keys: Array = cells.keys()
	# cegły wzmocnione (2 uderzenia), od poziomu 3
	var hard_p := clampf((n - 2) * 0.03, 0.0, 0.45)
	for k in keys:
		if rng.randf() < hard_p:
			cells[k].kind = 1
	# wybuchowe od poziomu 2
	var nb := mini(1 + n / 6, 5) if n >= 2 else 0
	for i in nb:
		var k: Vector2i = keys[rng.randi() % keys.size()]
		cells[k].kind = 3
	# niezniszczalne od poziomu 4 (nigdy sąsiadujące, nie więcej niż 10%)
	var ns := mini(n / 4, maxi(1, keys.size() / 10)) if n >= 4 else 0
	for i in ns:
		var k: Vector2i = keys[rng.randi() % keys.size()]
		var ok: bool = cells[k].kind == 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cells.has(k + d) and cells[k + d].kind == 2:
				ok = false
		if ok:
			cells[k].kind = 2
	for k in cells:
		list.append(cells[k])
	return list

func _start_level(n: int) -> void:
	level = n
	if result_panel:
		result_panel.queue_free()
		result_panel = null
	for c in bricks_root.get_children():
		c.queue_free()
	for c in misc_root.get_children():
		c.queue_free()
	bricks.clear()
	brick_grid.clear()
	capsules.clear()
	balls.clear()
	for k in fx_t:
		fx_t[k] = 0.0
	combo = 0
	for d in _gen_level(n):
		_add_brick(d)
	_apply_pad_width(true)
	paddle_x = 0.0
	target_x = 0.0
	state = "ready"
	_spawn_ball_on_paddle()
	_toast("POZIOM %d" % level, true)
	Audio.play_sfx("level")

func _brick_pos(gx: int, gy: int) -> Vector3:
	return Vector3(-FIELD + 0.5 + gx, 0.0, z_top + 1.3 + gy * BRICK_H)

func _add_brick(d: Dictionary) -> void:
	var kind: int = d.kind
	var key := "n%d" % int(d.color)
	if kind == 1:
		key = "hard2"
	elif kind == 2:
		key = "steel"
	elif kind == 3:
		key = "boom"
	var node := Node3D.new()
	node.add_child((protos[key] as Node3D).duplicate())
	var pos := _brick_pos(d.gx, d.gy)
	node.position = pos
	bricks_root.add_child(node)
	node.scale = Vector3.ZERO
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.25).set_delay(d.gy * 0.05 + d.gx * 0.01).set_trans(Tween.TRANS_BACK)
	var b := {"gx": d.gx, "gy": d.gy, "kind": kind, "hp": 2 if kind == 1 else 1, "node": node, "pos": pos, "alive": true, "color": d.color}
	bricks.append(b)
	brick_grid[Vector2i(d.gx, d.gy)] = b

func _breakable_left() -> int:
	var n := 0
	for b in bricks:
		if b.alive and b.kind != 2:
			n += 1
	return n

# ---------------------------------------------------------------------------- kule
func _ball_speed() -> float:
	var s := minf(8.5 + 0.2 * level, 12.5)
	if fx_t.slow > 0.0:
		s *= 0.65
	if fx_t.fast > 0.0:
		s *= 1.4
	return s

func _new_ball(pos: Vector3, vel: Vector3, stuck: bool) -> Dictionary:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	mi.mesh = sm
	var bm := (kit.mats.ball as ShaderMaterial).duplicate() as ShaderMaterial
	bm.set_shader_parameter("charge", 0.3)
	mi.material_override = bm
	node.add_child(mi)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.2, 0)
	glow.omni_range = 3.5
	glow.light_energy = 0.35
	glow.light_color = Color(1.0, 0.3, 0.22)
	node.add_child(glow)
	misc_root.add_child(node)
	var b := {"node": node, "mat": bm, "light": glow, "pos": pos, "vel": vel, "stuck": stuck, "off": 0.0,
		"charge": randf() * 0.4, "goal": randf_range(0.8, 1.6)}
	node.position = pos + Vector3(0, BALL_R, 0)
	balls.append(b)
	return b

func _spawn_ball_on_paddle() -> void:
	var b := _new_ball(Vector3(paddle_x, 0.0, paddle_z - PAD_H / 2.0 - BALL_R), Vector3.ZERO, true)
	b.off = 0.0

func _launch() -> void:
	for b in balls:
		if b.stuck:
			var off: float = clampf(b.off / maxf(pw / 2.0, 0.1), -1.0, 1.0)
			var ang := off * 0.6 + randf_range(-0.08, 0.08)
			b.vel = Vector3(sin(ang), 0, -cos(ang)) * _ball_speed()
			b.stuck = false
			Audio.play_sfx("launch", -4.0)
	if state == "ready":
		state = "play"

# ------------------------------------------------------------------- pętla fizyki
func _physics_process(delta: float) -> void:
	for k in fx_t:
		if fx_t[k] > 0.0 and state != "over":
			fx_t[k] = maxf(0.0, fx_t[k] - delta)
	_apply_pad_width(false)
	# sterowanie paletką
	var kx := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		kx -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		kx += 1.0
	kx += float(btn_dir)
	if kx != 0.0:
		target_x = clampf(target_x + kx * 14.0 * delta, -FIELD, FIELD)
	if fx_t.stun <= 0.0 and (state == "play" or state == "ready"):
		var tx := -target_x if fx_t.rev > 0.0 else target_x
		var lim := FIELD - pw / 2.0
		paddle_x = clampf(lerpf(paddle_x, clampf(tx, -lim, lim), 1.0 - exp(-delta * 28.0)), -lim, lim)
	paddle.position.x = paddle_x
	pad_vis.position.y = 0.0
	# kule
	if state == "play" or state == "ready":
		for k in range(balls.size() - 1, -1, -1):
			var b: Dictionary = balls[k]
			if b.stuck:
				b.pos = Vector3(paddle_x + b.off, 0.0, paddle_z - PAD_H / 2.0 - BALL_R)
			else:
				_step_ball(b, delta)
			(b.node as Node3D).position = (b.pos as Vector3) + Vector3(0, BALL_R, 0)
			if not b.stuck and b.pos.z > paddle_z + 1.4:
				_lose_ball(b)
				continue
			_update_charge(b, delta)
		_update_capsules(delta)
		_update_lasers(delta)
	for a in arcs:
		(a as Discharger).update(delta)

func _step_ball(b: Dictionary, dt: float) -> void:
	var sp := _ball_speed()
	var v: Vector3 = b.vel
	if v.length() < 0.01:
		v = Vector3(0, 0, -1)
	v = v.normalized() * sp
	b.vel = v
	var n := maxi(1, ceili(sp * dt / 0.07))
	var h := dt / n
	for i in n:
		b.pos += b.vel * h
		_collide_walls(b)
		_collide_paddle(b)
		if b.stuck:
			return
		_collide_bricks(b)

func _collide_walls(b: Dictionary) -> void:
	var p: Vector3 = b.pos
	var v: Vector3 = b.vel
	var bounced := false
	if p.x < -FIELD + BALL_R:
		p.x = -FIELD + BALL_R
		v.x = absf(v.x)
		bounced = true
	elif p.x > FIELD - BALL_R:
		p.x = FIELD - BALL_R
		v.x = -absf(v.x)
		bounced = true
	if p.z < z_top + BALL_R:
		p.z = z_top + BALL_R
		v.z = absf(v.z)
		bounced = true
	if bounced:
		# zapobiega zbyt płaskim torom
		if absf(v.z) < _ball_speed() * 0.22:
			v.z = signf(v.z if v.z != 0.0 else 1.0) * _ball_speed() * 0.3
		Audio.play_sfx("wall", -6.0, randf_range(0.9, 1.1))
	b.pos = p
	b.vel = v

func _collide_paddle(b: Dictionary) -> void:
	var v: Vector3 = b.vel
	if v.z <= 0.0 or b.stuck:
		return
	var p: Vector3 = b.pos
	var top := paddle_z - PAD_H / 2.0
	if p.z + BALL_R >= top and p.z - BALL_R <= paddle_z + PAD_H / 2.0 and absf(p.x - paddle_x) <= pw / 2.0 + BALL_R * 0.6:
		var off := clampf((p.x - paddle_x) / (pw / 2.0 + BALL_R * 0.5), -1.0, 1.0)
		var ang := off * deg_to_rad(62.0)
		combo = 0
		p.z = top - BALL_R
		b.pos = p
		Audio.play_sfx("paddle", 0.0, randf_range(0.95, 1.05))
		Settings.vibrate(8)
		fx.sparks(Vector3(p.x, 0.3, top), 4)
		if fx_t.catch > 0.0:
			b.stuck = true
			b.off = p.x - paddle_x
			b.vel = Vector3.ZERO
		else:
			b.vel = Vector3(sin(ang), 0, -cos(ang)) * _ball_speed()

func _collide_bricks(b: Dictionary) -> void:
	var p: Vector3 = b.pos
	var gx0 := int(floor((p.x + FIELD) / 1.0))
	var gy0 := int(floor((p.z - (z_top + 1.3 - BRICK_H / 2.0)) / BRICK_H))
	var best: Dictionary = {}
	var best_pen := -1.0
	var best_n := Vector3.ZERO
	for gx in range(gx0 - 1, gx0 + 2):
		for gy in range(gy0 - 1, gy0 + 2):
			var br = brick_grid.get(Vector2i(gx, gy))
			if br == null or not br.alive:
				continue
			var c: Vector3 = br.pos
			var dx := p.x - c.x
			var dz := p.z - c.z
			var cx := clampf(dx, -0.5, 0.5)
			var cz := clampf(dz, -BRICK_H / 2.0, BRICK_H / 2.0)
			var ex := dx - cx
			var ez := dz - cz
			var d2 := ex * ex + ez * ez
			if d2 >= BALL_R * BALL_R:
				continue
			var nrm := Vector3.ZERO
			var pen := 0.0
			if d2 > 0.000001:
				var d := sqrt(d2)
				nrm = Vector3(ex / d, 0, ez / d)
				pen = BALL_R - d
			else:
				# środek kulki wewnątrz cegły - wypchnij po osi o mniejszej penetracji
				var px := 0.5 + BALL_R - absf(dx)
				var pz := BRICK_H / 2.0 + BALL_R - absf(dz)
				if px < pz:
					nrm = Vector3(signf(dx), 0, 0)
					pen = px
				else:
					nrm = Vector3(0, 0, signf(dz))
					pen = pz
			if pen > best_pen:
				best_pen = pen
				best = br
				best_n = nrm
	if best.is_empty():
		return
	var steel: bool = best.kind == 2
	if fx_t.pierce > 0.0 and not steel:
		_damage_brick(best, true)
		return
	b.pos += best_n * best_pen
	var v: Vector3 = b.vel
	if v.dot(best_n) < 0.0:
		v = v - 2.0 * v.dot(best_n) * best_n
		if absf(v.z) < _ball_speed() * 0.2:
			v.z = signf(v.z if v.z != 0.0 else 1.0) * _ball_speed() * 0.3
		b.vel = v
	_damage_brick(best, false)

func _damage_brick(br: Dictionary, kill: bool) -> void:
	if not br.alive:
		return
	var pos: Vector3 = br.pos
	if br.kind == 2:
		Audio.play_sfx("tink", -2.0, randf_range(0.95, 1.1))
		fx.sparks(pos + Vector3(0, 0.4, 0), 4)
		return
	br.hp -= 99 if kill else 1
	if br.hp > 0:
		Audio.play_sfx("clang", 0.0, randf_range(0.95, 1.05))
		Settings.vibrate(8)
		fx.sparks(pos + Vector3(0, 0.4, 0), 6)
		_swap_visual(br, "hard1")
		return
	_break_brick(br)

func _swap_visual(br: Dictionary, key: String) -> void:
	var node: Node3D = br.node
	for c in node.get_children():
		c.queue_free()
	node.add_child((protos[key] as Node3D).duplicate())
	node.scale = Vector3.ONE * 1.15
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.15)

func _break_brick(br: Dictionary) -> void:
	br.alive = false
	var pos: Vector3 = br.pos
	var node: Node3D = br.node
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector3.ZERO, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "rotation:y", 2.5, 0.18)
	tw.chain().tween_callback(node.queue_free)
	combo += 1
	var mult := 1 + mini(combo, 24) / 8
	var pts := (100 if br.kind == 1 else 50) * mult
	score += pts
	Audio.play_sfx("brick", -2.0, randf_range(0.9, 1.15) + minf(combo * 0.012, 0.3))
	Settings.vibrate(8)
	fx.sparks(pos + Vector3(0, 0.4, 0), 10)
	_popup(pos, "+%d" % pts)
	if br.kind == 3:
		_explode(br)
	if randf() < 0.15:
		_spawn_capsule(pos)
	if _breakable_left() == 0 and state == "play":
		_level_done()

func _explode(br: Dictionary) -> void:
	var pos: Vector3 = br.pos
	Audio.play_sfx("boom")
	Settings.vibrate(40)
	fx.sparks(pos + Vector3(0, 0.4, 0), 30, true)
	fx.light_flash(pos, Color(1.0, 0.6, 0.2), 3.5)
	for o in bricks:
		if o.alive and o != br and o.kind != 2:
			var op: Vector3 = o.pos
			if Vector2(op.x - pos.x, op.z - pos.z).length() < 1.7:
				_arc(pos + Vector3(0, 0.4, 0), op + Vector3(0, 0.4, 0), 0.35)
				_damage_brick(o, false)

# ------------------------------------------------------------------- power-upy
func _spawn_capsule(pos: Vector3) -> void:
	var types: Array = PU.keys()
	var pt: String = types[randi() % types.size()]
	if not PU[pt].good and randf() < 0.45:
		pt = ["wide", "slow", "catch", "life", "multi", "laser", "pierce"][randi() % 7]
	var info: Dictionary = PU[pt]
	var node := PickupKit.build(kit, info.shape, Vector3.ZERO, info.col, info.good)
	node.position = pos
	misc_root.add_child(node)
	capsules.append({"type": pt, "node": node, "pos": pos})

func _update_capsules(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for k in range(capsules.size() - 1, -1, -1):
		var c: Dictionary = capsules[k]
		var pos: Vector3 = c.pos
		pos.z += 3.4 * delta
		c.pos = pos
		(c.node as Node3D).position = pos
		var body: Node3D = (c.node as Node3D).get_node("Body")
		body.rotation.y += delta * 3.0
		body.position.y = 0.38 + sin(t * 4.0 + k) * 0.04
		if pos.z > paddle_z - PAD_H / 2.0 - 0.2 and pos.z < paddle_z + 0.4 and absf(pos.x - paddle_x) < pw / 2.0 + 0.3:
			capsules.remove_at(k)
			_collect(c)
		elif pos.z > paddle_z + 2.0:
			(c.node as Node).queue_free()
			capsules.remove_at(k)

func _collect(c: Dictionary) -> void:
	var type: String = c.type
	var info: Dictionary = PU[type]
	var good: bool = info.good
	(c.node as Node).queue_free()
	var pos: Vector3 = c.pos
	fx.sparks(pos + Vector3(0, 0.3, 0), 20, true)
	fx.light_flash(pos, Color(0.4, 1.0, 0.6) if good else Color(1.0, 0.3, 0.2), 2.5)
	Audio.play_sfx("pu_good" if good else "pu_bad")
	Settings.vibrate(25)
	match type:
		"multi":
			var src: Dictionary = {}
			for b in balls:
				if not b.stuck:
					src = b
					break
			if src.is_empty() and not balls.is_empty():
				src = balls[0]
			if not src.is_empty():
				for i in 2:
					var a := randf_range(-0.9, 0.9)
					var nb := _new_ball(src.pos, Vector3(sin(a), 0, -cos(a)) * _ball_speed(), false)
					nb.stuck = false
		"life":
			lives += 1
		"stun":
			fx_t.stun = 1.5
		_:
			fx_t[type] = float(info.dur)
			if type == "wide":
				fx_t.narrow = 0.0
			elif type == "narrow":
				fx_t.wide = 0.0
	_toast("%s\n%s" % [info.name, info.desc], good)

func _apply_pad_width(instant: bool) -> void:
	var target := 2.0
	if fx_t.wide > 0.0:
		target = 3.0
	elif fx_t.narrow > 0.0:
		target = 1.2
	pw = target if instant else lerpf(pw, target, 0.2)
	pad_vis.scale = Vector3(pw, 1.0, 1.0)

func _update_lasers(delta: float) -> void:
	if fx_t.laser <= 0.0:
		return
	laser_t -= delta
	if laser_t > 0.0:
		return
	laser_t = 0.5
	for off in [-0.6, 0.6]:
		var x: float = paddle_x + off * pw / 2.0
		var best: Dictionary = {}
		var best_z := -999.0
		for b in bricks:
			if b.alive and absf(b.pos.x - x) < 0.5 and b.pos.z < paddle_z and b.pos.z > best_z:
				best_z = b.pos.z
				best = b
		var from := Vector3(x, 0.4, paddle_z - 0.2)
		var to := Vector3(x, 0.4, best_z if not best.is_empty() else z_top)
		_arc(from, to, 0.18)
		if not best.is_empty():
			_damage_brick(best, false)
	Audio.play_sfx("laser", -4.0, randf_range(0.95, 1.1))

# ------------------------------------------------- ładunek elektrostatyczny kulki
func _update_charge(b: Dictionary, delta: float) -> void:
	var mat: ShaderMaterial = b.mat
	if not Settings.effects:
		mat.set_shader_parameter("charge", 0.2)
		return
	b.charge += delta * (0.4 + (b.vel as Vector3).length() * 0.05)
	var c := clampf(b.charge / b.goal, 0.0, 1.0)
	mat.set_shader_parameter("charge", 0.35 + 0.65 * c)
	(b.light as OmniLight3D).light_energy = (0.45 + c * 0.7) * randf_range(0.75, 1.35)
	if b.charge >= b.goal:
		var best: Dictionary = {}
		var bd := 3.2
		for br in bricks:
			if br.alive:
				var d := Vector2(br.pos.x - b.pos.x, br.pos.z - b.pos.z).length()
				if d < bd and d > 0.7:
					bd = d
					best = br
		if not best.is_empty():
			b.charge = 0.0
			b.goal = randf_range(0.6, 1.2)
			var tp: Vector3 = best.pos
			_arc(b.pos + Vector3(0, 0.25, 0), tp + Vector3(0, 0.4, 0), 0.4)
			fx.sparks(tp + Vector3(0, 0.4, 0), 10)
			fx.light_flash(tp, Color(0.6, 0.9, 1.0), 2.5)
			Audio.play_sfx("discharge", -4.0, randf_range(0.9, 1.15))
			Settings.vibrate(8)
			score += 25
			mat.set_shader_parameter("flash", 1.0)
			create_tween().tween_method(func(v: float): mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.5)

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

# --------------------------------------------------------------- życie, poziomy
func _lose_ball(b: Dictionary) -> void:
	balls.erase(b)
	(b.node as Node).queue_free()
	if not balls.is_empty():
		return
	lives -= 1
	combo = 0
	Audio.play_sfx("drain")
	Settings.vibrate(60)
	for k in ["wide", "narrow", "slow", "fast", "catch", "laser", "pierce", "stun"]:
		fx_t[k] = 0.0
	for c in capsules:
		(c.node as Node).queue_free()
	capsules.clear()
	if lives <= 0:
		_game_over()
	else:
		state = "ready"
		_spawn_ball_on_paddle()
		_toast("ZOSTAŁO %d KUL" % lives, false)

func _level_done() -> void:
	state = "end"
	for b in balls:
		(b.node as Node).queue_free()
	balls.clear()
	var unlocked := Save.get_int("dionakra", "unlocked", 1)
	if level >= unlocked:
		Save.set_int("dionakra", "unlocked", mini(level + 1, MAX_LEVEL))
	var bonus := lives * 500
	score += bonus
	var high := Save.get_int("dionakra", "high", 0)
	if score > high:
		Save.set_int("dionakra", "high", score)
	Audio.play_sfx("win")
	Settings.vibrate(90)
	await get_tree().create_timer(0.9, false).timeout
	if is_inside_tree():
		_show_panel(true, bonus)

func _game_over() -> void:
	state = "over"
	var high := Save.get_int("dionakra", "high", 0)
	if score > high:
		Save.set_int("dionakra", "high", score)
	await get_tree().create_timer(0.6, false).timeout
	if is_inside_tree():
		_show_panel(false, 0)

func _show_panel(win: bool, bonus: int) -> void:
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.0, 0.1, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -280
	box.offset_bottom = 280
	box.add_theme_constant_override("separation", 22)
	result_panel.add_child(box)
	var t := UiKit.label("POZIOM UKOŃCZONY!" if win else "KONIEC GRY", 32 if win else 40, UiKit.C_GREEN if win else UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	var txt := "WYNIK %d\nREKORD %d" % [score, Save.get_int("dionakra", "high", 0)]
	if win:
		txt += "\nBONUS ZA KULE +%d" % bonus
	var s := UiKit.label(txt, 16, Color.WHITE, 6)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	if win and level < MAX_LEVEL:
		box.add_child(_panel_btn("DALEJ", UiKit.C_GREEN, func(): _start_level(level + 1)))
	box.add_child(_panel_btn("NOWA GRA" if not win else "POWTÓRZ", UiKit.C_ORANGE, func(): _restart(win)))
	box.add_child(_panel_btn("MENU", UiKit.C_CYAN, _go_menu))
	ui.add_child(result_panel)

func _restart(win: bool) -> void:
	if not win:
		score = 0
		lives = 3
	_start_level(level)

func _panel_btn(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(b, 24, col)
	b.pressed.connect(func():
		Audio.play_sfx("coin")
		cb.call())
	return b

# -------------------------------------------------------------------------- UI
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
	b_menu.custom_minimum_size = Vector2(130, 0)
	top.add_child(b_menu)
	lbl_score = UiKit.label("0", 32, UiKit.C_YELLOW, 8)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lbl_score)
	var b_lv := _btn("POZIOMY", _open_levels)
	b_lv.custom_minimum_size = Vector2(150, 0)
	top.add_child(b_lv)
	var b_opt := _btn("OPCJE", _open_options)
	b_opt.custom_minimum_size = Vector2(130, 0)
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
	lbl_toast.offset_top = HUD_TOP_PX + 20
	lbl_toast.offset_bottom = HUD_TOP_PX + 150
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.modulate.a = 0.0
	ui.add_child(lbl_toast)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 14
	bottom.offset_right = -14
	bottom.offset_top = -150
	bottom.offset_bottom = -28
	bottom.add_theme_constant_override("separation", 14)
	ui.add_child(bottom)
	bottom.add_child(_dir_btn("<", -1))
	bottom.add_child(_dir_btn(">", 1))
	lbl_hint = UiKit.label("DOTKNIJ POLE, ABY WYSTRZELIĆ KULKĘ", 16, UiKit.C_CYAN, 6)
	lbl_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl_hint.offset_top = -215
	lbl_hint.offset_bottom = -165
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(lbl_hint)

func _dir_btn(text: String, d: int) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(b, 40, UiKit.C_CYAN)
	b.button_down.connect(func():
		if overlay == null and result_panel == null:
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
	lbl_score.text = str(score)
	lbl_info.text = "POZIOM %d   KULE %d   REKORD %d" % [level, lives, Save.get_int("dionakra", "high", 0)]
	lbl_hint.visible = state == "ready"
	var parts := PackedStringArray()
	for k in fx_t:
		if fx_t[k] > 0.0 and k != "stun":
			var info: Dictionary = PU[k]
			var colr := "#7dffb0" if info.good else "#ff6a5a"
			parts.append("[color=%s]%s %d s[/color]" % [colr, info.name, ceili(fx_t[k])])
	var txt := "   ".join(parts)
	if txt != fx_text_cache:
		fx_text_cache = txt
		lbl_fx.text = txt

func _popup(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 56
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

# ---------------------------------------------------------------------- sterowanie
func _unhandled_input(e: InputEvent) -> void:
	var pos := Vector2.ZERO
	var kind := ""
	if e is InputEventScreenTouch:
		kind = "down" if e.pressed else "up"
		pos = e.position
	elif e is InputEventScreenDrag:
		kind = "move"
		pos = e.position
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not OS.has_feature("mobile"):
		kind = "down" if e.pressed else "up"
		pos = e.position
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not OS.has_feature("mobile"):
		kind = "move"
		pos = e.position
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE:
		_launch()
		return
	else:
		return
	if overlay != null or result_panel != null:
		return
	match kind:
		"down":
			touching = true
			target_x = clampf(_screen_x(pos.x), -FIELD, FIELD)
			_launch()
		"move":
			if touching:
				target_x = clampf(_screen_x(pos.x), -FIELD, FIELD)
		"up":
			touching = false

# ----------------------------------------------------------------- overlaye, menu
func _open_options() -> void:
	if overlay:
		return
	btn_dir = 0
	var panel := OptionsPanel.new()
	panel.closed.connect(_close_overlay)
	overlay = panel
	ui.add_child(panel)
	get_tree().paused = true

func _open_levels() -> void:
	if overlay:
		return
	btn_dir = 0
	var rt := Control.new()
	rt.process_mode = Node.PROCESS_MODE_ALWAYS
	rt.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.0, 0.1, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rt.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 80
	box.offset_bottom = -50
	box.add_theme_constant_override("separation", 20)
	rt.add_child(box)
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
	var unlocked := Save.get_int("dionakra", "unlocked", 1)
	for i in range(1, MAX_LEVEL + 1):
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(110, 110)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = i > unlocked
		UiKit.style_button(b, 24, UiKit.C_CYAN)
		b.pressed.connect(func():
			Audio.play_sfx("click")
			_close_overlay()
			score = 0
			lives = 3
			_start_level(i))
		gc.add_child(b)
	var close := Button.new()
	close.text = "ZAMKNIJ"
	close.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(close, 24, UiKit.C_GREEN)
	close.pressed.connect(func():
		Audio.play_sfx("back")
		_close_overlay())
	box.add_child(close)
	overlay = rt
	ui.add_child(rt)
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

func _schedule_ambient() -> void:
	get_tree().create_timer(randf_range(2.0, 4.5)).timeout.connect(_ambient)

func _ambient() -> void:
	if (state == "play" or state == "ready") and Settings.effects and overlay == null and not bricks.is_empty():
		var br: Dictionary = bricks[randi() % bricks.size()]
		if br.alive:
			var o: Dictionary = bricks[randi() % bricks.size()]
			if o.alive and o != br:
				var d := Vector2(o.pos.x - br.pos.x, o.pos.z - br.pos.z).length()
				if d < 2.5:
					_arc(br.pos + Vector3(0, 0.4, 0), o.pos + Vector3(0, 0.4, 0), 0.25)
					fx.sparks(o.pos + Vector3(0, 0.4, 0), 8)
					Audio.play_sfx("spark", -10.0, randf_range(0.9, 1.3))
	_schedule_ambient()
