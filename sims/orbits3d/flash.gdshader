// A burst of light where a satellite burns up: a soft additive disc that always faces the
// camera, a hot white core in an orange glow. `life` runs 0 to 1 and fades it out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform float life = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.55, 0.2);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float fade = 1.0 - life;
	float glow = exp(-r * r * 6.0) * fade * fade;
	float core = exp(-r * r * 40.0) * fade;
	ALBEDO = tint * glow * 1.6 + vec3(1.0, 0.95, 0.85) * core;
}
