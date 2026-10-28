// TreeGen's "fluffy" leaves: quads scattered over each leaf clump, each turned part way to face the
// camera (`billboard`), cut out of a leaf-cluster texture (alpha scissor), lit with normals bent
// out from the crown (`normal_bend`) so the whole crown shades as one soft mass.
// A card's vertices carry: CUSTOM0 its centre (xyz, model space) and half size; UV its corner;
// UV2.x a random number, UV2.y how much it sways; COLOR its colour (sRGB); NORMAL the crown's.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform, specular_disabled;

#include "res://tree/tree_common.gdshaderinc"

// 4 x 2 cells: a row of broad-leaved clusters, a row of narrow-leaved (TreeGen.clusters())
uniform sampler2D clusters : filter_linear_mipmap, repeat_disable;
uniform float leaf_row = 0.0;
uniform float billboard : hint_range(0.0, 1.0) = 0.85;
uniform float normal_bend : hint_range(0.0, 1.0) = 0.8;
uniform float alpha_cut : hint_range(0.05, 0.95) = 0.45;

varying float v_seed;

void vertex() {
	v_sway = UV2.y;
	v_seed = UV2.x;
	vec3 centre = CUSTOM0.xyz;
	vec3 shift = (VIEW_MATRIX * vec4(tree_wind(MODEL_MATRIX, centre, UV2.y, TIME), 0.0)).xyz;
	vec3 c = (MODELVIEW_MATRIX * vec4(centre, 1.0)).xyz + shift;
	vec3 here = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz + shift;
	// (a card right by the camera would fill the view: it shrinks away)
	float half_size = CUSTOM0.w * length(MODEL_MATRIX[0].xyz) * smoothstep(0.4, 2.0, -c.z);
	vec2 corner = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	VERTEX = mix(here, c + vec3(corner * half_size, 0.0), billboard);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	COLOR.rgb = tree_srgb(COLOR.rgb);
}

void fragment() {
	// each card turned its own way, and one of the four clusters in the row
	float a = v_seed * 6.2832;
	vec2 p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * (UV - 0.5) + 0.5;
	float inside = step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
	float cell = floor(fract(v_seed * 7.31) * 4.0);
	vec4 t = texture(clusters, vec2((cell + clamp(p.x, 0.0, 1.0)) * 0.25, (leaf_row + clamp(p.y, 0.0, 1.0)) * 0.5));
	// far off the mipmaps thin the leaves away: thicken them back as the texels shrink
	vec2 px = UV * 128.0;
	float lod = max(0.0, 0.5 * log2(max(dot(dFdx(px), dFdx(px)), dot(dFdy(px), dFdy(px)))));
	ALPHA = t.a * inside * (1.0 + lod * 0.35);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// R: dark at a leaf's foot, light at its tip; G: each leaf's own shade
	vec3 albedo = COLOR.rgb * mix(0.62, 1.15, t.r) * mix(0.88, 1.1, t.g);
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(vec3(0.0, 0.0, 1.0), n, normal_bend));
	vec3 emission = vec3(0.0);
	tree_debug(albedo, emission, NORMAL, INV_VIEW_MATRIX, v_sway);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 1.0;
}
