shader_type canvas_item;
// Starfield tunnel: polar coordinates turn the screen into a tube (distance from the centre
// becomes depth, the angle goes round the wall), and layers of stars rush outward past you.
// Steer with your finger.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Flight;
uniform float speed : hint_range(0.0, 4.0) = 1.0;
uniform float twist : hint_range(-2.0, 2.0) = 0.3;
uniform float tunnel : hint_range(0.0, 1.0) = 0.6;
group_uniforms Stars;
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform vec3 tube_color : source_color = vec3(0.3, 0.2, 0.9);
uniform vec3 star_color : source_color = vec3(1.0, 0.95, 0.85);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(resolution.x / resolution.y, 1.0);
	p -= (mouse - 0.5) * 0.6;
	float r = length(p);
	float a = atan(p.y, p.x);
	float z = 0.25 / max(r, 0.001) + TIME * speed;
	float rings = smoothstep(0.4, 0.6, 0.5 + 0.5 * sin(z * 6.28318));
	float spokes = smoothstep(0.45, 0.55, 0.5 + 0.5 * sin(a * 8.0 + twist * z * 2.0));
	float fade = smoothstep(0.02, 0.5, r); // the far end is dark
	vec3 col = tube_color * (rings * 0.6 + spokes * 0.4) * fade * tunnel;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float depth = fract(TIME * speed * 0.15 + fi * 0.25);
		vec2 q = p * mix(12.0, 0.6, depth) + vec2(fi * 7.3, fi * 3.1);
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		if (hash(cell + fi * 11.0) < density) {
			vec2 off = vec2(hash(cell + 1.7), hash(cell + 4.3)) - 0.5;
			float b = 1.0 - smoothstep(0.0, 0.07, length(f - off * 0.7));
			col += star_color * b * depth * (1.0 - depth) * 4.0;
		}
	}
	COLOR = vec4(col, 1.0);
}
