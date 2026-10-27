// The rim of air round the Earth, past its edge: drawn on the back faces of a shell, finding
// how close each line of sight passes to the Earth's centre. It fades out over `thickness`
// (Earth radii) above the limb and is brighter on the sunny side. The Earth hides the rest.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 air : source_color = vec3(0.4, 0.75, 1.0);
uniform float earth_radius = 1.0;
uniform float thickness = 0.07;

varying vec3 centre;

void vertex() {
	centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(VERTEX);
	float t = dot(centre, dir);
	vec3 off = dir * t - centre;
	float d = (length(off) / earth_radius - 1.0) / thickness;
	vec3 edge = normalize(mat3(INV_VIEW_MATRIX) * off);
	float lit = smoothstep(-0.35, 0.3, dot(edge, normalize(sun_dir)));
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.5) * 0.75 * lit * step(0.0, d);
	ALBEDO = air * a;
}
