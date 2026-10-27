shader_type spatial;
// GameCommon's ocean (OceanSurface): a sum of Gerstner waves (after Mariner's ocean, which used plain
// sines; the horizontal push of a Gerstner wave sharpens the crests as "chop" goes up). The fold of
// the surface (the Jacobian of the push) says where crests break, and that is where the foam is.
// Gusts darken and roughen the water in patches drifting downwind (Mariner's gust patches).
// Shading is done by hand: sky reflection by Fresnel, the sun's glitter, light scattering through
// thin crests, distance haze. Must match the CPU waves in ocean_surface.gd (wave_at, gust_at).
render_mode unshaded, cull_disabled;

const int MAX_WAVES = 12;
uniform vec4 waves[12];        // xy direction, z amplitude (m), w wavelength (m)
uniform float steepness[12];   // Gerstner Q per wave
uniform int wave_count = 8;
uniform float wave_time = 0.0;
uniform float fade_start = 80.0;
uniform float fade_end = 118.0;
uniform float max_height = 1.0;
uniform vec4 ripples[4];       // x, z, age (s), strength: rings from things that hit the water

uniform vec3 deep_color : source_color = vec3(0.01, 0.07, 0.16);
uniform vec3 scatter_color : source_color = vec3(0.05, 0.42, 0.45);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.97);
uniform vec3 zenith : source_color = vec3(0.13, 0.36, 0.78);
uniform vec3 horizon : source_color = vec3(0.66, 0.8, 0.94);
uniform vec3 light_dir = vec3(0.0, 0.7, -0.7);
uniform vec3 light_color : source_color = vec3(1.0);
uniform float light_energy = 1.2;
uniform vec3 ambient : source_color = vec3(0.5);
uniform float foam_amount : hint_range(0.0, 1.0) = 0.5;
uniform float chop = 0.5;
uniform float toon = 0.0;
uniform float overcast = 0.0;
uniform float haze_start = 60.0;
uniform float haze_end = 900.0;
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec2 detail_offset = vec2(0.0);
uniform float detail_strength = 0.6;
uniform sampler2D foam_noise : repeat_enable, filter_linear_mipmap;
uniform float gusts = 0.5;          // how strongly gust patches show (0 none)
uniform vec2 gust_offset = vec2(0.0); // how far the gust patches have drifted downwind (m)

varying vec3 world_pos;
varying vec3 wnormal;
varying float fold;
varying float wave_h;

// Big slow patches of stronger wind, drifting downwind (Mariner's gust_factor). Must match gust_at().
float gust_factor(vec2 p) {
	vec2 q = p - gust_offset;
	float g = sin(q.x * 0.021 + q.y * 0.013) * sin(-q.x * 0.011 + q.y * 0.027 + 1.7);
	g += 0.5 * sin(q.x * 0.043 - q.y * 0.031 + 4.0) * sin(q.x * 0.017 + q.y * 0.009);
	return clamp(g * 0.6 + 0.45, 0.0, 1.0);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 rel = wp.xz - MODEL_MATRIX[3].xz;
	float amp = 1.0 - smoothstep(fade_start, fade_end, max(abs(rel.x), abs(rel.y)));
	vec3 p = vec3(0.0);
	// Partial derivatives of the displaced point against x and z
	vec3 tx = vec3(1.0, 0.0, 0.0);
	vec3 tz = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < MAX_WAVES; i++) {
		if (i >= wave_count) break;
		vec2 d = normalize(waves[i].xy);
		float a = waves[i].z * amp;
		float k = 6.28318530718 / waves[i].w;
		float w = sqrt(9.81 * k);
		float ph = k * dot(d, wp.xz) - w * wave_time;
		float s = sin(ph);
		float c = cos(ph);
		float q = steepness[i];
		p += vec3(q * a * d.x * c, a * s, q * a * d.y * c);
		tx += vec3(-q * a * k * d.x * d.x * s, a * k * d.x * c, -q * a * k * d.x * d.y * s);
		tz += vec3(-q * a * k * d.x * d.y * s, a * k * d.y * c, -q * a * k * d.y * d.y * s);
	}
	// Rings from splashes: a damped ripple running outward
	for (int r = 0; r < 4; r++) {
		vec4 rp = ripples[r];
		if (rp.w <= 0.0) continue;
		float dist = length(wp.xz - rp.xy);
		float front = rp.z * 4.0;
		float env = exp(-abs(dist - front) * 0.6) * exp(-rp.z * 0.9) * rp.w;
		float rh = sin(dist * 2.4 - rp.z * 10.0) * env * 0.35;
		p.y += rh;
		float dr = cos(dist * 2.4 - rp.z * 10.0) * env * 0.35 * 2.4;
		vec2 dir = (wp.xz - rp.xy) / max(dist, 0.001);
		tx.y += dr * dir.x;
		tz.y += dr * dir.y;
	}
	VERTEX += p;
	wnormal = normalize(cross(tz, tx));
	fold = tx.x * tz.z - tx.z * tz.x;
	world_pos = wp + p;
	wave_h = p.y;
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - world_pos);
	float dist = length(CAMERA_POSITION_WORLD - world_pos);
	vec3 N = normalize(wnormal);
	// Fine ripples from a scrolling normal map, two layers crossing, fading with distance
	float near = 1.0 - smoothstep(20.0, 140.0, dist);
	vec2 uv = world_pos.xz * 0.03;
	vec3 n1 = texture(detail_normal, uv + detail_offset).xyz * 2.0 - 1.0;
	vec3 n2 = texture(detail_normal, uv * 1.9 - detail_offset * 1.3 + 0.5).xyz * 2.0 - 1.0;
	// Gusts: patches where the wind is stronger, rougher (more ripple) and darker
	float patch = smoothstep(0.55, 0.85, gust_factor(world_pos.xz)) * gusts;
	vec2 bump = (n1.xy + n2.xy) * detail_strength * near * 0.5 * (1.0 + patch * 1.3);
	N = normalize(N + vec3(bump.x, 0.0, bump.y));
	if (!FRONT_FACING) N = -N;
	vec3 L = normalize(light_dir);
	float sun_up = smoothstep(-0.05, 0.08, light_dir.y);

	float hn = clamp(wave_h / max(max_height, 0.05), -1.0, 1.0);
	float ndl = max(dot(N, L), 0.0);
	vec3 lit = ambient + light_color * light_energy * (0.35 + 0.65 * ndl) * 0.6;
	vec3 body = deep_color * lit + scatter_color * ambient * 0.12;
	// Light through thin crests, strongest looking toward the light
	float back = pow(clamp(dot(-V, normalize(vec3(L.x, 0.0, L.z) + vec3(0.0, 0.2, 0.0))), 0.0, 1.0), 3.0);
	float sss = clamp(hn * 0.8 + 0.3, 0.0, 1.0) * (0.35 + 1.4 * back) * sun_up;
	body += scatter_color * sss * light_color * light_energy * 0.55 * (1.0 - overcast * 0.7);

	vec3 R = reflect(-V, N);
	R.y = abs(R.y);
	vec3 sky = mix(horizon, zenith, pow(clamp(R.y, 0.0, 1.0), 0.5));
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 5.0);
	vec3 col = mix(body, sky, fres * 0.9);
	col *= 1.0 - patch * 0.28;
	// Sun glitter
	float spec = pow(max(dot(R, L), 0.0), 600.0) * 18.0 + pow(max(dot(R, L), 0.0), 60.0) * 0.6;
	col += light_color * spec * light_energy * (1.0 - overcast) * max(sun_up, 0.25);

	// Foam: where the surface folds (breaking crests), broken up by noise, plus a light lace
	float fn = texture(foam_noise, world_pos.xz * 0.05 + detail_offset * 0.3).r;
	float fn2 = texture(foam_noise, world_pos.xz * 0.19 - detail_offset * 0.5).r;
	// How far this point has folded, against the most the waves could fold it (1 = breaking)
	float folded = clamp((1.0 - fold) / max(chop * 0.6, 0.05), 0.0, 1.2);
	float e0 = 0.78 - 0.5 * foam_amount;
	float crest = smoothstep(e0, e0 + 0.25, folded) * step(0.01, foam_amount);
	// Erode the noise by how hard the crest is breaking: ragged whitecaps, not slabs
	float lace = fn * 0.55 + fn2 * 0.45;
	float foam = smoothstep(1.0 - crest * 0.75, 1.08 - crest * 0.75, lace + 0.12) * step(0.001, crest) * (0.45 + 0.55 * fn2);
	// Small whitecaps scattered over the short waves
	// Small whitecaps on the crests of the short waves, frothy at the edge
	float f3 = texture(foam_noise, world_pos.xz * 0.11 + detail_offset * 0.7).r;
	float cap = f3 * 0.55 + folded * 0.45 + fn2 * 0.15;
	float e1 = 0.86 - 0.28 * foam_amount;
	foam += smoothstep(e1, e1 + 0.06, cap) * smoothstep(0.35, 0.75, fn2 + fn * 0.3) * step(0.01, foam_amount) * 0.9;

	foam = clamp(foam, 0.0, 1.0) * near;

	if (toon > 0.5) {
		// Wind Waker: bands by wave height, a hard foam line, a flat horizon tint
		float band = floor(clamp(hn * 0.5 + 0.5, 0.0, 0.999) * 3.0) / 2.0;
		col = mix(deep_color, scatter_color, band) * (ambient + light_color * light_energy * 0.6);
		col = mix(col, horizon, step(0.5, fres) * 0.5);
		col = mix(col, deep_color * 0.8 * (ambient + light_color * light_energy * 0.6), patch * 0.55);
		col += light_color * step(0.6, spec) * 0.8;
		foam = step(0.5, foam + step(0.86 - foam_amount * 0.3, hn) * step(0.5, fn2 + 0.2));
	}
	col = mix(col, foam_color * (ambient + light_color * light_energy * (0.5 + 0.5 * ndl)) * 0.8, foam);
	// Haze into the sky at the horizon
	col = mix(col, horizon, smoothstep(haze_start, haze_end, dist) * 0.92);
	ALBEDO = col;
}
