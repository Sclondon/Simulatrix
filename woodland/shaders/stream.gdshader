// A stream, painted: dark peaty water, the warm sky in it where it is seen low, ripples running down it,
// the low sun glittering on it, paler where it runs over stones at its edges. UV.y is metres along it, UV.x
// across. (A still pond is GameCommon's water, a level box; a stream runs downhill, which a box cannot.)
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 sun_dir = vec3(0.0, 0.35, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 deep : source_color = vec3(0.03, 0.035, 0.03);
uniform vec3 shallow : source_color = vec3(0.28, 0.24, 0.14);
uniform vec3 sky : source_color = vec3(0.76, 0.66, 0.48);
uniform vec3 sky_low : source_color = vec3(0.2, 0.17, 0.1);
uniform float speed = 1.6;

varying vec3 world_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float waves(vec2 p) {
	vec2 q = vec2(p.x * 3.0, p.y * 1.4 - TIME * speed);
	return vnoise(q) * 0.6 + vnoise(q * 2.3 + vec2(0.0, -TIME * speed * 0.75)) * 0.4;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float e = 0.05;
	float h = waves(UV);
	vec3 n = normalize(vec3((h - waves(UV + vec2(e, 0.0))) * 1.5, 1.0, (h - waves(UV + vec2(0.0, e))) * 1.5));
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel = pow(1.0 - clamp(dot(to_cam, n), 0.0, 1.0), 3.0);
	vec3 r = reflect(-to_cam, n);
	vec3 reflected = mix(sky_low, sky, smoothstep(-0.05, 0.4, r.y));
	vec3 col = mix(mix(deep, shallow, 0.6), reflected, 0.1 + 0.45 * fresnel);
	// the sun glittering
	col += sun_color * pow(max(dot(r, normalize(sun_dir)), 0.0), 80.0) * 2.2;
	float edge = smoothstep(0.25, 0.0, min(UV.x, 1.0 - UV.x));
	col = mix(col, shallow * 1.4, edge * 0.5 + smoothstep(0.7, 0.9, h) * 0.25);
	ALBEDO = col;
}
