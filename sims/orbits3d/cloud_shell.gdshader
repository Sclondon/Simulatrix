// Atlas's cloud layer, on a shell a little bigger than the Earth (a child of it, so it turns
// with it and drifts on top), lit by the sun and dark on the night side.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float cloud_cover = 0.42;
uniform float cloud_opacity = 0.85;
uniform float cloud_drift = 0.0;

varying vec3 obj_n;
varying vec3 world_n;

#include "res://sims/orbits3d/clouds.gdshaderinc"

void vertex() {
	obj_n = NORMAL;
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float cloud = cloud_at(normalize(obj_n)) * cloud_opacity;
	float l = dot(normalize(world_n), normalize(sun_dir));
	float lit = smoothstep(-0.15, 0.25, l);
	ALBEDO = mix(vec3(0.07, 0.08, 0.12), vec3(1.0) * (0.6 + 0.5 * clamp(l, 0.0, 1.0)), lit);
	ALPHA = clamp(cloud, 0.0, 1.0);
}
