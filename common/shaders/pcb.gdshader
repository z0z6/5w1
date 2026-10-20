shader_type spatial;
// Płytka PCB: maska lutownicza + spójne ścieżki miedziane z tekstury trasowania
// (R = ścieżka, G = pad, B = otwór w padzie). Animowane prądy są na magistralach (bus.gdshader).

uniform vec3 mask_color : source_color = vec3(0.02, 0.27, 0.14);
uniform vec3 copper : source_color = vec3(0.86, 0.55, 0.30);
uniform sampler2D trace_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 board_size = vec2(16.0, 32.0);
uniform vec2 maze_half = vec2(6.0, 8.0);     // połowa rozmiaru labiryntu z ramką

varying vec3 lpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec2 uv = lpos.xz / board_size + 0.5;
	vec3 m = texture(trace_tex, uv).rgb;
	// wewnątrz labiryntu ścieżki, pady i otwory są mocno wygaszone (czytelność gry)
	float inmaze = step(abs(lpos.x), maze_half.x) * step(abs(lpos.z), maze_half.y);
	float trace = m.r * (1.0 - m.g) * mix(1.0, 0.35, inmaze);
	float pad = m.g * mix(1.0, 0.45, inmaze);
	float hole = m.b * mix(1.0, 0.45, inmaze);

	float grain = 0.85 + 0.15 * hash(floor(lpos.xz * 14.0));
	vec3 col = mask_color * grain;
	col = mix(col, vec3(0.06, 0.36, 0.19) * grain, trace * 0.8);   // ścieżka pod maską
	col = mix(col, copper, pad);
	col = mix(col, vec3(0.02), hole);

	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.3, pad);
	METALLIC = pad * 0.9;
	SPECULAR = 0.35;
}
