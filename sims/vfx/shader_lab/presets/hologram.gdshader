shader_type spatial;
// Hologram: unlit and added to whatever is behind it. Brightest at the silhouette (fresnel),
// scan lines scroll up in world height, the whole thing flickers, and now and then a glitch
// jolts the vertices sideways.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

group_uniforms Look;
uniform vec3 color : source_color = vec3(0.2, 0.85, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float line_density : hint_range(5.0, 200.0) = 60.0;
uniform float line_speed : hint_range(-5.0, 5.0) = 1.0;
uniform float brightness : hint_range(0.0, 4.0) = 1.5;
group_uniforms Glitch;
uniform float flicker : hint_range(0.0, 1.0) = 0.3;
uniform float glitch : hint_range(0.0, 0.3) = 0.05;

varying vec3 world_pos;

float hash1(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	float jolt = step(0.93, hash1(floor(TIME * 12.0))) * glitch;
	VERTEX.x += jolt * sin(VERTEX.y * 40.0 + TIME * 50.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);
	float lines = pow(0.5 + 0.5 * sin(world_pos.y * line_density - TIME * line_speed * 10.0), 4.0);
	float on = 1.0 - flicker * step(0.8, hash1(floor(TIME * 20.0))) * 0.6;
	ALBEDO = color * (fres * 1.5 + 0.12 + lines * 0.35) * brightness * on;
}
