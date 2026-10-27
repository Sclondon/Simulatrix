shader_type spatial;
// Ghost: see-through and unlit, brighter at the silhouette. Swirling 3D noise eats holes in it,
// the lower half frays into wisps, and the vertices sway and bob. Two dark eyes on the front.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

group_uniforms Ghost;
uniform vec3 color : source_color = vec3(0.7, 0.95, 0.9);
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
uniform float edge_glow : hint_range(0.0, 4.0) = 1.8;
uniform float wisps : hint_range(0.0, 1.0) = 0.6;
uniform bool face = true;
group_uniforms Motion;
uniform float sway : hint_range(0.0, 0.5) = 0.15;
uniform float bob : hint_range(0.0, 0.5) = 0.12;
uniform float swirl_speed : hint_range(0.0, 3.0) = 0.8;

varying vec3 lp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	lp = VERTEX;
	float low = clamp(-VERTEX.y, 0.0, 1.0); // the lower half trails more
	VERTEX.x += sin(TIME * 1.3 + VERTEX.y * 3.0) * sway * (0.3 + low);
	VERTEX.z += cos(TIME * 1.1 + VERTEX.y * 2.5) * sway * 0.6 * (0.3 + low);
	VERTEX.y += sin(TIME * 1.7) * bob;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float n = fbm(lp * 2.5 + vec3(0.0, -TIME * swirl_speed, TIME * 0.3));
	float fray = 1.0 - smoothstep(-1.0, -0.1, lp.y);
	float a = opacity * (0.35 + fres * edge_glow) * smoothstep(0.25, 0.5, n + 0.3 - fray * wisps * 0.7);
	vec3 col = color * (0.6 + fres * edge_glow * 0.7);
	if (face && lp.z > 0.5) {
		vec2 e = vec2(abs(lp.x) - 0.3, lp.y - 0.25);
		float eye = 1.0 - smoothstep(0.1, 0.13, length(e * vec2(1.0, 0.8)));
		float mouth = 1.0 - smoothstep(0.1, 0.13, length((lp.xy - vec2(0.0, -0.15)) * vec2(1.0, 0.6)));
		float dark = max(eye, mouth);
		col = mix(col, vec3(0.02, 0.04, 0.05), dark);
		a = mix(a, 0.95, dark);
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
