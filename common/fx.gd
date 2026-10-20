class_name Fx
extends RefCounted
## Wspólne efekty świetlne: iskry (cząsteczki) i błyski światła. Respektuje Settings.effects.

var host: Node3D                 # węzeł, na którym działają animacje i światła
var spark_parent: Node3D         # tu trafiają cząsteczki (np. korzeń poziomu)
var spark_mesh: SphereMesh
var spark_grad: Gradient
var spark_curve: Curve
var lights: Array[OmniLight3D] = []
var idx := 0

func _init(p_host: Node3D, spark_mat: Material) -> void:
	host = p_host
	spark_parent = p_host
	spark_mesh = SphereMesh.new()
	spark_mesh.radius = 0.055
	spark_mesh.height = 0.11
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	spark_mesh.material = spark_mat
	spark_grad = Gradient.new()
	spark_grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	spark_grad.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	spark_grad.colors = PackedColorArray([
		Color(0.3, 0.9, 1.0), Color(1.0, 0.9, 0.3), Color(1.0, 0.3, 0.9),
		Color(1.0, 1.0, 1.0), Color(1.0, 0.5, 0.15)])
	spark_curve = Curve.new()
	spark_curve.add_point(Vector2(0, 1))
	spark_curve.add_point(Vector2(1, 0))
	for i in 2:
		var l := OmniLight3D.new()
		l.omni_range = 4.0
		l.light_energy = 0.0
		host.add_child(l)
		lights.append(l)

static func rand_color() -> Color:
	return Color.from_hsv(randf(), 0.55, 1.0)

func sparks(pos: Vector3, amount := 20, big := false) -> void:
	if not Settings.effects or spark_parent == null:
		return
	var p := CPUParticles3D.new()
	p.mesh = spark_mesh
	p.amount = int(amount * 1.5)
	p.lifetime = 1.3 if big else 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0 if big else 75.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 7.5 if big else 5.5
	p.gravity = Vector3(0, -5, 0)
	p.scale_amount_curve = spark_curve
	p.color_initial_ramp = spark_grad
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.06
	spark_parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

func light_flash(pos: Vector3, color: Color, energy := 2.5) -> void:
	if not Settings.effects:
		return
	var l := lights[idx]
	idx = (idx + 1) % lights.size()
	l.global_position = pos + Vector3(0, 0.6, 0)
	l.light_color = color
	l.light_energy = energy * 1.4
	var tw := host.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.5)

## Pulsowanie diod LED (współdzielone materiały).
func pulse_leds(led_mats: Array) -> void:
	var i := 0
	for m in led_mats:
		var tw := host.create_tween().set_loops()
		var t := 0.6 + i * 0.3
		tw.tween_property(m, "emission_energy_multiplier", 4.5, t)
		tw.tween_property(m, "emission_energy_multiplier", 0.3, t)
		i += 1
