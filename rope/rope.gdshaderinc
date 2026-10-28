// Shared by rope.gdshader (the tube) and rope_leaf.gdshader (its leaves): where along the
// chain a point is, from the chain's points and frames that RopeLine sends every step.
// Points are world positions (the meshes draw at the world's origin, top_level).

uniform vec3 pts[25];
uniform vec3 nrm[25];
uniform int count = 2;
uniform float rope_length = 1.0;
uniform float r_root = 0.03;
uniform float r_tip = 0.03;
uniform float taper = 1.0;

vec3 rope_pt(int i) {
	// (one past either end: carried on straight, so the curve ends cleanly)
	if (i < 0) {
		return 2.0 * pts[0] - pts[1];
	}
	if (i >= count) {
		return 2.0 * pts[count - 1] - pts[count - 2];
	}
	return pts[i];
}

// Where it is `t` along (0 root .. 1 tip): a Catmull-Rom curve through the points, with its
// tangent and a frame round it (n, and b = t x n) carried smoothly along it.
void rope_frame(float t, out vec3 p, out vec3 tg, out vec3 n, out vec3 b, out int i, out float f) {
	float u = clamp(t, 0.0, 1.0) * float(count - 1);
	i = clamp(int(floor(u)), 0, count - 2);
	f = u - float(i);
	vec3 a = rope_pt(i - 1);
	vec3 c0 = pts[i];
	vec3 c1 = pts[i + 1];
	vec3 d = rope_pt(i + 2);
	float f2 = f * f;
	float f3 = f2 * f;
	p = 0.5 * (2.0 * c0 + (c1 - a) * f + (2.0 * a - 5.0 * c0 + 4.0 * c1 - d) * f2 + (-a + 3.0 * c0 - 3.0 * c1 + d) * f3);
	tg = 0.5 * ((c1 - a) + 2.0 * (2.0 * a - 5.0 * c0 + 4.0 * c1 - d) * f + 3.0 * (-a + 3.0 * c0 - 3.0 * c1 + d) * f2);
	float tl = length(tg);
	tg = tl > 1e-6 ? tg / tl : normalize(c1 - c0 + vec3(0.0, -1e-5, 0.0));
	n = mix(nrm[i], nrm[i + 1], f);
	n = n - tg * dot(n, tg);
	float nl = length(n);
	n = nl > 1e-5 ? n / nl : normalize(cross(tg, abs(tg.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	b = cross(tg, n);
}

float rope_radius(float t) {
	return mix(r_root, r_tip, pow(clamp(t, 0.0, 1.0), taper));
}
