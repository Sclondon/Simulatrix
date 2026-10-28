// TreeGen's "needle" leaves (after GameCommon PineTree's NEEDLES): crossed cards along each frond.
// A card has a twig down its middle; off it both ways, slanted towards the tip, run short branchlets,
// and off each branchlet needles, short and thin, lighter at their tips: all cut out (alpha scissor).
// Far off, where a needle would be under a pixel, the branchlets are drawn filled in instead, and
// further still the frond's outline, so it neither shimmers nor thins away.
// A card's vertices carry: UV metres along the frond and across it (-1..1 of its widest half);
// UV2.x 1, UV2.y how much it sways; CUSTOM0.x the frond's length; COLOR.a half its widest half-width.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://tree/tree_common.gdshaderinc"

// more needles, closer together (and shorter) at more than 1
uniform float needle_density : hint_range(0.4, 2.5) = 1.0;
// the fronds' own small sway, more towards their tips
uniform float frond_sway : hint_range(0.0, 0.3) = 0.04;
uniform float alpha_cut : hint_range(0.05, 0.95) = 0.5;

varying float half_width;
varying float frond;

float outline(float s) {
	return max(sin(PI * (0.1 + 0.9 * clamp(s, 0.0, 1.0))), 0.0);
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	v_sway = UV2.y;
	frond = CUSTOM0.x;
	half_width = COLOR.a * 2.0;
	COLOR.rgb = tree_srgb(COLOR.rgb);
	vec3 here = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = UV.x / max(frond, 0.01);
	float bend = s * s * frond * frond_sway;
	float t = TIME * 1.1 + dot(here.xz, vec2(0.13, 0.11)) + here.y * 0.05;
	vec3 shift = vec3(sin(t) * 0.6, sin(t * 1.7 + 0.8), cos(t * 0.8) * 0.6) * bend;
	shift += tree_wind(MODEL_MATRIX, VERTEX, UV2.y, TIME);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(shift, 0.0)).xyz;
}

void fragment() {
	float branch = 0.13 / needle_density;
	float spacing = 0.017 / needle_density;
	float needle_len = 0.07 / sqrt(needle_density);
	vec3 colour = COLOR.rgb;
	float x = UV.x;
	float s = x / max(frond, 0.01);
	float hw = max(half_width, 0.05);
	float out_m = abs(UV.y) * hw;
	float side = UV.y < 0.0 ? 1.0 : 0.0;
	float edge = outline(s) * hw;
	// the branchlet this is by: slanted towards the tip, the two sides staggered
	float u = x - out_m * 0.85 + side * branch * 0.5;
	float index = floor(u / branch) + side * 101.0;
	float r = hash(index);
	float across = (fract(u / branch) - 0.5) * branch / 1.31;
	float reach = edge * mix(0.75, 1.05, r);
	float into = clamp(out_m / max(reach, 0.01), 0.0, 1.0);
	float a = abs(across);
	// its needles: off its stem both ways, slanted outwards, shorter towards its end
	float length_here = needle_len * (1.0 - 0.5 * into) * mix(0.8, 1.15, r) * step(out_m, reach);
	float q = (out_m * 1.31 - a * 0.9) / spacing + r * 7.0;
	float nf = abs(fract(q) - 0.5);
	float thin = 0.24 * (1.0 - 0.75 * a / max(length_here, 0.001));
	float px = fwidth(x / spacing);
	float needle = (1.0 - smoothstep(thin - px, thin + px, nf)) * step(a, length_here);
	float stem = (1.0 - smoothstep(0.004, 0.004 + fwidth(across), a)) * step(out_m, reach);
	float twig = (1.0 - smoothstep(0.012, 0.012 + fwidth(out_m), out_m)) * step(s, 0.97);
	float near_cover = max(max(needle, stem), twig);
	// far off: the branchlets filled in, then the whole frond
	float fine = clamp(px * 1.6 - 0.6, 0.0, 1.0);
	float coarse = clamp(fwidth(x / branch) * 1.6 - 0.5, 0.0, 1.0);
	float tuft = step(a, length_here * 0.85) + twig;
	float cover = mix(mix(near_cover, tuft, fine), step(out_m, edge * 0.9), coarse);
	ALPHA = clamp(cover, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	// darker at the stems and twig, lighter out at the needles' tips, each needle its own shade
	float tip = clamp(a / max(length_here, 0.001), 0.0, 1.0);
	colour *= mix(mix(0.72, 1.2, tip), 0.95, fine) * mix(0.8, 1.0, into);
	colour *= 0.88 + 0.24 * hash(index * 3.1 + floor(q)) * (1.0 - fine);
	colour = mix(colour, vec3(0.06, 0.045, 0.03), max(stem, twig) * (1.0 - fine) * 0.8);
	// (lit the same from both sides: the normal is bent out from the crown)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 emission = vec3(0.0);
	tree_debug(colour, emission, NORMAL, INV_VIEW_MATRIX, v_sway);
	ALBEDO = colour;
	EMISSION = emission;
	ROUGHNESS = 1.0;
}
