extends Node3D
## SREDAVNI ECAPS - wirusy schodzą rzędami, Ty strzelasz wyładowaniami z dołu. Osłony z kondensatorów, ufo-trojan,
## boss co 5 fal, power-upy. Sterowanie: palec przesuwa działko (strzał automatyczny) albo przyciski < >.

const FIELD := 5.0
const COLS := 8
const CAM_FOV := 40.0
const HUD_TOP_PX := 230.0
const CTRL_PX := 190.0
const MIN_FIELD := 11.5
const PU := {
	"rapid": {"name": "SZYBKI OGIEŃ", "desc": "12 s", "good": true, "dur": 12.0, "col": Color(0.85, 1.0, 0.2), "shape": "scan"},
	"spread": {"name": "POTRÓJNY STRZAŁ", "desc": "12 s", "good": true, "dur": 12.0, "col": Color(0.4, 1.0, 0.4), "shape": "multi"},
	"shield": {"name": "TARCZA", "desc": "8 s", "good": true, "dur": 8.0, "col": Color(0.4, 0.7, 1.0), "shape": "insul"},
	"slow": {"name": "SPOWOLNIENIE", "desc": "wirusy wolniejsze 10 s", "good": true, "dur": 10.0, "col": Color(0.75, 0.9, 1.0), "shape": "heat"},
	"nuke": {"name": "EMP", "desc": "niszczy dolny rząd", "good": true, "dur": 0.0, "col": Color(1.0, 0.85, 0.2), "shape": "jumper"},
	"life": {"name": "ŻYCIE", "desc": "+1", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.35), "shape": "batt"},
	"jam": {"name": "ZACIĘCIE", "desc": "brak strzału 2.5 s", "good": false, "dur": 2.5, "col": Color(1.0, 0.1, 0.15), "shape": "mine"},
	"rev": {"name": "ODWROTNA POLARYZACJA", "desc": "8 s", "good": false, "dur": 8.0, "col": Color(0.85, 0.35, 1.0), "shape": "rev"},
	"haste": {"name": "PRZYSPIESZENIE WIRUSÓW", "desc": "8 s", "good": false, "dur": 8.0, "col": Color(1.0, 0.25, 0.1), "shape": "surge"},
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
var player_z := 7.0
var arcs: Array = []
var arc_idx := 0
var world: Node3D
var viruses: Array = []
var proto_virus: Array = []
var boss: Dictionary = {}
var cells: Array = []
var shots: Array = []
var ebullets: Array = []
var capsules: Array = []
var ufo: Dictionary = {}
var player: Node3D
var shield_node: MeshInstance3D
var mat_shot: StandardMaterial3D
var mat_ebullet: StandardMaterial3D
var cell_mats: Array = []

var state := "play"            # play / clear / over
var level := 1
var lives := 3
var score := 0
var player_x := 0.0
var target_x := 0.0
var btn_dir := 0
var fire_t := 0.0
var inv_t := 0.0
var form_x := 0.0
var form_z := 0.0
var form_dir := 1.0
var form_total := 1
var anim_t := 0.0
var march_acc := 0.0
var march_i := 0
var efire_t := 1.0
var ufo_t := 12.0
var boss_t := 0.0
var fx_t := {"rapid": 0.0, "spread": 0.0, "shield": 0.0, "slow": 0.0, "jam": 0.0, "rev": 0.0, "haste": 0.0}
var overlay: Control
var panel: Control

var ui: CanvasLayer
var lbl_score: Label
var lbl_info: Label
var lbl_fx: RichTextLabel
var lbl_toast: Label
var bar_boss: ColorRect
var bar_bg: ColorRect
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
	_make_materials()
	for i in 6:
		arcs.append(Discharger.new(root))
	world = Node3D.new()
	root.add_child(world)
	_build_player()
	_setup_ui()
	Audio.play_music("invaders")
	_new_game()
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
	var avail := vp.y - HUD_TOP_PX - CTRL_PX - 40.0
	if avail / ppu < MIN_FIELD:
		# niższy ekran (tablet): oddal kamerę, by pole gry miało min. wysokość
		ppu = avail / MIN_FIELD
		plane_w = vp.x / ppu
		dist = (plane_w / 2.0) / half_tan
	var half_h := vp.y / ppu / 2.0
	board_w = maxf(w, plane_w * 1.1)
	board_d = maxf(24.0, half_h * 2.0 * 1.1)
	camera.position = Vector3(0, dist, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	z_top = _sy(HUD_TOP_PX) + 1.0
	player_z = _sy(vp.y - CTRL_PX - 40.0)

func _sy(py: float) -> float:
	return (py - vp.y / 2.0) / ppu

func _screen_x(px: float) -> float:
	return (px - vp.x / 2.0) / ppu

func _build_board() -> void:
	var fh := player_z - z_top + 3.0
	kit.add_board(board_w, board_d, Vector2(FIELD + 1.3, fh / 2.0 + 0.5), 8181)
	var i := 0
	var z := z_top - 1.0
	var zb := player_z + 1.5
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
	rng.seed = 31
	var occ := {}
	kit.add_bus(-2.0, player_z + 2.0, 1, 2, rng, occ, board_d)
	kit.add_bus(2.2, player_z + 2.0, 1, 2, rng, occ, board_d)
	kit.add_decor(FIELD * 2.0 + 2.6, 2.0 * maxf(absf(z_top), absf(player_z)) + 3.0, occ, board_w, board_d)
	kit.flush(root)

func _make_materials() -> void:
	mat_shot = StandardMaterial3D.new()
	mat_shot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_shot.albedo_color = Color(1.0, 2.4, 2.8)
	mat_ebullet = StandardMaterial3D.new()
	mat_ebullet.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_ebullet.albedo_color = Color(3.0, 0.5, 0.3)
	cell_mats = [kit.mat(Color(0.1, 0.25, 0.8), 0.2, 0.4), kit.mat(Color(0.35, 0.28, 0.5), 0.2, 0.5), kit.mat(Color(0.3, 0.12, 0.12), 0.1, 0.6)]
	var cols := [Color(1.0, 0.2, 0.8), Color(0.3, 1.0, 0.3), Color(1.0, 0.6, 0.1)]
	for t in 3:
		proto_virus.append(_virus_proto(cols[t], t, 1.0))
	proto_virus.append(_virus_proto(Color(1.0, 0.15, 0.15), 3, 2.4))     # boss

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

func _virus_proto(col: Color, t: int, sc: float) -> Node3D:
	var n := Node3D.new()
	var body := kit.mat(Color(col.r * 0.3, col.g * 0.3, col.b * 0.3), 0.2, 0.4, col, 1.2)
	var eye := kit.mat(Color(1, 1, 1), 0.0, 0.3, Color(1, 1, 1), 3.0)
	for f in 2:
		var g := Node3D.new()
		g.name = "F%d" % f
		var sm := SphereMesh.new()
		sm.radius = 0.28 * sc
		sm.height = 0.56 * sc
		sm.radial_segments = 14
		sm.rings = 8
		_pm(g, sm, body, Vector3(0, 0.3 * sc, 0))
		for k in 6:
			var a := k * TAU / 6.0 + f * 0.5 + (0.0 if t != 1 else 0.2)
			var spike := _pm(g, _bm(Vector3(0.07, 0.07, 0.3) * sc), body, Vector3(cos(a) * 0.36 * sc, 0.26 * sc, sin(a) * 0.36 * sc))
			spike.rotation.y = -a
		_pm(g, _bm(Vector3(0.1, 0.06, 0.1) * sc), eye, Vector3(-0.1 * sc, 0.5 * sc, -0.12 * sc))
		_pm(g, _bm(Vector3(0.1, 0.06, 0.1) * sc), eye, Vector3(0.1 * sc, 0.5 * sc, -0.12 * sc))
		if t == 1 or t == 3:
			var tm := TorusMesh.new()
			tm.inner_radius = 0.3 * sc
			tm.outer_radius = 0.38 * sc
			tm.rings = 16
			tm.ring_segments = 6
			_pm(g, tm, body, Vector3(0, 0.32 * sc, 0))
		n.add_child(g)
	n.get_node("F1").visible = false
	return n

func _build_player() -> void:
	player = Node3D.new()
	root.add_child(player)
	var base := kit.mat(Color(0.08, 0.08, 0.1), 0.6, 0.3)
	_pm(player, _bm(Vector3(1.0, 0.3, 0.55)), base, Vector3(0, 0.15, 0.05))
	_pm(player, _bm(Vector3(1.0, 0.04, 0.2)), kit.mats.gold, Vector3(0, 0.32, 0.12))
	_pm(player, _bm(Vector3(0.18, 0.34, 0.5)), kit.mats.silver, Vector3(0, 0.3, -0.18))
	var tip := kit.mat(Color(0.3, 0.02, 0.02), 0.0, 0.3, Color(1.0, 0.15, 0.1), 1.6)
	_pm(player, _bm(Vector3(0.12, 0.2, 0.12)), tip, Vector3(0, 0.48, -0.36))
	shield_node = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.85
	sm.height = 1.7
	shield_node.mesh = sm
	var shm := kit.mat(Color(0.3, 0.7, 1.0, 0.25), 0.0, 0.3, Color(0.3, 0.7, 1.0), 1.4)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_node.material_override = shm
	shield_node.position.y = 0.3
	shield_node.visible = false
	player.add_child(shield_node)

# ------------------------------------------------------------------- start gry / fali
func _new_game() -> void:
	score = 0
	lives = 3
	level = 1
	for k in fx_t:
		fx_t[k] = 0.0
	if panel:
		panel.queue_free()
		panel = null
	_start_wave()

func _clear_world() -> void:
	for c in world.get_children():
		c.queue_free()
	viruses.clear()
	cells.clear()
	shots.clear()
	ebullets.clear()
	capsules.clear()
	boss = {}
	ufo = {}

func _start_wave() -> void:
	_clear_world()
	state = "play"
	player_x = 0.0
	target_x = 0.0
	inv_t = 1.2
	form_dir = 1.0
	efire_t = 1.5
	ufo_t = randf_range(10.0, 18.0)
	_build_bunkers()
	if level % 5 == 0:
		_spawn_boss()
		_toast("BOSS!\nWIRUS-MATKA", false)
	else:
		var rows := mini(3 + level / 3, 6)
		form_x = 0.0
		form_z = z_top + 1.3
		for gy in rows:
			for gx in COLS:
				var t := 0 if gy >= rows - 1 else (1 if gy >= rows - 3 else 2)
				if rows <= 3:
					t = [2, 1, 0][gy]
				var node := (proto_virus[t] as Node3D).duplicate() as Node3D
				world.add_child(node)
				viruses.append({"gx": gx, "gy": gy, "type": t, "node": node, "alive": true})
		form_total = viruses.size()
		_toast("FALA %d" % level, true)
	Audio.play_sfx("alarm", -4.0)

func _build_bunkers() -> void:
	var bz := player_z - 2.6
	for bx in [-3.6, -1.2, 1.2, 3.6]:
		for cx in 6:
			for cz in 3:
				if cz == 2 and (cx == 2 or cx == 3):
					continue          # wnęka od dołu
				var mi := MeshInstance3D.new()
				mi.mesh = _bm(Vector3(0.28, 0.3, 0.26))
				mi.material_override = cell_mats[0]
				var pos := Vector3(bx - 0.7 + cx * 0.28, 0.15, bz + cz * 0.26)
				mi.position = pos
				world.add_child(mi)
				cells.append({"node": mi, "pos": pos, "hp": 3})

func _spawn_boss() -> void:
	var node := (proto_virus[3] as Node3D).duplicate() as Node3D
	world.add_child(node)
	var hp := 24 + level * 3
	boss = {"node": node, "x": 0.0, "z": z_top + 2.2, "hp": hp, "max": hp, "t": 0.0}
	node.position = Vector3(0, 0, boss.z)

# ------------------------------------------------------------------------ pętla gry
func _process(delta: float) -> void:
	lbl_score.text = str(score)
	lbl_info.text = "FALA %d   ŻYCIA %d   REKORD %d" % [level, lives, Save.get_int("sredavni", "high", 0)]
	var parts := PackedStringArray()
	for k in fx_t:
		if fx_t[k] > 0.0 and k != "jam":
			var info: Dictionary = PU[k]
			parts.append("[color=%s]%s %d s[/color]" % ["#7dffb0" if info.good else "#ff6a5a", info.name, ceili(fx_t[k])])
	var txt := "   ".join(parts)
	if txt != fx_text_cache:
		fx_text_cache = txt
		lbl_fx.text = txt
	bar_bg.visible = not boss.is_empty()
	if not boss.is_empty():
		bar_boss.size.x = (bar_bg.size.x - 6.0) * clampf(float(boss.hp) / float(boss.max), 0.0, 1.0)
	for a in arcs:
		(a as Discharger).update(delta)

func _physics_process(delta: float) -> void:
	for k in fx_t:
		if fx_t[k] > 0.0 and state != "over":
			fx_t[k] = maxf(0.0, fx_t[k] - delta)
	inv_t = maxf(0.0, inv_t - delta)
	# sterowanie
	var kx := float(btn_dir)
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		kx -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		kx += 1.0
	if kx != 0.0:
		target_x = clampf(target_x + kx * 14.0 * delta, -FIELD, FIELD)
	if state != "over":
		var tx := -target_x if fx_t.rev > 0.0 else target_x
		var lim := FIELD - 0.55
		player_x = clampf(lerpf(player_x, clampf(tx, -lim, lim), 1.0 - exp(-delta * 26.0)), -lim, lim)
	player.position = Vector3(player_x, 0, player_z)
	player.visible = inv_t <= 0.0 or int(Time.get_ticks_msec() / 90.0) % 2 == 0
	shield_node.visible = fx_t.shield > 0.0
	if state != "play":
		return
	_update_fire(delta)
	_update_viruses(delta)
	_update_boss(delta)
	_update_enemy_fire(delta)
	_update_bullets(delta)
	_update_ufo(delta)
	_update_capsules(delta)
	# koniec fali
	if viruses.filter(func(v): return v.alive).is_empty() and boss.is_empty():
		_wave_clear()

func _update_fire(delta: float) -> void:
	fire_t -= delta
	if fire_t > 0.0 or fx_t.jam > 0.0:
		return
	fire_t = 0.17 if fx_t.rapid > 0.0 else 0.32
	var angles: Array = [0.0]
	if fx_t.spread > 0.0:
		angles = [-0.16, 0.0, 0.16]
	for a in angles:
		var mi := MeshInstance3D.new()
		mi.mesh = _bm(Vector3(0.09, 0.09, 0.5))
		mi.material_override = mat_shot
		world.add_child(mi)
		var vel := Vector3(sin(a), 0, -cos(a)) * 15.0
		var pos := Vector3(player_x, 0.35, player_z - 0.5)
		mi.position = pos
		mi.rotation.y = -a
		shots.append({"node": mi, "pos": pos, "vel": vel})
	Audio.play_sfx("laser", -8.0, randf_range(0.95, 1.1))

func _virus_pos(v: Dictionary) -> Vector3:
	return Vector3(form_x + (v.gx - (COLS - 1) / 2.0) * 1.05, 0.0, form_z + v.gy * 0.8)

func _update_viruses(delta: float) -> void:
	if viruses.is_empty():
		return
	var alive := 0
	var min_x := 99.0
	var max_x := -99.0
	var max_z := -99.0
	for v in viruses:
		if v.alive:
			alive += 1
			var p := _virus_pos(v)
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			max_z = maxf(max_z, p.z)
	if alive == 0:
		return
	var spd := (0.62 + 0.07 * level) * (1.0 + 2.2 * (1.0 - float(alive) / float(form_total)))
	if fx_t.slow > 0.0:
		spd *= 0.5
	if fx_t.haste > 0.0:
		spd *= 1.6
	form_x += form_dir * spd * delta
	march_acc += spd * delta
	if march_acc > 0.5:
		march_acc = 0.0
		march_i = (march_i + 1) % 4
		Audio.play_sfx("tick", -10.0, [1.0, 0.9, 0.8, 0.7][march_i])
	if (form_dir > 0.0 and max_x > FIELD - 0.6) or (form_dir < 0.0 and min_x < -FIELD + 0.6):
		form_dir = -form_dir
		form_z += 0.38
	anim_t += delta
	var frame := int(anim_t / 0.45) % 2
	for v in viruses:
		if not v.alive:
			continue
		var node: Node3D = v.node
		node.position = _virus_pos(v)
		(node.get_node("F0") as Node3D).visible = frame == 0
		(node.get_node("F1") as Node3D).visible = frame == 1
		# wirusy niszczą osłony, po których przechodzą
		for c in cells:
			if (c.pos as Vector3).distance_to(node.position) < 0.55:
				_hit_cell(c, 9)
		if node.position.z >= player_z - 0.9:
			_game_over()
			return

func _update_boss(delta: float) -> void:
	if boss.is_empty():
		return
	boss.t += delta
	var sp := 1.0 + (1.0 - float(boss.hp) / float(boss.max)) * 0.9
	boss.x = sin(boss.t * 0.9 * sp) * (FIELD - 1.6)
	boss.z = z_top + 2.2 + sin(boss.t * 0.5) * 0.4
	(boss.node as Node3D).position = Vector3(boss.x, 0, boss.z)
	var f := int(boss.t / 0.4) % 2
	(boss.node.get_node("F0") as Node3D).visible = f == 0
	(boss.node.get_node("F1") as Node3D).visible = f == 1
	boss_t -= delta
	if boss_t <= 0.0:
		boss_t = maxf(0.6, 1.4 - level * 0.03)
		for a in [-0.3, 0.0, 0.3]:
			_enemy_bullet(Vector3(boss.x, 0.35, boss.z + 0.6), Vector3(sin(a), 0, cos(a)) * 5.5)

func _enemy_bullet(pos: Vector3, vel: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bm(Vector3(0.14, 0.14, 0.34))
	mi.material_override = mat_ebullet
	mi.position = pos
	world.add_child(mi)
	ebullets.append({"node": mi, "pos": pos, "vel": vel})

func _update_enemy_fire(delta: float) -> void:
	if viruses.is_empty():
		return
	efire_t -= delta
	if efire_t > 0.0:
		return
	efire_t = maxf(0.35, 1.2 - level * 0.05) * randf_range(0.6, 1.2)
	var col := randi() % COLS
	var low: Dictionary = {}
	for v in viruses:
		if v.alive and v.gx == col and (low.is_empty() or v.gy > low.gy):
			low = v
	if low.is_empty():
		return
	var p := _virus_pos(low)
	_enemy_bullet(Vector3(p.x, 0.35, p.z + 0.4), Vector3(0, 0, 5.0 + level * 0.2))

func _hit_cell(c: Dictionary, dmg: int) -> void:
	c.hp -= dmg
	var node: MeshInstance3D = c.node
	if c.hp <= 0:
		fx.sparks(c.pos + Vector3(0, 0.2, 0), 4)
		node.queue_free()
		cells.erase(c)
	else:
		node.material_override = cell_mats[clampi(3 - c.hp, 0, 2)]

func _update_bullets(delta: float) -> void:
	# strzały gracza
	for k in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[k]
		s.pos += s.vel * delta
		(s.node as Node3D).position = s.pos
		var dead: bool = s.pos.z < z_top - 0.2
		if not dead:
			for c in cells:
				if absf(c.pos.x - s.pos.x) < 0.2 and absf(c.pos.z - s.pos.z) < 0.2:
					_hit_cell(c, 1)
					dead = true
					break
		if not dead:
			for v in viruses:
				if v.alive and (_virus_pos(v) as Vector3).distance_to(s.pos) < 0.5:
					_kill_virus(v)
					dead = true
					break
		if not dead and not boss.is_empty() and Vector2(boss.x - s.pos.x, boss.z - s.pos.z).length() < 1.0:
			_hit_boss()
			dead = true
		if not dead and not ufo.is_empty() and Vector2(ufo.x - s.pos.x, ufo.z - s.pos.z).length() < 0.6:
			_kill_ufo()
			dead = true
		if dead:
			(s.node as Node).queue_free()
			shots.remove_at(k)
	# pociski wrogów
	for k in range(ebullets.size() - 1, -1, -1):
		var b: Dictionary = ebullets[k]
		b.pos += b.vel * delta
		(b.node as Node3D).position = b.pos
		var dead: bool = b.pos.z > player_z + 1.5 or absf(b.pos.x) > FIELD + 0.5
		if not dead:
			for c in cells:
				if absf(c.pos.x - b.pos.x) < 0.22 and absf(c.pos.z - b.pos.z) < 0.22:
					_hit_cell(c, 1)
					dead = true
					break
		if not dead and absf(b.pos.x - player_x) < 0.6 and absf(b.pos.z - player_z) < 0.4:
			if _player_hit():
				break            # lista pocisków została wyczyszczona
			dead = true
		if dead:
			(b.node as Node).queue_free()
			ebullets.remove_at(k)

func _kill_virus(v: Dictionary) -> void:
	v.alive = false
	var node: Node3D = v.node
	var pos := node.position
	node.queue_free()
	score += [30, 20, 10][v.type] * (1 + level / 5)
	Audio.play_sfx("brick", -2.0, randf_range(0.9, 1.2))
	Settings.vibrate(8)
	fx.sparks(pos + Vector3(0, 0.4, 0), 12)
	if randf() < 0.09:
		_spawn_capsule(pos)

func _hit_boss() -> void:
	boss.hp -= 1
	fx.sparks(Vector3(boss.x, 0.5, boss.z + 0.5), 4)
	Audio.play_sfx("clang", -4.0, randf_range(0.9, 1.1))
	if boss.hp <= 0:
		var p := Vector3(boss.x, 0.4, boss.z)
		fx.sparks(p, 50, true)
		fx.light_flash(p, Color(1.0, 0.5, 0.2), 4.0)
		(boss.node as Node).queue_free()
		boss = {}
		score += 500 + level * 50
		Audio.play_sfx("boom")
		Settings.vibrate(80)
		_spawn_capsule(p)

## Zwraca true, jeśli gracz stracił życie (wtedy wszystkie pociski wroga znikają).
func _player_hit() -> bool:
	if inv_t > 0.0:
		return false
	if fx_t.shield > 0.0:
		fx.sparks(Vector3(player_x, 0.4, player_z), 10)
		Audio.play_sfx("tink")
		return false
	lives -= 1
	inv_t = 2.0
	Audio.play_sfx("shock")
	Settings.vibrate(60)
	fx.sparks(Vector3(player_x, 0.4, player_z), 30, true)
	fx.light_flash(Vector3(player_x, 0, player_z), Color(1.0, 0.3, 0.2), 3.0)
	for eb in ebullets:
		(eb.node as Node).queue_free()
	ebullets.clear()
	if lives <= 0:
		_game_over()
	return true

func _wave_clear() -> void:
	state = "clear"
	score += 200 + lives * 100
	Audio.play_sfx("win")
	Settings.vibrate(60)
	_toast("FALA %d ZNISZCZONA!" % level, true)
	await get_tree().create_timer(1.6, false).timeout
	if is_inside_tree() and state == "clear":
		level += 1
		_start_wave()

func _game_over() -> void:
	if state == "over":
		return
	state = "over"
	var high := Save.get_int("sredavni", "high", 0)
	var best_w := Save.get_int("sredavni", "best_wave", 0)
	if score > high:
		Save.set_int("sredavni", "high", score)
	if level > best_w:
		Save.set_int("sredavni", "best_wave", level)
	Audio.play_sfx("drain")
	Settings.vibrate(80)
	await get_tree().create_timer(0.8, false).timeout
	if not is_inside_tree():
		return
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
	var t := UiKit.label("SYSTEM ZAINFEKOWANY", 32, UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	var s := UiKit.label("WYNIK %d\nFALA %d\nREKORD %d" % [score, level, Save.get_int("sredavni", "high", 0)], 16, UiKit.C_YELLOW, 6)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
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

# --------------------------------------------------------------------- ufo, power-upy
func _update_ufo(delta: float) -> void:
	if not boss.is_empty():
		return
	if ufo.is_empty():
		ufo_t -= delta
		if ufo_t <= 0.0:
			_spawn_ufo()
		return
	ufo.x += ufo.dir * 3.0 * delta
	(ufo.node as Node3D).position = Vector3(ufo.x, 0, ufo.z)
	ufo.sfx_t -= delta
	if ufo.sfx_t <= 0.0:
		ufo.sfx_t = 0.5
		Audio.play_sfx("ufo", -8.0)
	if absf(ufo.x) > FIELD + 1.0:
		(ufo.node as Node).queue_free()
		ufo = {}
		ufo_t = randf_range(14.0, 24.0)

func _spawn_ufo() -> void:
	var node := Node3D.new()
	var body := kit.mat(Color(0.2, 0.2, 0.25), 0.5, 0.3)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 0.14
	cm.radial_segments = 16
	_pm(node, cm, body, Vector3(0, 0.12, 0))
	var dm := SphereMesh.new()
	dm.radius = 0.26
	dm.height = 0.4
	_pm(node, dm, kit.mat(Color(0.3, 0.05, 0.05), 0.0, 0.3, Color(1.0, 0.2, 0.15), 2.0), Vector3(0, 0.26, 0))
	world.add_child(node)
	var dir := 1.0 if randf() < 0.5 else -1.0
	ufo = {"node": node, "x": -dir * (FIELD + 0.9), "z": z_top + 0.7, "dir": dir, "sfx_t": 0.0}

func _kill_ufo() -> void:
	var p := Vector3(ufo.x, 0.4, ufo.z)
	(ufo.node as Node).queue_free()
	ufo = {}
	ufo_t = randf_range(14.0, 24.0)
	var pts: int = [100, 150, 300][randi() % 3]
	score += pts
	fx.sparks(p, 30, true)
	fx.light_flash(p, Color(1.0, 0.8, 0.3), 3.0)
	Audio.play_sfx("boom")
	Settings.vibrate(30)
	_toast("TROJAN! +%d" % pts, true)
	_spawn_capsule(p)

func _spawn_capsule(pos: Vector3) -> void:
	var types: Array = PU.keys()
	var pt: String = types[randi() % types.size()]
	if not PU[pt].good and randf() < 0.5:
		pt = ["rapid", "spread", "shield", "slow", "nuke", "life"][randi() % 6]
	var info: Dictionary = PU[pt]
	var node := PickupKit.build(kit, info.shape, Vector3.ZERO, info.col, info.good)
	node.position = Vector3(pos.x, 0, pos.z)
	world.add_child(node)
	capsules.append({"type": pt, "node": node, "pos": Vector3(pos.x, 0, pos.z)})

func _update_capsules(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for k in range(capsules.size() - 1, -1, -1):
		var c: Dictionary = capsules[k]
		var pos: Vector3 = c.pos
		pos.z += 3.0 * delta
		c.pos = pos
		(c.node as Node3D).position = pos
		var body: Node3D = (c.node as Node3D).get_node("Body")
		body.rotation.y += delta * 3.0
		body.position.y = 0.38 + sin(t * 4.0 + k) * 0.04
		if absf(pos.z - player_z) < 0.55 and absf(pos.x - player_x) < 0.8:
			capsules.remove_at(k)
			_collect(c)
		elif pos.z > player_z + 2.0:
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
		"life":
			lives += 1
		"nuke":
			var bottom := -1
			for v in viruses:
				if v.alive:
					bottom = maxi(bottom, v.gy)
			for v in viruses:
				if v.alive and v.gy == bottom:
					_arc(Vector3(player_x, 0.4, player_z), (v.node as Node3D).position + Vector3(0, 0.4, 0), 0.4)
					_kill_virus(v)
			if not boss.is_empty():
				for i in 6:
					_hit_boss()
			Audio.play_sfx("blast")
		_:
			fx_t[type] = float(info.dur)
	_toast("%s\n%s" % [info.name, info.desc], good)

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
	bar_bg = ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.position = Vector2(24, 172)
	bar_bg.size = Vector2(672, 22)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.visible = false
	ui.add_child(bar_bg)
	bar_boss = ColorRect.new()
	bar_boss.color = UiKit.C_MAGENTA
	bar_boss.position = Vector2(3, 3)
	bar_boss.size = Vector2(0, 16)
	bar_boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar_boss)
	lbl_toast = UiKit.label("", 24, Color.WHITE, 10)
	lbl_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_toast.offset_top = HUD_TOP_PX + 90
	lbl_toast.offset_bottom = HUD_TOP_PX + 220
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
	else:
		return
	if overlay != null or panel != null:
		return
	if kind == "down" or kind == "move":
		target_x = clampf(_screen_x(pos.x), -FIELD, FIELD)

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

func _schedule_ambient() -> void:
	get_tree().create_timer(randf_range(2.0, 4.5)).timeout.connect(_ambient)

func _ambient() -> void:
	if state == "play" and Settings.effects and overlay == null and viruses.size() > 1:
		var a: Dictionary = viruses[randi() % viruses.size()]
		var b: Dictionary = viruses[randi() % viruses.size()]
		if a.alive and b.alive and a != b:
			var pa: Vector3 = (a.node as Node3D).position
			var pb: Vector3 = (b.node as Node3D).position
			if pa.distance_to(pb) < 2.2:
				_arc(pa + Vector3(0, 0.4, 0), pb + Vector3(0, 0.4, 0), 0.25)
				fx.sparks(pb + Vector3(0, 0.4, 0), 6)
				Audio.play_sfx("spark", -10.0, randf_range(0.9, 1.3))
	_schedule_ambient()
