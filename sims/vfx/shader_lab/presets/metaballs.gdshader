shader_type canvas_item;
// Raymarched metaballs: a signed distance field of spheres blended with a smooth minimum,
// marched per pixel from a camera. Your finger drags one more blob around.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Blobs;
uniform int count : hint_range(2, 8) = 5;
uniform float smoothness : hint_range(0.05, 1.5) = 0.6;
uniform float speed : hint_range(0.0, 2.0) = 0.7;
group_uniforms Look;
uniform vec3 base_color : source_color = vec3(0.95, 0.35, 0.55);
uniform vec3 rim_color : source_color = vec3(0.4, 0.8, 1.0);
uniform float gloss : hint_range(2.0, 128.0) = 48.0;

// polynomial smooth minimum: blends two distances over a width k
float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float scene(vec3 p) {
	float d = 100000.0;
	for (int i = 0; i < 8; i++) {
		if (i >= count) {
			break;
		}
		float fi = float(i);
		vec3 c = vec3(sin(TIME * speed * (0.7 + fi * 0.13) + fi * 2.1),
			cos(TIME * speed * (0.5 + fi * 0.17) + fi * 1.3),
			sin(TIME * speed * (0.3 + fi * 0.11) + fi * 4.0) * 0.6) * 1.1;
		d = smin(d, length(p - c) - (0.45 + 0.1 * sin(fi)), smoothness);
	}
	float aspect = resolution.x / resolution.y;
	vec3 finger = vec3((mouse - 0.5) * vec2(aspect, -1.0) * (5.0 / 1.4), 0.0);
	return smin(d, length(p - finger) - 0.35, smoothness);
}

vec3 normal_at(vec3 p) {
	vec2 e = vec2(0.002, 0.0);
	return normalize(vec3(scene(p + e.xyy) - scene(p - e.xyy),
		scene(p + e.yxy) - scene(p - e.yxy),
		scene(p + e.yyx) - scene(p - e.yyx)));
}

void fragment() {
	vec2 uv = (UV - 0.5) * vec2(resolution.x / resolution.y, -1.0);
	vec3 ro = vec3(0.0, 0.0, 5.0);
	vec3 rd = normalize(vec3(uv, -1.4));
	float t = 0.0;
	bool hit = false;
	for (int i = 0; i < 64; i++) {
		float d = scene(ro + rd * t);
		if (d < 0.002) {
			hit = true;
			break;
		}
		t += d;
		if (t > 12.0) {
			break;
		}
	}
	vec3 col = mix(vec3(0.16, 0.17, 0.22), vec3(0.07, 0.08, 0.11), UV.y);
	if (hit) {
		vec3 p = ro + rd * t;
		vec3 n = normal_at(p);
		vec3 l = normalize(vec3(0.6, 0.8, 0.5));
		float diff = max(dot(n, l), 0.0);
		float spec = pow(max(dot(reflect(-l, n), -rd), 0.0), gloss);
		float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
		col = base_color * (0.15 + 0.85 * diff) + vec3(spec) + rim_color * rim;
	}
	COLOR = vec4(col, 1.0);
}
