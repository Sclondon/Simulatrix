// The Moon (NASA's LRO map, as in Atlas), lit by the same sun so it shows its phases, with a
// little earthshine on the dark side. Its +Z is the near side, turned to the Earth by the script.
shader_type spatial;
render_mode unshaded;

uniform sampler2D moon_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);

varying vec3 obj_n;
varying vec3 world_n;

uniform float cloud_cover = 0.0;
uniform float cloud_drift = 0.0;
#include "res://sims/orbits3d/clouds.gdshaderinc"

void vertex() {
	obj_n = NORMAL;
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = normalize(obj_n);
	vec2 uv = vec2(0.5 + atan(n.x, n.z) / TAU, 0.5 - asin(clamp(n.y, -1.0, 1.0)) / PI);
	vec4 g = seam_grad(uv);
	vec3 rock = textureGrad(moon_map, uv, g.xy, g.zw).rgb * 1.25;
	float sunlit = clamp(dot(normalize(world_n), normalize(sun_dir)) * 1.4, 0.0, 1.0);
	ALBEDO = rock * (0.06 + sunlit);
}
