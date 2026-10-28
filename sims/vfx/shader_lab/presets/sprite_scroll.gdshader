shader_type canvas_item;
// Sprite scroll: a picture tiled across the preview, drifting, bent by a noise texture.
// Every sampler2D uniform becomes a picker on the panel: a built-in noise, a sprite you draw
// (+ Draw), or an image you import (+ Import).
uniform vec2 resolution = vec2(512.0);

group_uniforms Pictures;
uniform sampler2D pattern : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D warp_noise : repeat_enable, filter_linear;
group_uniforms Motion;
uniform float tiles : hint_range(1.0, 12.0) = 4.0;
uniform float drift : hint_range(0.0, 1.0) = 0.15;
uniform float bend : hint_range(0.0, 0.5) = 0.08;
group_uniforms Colour;
uniform vec3 tint : source_color = vec3(1.0, 0.75, 0.35);
uniform vec3 back : source_color = vec3(0.08, 0.07, 0.12);

void fragment() {
	vec2 uv = UV * vec2(resolution.x / resolution.y, 1.0) * tiles;
	uv += vec2(TIME * drift, TIME * drift * 0.6);
	vec2 n = texture(warp_noise, UV * 0.7 + TIME * 0.03).rg - 0.5;
	uv += n * bend * tiles;
	vec4 p = texture(pattern, uv);
	COLOR = vec4(mix(back, p.rgb * tint, p.a), 1.0);
}
