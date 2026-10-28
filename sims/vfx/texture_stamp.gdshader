shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Texture Lab's stamp pass, between the generator and the output: lays a sprite (a built-in
// shape, one drawn on the shape pad, or an imported image) onto the packed height (r + g / 255).
//   mode 0  off: the height goes through as it is
//   mode 1  scatter: one stamp in each cell of a grid, moved, turned and sized at random
//   mode 2  tile: one stamp in each cell, in rows
//   mode 3  mask: the height shows only where the image is (stretched once over the tile)
//   mode 4  base: the image's brightness is the height (a photo to colour, bump and tile)
// Scatter and tile wrap at the tile's edges, so a seamless texture stays seamless.

uniform sampler2D height_tex : filter_nearest, repeat_enable;
uniform sampler2D stamp : filter_linear_mipmap, repeat_disable;
uniform int mode = 0;
uniform float cells = 6.0; // stamps across the tile
uniform float stamp_size = 0.8; // as a share of a cell
uniform float size_rand = 0.3;
uniform float jitter = 1.0;
uniform float spin = 1.0; // 0 upright, 1 any angle
uniform float level = 1.0; // the height a stamp lays down (0 cuts holes)
uniform float strength = 1.0;
uniform float seed = 1.0;
// for base: the same shaping the generator gives its noise
uniform float contrast = 1.0;
uniform float level_lo = 0.0;
uniform float level_hi = 1.0;
uniform bool invert = false;
uniform int posterize = 0;

float hash(vec2 p) {
	p = mod(p, 4096.0);
	return fract(sin(dot(p + seed * 0.137, vec2(127.1, 311.7))) * 43758.5453);
}

float height(vec2 uv) {
	vec4 c = texture(height_tex, uv);
	return c.r + c.g / 255.0;
}

// The stamp's cover (its alpha) over this point, from the stamps of this cell and its neighbours.
float scatter(vec2 uv, bool rows) {
	float n = max(floor(cells + 0.5), 1.0);
	vec2 p = uv * n;
	vec2 base_cell = floor(p);
	float cover = 0.0;
	float lod = log2(max(float(textureSize(stamp, 0).x) / max(float(textureSize(height_tex, 0).x) / n * stamp_size, 1.0), 1.0));
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = base_cell + vec2(float(x), float(y));
			vec2 key = mod(cell, n); // wrap: the tile repeats
			vec2 centre = cell + 0.5;
			float turn = 0.0;
			float s = stamp_size;
			if (!rows) {
				centre += (vec2(hash(key), hash(key + 17.0)) - 0.5) * jitter;
				turn = (hash(key + 31.0) - 0.5) * 6.2831853 * spin;
				s *= 1.0 - size_rand * hash(key + 47.0);
			}
			vec2 d = p - centre;
			float c = cos(turn);
			float sn = sin(turn);
			d = vec2(c * d.x + sn * d.y, -sn * d.x + c * d.y) / max(s, 0.001);
			vec2 suv = d + 0.5;
			if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0) {
				float a = textureLod(stamp, suv, lod).a;
				cover = max(cover, a);
			}
		}
	}
	return cover;
}

void fragment() {
	float h = height(UV);
	if (mode == 1 || mode == 2) {
		h = mix(h, level, scatter(UV, mode == 2) * strength);
	} else if (mode == 3) {
		h *= mix(1.0, texture(stamp, UV).a, strength);
	} else if (mode == 4) {
		vec4 s = texture(stamp, UV);
		float b = dot(s.rgb, vec3(0.2126, 0.7152, 0.0722)) * s.a;
		b = clamp((b - level_lo) / max(level_hi - level_lo, 0.001), 0.0, 1.0);
		b = clamp((b - 0.5) * contrast + 0.5, 0.0, 1.0);
		if (invert) {
			b = 1.0 - b;
		}
		if (posterize > 1) {
			b = floor(b * float(posterize) * 0.9999) / float(posterize - 1);
		}
		h = mix(h, b, strength);
	}
	h = clamp(h, 0.0, 1.0);
	float hi = floor(h * 255.0) / 255.0;
	COLOR = vec4(hi, (h - hi) * 255.0, 0.0, 1.0);
}
