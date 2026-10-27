shader_type canvas_item;
// Fire: fractal noise scrolls upward through a flame-shaped mask. The result is a temperature,
// and a three-colour ramp turns it into flame. The flame leans toward your finger.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Flame;
uniform float height : hint_range(0.2, 1.5) = 0.75;
uniform float width : hint_range(0.1, 1.0) = 0.3;
uniform float speed : hint_range(0.0, 4.0) = 1.6;
uniform float turbulence : hint_range(0.0, 2.0) = 1.0;
group_uniforms Colour;
uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.7);
uniform vec3 mid : source_color = vec3(1.0, 0.45, 0.08);
uniform vec3 cool : source_color = vec3(0.5, 0.05, 0.02);
uniform bool pixelate = false;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// fractal Brownian motion: five octaves, each twice as fine and half as strong
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	if (pixelate) {
		uv = (floor(uv * 72.0) + 0.5) / 72.0;
	}
	float aspect = resolution.x / resolution.y;
	vec2 p = vec2((uv.x - 0.5) * aspect, 1.0 - uv.y); // x across, y up from the bottom edge
	p.x -= (mouse.x - 0.5) * p.y * 0.8;
	float t = TIME * speed;
	float n = fbm(vec2(p.x * 4.0, p.y * 3.0 - t));
	float n2 = fbm(vec2(p.x * 8.0 + 3.1, p.y * 6.0 - t * 1.7));
	p.x += (n - 0.5) * 0.25 * turbulence * p.y;
	float y = p.y / height;
	float x = p.x / width;
	float body = 1.0 - (x * x * 3.0 + y * 1.2); // hottest at the base, in the middle
	float heat = clamp(body + (n2 - 0.5) * turbulence * (0.2 + y * 0.9), 0.0, 1.0);
	vec3 col = mix(cool, mid, smoothstep(0.05, 0.45, heat));
	col = mix(col, hot, smoothstep(0.5, 0.9, heat));
	float alpha = smoothstep(0.02, 0.15, heat);
	vec3 bg = vec3(0.04, 0.035, 0.045) + vec3(0.25, 0.08, 0.02) * exp(-length(vec2(p.x, p.y - 0.1)) * 3.0) * 0.5;
	COLOR = vec4(mix(bg, col, alpha), 1.0);
}
