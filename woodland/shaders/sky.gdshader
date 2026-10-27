// The sky, painted: creamy gold low down where the sun is, cooling to a pale grey-blue overhead, a soft
// glow round the low sun, and long thin cloud streaks lit underneath.
shader_type sky;

uniform vec3 sun_dir = vec3(0.0, 0.35, -1.0);
uniform vec3 horizon : source_color = vec3(0.96, 0.84, 0.62);
uniform vec3 zenith : source_color = vec3(0.6, 0.64, 0.68);
uniform vec3 glow : source_color = vec3(1.0, 0.86, 0.55);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = normalize(sun_dir);
	float up = clamp(d.y, 0.0, 1.0);
	float towards = clamp(dot(d, sun), 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.6));
	// warmer all round the side the sun is on
	col = mix(col, glow, pow(towards, 3.0) * 0.5);
	col += glow * pow(towards, 40.0) * 0.6;
	// streaks of cloud, long across the sky
	vec2 q = d.xz / max(d.y + 0.15, 0.05);
	float cloud = smoothstep(0.55, 0.85, vnoise(q * vec2(0.6, 3.0) + vec2(TIME * 0.004, 0.0)) * 0.7 + vnoise(q * 2.0) * 0.3);
	col = mix(col, mix(vec3(0.85, 0.7, 0.55), glow, pow(towards, 2.0)), cloud * smoothstep(0.02, 0.2, d.y) * 0.5);
	COLOR = col;
}
