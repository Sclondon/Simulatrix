// The sky: NASA's Deep Star Maps (as in Atlas and Close Encounters), darkened between the
// stars with the bright ones twinkling, and the sun as a white-hot disc in a wide glow.
shader_type sky;

uniform sampler2D star_map : source_color, filter_linear, repeat_enable;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float star_gain = 0.45;
uniform vec3 space : source_color = vec3(0.006, 0.008, 0.02);
const float SUN_SIZE = 0.05;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 look = EYEDIR;
	vec2 uv = vec2(0.5 - atan(look.x, look.z) / TAU, 0.5 - asin(clamp(look.y, -1.0, 1.0)) / PI);
	vec3 field = pow(texture(star_map, uv).rgb, vec3(2.6)) * 1.3;
	float bright = max(field.r, max(field.g, field.b));
	vec2 cell = floor(uv * 2048.0);
	float twinkle = 1.0 + smoothstep(0.35, 0.9, bright) * 0.45 * sin(TIME * (2.0 + hash(vec3(cell, 1.0)) * 7.0) + hash(vec3(cell, 3.0)) * 40.0);
	vec3 col = space + field * (star_gain + smoothstep(0.15, 0.6, bright) * 3.5) * twinkle;
	vec3 sun = normalize(sun_dir);
	float off = acos(clamp(dot(look, sun), -1.0, 1.0));
	col *= 1.0 - smoothstep(0.5, 0.0, off) * 0.85;
	col += vec3(1.0, 0.84, 0.58) * (exp(-off * off / 0.02) * 0.9 + exp(-off / 0.14) * 0.3);
	col = mix(col, vec3(1.0, 0.97, 0.88) * (1.2 - 0.3 * pow(off / SUN_SIZE, 2.0)), smoothstep(SUN_SIZE, SUN_SIZE * 0.9, off));
	COLOR = col;
}
