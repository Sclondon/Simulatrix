shader_type spatial;
// Texture Lab's 3D preview: the generated colour as albedo, the generated height as a
// bump (normals from finite differences) and, for the terrain, as real displacement.

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D height_tex : filter_linear, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform float relief = 0.0; // displacement along the normal, metres
uniform float bump = 4.0; // normal-map strength
uniform float texel = 0.00390625; // the step for the height differences, in UV
uniform float roughness_val = 0.8;
uniform float floor_h = 0.0; // heights below this stay level (a sea for the Terrain ramp)

void vertex() {
	if (relief > 0.0) {
		float h = max(textureLod(height_tex, UV * uv_scale, 0.0).r, floor_h);
		VERTEX += NORMAL * (h - 0.5) * relief;
	}
}

void fragment() {
	vec2 uv = UV * uv_scale;
	ALBEDO = texture(albedo_tex, uv).rgb;
	float h0 = texture(height_tex, uv).r;
	float h = max(h0, floor_h);
	float hx = max(texture(height_tex, uv + vec2(texel, 0.0)).r, floor_h);
	float hy = max(texture(height_tex, uv + vec2(0.0, texel)).r, floor_h);
	vec3 n = normalize(vec3((h - hx) * bump, (h - hy) * bump, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	ROUGHNESS = h0 < floor_h ? 0.15 : roughness_val; // the sea shines
}
