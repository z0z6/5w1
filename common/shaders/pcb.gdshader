shader_type spatial;
// Płytka PCB: maska lutownicza + spójne ścieżki miedziane z tekstury trasowania
// (R = ścieżka, G = pad, B = otwór w padzie) + "życie": plamy maski, ślady topnika przy padach,
// zabrudzenia i rysy. Animowane prądy są na magistralach (bus.gdshader).

uniform vec3 mask_color : source_color = vec3(0.02, 0.27, 0.14);
uniform vec3 copper : source_color = vec3(0.86, 0.55, 0.30);
uniform sampler2D trace_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 board_size = vec2(16.0, 32.0);
uniform vec2 maze_half = vec2(6.0, 8.0);     // połowa rozmiaru obszaru gry z ramką
uniform vec2 scroll = vec2(0.0);             // przesunięcie wzoru (gry ze scrollem)
uniform float wear = 1.0;                    // 0 = czysta płytka, 1 = zużyta

varying vec3 lpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec2 w = lpos.xz + scroll;
	vec2 uv = w / board_size + 0.5;
	vec3 m = texture(trace_tex, uv).rgb;
	// wewnątrz obszaru gry ścieżki, pady i otwory są mocno wygaszone (czytelność gry)
	float inmaze = step(abs(lpos.x), maze_half.x) * step(abs(lpos.z), maze_half.y);
	float trace = m.r * (1.0 - m.g) * mix(1.0, 0.35, inmaze);
	float pad = m.g * mix(1.0, 0.45, inmaze);
	float hole = m.b * mix(1.0, 0.45, inmaze);

	float grain = 0.85 + 0.15 * hash(floor(w * 14.0));
	vec3 col = mask_color * grain;
	// niskoczęstotliwościowe plamy: maska nie jest idealnie równa
	float lowf = fbm(w * 0.33);
	col *= 1.0 + (lowf - 0.5) * 0.3 * wear;
	col = mix(col, vec3(0.06, 0.36, 0.19) * grain, trace * 0.8);
	col = mix(col, copper, pad);
	col = mix(col, vec3(0.02), hole);

	// ślady topnika: brązowo-żółty nalot, mocniejszy wokół padów (rozmyta mipmapa kanału G)
	float pad_blur = textureLod(trace_tex, uv, 3.0).g;
	float flux_n = fbm(w * 1.6 + 7.0);
	float flux = smoothstep(0.5, 0.78, flux_n) * (0.22 + 1.5 * pad_blur) * wear;
	flux = clamp(flux, 0.0, 1.0) * (1.0 - 0.6 * inmaze);
	col = mix(col, vec3(0.50, 0.36, 0.10), flux * 0.42);

	// zabrudzenia i drobne rysy
	float dirt = smoothstep(0.6, 0.86, fbm(w * 2.9 + 19.0)) * wear;
	col *= 1.0 - 0.32 * dirt;
	vec2 q = vec2(w.x * 0.8 + w.y * 0.6, -w.x * 0.6 + w.y * 0.8);
	float scr_row = floor(q.y * 3.0);
	float scr = step(0.93, hash(vec2(scr_row, 4.0))) * smoothstep(0.012, 0.0, abs(fract(q.y * 3.0) - 0.5)) * step(0.55, vnoise(vec2(q.x * 0.9, scr_row)));
	col += vec3(0.07, 0.09, 0.08) * scr * wear;

	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.3, pad) + flux * 0.25 + dirt * 0.2;
	METALLIC = pad * 0.9;
	SPECULAR = 0.35;
}
