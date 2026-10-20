shader_type canvas_item;
// Nakładka CRT: linie skanowania, winieta, delikatne migotanie.

uniform float scan = 0.20;
uniform float vig = 0.55;

void fragment() {
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159 * 0.66);
	float v = smoothstep(0.35, 0.95, length(UV - 0.5) * 1.25);
	float flicker = 0.97 + 0.03 * sin(TIME * 60.0);
	float a = (scan * line + vig * v * 0.6) * flicker;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 0.8));
}
