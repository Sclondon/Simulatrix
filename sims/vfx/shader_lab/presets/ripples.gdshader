shader_type canvas_item;
// Water ripples: rings spread from a few drops and from your finger. The slope of the summed
// waves bends the view of a tiled pool floor (refraction), and where the surface curves inward
// the light gathers into bright caustic lines.
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Waves;
uniform float wavelength : hint_range(0.01, 0.2) = 0.05;
uniform float speed : hint_range(0.0, 1.0) = 0.12;
uniform float damping : hint_range(0.5, 10.0) = 3.0;
uniform float refraction : hint_range(0.0, 0.1) = 0.03;
group_uniforms Pool;
uniform vec3 water : source_color = vec3(0.1, 0.55, 0.7);
uniform vec3 tile_color : source_color = vec3(0.85, 0.92, 0.95);
uniform float tiles : hint_range(2.0, 30.0) = 10.0;
uniform float caustics : hint_range(0.0, 2.0) = 1.0;

float wave(vec2 p, vec2 source) {
	float d = length(p - source);
	return sin((d - TIME * speed) * 6.28318 / wavelength) * exp(-d * damping);
}

float field(vec2 p) {
	float a = resolution.x / resolution.y;
	float h = wave(p, vec2(0.3 * a, 0.3));
	h += wave(p, vec2(0.7 * a, 0.65));
	h += wave(p, vec2((0.5 + 0.3 * sin(TIME * 0.3)) * a, 0.5 + 0.3 * cos(TIME * 0.23)));
	h += 1.5 * wave(p, mouse * vec2(a, 1.0));
	return h;
}

void fragment() {
	vec2 p = UV * vec2(resolution.x / resolution.y, 1.0);
	float e = 0.0015;
	float h = field(p);
	float hx = field(p + vec2(e, 0.0));
	float hy = field(p + vec2(0.0, e));
	float hx2 = field(p - vec2(e, 0.0));
	float hy2 = field(p - vec2(0.0, e));
	vec2 slope = vec2(hx - hx2, hy - hy2) / (2.0 * e);
	float bend = (hx + hx2 + hy + hy2 - 4.0 * h) / (e * e); // the Laplacian: how the surface curves
	vec2 q = p + slope * refraction * wavelength / 6.28318;
	vec2 t = fract(q * tiles);
	float grout = step(0.05, t.x) * step(0.05, t.y);
	vec3 col = mix(mix(tile_color * 0.55, tile_color, grout), water, 0.55);
	col += caustics * max(-bend * wavelength * wavelength * 0.02, 0.0) * vec3(0.8, 1.0, 1.0) * 0.5;
	vec3 n = normalize(vec3(-slope * wavelength * 0.1, 1.0));
	col += pow(clamp(dot(n, normalize(vec3(0.3, 0.5, 1.0))), 0.0, 1.0), 60.0) * 0.6;
	COLOR = vec4(col, 1.0);
}
