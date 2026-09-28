shader_type canvas_item;
// Turns the summed blobs into a liquid: solid where the density passes a
// threshold, lighter toward the surface, foamy where it's moving fast.

uniform sampler2D field : filter_linear;
uniform vec4 deep : source_color = vec4(0.06, 0.3, 0.6, 1.0);
uniform vec4 light : source_color = vec4(0.36, 0.78, 1.0, 1.0);
uniform vec4 foam : source_color = vec4(0.9, 0.97, 1.0, 1.0);

void fragment() {
	vec4 f = texture(field, UV);
	float density = f.r;
	float edge = smoothstep(0.34, 0.42, density);
	// Thin near the surface, deep and dark in the middle of the body
	float depth = smoothstep(0.42, 0.95, density);
	vec3 col = mix(light.rgb, deep.rgb, depth);
	// Fast-moving liquid churns white
	float churn = clamp(f.g / max(density, 0.001), 0.0, 1.0);
	col = mix(col, foam.rgb, smoothstep(0.55, 1.0, churn) * 0.6);
	// A bright rim along the surface
	col = mix(col, foam.rgb, (1.0 - smoothstep(0.42, 0.47, density)) * 0.7);
	COLOR = vec4(col, edge);
}
