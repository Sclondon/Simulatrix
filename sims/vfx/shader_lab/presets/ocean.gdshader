shader_type spatial;
// Ocean waves: four Gerstner waves move the vertices of the plane. Each lifts the surface in a
// sine and pulls it sideways toward the crests, so crests come out sharp and troughs broad.
// The fragment shades by height, adds foam on the highest crests and a fresnel sky reflection.
// 3D shaders in the lab go on the preview mesh (pick it under Preview); drag to orbit.
render_mode cull_disabled;

group_uniforms Waves;
uniform float amplitude : hint_range(0.0, 0.5) = 0.18;
uniform float wavelength : hint_range(0.5, 6.0) = 2.4;
uniform float steepness : hint_range(0.0, 1.0) = 0.6;
uniform float speed : hint_range(0.0, 3.0) = 1.0;
uniform float direction : hint_range(0.0, 360.0) = 30.0;
group_uniforms Colour;
uniform vec3 deep : source_color = vec3(0.02, 0.12, 0.22);
uniform vec3 shallow : source_color = vec3(0.1, 0.5, 0.55);
uniform vec3 sky_color : source_color = vec3(0.7, 0.82, 0.95);
uniform float foam : hint_range(0.0, 1.0) = 0.5;

varying float crest;

void vertex() {
	vec2 p = VERTEX.xz;
	vec3 offset = vec3(0.0);
	vec2 slope = vec2(0.0);
	float heading = radians(direction);
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float angle = heading + (fi - 1.5) * 0.45;
		float len = wavelength * (1.0 - fi * 0.18);
		float amp = amplitude * (1.0 - fi * 0.2);
		vec2 d = vec2(cos(angle), sin(angle));
		float k = 6.28318 / len;
		// deep-water waves travel at sqrt(g / k)
		float f = k * (dot(d, p) - sqrt(9.8 / k) * TIME * speed * 0.5) + fi * 1.7;
		offset.xz += d * steepness * amp * cos(f);
		offset.y += amp * sin(f);
		slope += d * amp * k * cos(f);
	}
	VERTEX += offset;
	NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	crest = offset.y / max(amplitude, 0.001);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = mix(deep, shallow, clamp(crest * 0.35 + 0.35, 0.0, 1.0));
	col = mix(col, sky_color, fres * 0.7);
	col = mix(col, vec3(0.95), smoothstep(1.9 - foam * 1.2, 2.5, crest));
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
