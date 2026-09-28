shader_type canvas_item;
// Colours the falling-sand grid: one byte per cell picks a palette entry, then
// each cell gets its own grain of light and dark so piles look like piles, and
// fire and lava flicker.

uniform sampler2D cells : filter_nearest;
uniform sampler2D palette : filter_nearest;
uniform float count = 10.0;
uniform vec2 grid = vec2(100.0, 100.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float id = floor(texture(cells, UV).r * 255.0 + 0.5);
	vec2 cell = floor(UV * grid);
	vec3 col = texture(palette, vec2((id + 0.5) / count, 0.5)).rgb;
	float grain = hash(cell) - 0.5;
	if (id < 0.5) {
		// Empty: a dark backdrop with a faint vertical gradient
		col *= 0.85 + 0.25 * (1.0 - UV.y);
	} else if (id == 5.0 || id == 7.0) {
		// Fire and lava shimmer
		float flick = hash(cell + floor(TIME * 12.0));
		col = mix(col, vec3(1.0, 0.9, 0.4), flick * (id == 5.0 ? 0.6 : 0.25));
	} else if (id == 2.0) {
		col += 0.06 * sin(TIME * 2.0 + cell.x * 0.4 + cell.y * 0.2);
	} else {
		col *= 1.0 + grain * 0.18;
	}
	COLOR = vec4(col, 1.0);
}
