shader_type canvas_item;
// Matrix rain: the screen is a grid of glyph cells. Each column has a falling head with a
// fading tail; glyphs are 3x5 dot patterns from a hash that flicker now and then.
// Your finger clears a hole in the rain.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Rain;
uniform float cell_size : hint_range(8.0, 48.0) = 18.0;
uniform float speed : hint_range(0.0, 3.0) = 1.0;
uniform float tail : hint_range(2.0, 40.0) = 14.0;
uniform float flicker : hint_range(0.0, 10.0) = 3.0;
group_uniforms Colour;
uniform vec3 glyph_color : source_color = vec3(0.3, 1.0, 0.45);
uniform vec3 head_color : source_color = vec3(0.85, 1.0, 0.9);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float glyph(vec2 cell, vec2 f) {
	vec2 g = floor(f * vec2(3.0, 5.0));
	float on = step(0.5, hash(cell + g * 0.37 + floor(TIME * flicker * hash(cell))));
	vec2 inner = fract(f * vec2(3.0, 5.0));
	float pip = step(0.15, inner.x) * step(0.15, inner.y) * step(inner.x, 0.85) * step(inner.y, 0.85);
	float frame = step(0.1, f.x) * step(f.x, 0.9) * step(0.05, f.y) * step(f.y, 0.95);
	return on * pip * frame;
}

void fragment() {
	vec2 px = UV * resolution;
	vec2 cell = floor(px / cell_size);
	vec2 f = fract(px / cell_size);
	float rows = resolution.y / cell_size;
	float column_speed = (0.5 + hash(vec2(cell.x, 7.0))) * speed * 8.0;
	float head = mod(TIME * column_speed + hash(vec2(cell.x, 3.0)) * 100.0, rows + tail);
	float dist = head - cell.y;
	float b = dist >= 0.0 && dist < tail ? 1.0 - dist / tail : 0.0;
	float g = glyph(cell, f);
	vec3 col = glyph_color * g * b * b;
	if (dist >= 0.0 && dist < 1.0) {
		col = head_color * g * 1.4;
	}
	float hole = smoothstep(0.08, 0.16, length((UV - mouse) * vec2(resolution.x / resolution.y, 1.0)));
	col *= mix(0.15, 1.0, hole);
	COLOR = vec4(col + vec3(0.0, 0.02, 0.01), 1.0);
}
