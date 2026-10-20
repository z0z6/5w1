shader_type spatial;
// Fluorescencyjna, silnie naelektryzowana kulka: świecąca powłoka + gęste migoczące
// ładunki + trzaskająca korona na obrzeżu. charge (0..1) - poziom naładowania, flash - błysk po wyładowaniu.

uniform vec3 body_color : source_color = vec3(0.1, 0.85, 1.0);
uniform float charge = 0.3;
uniform float flash = 0.0;

varying vec3 onorm;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	onorm = NORMAL;
}

void fragment() {
	vec3 n = normalize(onorm);
	vec3 sparks = vec3(0.0);
	// cztery warstwy "ładunków": różna gęstość i tempo migotania
	for (int i = 0; i < 4; i++) {
		float dens = 5.0 + float(i) * 3.5;
		float rate = 6.0 + float(i) * 5.0;
		vec3 q = n * dens;
		vec3 id = floor(q);
		vec3 f = fract(q) - 0.5;
		float st = floor(TIME * rate + float(i) * 3.7);
		float h = hash3(id + vec3(st * 0.37, st * 0.11, float(i)));
		float on = step(1.0 - (0.06 + 0.18 * charge), h);
		float dotv = on * smoothstep(0.42, 0.03, length(f));
		vec3 c = mix(vec3(0.6, 1.0, 1.0), vec3(1.0, 0.55, 1.0), fract(h * 7.0));
		sparks += c * dotv;
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float breathe = 0.85 + 0.15 * sin(TIME * 3.0 + n.y * 4.0);
	// całe ciało rozbłyskuje w nieregularnych odstępach
	float fl = 1.0 + 0.35 * step(0.9, hash3(vec3(floor(TIME * 18.0), 1.0, 2.0)));

	ALBEDO = body_color * 0.25;
	METALLIC = 0.4;
	ROUGHNESS = 0.2;
	EMISSION = body_color * breathe * fl * (0.9 + charge * 0.7)
		+ body_color * fres * (1.8 + 0.8 * charge * sin(TIME * 35.0))
		+ sparks * (2.0 + 2.2 * charge)
		+ body_color * flash * 1.6;
}
