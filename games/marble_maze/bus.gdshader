shader_type spatial;
render_mode cull_disabled;
// Magistrala: wiązka równoległych miedzianych ścieżek z szybko płynącymi impulsami.
// UV.x = odległość wzdłuż ścieżki (w jednostkach świata), UV.y = numer ścieżki w wiązce.
// Każda ścieżka ma własną prędkość, gęstość pakietów i natężenie (różna jasność).

uniform vec3 color_a : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 color_b : source_color = vec3(0.2, 0.4, 1.0);
uniform vec3 copper_color : source_color = vec3(0.5, 0.3, 0.15);
uniform float speed = 4.0;
uniform float intensity = 1.0;
uniform float dir = 1.0;
uniform float anim = 1.0;

float hash(float n) {
	return fract(sin(n * 91.345 + 3.17) * 47453.5453);
}

void fragment() {
	float lane = floor(UV.y);
	float h = hash(lane + 1.0);
	float h2 = hash(lane + 17.0);
	float across = abs(fract(UV.y) - 0.5) * 2.0;     // 0 = środek, 1 = brzeg
	float core = 1.0 - smoothstep(0.35, 1.0, across);

	float x = UV.x * dir;
	float sp = speed * (0.6 + 1.2 * h);

	// Wolniejsze, długie pakiety z ogonem
	float ph = fract(x * (0.18 + 0.25 * h2) - TIME * sp * 0.25 + h * 9.0);
	float pk = smoothstep(0.0, 0.02, ph) * (1.0 - smoothstep(0.02, 0.10 + 0.25 * h2, ph));
	// Szybkie, krótkie błyski
	float ph2 = fract(x * 0.55 - TIME * sp * 0.65 + h2 * 5.0);
	float pk2 = smoothstep(0.0, 0.01, ph2) * (1.0 - smoothstep(0.01, 0.07, ph2));
	// Wahania natężenia ("przepięcia")
	float surge = 0.6 + 0.4 * sin(TIME * (1.0 + 2.0 * h) + h2 * 6.283);
	float lane_int = intensity * (0.35 + 0.65 * h2) * surge;

	vec3 c = mix(color_a, color_b, h);
	vec3 glow = c * pk * 1.4 + mix(c, vec3(1.0), 0.5) * pk2 * 2.2 + c * 0.08;

	ALBEDO = copper_color;
	METALLIC = 0.85;
	ROUGHNESS = 0.35;
	EMISSION = glow * lane_int * core * anim;
}
