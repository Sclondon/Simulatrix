shader_type canvas_item;
// Pixelate + CRT: draws a little synthwave scene, cuts it into big pixels with few colours,
// then shows it on a curved tube with scanlines, colour fringes and a vignette.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Pixels;
uniform float pixel_rows : hint_range(16.0, 400.0) = 120.0;
uniform int colors : hint_range(2, 32) = 8;
group_uniforms Tube;
uniform float curvature : hint_range(0.0, 0.5) = 0.18;
uniform float scanlines : hint_range(0.0, 1.0) = 0.5;
uniform float aberration : hint_range(0.0, 3.0) = 1.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.6;

// The picture on the tube: a striped sun over a scrolling neon grid.
vec3 scene(vec2 uv) {
	float aspect = resolution.x / resolution.y;
	vec2 p = vec2((uv.x - 0.5) * aspect, 0.55 - uv.y);
	if (p.y > 0.0) {
		vec3 sky_col = mix(vec3(1.0, 0.45, 0.55), vec3(0.12, 0.04, 0.3), clamp(p.y * 2.2, 0.0, 1.0));
		vec2 s = p - vec2((mouse.x - 0.5) * 0.4, 0.13); // the sun follows your finger
		bool cut = s.y < 0.0 && fract(s.y * 30.0) < 0.35;
		if (length(s) < 0.15 && !cut) {
			sky_col = mix(vec3(1.0, 0.25, 0.5), vec3(1.0, 0.9, 0.35), clamp(s.y * 3.0 + 0.5, 0.0, 1.0));
		}
		return sky_col;
	}
	// the floor seen in perspective: depth grows toward the horizon, x spreads with it
	float depth = 1.0 / max(-p.y, 0.002);
	vec2 g = vec2(p.x * depth * 3.0, depth + TIME * 1.5);
	vec2 d = 0.5 - abs(fract(g) - 0.5); // distance to the nearest line, in grid squares
	vec2 w = clamp(vec2(depth * 3.0, depth * depth) / pixel_rows * 1.5, 0.04, 0.5); // about a pixel wide
	float grid_line = max(1.0 - smoothstep(w.x * 0.5, w.x, d.x), 1.0 - smoothstep(w.y * 0.5, w.y, d.y));
	vec3 ground = mix(vec3(0.08, 0.02, 0.15), vec3(0.2, 0.95, 1.0), grid_line);
	return mix(ground, vec3(1.0, 0.4, 0.6), exp(p.y * 14.0) * 0.85); // haze on the horizon
}

// Bulge the picture like the glass of an old tube.
vec2 curve(vec2 uv) {
	uv = uv * 2.0 - 1.0;
	uv += uv * (uv.yx * uv.yx) * curvature;
	return uv * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = curve(UV);
	vec3 col = vec3(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec2 cells = vec2(pixel_rows * resolution.x / resolution.y, pixel_rows);
		vec2 px = (floor(uv * cells) + 0.5) / cells;
		float shift = aberration / cells.x;
		col = vec3(scene(px + vec2(shift, 0.0)).r, scene(px).g, scene(px - vec2(shift, 0.0)).b);
		float steps = float(colors - 1);
		col = floor(col * steps + 0.5) / steps;
		float scan = 0.5 + 0.5 * sin(uv.y * pixel_rows * 6.28318);
		col *= 1.0 - scanlines * (1.0 - scan) * 0.7;
		vec2 v = uv * (1.0 - uv.yx);
		col *= mix(1.0, pow(v.x * v.y * 16.0, 0.35), vignette);
	}
	COLOR = vec4(col, 1.0);
}
