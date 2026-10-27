extends Node3D
## DNAMMOC ELISSIM - obrona rdzenia. Wirusy-pociski spadają na układy scalone (6 miast) i 3 wyrzutnie. Stukasz w ekran:
## najbliższa wyrzutnia z amunicją strzela przechwytywaczem, który detonuje w tym miejscu - wybuch EMP niszczy
## wirusy w zasięgu. Fale rosną, pociski się dzielą, nadlatują bombowce. Power-upy łapiesz wybuchem.

const FIELD := 5.0
const CAM_FOV := 40.0
const HUD_TOP_PX := 230.0
const BOTTOM_PX := 110.0
const CITY_X := [-3.4, -2.3, -1.2, 1.2, 2.3, 3.4]
const LAUNCHER_X := [-4.5, 0.0, 4.5]
const AMMO_PER := 12
const PU := {
	"wide": {"name": "WIĘKSZE WYBUCHY", "desc": "15 s", "good": true, "dur": 15.0, "col": Color(0.75, 0.9, 1.0), "shape": "big"},
	"fast": {"name": "SZYBKIE PRZECHWYTYWACZE", "desc": "15 s", "good": true, "dur": 15.0, "col": Color(0.85, 1.0, 0.2), "shape": "scan"},
	"multi": {"name": "SALWA", "desc": "3 pociski naraz, 15 s", "good": true, "dur": 15.0, "col": Color(0.4, 1.0, 0.4), "shape": "multi"},
	"shield": {"name": "TARCZA", "desc": "osłona jednego układu", "good": true, "dur": 0.0, "col": Color(0.4, 0.7, 1.0), "shape": "insul"},
	"repair": {"name": "NAPRAWA", "desc": "odbudowa układu", "good": true, "dur": 0.0, "col": Color(0.3, 1.0, 0.35), "shape": "batt"},
	"ammo": {"name": "AMUNICJA", "desc": "+6 na wyrzutnię", "good": true, "dur": 0.0, "col": Color(1.0, 0.85, 0.2), "shape": "jumper"},
	"jam": {"name": "ZAKŁÓCENIA", "desc": "strzały rozrzucone 10 s", "good": false, "dur": 10.0, "col": Color(1.0, 0.6, 0.1), "shape": "emi"},
	"drain": {"name": "ROZŁADOWANIE", "desc": "-5 amunicji", "good": false, "dur": 0.0, "col": Color(1.0, 0.1, 0.15), "shape": "mine"},
	"haste": {"name": "SZYBKIE WIRUSY", "desc": "10 s", "good": false, "dur": 10.0, "col": Color(1.0, 0.25, 0.1), "shape": "surge"},
}

var root: Node3D
var kit: PcbKit
var fx: Fx
var camera: Camera3D
var board_w := 12.2
var board_d := 24.0
var ppu := 65.0
var vp := Vector2(720, 1600)
var z_top := -9.0
var ground_z := 8.0
var field_h := 17.0
var arcs: Array = []
var arc_idx := 0
var world: Node3D
var mat_trail: StandardMaterial3D
var mat_head: StandardMaterial3D
var mat_bolt: StandardMaterial3D
var mat_burst: StandardMaterial3D
var proto_city: Node3D
var proto_launcher: Node3D
var proto_rubble: Node3D

var cities: Array = []
var launchers: Array = []
var missiles: Array = []
var bolts: Array = []
var bursts: Array = []
var capsules: Array = []
var spawn_list: Array = []
var bomber: Dictionary = {}

var state := "play"
var wave := 1
var score := 0
var wave_t := 0.0
var wave_total := 0
var shot_cd := 0.0
var bomber_t := 0.0
var caps_t := 10.0
var next_repair := 10000
var fx_t := {"wide": 0.0, "fast": 0.0, "multi": 0.0, "jam": 0.0, "haste": 0.0}
var overlay: Control
var panel: Control

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
	_setup_camera_and_layout()
	_build_board()
	_make_materials()
	for i in 10:
		arcs.append(Discharger.new(root))
	world = Node3D.new()
	root.add_child(world)
	_setup_ui()
	Audio.play_music("defense")
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
	env.glow_intensity = 0.8
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
	var avail := vp.y - HUD_TOP_PX - BOTTOM_PX
	if avail / ppu < 11.0:
		ppu = avail / 11.0                      # niższy ekran: oddal kamerę
		plane_w = vp.x / ppu
		dist = (plane_w / 2.0) / half_tan
	var half_h := vp.y / ppu / 2.0
	board_w = maxf(w, plane_w * 1.1)
	board_d = maxf(24.0, half_h * 2.0 * 1.1)
	camera.position = Vector3(0, dist, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	z_top = _sy(HUD_TOP_PX) + 1.0
	ground_z = _sy(vp.y - BOTTOM_PX) - 0.4
	field_h = ground_z - z_top

func _sy(py: float) -> float:
	return (py - vp.y / 2.0) / ppu

func _screen_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - vp.x / 2.0) / ppu, 0.0, (p.y - vp.y / 2.0) / ppu)

func _build_board() -> void:
	kit.add_board(board_w, board_d, Vector2(FIELD + 1.3, (ground_z - z_top) / 2.0 + 1.2), 6363)
	var i := 0
	var z := z_top - 1.0
	var zb := ground_z + 1.2
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
		# podłoże pod budynkami: rząd elementów jako "grunt"
		kit.begin_part(Vector3(gx + 0.0, 0, ground_z + 0.9), 0.0)
		kit.part(int(kit._hash2(gx * 3.0 + 5.0, 9.0) * 12.0) % 12, i)
		i += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var occ := {}
	kit.add_decor(FIELD * 2.0 + 2.6, 2.0 * maxf(absf(z_top), absf(ground_z)) + 3.0, occ, board_w, board_d)
	kit.flush(root)

func _make_materials() -> void:
	mat_trail = StandardMaterial3D.new()
	mat_trail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_trail.albedo_color = Color(2.6, 0.5, 0.35)
	mat_head = StandardMaterial3D.new()
	mat_head.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_head.albedo_color = Color(3.0, 1.2, 0.8)
	mat_bolt = StandardMaterial3D.new()
	mat_bolt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_bolt.albedo_color = Color(1.0, 2.4, 2.8)
	mat_burst = StandardMaterial3D.new()
	mat_burst.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_burst.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_burst.albedo_color = Color(0.5, 1.6, 2.4, 0.38)
	# modele: układ scalony (miasto), wyrzutnia (cewka z anteną), gruz
	proto_city = Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mats.chip, Vector3(0.9, 0.42, 0.62), Vector3(0, 0.21, 0))
	kit.box(kit.mats.chip_mark, Vector3(0.08, 0.02, 0.08), Vector3(-0.34, 0.43, -0.2))
	for i in 4:
		kit.box(kit.mats.silver, Vector3(0.08, 0.05, 0.1), Vector3(-0.33 + i * 0.22, 0.08, 0.34))
		kit.box(kit.mats.silver, Vector3(0.08, 0.05, 0.1), Vector3(-0.33 + i * 0.22, 0.08, -0.34))
	kit.box(kit.mat(Color(0.3, 0.7, 1.0), 0.0, 0.3, Color(0.3, 0.8, 1.0), 2.0), Vector3(0.5, 0.04, 0.1), Vector3(0.05, 0.43, 0.14))
	kit.flush(proto_city)
	proto_launcher = Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mats.black, Vector3(0.9, 0.2, 0.7), Vector3(0, 0.1, 0))
	kit.torus(kit.mats.copper, 0.1, 0.3, Vector3(0, 0.32, 0))
	kit.cyl(kit.mats.silver, 0.04, 0.5, Vector3(0, 0.6, 0), 8)
	kit.cyl(kit.mats.led[0], 0.08, 0.1, Vector3(0, 0.88, 0), 8)
	kit.flush(proto_launcher)
	proto_rubble = Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	kit.box(kit.mats.black, Vector3(0.9, 0.08, 0.6), Vector3(0, 0.04, 0))
	kit.box(kit.mats.chip, Vector3(0.3, 0.14, 0.2), Vector3(-0.2, 0.1, 0.05))
	kit.box(kit.mats.silver, Vector3(0.2, 0.06, 0.1), Vector3(0.22, 0.08, -0.1))
	kit.flush(proto_rubble)

# ------------------------------------------------------------------- gra
func _new_game() -> void:
	score = 0
	wave = 1
	next_repair = 10000
	if panel:
		panel.queue_free()
		panel = null
	for c in world.get_children():
		c.queue_free()
	cities.clear()
	launchers.clear()
	for x in CITY_X:
		var node := (proto_city.duplicate() as Node3D)
		node.position = Vector3(x, 0, ground_z)
		world.add_child(node)
		cities.append({"x": x, "node": node, "alive": true, "shield": null, "shield_hp": 0})
	for x in LAUNCHER_X:
		var node := (proto_launcher.duplicate() as Node3D)
		node.position = Vector3(x, 0, ground_z)
		world.add_child(node)
		var lbl := Label3D.new()
		lbl.font_size = 40
		lbl.pixel_size = 0.006
		lbl.modulate = Color(0.6, 1.0, 1.0)
		lbl.outline_size = 8
		lbl.rotation_degrees = Vector3(-90, 0, 0)
		lbl.position = Vector3(x, 0.6, ground_z + 0.65)
		world.add_child(lbl)
		launchers.append({"x": x, "node": node, "alive": true, "ammo": AMMO_PER, "label": lbl})
	for k in fx_t:
		fx_t[k] = 0.0
	_start_wave()

func _clear_dynamic() -> void:
	for m in missiles:
		_free_missile(m)
	missiles.clear()
	for b in bolts:
		(b.node as Node).queue_free()
	bolts.clear()
	for b in bursts:
		(b.node as Node).queue_free()
	bursts.clear()
	for c in capsules:
		(c.node as Node).queue_free()
	capsules.clear()
	if not bomber.is_empty():
		(bomber.node as Node).queue_free()
		bomber = {}

func _alive_targets() -> Array:
	var t: Array = []
	for c in cities:
		if c.alive:
			t.append(c)
	for l in launchers:
		if l.alive:
			t.append(l)
	return t

func _start_wave() -> void:
	_clear_dynamic()
	state = "play"
	wave_t = 0.0
	for l in launchers:
		if l.alive:
			l.ammo = AMMO_PER
	var n := 8 + wave * 3
	wave_total = n
	spawn_list.clear()
	var dur := minf(16.0 + wave * 1.5, 34.0)
	for i in n:
		spawn_list.append({"t": randf_range(0.5, dur), "split": wave >= 3 and randf() < 0.25 + 0.02 * wave})
	spawn_list.sort_custom(func(a, b): return a.t < b.t)
	bomber_t = randf_range(6.0, 12.0) if wave >= 2 and wave % 2 == 0 else 1e9
	caps_t = randf_range(8.0, 16.0)
	_toast("FALA %d\n%d WIRUSÓW" % [wave, n], true)
	Audio.play_sfx("alarm", -4.0)
	_update_labels()

func _fall_time() -> float:
	var t := maxf(3.4, 9.0 - 0.5 * wave)
	if fx_t.haste > 0.0:
		t /= 1.5
	return t

func _spawn_missile(x0: float, z0: float, tx: float, split := false) -> void:
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 8
	sm.rings = 4
	head.mesh = sm
	head.material_override = mat_head
	world.add_child(head)
	var trail := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 1.0)
	trail.mesh = bm
	trail.material_override = mat_trail
	world.add_child(trail)
	var a := Vector3(x0, 0.3, z0)
	var b := Vector3(tx, 0.3, ground_z)
	missiles.append({"head": head, "trail": trail, "a": a, "b": b, "p": a, "split": split, "split_at": randf_range(0.3, 0.5), "prog": 0.0, "spd_mul": randf_range(0.85, 1.15)})

func _free_missile(m: Dictionary) -> void:
	(m.head as Node).queue_free()
	(m.trail as Node).queue_free()

func _place_line(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var dn := d / l
	var up := Vector3.UP if absf(dn.y) < 0.98 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(dn, up) * Basis.from_scale(Vector3(1, 1, l)), (a + b) / 2.0)

# ----------------------------------------------------------------------- pętla
func _physics_process(delta: float) -> void:
	for k in fx_t:
		if fx_t[k] > 0.0 and state != "over":
			fx_t[k] = maxf(0.0, fx_t[k] - delta)
	shot_cd = maxf(0.0, shot_cd - delta)
	for a in arcs:
		(a as Discharger).update(delta)
	if state != "play":
		return
	wave_t += delta
	# spawn
	while not spawn_list.is_empty() and spawn_list[0].t <= wave_t:
		var sp: Dictionary = spawn_list.pop_front()
		var targets := _alive_targets()
		if targets.is_empty():
			break
		var tg: Dictionary = targets[randi() % targets.size()]
		_spawn_missile(randf_range(-FIELD + 0.5, FIELD - 0.5), z_top + 0.3, tg.x, sp.split)
	# bombowiec
	bomber_t -= delta
	if bomber_t <= 0.0 and bomber.is_empty():
		_spawn_bomber()
	_update_bomber(delta)
	_update_missiles(delta)
	_update_bolts(delta)
	_update_bursts(delta)
	_update_capsules(delta)
	caps_t -= delta
	if caps_t <= 0.0:
		caps_t = randf_range(14.0, 22.0)
		_spawn_capsule(Vector3(randf_range(-FIELD + 1.0, FIELD - 1.0), 0, z_top + 0.6))
	# koniec fali
	if spawn_list.is_empty() and missiles.is_empty() and bomber.is_empty() and bomber_t > 1e8:
		_wave_end()
	var any_city := false
	for c in cities:
		if c.alive:
			any_city = true
	if not any_city:
		_game_over()

func _update_missiles(delta: float) -> void:
	var v := field_h / _fall_time()
	for k in range(missiles.size() - 1, -1, -1):
		var m: Dictionary = missiles[k]
		var len_total: float = (m.b - m.a).length()
		m.prog += (v * m.spd_mul * delta) / len_total
		var p: Vector3 = (m.a as Vector3).lerp(m.b, clampf(m.prog, 0.0, 1.0))
		m.p = p
		(m.head as Node3D).position = p
		_place_line(m.trail, m.a, p)
		if m.split and m.prog > m.split_at:
			m.split = false
			var targets := _alive_targets()
			for i in 2:
				if not targets.is_empty():
					var tg: Dictionary = targets[randi() % targets.size()]
					_spawn_missile(p.x, p.z, tg.x)
			fx.sparks(p, 8)
		if m.prog >= 1.0:
			_impact(m)
			_free_missile(m)
			missiles.remove_at(k)

func _impact(m: Dictionary) -> void:
	var p: Vector3 = m.b
	fx.sparks(p + Vector3(0, 0.3, 0), 30, true)
	fx.light_flash(p, Color(1.0, 0.5, 0.2), 3.0)
	Settings.vibrate(30)
	for c in cities:
		if c.alive and absf(c.x - p.x) < 0.6:
			if c.shield_hp > 0:
				c.shield_hp = 0
				(c.shield as Node).queue_free()
				c.shield = null
				Audio.play_sfx("tink")
				return
			_destroy(c, false)
			return
	for l in launchers:
		if l.alive and absf(l.x - p.x) < 0.6:
			_destroy(l, true)
			return

func _destroy(b: Dictionary, is_launcher: bool) -> void:
	b.alive = false
	(b.node as Node).queue_free()
	var r := proto_rubble.duplicate() as Node3D
	r.position = Vector3(b.x, 0, ground_z)
	world.add_child(r)
	b.rubble = r
	Audio.play_sfx("boom")
	Audio.play_sfx("shock", -4.0)
	Settings.vibrate(70)
	if is_launcher:
		b.ammo = 0
		_update_labels()
		_toast("WYRZUTNIA ZNISZCZONA!", false)
	else:
		_toast("UKŁAD ZNISZCZONY!", false)

func _update_labels() -> void:
	for l in launchers:
		var lbl: Label3D = l.label
		lbl.text = str(l.ammo) if l.alive else ""

func _ammo_total() -> int:
	var n := 0
	for l in launchers:
		if l.alive:
			n += l.ammo
	return n

# ---------------------------------------------------------------- strzelanie
func _fire_at(target: Vector3) -> void:
	if shot_cd > 0.0:
		return
	target.z = minf(target.z, ground_z - 1.0)
	target.z = maxf(target.z, z_top + 0.3)
	target.x = clampf(target.x, -FIELD + 0.3, FIELD - 0.3)
	var best: Dictionary = {}
	var bd := 1e9
	for l in launchers:
		if l.alive and l.ammo > 0 and absf(l.x - target.x) < bd:
			bd = absf(l.x - target.x)
			best = l
	if best.is_empty():
		Audio.play_sfx("bad", -4.0)
		_toast("BRAK AMUNICJI!", false)
		return
	shot_cd = 0.1
	var shots := 3 if fx_t.multi > 0.0 else 1
	for i in shots:
		if best.ammo <= 0:
			break
		best.ammo -= 1
		var t := target
		if shots > 1:
			t.x += (i - 1) * 0.9
		if fx_t.jam > 0.0:
			t += Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.0, 1.0))
		_launch_bolt(Vector3(best.x, 0.5, ground_z), t)
	Audio.play_sfx("laser", -2.0, randf_range(0.95, 1.1))
	_update_labels()

func _launch_bolt(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, 1.0)
	mi.mesh = bm
	mi.material_override = mat_bolt
	world.add_child(mi)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	head.mesh = sm
	head.material_override = mat_bolt
	world.add_child(head)
	bolts.append({"node": mi, "head": head, "a": from, "b": Vector3(to.x, 0.5, to.z), "prog": 0.0})

func _update_bolts(delta: float) -> void:
	var v := field_h / 0.75 * (2.0 if fx_t.fast > 0.0 else 1.0)
	for k in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[k]
		var l: float = (b.b - b.a).length()
		b.prog += v * delta / maxf(l, 0.1)
		var p: Vector3 = (b.a as Vector3).lerp(b.b, clampf(b.prog, 0.0, 1.0))
		(b.head as Node3D).position = p
		_place_line(b.node, b.a, p)
		if b.prog >= 1.0:
			_burst(b.b)
			(b.node as Node).queue_free()
			(b.head as Node).queue_free()
			bolts.remove_at(k)

func _burst(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.1
	cm.radial_segments = 28
	mi.mesh = cm
	mi.material_override = mat_burst
	mi.position = Vector3(pos.x, 0.45, pos.z)
	world.add_child(mi)
	var rmax := 1.25 * (1.6 if fx_t.wide > 0.0 else 1.0)
	bursts.append({"node": mi, "pos": pos, "t": 0.0, "rmax": rmax, "r": 0.1})
	Audio.play_sfx("blast", -6.0, randf_range(0.95, 1.15))
	fx.sparks(pos + Vector3(0, 0.3, 0), 12)
	fx.light_flash(pos, Color(0.5, 0.9, 1.0), 2.0)
	Settings.vibrate(12)

func _update_bursts(delta: float) -> void:
	for k in range(bursts.size() - 1, -1, -1):
		var b: Dictionary = bursts[k]
		b.t += delta
		# narasta 0.25 s, trzyma 0.55 s, zanika 0.25 s
		var r: float = b.rmax
		if b.t < 0.25:
			r = lerpf(0.1, b.rmax, b.t / 0.25)
		elif b.t > 0.8:
			r = lerpf(b.rmax, 0.0, (b.t - 0.8) / 0.25)
		b.r = r
		(b.node as Node3D).scale = Vector3(r, 1.0, r)
		# wirusy w zasięgu
		for i in range(missiles.size() - 1, -1, -1):
			var m: Dictionary = missiles[i]
			if Vector2(m.p.x - b.pos.x, m.p.z - b.pos.z).length() < r + 0.12:
				_kill_missile(m, i)
		if not bomber.is_empty() and Vector2(bomber.x - b.pos.x, bomber.z - b.pos.z).length() < r + 0.4:
			_kill_bomber()
		for j in range(capsules.size() - 1, -1, -1):
			var c: Dictionary = capsules[j]
			if Vector2(c.pos.x - b.pos.x, c.pos.z - b.pos.z).length() < r + 0.3:
				capsules.remove_at(j)
				_collect(c)
		if b.t >= 1.05:
			(b.node as Node).queue_free()
			bursts.remove_at(k)

func _kill_missile(m: Dictionary, idx: int) -> void:
	var p: Vector3 = m.p
	score += 25 + wave * 5
	Audio.play_sfx("brick", -3.0, randf_range(0.9, 1.25))
	fx.sparks(p + Vector3(0, 0.2, 0), 10)
	_free_missile(m)
	missiles.remove_at(idx)

# ---------------------------------------------------------------- bombowiec
func _spawn_bomber() -> void:
	var node := Node3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 0.14
	cm.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = kit.mat(Color(0.2, 0.2, 0.25), 0.5, 0.3)
	mi.position.y = 0.4
	node.add_child(mi)
	var dm := SphereMesh.new()
	dm.radius = 0.26
	dm.height = 0.4
	var dome := MeshInstance3D.new()
	dome.mesh = dm
	dome.material_override = kit.mat(Color(0.3, 0.05, 0.05), 0.0, 0.3, Color(1.0, 0.2, 0.15), 2.0)
	dome.position.y = 0.55
	node.add_child(dome)
	world.add_child(node)
	var dir := 1.0 if randf() < 0.5 else -1.0
	bomber = {"node": node, "x": -dir * (FIELD + 0.9), "z": z_top + 1.4, "dir": dir, "drop": 0.8, "sfx": 0.0}
	bomber_t = 1e9

func _update_bomber(delta: float) -> void:
	if bomber.is_empty():
		return
	bomber.x += bomber.dir * 2.6 * delta
	(bomber.node as Node3D).position = Vector3(bomber.x, 0, bomber.z)
	bomber.sfx -= delta
	if bomber.sfx <= 0.0:
		bomber.sfx = 0.5
		Audio.play_sfx("ufo", -8.0)
	bomber.drop -= delta
	if bomber.drop <= 0.0 and absf(bomber.x) < FIELD:
		bomber.drop = 1.0
		var targets := _alive_targets()
		if not targets.is_empty():
			var tg: Dictionary = targets[randi() % targets.size()]
			_spawn_missile(bomber.x, bomber.z + 0.3, tg.x)
	if absf(bomber.x) > FIELD + 1.2:
		(bomber.node as Node).queue_free()
		bomber = {}

func _kill_bomber() -> void:
	var p := Vector3(bomber.x, 0.4, bomber.z)
	(bomber.node as Node).queue_free()
	bomber = {}
	var pts: int = [100, 150, 300][randi() % 3]
	score += pts
	fx.sparks(p, 40, true)
	fx.light_flash(p, Color(1.0, 0.8, 0.3), 3.5)
	Audio.play_sfx("boom")
	_toast("BOMBOWIEC! +%d" % pts, true)
	_spawn_capsule(Vector3(p.x, 0, p.z))

# ------------------------------------------------------------------ power-upy
func _spawn_capsule(pos: Vector3) -> void:
	var types: Array = PU.keys()
	var pt: String = types[randi() % types.size()]
	if not PU[pt].good and randf() < 0.5:
		pt = ["wide", "fast", "multi", "shield", "repair", "ammo"][randi() % 6]
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
		pos.z += 1.1 * delta
		c.pos = pos
		(c.node as Node3D).position = pos
		var body: Node3D = (c.node as Node3D).get_node("Body")
		body.rotation.y += delta * 3.0
		body.position.y = 0.38 + sin(t * 4.0 + k) * 0.04
		if pos.z > ground_z - 0.3:
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
		"ammo":
			for l in launchers:
				if l.alive:
					l.ammo += 6
			_update_labels()
		"drain":
			for l in launchers:
				if l.alive:
					l.ammo = maxi(0, l.ammo - 5)
			_update_labels()
		"repair":
			_repair_city()
		"shield":
			var alive: Array = []
			for ct in cities:
				if ct.alive and ct.shield_hp == 0:
					alive.append(ct)
			if not alive.is_empty():
				var ct: Dictionary = alive[randi() % alive.size()]
				_give_shield(ct)
		_:
			fx_t[type] = float(info.dur)
	_toast("%s\n%s" % [info.name, info.desc], good)

func _give_shield(ct: Dictionary) -> void:
	var sh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.75
	sm.height = 1.5
	sh.mesh = sm
	var m := kit.mat(Color(0.3, 0.7, 1.0, 0.25), 0.0, 0.3, Color(0.3, 0.7, 1.0), 1.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.material_override = m
	sh.position = Vector3(ct.x, 0.3, ground_z)
	world.add_child(sh)
	ct.shield = sh
	ct.shield_hp = 1

func _repair_city() -> bool:
	for c in cities:
		if not c.alive:
			var node := (proto_city.duplicate() as Node3D)
			node.position = Vector3(c.x, 0, ground_z)
			world.add_child(node)
			c.node = node
			c.alive = true
			if c.has("rubble") and c.rubble != null:
				(c.rubble as Node).queue_free()
				c.rubble = null
			fx.sparks(Vector3(c.x, 0.4, ground_z), 24, true)
			return true
	return false

# --------------------------------------------------------------- koniec fali / gry
func _wave_end() -> void:
	if state != "play":
		return
	state = "tally"
	var ammo := _ammo_total()
	var alive_c := 0
	for c in cities:
		if c.alive:
			alive_c += 1
	var bonus := ammo * 5 + alive_c * 100
	score += bonus
	Audio.play_sfx("win")
	Settings.vibrate(60)
	_toast("FALA %d ODPARTA!\nBONUS %d" % [wave, bonus], true)
	if score >= next_repair:
		next_repair += 10000
		if _repair_city():
			_toast("FALA %d ODPARTA!\nBONUS %d\nUKŁAD ODBUDOWANY" % [wave, bonus], true)
	await get_tree().create_timer(2.2, false).timeout
	if is_inside_tree() and state == "tally":
		wave += 1
		_start_wave()

func _game_over() -> void:
	if state == "over":
		return
	state = "over"
	var high := Save.get_int("dnammoc", "high", 0)
	var best_w := Save.get_int("dnammoc", "best_wave", 0)
	if score > high:
		Save.set_int("dnammoc", "high", score)
	if wave > best_w:
		Save.set_int("dnammoc", "best_wave", wave)
	Audio.play_sfx("drain")
	Settings.vibrate(80)
	await get_tree().create_timer(1.2, false).timeout
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
	var t := UiKit.label("RDZEŃ UTRACONY", 32, UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	var s := UiKit.label("WYNIK %d\nFALA %d\nREKORD %d" % [score, wave, Save.get_int("dnammoc", "high", 0)], 16, UiKit.C_YELLOW, 6)
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
	lbl_toast.offset_top = HUD_TOP_PX + 40
	lbl_toast.offset_bottom = HUD_TOP_PX + 200
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.modulate.a = 0.0
	ui.add_child(lbl_toast)

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
	var alive := 0
	for c in cities:
		if c.alive:
			alive += 1
	lbl_info.text = "FALA %d   UKŁADY %d/6   AMUNICJA %d   REKORD %d" % [wave, alive, _ammo_total(), Save.get_int("dnammoc", "high", 0)]
	var parts := PackedStringArray()
	for k in fx_t:
		if fx_t[k] > 0.0:
			var info: Dictionary = PU[k]
			parts.append("[color=%s]%s %d s[/color]" % ["#7dffb0" if info.good else "#ff6a5a", info.name, ceili(fx_t[k])])
	var txt := "   ".join(parts)
	if txt != fx_text_cache:
		fx_text_cache = txt
		lbl_fx.text = txt

func _unhandled_input(e: InputEvent) -> void:
	var pos := Vector2.ZERO
	if e is InputEventScreenTouch and e.pressed:
		pos = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not OS.has_feature("mobile"):
		pos = e.position
	else:
		return
	if overlay != null or panel != null or state != "play":
		return
	if pos.y < HUD_TOP_PX - 60.0:
		return
	_fire_at(_screen_to_world(pos))

func _open_options() -> void:
	if overlay:
		return
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

func _schedule_ambient() -> void:
	get_tree().create_timer(randf_range(2.0, 4.0)).timeout.connect(_ambient)

func _ambient() -> void:
	if state == "play" and Settings.effects and overlay == null and cities.size() > 1:
		var a: Dictionary = cities[randi() % cities.size()]
		var b: Dictionary = cities[randi() % cities.size()]
		if a.alive and b.alive and a != b and absf(a.x - b.x) < 2.6:
			var pa := Vector3(a.x, 0.45, ground_z)
			var pb := Vector3(b.x, 0.45, ground_z)
			_arc(pa, pb, 0.25)
			fx.sparks(pb, 8)
			Audio.play_sfx("spark", -10.0, randf_range(0.9, 1.3))
	_schedule_ambient()
