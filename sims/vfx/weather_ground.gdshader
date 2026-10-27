shader_type spatial;
// The Weather Lab's land: a flat meadow, rolling hills, a ring of mountains. It gets wet in rain
// (darker, glossy, puddles that mirror the sky and ring with drops), white under settling snow,
// and dappled by cloud shadows. The height must match terrain() in weather.gd.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float wet = 0.0;
uniform float snow = 0.0;
uniform float raining = 0.0;
uniform float hole = 0.0;            // sink the middle (the far mesh, under the near one)
uniform vec3 zenith : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 horizon : source_color = vec3(0.7, 0.8, 0.9);
uniform float shadow_amount = 0.0;
uniform vec2 shadow_offset = vec2(0.0);
uniform float shadow_scale = 0.00012;
uniform float shadow_cover = 0.4;

varying vec3 world;
varying vec3 wnormal;

float terrain(vec2 p) {
	float r = length(p);
	float bumps = sin(p.x * 0.05) * cos(p.y * 0.043) * 0.6 + sin(p.x * 0.13 + 1.0) * sin(p.y * 0.11) * 0.2;
	float hills = sin(p.x * 0.004) * cos(p.y * 0.0035) * 28.0 + sin(p.x * 0.011 + 1.3) * sin(p.y * 0.009 + 0.7) * 9.0;
	float a = atan(p.y, p.x);
	float ridge = 0.6 + 0.4 * sin(a * 5.0 + 1.0) * sin(a * 3.0 + 2.0) + 0.15 * sin(a * 17.0) + 0.08 * sin(p.x * 0.003 + p.y * 0.002);
	float mountains = smoothstep(1800.0, 4800.0, r) * 900.0 * ridge;
	return bumps + (hills + 6.0) * smoothstep(160.0, 700.0, r) + mountains;
}

// Ridges and gullies on the far mountains only (none near the trees, so the CPU copy can skip it)
float crags(vec2 p) {
	float m = smoothstep(1600.0, 3200.0, length(p));
	if (m <= 0.0) return 0.0;
	float n = textureLod(noise_tex, p * 0.00025, 0.0).r;
	float n2 = textureLod(noise_tex, p * 0.0009 + 0.3, 0.0).r;
	float ridged = 1.0 - abs(n2 * 2.0 - 1.0);
	return m * ((n - 0.5) * 420.0 + ridged * ridged * 160.0);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float e = 3.0 + hole * 30.0;
	float h = terrain(wp.xz) + crags(wp.xz);
	float hx = terrain(wp.xz + vec2(e, 0.0)) + crags(wp.xz + vec2(e, 0.0)) - terrain(wp.xz - vec2(e, 0.0)) - crags(wp.xz - vec2(e, 0.0));
	float hz = terrain(wp.xz + vec2(0.0, e)) + crags(wp.xz + vec2(0.0, e)) - terrain(wp.xz - vec2(0.0, e)) - crags(wp.xz - vec2(0.0, e));
	h -= hole * 3.0 * (1.0 - smoothstep(290.0, 300.0, max(abs(wp.x), abs(wp.z))));
	VERTEX.y += h;
	wnormal = normalize(vec3(-hx, 2.0 * e, -hz));
	NORMAL = (VIEW_MATRIX * vec4(wnormal, 0.0)).xyz;
	world = wp + vec3(0.0, h, 0.0);
}

// Rings spreading from raindrops in a puddle: one drop a cell, each at its own moment
float ripples(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float rnd = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 c = vec2(fract(rnd * 13.7), fract(rnd * 71.3)) * 0.6 + 0.2;
	float t = fract(TIME * 0.9 + rnd);
	float d = length(f - c);
	return step(0.35, fract(rnd * 7.7)) * sin((d - t * 0.45) * 60.0) * (1.0 - smoothstep(0.0, 0.08, abs(d - t * 0.45))) * (1.0 - t);
}

void fragment() {
	vec2 p = world.xz;
	float dist = length(world - CAMERA_POSITION_WORLD);
	float n1 = texture(noise_tex, p * 0.0035).r;
	float n2 = texture(noise_tex, p * 0.031).r;
	float n3 = texture(noise_tex, p * 0.21).r;
	float slope = 1.0 - wnormal.y;
	float alt = world.y;
	// Meadow greens and dry patches, dirt where it's steep, rock and scree up high
	vec3 grass = mix(vec3(0.16, 0.26, 0.09), vec3(0.32, 0.38, 0.14), n2);
	grass = mix(grass, vec3(0.42, 0.36, 0.2), smoothstep(0.55, 0.8, n1) * 0.6);
	grass *= 0.85 + 0.3 * n3;
	vec3 rock = mix(vec3(0.3, 0.29, 0.28), vec3(0.48, 0.46, 0.43), n2);
	vec3 col = mix(grass, rock, clamp(smoothstep(0.18, 0.45, slope) + smoothstep(250.0, 500.0, alt), 0.0, 1.0));
	// Snow caps on the peaks, always
	float cap = smoothstep(600.0, 720.0, alt + n2 * 80.0) * (1.0 - smoothstep(0.3, 0.7, slope));
	// Settling snow: thin at first, patchy, then a blanket; it sits on the flat first
	float lie = snow * 1.25 - (n3 * 0.35 + n2 * 0.25) + (wnormal.y - 0.8) * 0.8;
	float sn = max(cap, smoothstep(0.05, 0.25, lie));
	// Wet: darker, and puddles in the low spots
	float puddle = smoothstep(0.62, 0.7, wet * 0.35 + (1.0 - n2) * 0.55 + (1.0 - n3) * 0.1) * smoothstep(0.75, 0.95, wnormal.y);
	puddle *= 1.0 - sn;
	col *= 1.0 - wet * 0.45;
	// Cloud shadows drifting over
	float cs = texture(noise_tex, p * shadow_scale + shadow_offset).r;
	float shadow = smoothstep(1.0 - shadow_cover, 1.0 - shadow_cover + 0.2, cs) * shadow_amount;
	vec3 snow_col = vec3(0.92, 0.94, 0.98) * (0.92 + 0.08 * n3);
	col = mix(col, snow_col, sn);
	vec3 V = normalize(CAMERA_POSITION_WORLD - world);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(V.y, 0.0, 1.0), 5.0);
	float rip = 0.0;
	if (raining > 0.0 && dist < 60.0) {
		rip = (ripples(p * 1.3) + ripples(p * 1.3 + 0.5)) * raining * (1.0 - dist / 60.0);
	}
	vec3 sky = mix(horizon, zenith, clamp(V.y + rip * 0.15, 0.0, 1.0) * 0.6);
	col = mix(col, col * 0.3, puddle);
	ALBEDO = col * (1.0 - shadow * 0.55);
	ROUGHNESS = mix(mix(0.95, 0.45, wet), 0.05, puddle);
	SPECULAR = mix(0.3, 0.6, wet);
	EMISSION = sky * puddle * (fres * 0.8 + 0.12) * (1.0 + rip * 0.6) + sky * wet * fres * 0.1 * (1.0 - sn);
}
