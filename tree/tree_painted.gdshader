// TreeGen's "painted" leaves (after GameCommon painted-woodland's foliage): big camera-facing cards,
// each a clump of real leaves (painted-woodland's leaf atlas, or TreeGen's own clusters without it),
// one leaf to each cell of a Voronoi pattern at its own slant, the edge ragged with strays, twigs in
// the gaps and a dark middle. Lit by the scene's lights through normals bent out from the crown.
// Vertices carry what tree_fluffy.gdshader's do.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform, specular_disabled;

#include "res://tree/tree_common.gdshaderinc"

uniform sampler2D leaf_atlas : filter_linear_mipmap, repeat_disable;
// the atlas's cells across and down, and which cell (0 beech, 1 oak, 2 maple, 3 aspen, 4 birch)
uniform float atlas_cols = 5.0;
uniform float atlas_rows = 1.0;
uniform float shape = 1.0;
uniform float leaf_scale = 6.5;
uniform float billboard : hint_range(0.0, 1.0) = 1.0;
uniform float normal_bend : hint_range(0.0, 1.0) = 0.8;

varying float v_seed;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void vertex() {
	v_sway = UV2.y;
	v_seed = UV2.x;
	vec3 centre = CUSTOM0.xyz;
	vec3 shift = (VIEW_MATRIX * vec4(tree_wind(MODEL_MATRIX, centre, UV2.y, TIME), 0.0)).xyz;
	vec3 c = (MODELVIEW_MATRIX * vec4(centre, 1.0)).xyz + shift;
	vec3 here = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz + shift;
	float half_size = CUSTOM0.w * length(MODEL_MATRIX[0].xyz) * smoothstep(0.6, 3.0, -c.z);
	vec2 corner = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float spin = (UV2.x - 0.5) * 1.2;
	corner = vec2(corner.x * cos(spin) - corner.y * sin(spin), corner.x * sin(spin) + corner.y * cos(spin));
	// (each card a step nearer or further, so where they cross they do not flicker)
	c.z += (UV2.x - 0.5) * half_size * 0.8;
	VERTEX = mix(here, c + vec3(corner * half_size, 0.0), billboard);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	COLOR.rgb = tree_srgb(COLOR.rgb);
}

void fragment() {
	float seed = v_seed * 97.0;
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float edge = 0.7 + 0.24 * tw_noise(vec2(ang * 1.6 + seed, seed)) + 0.06 * sin(ang * 13.0 + seed);
	// one leaf per cell at a slant of its own; where leaves overlap the higher numbered is in front;
	// past the clump's edge fewer, so the outline is ragged with strays
	vec2 g = UV * leaf_scale + seed;
	vec2 gi = floor(g);
	vec2 gf = fract(g);
	float front = -1.0;
	float along = 0.0;
	float vein = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 h = hash2(gi + o);
			vec2 d = gf - (o + h);
			float a = h.x * 6.283 + h.y * 3.0;
			vec2 q = vec2(d.x * cos(a) + d.y * sin(a), -d.x * sin(a) + d.y * cos(a));
			vec2 lu = vec2(0.5 + q.y / 1.3, 0.5 - q.x / 1.3);
			if (lu.x > 0.0 && lu.x < 1.0 && lu.y > 0.0 && lu.y < 1.0) {
				vec4 cut = textureLod(leaf_atlas, vec2((shape + lu.x) / atlas_cols, lu.y / atlas_rows), 1.0);
				float lr = length(((gi + o + h - seed) / leaf_scale - 0.5) * 2.0);
				bool kept = lr < edge || (lr < edge + 0.22 && hash2(gi + o + 5.0).x < 0.3);
				float id = hash2(gi + o + 17.0).x;
				if (cut.a > 0.5 && kept && id > front) {
					front = id;
					along = clamp(1.0 - lu.y * 2.0, -1.0, 1.0);
					vein = 1.0 - cut.r;
				}
			}
		}
	}
	// twigs out through the clump, seen in its gaps
	float twig = 0.0;
	for (int k = 0; k < 4; k++) {
		float ta = v_seed * 40.0 + float(k) * 1.57 + float(k * k) * 0.5;
		vec2 dir = vec2(cos(ta), sin(ta));
		float s = clamp(dot(p, dir), 0.0, 0.95);
		vec2 bend = vec2(-dir.y, dir.x) * sin(s * 4.0 + float(k)) * 0.06;
		twig = max(twig, step(length(p - dir * s - bend), 0.03 * (1.0 - s * 0.7)) * step(0.02, dot(p, dir)));
	}
	bool in_middle = r < edge - 0.2 && tw_noise(UV * 7.0 + seed) > 0.3;
	ALPHA = (front >= 0.0 || in_middle || twig > 0.5) ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float tone = 0.75 - r * 0.3;
	if (front >= 0.0) {
		tone += (front - 0.5) * 0.4 + along * 0.08 - vein * 0.5;
	} else {
		tone = tone * 0.35 - 0.15;
	}
	tone = clamp(tone, 0.0, 1.0);
	vec3 albedo = mix(COLOR.rgb * vec3(0.25, 0.22, 0.2), COLOR.rgb, smoothstep(0.05, 0.6, tone));
	albedo = mix(albedo, COLOR.rgb * 1.25, smoothstep(0.65, 1.0, tone));
	if (twig > 0.5 && front < 0.0) {
		albedo = vec3(0.05, 0.035, 0.025);
	}
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = normalize(mix(vec3(0.0, 0.0, 1.0), n, normal_bend));
	vec3 emission = vec3(0.0);
	tree_debug(albedo, emission, NORMAL, INV_VIEW_MATRIX, v_sway);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 1.0;
}
