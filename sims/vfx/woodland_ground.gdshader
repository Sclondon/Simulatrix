// Painted Wood's ground (after Scenic Route's): leaf litter in dabs over dark earth, mossy patches, a worn
// path across the glade, dark pools under the trees and dappled sun coming through the canopy, drifting as
// the wind moves the leaves. Lit by hand, as the woodland kit is.
shader_type spatial;
render_mode unshaded;

uniform vec3 sun_color : source_color = vec3(1.0, 0.84, 0.52);
uniform vec3 dirt : source_color = vec3(0.5, 0.38, 0.25);
uniform vec3 dirt_dark : source_color = vec3(0.26, 0.18, 0.11);
uniform vec3 litter_a : source_color = vec3(0.62, 0.36, 0.14);
uniform vec3 litter_b : source_color = vec3(0.42, 0.25, 0.11);
uniform vec3 litter_c : source_color = vec3(0.72, 0.52, 0.2);
uniform vec3 moss : source_color = vec3(0.32, 0.33, 0.13);
uniform vec3 shadow : source_color = vec3(0.09, 0.06, 0.045);
// x, z, crown radius, 0: up to 48 trees, for the pools under them
uniform vec4 trees[48];
uniform int tree_count = 0;
uniform float dapple = 1.0;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.28 + vnoise(p * 4.1 + 3.3) * 0.17;
}

// nearest leaf dab: x its shade, y how close to its middle
vec2 dabs(vec2 p) {
	vec2 gi = floor(p);
	vec2 gf = fract(p);
	float best = 8.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 d = o + hash2(gi + o) - gf;
			d.x *= 1.6;
			float dd = dot(d, d);
			if (dd < best) { best = dd; id = gi + o; }
		}
	}
	return vec2(hash(id), 1.0 - sqrt(best));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 d = dabs(p * 4.6);
	vec3 litter = d.x < 0.4 ? litter_a : (d.x < 0.75 ? litter_b : litter_c);
	litter *= 0.75 + 0.4 * d.y;
	litter = mix(litter, dirt_dark, smoothstep(0.5, 0.85, fbm(p * 0.35)) * 0.7);
	litter = mix(litter, moss * (0.8 + 0.3 * vnoise(p * 2.0)), smoothstep(0.62, 0.8, fbm(p * 0.21 + 11.0)) * 0.8);
	// a path worn across the glade
	float px = 1.6 * sin(p.y * 0.09) + 0.8 * sin(p.y * 0.21 + 1.0);
	float on_path = 1.0 - smoothstep(0.9, 1.5, abs(p.x - px) + (fbm(p * 0.6) - 0.5) * 0.8);
	vec3 c = mix(litter, dirt * (0.85 + 0.25 * vnoise(p * 4.0)), on_path * 0.85);
	// pools of shade under the crowns, lit through in drifting patches
	float shade = 0.0;
	for (int i = 0; i < 48; i++) {
		if (i >= tree_count) {
			break;
		}
		float r = trees[i].z;
		float k = 1.0 - smoothstep(r * 0.25, r * 1.1, distance(p, trees[i].xy));
		shade = max(shade, k);
	}
	float drift = fbm(p * 0.7 + vec2(TIME * 0.05, TIME * 0.03));
	float sun_patch = smoothstep(0.55, 0.62, drift) * dapple;
	float lit = mix(1.0, 0.45, shade * (1.0 - sun_patch * 0.8));
	c *= lit;
	c += c * sun_color * sun_patch * (1.0 - shade * 0.5) * 0.35;
	ALBEDO = c;
}
