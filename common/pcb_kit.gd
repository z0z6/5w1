class_name PcbKit
extends RefCounted
## Wspólny zestaw do budowy gier w stylu "płytka PCB": materiały, części elektroniczne (12 rodzajów),
## scalanie geometrii (1 mesh na materiał), spójne ścieżki, złote magistrale, dekoracje i płytka.
## Użycie: var kit := PcbKit.new(root); kit.begin_part(pos, rot); kit.part(kind, variant); ... kit.flush(root)

const CELL := 1.0
const WALL_H := 0.7
const TRACE_PPU := 44.0     # rozdzielczość tekstury ścieżek [px / jednostkę]
const TRACE_CELL := 5       # rozmiar komórki trasowania [px]
const BUS_PALETTES := [
	[Color(1.0, 0.85, 0.4), Color(1.0, 0.6, 0.15)],
	[Color(1.0, 0.78, 0.3), Color(0.95, 0.5, 0.1)],
	[Color(1.0, 0.9, 0.55), Color(1.0, 0.7, 0.2)],
]

var root: Node3D
var mats := {}
var batches := {}
var spark_spots: Array[Vector3] = []
var bus_mats: Array = []
var _o := Vector3.ZERO
var _rot := 0.0
var _vary := false
var _vc := Vector3.ZERO
var _yaw := 0.0
var _off := Vector3.ZERO
var _tint := Color.WHITE
var _dirt := 0.0

func _init(p_root: Node3D) -> void:
	root = p_root
	_make_materials()

func scl(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)

func mat(color: Color, metallic := 0.0, rough := 0.5, emis := Color.BLACK, emis_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.metallic = metallic
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m

func _scale(c: Color, k: float) -> Color:
	return scl(c, k)

func _mat(color: Color, metallic := 0.0, rough := 0.5, emis := Color.BLACK, emis_e := 0.0) -> StandardMaterial3D:
	return mat(color, metallic, rough, emis, emis_e)

# ------------------------------------------------------------ scalanie geometrii
## Ustawia początek i obrót (wokół Y) dla kolejnych wywołań box/cyl/torus/part.
func begin_part(origin: Vector3, rot_y := 0.0) -> void:
	_o = origin
	_rot = rot_y
	_vary = false

## Włącza losowe zróżnicowanie kolejnych elementów (ziarno z pozycji): drobny obrót i przesunięcie,
## odcień, zabrudzona górna powierzchnia oraz ciemniejsza podstawa (fałszywe AO).
func vary(seed_pos: Vector3) -> void:
	var sx := seed_pos.x * 1.7 + 3.1
	var sz := seed_pos.z * 2.3 + 1.7
	_vc = seed_pos
	_yaw = (_hash2(sx, sz) - 0.5) * 0.09
	_off = Vector3((_hash2(sx + 11.0, sz + 5.0) - 0.5) * 0.05, 0.0, (_hash2(sx + 23.0, sz + 9.0) - 0.5) * 0.05)
	_tint = Color(1.0 + (_hash2(sx + 31.0, sz) - 0.5) * 0.16, 1.0 + (_hash2(sx, sz + 37.0) - 0.5) * 0.12,
		1.0 + (_hash2(sx + 41.0, sz + 43.0) - 0.5) * 0.14)
	_dirt = pow(_hash2(sx + 53.0, sz + 59.0), 1.6)
	_vary = true

func _xf(local: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, _rot)
	var p := _o + b * local
	if _vary:
		var jb := Basis(Vector3.UP, _yaw)
		p = jb * (p - _vc) + _vc + _off
		b = jb * b
	return Transform3D(b, p)

## Dodaje prymityw z kolorami wierzchołków: ciemniejsza podstawa i (czasem) zabrudzona góra.
func _add(m: Material, prim: PrimitiveMesh, local: Vector3) -> void:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ymin := 1e9
	var ymax := -1e9
	for v in verts:
		ymin = minf(ymin, v.y)
		ymax = maxf(ymax, v.y)
	var span := maxf(ymax - ymin, 0.001)
	var cols := PackedColorArray()
	cols.resize(verts.size())
	var ao := 0.6 if _vary else 1.0
	for i in verts.size():
		var k := (verts[i].y - ymin) / span
		var shade := lerpf(ao, 1.0, pow(k, 0.7))
		if _vary and k > 0.92:
			shade *= 1.0 - 0.22 * _dirt           # zabrudzona wierzchnia powierzchnia
		cols[i] = Color(clampf(_tint.r * shade, 0.0, 1.5), clampf(_tint.g * shade, 0.0, 1.5), clampf(_tint.b * shade, 0.0, 1.5))
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_batch(m).append_from(am, 0, _xf(local))

func _batch(m: Material) -> SurfaceTool:
	if not batches.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[m] = st
	return batches[m]

func box(m: Material, size: Vector3, local: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_add(m, bm, local)

func cyl(m: Material, r: float, h: float, local: Vector3, seg := 14) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	_add(m, cm, local)

func torus(m: Material, inner: float, outer: float, local: Vector3) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 20
	tm.ring_segments = 8
	_add(m, tm, local)

## Tworzy po jednym MeshInstance3D na materiał.
func flush(parent: Node3D) -> void:
	for m in batches:
		var st: SurfaceTool = batches[m]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		parent.add_child(mi)
	batches.clear()

## Pełna płytka PCB z teksturą ścieżek (rect_half = połowa rozmiaru obszaru gry; wewnątrz ścieżki wygaszone).
func add_board(board_w: float, board_d: float, rect_half: Vector2, seed_value: int) -> MeshInstance3D:
	var pcb_mat := mats.pcb as ShaderMaterial
	pcb_mat.set_shader_parameter("trace_tex", trace_texture(board_w, board_d, rect_half, seed_value))
	pcb_mat.set_shader_parameter("board_size", Vector2(board_w, board_d))
	pcb_mat.set_shader_parameter("maze_half", rect_half)
	var pcb := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(board_w, 0.2, board_d)
	pcb.mesh = bm
	pcb.position = Vector3(0, -0.1, 0)
	pcb.material_override = pcb_mat
	root.add_child(pcb)
	return pcb

## Włącza / wyłącza animację prądów na magistralach.
func set_effects(on: bool) -> void:
	for m in bus_mats:
		(m as ShaderMaterial).set_shader_parameter("anim", 1.0 if on else 0.0)

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
	# dekale: miękki cień pod elementem i brązowo-żółty ślad topnika
	var shdm := StandardMaterial3D.new()
	shdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shdm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shdm.albedo_color = Color(0, 0, 0, 0.2)
	mats.shadow = shdm
	var flm := StandardMaterial3D.new()
	flm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flm.albedo_color = Color(0.74, 0.54, 0.14, 0.2)
	flm.roughness = 0.35
	flm.metallic = 0.2
	mats.flux = flm
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

# ------------------------------------------------------------------ części
## Cień pod elementem i (u ok. 40% elementów) ślad topnika wokół podstawy.
func _decals(variant: int) -> void:
	var sx := _o.x * 1.3 + variant * 0.7
	var sz := _o.z * 1.9
	var keep_vary := _vary
	_vary = false
	box(mats.shadow, Vector3(1.1, 0.002, 1.1), Vector3(0.03, 0.002, 0.04))
	if _hash2(sx + 7.0, sz + 3.0) < 0.4:
		var r := 0.42 + _hash2(sx + 13.0, sz + 17.0) * 0.28
		cyl(mats.flux, r, 0.002, Vector3((_hash2(sx + 19.0, sz) - 0.5) * 0.3, 0.0045, (_hash2(sx, sz + 29.0) - 0.5) * 0.3), 10)
	_vary = keep_vary

## Element ściany / rzędu (12 rodzajów); pozycje względem begin_part().
func part(kind: int, variant: int) -> void:
	vary(_o)
	_decals(variant)
	match kind:
		0:  # układ DIP z nóżkami
			box(mats.chip, Vector3(0.82, 0.5, 0.94), Vector3(0, 0.25, 0))
			box(mats.chip_mark, Vector3(0.12, 0.02, 0.12), Vector3(-0.25, 0.51, -0.34))
			for i in 5:
				var zz := -0.36 + i * 0.18
				box(mats.silver, Vector3(0.12, 0.05, 0.09), Vector3(-0.46, 0.12, zz))
				box(mats.silver, Vector3(0.12, 0.05, 0.09), Vector3(0.46, 0.12, zz))
		1:  # radiator
			box(mats.alu, Vector3(0.94, 0.12, 0.94), Vector3(0, 0.06, 0))
			for i in 5:
				box(mats.alu, Vector3(0.1, 0.6, 0.9), Vector3(-0.38 + i * 0.19, 0.42, 0))
		2:  # kondensator elektrolityczny (niebieski lub czarny)
			var body_mat: Material = mats.cap_blue if variant % 2 == 0 else mats.cap_black
			cyl(body_mat, 0.45, 0.7, Vector3(0, 0.35, 0), 20)
			cyl(mats.cap_top, 0.4, 0.02, Vector3(0, 0.71, 0), 20)
			box(mats.chip, Vector3(0.5, 0.012, 0.04), Vector3(0, 0.725, 0))
			box(mats.chip, Vector3(0.04, 0.012, 0.5), Vector3(0, 0.725, 0))
		3:  # listwa goldpin
			box(mats.black, Vector3(0.94, 0.45, 0.94), Vector3(0, 0.225, 0))
			for ix in 2:
				for iz in 3:
					cyl(mats.gold, 0.045, 0.2, Vector3(-0.2 + ix * 0.4, 0.55, -0.3 + iz * 0.3), 8)
		4:  # dławik toroidalny (miedziane uzwojenie)
			box(mats.black, Vector3(0.94, 0.08, 0.94), Vector3(0, 0.04, 0))
			torus(mats.copper, 0.17, 0.47, Vector3(0, 0.3, 0))
			torus(mats.copper, 0.17, 0.47, Vector3(0, 0.52, 0))
		5:  # rezonator kwarcowy
			box(mats.black, Vector3(0.94, 0.1, 0.94), Vector3(0, 0.05, 0))
			box(mats.silver, Vector3(0.52, 0.5, 0.86), Vector3(0, 0.35, 0))
			box(mats.chip_mark, Vector3(0.3, 0.01, 0.4), Vector3(0, 0.61, 0))
		6:  # transformator z rdzeniem ferrytowym
			box(mats.ferrite, Vector3(0.92, 0.6, 0.92), Vector3(0, 0.3, 0))
			box(mats.copper, Vector3(0.95, 0.22, 0.6), Vector3(0, 0.34, 0))
			box(mats.gold, Vector3(0.95, 0.04, 0.62), Vector3(0, 0.48, 0))
		7:  # przekaźnik
			box(mats.black, Vector3(0.94, 0.08, 0.94), Vector3(0, 0.04, 0))
			box(mats.relay, Vector3(0.9, 0.58, 0.72), Vector3(0, 0.37, 0))
			box(mats.white, Vector3(0.6, 0.012, 0.4), Vector3(0, 0.67, 0))
		8:  # złącze USB / RJ45
			box(mats.silver, Vector3(0.94, 0.62, 0.94), Vector3(0, 0.31, 0))
			box(mats.black, Vector3(0.7, 0.3, 0.06), Vector3(0, 0.32, 0.46))
			box(mats.gold, Vector3(0.5, 0.04, 0.04), Vector3(0, 0.2, 0.49))
		9:  # wskaźnik LED (pulsuje)
			box(mats.black, Vector3(0.94, 0.2, 0.94), Vector3(0, 0.1, 0))
			cyl(mats.led[variant % 3], 0.3, 0.4, Vector3(0, 0.4, 0), 16)
		10:  # bateria kondensatorów MLCC
			box(mats.black, Vector3(0.94, 0.1, 0.94), Vector3(0, 0.05, 0))
			for ix in 2:
				for iz in 2:
					box(mats.tantal, Vector3(0.36, 0.5, 0.36), Vector3(-0.22 + ix * 0.44, 0.35, -0.22 + iz * 0.44))
		_:  # tranzystor TO-220 z radiatorkiem
			box(mats.alu, Vector3(0.94, 0.1, 0.94), Vector3(0, 0.05, 0))
			box(mats.chip, Vector3(0.6, 0.55, 0.3), Vector3(0, 0.37, 0.1))
			box(mats.silver, Vector3(0.6, 0.7, 0.08), Vector3(0, 0.4, -0.12))
			for i in 3:
				box(mats.silver, Vector3(0.06, 0.1, 0.2), Vector3(-0.2 + i * 0.2, 0.15, 0.4))

func decor_qfp(c: Vector3) -> void:
	box(mats.chip, Vector3(1.5, 0.14, 1.5), c + Vector3(0, 0.07, 0))
	box(mats.chip_mark, Vector3(0.14, 0.015, 0.14), c + Vector3(-0.55, 0.15, -0.55))
	box(mats.silver, Vector3(1.72, 0.04, 0.1), c + Vector3(0, 0.03, 0.8))
	box(mats.silver, Vector3(1.72, 0.04, 0.1), c + Vector3(0, 0.03, -0.8))
	box(mats.silver, Vector3(0.1, 0.04, 1.72), c + Vector3(0.8, 0.03, 0))
	box(mats.silver, Vector3(0.1, 0.04, 1.72), c + Vector3(-0.8, 0.03, 0))
	spark_spots.append(c + Vector3(0, 0.2, 0))

func decor_cap(pos: Vector3, h: float) -> void:
	var m: Material = mats.cap_blue if h < 0.075 else mats.cap_black
	cyl(m, 0.32, 0.32, pos + Vector3(0, 0.16, 0), 16)
	cyl(mats.cap_top, 0.27, 0.02, pos + Vector3(0, 0.33, 0), 16)
	spark_spots.append(pos + Vector3(0, 0.35, 0))

func decor_soic(pos: Vector3) -> void:
	box(mats.chip, Vector3(0.8, 0.12, 0.5), pos + Vector3(0, 0.06, 0))
	box(mats.chip_mark, Vector3(0.08, 0.015, 0.08), pos + Vector3(-0.3, 0.13, -0.15))
	box(mats.silver, Vector3(0.92, 0.03, 0.08), pos + Vector3(0, 0.02, 0.29))
	box(mats.silver, Vector3(0.92, 0.03, 0.08), pos + Vector3(0, 0.02, -0.29))
	spark_spots.append(pos + Vector3(0, 0.15, 0))

## Elementy poza obszarem gry (mw x md = rozmiar obszaru gry; dekoracje wypełniają resztę płytki).
func add_decor(mw: float, md: float, occ: Dictionary, board_w: float, board_d: float) -> void:
	# Elementy poza labiryntem - tylko wizualne, bez kolizji.
	var xm := int(board_w / 2.0)
	var zm := int(board_d / 2.0)
	for gz in range(-zm, zm + 1):
		for gx in range(-xm, xm + 1):
			if occ.has(Vector2i(gx, gz)) or _in_maze(gx, gz, mw, md):
				continue
			var h := _hash2(gx * 1.7 + 3.0, gz * 2.3 + 1.0)
			var pos := Vector3(gx, 0, gz)
			vary(pos)
			if h < 0.05:
				if _free_cells(gx, gz, 2, occ, mw, md, xm, zm):
					_occupy(gx, gz, 2, occ)
					decor_qfp(pos + Vector3(0.5, 0, 0.5))
			elif h < 0.10:
				decor_cap(pos, h)
			elif h < 0.15:
				decor_soic(pos)
			elif h < 0.20:
				box(mats.black, Vector3(0.7, 0.04, 0.95), pos + Vector3(0, 0.02, 0))
				box(mats.silver, Vector3(0.5, 0.16, 0.8), pos + Vector3(0, 0.12, 0))
			elif h < 0.26:
				for i in 3:
					var zz := -0.3 + i * 0.3
					box(mats.resistor, Vector3(0.3, 0.08, 0.18), pos + Vector3(0, 0.05, zz))
					box(mats.silver, Vector3(0.06, 0.09, 0.2), pos + Vector3(-0.17, 0.05, zz))
					box(mats.silver, Vector3(0.06, 0.09, 0.2), pos + Vector3(0.17, 0.05, zz))
			elif h < 0.30:
				box(mats.black, Vector3(0.9, 0.12, 0.9), pos + Vector3(0, 0.06, 0))
				for ix in 2:
					for iz in 2:
						cyl(mats.gold, 0.045, 0.1, pos + Vector3(-0.2 + ix * 0.4, 0.15, -0.2 + iz * 0.4), 8)
			elif h < 0.34:
				box(mats.white, Vector3(0.34, 0.05, 0.22), pos + Vector3(0, 0.025, 0))
				cyl(mats.led[int(h * 100.0) % 3], 0.11, 0.16, pos + Vector3(0, 0.12, 0), 10)
			elif h < 0.38:
				box(mats.tantal, Vector3(0.4, 0.22, 0.56), pos + Vector3(0, 0.11, 0))
				box(mats.chip, Vector3(0.1, 0.225, 0.58), pos + Vector3(-0.15, 0.11, 0))
			elif h < 0.41:
				cyl(mats.gold, 0.2, 0.3, pos + Vector3(0, 0.15, 0), 6)
				cyl(mats.silver, 0.08, 0.02, pos + Vector3(0, 0.31, 0), 8)
			elif h < 0.44:
				box(mats.red_part, Vector3(0.7, 0.2, 0.5), pos + Vector3(0, 0.1, 0))
				box(mats.silver, Vector3(0.08, 0.04, 0.5), pos + Vector3(0.38, 0.04, 0))

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

func _hash2(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)

# ------------------------------------------------------- magistrale i ścieżki
## Magistrala z gniazdem (slotem) przy ścianie. cx = środek, z_wall = oś ściany, side = -1 (w górę) / 1 (w dół).
func add_bus(cx: float, z_wall: float, side: int, wc: int, rng: RandomNumberGenerator, occ: Dictionary, board_d: float) -> void:
	begin_part(Vector3.ZERO, 0.0)
	var z0 := z_wall + side * 1.0                # zewnętrzna krawędź slotu
	var avail := board_d / 2.0 - absf(z0) - 0.3
	if avail < 2.0:
		return
	var length := minf(rng.randf_range(3.0, 11.0), avail)
	var chip := length < avail - 1.2
	var z_end := z0 + side * length
	var half := wc * CELL / 2.0

	# slot (gniazdo) przy ścianie: czarna obudowa, złote styki, zatrzaski, dioda
	box(mats.black, Vector3(wc * CELL - 0.06, 0.2, 0.46), Vector3(cx, 0.1, z_wall + side * 0.73))
	box(mats.gold, Vector3(wc * CELL - 0.3, 0.215, 0.1), Vector3(cx, 0.1075, z_wall + side * 0.9))
	box(mats.silver, Vector3(0.14, 0.24, 0.5), Vector3(cx - half + 0.1, 0.12, z_wall + side * 0.73))
	box(mats.silver, Vector3(0.14, 0.24, 0.5), Vector3(cx + half - 0.1, 0.12, z_wall + side * 0.73))
	cyl(mats.led[rng.randi() % 3], 0.07, 0.1, Vector3(cx, 0.22, z_wall + side * 0.62), 8)
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
	box(mats.ribbon, Vector3(wc * CELL - 0.06, 0.004, length), Vector3(cx, 0.002, z0 + side * length / 2.0))
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
	root.add_child(mi)
	bus_mats.append(m)

	# układ na końcu magistrali
	var tail := 0.0
	if chip:
		var zc := z_end + side * 0.7
		var w := wc * CELL + 0.3
		box(mats.chip, Vector3(w, 0.14, 1.2), Vector3(cx, 0.07, zc))
		box(mats.silver, Vector3(w + 0.2, 0.04, 0.12), Vector3(cx, 0.03, z_end + side * 0.08))
		box(mats.chip_mark, Vector3(0.14, 0.015, 0.14), Vector3(cx - w / 2.0 + 0.2, 0.15, zc - side * 0.4))
		spark_spots.append(Vector3(cx, 0.2, zc))
		tail = 1.4

	# zajęte komórki - dekoracje ich nie nadpiszą
	var za := roundi(minf(z0, z_end + side * tail))
	var zb := roundi(maxf(z0, z_end + side * tail))
	for xc in wc:
		var gx := roundi(cx - (wc - 1) / 2.0 * CELL + xc * CELL)
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

func trace_texture(w_units: float, d_units: float, rect_half: Vector2, seed_value: int) -> ImageTexture:
	var wpx := clampi(int(ceil(w_units * TRACE_PPU)), 64, 4096)
	var hpx := clampi(int(ceil(d_units * TRACE_PPU)), 64, 4096)
	var img := Image.create_empty(wpx, hpx, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var gw := wpx / TRACE_CELL
	var gh := hpx / TRACE_CELL
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var pads: Array[Vector2i] = []
	var nets := int(gw * gh / 160.0)
	var half_x := rect_half.x * TRACE_PPU / TRACE_CELL
	var half_y := rect_half.y * TRACE_PPU / TRACE_CELL
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

