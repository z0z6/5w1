shader_type spatial;
render_mode cull_disabled;
// Magistrala: wiązka delikatnych, złotych przewodów z falującymi prądami.
// UV.x = odległość wzdłuż przewodu (jednostki świata), UV.y = numer przewodu w wiązce.
// Fale przesunięte w fazie między sąsiednimi przewodami -> po wiązce "przelewa się" łagodna fala.

uniform vec3 gold : source_color = vec3(1.0, 0.72, 0.22);
uniform vec3 glow_a : source_color = vec3(1.0, 0.85, 0.4);
uniform vec3 glow_b : source_color = vec3(1.0, 0.6, 0.15);
uniform float speed = 1.6;
uniform float intensity = 0.8;
uniform float dir = 1.0;
uniform float anim = 1.0;

float hash(float n) {
	return fract(sin(n * 91.345 + 3.17) * 47453.5453);
}

void fragment() {
	float lane = floor(UV.y);
	float h = hash(lane + 1.0);
	float h2 = hash(lane + 17.0);
	float across = abs(fract(UV.y) - 0.5) * 2.0;           // 0 = środek, 1 = brzeg
	float edge = 1.0 - smoothstep(0.55, 1.0, across);

	float x = UV.x * dir;
	// dwie łagodne fale: długa (wolna) i krótsza (szybsza), z przesunięciem fazy między przewodami
	float w1 = 0.5 + 0.5 * sin(x * (0.8 + 0.3 * h) - TIME * speed + lane * 0.35 + h * 6.283);
	float w2 = 0.5 + 0.5 * sin(x * (2.1 + 0.8 * h2) - TIME * speed * 1.7 + lane * 0.6);
	float wave = pow(w1, 2.0) * 0.7 + pow(w2, 4.0) * 0.3;
	vec3 c = mix(glow_a, glow_b, h);

	ALBEDO = gold;
	METALLIC = 0.4;
	ROUGHNESS = 0.3;
	// stały, ciepły połysk złota + delikatna fala prądu (wyłączana przez anim)
	EMISSION = gold * 0.20 * edge + c * wave * intensity * (0.4 + 0.6 * h2) * edge * 0.9 * anim;
}
