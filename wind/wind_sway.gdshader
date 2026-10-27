shader_type spatial;
render_mode cull_disabled;
// A tree (or anything tall) swaying in a WindField (WindField.sway_material() makes one and keeps it
// set): GameCommon's LeafyTree and PineTree meshes, vertex colours (sRGB). LeafyTree says in UV2.y how
// much each corner sways; for anything else `sway_by_height` (its height, m) sways it by height. The
// whole tree leans with the gust at its foot (the same gust noise as WindField.gust() and GameCommon's
// grass), the crown flutters with turbulence, and blasts throw it back.
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind = 0.45; // as the grass's `wind`
uniform float gust_size = 16.0;
uniform float gust_speed = 5.0;
uniform float gustiness = 0.6;
uniform float turbulence = 0.3;
uniform float sway_by_height = 0.0; // the tree's height in metres, or 0 to read UV2.y
uniform vec4 blasts[4];
uniform float blast_speed = 9.0;
uniform float wrap = 0.25;

varying vec3 v_colour;
varying float v_sway;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 whole = floor(p);
	vec2 part = fract(p);
	part = part * part * (3.0 - 2.0 * part);
	return mix(mix(hash(whole), hash(whole + vec2(1.0, 0.0)), part.x),
			mix(hash(whole + vec2(0.0, 1.0)), hash(whole + vec2(1.0, 1.0)), part.x), part.y);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sway_by_height > 0.0 ? pow(clamp(VERTEX.y / sway_by_height, 0.0, 1.0), 1.6) : UV2.y;
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	vec2 g = root.xz / gust_size - wd * TIME * gust_speed / gust_size;
	float gust = smoothstep(0.25, 0.85, noise(g) * 0.65 + noise(g * 2.3 + 7.0) * 0.35);
	float push = wind * (0.35 + gustiness * 1.4 * gust + (1.0 - gustiness) * 0.4);
	// a slow rocking back against the lean, quicker the harder it blows
	float rock = sin(TIME * (1.1 + wind * 0.8) + root.x * 0.3 + root.z * 0.2) * (0.25 + turbulence);
	vec2 bend = wd * push * (1.0 + rock * 0.35);
	for (int i = 0; i < 4; i++) {
		vec4 b = blasts[i];
		float age = TIME - b.z;
		if (b.w <= 0.0 || age < 0.0 || age > 3.0) {
			continue;
		}
		vec2 away = root.xz - b.xy;
		float dist = length(away);
		float ring = exp(-pow((dist - age * blast_speed) / 2.5, 2.0));
		bend += away / max(dist, 0.001) * ring * b.w * (1.0 - smoothstep(0.0, 3.0, age)) * 1.6 / (1.0 + dist * 0.06);
	}
	// leaves flutter on their own, faster and wider with turbulence
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float f = sin(TIME * (6.0 + 6.0 * turbulence) + w.x * 3.1 + w.y * 2.3 + w.z * 2.7);
	vec3 flutter = vec3(f, f * 0.5, -f) * (0.03 + 0.08 * turbulence) * (0.3 + push);
	vec3 shift = vec3(bend.x, 0.0, bend.y) * 0.9 * sway;
	shift.y -= dot(bend, bend) * 0.2 * sway * sway; // bending, it dips
	VERTEX += (inverse(MODEL_MATRIX) * vec4(shift + flutter * sway, 0.0)).xyz;
	v_colour = pow(COLOR.rgb, vec3(2.2));
	v_sway = sway;
}

void fragment() {
	ALBEDO = v_colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float towards = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.08, (towards + wrap) / (1.0 + wrap)) * ATTENUATION;
	DIFFUSE_LIGHT += mix(clamp(towards, 0.0, 1.0) * ATTENUATION, lit, 0.7) * LIGHT_COLOR / PI;
}
