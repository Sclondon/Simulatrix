shader_type canvas_item;
// The electric potential of up to twelve charges: red where it's high, blue
// where it's low, near-black where it's level, with thin contour lines.

uniform vec2 size = vec2(720.0);
uniform int count = 0;
uniform vec4 charges[12]; // xy position, z charge

void fragment() {
	vec2 p = UV * size;
	float v = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= count) break;
		v += charges[i].z / sqrt(dot(p - charges[i].xy, p - charges[i].xy) + 400.0);
	}
	v *= 60.0;
	float s = clamp(abs(v) / 3.0, 0.0, 1.0);
	vec3 base = vec3(0.04, 0.045, 0.07);
	vec3 hot = vec3(0.65, 0.12, 0.14);
	vec3 cold = vec3(0.1, 0.22, 0.65);
	vec3 col = mix(base, v > 0.0 ? hot : cold, pow(s, 0.7));
	// Equipotential contours, evenly spaced in potential
	float band = abs(fract(v * 2.0 + 0.5) - 0.5);
	float w = fwidth(v * 2.0);
	col += vec3(0.25) * (1.0 - smoothstep(0.0, w * 1.5, band)) * (0.25 + 0.75 * (1.0 - s));
	COLOR = vec4(col, 1.0);
}
