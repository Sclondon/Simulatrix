// A shaft of sun slanting down through the canopy: a long card added over the scene, soft at its sides,
// fading out at its ends, breathing as leaves pass across the sun, coming and going over half a minute
// or so, and gone when the camera is in it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.5);
uniform float strength = 0.16;
uniform float seed = 0.0;

varying vec3 world_pos;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x - 0.5) * 2.0;
	float soft = pow(1.0 - across, 2.0);
	float ends = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.55, UV.y);
	// streaks along the shaft, flickering
	float streak = 0.6 + 0.4 * sin(UV.x * 23.0 + seed * 10.0 + sin(TIME * 0.4 + seed) * 2.0);
	float breathe = 0.65 + 0.35 * sin(TIME * (0.3 + hash(seed) * 0.3) + seed * 5.0);
	// each shaft comes and goes on its own slow clock, as cloud and leaves cross the sun
	float come = 0.5 + 0.5 * sin(TIME * (0.06 + hash(seed + 1.0) * 0.07) + seed * 6.283);
	breathe *= smoothstep(0.25, 0.75, come);
	float near = smoothstep(2.0, 7.0, distance(world_pos, CAMERA_POSITION_WORLD));
	// thin where it is seen face-on to its edge
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float face = abs(dot(n, normalize(CAMERA_POSITION_WORLD - world_pos)));
	ALBEDO = color * strength * soft * ends * streak * breathe * near * smoothstep(0.0, 0.5, face);
}
