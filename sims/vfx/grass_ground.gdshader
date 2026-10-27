shader_type spatial;
// Ground under the grass: its root colour, mottled, fading into the fog colour far off.

uniform vec3 ground : source_color = vec3(0.2, 0.31, 0.1);
uniform vec3 far_colour : source_color = vec3(0.6, 0.7, 0.8);
uniform float fade_from = 30.0;
uniform float fade_to = 70.0;

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

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = noise(world.xz * 0.35) * 0.6 + noise(world.xz * 1.7) * 0.4;
	vec3 col = mix(ground, far_colour, 0.15) * (0.75 + 0.45 * n);
	float d = length(world.xz - CAMERA_POSITION_WORLD.xz);
	ALBEDO = mix(col, far_colour, smoothstep(fade_from, fade_to, d) * 0.85);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
