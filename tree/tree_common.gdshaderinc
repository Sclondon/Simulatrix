// Shared by the tree shaders (TreeGen): the wind, the light, and the debug views.
//
// Wind: the same uniforms as GameCommon wind's wind_sway.gdshader, so WindField.register(material)
// drives a tree too. UV2.y on every vertex says how much it sways (0 the trunk's foot, 1 the tips):
// the whole tree leans with the gust at its foot, rocks back, and the leaves flutter.
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind = 0.35;
uniform float gust_size = 16.0;
uniform float gust_speed = 5.0;
uniform float gustiness = 0.6;
uniform float turbulence = 0.3;
uniform vec4 blasts[4];
uniform float blast_speed = 9.0;
// Light: 0 soft (half-Lambert, wrapping round the crown), 1 two-tone cel. `rim` a fresnel edge that
// glows most with the sun behind.
uniform float toon : hint_range(0.0, 1.0) = 0.0;
uniform float rim : hint_range(0.0, 1.0) = 0.0;
// 0 shaded, 1 the normals, 2 the sway weights as a heat ramp, 3 dimmed (under a wireframe).
uniform int debug_view = 0;

varying float v_sway;

float tw_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float tw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(tw_hash(i), tw_hash(i + vec2(1.0, 0.0)), f.x), mix(tw_hash(i + vec2(0.0, 1.0)), tw_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// How far (world space, metres) a point `at` of the tree moves now, swaying by `sway`.
vec3 tree_wind(mat4 model, vec3 at, float sway, float time) {
	vec3 root = model[3].xyz;
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	vec2 g = root.xz / gust_size - wd * time * gust_speed / gust_size;
	float gust = smoothstep(0.25, 0.85, tw_noise(g) * 0.65 + tw_noise(g * 2.3 + 7.0) * 0.35);
	float push = wind * (0.35 + gustiness * 1.4 * gust + (1.0 - gustiness) * 0.4);
	float rock = sin(time * (1.1 + wind * 0.8) + root.x * 0.3 + root.z * 0.2) * (0.25 + turbulence);
	vec2 bend = wd * push * (1.0 + rock * 0.35);
	for (int i = 0; i < 4; i++) {
		vec4 b = blasts[i];
		float age = time - b.z;
		if (b.w > 0.0 && age >= 0.0 && age <= 3.0) {
			vec2 away = root.xz - b.xy;
			float dist = length(away);
			float ring = exp(-pow((dist - age * blast_speed) / 2.5, 2.0));
			bend += away / max(dist, 0.001) * ring * b.w * (1.0 - smoothstep(0.0, 3.0, age)) * 1.6 / (1.0 + dist * 0.06);
		}
	}
	vec3 w = (model * vec4(at, 1.0)).xyz;
	float f = sin(time * (6.0 + 6.0 * turbulence) + w.x * 3.1 + w.y * 2.3 + w.z * 2.7);
	vec3 flutter = vec3(f, f * 0.5, -f) * (0.03 + 0.08 * turbulence) * (0.3 + push);
	vec3 shift = vec3(bend.x, 0.0, bend.y) * 0.9 * sway;
	shift.y -= dot(bend, bend) * 0.2 * sway * sway;
	return shift + flutter * sway;
}

vec3 tree_srgb(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// The debug views: what ALBEDO and EMISSION become (`n` the view-space normal).
void tree_debug(inout vec3 albedo, inout vec3 emission, vec3 n, mat4 inv_view, float sway) {
	if (debug_view == 1) {
		emission = pow(normalize((inv_view * vec4(n, 0.0)).xyz) * 0.5 + 0.5, vec3(2.2));
		albedo = vec3(0.0);
	} else if (debug_view == 2) {
		vec3 cold = vec3(0.05, 0.1, 0.45);
		vec3 mid = vec3(0.1, 0.75, 0.3);
		vec3 hot = vec3(1.0, 0.35, 0.05);
		emission = sway < 0.5 ? mix(cold, mid, sway * 2.0) : mix(mid, hot, sway * 2.0 - 1.0);
		albedo = vec3(0.0);
	} else if (debug_view == 3) {
		albedo *= 0.25;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// (shadow softened: a crown of cards shadowing itself would be speckled dark)
	float soft = pow(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), 1.6) * mix(0.45, 1.0, ATTENUATION);
	float cel = mix(0.38, 1.0, smoothstep(0.0, 0.06, ndl) * step(0.5, ATTENUATION));
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float behind = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * (mix(soft, cel, toon) + rim * edge * (0.3 + behind) * ATTENUATION) / PI;
}
