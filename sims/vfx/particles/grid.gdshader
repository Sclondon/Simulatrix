shader_type spatial;
// The editor floor: a lit grey plane with metre lines, every fifth one stronger,
// the X axis red and the Z axis blue, fading out with distance.

uniform vec3 base : source_color = vec3(0.16, 0.16, 0.17);
uniform vec3 line_color : source_color = vec3(0.30, 0.30, 0.33);
uniform float fade_distance = 22.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float step_size) {
	vec2 q = p / step_size;
	vec2 w = fwidth(q);
	vec2 g = abs(fract(q - 0.5) - 0.5) / max(w, vec2(1e-4));
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	float minor = grid(p, 1.0);
	float major = grid(p, 5.0);
	vec3 col = base;
	col = mix(col, line_color, minor * 0.55);
	col = mix(col, line_color * 1.35, major * 0.8);
	vec2 w = fwidth(p);
	float ax = 1.0 - clamp(abs(p.y) / max(w.y, 1e-4), 0.0, 1.0);
	float az = 1.0 - clamp(abs(p.x) / max(w.x, 1e-4), 0.0, 1.0);
	col = mix(col, vec3(0.62, 0.22, 0.22), ax);
	col = mix(col, vec3(0.22, 0.36, 0.66), az);
	float d = length(p);
	col = mix(col, base * 0.8, smoothstep(fade_distance * 0.4, fade_distance, d));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}
