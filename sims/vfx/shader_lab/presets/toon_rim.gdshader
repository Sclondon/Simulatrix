shader_type spatial;
// Toon + rim: the light() function runs once per light and snaps the light into flat bands,
// adds a rim of light round the silhouette on the lit side, and a crisp specular blob.

group_uniforms Shading;
uniform vec3 base_color : source_color = vec3(0.95, 0.45, 0.3);
uniform vec3 shade_color : source_color = vec3(0.3, 0.14, 0.32);
uniform int bands : hint_range(1, 6) = 2;
uniform float softness : hint_range(0.0, 0.2) = 0.02;
group_uniforms Rim;
uniform vec3 rim_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float rim_width : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 2.0) = 1.0;
uniform float specular_size : hint_range(0.0, 1.0) = 0.25;

// light() works in linear colour, but in the Compatibility renderer a source_color uniform arrives
// as picked (sRGB), so convert it first or the bands come out washed and pale.
vec3 to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

void fragment() {
	ALBEDO = vec3(1.0); // the colours come from light()
	AO = 0.0; // no ambient light and
	SPECULAR = 0.0; // no sky reflections: only the bands below
	ROUGHNESS = 1.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5; // half-Lambert, 0 at the back, 1 facing the light
	float l = clamp(ndl * ATTENUATION, 0.0, 1.0) * float(bands);
	float edge = max(softness * 5.0, 0.001);
	float stepped = (floor(l) + smoothstep(0.5 - edge, 0.5 + edge, fract(l))) / float(bands);
	// the light's hue without its strength, so the bands come out in exactly the colours picked
	vec3 tint = LIGHT_COLOR / max(max(LIGHT_COLOR.r, LIGHT_COLOR.g), max(LIGHT_COLOR.b, 0.001));
	DIFFUSE_LIGHT += mix(to_linear(shade_color), to_linear(base_color), clamp(stepped, 0.0, 1.0)) * tint;
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.05, 1.0 - dot(NORMAL, VIEW));
	DIFFUSE_LIGHT += to_linear(rim_color) * rim * rim_strength * smoothstep(0.4, 0.7, ndl) * ATTENUATION * tint * 0.6;
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(1.0 - specular_size * 0.08, 1.0 - specular_size * 0.08 + 0.005, dot(NORMAL, h));
	SPECULAR_LIGHT += vec3(spec) * ATTENUATION * tint * 0.8;
}
