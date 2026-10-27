shader_type spatial;
// One puff of cloud: a camera-facing disc shaded as if it were a sphere, its edge eaten into by
// drifting noise so it goes wispy. Clouds are heaps of these (weather.gd sorts them back to front).
// Per puff, INSTANCE_CUSTOM: x how high in its cloud (0 base, 1 top), y how dark its belly gets
// (storms), z a seed, w how squashed (1 round, less flat).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 light_dir = vec3(0.0, 0.8, -0.6);
uniform vec3 light_color : source_color = vec3(1.0);
uniform float light_energy = 1.2;
uniform vec3 ambient : source_color = vec3(0.5, 0.55, 0.65);
uniform vec3 horizon : source_color = vec3(0.7, 0.8, 0.9);
uniform float warmth = 0.0;        // sunset tint on the lit side
uniform float opacity = 1.0;
uniform float fade_far = 9000.0;
uniform vec3 flash_pos = vec3(0.0);
uniform float flash = 0.0;
uniform float gloom = 0.0;          // storm and overcast: everything greyer and darker

varying vec3 world;
varying vec4 info;
varying float size;
varying float base_y;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	size = length(MODEL_MATRIX[0].xyz);
	info = INSTANCE_CUSTOM;
	base_y = MODEL_MATRIX[1].y;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	world = c + (right * VERTEX.x + up * VERTEX.y * info.w) * size * 2.0;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r2 = dot(p, p);
	if (r2 > 1.0) discard;
	vec2 s = vec2(info.z * 7.13, info.z * 3.71);
	float n = texture(noise_tex, UV * 0.55 + s + vec2(TIME * 0.003, 0.0)).r;
	float n2 = texture(noise_tex, UV * 1.6 + s.yx - vec2(0.0, TIME * 0.005)).r;
	float edge = 1.0 - sqrt(r2);
	float a = smoothstep(0.0, 0.35, edge - (n * 0.6 + n2 * 0.4 - 0.5) * 0.7);
	// Cumulus have flat bottoms: the air below the condensation level is clear
	a *= smoothstep(base_y - 10.0, base_y + 90.0, world.y);
	if (a < 0.02) discard;

	// The disc as a lumpy sphere, in world space
	vec3 nv = vec3(p.x, p.y, sqrt(max(1.0 - r2, 0.0)));
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz + (vec3(n, n2, n) - 0.5) * 0.9);
	vec3 L = normalize(light_dir);
	float day = smoothstep(-0.1, 0.1, L.y);
	float ndl = dot(nw, L) * 0.5 + 0.5;
	// Tops catch the light, bellies sit in the cloud's own shade
	float height = mix(0.45, 1.0, info.x);
	float lit = ndl * 0.65 + height * 0.45 - 0.1;
	vec3 sun_col = mix(light_color, light_color * vec3(1.15, 0.72, 0.5), warmth) * light_energy * 1.35;
	vec3 shade = mix(ambient, horizon, 0.35) * mix(0.75, 1.15, info.x);
	vec3 col = mix(shade * 1.1, shade * 0.35 + sun_col, smoothstep(0.2, 0.9, lit));
	col *= mix(1.0, 0.3, info.y * (1.0 - info.x));
	col = mix(col, vec3(dot(col, vec3(0.33))) * vec3(0.9, 0.95, 1.05), gloom * 0.6) * mix(1.0, 0.6, gloom);
	// Thin edges glow when you look toward the sun
	vec3 V = normalize(CAMERA_POSITION_WORLD - world);
	float toward = pow(max(dot(-V, L), 0.0), 6.0);
	col += sun_col * toward * (1.0 - a) * 1.5 * day;
	// Lightning inside the cloud
	float fd = length(world - flash_pos);
	col += vec3(0.85, 0.85, 1.0) * flash * exp(-fd / 1400.0) * (0.6 + 0.8 * n) * 2.0;
	// Distance: into the haze, then gone
	float dist = length(world - CAMERA_POSITION_WORLD);
	col = mix(col, horizon, smoothstep(fade_far * 0.15, fade_far, dist) * 0.75);
	a *= 1.0 - smoothstep(fade_far * 0.8, fade_far, length(world.xz - CAMERA_POSITION_WORLD.xz));
	ALBEDO = col;
	ALPHA = a * opacity;
}
