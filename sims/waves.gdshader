shader_type canvas_item;
// Ripple tank. Each source is a circular wave; the field is their complex sum,
// so interference falls out for free. Double-slit mode feeds a plane wave
// through two gaps in a barrier (Huygens: each gap acts as a new source).

uniform vec2 size = vec2(720.0);
uniform int count = 0;
uniform vec4 sources[8]; // xy position, z phase offset
uniform float wavelength = 60.0;
uniform float phase_time = 0.0; // in cycles
uniform int mode = 0; // 0 waves, 1 intensity
uniform int slit = 0;
uniform float barrier_x = 200.0;
uniform float slit_gap = 120.0;
uniform float slit_width = 14.0;

vec2 wave(vec2 p, vec2 src, float extra_path, float k) {
	float r = distance(p, src);
	float amp = 1.0 / sqrt(1.0 + r / wavelength * 0.8);
	float ph = k * (r + extra_path);
	return amp * vec2(cos(ph), sin(ph));
}

void fragment() {
	vec2 p = UV * size;
	float k = 6.2831853 / wavelength;
	vec2 z = vec2(0.0);
	float norm = 1.0;
	bool wall = false;
	if (slit == 1) {
		float cy = size.y * 0.5;
		if (p.x < barrier_x) {
			z = vec2(cos(k * p.x), sin(k * p.x));
		} else {
			z += wave(p, vec2(barrier_x, cy - slit_gap * 0.5), barrier_x, k);
			z += wave(p, vec2(barrier_x, cy + slit_gap * 0.5), barrier_x, k);
			norm = 1.4;
		}
		bool in_gap = abs(abs(p.y - cy) - slit_gap * 0.5) < slit_width * 0.5;
		wall = abs(p.x - barrier_x) < 5.0 && !in_gap;
	} else {
		for (int i = 0; i < 8; i++) {
			if (i >= count) break;
			z += wave(p, sources[i].xy, sources[i].z * wavelength, k);
		}
		norm = max(sqrt(float(count)), 1.0);
	}
	z /= norm;
	float w = 6.2831853 * phase_time;
	vec3 col;
	if (mode == 0) {
		float h = z.x * cos(w) + z.y * sin(w);
		vec3 trough = vec3(0.02, 0.05, 0.16);
		vec3 mid = vec3(0.05, 0.28, 0.45);
		vec3 crest = vec3(0.75, 0.97, 1.0);
		col = h < 0.0 ? mix(mid, trough, clamp(-h, 0.0, 1.0)) : mix(mid, crest, clamp(h, 0.0, 1.0));
	} else {
		float intensity = 1.0 - exp(-dot(z, z) * 1.6);
		col = mix(vec3(0.02, 0.02, 0.05), vec3(1.0, 0.55, 0.2), intensity);
		col = mix(col, vec3(1.0, 0.95, 0.8), smoothstep(0.7, 1.0, intensity));
	}
	if (count == 0 && slit == 0) {
		col = vec3(0.05, 0.28, 0.45) * 0.6;
	}
	if (wall) {
		col = vec3(0.55, 0.6, 0.7);
	}
	COLOR = vec4(col, 1.0);
}
