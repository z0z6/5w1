extends Node3D
## Chip Match - match-3 z elementów elektronicznych na płytce PCB.
## Zamiana sąsiednich elementów (przeciągnięcie albo dwa stuknięcia): 3+ takie same w rzędzie znikają,
## reszta spada, kaskady mnożą punkty. 4 w rzędzie = ZWARCIE (czyści cały rząd/kolumnę),
## 5 w rzędzie lub układ L/T = EMP (zamień z elementem -> znikają wszystkie takie same).

const COLS := 8
const ROWS := 10
const BOARD_Z := 0.8
const CAM_FOV := 40.0
const MAX_LEVEL := 30
const SWAP_T := 0.16
const INVALID := Vector2i(-1, -1)
const DIRS2: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const TYPE_NAMES := ["KONDENSATOR", "UKŁAD SCAL.", "DIODA LED", "TANTAL", "DŁAWIK", "KWARC"]

var root: Node3D
var kit: PcbKit
var fx: Fx
var camera: Camera3D
var board_w := 10.6
var board_d := 24.0
var pieces_root: Node3D
var protos: Array = []
var emp_mat: StandardMaterial3D
var mark_mat: StandardMaterial3D
var sel_ring: MeshInstance3D
var hint_ring: MeshInstance3D
var arcs: Array = []
var arc_idx := 0

var grid: Array = []
var ox := 0.0
var oz := 0.0
var level := 1
var types_n := 5
var score := 0
var moves := 20
var target := 2000
var goal_reached := false
var busy := false
var sel := INVALID
var drag_cell := INVALID
var boosters := {"solder": 1, "shuffle": 1, "battery": 1}
var booster_mode := ""
var idle_t := 0.0
var best_cascade := 0
var overlay: Control
var result_panel: Control

var ui: CanvasLayer
var lbl_level: Label
var lbl_score: Label
var lbl_moves: Label
var lbl_target: Label
var lbl_toast: Label
var bar_bg: ColorRect
var bar_fill: ColorRect
var bar_goal: ColorRect
var booster_btns: Dictionary = {}
var toast_tw: Tween

func _ready() -> void:
	root = Node3D.new()
	add_child(root)
	kit = PcbKit.new(root)
	fx = Fx.new(self, kit.mats.spark)
	fx.spark_parent = root
	fx.pulse_leds(kit.mats.led)
	_setup_environment()
	_setup_camera()
	_build_board()
	_build_protos()
	for i in 8:
		arcs.append(Discharger.new(root))
	pieces_root = Node3D.new()
	root.add_child(pieces_root)
	_make_rings()
	_setup_ui()
	Audio.play_music("match3")
	_start_level(clampi(Save.get_int("match3", "unlocked", 1), 1, MAX_LEVEL))
	_schedule_ambient()

# ------------------------------------------------------- środowisko, kamera, plansza
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

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAM_FOV
	add_child(camera)
	var w := COLS + 2.6
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_tan := tan(deg_to_rad(CAM_FOV / 2.0))
	var dist := (w / 2.0) / half_tan + 0.7
	var half_w := dist * half_tan
	var half_h := half_w / aspect
	# na niższych ekranach (tablet) oddal kamerę, by plansza mieściła się między HUD-em a boosterami
	var ppu_cap := minf((vp.y / 2.0 - 250.0) / 5.2, (vp.y / 2.0 - 140.0) / 6.8)
	if vp.x / (2.0 * half_w) > ppu_cap and ppu_cap > 10.0:
		half_w = vp.x / (2.0 * ppu_cap)
		dist = half_w / half_tan
		half_h = half_w / aspect
	board_w = maxf(w, half_w * 2.0 * 1.1)
	board_d = maxf(ROWS + 4.0, half_h * 2.0 * 1.1)
	camera.position = Vector3(0, dist, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	ox = -(COLS - 1) / 2.0
	oz = BOARD_Z - (ROWS - 1) / 2.0

func cell_pos(x: float, y: float) -> Vector3:
	return Vector3(ox + x, 0.0, oz + y)

func _build_board() -> void:
	kit.add_board(board_w, board_d, Vector2(COLS / 2.0 + 1.3, ROWS / 2.0 + 1.5), 31337)
	ox = -(COLS - 1) / 2.0
	oz = BOARD_Z - (ROWS - 1) / 2.0
	var tile_a := kit.mat(Color(0.03, 0.09, 0.06), 0.0, 0.7)
	var tile_b := kit.mat(Color(0.05, 0.14, 0.09), 0.0, 0.7)
	for x in COLS:
		for y in ROWS:
			kit.begin_part(cell_pos(x, y), 0.0)
			kit.box(tile_a if (x + y) % 2 == 0 else tile_b, Vector3(0.96, 0.03, 0.96), Vector3(0, 0.015, 0))
	# ramka z elementów wokół planszy
	var i := 0
	for x in range(-1, COLS + 1):
		for y in range(-1, ROWS + 1):
			if x >= 0 and x < COLS and y >= 0 and y < ROWS:
				continue
			kit.begin_part(cell_pos(x, y), 0.0)
			kit.part(int(kit._hash2(x * 3.0 + 1.0, y * 5.0 + 2.0) * 12.0) % 12, i)
			i += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var occ := {}
	var z_top := oz - 1.0
	var z_bot := oz + ROWS
	kit.add_bus(-2.0, z_top, -1, 2, rng, occ, board_d)
	kit.add_bus(2.0, z_top, -1, 1, rng, occ, board_d)
	kit.add_bus(-1.5, z_bot, 1, 2, rng, occ, board_d)
	kit.add_bus(2.0, z_bot, 1, 2, rng, occ, board_d)
	kit.add_decor(COLS + 2.6, ROWS + 3.0, occ, board_w, board_d)
	kit.flush(root)

func _make_rings() -> void:
	sel_ring = _ring(Color(1, 1, 1))
	hint_ring = _ring(Color(1.0, 0.9, 0.2))

func _ring(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	mi.material_override = kit.mat(Color(0.2, 0.2, 0.2), 0.0, 0.3, col, 4.0)
	mi.visible = false
	mi.position.y = 0.06
	root.add_child(mi)
	return mi

# -------------------------------------------------------------- elementy (modele)
func _build_protos() -> void:
	for t in 6:
		protos.append(_build_proto(t))
	emp_mat = kit.mat(Color(0.3, 0.3, 0.3), 0.3, 0.2, Color(1, 0.4, 0.8), 3.5)
	mark_mat = kit.mat(Color(1.0, 0.9, 0.3), 0.0, 0.3, Color(1.0, 0.9, 0.3), 3.0)
	var tw := create_tween().set_loops()
	tw.tween_method(func(h: float):
		var c := Color.from_hsv(h, 0.75, 1.0)
		emp_mat.emission = c
		emp_mat.albedo_color = c * 0.4, 0.0, 1.0, 2.0)
	var tw2 := create_tween().set_loops()
	tw2.tween_property(mark_mat, "emission_energy_multiplier", 5.5, 0.5)
	tw2.tween_property(mark_mat, "emission_energy_multiplier", 1.5, 0.5)

func _build_proto(t: int) -> Node3D:
	var n := Node3D.new()
	kit.begin_part(Vector3.ZERO, 0.0)
	match t:
		0:  # kondensator elektrolityczny (niebieski)
			var blue := kit.mat(Color(0.08, 0.28, 0.95), 0.2, 0.35)
			kit.cyl(blue, 0.32, 0.55, Vector3(0, 0.275, 0), 20)
			kit.cyl(blue, 0.28, 0.02, Vector3(0, 0.56, 0), 20)
			kit.torus(kit.mats.cap_top, 0.27, 0.33, Vector3(0, 0.56, 0))
			kit.box(kit.mats.white, Vector3(0.36, 0.012, 0.05), Vector3(0, 0.575, 0))
			kit.box(kit.mats.white, Vector3(0.05, 0.012, 0.36), Vector3(0, 0.575, 0))
		1:  # układ scalony (czarny, biała kropka, nóżki)
			kit.box(kit.mats.chip, Vector3(0.62, 0.3, 0.7), Vector3(0, 0.15, 0))
			kit.box(kit.mats.chip_mark, Vector3(0.1, 0.02, 0.1), Vector3(-0.2, 0.31, -0.26))
			for i in 4:
				var zz := -0.24 + i * 0.16
				kit.box(kit.mats.silver, Vector3(0.1, 0.05, 0.09), Vector3(-0.35, 0.1, zz))
				kit.box(kit.mats.silver, Vector3(0.1, 0.05, 0.09), Vector3(0.35, 0.1, zz))
		2:  # dioda LED (zielona, świeci)
			kit.box(kit.mats.black, Vector3(0.62, 0.1, 0.62), Vector3(0, 0.05, 0))
			kit.cyl(kit.mats.led[1], 0.25, 0.36, Vector3(0, 0.28, 0), 16)
		3:  # kondensator tantalowy (żółty)
			kit.box(kit.mats.tantal, Vector3(0.62, 0.36, 0.5), Vector3(0, 0.18, 0))
			kit.box(kit.mats.chip, Vector3(0.1, 0.37, 0.52), Vector3(-0.22, 0.185, 0))
		4:  # dławik toroidalny (miedź)
			kit.box(kit.mats.black, Vector3(0.8, 0.06, 0.8), Vector3(0, 0.03, 0))
			kit.torus(kit.mats.copper, 0.12, 0.36, Vector3(0, 0.22, 0))
			kit.torus(kit.mats.copper, 0.12, 0.36, Vector3(0, 0.36, 0))
		_:  # kwarc (srebrny ze złotem)
			kit.box(kit.mats.black, Vector3(0.74, 0.08, 0.74), Vector3(0, 0.04, 0))
			kit.box(kit.mats.silver, Vector3(0.44, 0.5, 0.64), Vector3(0, 0.33, 0))
			kit.box(kit.mats.gold, Vector3(0.3, 0.02, 0.3), Vector3(0, 0.59, 0))
	kit.flush(n)
	return n

func _make_node(type: int, special: int) -> Node3D:
	var node: Node3D
	if special == 3:
		node = Node3D.new()
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.64
		mi.mesh = sm
		mi.material_override = emp_mat
		mi.position.y = 0.36
		node.add_child(mi)
		var rg := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.36
		tm.outer_radius = 0.46
		tm.rings = 20
		tm.ring_segments = 6
		rg.mesh = tm
		rg.material_override = emp_mat
		rg.position.y = 0.36
		node.add_child(rg)
	else:
		node = Node3D.new()
		var body := (protos[type] as Node3D).duplicate() as Node3D
		body.scale = Vector3.ONE * 1.16
		node.add_child(body)
		if special == 1 or special == 2:
			var mark := Node3D.new()
			mark.name = "Mark"
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.92, 0.05, 0.12)
			bar.mesh = bm
			bar.material_override = mark_mat
			bar.position.y = 0.66
			mark.add_child(bar)
			if special == 2:
				mark.rotation.y = PI / 2.0
			node.add_child(mark)
	return node

# ----------------------------------------------------------------------- dane planszy
func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS

func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1

func _new_piece(x: int, y: int, type: int, special: int, world_y: float) -> Dictionary:
	var node := _make_node(type, special)
	node.position = cell_pos(x, world_y)
	pieces_root.add_child(node)
	return {"type": type, "special": special, "node": node, "x": x, "y": y}

func _swap_data(a: Vector2i, b: Vector2i) -> void:
	var pa = grid[a.x][a.y]
	var pb = grid[b.x][b.y]
	grid[a.x][a.y] = pb
	grid[b.x][b.y] = pa
	if pa != null:
		pa.x = b.x
		pa.y = b.y
	if pb != null:
		pb.x = a.x
		pb.y = a.y

func _same(x: int, y: int, t: int) -> bool:
	var p = grid[x][y]
	return p != null and p.special != 3 and p.type == t

func _match_at(c: Vector2i) -> bool:
	var p = grid[c.x][c.y]
	if p == null or p.special == 3:
		return false
	var t: int = p.type
	var cnt := 1
	var x := c.x - 1
	while x >= 0 and _same(x, c.y, t):
		cnt += 1
		x -= 1
	x = c.x + 1
	while x < COLS and _same(x, c.y, t):
		cnt += 1
		x += 1
	if cnt >= 3:
		return true
	cnt = 1
	var y := c.y - 1
	while y >= 0 and _same(c.x, y, t):
		cnt += 1
		y -= 1
	y = c.y + 1
	while y < ROWS and _same(c.x, y, t):
		cnt += 1
		y += 1
	return cnt >= 3

func _find_move() -> Array:
	for x in COLS:
		for y in ROWS:
			var p = grid[x][y]
			if p == null:
				continue
			for d in DIRS2:
				var a := Vector2i(x, y)
				var b := a + d
				if not _in(b):
					continue
				var q = grid[b.x][b.y]
				if q == null:
					continue
				if p.special == 3 or q.special == 3:
					return [a, b]
				_swap_data(a, b)
				var ok := _match_at(a) or _match_at(b)
				_swap_data(a, b)
				if ok:
					return [a, b]
	return []

func _find_matches() -> Dictionary:
	var cells := {}
	var groups: Array = []
	for y in ROWS:
		var x := 0
		while x < COLS:
			var p = grid[x][y]
			if p == null or p.special == 3:
				x += 1
				continue
			var x2 := x
			while x2 + 1 < COLS and _same(x2 + 1, y, p.type):
				x2 += 1
			if x2 - x >= 2:
				var g := {"cells": [], "dir": "h", "type": p.type}
				for i in range(x, x2 + 1):
					g.cells.append(Vector2i(i, y))
					cells[Vector2i(i, y)] = true
				groups.append(g)
			x = x2 + 1
	for x in COLS:
		var y := 0
		while y < ROWS:
			var p = grid[x][y]
			if p == null or p.special == 3:
				y += 1
				continue
			var y2 := y
			while y2 + 1 < ROWS and _same(x, y2 + 1, p.type):
				y2 += 1
			if y2 - y >= 2:
				var g := {"cells": [], "dir": "v", "type": p.type}
				for i in range(y, y2 + 1):
					g.cells.append(Vector2i(x, i))
					cells[Vector2i(x, i)] = true
				groups.append(g)
			y = y2 + 1
	return {"cells": cells, "groups": groups}

# --------------------------------------------------------------------- start poziomu
func _level_params(n: int) -> Dictionary:
	# ~560 pkt na ruch dla losowo grającego; cel rośnie od 45% do 132% tej wartości
	var mv := clampi(24 - n / 2, 14, 24)
	var t := roundi(mv * 560.0 * (0.45 + 0.03 * (n - 1)) / 100.0) * 100
	return {"moves": mv, "target": t, "types": 5 if n < 6 else 6}

func _start_level(n: int) -> void:
	level = n
	var lp := _level_params(n)
	moves = lp.moves
	target = lp.target
	types_n = lp.types
	score = 0
	goal_reached = false
	best_cascade = 0
	boosters = {"solder": 1, "shuffle": 1, "battery": 1}
	booster_mode = ""
	busy = false
	idle_t = 0.0
	if result_panel:
		result_panel.queue_free()
		result_panel = null
	for c in pieces_root.get_children():
		c.queue_free()
	grid = []
	for x in COLS:
		var col := []
		col.resize(ROWS)
		col.fill(null)
		grid.append(col)
	_fill_initial()
	_select(INVALID)
	_toast("POZIOM %d\nCEL: %d PKT W %d RUCHACH" % [level, target, moves], true)
	Audio.play_sfx("level")

func _random_type(avoid: Array) -> int:
	var opts: Array = []
	for t in types_n:
		if not avoid.has(t):
			opts.append(t)
	return opts[randi() % opts.size()] if not opts.is_empty() else randi() % types_n

func _fill_initial() -> void:
	for attempt in 30:
		for x in COLS:
			for y in ROWS:
				if grid[x][y] != null:
					(grid[x][y].node as Node).queue_free()
					grid[x][y] = null
		for x in COLS:
			for y in ROWS:
				var avoid: Array = []
				if x >= 2 and grid[x - 1][y].type == grid[x - 2][y].type:
					avoid.append(grid[x - 1][y].type)
				if y >= 2 and grid[x][y - 1].type == grid[x][y - 2].type:
					avoid.append(grid[x][y - 1].type)
				var p := _new_piece(x, y, _random_type(avoid), 0, y)
				grid[x][y] = p
		if not _find_move().is_empty():
			break
	# animacja wejścia
	for x in COLS:
		for y in ROWS:
			var node: Node3D = grid[x][y].node
			node.scale = Vector3.ZERO
			create_tween().tween_property(node, "scale", Vector3.ONE, 0.25).set_delay((x + y) * 0.02).set_trans(Tween.TRANS_BACK)

# --------------------------------------------------------------------------------- UI
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
	lbl_level = UiKit.label("POZIOM 1", 24, UiKit.C_YELLOW, 8)
	lbl_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lbl_level)
	var b_lv := _btn("POZIOMY", _open_levels)
	b_lv.custom_minimum_size = Vector2(150, 0)
	top.add_child(b_lv)

	lbl_score = UiKit.label("0", 40, UiKit.C_CYAN, 8)
	lbl_score.position = Vector2(24, 112)
	ui.add_child(lbl_score)
	lbl_moves = UiKit.label("", 24, Color.WHITE, 8)
	lbl_moves.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lbl_moves.offset_left = -250
	lbl_moves.offset_right = -24
	lbl_moves.offset_top = 118
	lbl_moves.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(lbl_moves)
	lbl_target = UiKit.label("", 16, Color("e8c9a0"), 6)
	lbl_target.position = Vector2(24, 176)
	ui.add_child(lbl_target)
	bar_bg = ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.6)
	bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_bg.offset_left = 24
	bar_bg.offset_right = -24
	bar_bg.offset_top = 206
	bar_bg.offset_bottom = 232
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar_bg)
	bar_fill = ColorRect.new()
	bar_fill.color = UiKit.C_GREEN
	bar_fill.position = Vector2(3, 3)
	bar_fill.size = Vector2(0, 20)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar_fill)

	lbl_toast = UiKit.label("", 24, Color.WHITE, 10)
	lbl_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl_toast.offset_top = 260
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
	bottom.offset_top = -120
	bottom.offset_bottom = -24
	bottom.add_theme_constant_override("separation", 10)
	ui.add_child(bottom)
	for k in [["solder", "LUTUJ"], ["shuffle", "MIESZAJ"], ["battery", "+3 RUCHY"]]:
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_button(b, 16, UiKit.C_ORANGE)
		var key: String = k[0]
		b.pressed.connect(func(): _use_booster(key))
		bottom.add_child(b)
		booster_btns[key] = {"btn": b, "name": k[1]}

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
	lbl_level.text = "POZIOM %d" % level
	lbl_score.text = str(score)
	lbl_moves.text = "RUCHY %d" % moves
	lbl_moves.add_theme_color_override("font_color", UiKit.C_MAGENTA if moves <= 3 else Color.WHITE)
	lbl_target.text = "CEL: %d%s" % [target, "  OK!" if goal_reached else ""]
	var full := bar_bg.size.x - 6.0
	bar_fill.size.x = full * clampf(float(score) / float(target), 0.0, 1.0)
	bar_fill.color = UiKit.C_GREEN if goal_reached else UiKit.C_CYAN
	for key in booster_btns:
		var d: Dictionary = booster_btns[key]
		var b: Button = d.btn
		b.text = "%s\nx%d" % [d.name, boosters[key]]
		b.disabled = boosters[key] <= 0 or busy
	var s: Button = booster_btns.solder.btn
	s.add_theme_color_override("font_color", UiKit.C_YELLOW if booster_mode == "solder" else Color.WHITE)

func _process(delta: float) -> void:
	_update_hud()
	for a in arcs:
		(a as Discharger).update(delta)
	hint_ring.rotation.y += delta * 2.0
	if sel != INVALID:
		sel_ring.position = cell_pos(sel.x, sel.y) + Vector3(0, 0.06, 0)
	if not busy and result_panel == null and overlay == null:
		idle_t += delta
		if idle_t > 6.0 and not hint_ring.visible:
			var mv := _find_move()
			if not mv.is_empty():
				hint_ring.position = cell_pos(mv[0].x, mv[0].y) + Vector3(0, 0.06, 0)
				hint_ring.visible = true

# --------------------------------------------------------------------------- sterowanie
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
	match kind:
		"down":
			_on_down(pos)
		"move":
			_on_move(pos)
		"up":
			drag_cell = INVALID

func _world_at(pos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(pos), camera.project_ray_normal(pos))

func _on_down(pos: Vector2) -> void:
	if busy or overlay != null or result_panel != null:
		return
	idle_t = 0.0
	hint_ring.visible = false
	var w = _world_at(pos)
	if w == null:
		return
	var c := Vector2i(roundi(w.x - ox), roundi(w.z - oz))
	if not _in(c):
		return
	if booster_mode == "solder":
		_use_solder(c)
		return
	if sel != INVALID and _adjacent(sel, c):
		var a := sel
		_select(INVALID)
		drag_cell = INVALID
		_try_swap(a, c)
		return
	_select(c)
	drag_cell = c
	Audio.play_sfx("tick", -6.0)

func _on_move(pos: Vector2) -> void:
	if drag_cell == INVALID or busy:
		return
	var w = _world_at(pos)
	if w == null:
		return
	var d: Vector3 = (w as Vector3) - cell_pos(drag_cell.x, drag_cell.y)
	if maxf(absf(d.x), absf(d.z)) < 0.55:
		return
	var dir := Vector2i(signi(roundi(d.x)) if absf(d.x) >= absf(d.z) else 0, signi(roundi(d.z)) if absf(d.z) > absf(d.x) else 0)
	var n := drag_cell + dir
	var a := drag_cell
	drag_cell = INVALID
	_select(INVALID)
	if _in(n) and dir != Vector2i.ZERO:
		_try_swap(a, n)

func _select(c: Vector2i) -> void:
	sel = c
	sel_ring.visible = c != INVALID
	if c != INVALID:
		sel_ring.position = cell_pos(c.x, c.y) + Vector3(0, 0.06, 0)

# --------------------------------------------------------------------- logika ruchu
func _wait(t: float) -> void:
	await get_tree().create_timer(t, false).timeout

func _move_to(p: Dictionary, wp: Vector3, t: float) -> void:
	var node: Node3D = p.node
	create_tween().tween_property(node, "position", wp, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _swap_visual(a: Vector2i, b: Vector2i) -> void:
	_swap_data(a, b)
	var pa = grid[a.x][a.y]
	var pb = grid[b.x][b.y]
	if pa != null:
		_move_to(pa, cell_pos(a.x, a.y), SWAP_T)
	if pb != null:
		_move_to(pb, cell_pos(b.x, b.y), SWAP_T)

func _try_swap(a: Vector2i, b: Vector2i) -> void:
	if busy or moves <= 0 or not _in(a) or not _in(b) or not _adjacent(a, b):
		return
	if grid[a.x][a.y] == null or grid[b.x][b.y] == null:
		return
	busy = true
	idle_t = 0.0
	hint_ring.visible = false
	Audio.play_sfx("swap")
	_swap_visual(a, b)
	await _wait(SWAP_T + 0.02)
	if not is_inside_tree():
		return
	var pa = grid[a.x][a.y]
	var pb = grid[b.x][b.y]
	if pa.special == 3 or pb.special == 3:
		moves -= 1
		await _activate_emp(a, b)
		await _collapse()
		await _resolve([])
		await _after_move()
		return
	var res := _find_matches()
	if res.cells.is_empty():
		_swap_visual(a, b)
		Audio.play_sfx("bad")
		Settings.vibrate(15)
		await _wait(SWAP_T + 0.02)
		busy = false
		return
	moves -= 1
	await _resolve([a, b])
	await _after_move()

func _resolve(swapped: Array) -> void:
	var cascade := 0
	while is_inside_tree():
		var res := _find_matches()
		if res.cells.is_empty():
			break
		cascade += 1
		best_cascade = maxi(best_cascade, cascade)
		await _clear(res, cascade, swapped)
		swapped = []
		await _collapse()

func _pick_cell(g: Dictionary, swapped: Array) -> Vector2i:
	for c in g.cells:
		if swapped.has(c):
			return c
	return g.cells[g.cells.size() / 2]

func _clear(res: Dictionary, cascade: int, swapped: Array) -> void:
	var set: Dictionary = res.cells.duplicate()
	var creations: Array = []
	var taken := {}
	# układy L/T (przecięcie poziomej i pionowej grupy) -> EMP
	var h_cells := {}
	var v_cells := {}
	for g in res.groups:
		for c in g.cells:
			if g.dir == "h":
				h_cells[c] = true
			else:
				v_cells[c] = true
	for c in h_cells:
		if v_cells.has(c) and not taken.has(c):
			taken[c] = true
			creations.append({"cell": c, "special": 3})
	for g in res.groups:
		var n: int = g.cells.size()
		if n < 4:
			continue
		var pc := _pick_cell(g, swapped)
		if taken.has(pc):
			continue
		taken[pc] = true
		if n >= 5:
			creations.append({"cell": pc, "special": 3})
		else:
			creations.append({"cell": pc, "special": 1 if g.dir == "h" else 2})
	for cr in creations:
		set.erase(cr.cell)
	# reakcje łańcuchowe: specjalne elementy w czyszczonym zbiorze
	var queue: Array = set.keys()
	var extra := 0
	var i := 0
	while i < queue.size():
		var c: Vector2i = queue[i]
		i += 1
		var p = grid[c.x][c.y]
		if p == null:
			continue
		if p.special == 1 or p.special == 2:
			extra += 150
			_bolt(c, p.special)
			var line: Array = []
			if p.special == 1:
				for x in COLS:
					line.append(Vector2i(x, c.y))
			else:
				for y in ROWS:
					line.append(Vector2i(c.x, y))
			for lc in line:
				if not set.has(lc) and not taken.has(lc):
					set[lc] = true
					queue.append(lc)
	# tworzenie specjalnych elementów
	for cr in creations:
		var c: Vector2i = cr.cell
		var p = grid[c.x][c.y]
		_convert(p, cr.special)
		fx.sparks(cell_pos(c.x, c.y) + Vector3(0, 0.4, 0), 24, true)
		fx.light_flash(cell_pos(c.x, c.y), Color(1.0, 0.9, 0.4), 2.5)
		if cr.special == 3:
			_reward()
	if not creations.is_empty():
		Audio.play_sfx("special")
		Settings.vibrate(30)
	Audio.play_sfx("match", 0.0, pow(1.0595, [0, 2, 4, 5, 7, 9, 11, 12][mini(cascade - 1, 7)]))
	Settings.vibrate(10 + cascade * 4)
	if cascade >= 2:
		_toast("KOMBO x%d!" % cascade, true)
	await _remove(set, cascade, extra)

func _convert(p: Dictionary, special: int) -> void:
	var old: Node3D = p.node
	var pos := old.position
	old.queue_free()
	p.special = special
	if special == 3:
		p.type = -1
	var node := _make_node(p.type, special)
	node.position = pos
	pieces_root.add_child(node)
	p.node = node
	node.scale = Vector3.ONE * 1.4
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)

func _reward() -> void:
	var keys := ["solder", "shuffle", "battery"]
	var k: String = keys[randi() % 3]
	boosters[k] += 1
	_toast("NAGRODA: %s +1" % booster_btns[k].name, true)

func _remove(cells: Dictionary, cascade: int, extra := 0) -> void:
	var n := 0
	var sum := Vector3.ZERO
	for c in cells:
		var p = grid[c.x][c.y]
		if p == null:
			continue
		grid[c.x][c.y] = null
		n += 1
		var wp := cell_pos(c.x, c.y)
		sum += wp
		fx.sparks(wp + Vector3(0, 0.3, 0), 6)
		var node: Node3D = p.node
		var tw := create_tween().set_parallel(true)
		tw.tween_property(node, "scale", Vector3.ZERO, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_property(node, "rotation:y", 3.0, 0.22)
		tw.chain().tween_callback(node.queue_free)
	if n == 0:
		return
	var pts := roundi((n * 40 + extra) * cascade * (1.0 if types_n <= 5 else 1.7))
	score += pts
	_popup(sum / n, "+%d" % pts)
	await _wait(0.25)

func _collapse() -> void:
	var longest := 0.0
	for x in COLS:
		var write := ROWS - 1
		for y in range(ROWS - 1, -1, -1):
			var p = grid[x][y]
			if p == null:
				continue
			if y != write:
				grid[x][write] = p
				grid[x][y] = null
				p.y = write
				var dur := 0.1 + 0.06 * (write - y)
				longest = maxf(longest, dur)
				var node: Node3D = p.node
				create_tween().tween_property(node, "position", cell_pos(x, write), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			write -= 1
		var missing := write + 1
		for y in range(write, -1, -1):
			var np := _new_piece(x, y, _random_type([]), 0, y - missing)
			grid[x][y] = np
			var dur := 0.1 + 0.06 * missing
			longest = maxf(longest, dur)
			create_tween().tween_property(np.node as Node3D, "position", cell_pos(x, y), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(longest + 0.05)

func _marker(pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	root.add_child(m)
	m.position = pos
	get_tree().create_timer(0.8, false).timeout.connect(m.queue_free)
	return m

func _arc(from: Vector3, to: Vector3, dur := 0.5) -> void:
	if not Settings.effects:
		return
	var d: Discharger = arcs[arc_idx]
	arc_idx = (arc_idx + 1) % arcs.size()
	d.fire(_marker(from), to, dur)

func _bolt(c: Vector2i, special: int) -> void:
	var a := cell_pos(c.x, c.y) + Vector3(0, 0.45, 0)
	var b := a
	var b2 := a
	if special == 1:
		a = cell_pos(0, c.y) + Vector3(0, 0.45, 0)
		b = cell_pos(COLS - 1, c.y) + Vector3(0, 0.45, 0)
	else:
		a = cell_pos(c.x, 0) + Vector3(0, 0.45, 0)
		b = cell_pos(c.x, ROWS - 1) + Vector3(0, 0.45, 0)
	_arc(a, b, 0.45)
	_arc(b, a, 0.45)
	Audio.play_sfx("blast")
	Settings.vibrate(40)
	fx.light_flash((a + b) / 2.0, Color(1.0, 0.9, 0.4), 3.0)
	b2 = b

func _activate_emp(a: Vector2i, b: Vector2i) -> void:
	var pa = grid[a.x][a.y]
	var pb = grid[b.x][b.y]
	var set := {}
	var origin := a if pa.special == 3 else b
	if pa.special == 3 and pb.special == 3:
		for x in COLS:
			for y in ROWS:
				set[Vector2i(x, y)] = true
	else:
		var other = pb if pa.special == 3 else pa
		set[origin] = true
		for x in COLS:
			for y in ROWS:
				var p = grid[x][y]
				if p != null and p.special != 3 and p.type == other.type:
					set[Vector2i(x, y)] = true
	var from := cell_pos(origin.x, origin.y) + Vector3(0, 0.4, 0)
	var k := 0
	for c in set:
		if k < 8 and c != origin:
			_arc(from, cell_pos(c.x, c.y) + Vector3(0, 0.3, 0), 0.5)
			k += 1
	Audio.play_sfx("emp")
	Settings.vibrate(80)
	fx.light_flash(cell_pos(origin.x, origin.y), Color(1.0, 0.5, 0.9), 3.5)
	await _wait(0.3)
	await _remove(set, 1, 200)

func _after_move() -> void:
	if not is_inside_tree():
		return
	if score >= target and not goal_reached:
		goal_reached = true
		_toast("CEL OSIĄGNIĘTY!", true)
		Audio.play_sfx("pu_good")
	if moves <= 0:
		_end_level()
		return
	if _find_move().is_empty():
		await _do_shuffle()
	busy = false

# ---------------------------------------------------------------------- boostery
func _use_booster(key: String) -> void:
	if busy or boosters[key] <= 0 or overlay != null or result_panel != null:
		return
	Audio.play_sfx("click")
	match key:
		"solder":
			booster_mode = "" if booster_mode == "solder" else "solder"
			if booster_mode == "solder":
				_toast("WYBIERZ ELEMENT DO ZLUTOWANIA", true)
		"battery":
			boosters.battery -= 1
			moves += 3
			Audio.play_sfx("booster")
			_toast("+3 RUCHY", true)
		"shuffle":
			boosters.shuffle -= 1
			busy = true
			await _do_shuffle()
			busy = false

func _use_solder(c: Vector2i) -> void:
	booster_mode = ""
	if grid[c.x][c.y] == null:
		return
	boosters.solder -= 1
	busy = true
	Audio.play_sfx("booster")
	await _remove({c: true}, 1)
	await _collapse()
	await _resolve([])
	await _after_move()

func _do_shuffle() -> void:
	Audio.play_sfx("shuffle")
	_toast("MIESZANIE...", true)
	for attempt in 12:
		var kinds: Array = []
		for x in COLS:
			for y in ROWS:
				var p = grid[x][y]
				if p != null and p.special != 3:
					kinds.append(p.type)
		kinds.shuffle()
		var idx := 0
		for x in COLS:
			for y in ROWS:
				var p = grid[x][y]
				if p != null and p.special != 3:
					p.type = kinds[idx]
					idx += 1
		_fix_matches()
		if _find_matches().cells.is_empty() and not _find_move().is_empty():
			break
	for x in COLS:
		for y in ROWS:
			var p = grid[x][y]
			if p != null:
				var old: Node3D = p.node
				var pos := old.position
				old.queue_free()
				var node := _make_node(p.type, p.special)
				node.position = pos
				node.scale = Vector3.ZERO
				pieces_root.add_child(node)
				p.node = node
				create_tween().tween_property(node, "scale", Vector3.ONE, 0.3).set_delay((x + y) * 0.015).set_trans(Tween.TRANS_BACK)
	await _wait(0.6)

## Przelosowuje typy w miejscach dopasowań, aż plansza nie ma żadnej trójki.
func _fix_matches() -> void:
	for pass_i in 60:
		var res := _find_matches()
		if res.cells.is_empty():
			return
		for c in res.cells:
			var p = grid[c.x][c.y]
			if p == null or p.special == 3:
				continue
			var avoid: Array = []
			for d in DIRS4:
				var n: Vector2i = c + d
				if _in(n) and grid[n.x][n.y] != null and grid[n.x][n.y].special != 3:
					avoid.append(grid[n.x][n.y].type)
			p.type = _random_type(avoid)

# ------------------------------------------------------------------ koniec poziomu
func _stars() -> int:
	var r := float(score) / float(target)
	if r >= 2.0:
		return 3
	if r >= 1.5:
		return 2
	if r >= 1.0:
		return 1
	return 0

func _end_level() -> void:
	var win := score >= target
	var st := _stars()
	if win:
		var unlocked := Save.get_int("match3", "unlocked", 1)
		if level >= unlocked:
			Save.set_int("match3", "unlocked", mini(level + 1, MAX_LEVEL))
		if st > Save.get_int("match3", "stars_%d" % level, 0):
			Save.set_int("match3", "stars_%d" % level, st)
		if score > Save.get_int("match3", "best_%d" % level, 0):
			Save.set_int("match3", "best_%d" % level, score)
		Audio.play_sfx("win")
		Settings.vibrate(90)
	else:
		Audio.play_sfx("drain")
		Settings.vibrate(60)
	await _wait(0.5)
	if not is_inside_tree():
		return
	_show_result(win, st)

func _show_result(win: bool, st: int) -> void:
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
	box.offset_top = -300
	box.offset_bottom = 300
	box.add_theme_constant_override("separation", 22)
	result_panel.add_child(box)
	var t := UiKit.label("POZIOM UKOŃCZONY!" if win else "KONIEC RUCHÓW", 32 if win else 40, UiKit.C_GREEN if win else UiKit.C_MAGENTA, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	if win:
		var stars := UiKit.label("GWIAZDKI: " + "*".repeat(st) + "-".repeat(3 - st), 24, UiKit.C_YELLOW, 8)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(stars)
	var s := UiKit.label("WYNIK %d / %d\nNAJWIĘKSZE KOMBO x%d" % [score, target, best_cascade], 16, Color.WHITE, 6)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	if win and level < MAX_LEVEL:
		box.add_child(_panel_btn("DALEJ", UiKit.C_GREEN, func(): _start_level(level + 1)))
	elif win:
		var all := UiKit.label("WSZYSTKIE POZIOMY!", 24, UiKit.C_YELLOW, 8)
		all.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(all)
	box.add_child(_panel_btn("POWTÓRZ", UiKit.C_ORANGE, func(): _start_level(level)))
	box.add_child(_panel_btn("MENU", UiKit.C_CYAN, _go_menu))
	ui.add_child(result_panel)

func _panel_btn(text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 90)
	UiKit.style_button(b, 24, col)
	b.pressed.connect(func():
		Audio.play_sfx("coin")
		cb.call())
	return b

func _open_levels() -> void:
	if overlay or busy:
		return
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
	var unlocked := Save.get_int("match3", "unlocked", 1)
	for i in range(1, MAX_LEVEL + 1):
		var b := Button.new()
		var st := Save.get_int("match3", "stars_%d" % i, 0)
		b.text = "%d\n%s" % [i, "*".repeat(st) if st > 0 else " "]
		b.custom_minimum_size = Vector2(110, 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = i > unlocked
		UiKit.style_button(b, 24, UiKit.C_CYAN)
		b.pressed.connect(func():
			Audio.play_sfx("click")
			_close_overlay()
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
	tw.tween_property(l, "position:z", pos.z - 1.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)

# -------------------------------------------- losowe wyładowania elektrostatyczne
func _schedule_ambient() -> void:
	get_tree().create_timer(randf_range(2.0, 4.5)).timeout.connect(_ambient)

func _ambient() -> void:
	if not busy and Settings.effects and overlay == null and result_panel == null and not grid.is_empty():
		var a := Vector2i(randi() % COLS, randi() % ROWS)
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
		var b: Vector2i = a + dirs[randi() % 4]
		if _in(b):
			var from := cell_pos(a.x, a.y) + Vector3(0, 0.4, 0)
			var to := cell_pos(b.x, b.y) + Vector3(0, 0.4, 0)
			_arc(from, to, 0.25)
			fx.sparks(to, 8)
			Audio.play_sfx("spark", -10.0, randf_range(0.9, 1.3))
	_schedule_ambient()
