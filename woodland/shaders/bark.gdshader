// Trunks, branches and roots, painted. Dark bark is cut into long plates by deep furrows that follow the
// trunk's twist; `birch` gives an aspen's pale bark with its dark "eyes" (almond scars where branches
// were, each with a brow), short dark lenticels, and black, rough bark at the foot. A warm edge on the
// side to the sun, darker at the foot. Lit by hand, like the leaves.
// UV.x runs round the wood (0..1), UV.y up it in metres. CUSTOM0: r how far out on the tree (0 trunk
// foot .. 1 twig), g the tree's girth (foot radius, metres), b how far round the ropes have turned.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 sun_dir = vec3(0.0, 0.35, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.82, 0.5);
uniform vec3 bark : source_color = vec3(0.27, 0.19, 0.13);
uniform vec3 bark_light : source_color = vec3(0.4, 0.3, 0.2);
uniform vec3 bark_dark : source_color = vec3(0.06, 0.045, 0.035);
uniform float birch = 0.0;
uniform float moss = 0.0;
// metres across a plate of bark
uniform float plate = 0.14;

varying vec3 world_normal;
varying vec3 world_pos;
varying vec4 wood;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Plates of bark: cells long up the trunk. x how near a furrow (0 in it), y the plate's own shade
vec2 plates(vec2 q) {
	vec2 g = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 c = o + hash2(g + o) * vec2(0.8, 0.9) - f;
			c.y *= 0.35;
			float d = dot(c, c);
			if (d < d1) { d2 = d1; d1 = d; id = g + o; }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), hash(id));
}

// An aspen's eyes, in metres round (x) and up (y): 0 bare bark, 1 the dark of an eye or its brow
float eyes(vec2 q) {
	vec2 cell = vec2(0.32, 0.5);
	vec2 g = floor(q / cell);
	float dark = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = g + vec2(float(i), float(j));
			float h = hash(id * 1.31 + 4.0);
			if (h < 0.45) {
				continue;
			}
			vec2 c = (id + vec2(0.5) + (hash2(id) - 0.5) * 0.6) * cell;
			float w = mix(0.04, 0.12, hash(id + 9.0));
			vec2 d = q - c;
			d.x /= w;
			d.y /= w * 0.42;
			// the almond: pointed at both ends, a little heavier underneath
			float lid = 1.0 - d.x * d.x;
			float eye = step(abs(d.y + 0.15 * d.x * d.x), max(lid, 0.0));
			// the brow: a chevron above it, sloping down to both sides
			float bx = (q.x - c.x) / (w * 1.6);
			float by = (q.y - c.y - w * 0.9) / w;
			float brow = step(abs(by + abs(bx) * 0.55), 0.1) * step(abs(bx), 1.0) * step(0.7, h);
			dark = max(dark, max(eye, brow * 0.85));
		}
	}
	return dark;
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wood = CUSTOM0;
}

// The bark's look at a point `around` metres round and `h` up: colour, and how deep in a furrow
vec4 bark_at(float around, float h, float outness) {
	vec3 col;
	float groove = 0.0;
	if (birch > 0.5) {
		vec2 q = vec2(around, h);
		vec3 pale = mix(vec3(0.82, 0.8, 0.7), vec3(0.72, 0.74, 0.62), vnoise(q * vec2(3.0, 0.8)));
		// faint horizontal lenticels
		float dash = step(0.82, vnoise(vec2(around * 7.0, h * 40.0))) * step(0.4, vnoise(q * 4.0));
		col = mix(pale, pale * 0.7, dash * 0.4);
		float e = eyes(q);
		col = mix(col, bark_dark * 1.4, e);
		// the foot: black, cracked, in ragged bands that climb a little way
		float foot = smoothstep(1.6, 0.2, h + (vnoise(vec2(around * 3.0, 0.0)) - 0.5) * 1.2);
		vec2 pl = plates(vec2(around / 0.08, h / 0.2));
		vec3 rough = mix(bark_dark * 1.6, bark * 0.7, smoothstep(0.0, 0.35, pl.x));
		col = mix(col, rough, foot);
		// and a few black bands higher up, partly round
		float band = step(0.72, vnoise(vec2(around * 2.0, h * 1.6))) * step(0.5, vnoise(vec2(around * 6.0 + 3.0, h * 0.9)));
		col = mix(col, bark_dark * 1.2, band * (1.0 - foot));
		groove = foot * (1.0 - smoothstep(0.05, 0.25, pl.x));
	} else {
		// smoother bark out on the twigs
		float size = plate * mix(1.0, 0.45, outness);
		vec2 pl = plates(vec2(around / size, h / (size * 3.2)));
		float edge = smoothstep(0.0, 0.3, pl.x);
		vec3 face = mix(bark, bark_light, pl.y * 0.3 + vnoise(vec2(around * 8.0, h * 1.5)) * 0.15);
		// the furrows only a little darker than the plates: a soft pattern, not a busy one
		col = mix(mix(bark_dark, bark, 0.5), face, edge);
		groove = 1.0 - edge;
	}
	return vec4(col, groove);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 sun = normalize(sun_dir);
	float h = UV.y;
	float girth = max(wood.g, 0.05);
	float circ = 6.2832 * girth;
	// round the wood in metres, following the twist; drawn twice and blended across the seam
	float u = UV.x + wood.b;
	vec4 a = bark_at(u * circ, h, wood.r);
	vec4 b = bark_at((u - 1.0) * circ, h, wood.r);
	vec4 bk = mix(a, b, smoothstep(0.8, 1.0, UV.x));
	vec3 col = bk.rgb;
	// moss on the side away from the sun and low down
	float mossy = moss * smoothstep(0.1, 0.6, -dot(n, sun) + 0.2) * smoothstep(4.0, 0.5, h) * step(0.45, vnoise(vec2(UV.x * 10.0, h * 3.0)));
	col = mix(col, vec3(0.32, 0.33, 0.12), mossy * 0.8 * (1.0 - birch));
	// light: a soft wrap, a bright rim on the sun side, the foot in shadow, furrows darker still
	float wrap = clamp(dot(n, sun) * 0.6 + 0.4, 0.0, 1.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	float rim = pow(1.0 - clamp(dot(n, to_cam), 0.0, 1.0), 3.0) * clamp(dot(n, sun) + 0.5, 0.0, 1.0);
	float foot = mix(0.55, 1.0, smoothstep(0.0, 2.5, h));
	vec3 lit = col * (0.42 + 0.75 * wrap * sun_color) * foot;
	lit += sun_color * rim * 0.35 * (1.0 - bk.a * 0.5);
	ALBEDO = lit;
}
