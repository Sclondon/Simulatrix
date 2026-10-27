// An editor's ground grid: metre lines, a heavier line every five, the axes tinted, fading out with distance.
shader_type spatial;
render_mode unshaded;

uniform vec3 floor_color : source_color = vec3(0.16, 0.17, 0.18);
uniform vec3 line_color : source_color = vec3(0.3, 0.31, 0.33);
uniform vec3 major_color : source_color = vec3(0.42, 0.43, 0.46);
uniform vec3 fog_color : source_color = vec3(0.55, 0.6, 0.66);
uniform float fade = 70.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float step_size) {
	vec2 g = abs(fract(p / step_size - 0.5) - 0.5) / fwidth(p / step_size);
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 c = floor_color;
	c = mix(c, line_color, grid(p, 1.0) * 0.8);
	c = mix(c, major_color, grid(p, 5.0));
	vec2 axis = 1.0 - clamp(abs(p) / fwidth(p) * 0.6, 0.0, 1.0);
	c = mix(c, vec3(0.75, 0.25, 0.25), axis.y);
	c = mix(c, vec3(0.25, 0.4, 0.8), axis.x);
	float d = length(world_pos - CAMERA_POSITION_WORLD);
	ALBEDO = mix(c, fog_color, smoothstep(fade * 0.3, fade, d));
}
