shader_type spatial;
// The Weather Lab's land: a flat meadow, rolling hills, a ring of mountains, with GameCommon weather's
// ground_weather on top (wet, puddles that mirror the sky and ring with drops, settling snow, cloud
// shadows; WeatherRig.register keeps it set). The height must match terrain() in weather.gd.

#include "res://weather/ground_weather.gdshaderinc"

uniform float hole = 0.0;            // sink the middle (the far mesh, under the near one)

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
	float rough;
	float spec;
	vec3 emit;
	weather_ground_cap(world, wnormal, CAMERA_POSITION_WORLD, col, n2, n3, cap, rough, spec, emit);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emit;
}
