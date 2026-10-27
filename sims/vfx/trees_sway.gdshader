// Tree Lab's tree material: the generated trees' sRGB vertex colours, swayed by the wind.
// LeafyTree carries how much each corner sways in UV2.y; a PineTree has no UV2, so with `pine` on
// the sway is worked out from height up the tree and reach from the trunk.
// `view`: 0 shaded, 1 the bent normals, 2 the sway weights as a heat ramp, 3 dimmed (under the wire),
// 4 flat wire colour.
shader_type spatial;
render_mode cull_disabled;

uniform float wind = 0.35;
uniform float tree_height = 8.0;
uniform float pine = 0.0;
uniform int view = 0;
uniform vec3 wire_color : source_color = vec3(0.35, 0.85, 1.0);
// 0 soft wrapped light, 1 two-tone cel shading as the games draw these trees
uniform float toon = 0.0;

varying float sway_w;
varying vec3 world_normal;

void vertex() {
	float w = UV2.y;
	if (pine > 0.5) {
		float h = clamp(VERTEX.y / tree_height, 0.0, 1.0);
		float r = clamp(length(VERTEX.xz) / (tree_height * 0.2), 0.0, 1.0);
		w = h * h * 0.7 + r * h * 0.5;
	}
	sway_w = w;
	vec3 root = MODEL_MATRIX[3].xyz;
	float phase = dot(root.xz, vec2(0.13, 0.21));
	float t = TIME;
	// a slow lean that comes and goes in gusts, and a quick flutter over the leaves
	float gust = 0.55 + 0.45 * sin(t * 0.7 + phase) * sin(t * 0.27 + phase * 1.7);
	vec3 lean = normalize(vec3(1.0, 0.0, 0.35)) * gust * (0.6 + 0.4 * sin(t * 1.9 + phase * 3.0));
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 flutter = vec3(sin(t * 6.1 + wp.y * 2.3 + wp.x * 3.1), 0.6 * sin(t * 5.3 + wp.z * 2.9), cos(t * 5.7 + wp.x * 2.6));
	float scale = length(MODEL_MATRIX[1].xyz);
	vec3 off = (lean * w * w * tree_height * 0.07 + flutter * smoothstep(0.15, 0.4, w) * 0.05) * wind * scale;
	off.y -= length(off.xz) * 0.25 * w;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	if (view == 1) {
		ALBEDO = vec3(0.0);
		EMISSION = pow(world_normal * 0.5 + 0.5, vec3(2.2));
	} else if (view == 2) {
		ALBEDO = vec3(0.0);
		vec3 cold = vec3(0.05, 0.1, 0.45);
		vec3 mid = vec3(0.1, 0.75, 0.3);
		vec3 hot = vec3(1.0, 0.35, 0.05);
		EMISSION = sway_w < 0.5 ? mix(cold, mid, sway_w * 2.0) : mix(mid, hot, sway_w * 2.0 - 1.0);
	} else if (view == 3) {
		ALBEDO = base * 0.25;
	} else if (view == 4) {
		ALBEDO = vec3(0.0);
		EMISSION = wire_color;
	} else {
		ALBEDO = base;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// half-Lambert: the bent normals wrap light round the crown like one soft shape
	float soft = pow(clamp(ndl * 0.5 + 0.5, 0.0, 1.0), 1.6) * ATTENUATION;
	float cel = mix(0.38, 1.0, smoothstep(0.0, 0.06, ndl) * step(0.5, ATTENUATION));
	DIFFUSE_LIGHT += LIGHT_COLOR * mix(soft, cel, toon) / PI;
}
