extends Node3D
## Sirtet - spadające bloki-moduły na płytce PCB (łączenie rzędów). Plansza 8 kolumn, wysokość zależy od ekranu.
## Sterowanie: przyciski na dole albo gesty na planszy (przeciągnij w bok = ruch, stuknięcie = obrót,
## przeciągnij w dół = szybciej, szybkie machnięcie w dół = zrzut). Klawiatura: strzałki, Z/X, spacja, C.

const COLS := 8
const CAM_FOV := 40.0
const HUD_TOP_PX := 270.0           # miejsce na HUD i podgląd nad planszą (px bazowe)
const CTRL_PX := 215.0              # miejsce na przyciski pod planszą
const SPAWN_Y := -1
const LOCK_DELAY := 0.5
const JUNK := 7
const SHAPES := [
	{"n": 4, "c": [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]},   # I
	{"n": 2, "c": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},   # O
	{"n": 3, "c": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]},   # T
	{"n": 3, "c": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]},   # S
	{"n": 3, "c": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]},   # Z
	{"n": 3, "c": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]},   # J
	{"n": 3, "c": [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]},   # L
]
const KICKS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -1)]
const LINE_SCORE := [0, 100, 300, 500, 800]
const PU := {
	"slow": {"name": "SPOWOLNIENIE", "desc": "wolniejsze spadanie 15 s", "good": true, "dur": 15.0, "col": Color(0.75, 0.9, 1.0), "shape": "heat"},
	"x2": {"name": "PODWÓJNE PUNKTY", "desc": "x2 przez 15 s", "good": true, "dur": 15.0, "col": Color(1.0, 0.85, 0.2), "shape": "x2"},
	"bomb": {"name": "ZWARCIE", "desc": "czyści 2 dolne rzędy", "good": true, "dur": 0.0, "col": Color(0.4, 1.0, 0.4), "shape": "multi"},
	"fast": {"name": "PRZYSPIESZENIE", "desc": "szybsze spadanie 12 s", "good": false, "dur": 12.0, "col": Color(1.0, 0.25, 0.1), "shape": "surge"},
	"junk": {"name": "ŚMIECI", "desc": "dodatkowy rząd od dołu", "good": false, "dur": 0.0, "col": Color(1.0, 0.1, 0.15), "shape": "mine"},
	"rev": {"name": "ODWROTNA POLARYZACJA", "desc": "lewo i prawo odwrócone 10 s", "good": false, "dur": 10.0, "col": Color(0.85, 0.35, 1.0), "shape": "rev"},
}

var root: Node3D
var kit: PcbKit
var fx: Fx
var camera: Camera3D
var board_w := 10.6
var board_d := 24.0
var rows := 14
var ox := 0.0
var oz := 0.0
var ppu := 68.0
var vp := Vector2(720, 1600)
var pieces_root: Node3D
var preview_root: Node3D
var protos: Array = []
var ghost_nodes: Array = []
var arcs: Array = []
var arc_idx := 0

var grid: Array = []
var cur: Dictionary = {}
var bag: Array = []
var next_q: Array = []
var hold_type := -1
var can_hold := true
var state := "play"          # play / clear / over
var score := 0
var lines := 0
var level := 1
var combo := 0
var grav_t := 0.0
var lock_t := 0.0
var lock_resets := 0
var fx_t := {"slow": 0.0, "x2": 0.0, "fast": 0.0, "rev": 0.0}
var pickup_bodies: Array = []
var hold_dir := 0
var das_t := 0.0
var soft := false
var g_active := false
var g_start := Vector2.ZERO
var g_last := Vector2.ZERO
var g_acc := 0.0
var g_t0 := 0.0
var g_moved := false
var g_soft := false
var overlay: Control
var over_panel: Control

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
	_build_protos()
	for i in 6:
		arcs.append(Discharger.new(root))
	pieces_root = Node3D.new()
	root.add_child(pieces_root)
	preview_root = Node3D.new()
	root.add_child(preview_root)
	_setup_ui()
	Audio.play_music("sirtet")
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
	var w := COLS + 2.6
	vp = get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_tan := tan(deg_to_rad(CAM_FOV / 2.0))
	var dist := (w / 2.0) / half_tan + 0.7
	var plane_w := 2.0 * dist * half_tan
	ppu = vp.x / plane_w
	var half_h := vp.y / ppu / 2.0
	board_w = maxf(w, plane_w * 1.1)
	board_d = maxf(24.0, half_h * 2.0 * 1.1)
	# wysokość planszy: tyle rzędów, ile zmieści się między HUD-em a przyciskami
	var avail := vp.y - HUD_TOP_PX - CTRL_PX
	var fit := int(floor(avail / ppu)) - 2
	if fit < 12:
		# ekran niższy niż potrzeba (np. tablet): zostaje 12 rzędów, a kamera się oddala,
		# żeby cała plansza (z ramką) mieściła się nad przyciskami
		rows = 12
		ppu = avail / float(rows + 2)
		plane_w = vp.x / ppu
		dist = (plane_w / 2.0) / half_tan
		half_h = vp.y / ppu / 2.0
		board_w = maxf(w, plane_w * 1.1)
		board_d = maxf(24.0, half_h * 2.0 * 1.1)
	else:
		rows = mini(fit, 17)
	camera.position = Vector3(0, dist, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	# górna krawędź ramki na ekranie = HUD_TOP_PX
	var z_frame_top := (HUD_TOP_PX - vp.y / 2.0) / ppu
	ox = -(COLS - 1) / 2.0
	oz = z_frame_top + 1.5          # środek rzędu 0 (ramka 1 + pół komórki)

func cell_pos(x: float, y: float) -> Vector3:
	return Vector3(ox + x, 0.0, oz + y)

func _screen_to_world(p: Vector2) -> Vector3:
	return Vector3((p.x - vp.x / 2.0) / ppu, 0.0, (p.y - vp.y / 2.0) / ppu)

func _build_board() -> void:
	kit.add_board(board_w, board_d, Vector2(COLS / 2.0 + 1.3, rows / 2.0 + 1.5), 777)
	var tile_a := kit.mat(Color(0.03, 0.09, 0.06), 0.0, 0.7)
	var tile_b := kit.mat(Color(0.05, 0.13, 0.09), 0.0, 0.7)
	for x in COLS:
		for y in rows:
			kit.begin_part(cell_pos(x, y), 0.0)
			kit.box(tile_a if (x + y) % 2 == 0 else tile_b, Vector3(0.96, 0.03, 0.96), Vector3(0, 0.015, 0))
	var i := 0
	for x in range(-1, COLS + 1):
		for y in range(-1, rows + 1):
			if x >= 0 and x < COLS and y >= 0 and y < rows:
				continue
			kit.begin_part(cell_pos(x, y), 0.0)
			kit.part(int(kit._hash2(x * 3.0 + 1.0, y * 5.0 + 2.0) * 12.0) % 12, i)
			i += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var occ := {}
	kit.add_bus(-1.5, oz + rows, 1, 2, rng, occ, board_d)
	kit.add_bus(2.0, oz + rows, 1, 2, rng, occ, board_d)
	kit.add_decor(COLS + 2.6, rows + 3.0, occ, board_w, board_d)
	kit.flush(root)

# --------------------------------------------------------------- bloki (modele)
func _build_protos() -> void:
	var cols: Array = [
		[Color(0.0, 0.55, 0.45), Color(0.1, 0.8, 0.65)],     # I: moduł RAM (turkus)
		[Color(0.04, 0.04, 0.05), Color(0.2, 0.2, 0.24)],    # O: układ scalony (czarny)
		[Color(0.08, 0.22, 0.75), Color(0.25, 0.45, 1.0)],   # T: przekaźnik (niebieski)
		[Color(0.85, 0.6, 0.05), Color(1.0, 0.85, 0.25)],    # S: tantal (żółty)
		[Color(0.7, 0.28, 0.06), Color(0.95, 0.5, 0.15)],    # Z: transformator (pomarańcz)
		[Color(0.5, 0.52, 0.58), Color(0.8, 0.82, 0.88)],    # J: radiator (srebro)
		[Color(0.6, 0.06, 0.1), Color(0.95, 0.2, 0.25)],     # L: kondensator (czerwony)
		[Color(0.22, 0.22, 0.26), Color(0.35, 0.35, 0.4)],   # śmieci
	]
	for t in 8:
		var n := Node3D.new()
		kit.begin_part(Vector3.ZERO, 0.0)
		var base := kit.mat(cols[t][0], 0.3, 0.45)
		var top := kit.mat(cols[t][1], 0.4, 0.35)
		kit.box(base, Vector3(0.94, 0.4, 0.94), Vector3(0, 0.2, 0))
		kit.box(top, Vector3(0.7, 0.05, 0.7), Vector3(0, 0.425, 0))
		match t:
			0:  # RAM: złote styki + czarny układ
				for i in 5:
					kit.box(kit.mats.gold, Vector3(0.1, 0.1, 0.07), Vector3(-0.36 + i * 0.18, 0.12, 0.46))
				kit.box(kit.mats.chip, Vector3(0.4, 0.06, 0.3), Vector3(0, 0.47, -0.05))
			1:
				kit.box(kit.mats.chip_mark, Vector3(0.1, 0.03, 0.1), Vector3(-0.26, 0.45, -0.26))
				for i in 4:
					kit.box(kit.mats.silver, Vector3(0.08, 0.06, 0.1), Vector3(-0.47, 0.12, -0.27 + i * 0.18))
					kit.box(kit.mats.silver, Vector3(0.08, 0.06, 0.1), Vector3(0.47, 0.12, -0.27 + i * 0.18))
			2:
				kit.box(kit.mats.white, Vector3(0.44, 0.03, 0.26), Vector3(0, 0.46, 0))
			3:
				kit.box(kit.mats.chip, Vector3(0.1, 0.06, 0.7), Vector3(-0.3, 0.46, 0))
			4:
				kit.torus(kit.mats.copper, 0.1, 0.28, Vector3(0, 0.5, 0))
			5:
				for i in 4:
					kit.box(kit.mats.alu, Vector3(0.07, 0.14, 0.7), Vector3(-0.27 + i * 0.18, 0.48, 0))
			6:
				kit.cyl(kit.mats.cap_top, 0.22, 0.06, Vector3(0, 0.46, 0), 16)
		kit.flush(n)
		protos.append(n)

func _make_block(type: int) -> Node3D:
	var n := Node3D.new()
	var body := (protos[type] as Node3D).duplicate() as Node3D
	n.add_child(body)
	return n

func _shape_cells(type: int, rot: int) -> Array[Vector2i]:
	var n: int = SHAPES[type].n
	var out: Array[Vector2i] = []
	for c in SHAPES[type].c:
		var p: Vector2i = c
		for _i in rot % 4:
			p = Vector2i(n - 1 - p.y, p.x)
		out.append(p)
	return out

func _cells_of(type: int, rot: int, pos: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _shape_cells(type, rot):
		out.append(c + pos)
	return out

func _valid(cells: Array[Vector2i]) -> bool:
	for c in cells:
		if c.x < 0 or c.x >= COLS or c.y >= rows:
			return false
		if c.y >= 0 and grid[c.x][c.y] != null:
			return false
	return true

# ------------------------------------------------------------------ przebieg gry
func _new_game() -> void:
	for c in pieces_root.get_children():
		c.queue_free()
	pickup_bodies.clear()
	grid = []
	for x in COLS:
		var col := []
		col.resize(rows)
		col.fill(null)
		grid.append(col)
	score = 0
	lines = 0
	level = 1
	combo = 0
	hold_type = -1
	can_hold = true
	bag.clear()
	next_q.clear()
	for k in fx_t:
		fx_t[k] = 0.0
	if over_panel:
		over_panel.queue_free()
		over_panel = null
	state = "play"
	cur = {}
	_spawn(_draw_piece())

func _refill_bag() -> void:
	var b: Array = [0, 1, 2, 3, 4, 5, 6]
	b.shuffle()
	bag.append_array(b)

func _draw_piece() -> int:
	while next_q.size() < 4:
		if bag.is_empty():
			_refill_bag()
		next_q.append(bag.pop_front())
	return next_q.pop_front()

func _spawn(type: int) -> void:
	var n: int = SHAPES[type].n
	cur = {"type": type, "rot": 0, "pos": Vector2i((COLS - n) / 2, SPAWN_Y), "nodes": [], "pick_idx": -1, "pick_type": ""}
	var cells := _cells_of(type, 0, cur.pos)
	for i in 4:
		var node := _make_block(type)
		node.position = cell_pos(cells[i].x, cells[i].y)
		pieces_root.add_child(node)
		cur.nodes.append(node)
	# co kilka klocków: komórka z power-upem
	if randf() < 0.11 and score > 0:
		var types: Array = PU.keys()
		var pt: String = types[randi() % types.size()] if randf() < 0.7 else ["fast", "junk", "rev"][randi() % 3]
		if PU[pt].good == false and randf() < 0.5:
			pt = ["slow", "x2", "bomb"][randi() % 3]
		cur.pick_idx = randi() % 4
		cur.pick_type = pt
		_attach_pickup(cur.nodes[cur.pick_idx], pt)
	grav_t = 0.0
	lock_t = 0.0
	lock_resets = 0
	can_hold = true
	_update_ghost()
	_update_previews()
	if not _valid(cells):
		_game_over()

func _attach_pickup(block: Node3D, pt: String) -> void:
	var info: Dictionary = PU[pt]
	var pn := PickupKit.build(kit, info.shape, Vector3.ZERO, info.col, info.good)
	pn.scale = Vector3.ONE * 0.55
	pn.position.y = 0.45
	pn.name = "Pick"
	block.add_child(pn)
	pickup_bodies.append(pn.get_node("Body"))

func _gravity_delay() -> float:
	var d := maxf(0.07, 0.75 * pow(0.85, level - 1))
	if fx_t.slow > 0.0:
		d *= 2.2
	if fx_t.fast > 0.0:
		d *= 0.45
	return d

func _try_move(dx: int, dy: int) -> bool:
	if cur.is_empty() or state != "play":
		return false
	var np: Vector2i = cur.pos + Vector2i(dx, dy)
	if not _valid(_cells_of(cur.type, cur.rot, np)):
		return false
	cur.pos = np
	if dy == 0 and lock_resets < 12:
		lock_t = 0.0
		lock_resets += 1
	_update_ghost()
	return true

func _try_rotate(dir: int) -> bool:
	if cur.is_empty() or state != "play" or cur.type == 1:
		return false
	var nr: int = (cur.rot + dir + 4) % 4
	for k in KICKS:
		var np: Vector2i = cur.pos + k
		if _valid(_cells_of(cur.type, nr, np)):
			cur.rot = nr
			cur.pos = np
			if lock_resets < 12:
				lock_t = 0.0
				lock_resets += 1
			Audio.play_sfx("rot")
			_update_ghost()
			return true
	return false

func _ghost_pos() -> Vector2i:
	var p: Vector2i = cur.pos
	while _valid(_cells_of(cur.type, cur.rot, p + Vector2i(0, 1))):
		p.y += 1
	return p

func _update_ghost() -> void:
	if cur.is_empty():
		return
	if ghost_nodes.is_empty():
		var gm := kit.mat(Color(1, 1, 1, 0.18), 0.0, 0.5, Color(0.6, 0.9, 1.0), 0.8)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for i in 4:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 0.12, 0.9)
			mi.mesh = bm
			mi.material_override = gm
			root.add_child(mi)
			ghost_nodes.append(mi)
	var cells := _cells_of(cur.type, cur.rot, _ghost_pos())
	for i in 4:
		(ghost_nodes[i] as Node3D).position = cell_pos(cells[i].x, cells[i].y) + Vector3(0, 0.06, 0)
		(ghost_nodes[i] as Node3D).visible = state == "play"

func _hard_drop() -> void:
	if cur.is_empty() or state != "play":
		return
	var gp := _ghost_pos()
	var d: int = gp.y - cur.pos.y
	cur.pos = gp
	score += d * 2 * (2 if fx_t.x2 > 0.0 else 1)
	Audio.play_sfx("hard")
	Settings.vibrate(20)
	for c in _cells_of(cur.type, cur.rot, cur.pos):
		fx.sparks(cell_pos(c.x, c.y) + Vector3(0, 0.3, 0), 3)
	_lock()

func _soft_step() -> void:
	if _try_move(0, 1):
		score += 1
		grav_t = 0.0

func _hold() -> void:
	if cur.is_empty() or state != "play" or not can_hold:
		return
	Audio.play_sfx("hold")
	var t: int = cur.type
	for n in cur.nodes:
		(n as Node).queue_free()
	var swap_t := hold_type
	hold_type = t
	cur = {}
	_spawn(swap_t if swap_t >= 0 else _draw_piece())
	can_hold = false
	_update_previews()

func _lock() -> void:
	state = "clear"
	var cells := _cells_of(cur.type, cur.rot, cur.pos)
	var over := false
	for i in 4:
		var c := cells[i]
		if c.y < 0:
			over = true
			continue
		grid[c.x][c.y] = {"type": cur.type, "node": cur.nodes[i]}
		(cur.nodes[i] as Node3D).position = cell_pos(c.x, c.y)
	Audio.play_sfx("lock", -4.0)
	var pt: String = cur.pick_type
	var pick_idx: int = cur.pick_idx
	if pick_idx >= 0:
		var pn := (cur.nodes[pick_idx] as Node3D).get_node_or_null("Pick")
		if pn:
			pickup_bodies.erase(pn.get_node("Body"))
			pn.queue_free()
	cur = {}
	for g in ghost_nodes:
		(g as Node3D).visible = false
	if over:
		_game_over()
		return
	if pt != "":
		await _apply_pickup(pt, cells[pick_idx])
	var full: Array = []
	for y in rows:
		var f := true
		for x in COLS:
			if grid[x][y] == null:
				f = false
				break
		if f:
			full.append(y)
	if full.is_empty():
		combo = 0
		_after_lock()
	else:
		await _clear_rows(full, false)
		_after_lock()

func _after_lock() -> void:
	if state == "over" or not is_inside_tree():
		return
	state = "play"
	_spawn(_draw_piece())

func _clear_rows(full: Array, bomb: bool) -> void:
	state = "clear"
	var n := full.size()
	combo += 1
	var pts: int = LINE_SCORE[mini(n, 4)] * level
	if bomb:
		pts = 200 * level
	pts += (combo - 1) * 50 * level
	pts *= 2 if fx_t.x2 > 0.0 else 1
	score += pts
	lines += n
	Audio.play_sfx("quad" if n >= 4 else "line", 0.0, 1.0 + (combo - 1) * 0.06)
	Settings.vibrate(20 + n * 15)
	var mid := Vector3.ZERO
	for y in full:
		_arc(cell_pos(0, y) + Vector3(0, 0.4, 0), cell_pos(COLS - 1, y) + Vector3(0, 0.4, 0), 0.4)
		mid += cell_pos(COLS / 2.0 - 0.5, y)
		for x in COLS:
			var cell = grid[x][y]
			if cell == null:
				continue
			grid[x][y] = null
			var node: Node3D = cell.node
			fx.sparks(cell_pos(x, y) + Vector3(0, 0.3, 0), 5)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(node, "scale", Vector3(1.3, 1.3, 1.3), 0.12)
			tw.chain().tween_property(node, "scale", Vector3.ZERO, 0.16)
			tw.chain().tween_callback(node.queue_free)
	mid /= n
	fx.light_flash(mid, Color(1.0, 0.95, 0.5), 3.0 if n < 4 else 4.5)
	_popup(mid, "+%d" % pts)
	if n >= 4:
		_toast("ZWARCIE x4!\n+%d" % pts, true)
	elif combo >= 2:
		_toast("KOMBO x%d!" % combo, true)
	await _wait(0.34)
	if not is_inside_tree():
		return
	# opadanie wyższych rzędów
	var cleared := {}
	for y in full:
		cleared[y] = true
	var write := rows - 1
	for y in range(rows - 1, -1, -1):
		if cleared.has(y):
			continue
		if y != write:
			for x in COLS:
				var cell = grid[x][y]
				grid[x][write] = cell
				grid[x][y] = null
				if cell != null:
					create_tween().tween_property(cell.node as Node3D, "position", cell_pos(x, write), 0.16).set_trans(Tween.TRANS_QUAD)
		write -= 1
	await _wait(0.2)
	var new_level := lines / 10 + 1
	if new_level > level:
		level = mini(new_level, 15)
		Audio.play_sfx("level")
		_toast("POZIOM %d" % level, true)

func _apply_pickup(pt: String, at: Vector2i) -> void:
	var info: Dictionary = PU[pt]
	var good: bool = info.good
	var wp := cell_pos(at.x, at.y)
	fx.sparks(wp + Vector3(0, 0.4, 0), 24, true)
	fx.light_flash(wp, Color(0.4, 1.0, 0.6) if good else Color(1.0, 0.3, 0.2), 2.5)
	Audio.play_sfx("pu_good" if good else "pu_bad")
	Settings.vibrate(30)
	_toast("%s\n%s" % [info.name, info.desc], good)
	match pt:
		"bomb":
			await _clear_rows([rows - 2, rows - 1], true)
		"junk":
			_add_junk()
		_:
			fx_t[pt] = float(info.dur)

func _add_junk() -> void:
	for x in COLS:
		if grid[x][0] != null:
			_game_over()
			return
	for y in range(0, rows - 1):
		for x in COLS:
			var cell = grid[x][y + 1]
			grid[x][y] = cell
			grid[x][y + 1] = null
			if cell != null:
				create_tween().tween_property(cell.node as Node3D, "position", cell_pos(x, y), 0.2)
	var hole := randi() % COLS
	for x in COLS:
		if x == hole:
			continue
		var node := _make_block(JUNK)
		node.position = cell_pos(x, rows)
		pieces_root.add_child(node)
		grid[x][rows - 1] = {"type": JUNK, "node": node}
		create_tween().tween_property(node, "position", cell_pos(x, rows - 1), 0.2)

# --------------------------------------------------------------------------- pętla
func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout

func _process(delta: float) -> void:
	for k in fx_t:
		if state != "over" and fx_t[k] > 0.0:
			fx_t[k] = maxf(0.0, fx_t[k] - delta)
	for a in arcs:
		(a as Discharger).update(delta)
	for b in pickup_bodies:
		if is_instance_valid(b):
			(b as Node3D).rotation.y += delta * 2.0
	_update_hud()
	if state != "play" or cur.is_empty():
		return
	# ruch ciągły (przytrzymane przyciski)
	if hold_dir != 0:
		das_t -= delta
		if das_t <= 0.0:
			_try_move(hold_dir * (-1 if fx_t.rev > 0.0 else 1), 0)
			das_t = 0.055
	if soft or g_soft:
		grav_t += delta * 12.0
	grav_t += delta
	var gd := _gravity_delay()
	while grav_t >= gd and state == "play":
		grav_t -= gd
		if _try_move(0, 1):
			if soft or g_soft:
				score += 1
		else:
			break
	# opóźnienie blokady
	if state == "play" and not _valid(_cells_of(cur.type, cur.rot, cur.pos + Vector2i(0, 1))):
		lock_t += delta
		if lock_t >= LOCK_DELAY:
			_lock()
	elif state == "play":
		lock_t = 0.0
	# płynne ustawianie węzłów aktywnego klocka
	if state == "play" and not cur.is_empty():
		var cells := _cells_of(cur.type, cur.rot, cur.pos)
		for i in 4:
			var node: Node3D = cur.nodes[i]
			node.position = node.position.lerp(cell_pos(cells[i].x, cells[i].y), minf(1.0, delta * 30.0))

# ---------------------------------------------------------------------- sterowanie
func _input_dir(d: int) -> int:
	return -d if fx_t.rev > 0.0 else d

func _press_dir(d: int) -> void:
	hold_dir = d
	das_t = 0.17
	_try_move(_input_dir(d), 0)
	Audio.play_sfx("tick", -8.0)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and state == "play":
		match e.keycode:
			KEY_LEFT, KEY_A:
				_try_move(_input_dir(-1), 0)
			KEY_RIGHT, KEY_D:
				_try_move(_input_dir(1), 0)
			KEY_UP, KEY_X, KEY_W:
				_try_rotate(1)
			KEY_Z:
				_try_rotate(-1)
			KEY_DOWN, KEY_S:
				_soft_step()
			KEY_SPACE:
				_hard_drop()
			KEY_C:
				_hold()
		return
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
	match kind:
		"down":
			if state != "play" or overlay != null or pos.y < HUD_TOP_PX - 40.0 or pos.y > vp.y - CTRL_PX:
				return
			g_active = true
			g_start = pos
			g_last = pos
			g_acc = 0.0
			g_t0 = Time.get_ticks_msec() / 1000.0
			g_moved = false
			g_soft = false
		"move":
			if not g_active:
				return
			g_acc += pos.x - g_last.x
			g_last = pos
			var step := ppu * 0.9
			while absf(g_acc) >= step:
				var d := 1 if g_acc > 0.0 else -1
				g_acc -= d * step
				_try_move(_input_dir(d), 0)
				g_moved = true
			if pos.y - g_start.y > ppu * 1.6 and absf(pos.x - g_start.x) < ppu * 2.0:
				g_soft = true
				g_moved = true
		"up":
			if not g_active:
				return
			g_active = false
			g_soft = false
			var dur := Time.get_ticks_msec() / 1000.0 - g_t0
			var dy := g_last.y - g_start.y
			if dur < 0.3 and dy > ppu * 3.0 and absf(g_last.x - g_start.x) < ppu * 2.0:
				_hard_drop()
			elif not g_moved and (g_last - g_start).length() < ppu * 0.4 and dur < 0.35:
				_try_rotate(1)

# --------------------------------------------------------------- podglądy (next/hold)
func _update_previews() -> void:
	for c in preview_root.get_children():
		c.queue_free()
	# HOLD po lewej, NEXT (3) po prawej - w pasie HUD nad planszą
	var hold_c := _screen_to_world(Vector2(vp.x * 0.16, HUD_TOP_PX - 70.0))
	if hold_type >= 0:
		_preview_piece(hold_type, hold_c, 0.55)
	var next_c := _screen_to_world(Vector2(vp.x * 0.5, HUD_TOP_PX - 70.0))
	for i in 3:
		if i < next_q.size():
			_preview_piece(next_q[i], next_c + Vector3(i * 1.5 + 0.2, 0, 0), 0.5 if i == 0 else 0.4)

func _label3d(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.005
	l.modulate = Color(0.9, 0.95, 0.9, 0.85)
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = pos
	preview_root.add_child(l)

func _preview_piece(type: int, center: Vector3, sc: float) -> void:
	var cells := _shape_cells(type, 0)
	var mn := Vector2(99, 99)
	var mx := Vector2(-99, -99)
	for c in cells:
		mn = Vector2(minf(mn.x, c.x), minf(mn.y, c.y))
		mx = Vector2(maxf(mx.x, c.x), maxf(mx.y, c.y))
	var mid := (mn + mx) / 2.0
	for c in cells:
		var b := _make_block(type)
		b.scale = Vector3.ONE * sc
		b.position = center + Vector3((c.x - mid.x) * sc, 0, (c.y - mid.y) * sc)
		preview_root.add_child(b)

# ------------------------------------------------------------------------------- UI
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
	lbl_info.position = Vector2(20, 98)
	ui.add_child(lbl_info)
	lbl_fx = RichTextLabel.new()
	lbl_fx.bbcode_enabled = true
	lbl_fx.fit_content = true
	lbl_fx.scroll_active = false
	lbl_fx.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_fx.position = Vector2(20, 124)
	lbl_fx.custom_minimum_size = Vector2(672, 40)
	lbl_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_fx.add_theme_font_size_override("normal_font_size", 16)
	lbl_fx.add_theme_constant_override("outline_size", 6)
	lbl_fx.add_theme_color_override("font_outline_color", Color.BLACK)
	ui.add_child(lbl_fx)
	var l_hold := UiKit.label("HOLD", 16, UiKit.C_CYAN, 6)
	l_hold.position = Vector2(vp.x * 0.16 - 32.0, 164)
	ui.add_child(l_hold)
	var l_next := UiKit.label("NEXT", 16, UiKit.C_CYAN, 6)
	l_next.position = Vector2(vp.x * 0.5 + 40.0, 164)
	ui.add_child(l_next)
	lbl_toast = UiKit.label("", 24, Color.WHITE, 10)
	lbl_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_toast.offset_top = HUD_TOP_PX + 60
	lbl_toast.offset_bottom = HUD_TOP_PX + 190
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.modulate.a = 0.0
	ui.add_child(lbl_toast)

	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 8
	bottom.offset_right = -8
	bottom.offset_top = -(CTRL_PX - 40.0)
	bottom.offset_bottom = -22
	bottom.add_theme_constant_override("separation", 6)
	ui.add_child(bottom)
	bottom.add_child(_ctl("HOLD", func(): _hold()))
	bottom.add_child(_ctl_hold("<", -1))
	bottom.add_child(_ctl("OBR", func(): _try_rotate(1)))
	bottom.add_child(_ctl_hold(">", 1))
	bottom.add_child(_ctl_soft())
	bottom.add_child(_ctl("DROP", func(): _hard_drop()))

func _ctl(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(b, 16, UiKit.C_ORANGE)
	b.button_down.connect(func():
		if state == "play" and overlay == null:
			cb.call())
	return b

func _ctl_hold(text: String, d: int) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(b, 24, UiKit.C_CYAN)
	b.button_down.connect(func():
		if state == "play" and overlay == null:
			_press_dir(d))
	b.button_up.connect(func():
		if hold_dir == d:
			hold_dir = 0)
	return b

func _ctl_soft() -> Button:
	var b := Button.new()
	b.text = "v"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	UiKit.style_button(b, 24, UiKit.C_CYAN)
	b.button_down.connect(func(): soft = true)
	b.button_up.connect(func(): soft = false)
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

func _update_hud() -> void:
	lbl_score.text = str(score)
	lbl_info.text = "POZIOM %d   LINIE %d   REKORD %d" % [level, lines, Save.get_int("sirtet", "high", 0)]
	var parts := PackedStringArray()
	for k in fx_t:
		if fx_t[k] > 0.0:
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
	l.font_size = 64
	l.pixel_size = 0.007
	l.modulate = Color(1, 0.95, 0.5)
	l.outline_size = 10
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.position = Vector3(pos.x, 1.0, pos.z)
	root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:z", pos.z - 1.2, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)

func _marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	root.add_child(m)
	m.position = pos
	get_tree().create_timer(0.8, false).timeout.connect(m.queue_free)
	return m

func _arc(from: Vector3, to: Vector3, dur := 0.4) -> void:
	if not Settings.effects:
		return
	var d: Discharger = arcs[arc_idx]
	arc_idx = (arc_idx + 1) % arcs.size()
	d.fire(_marker(from), to, dur)

func _game_over() -> void:
	if state == "over":
		return
	state = "over"
	hold_dir = 0
	soft = false
	var high := Save.get_int("sirtet", "high", 0)
	var record := score > high
	if record:
		Save.set_int("sirtet", "high", score)
	for g in ghost_nodes:
		(g as Node3D).visible = false
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
	box.offset_top = -280
	box.offset_bottom = 280
	box.add_theme_constant_override("separation", 24)
	over_panel.add_child(box)
	var t := UiKit.label("KONIEC GRY", 40, UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := UiKit.label("WYNIK\n%d" % score, 32, UiKit.C_YELLOW, 8)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	var hs := UiKit.label(("NOWY REKORD!" if record else "REKORD: %d" % high) + "\nPOZIOM %d   LINIE %d" % [level, lines], 16, UiKit.C_GREEN if record else UiKit.C_CYAN, 6)
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
	Audio.play_sfx("win" if record else "drain")
	Settings.vibrate(80)

func _open_options() -> void:
	if overlay:
		return
	hold_dir = 0
	soft = false
	g_active = false
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
	if state == "play" and Settings.effects and overlay == null and not grid.is_empty():
		var x := randi() % COLS
		var y := randi() % rows
		if grid[x][y] != null:
			var from := cell_pos(x, y) + Vector3(0, 0.45, 0)
			var to := cell_pos(clampi(x + (randi() % 3 - 1), 0, COLS - 1), clampi(y + (randi() % 3 - 1), 0, rows - 1)) + Vector3(0, 0.45, 0)
			if from.distance_to(to) > 0.3:
				_arc(from, to, 0.25)
				fx.sparks(to, 8)
				Audio.play_sfx("spark", -10.0, randf_range(0.9, 1.3))
	_schedule_ambient()
