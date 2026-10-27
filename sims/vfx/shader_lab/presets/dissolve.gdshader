shader_type spatial;
// Dissolve: 3D noise in the mesh's own space against a threshold. Fragments below it are
// discarded; a thin band just above it glows like burning paper. Back faces are drawn so you
// can see inside. Turn Animate off to scrub Amount by hand.
render_mode cull_disabled;

group_uniforms Dissolve;
uniform float amount : hint_range(0.0, 1.0) = 0.5;
uniform bool animate = true;
uniform float noise_scale : hint_range(0.5, 10.0) = 3.0;
uniform float edge_width : hint_range(0.0, 0.2) = 0.05;
group_uniforms Colour;
uniform vec3 surface : source_color = vec3(0.75, 0.75, 0.8);
uniform vec3 edge_color : source_color = vec3(1.0, 0.45, 0.05);
uniform float glow : hint_range(0.0, 10.0) = 4.0;

varying vec3 local_pos;

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
	local_pos = VERTEX;
}

void fragment() {
	float t = animate ? 0.5 + 0.45 * sin(TIME * 0.6) : amount;
	float n = fbm(local_pos * noise_scale);
	float cut = mix(0.08, 0.85, t); // fbm mostly lies between these
	if (n < cut) {
		discard;
	}
	float e = 1.0 - smoothstep(cut, cut + edge_width, n);
	vec3 col = mix(surface, edge_color, e);
	ALBEDO = FRONT_FACING ? col : col * 0.4;
	EMISSION = edge_color * e * glow;
	ROUGHNESS = 0.5;
}
