// TreeGen's solid parts: the trunk, branches and roots, the dark mass inside the crown, and the
// "blobs" leaf clumps. Vertex colours (sRGB); UV2.y how much each corner sways.
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://tree/tree_common.gdshaderinc"

void vertex() {
	v_sway = UV2.y;
	vec3 shift = tree_wind(MODEL_MATRIX, VERTEX, UV2.y, TIME);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(shift, 0.0)).xyz;
	COLOR.rgb = tree_srgb(COLOR.rgb);
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	vec3 emission = vec3(0.0);
	tree_debug(albedo, emission, NORMAL, INV_VIEW_MATRIX, v_sway);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 1.0;
}
