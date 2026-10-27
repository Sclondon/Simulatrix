shader_type canvas_item;
// Voronoi cells: every pixel looks for the nearest of the drifting seeds round it (F1) and the
// second nearest (F2). F1 picks the cell's colour; where F2 - F1 is small, we're on an edge.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Cells;
uniform float scale : hint_range(2.0, 30.0) = 8.0;
uniform float jitter : hint_range(0.0, 1.0) = 0.9;
uniform float speed : hint_range(0.0, 3.0) = 0.6;
group_uniforms Look;
uniform float edge_width : hint_range(0.0, 0.3) = 0.06;
uniform vec3 edge_color : source_color = vec3(0.05, 0.05, 0.08);
uniform float color_amount : hint_range(0.0, 1.0) = 0.8;
uniform bool show_distance = false;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 aspect = vec2(resolution.x / resolution.y, 1.0);
	vec2 p = UV * aspect * scale;
	vec2 m = mouse * aspect * scale;
	vec2 cell = floor(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 h = hash2(c);
			vec2 seed = c + 0.5 + 0.5 * sin(TIME * speed + 6.28318 * h) * jitter;
			float d = length(p - seed);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				id = c;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	vec2 h = hash2(id);
	vec3 col = 0.5 + 0.5 * cos(6.28318 * (h.x + vec3(0.0, 0.33, 0.67)));
	col = mix(vec3(0.5), col, color_amount) * (0.75 + 0.25 * h.y);
	if (show_distance) {
		col = vec3(f1);
	}
	col = mix(edge_color, col, smoothstep(edge_width, edge_width + 0.03, f2 - f1));
	col += vec3(0.25, 0.3, 0.4) * exp(-length(p - m) * 1.5); // a glow under your finger
	COLOR = vec4(col, 1.0);
}
