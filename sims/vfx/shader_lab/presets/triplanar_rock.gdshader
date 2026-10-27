shader_type spatial;
// Triplanar rock: procedural noise sampled on the three world planes (YZ, XZ, XY) and blended by
// the normal, so the mesh needs no UVs and nothing stretches. Voronoi edges cut cracks, moss
// grows on the faces that point up, and the height bumps the normal using screen derivatives.

group_uniforms Rock;
uniform float scale : hint_range(0.5, 10.0) = 2.5;
uniform vec3 rock_light : source_color = vec3(0.62, 0.58, 0.52);
uniform vec3 rock_dark : source_color = vec3(0.25, 0.23, 0.22);
uniform float cracks : hint_range(0.0, 1.0) = 0.6;
uniform float blend_sharpness : hint_range(1.0, 16.0) = 6.0;
uniform float bump : hint_range(0.0, 1.0) = 0.5;
group_uniforms Moss;
uniform vec3 moss : source_color = vec3(0.3, 0.45, 0.15);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.5;

varying vec3 wpos;
varying vec3 wnorm;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p);
		p = p * 2.07 + vec2(1.3, 7.1);
		a *= 0.5;
	}
	return v / 0.97;
}

// distance to the nearest Voronoi edge (F2 - F1)
float cell_edge(vec2 p) {
	vec2 c = floor(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = c + vec2(float(x), float(y));
			float d = length(p - g - hash2(g));
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

float rock(vec2 p) {
	float n = fbm2(p * scale);
	float crack = smoothstep(0.0, 0.12, cell_edge(p * scale * 0.7));
	return mix(n, n * crack, cracks);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wnorm), vec3(blend_sharpness));
	w /= (w.x + w.y + w.z);
	float h = rock(wpos.zy) * w.x + rock(wpos.xz) * w.y + rock(wpos.xy) * w.z;
	vec3 col = mix(rock_dark, rock_light, smoothstep(0.2, 0.8, h));
	float m = smoothstep(1.0 - moss_amount, 1.0 - moss_amount + 0.3, wnorm.y + (h - 0.5) * 0.6);
	col = mix(col, moss * (0.7 + 0.6 * h), m);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 1.0, m);
	// bump mapping from screen-space derivatives (Mikkelsen's surface gradient)
	float hb = h * bump * 0.05;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(hb) * r1 + dFdy(hb) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
