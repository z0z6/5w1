class_name Discharger
extends RefCounted
## Łuk elektryczny (wyładowanie) między dwoma punktami: poszarpana linia z HDR-owych odcinków.

var node: Node3D
var segs: Array = []
var jit: Array = []
var mat: StandardMaterial3D
var time := 0.0
var reroll := 0.0
var src: Node3D
var target := Vector3.ZERO

func _init(parent: Node3D) -> void:
	node = Node3D.new()
	node.visible = false
	parent.add_child(node)
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.5, 2.4, 2.8)
	for i in 7:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.035, 1.0)
		mi.mesh = bm
		mi.material_override = mat
		node.add_child(mi)
		segs.append(mi)
		jit.append(Vector3.ZERO)

## Odpala łuk od węzła `from` do punktu `to` na `duration` sekund.
func fire(from: Node3D, to: Vector3, duration := 0.45) -> void:
	src = from
	target = to
	time = duration
	reroll = 0.0

func update(delta: float) -> void:
	if time <= 0.0 or src == null or not is_instance_valid(src):
		node.visible = false
		return
	time -= delta
	node.visible = true
	if reroll <= 0.0:
		reroll = 0.04
		for i in jit.size():
			jit[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.16
		var c := Fx.rand_color()
		mat.albedo_color = Color(c.r * 2.0 + 0.6, c.g * 2.0 + 0.6, c.b * 2.0 + 0.6)
	reroll -= delta
	var a := src.global_position
	var n := segs.size()
	var prev := a
	for i in n:
		var nxt := a.lerp(target, float(i + 1) / n)
		if i < n - 1:
			nxt += jit[i]
		_place(segs[i], prev, nxt)
		prev = nxt

func _place(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var seg_len := d.length()
	if seg_len < 0.001:
		seg.visible = false
		return
	seg.visible = true
	var dn := d / seg_len
	var up := Vector3.UP if absf(dn.y) < 0.98 else Vector3.RIGHT
	seg.transform = Transform3D(Basis.looking_at(dn, up) * Basis.from_scale(Vector3(1, 1, seg_len)), (a + b) / 2.0)
