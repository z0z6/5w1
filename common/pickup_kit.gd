class_name PickupKit
extends RefCounted
## Wspólne pickupy (power-upy) dla wszystkich gier.

## Pickup (power-up) w stylu płytki: podstawka (zielona = pomaga, czerwona = przeszkadza) + obracający się element.
static func build(kit: PcbKit, type: String, pos: Vector3, col: Color, good: bool) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	# podstawka: zielona = pomaga, czerwona = przeszkadza
	var ring_col := Color(0.2, 1.0, 0.4) if good else Color(1.0, 0.15, 0.1)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.26
	rm.outer_radius = 0.36
	rm.rings = 20
	rm.ring_segments = 8
	ring.mesh = rm
	ring.material_override = kit.mat(kit.scl(ring_col, 0.3), 0.0, 0.4, ring_col, 2.5)
	ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)
	var body := Node3D.new()
	body.name = "Body"
	body.position = Vector3(0, 0.38, 0)
	root.add_child(body)
	var mat := kit.mat(kit.scl(col, 0.4), 0.2, 0.3, col, 2.2)
	match type:
		"jumper":
			_pm(body, _bm(Vector3(0.36, 0.16, 0.16)), mat, Vector3.ZERO)
			_pm(body, _bm(Vector3(0.08, 0.12, 0.08)), kit.mats.black, Vector3(-0.1, -0.12, 0))
			_pm(body, _bm(Vector3(0.08, 0.12, 0.08)), kit.mats.black, Vector3(0.1, -0.12, 0))
		"insul":
			var sm := SphereMesh.new()
			sm.radius = 0.17
			sm.height = 0.34
			_pm(body, sm, mat, Vector3.ZERO)
		"heat":
			for i in 3:
				_pm(body, _bm(Vector3(0.38, 0.05, 0.38)), mat, Vector3(0, -0.1 + i * 0.1, 0))
		"scan":
			var tm := TorusMesh.new()
			tm.inner_radius = 0.1
			tm.outer_radius = 0.2
			tm.rings = 20
			tm.ring_segments = 8
			_pm(body, tm, mat, Vector3.ZERO)
		"batt":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.12
			cm.bottom_radius = 0.12
			cm.height = 0.3
			cm.radial_segments = 12
			_pm(body, cm, mat, Vector3.ZERO)
			_pm(body, _bm(Vector3(0.1, 0.05, 0.1)), kit.mats.silver, Vector3(0, 0.17, 0))
		"surge":
			var pm := CylinderMesh.new()
			pm.top_radius = 0.22
			pm.bottom_radius = 0.22
			pm.height = 0.3
			pm.radial_segments = 3
			_pm(body, pm, mat, Vector3.ZERO)
		"rev":
			var dm := CylinderMesh.new()
			dm.top_radius = 0.24
			dm.bottom_radius = 0.24
			dm.height = 0.12
			dm.radial_segments = 4
			_pm(body, dm, mat, Vector3.ZERO)
		"emi":
			for i in 3:
				var sm2 := SphereMesh.new()
				sm2.radius = 0.08
				sm2.height = 0.16
				_pm(body, sm2, mat, Vector3(cos(i * TAU / 3.0) * 0.14, 0, sin(i * TAU / 3.0) * 0.14))
		"multi":
			for i in 3:
				var sm4 := SphereMesh.new()
				sm4.radius = 0.1
				sm4.height = 0.2
				_pm(body, sm4, mat, Vector3(cos(i * TAU / 3.0 + 0.5) * 0.17, 0, sin(i * TAU / 3.0 + 0.5) * 0.17))
		"x2":
			var lbl := Label3D.new()
			lbl.text = "x2"
			lbl.font_size = 96
			lbl.pixel_size = 0.0055
			lbl.modulate = col
			lbl.outline_size = 12
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			body.add_child(lbl)
		"big":
			_pm(body, _bm(Vector3(0.5, 0.1, 0.14)), mat, Vector3.ZERO)
			_pm(body, _bm(Vector3(0.18, 0.1, 0.18)), kit.mats.silver, Vector3(-0.2, 0, 0))
		"small":
			_pm(body, _bm(Vector3(0.24, 0.1, 0.14)), mat, Vector3.ZERO)
			_pm(body, _bm(Vector3(0.14, 0.1, 0.14)), kit.mats.silver, Vector3(-0.1, 0, 0))
		"swap":
			var dm2 := CylinderMesh.new()
			dm2.top_radius = 0.24
			dm2.bottom_radius = 0.24
			dm2.height = 0.12
			dm2.radial_segments = 4
			_pm(body, dm2, mat, Vector3.ZERO)
			_pm(body, _bm(Vector3(0.36, 0.06, 0.06)), kit.mats.silver, Vector3.ZERO)
		_:  # mina
			var sm3 := SphereMesh.new()
			sm3.radius = 0.15
			sm3.height = 0.3
			_pm(body, sm3, mat, Vector3.ZERO)
			for ax in 3:
				var sz := Vector3(0.5, 0.05, 0.05)
				var sp := _pm(body, _bm(sz), mat, Vector3.ZERO)
				sp.rotation = [Vector3(0, 0, 0), Vector3(0, PI / 2, 0), Vector3(0, 0, PI / 2)][ax]
	return root

static func _bm(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

static func _pm(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
