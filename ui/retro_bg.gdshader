shader_type canvas_item;
// Retro tło "synthwave": gwiazdy, słońce z pasami, góry, siatka w perspektywie.
// Wszystko pikselowane do niskiej rozdzielczości dla chunky, arcade'owego wyglądu.

uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform float horizon = 0.56;
uniform float dim = 1.0;
uniform float pixels = 150.0;       // liczba "pikseli" na wysokość ekranu

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float asp = rect_size.x / rect_size.y;
	vec2 g = vec2(pixels * asp, pixels);
	vec2 uv = (floor(UV * g) + 0.5) / g;
	vec3 col;

	if (uv.y < horizon) {
		float t = uv.y / horizon;
		col = mix(vec3(0.02, 0.0, 0.10), vec3(0.52, 0.06, 0.48), pow(t, 2.2));

		// gwiazdy (2x2 piksele, migoczą)
		vec2 sg = floor(uv * g / 2.0);
		float h = hash(sg);
		float tw = 0.5 + 0.5 * sin(TIME * (2.0 + h * 4.0) + h * 40.0);
		col += vec3(step(0.985, h) * tw * (1.0 - t));

		// słońce z pasami
		vec2 c = vec2(0.5, horizon - 0.12);
		vec2 d = (uv - c) * vec2(asp, 1.0);
		float R = 0.17;
		float r = length(d);
		col += vec3(1.0, 0.25, 0.6) * 0.30 * exp(-max(r - R, 0.0) * 9.0);
		if (r < R) {
			float local = (uv.y - (c.y - R)) / (2.0 * R);
			bool cut = local > 0.38 && fract(local * 10.0) < (local - 0.33) * 1.2;
			if (!cut) {
				col = mix(vec3(1.0, 0.92, 0.25), vec3(1.0, 0.15, 0.6), local);
			}
		}

		// góry (pikselowa sylwetka z neonowym konturem)
		float ridge = horizon - (0.035 * abs(sin(uv.x * asp * 6.0 + 1.0)) + 0.018 * abs(sin(uv.x * asp * 15.0 + 2.0)) + 0.01);
		if (uv.y > ridge) {
			col = vec3(0.05, 0.0, 0.14);
			if (uv.y < ridge + 1.6 / pixels) {
				col = vec3(0.0, 0.85, 1.0) * 0.8;
			}
		}
	} else {
		float y = uv.y - horizon;
		float z = 0.18 / max(y, 0.001);
		float x = (uv.x - 0.5) * asp * z * 2.2;
		float gx = abs(fract(x + 0.5) - 0.5);
		float gz = abs(fract(z - TIME * 0.7) - 0.5);
		float lx = smoothstep(0.46, 0.5, gx);
		float lz = smoothstep(0.46, 0.5, gz);
		float line = max(lx, lz) * smoothstep(0.0, 0.07, y);
		col = mix(vec3(0.14, 0.0, 0.24), vec3(0.03, 0.0, 0.08), clamp(y * 2.0, 0.0, 1.0));
		col += vec3(0.0, 0.55, 0.85) * exp(-y * 28.0) * 0.5;
		col = mix(col, vec3(1.0, 0.2, 0.85), line * 0.9);
	}
	COLOR = vec4(col * dim, 1.0);
}
