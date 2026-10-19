shader_type spatial;
// Proceduralna płytka PCB: maska lutownicza + ścieżki miedziane + pady.

uniform vec3 mask_color : source_color = vec3(0.02, 0.27, 0.14);
uniform vec3 copper : source_color = vec3(0.86, 0.55, 0.30);

varying vec3 lpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

	ALBEDO = col;
	ROUGHNESS = mix(0.32, 0.28, pad);
	METALLIC = pad * 0.9;
	SPECULAR = 0.7;
}
