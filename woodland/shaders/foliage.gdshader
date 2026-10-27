// A clump of autumn leaves as a card that always faces the camera, painted in dabs: each cell of a
// Voronoi pattern is one leaf of the tree's own shape and shade, the outline ragged with strays, dark
// twigs reaching out through the gaps.
// Lit by hand, not by the engine: lighter on the side to the sun, glowing when the sun is behind it.
// INSTANCE_CUSTOM: x size, y the leaf (whole part: 0 beech, 1 oak, 2 maple, 3 aspen, 4 birch) and hue (fraction: 0 gold .. rust),
// z how lit it is (0 deep inside the crown .. 1 out in the sun), w a seed.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec3 sun_dir = vec3(0.0, 0.35, -1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.55);
uniform vec3 gold : source_color = vec3(0.93, 0.68, 0.24);
uniform vec3 orange : source_color = vec3(0.84, 0.43, 0.13);
uniform vec3 rust : source_color = vec3(0.52, 0.24, 0.10);
uniform vec3 shade : source_color = vec3(0.17, 0.11, 0.07);
uniform float leaf_scale = 11.0;
// the real leaves (leaf_atlas.gd): beech, oak, maple, aspen, birch in a row
uniform sampler2D leaf_atlas : filter_linear_mipmap, repeat_disable;
// 0 leaves, 1 dry grass and bracken (blades instead of leaves)
uniform float blades = 0.0;
uniform float sway = 1.0;
uniform float darkness = 0.0;

varying vec4 custom;
varying vec3 world_pos;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float hash1(float n) { return fract(sin(n) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	custom = INSTANCE_CUSTOM;
	float size = custom.x;
	// a clump right by the camera would fill the view with one leaf: it shrinks away
	size *= smoothstep(1.2, 3.5, distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD));
	vec3 centre = MODEL_MATRIX[3].xyz;
	float t = TIME * 0.9 + custom.w * 40.0;
	vec3 wind = vec3(sin(t) + 0.4 * sin(t * 2.3), 0.15 * sin(t * 1.7), 0.5 * cos(t * 0.8)) * 0.06 * size * sway;
	centre += wind * (blades > 0.5 ? max(VERTEX.y + 0.5, 0.0) * 2.0 : 1.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	if (blades > 0.5) {
		// grass stands up: turn to the camera about the vertical only
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
		centre.y += size * 0.5;
	}
	float spin = (custom.w - 0.5) * 1.2;
	vec2 v = VERTEX.xy;
	if (blades < 0.5) {
		v = vec2(v.x * cos(spin) - v.y * sin(spin), v.x * sin(spin) + v.y * cos(spin));
	}
	world_pos = centre + (right * v.x + up * v.y) * size;
	// each card a step nearer or further than its neighbours, so where they cross they do not flicker
	world_pos += normalize(CAMERA_POSITION_WORLD - centre) * (custom.w - 0.5) * size * 0.8;
	// instances carry no rotation or scale, so world to model is only the offset
	VERTEX = world_pos - MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 uv = UV;
	float seed = custom.w * 97.0;
	vec3 view_to_cam = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 sun = normalize(sun_dir);
	// the clump's own light: z, plus the upper side and the side towards the sun
	float lit = custom.z;
	vec2 sun_on_card = vec2(dot(sun, INV_VIEW_MATRIX[0].xyz), dot(sun, INV_VIEW_MATRIX[1].xyz));
	float backlit = clamp(dot(-view_to_cam, sun), 0.0, 1.0);
	backlit = pow(backlit, 3.0);

	float alpha;
	float tone;
	if (blades < 0.5) {
		vec2 p = (uv - 0.5) * 2.0;
		float r = length(p);
		float ang = atan(p.y, p.x);
		float edge = 0.7 + 0.24 * vnoise(vec2(ang * 1.6 + seed, seed)) + 0.06 * sin(ang * 13.0 + seed);
		// the tree's own leaf: 0 beech, 1 oak, 2 maple, 3 aspen, 4 birch
		float shape = floor(custom.y);
		float scale = leaf_scale * (shape < 0.5 ? 1.0 : (shape < 1.5 ? 0.85 : (shape < 2.5 ? 0.72 : (shape < 3.5 ? 1.3 : 1.15))));
		// one leaf per cell, at a slant of its own; where leaves overlap, the higher numbered one is in front.
		// Leaves out past the clump's edge are fewer, so the outline is ragged with strays.
		vec2 g = uv * scale + seed;
		vec2 gi = floor(g);
		vec2 gf = fract(g);
		float front = -1.0;
		float along = 0.0;
		float vein = 0.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 o = vec2(float(i), float(j));
				vec2 h = hash2(gi + o);
				vec2 d = gf - (o + h);
				float a = h.x * 6.283 + h.y * 3.0;
				vec2 q = vec2(d.x * cos(a) + d.y * sin(a), -d.x * sin(a) + d.y * cos(a));
				// cut from the real leaf in the sheet: its tip along +q.x, a little over a cell long
				vec2 lu = vec2(0.5 + q.y / 1.3, 0.5 - q.x / 1.3);
				float t = 1.0 - lu.y * 2.0;
				vec4 cut = vec4(0.0);
				if (lu.x > 0.0 && lu.x < 1.0 && lu.y > 0.0 && lu.y < 1.0) {
					cut = textureLod(leaf_atlas, vec2((shape + lu.x) / 5.0, lu.y), 1.0);
				}
				bool in_leaf = cut.a > 0.5;
				vec2 leaf_uv = (gi + o + h - seed) / scale;
				float lr = length((leaf_uv - 0.5) * 2.0);
				bool kept = lr < edge || (lr < edge + 0.22 && hash2(gi + o + 5.0).x < 0.3);
				if (in_leaf && kept) {
					float id = hash2(gi + o + 17.0).x;
					if (id > front) {
						front = id;
						along = clamp(t, -1.0, 1.0);
						vein = 1.0 - cut.r;
					}
				}
			}
		}
		// twigs out through the clump, dark, seen in its gaps
		float twig = 0.0;
		for (int k = 0; k < 5; k++) {
			float ta = custom.w * 40.0 + float(k) * 1.37 + float(k * k) * 0.5;
			vec2 dir = vec2(cos(ta), sin(ta));
			float s = clamp(dot(p, dir), 0.0, 0.95);
			vec2 bend = vec2(-dir.y, dir.x) * sin(s * 4.0 + float(k)) * 0.06;
			float dist = length(p - dir * s - bend);
			twig = max(twig, step(dist, 0.03 * (1.0 - s * 0.7)) * step(0.02, dot(p, dir)));
		}
		// the dark inside of the clump, with holes in it
		bool in_middle = r < edge - 0.2 && vnoise(uv * 7.0 + seed) > 0.3;
		alpha = (front >= 0.0 || in_middle || twig > 0.5) ? 1.0 : 0.0;
		// shading across the clump: down-and-away from the sun is the dark inside
		float side = dot(p, normalize(sun_on_card + vec2(0.0, 0.6))) * 0.5 + 0.5;
		tone = lit * 0.6 + side * 0.4 - r * 0.3;
		if (front >= 0.0) {
			tone += (front - 0.5) * 0.4 + along * 0.08 - vein * 0.5;
		} else {
			tone = tone * 0.35 - 0.15;
		}
		tone = clamp(tone, 0.0, 1.0);
	} else {
		// dry grass: thin tapering blades leaning this way and that
		float x = uv.x * 13.0 + seed;
		float top = 1.0 - uv.y;
		alpha = 0.0;
		tone = 0.0;
		// two staggered rows of blades, so they cross
		for (int row = 0; row < 2; row++) {
			float xr = x + float(row) * 0.5;
			float col = floor(xr);
			float h = hash1(col + float(row) * 31.0);
			float lean = (hash1(col + 3.1 + float(row) * 7.0) - 0.5) * 0.25;
			float bx = fract(xr + lean * top * top * 13.0) - 0.5;
			float height = 0.3 + 0.7 * h * h;
			float width = 0.16 * (1.0 - top / height);
			if (top < height && abs(bx) < width && hash1(col * 1.7 + float(row)) > 0.3) {
				alpha = 1.0;
				tone = max(tone, clamp(lit * 0.45 + top * 0.5 + (h - 0.5) * 0.3 - float(row) * 0.15, 0.0, 1.0));
			}
		}
	}
	if (alpha < 0.5) {
		discard;
	}
	float hue = fract(custom.y);
	vec3 base = hue < 0.5 ? mix(gold, orange, hue * 2.0) : mix(orange, rust, (hue - 0.5) * 2.0);
	vec3 dark = mix(shade, base * 0.4, 0.3);
	vec3 col = mix(dark, base, smoothstep(0.1, 0.6, tone));
	col = mix(col, mix(base, gold, 0.4) * sun_color * 1.3, smoothstep(0.6, 1.0, tone) * lit);
	// leaves with the sun behind them glow through, deepening in colour rather than going white
	col += base * base * sun_color * backlit * (0.2 + 0.45 * lit) * smoothstep(0.1, 0.5, tone);
	col *= 1.0 - darkness;
	ALBEDO = col;
}
