shader_type spatial;
render_mode cull_disabled;
// A flag (WindFlag's cloth: a PlaneMesh facing +z, x 0..flag_length from the pole). Its node is turned
// to point downwind; here it hangs limp in calm air, stands out as the wind rises, and ripples in waves
// that run to the free end, faster in a stronger wind.
uniform float strength = 0.5; // 0 calm .. 1 a gale
uniform float flag_length = 1.6;
uniform vec3 colour_a : source_color = vec3(0.95, 0.42, 0.12);
uniform vec3 colour_b : source_color = vec3(0.96, 0.94, 0.9);

void vertex() {
	float t = clamp(VERTEX.x / flag_length, 0.0, 1.0);
	float s = clamp(strength, 0.0, 1.0);
	float pace = 4.0 + 12.0 * s;
	float wave = sin(VERTEX.x * 4.5 - TIME * pace) * 0.6 + sin(VERTEX.x * 9.0 - TIME * pace * 1.7 + VERTEX.y * 2.0) * 0.25;
	VERTEX.z += wave * (0.06 + 0.12 * s) * t;
	// hang: turn down about the pole the less it blows
	float droop = (1.0 - smoothstep(0.0, 0.7, s)) * 1.35 + 0.1;
	float x = VERTEX.x;
	VERTEX.x = x * cos(droop) + VERTEX.y * sin(droop);
	VERTEX.y = VERTEX.y * cos(droop) - x * sin(droop);
	NORMAL = normalize(vec3(-cos(VERTEX.x * 4.5 - TIME * pace) * 0.3 * t, 0.0, 1.0));
}

void fragment() {
	float band = step(0.5, fract(UV.y * 2.0 + 0.25));
	ALBEDO = mix(colour_a, colour_b, band);
	ROUGHNESS = 0.9;
}
