// Weather on the ground, for a ground shader to #include ("res://weather/ground_weather.gdshaderinc"):
// rain wets it (darker, glossier, puddles in the low spots that mirror the sky and ring with
// drops), snow settles on it (patchy at first, the flat first, then a blanket), and cloud shadows
// drift over it. WeatherRig.register(material) keeps these uniforms set.
//
// In fragment(), with the point in the world, its normal (world space) and the ground's own colour:
//     float rough; float spec; vec3 emit;
//     weather_ground(world, wnormal, CAMERA_POSITION_WORLD, col, n2, n3, rough, spec, emit); // n2, n3: 0..1 noise, coarse, fine
//     ALBEDO = col; ROUGHNESS = rough; SPECULAR = spec; EMISSION = emit;
// See weather/ground.gdshader for a whole ground; the Simulatrix's weather labs use it on an editor grid.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float wet = 0.0;
uniform float snow = 0.0;
uniform float raining = 0.0;
uniform vec3 zenith : source_color = vec3(0.2, 0.4, 0.8);
uniform vec3 horizon : source_color = vec3(0.7, 0.8, 0.9);
uniform float shadow_amount = 0.0;
uniform vec2 shadow_offset = vec2(0.0);
uniform float shadow_scale = 0.00012;
uniform float shadow_cover = 0.4;
uniform float puddles = 1.0;         // how much of the wet gathers into puddles (0 none, 1 as made, 2 a lot)


// Rings spreading from raindrops in a puddle: one drop a cell, each at its own moment
float weather_ripples(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float rnd = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 c = vec2(fract(rnd * 13.7), fract(rnd * 71.3)) * 0.6 + 0.2;
	float t = fract(TIME * 0.9 + rnd);
	float d = length(f - c);
	return step(0.35, fract(rnd * 7.7)) * sin((d - t * 0.45) * 60.0) * (1.0 - smoothstep(0.0, 0.08, abs(d - t * 0.45))) * (1.0 - t);
}

// `cap`: snow that is always there (peaks), 0..1. Gives back the roughness, specular and emission.
void weather_ground_cap(vec3 world, vec3 wnormal, vec3 cam, inout vec3 col, float n2, float n3, float cap,
		out float rough, out float spec, out vec3 emit) {
	vec2 p = world.xz;
	float dist = length(world - cam);
	// Settling snow: thin at first, patchy, then a blanket; it sits on the flat first
	float lie = snow * 1.25 - (n3 * 0.35 + n2 * 0.25) + (wnormal.y - 0.8) * 0.8;
	float sn = max(cap, smoothstep(0.05, 0.25, lie));
	// Wet: darker, and puddles in the low spots
	float puddle = smoothstep(0.62, 0.7, wet * 0.35 + (1.0 - n2) * 0.55 + (1.0 - n3) * 0.1 + (puddles - 1.0) * 0.3 * wet) * min(puddles * 4.0, 1.0) * smoothstep(0.75, 0.95, wnormal.y);
	puddle *= 1.0 - sn;
	col *= 1.0 - wet * 0.45;
	// Cloud shadows drifting over
	float cs = texture(noise_tex, p * shadow_scale + shadow_offset).r;
	float shadow = smoothstep(1.0 - shadow_cover, 1.0 - shadow_cover + 0.2, cs) * shadow_amount;
	vec3 snow_col = vec3(0.92, 0.94, 0.98) * (0.92 + 0.08 * n3);
	col = mix(col, snow_col, sn);
	vec3 V = normalize(cam - world);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(V.y, 0.0, 1.0), 5.0);
	float rip = 0.0;
	if (raining > 0.0 && dist < 60.0) {
		rip = (weather_ripples(p * 1.3) + weather_ripples(p * 1.3 + 0.5)) * raining * (1.0 - dist / 60.0);
	}
	vec3 sky = mix(horizon, zenith, clamp(V.y + rip * 0.15, 0.0, 1.0) * 0.6);
	col = mix(col, col * 0.3, puddle);
	col *= 1.0 - shadow * 0.55;
	rough = mix(mix(0.95, 0.45, wet), 0.05, puddle);
	spec = mix(0.3, 0.6, wet);
	emit = sky * puddle * (fres * 0.8 + 0.12) * (1.0 + rip * 0.6) + sky * wet * fres * 0.1 * (1.0 - sn);
}

void weather_ground(vec3 world, vec3 wnormal, vec3 cam, inout vec3 col, float n2, float n3,
		out float rough, out float spec, out vec3 emit) {
	weather_ground_cap(world, wnormal, cam, col, n2, n3, 0.0, rough, spec, emit);
}
