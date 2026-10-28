shader_type spatial;
// The Rope Lab's seabed: rippled sand, mottled with weed and shade, under moving caustics
// (light focused by the waves overhead), fading into the water's colour far off.

uniform vec3 sand : source_color = vec3(0.62, 0.56, 0.4);
uniform vec3 weed : source_color = vec3(0.3, 0.32, 0.18);
uniform vec3 caustic_colour : source_color = vec3(0.75, 0.95, 1.0);
uniform float caustics = 0.6;

varying vec3 world;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A web of bright lines: two layers of warped ridged noise drifting against each other.
float web(vec2 p, float t) {
	vec2 w = p + vec2(noise(p * 0.7 + t * 0.3), noise(p * 0.7 - t * 0.27 + 5.0)) * 1.6;
	float a = 1.0 - abs(noise(w * 1.3 + t * 0.2) * 2.0 - 1.0);
	float b = 1.0 - abs(noise(w * 1.7 - t * 0.25 + 9.0) * 2.0 - 1.0);
	return pow(a * b, 6.0);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float n = noise(p * 0.25) * 0.6 + noise(p * 1.3) * 0.4;
	float ripple = sin(p.x * 3.1 + noise(p * 0.5) * 6.0) * 0.5 + 0.5;
	vec3 col = mix(sand, weed, smoothstep(0.55, 0.8, noise(p * 0.18 + 3.0)) * 0.7);
	col *= 0.7 + 0.35 * n + 0.08 * ripple;
	float c = web(p * 0.55, TIME * 0.6);
	ALBEDO = col;
	EMISSION = caustic_colour * c * caustics * col * 1.6;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
