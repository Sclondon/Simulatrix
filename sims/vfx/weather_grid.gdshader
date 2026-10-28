shader_type spatial;
// The weather labs' floor: the editor grid the other labs stand on (grey, metre lines, every fifth
// stronger, X red and Z blue), lit, with GameCommon weather's ground_weather on top, so it darkens
// and puddles in the rain (puddles mirror the sky and ring with drops), takes settling snow and
// cloud shadows. WeatherRig.register keeps those uniforms set (noise_tex comes from the include).
// Far off it fades into far_color (the lab keeps it the sky's colour under the horizon), so the floor
// meets the sky.

#include "res://weather/ground_weather.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 line_color : source_color = vec3(0.32, 0.32, 0.35);
uniform float line_fade = 70.0;     // grid lines fade out by here, m
uniform float far_fade = 6000.0;    // the floor is the horizon by here, m
uniform vec3 far_color : source_color = vec3(0.66, 0.8, 0.94); // the sky just under the horizon

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float step_size) {
	vec2 q = p / step_size;
	vec2 w = fwidth(q);
	vec2 g = abs(fract(q - 0.5) - 0.5) / max(w, vec2(1e-4));
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}

void fragment() {
	vec2 p = world.xz;
	float d = length(p - CAMERA_POSITION_WORLD.xz);
	float lines = 1.0 - smoothstep(line_fade * 0.35, line_fade, d);
	vec3 col = base_color;
	col = mix(col, line_color, grid(p, 1.0) * 0.55 * lines);
	col = mix(col, line_color * 1.35, grid(p, 5.0) * 0.8 * lines);
	vec2 w = fwidth(p);
	float ax = (1.0 - clamp(abs(p.y) / max(w.y, 1e-4), 0.0, 1.0)) * lines;
	float az = (1.0 - clamp(abs(p.x) / max(w.x, 1e-4), 0.0, 1.0)) * lines;
	col = mix(col, vec3(0.62, 0.22, 0.22), ax);
	col = mix(col, vec3(0.22, 0.36, 0.66), az);
	float n2 = texture(noise_tex, p * 0.031).r;
	float n3 = texture(noise_tex, p * 0.21).r;
	float rough;
	float spec;
	vec3 emit;
	weather_ground(world, vec3(0.0, 1.0, 0.0), CAMERA_POSITION_WORLD, col, n2, n3, rough, spec, emit);
	float far = smoothstep(far_fade * 0.05, far_fade, d);
	ALBEDO = col * (1.0 - far);
	ROUGHNESS = rough;
	SPECULAR = spec * (1.0 - far);
	EMISSION = mix(emit, far_color, far);
}
