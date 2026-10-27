shader_type spatial;
// For GameCommon's PineTree and LeafyTree (vertex colours, normals bent out of the crown) and the
// rocks: sways in the wind (a leafy tree by its UV2.y, a pine by height), darkens when wet, and
// takes snow on whatever faces up.

uniform vec3 tint : source_color = vec3(1.0);
uniform float use_uv2 = 0.0;
uniform float tree_height = 10.0;
uniform float wind = 0.0;           // m/s
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wet = 0.0;
uniform float snow = 0.0;

varying vec3 wnormal;

void vertex() {
	float sway = use_uv2 > 0.5 ? UV2.y : pow(clamp(VERTEX.y / tree_height, 0.0, 1.0), 2.0);
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.13 + origin.z * 0.09;
	float s = wind / 12.0;
	float gust = 0.6 + 0.4 * sin(TIME * 0.7 + phase * 0.3);
	float bend = s * s * gust * 0.8 + s * 0.12 * sin(TIME * (1.6 + s) + phase);
	float flutter = s * 0.05 * sin(TIME * 9.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + phase) * (use_uv2 > 0.5 ? UV2.y : 0.0);
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (bend * sway * tree_height * 0.12) + vec3(0.0, flutter, 0.0);
	off.y -= length(off.xz) * 0.25 * sway;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2)) * tint;
	float n = fract(sin(dot(floor(wnormal * 9.0), vec3(12.9, 78.2, 37.7))) * 43758.5);
	float sn = smoothstep(0.25, 0.75, wnormal.y + snow * 1.1 - 0.75 - n * 0.15) * step(0.01, snow);
	base *= 1.0 - wet * 0.35;
	ALBEDO = mix(base, vec3(0.9, 0.92, 0.96), sn);
	ROUGHNESS = mix(0.95, 0.5, wet);
	SPECULAR = mix(0.2, 0.5, wet);
}
