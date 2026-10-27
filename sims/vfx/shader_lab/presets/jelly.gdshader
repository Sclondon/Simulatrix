shader_type spatial;
// Wobble jelly: tap the preview and it squashes and wobbles on a damped spring, a wave running
// up its sides; between taps it breathes. since_poke (seconds since your last tap) is filled in
// by the lab. Glossy, with a soft glow at the edges as if light got inside.
render_mode depth_draw_always;

uniform float since_poke = 100.0;

group_uniforms Jelly;
uniform vec3 color : source_color = vec3(0.3, 0.9, 0.4);
uniform float wobble : hint_range(0.0, 0.5) = 0.2;
uniform float frequency : hint_range(1.0, 20.0) = 9.0;
uniform float damping : hint_range(0.5, 8.0) = 2.2;
uniform float idle_wobble : hint_range(0.0, 0.1) = 0.03;
uniform float translucency : hint_range(0.0, 1.0) = 0.5;

void vertex() {
	float t = since_poke;
	float hit = wobble * exp(-damping * t) * sin(t * frequency);
	float idle = idle_wobble * sin(TIME * 3.0);
	float s = hit + idle;
	VERTEX.y *= 1.0 + s;
	VERTEX.xz *= 1.0 - s * 0.5; // keep the volume: taller means thinner
	VERTEX += NORMAL * sin(VERTEX.y * 6.0 - t * frequency * 1.5) * (abs(hit) * 0.25 + idle_wobble * 0.3);
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = color * (1.0 - translucency * 0.4);
	EMISSION = color * (0.15 + fres * 0.8) * translucency;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
	ALPHA = mix(1.0, 0.8, translucency);
}
