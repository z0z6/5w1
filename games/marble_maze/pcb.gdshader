shader_type spatial;
// Proceduralna płytka PCB: maska lutownicza + ścieżki miedziane + pady
// + kolorowe impulsy prądu płynące po ścieżkach (uniform anim = 0 wyłącza).

uniform vec3 mask_color : source_color = vec3(0.02, 0.27, 0.14);
uniform vec3 copper : source_color = vec3(0.86, 0.55, 0.30);
uniform float anim = 1.0;

varying vec3 lpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec2 p = lpos.xz * 2.0;           // siatka pół-komórkowa
	vec2 cell = floor(p);
	vec2 f = fract(p);

	// Ścieżki: długie odcinki poziome / pionowe
	float hr = hash(vec2(cell.y, floor(cell.x / 5.0)));
	float hc = hash(vec2(cell.x + 100.0, floor(cell.y / 5.0)));
	float tr_h = step(hr, 0.28) * step(abs(f.y - 0.5), 0.08);
	float tr_v = step(hc, 0.28) * step(abs(f.x - 0.5), 0.08);
	float trace = max(tr_h, tr_v);

	// Pady / przelotki
	float pad = step(0.90, hash(cell + 7.3)) * step(length(f - 0.5), 0.26);
	float hole = step(length(f - 0.5), 0.09) * pad;

	float grain = 0.85 + 0.15 * hash(floor(lpos.xz * 14.0));
	vec3 col = mask_color * grain;
	col = mix(col, col * 1.7 + vec3(0.0, 0.04, 0.02), trace);   // ścieżka pod maską
	col = mix(col, copper, pad);
	col = mix(col, vec3(0.02), hole);

	// Płynący prąd: "kometa" z ostrym czołem i ogonem, kierunek zależny od odcinka
	float dir_h = hr > 0.14 ? 1.0 : -1.0;
	float dir_v = hc > 0.14 ? 1.0 : -1.0;
	float ph_h = fract(lpos.x * 0.30 * dir_h - TIME * 0.45 + hr * 7.0);
	float ph_v = fract(lpos.z * 0.30 * dir_v - TIME * 0.45 + hc * 7.0);
	float pulse_h = smoothstep(0.0, 0.03, ph_h) * (1.0 - smoothstep(0.03, 0.22, ph_h));
	float pulse_v = smoothstep(0.0, 0.03, ph_v) * (1.0 - smoothstep(0.03, 0.22, ph_v));
	vec3 glow = hue(hr * 3.5) * tr_h * pulse_h + hue(hc * 3.5 + 0.3) * tr_v * pulse_v;

	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.3, pad);
	METALLIC = pad * 0.9;
	SPECULAR = 0.35;
	EMISSION = glow * 2.6 * anim;
}
