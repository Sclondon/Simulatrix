// The Earth as a lit ball: Atlas's globe (NASA's Blue Marble, the City Lights at night, the
// sun glinting off the sea, a warm band along the line between day and night, the air
// thickening toward the edge, cloud shadows) moved from a ray-traced canvas to a sphere mesh.
// The maps are looked up from the object-space normal, so the ball spins with its node.
shader_type spatial;
render_mode unshaded;

uniform sampler2D day_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D night_map : source_color, filter_linear_mipmap, repeat_enable;
// Towards the sun, in the world and in the Earth's own (spinning) frame.
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform vec3 air : source_color = vec3(0.4, 0.75, 1.0);
uniform float city_lights = 1.0;
uniform float cloud_cover = 0.42;
uniform float cloud_opacity = 0.85;
uniform float cloud_drift = 0.0;
uniform float cloud_height = 1.025;

varying vec3 obj_n;
varying vec3 world_n;
varying vec3 world_pos;

#include "res://sims/orbits3d/clouds.gdshaderinc"

vec2 map_uv(vec3 n) {
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.x, n.z);
	return vec2(lon / TAU + 0.5, 0.5 - lat / PI);
}

float ocean_at(vec3 c) {
	return smoothstep(0.02, 0.08, c.b - max(c.r, c.g * 0.9));
}

void vertex() {
	obj_n = NORMAL;
	world_n = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(obj_n);
	vec3 wn = normalize(world_n);
	vec3 sun = normalize(sun_dir);
	vec3 eye = normalize(CAMERA_POSITION_WORLD - world_pos);
	// (no line of blur down the seam where atan wraps: see seam_grad)
	vec2 uv = map_uv(n);
	vec4 g = seam_grad(uv);

	vec3 sat = textureGrad(day_map, uv, g.xy, g.zw).rgb;
	vec3 town = textureGrad(night_map, uv, g.xy, g.zw).rgb;
	float l = dot(wn, sun);
	float day = smoothstep(-0.12, 0.12, l);
	// the clouds are up in the air, so their shadows fall away from the sun
	float shadow = cloud_at(normalize(n * cloud_height + normalize(sun_local) * (cloud_height - 1.0))) * cloud_opacity;
	vec3 ground = sat * (1.0 - 0.45 * shadow * day);
	ground *= 0.35 + 0.8 * clamp(l, 0.0, 1.0);
	float sea = ocean_at(sat);
	ground += vec3(1.0, 0.92, 0.75) * pow(max(dot(reflect(-sun, wn), eye), 0.0), 140.0) * sea * 0.4;
	ground += vec3(0.9, 0.35, 0.1) * 0.12 * exp(-abs(l) * 14.0);
	vec3 dark = sat * vec3(0.09, 0.11, 0.17) + vec3(0.0, 0.004, 0.012);
	float glow = smoothstep(0.12, 0.55, town.r) * city_lights * (1.0 - shadow * 0.8);
	dark += vec3(1.0, 0.78, 0.42) * glow * 1.3;
	ground = mix(dark, ground, day);
	float facing = clamp(dot(wn, eye), 0.0, 1.0);
	ALBEDO = mix(ground, air, pow(1.0 - facing, 2.5) * 0.5 * day);
}
