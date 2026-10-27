shader_type spatial;
// A ground that takes the weather (WeatherRig.ground_material()): any mesh (a plane, a terrain),
// coloured from `colour_a` to `colour_b` by noise, with ground_weather.gdshaderinc on top: wet and
// puddles in rain, settling snow, cloud shadows. WeatherRig.register() keeps the weather set.

#include "res://weather/ground_weather.gdshaderinc"

uniform vec3 colour_a : source_color = vec3(0.16, 0.26, 0.09);
uniform vec3 colour_b : source_color = vec3(0.32, 0.38, 0.14);

varying vec3 world;
varying vec3 wnormal;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world.xz;
	float n2 = texture(noise_tex, p * 0.031).r;
	float n3 = texture(noise_tex, p * 0.21).r;
	vec3 col = mix(colour_a, colour_b, n2) * (0.85 + 0.3 * n3);
	float rough;
	float spec;
	vec3 emit;
	weather_ground(world, wnormal, CAMERA_POSITION_WORLD, col, n2, n3, rough, spec, emit);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emit;
}
