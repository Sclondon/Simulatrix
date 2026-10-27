shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Texture Lab's output pass: colours the packed height the generator pass made
// (texture_gen.gdshaderinc) through the ramp, or shows it as grey height or as a
// normal map from neighbouring texels. Cheap and fixed, so changing the ramp or the
// view never touches the generator.

uniform sampler2D height_tex : filter_nearest, repeat_enable;
uniform sampler2D ramp : filter_linear, repeat_disable;
uniform int view_mode = 0; // 0 colour, 1 height, 2 normal map
uniform float normal_strength = 1.0;

float height(vec2 uv) {
	vec4 c = texture(height_tex, uv);
	return c.r + c.g / 255.0;
}

void fragment() {
	float h = height(UV);
	if (view_mode == 1) {
		COLOR = vec4(vec3(h), 1.0);
	} else if (view_mode == 2) {
		float size = float(textureSize(height_tex, 0).x);
		float e = 1.0 / size;
		float hx = height(UV + vec2(e, 0.0));
		float hy = height(UV + vec2(0.0, e));
		float s = normal_strength * size * 0.04;
		vec3 n = normalize(vec3((h - hx) * s, (h - hy) * s, 1.0));
		COLOR = vec4(n * 0.5 + 0.5, 1.0);
	} else {
		COLOR = vec4(texture(ramp, vec2(h, 0.5)).rgb, 1.0);
	}
}
