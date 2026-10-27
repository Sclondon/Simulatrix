shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Texture Lab's generator: one procedural texture across UV 0..1, drawn into a SubViewport.
// Every noise is periodic in UV when `seamless` is on: lattice noises wrap their cell
// coordinates at a whole-number frequency, simplex (which has no square lattice) blends
// four shifted copies. Time is a third axis, so animating evolves the texture in place.

uniform int gen_type = 8;
uniform int basis = 1; // 0 value, 1 perlin, 2 simplex
uniform float seed = 1234.0;
uniform float scale = 4.0;
uniform int octaves = 6;
uniform float lacunarity = 2.0;
uniform float gain = 0.5;
uniform float warp = 0.0;
uniform float jitter = 1.0;
uniform float rotation = 0.0;
uniform float time = 0.0;
uniform bool seamless = true;
uniform sampler2D ramp : filter_linear, repeat_disable;
uniform int view_mode = 0; // 0 colour, 1 height, 2 normal map
uniform bool invert = false;
uniform float contrast = 1.0;
uniform float level_lo = 0.0;
uniform float level_hi = 1.0;
uniform int posterize = 0;
uniform float normal_strength = 1.0;
uniform float tex_size = 512.0;

// --- hashes (Dave Hoskins' sine-free hashes) ---------------------------------

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// A lattice cell wrapped to the period, then moved by the seed
vec3 cell(vec3 c, vec2 per) {
	return vec3(mod(c.xy, per), c.z) + vec3(seed * 1.618, seed * 2.414, seed * 0.577);
}

// --- the three bases -----------------------------------------------------------

float vnoise(vec3 p, vec2 per) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = hash13(cell(i, per));
	float b = hash13(cell(i + vec3(1.0, 0.0, 0.0), per));
	float c = hash13(cell(i + vec3(0.0, 1.0, 0.0), per));
	float d = hash13(cell(i + vec3(1.0, 1.0, 0.0), per));
	float e = hash13(cell(i + vec3(0.0, 0.0, 1.0), per));
	float g = hash13(cell(i + vec3(1.0, 0.0, 1.0), per));
	float h = hash13(cell(i + vec3(0.0, 1.0, 1.0), per));
	float k = hash13(cell(i + vec3(1.0, 1.0, 1.0), per));
	return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z) * 2.0 - 1.0;
}

float gdot(vec3 i, vec3 o, vec3 f, vec2 per) {
	vec3 g = hash33(cell(i + o, per)) * 2.0 - 1.0;
	return dot(g, f - o);
}

float pnoise(vec3 p, vec2 per) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = gdot(i, vec3(0.0, 0.0, 0.0), f, per);
	float n100 = gdot(i, vec3(1.0, 0.0, 0.0), f, per);
	float n010 = gdot(i, vec3(0.0, 1.0, 0.0), f, per);
	float n110 = gdot(i, vec3(1.0, 1.0, 0.0), f, per);
	float n001 = gdot(i, vec3(0.0, 0.0, 1.0), f, per);
	float n101 = gdot(i, vec3(1.0, 0.0, 1.0), f, per);
	float n011 = gdot(i, vec3(0.0, 1.0, 1.0), f, per);
	float n111 = gdot(i, vec3(1.0, 1.0, 1.0), f, per);
	return 1.5 * mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

// Simplex 3D after Ashima Arts / Stefan Gustavson (MIT)
vec3 mod289_3(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289_4(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289_4(((x * 34.0) + 1.0) * x); }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;
	i = mod289_3(i);
	vec4 p = permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0)) + i.x + vec4(0.0, i1.x, i2.x, 1.0));
	vec3 ns = 0.142857142857 * D.wyz - D.xzx;
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);
	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	vec4 norm = 1.79284291400159 - 0.85373472095314 * vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;
	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Simplex made to tile: four copies shifted by a whole tile, cross-faded, with the
// variance put back so the middle of the tile isn't greyer than its edges
float snoise_tiled(vec2 uv, vec2 fr, float z) {
	vec3 so = vec3(seed * 0.618, seed * 0.414, 0.0);
	if (!seamless) {
		return snoise(vec3(uv * fr, z) + so);
	}
	vec2 t = fract(uv);
	float a = snoise(vec3(t * fr, z) + so);
	float b = snoise(vec3((t - vec2(1.0, 0.0)) * fr, z) + so);
	float c = snoise(vec3((t - vec2(0.0, 1.0)) * fr, z) + so);
	float d = snoise(vec3((t - vec2(1.0, 1.0)) * fr, z) + so);
	vec2 w = smoothstep(0.0, 1.0, t);
	float n = mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
	vec2 k = sqrt((1.0 - w) * (1.0 - w) + w * w);
	return n / (k.x * k.y);
}

// One octave of the chosen basis, about -1..1, at frequency `fr` across the tile
float noise(vec2 uv, vec2 fr, float z, int kind) {
	vec2 per = seamless ? fr : vec2(65536.0);
	if (kind == 0) {
		return vnoise(vec3(uv * fr, z), per);
	} else if (kind == 1) {
		return pnoise(vec3(uv * fr, z), per);
	}
	return snoise_tiled(uv, fr, z);
}

vec2 freq_at(vec2 base, int o) {
	vec2 f = base * pow(lacunarity, float(o));
	return seamless ? max(round(f), vec2(1.0)) : f;
}

// Fractal sum: mode 0 plain fBm, 1 ridged multifractal, 2 billow. About -1..1.
float fbm(vec2 uv, vec2 base, int oct, int mode, int kind) {
	float sum = 0.0;
	float amp = 1.0;
	float norm = 0.0;
	float prev = 1.0;
	for (int o = 0; o < 8; o++) {
		if (o >= oct) {
			break;
		}
		float n = noise(uv, freq_at(base, o), time + float(o) * 3.17, kind);
		if (mode == 1) {
			n = 1.0 - abs(n);
			n *= n * prev;
			prev = clamp(n * 1.6, 0.0, 1.0);
			n = n * 2.0 - 1.0;
		} else if (mode == 2) {
			n = abs(n) * 2.0 - 1.0;
		}
		sum += n * amp;
		norm += amp;
		amp *= gain;
	}
	return sum / norm;
}

// Distances to the nearest and second-nearest feature point (Worley). Points drift with time.
vec2 worley(vec2 uv, vec2 fr) {
	vec2 per = seamless ? max(round(fr), vec2(1.0)) : vec2(65536.0);
	if (seamless) {
		fr = per;
	}
	vec2 p = uv * fr;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = hash22(mod(i + o, per) + vec2(seed * 1.618, seed * 2.414));
			vec2 pt = 0.5 + jitter * 0.5 * sin(time * 1.5 + TAU * h);
			float d = length(o + pt - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(f1, f2);
}

float whole(float x) {
	return seamless ? max(1.0, round(x)) : max(x, 0.25);
}

// --- the generators --------------------------------------------------------------

float raw(vec2 uv) {
	if (!seamless && rotation != 0.0) {
		float c = cos(rotation);
		float s = sin(rotation);
		uv = mat2(vec2(c, s), vec2(-s, c)) * (uv - 0.5) + 0.5;
	}
	vec2 S = vec2(scale);
	if (warp > 0.001 && gen_type != 8) {
		vec2 q = vec2(fbm(uv + vec2(0.13, 0.71), S * 0.5, 3, 0, 1), fbm(uv + vec2(0.53, 0.29), S * 0.5, 3, 0, 1));
		uv += q * warp * 0.6 / scale;
	}
	float h = 0.0;
	if (gen_type <= 2) {
		h = noise(uv, seamless ? max(round(S), vec2(1.0)) : S, time, gen_type) * 0.5 + 0.5;
	} else if (gen_type == 3) {
		h = clamp(worley(uv, S).x * 1.1, 0.0, 1.0);
	} else if (gen_type == 4) {
		vec2 w = worley(uv, S);
		h = clamp((w.y - w.x) * 1.6, 0.0, 1.0);
	} else if (gen_type <= 7) {
		h = fbm(uv, S, octaves, gen_type - 5, basis) * 0.5 + 0.5;
	} else if (gen_type == 8) {
		// Domain warp (after Inigo Quilez): fBm of fBm of fBm
		float k = (1.0 + warp * 3.0) / scale;
		int oct = min(octaves, 5);
		vec2 q = vec2(fbm(uv, S, oct, 0, basis), fbm(uv + vec2(0.52, 0.13), S, oct, 0, basis));
		vec2 r = vec2(fbm(uv + k * q + vec2(0.17, 0.92), S, oct, 0, basis),
			fbm(uv + k * q + vec2(0.83, 0.28), S, oct, 0, basis));
		h = fbm(uv + k * r, S, octaves, 0, basis) * 0.5 + 0.5;
	} else if (gen_type == 9) {
		// Wood: growth rings across the board, bent by noise, with fibres along it
		float rings = whole(scale * 0.75);
		float t = uv.y * rings + 0.55 * fbm(uv, S * vec2(0.3, 0.6), min(octaves, 4), 0, basis);
		float r = fract(t);
		float ring = smoothstep(0.0, 0.8, r) * (1.0 - smoothstep(0.86, 1.0, r));
		float fibres = noise(uv, vec2(whole(scale * 0.5), whole(scale * 24.0)), time, 1);
		h = 0.2 + 0.62 * ring + 0.12 * fibres;
	} else if (gen_type == 10) {
		// Marble: thin dark veins where a turbulent sine crosses zero
		float k = whole(scale * 0.25);
		float t = (uv.x + uv.y) * k + 1.3 * fbm(uv, S * 0.5, octaves, 0, basis);
		float s = abs(sin(3.14159 * t));
		float t2 = uv.x * k * 2.0 - uv.y * k + 2.0 * fbm(uv + vec2(0.4, 0.7), S * 0.75, octaves, 0, basis);
		float s2 = abs(sin(3.14159 * t2));
		float cloud = fbm(uv + vec2(0.31, 0.17), S, min(octaves, 4), 2, basis);
		h = 0.86 + 0.1 * cloud - 0.75 * pow(1.0 - s, 6.0) - 0.35 * pow(1.0 - s2, 14.0);
	} else if (gen_type == 11) {
		// Bricks in running bond: bevelled faces of varied fire, mortar between
		float rows = seamless ? max(2.0, 2.0 * round(scale * 0.5)) : max(scale, 1.0);
		float cols = seamless ? max(1.0, round(rows * 0.5)) : rows * 0.5;
		vec2 p = uv * vec2(cols, rows);
		float row = floor(p.y);
		p.x += mod(row, 2.0) * 0.5;
		vec2 c = floor(p);
		vec2 f = fract(p);
		vec2 cw = seamless ? vec2(mod(c.x, cols), mod(c.y, rows)) : c;
		float e = min(min(f.x, 1.0 - f.x) * rows / cols, min(f.y, 1.0 - f.y));
		float mortar = 0.05 + 0.1 * jitter * 0.5;
		float face = smoothstep(mortar, mortar + 0.07, e);
		float tint = hash13(vec3(cw, 0.0) + vec3(seed * 1.618, seed * 2.414, 0.0));
		float grime = fbm(uv, S * 2.0, min(octaves, 4), 0, basis);
		float grit = noise(uv, vec2(whole(scale * 12.0)), time, 0);
		h = mix(0.12 + 0.04 * grit, 0.5 + 0.4 * tint + 0.06 * grime + 0.04 * grit, face);
	} else if (gen_type == 12) {
		// Bark: long plates split by fissures, ridged fibres running down them
		// (fissures are where a tall, narrow noise crosses zero, so they run up and down and fork)
		vec2 bent = uv + 0.05 * vec2(fbm(uv, S * vec2(0.5, 1.0), 3, 0, basis), 0.0);
		float n = noise(bent, vec2(whole(scale * 1.3), whole(scale * 0.2)), time, 1);
		float crack = smoothstep(0.0, 0.22, abs(n));
		float plate = noise(bent, vec2(whole(scale * 2.6), whole(scale * 0.5)), time + 5.0, 1);
		float fibre = fbm(uv, S * vec2(3.0, 0.3), octaves, 1, basis) * 0.5 + 0.5;
		h = crack * (0.3 + 0.45 * fibre + 0.25 * smoothstep(-0.4, 0.6, plate));
	} else if (gen_type == 13) {
		// Clouds: billowy fBm through a soft threshold
		float c = fbm(uv, S, octaves, 0, basis) * 0.5 + 0.5;
		float b = fbm(uv + vec2(0.37, 0.61), S * 2.0, min(octaves, 4), 2, basis) * 0.5 + 0.5;
		h = smoothstep(0.38, 0.82, c * 0.8 + b * 0.25);
	} else if (gen_type == 14) {
		// Sand ripples: asymmetric wind ripples (long stoss, steep lee) with grain
		float k = whole(scale * 0.9);
		float t = uv.y * k + 0.45 * fbm(uv, S * vec2(0.3, 0.2), min(octaves, 4), 0, basis);
		float r = fract(t);
		float rip = r < 0.72 ? r / 0.72 : (1.0 - r) / 0.28;
		rip = smoothstep(0.0, 1.0, rip);
		float grain = noise(uv, vec2(whole(scale * 32.0)), 0.0, 0);
		h = 0.15 + 0.7 * rip + 0.08 * grain + 0.07 * fbm(uv, S * 0.5, 3, 0, basis);
	} else {
		// Caustics: bright webs where two drifting cell layers' edges meet
		vec2 a = worley(uv, S);
		vec2 b = worley(uv + vec2(0.37, 0.11), S * 1.5);
		float ca = pow(1.0 - smoothstep(0.0, 0.22, a.y - a.x), 3.0);
		float cb = pow(1.0 - smoothstep(0.0, 0.18, b.y - b.x), 3.0);
		h = clamp(0.12 + ca * 0.7 + cb * 0.5, 0.0, 1.0);
	}
	return clamp(h, 0.0, 1.0);
}

float height(vec2 uv) {
	float h = raw(uv);
	h = clamp((h - level_lo) / max(level_hi - level_lo, 0.001), 0.0, 1.0);
	h = clamp((h - 0.5) * contrast + 0.5, 0.0, 1.0);
	if (invert) {
		h = 1.0 - h;
	}
	if (posterize > 1) {
		h = floor(h * float(posterize) * 0.9999) / float(posterize - 1);
	}
	return h;
}

void fragment() {
	vec2 uv = UV;
	float h = height(uv);
	if (view_mode == 1) {
		COLOR = vec4(vec3(h), 1.0);
	} else if (view_mode == 2) {
		float e = 1.0 / tex_size;
		float hx = height(uv + vec2(e, 0.0));
		float hy = height(uv + vec2(0.0, e));
		float s = normal_strength * tex_size * 0.04;
		vec3 n = normalize(vec3((h - hx) * s, (h - hy) * s, 1.0));
		COLOR = vec4(n * 0.5 + 0.5, 1.0);
	} else {
		COLOR = vec4(texture(ramp, vec2(h, 0.5)).rgb, 1.0);
	}
}
