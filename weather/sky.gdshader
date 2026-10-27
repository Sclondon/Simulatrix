shader_type sky;
// GameCommon weather's sky: a gradient from the horizon to the zenith, a sun with a glow, a moon,
// stars at night, a layer of cloud projected on a plane overhead (lit from the sun, dark
// underneath when it is thick) and a lightning flash. Colours come from Daylight (daylight.gd).

uniform vec3 zenith : source_color = vec3(0.13, 0.36, 0.78);
uniform vec3 horizon : source_color = vec3(0.66, 0.8, 0.94);
uniform vec3 ground : source_color = vec3(0.2, 0.22, 0.24);
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.9);
uniform float night = 0.0;
uniform float overcast = 0.0;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_scale = 1.0;      // bigger: higher, smaller-looking clouds
uniform vec2 cloud_offset = vec2(0.0);
uniform vec2 cloud_stretch = vec2(1.0); // cirrus: long streaks
uniform float flash = 0.0;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float clouds(vec2 uv) {
	float n = texture(cloud_noise, uv).r * 0.7 + texture(cloud_noise, uv * 2.7 + 0.31).r * 0.3;
	float c = clamp(cloud_cover * 1.15, 0.0, 1.0);
	return smoothstep(1.0 - c, 1.0 - c + 0.28, n);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
	if (h < 0.0) {
		col = mix(horizon, ground * (0.3 + 0.7 * (1.0 - night)), smoothstep(0.0, 0.25, -h));
	}
	vec3 sd = normalize(sun_dir);
	float sun_up = smoothstep(-0.12, 0.05, sd.y);
	float mu = max(dot(d, sd), 0.0);
	float clear = 1.0 - overcast;
	// Haze round the sun and a warm horizon band toward it
	col += sun_color * (pow(mu, 8.0) * 0.35 + pow(mu, 64.0) * 0.4) * sun_up * clear;

	if (!AT_CUBEMAP_PASS) {
		// Stars, a coarse grid so they read as points
		vec3 q = floor(d * 260.0);
		float n = hash(q);
		float tw = 0.6 + 0.4 * sin(TIME * 2.3 + n * 60.0);
		col += vec3(step(0.9965, n) * tw) * night * clear * smoothstep(0.0, 0.25, h);
		// Sun and moon discs
		col = mix(col, sun_color * 3.0, smoothstep(0.9993, 0.9996, mu) * sun_up * clear);
		vec3 md = normalize(moon_dir);
		float mm = dot(d, md);
		float disc = smoothstep(0.99935, 0.9996, mm);
		float shade = 0.75 + 0.25 * texture(cloud_noise, d.xy * 9.0).r;
		col = mix(col, vec3(0.86, 0.9, 1.0) * shade, disc * night * clear);
		col += vec3(0.5, 0.6, 0.9) * pow(max(mm, 0.0), 300.0) * 0.25 * night * clear;

		// The cloud layer: noise on a plane overhead, seen from below
		if (h > 0.0) {
			vec2 uv = d.xz / (h + 0.08) * 0.22 / cloud_scale / cloud_stretch + cloud_offset;
			float c = clouds(uv);
			// Toward the sun: how much cloud the light passes through on the way
			vec2 to_sun = normalize(sd.xz + vec2(0.0001)) * 0.025;
			float behind = clouds(uv + to_sun);
			float lit = clamp(1.0 - behind * 0.9 + 0.2, 0.0, 1.0);
			vec3 bright = mix(vec3(1.0), sun_color, 0.35) * (0.45 + 0.75 * (1.0 - night));
			vec3 dark = mix(horizon, zenith, 0.4) * 0.55 + vec3(0.06);
			dark = mix(dark, vec3(0.24, 0.25, 0.28) * (1.0 - night * 0.8), overcast);
			vec3 cc = mix(dark, bright, lit * (1.0 - overcast * 0.7));
			// Silver lining: thin cloud edges glow toward the sun
			cc += sun_color * pow(mu, 6.0) * (1.0 - c) * 1.6 * sun_up;
			float fade = smoothstep(0.0, 0.22, h);
			col = mix(col, cc, c * fade);
		}
	}
	// Overcast: a flat lid of cloud over everything
	vec3 lid = mix(horizon, vec3(0.42, 0.44, 0.48) * (1.0 - night * 0.85), 0.6);
	col = mix(col, lid * (0.8 + 0.25 * h), overcast * 0.55 * smoothstep(-0.05, 0.2, h));
	col += vec3(0.75, 0.8, 1.0) * flash;
	COLOR = col;
}
