shader_type spatial;
// Fresnel glass: clear where you look straight through it, mirror-like at grazing angles
// (Schlick's approximation of the Fresnel term from the index of refraction). A painted sky,
// floor and sun stand in for the world it reflects, with a little rainbow at the edges.
render_mode blend_mix, cull_back, depth_draw_always;

group_uniforms Glass;
uniform vec3 tint : source_color = vec3(0.6, 0.85, 0.95);
uniform float ior : hint_range(1.0, 2.5) = 1.5;
uniform float clarity : hint_range(0.0, 1.0) = 0.75;
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
group_uniforms Reflection;
uniform vec3 sky_top : source_color = vec3(0.55, 0.7, 1.0);
uniform vec3 sky_horizon : source_color = vec3(1.0, 0.85, 0.7);
uniform float reflection : hint_range(0.0, 2.0) = 1.4;
uniform float dispersion : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float cos_t = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float r0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
	float fres = r0 + (1.0 - r0) * pow(1.0 - cos_t, 5.0);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz; // reflection, in world space
	vec3 env = mix(sky_horizon, sky_top, smoothstep(-0.1, 0.6, r.y));
	env = mix(env, vec3(0.15, 0.15, 0.17), 1.0 - smoothstep(-0.3, 0.0, r.y)); // the floor
	env += vec3(4.0) * pow(max(dot(r, normalize(vec3(0.5, 0.8, 0.3))), 0.0), 200.0); // the sun
	vec3 rainbow = 0.5 + 0.5 * cos(6.28318 * (cos_t * 2.0 + vec3(0.0, 0.33, 0.67)));
	env = mix(env, env * rainbow * 1.5, dispersion * pow(1.0 - cos_t, 2.0));
	// light bent through the glass picks up the tint, strongest where the glass is thickest to the eye
	vec3 through = tint * mix(sky_horizon, sky_top, 0.5) * 0.25 * cos_t;
	ALBEDO = tint * (1.0 - fres) * 0.2;
	EMISSION = env * fres * reflection + through + tint * pow(1.0 - cos_t, 3.0) * 0.5;
	ALPHA = clamp(mix(1.0 - clarity, 1.0, fres), 0.0, 1.0);
	ROUGHNESS = roughness;
	SPECULAR = 0.8;
}
