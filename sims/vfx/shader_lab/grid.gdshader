shader_type spatial;
// Shader Lab's floor: a fading editor grid, a line every metre and a stronger one every four.
uniform vec3 base_color : source_color = vec3(0.15, 0.16, 0.18);
uniform vec3 line_color : source_color = vec3(0.34, 0.36, 0.41);
varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(wp.xz - 0.5) - 0.5) / fwidth(wp.xz);
	float fine = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 q = wp.xz * 0.25;
	vec2 g4 = abs(fract(q - 0.5) - 0.5) / fwidth(q);
	float coarse = 1.0 - min(min(g4.x, g4.y), 1.0);
	float fade = 1.0 - smoothstep(4.0, 14.0, length(wp.xz));
	ALBEDO = mix(base_color, line_color, max(fine * 0.45, coarse) * fade);
	ROUGHNESS = 0.9;
}
