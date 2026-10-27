shader_type canvas_item;
// Plasma: a sum of sine waves gives a smooth field; a cosine palette turns it into colour.
// 2D shaders in the lab run over the whole preview. UV goes 0..1 across it.
// Filled in for you: resolution (pixels), mouse (UV under your finger), since_poke (seconds since a tap).
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

group_uniforms Motion;
uniform float speed : hint_range(0.0, 3.0) = 0.6;
uniform float scale : hint_range(1.0, 20.0) = 6.0;
group_uniforms Palette;
uniform vec3 offset_color : source_color = vec3(0.5, 0.42, 0.55);
uniform vec3 swing_color : source_color = vec3(0.5, 0.45, 0.45);
uniform float phase : hint_range(0.0, 1.0) = 0.6;
uniform int bands : hint_range(0, 16) = 0;

// Inigo Quilez's cosine palette: offset + swing * cos(2 pi (t + a phase per channel))
vec3 palette(float t) {
	return offset_color + swing_color * cos(6.28318 * (t + vec3(0.0, 0.1, 0.2) + phase));
}

void fragment() {
	float aspect = resolution.x / resolution.y;
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0) * scale;
	vec2 m = (mouse - 0.5) * vec2(aspect, 1.0) * scale;
	float t = TIME * speed;
	float v = sin(p.x + t);
	v += sin((p.y + t) * 0.5);
	v += sin((p.x + p.y + t) * 0.5);
	v += sin(length(p - m) * 1.5 - t * 2.0); // rings spread from your finger
	v *= 0.25;
	if (bands > 0) {
		v = floor(v * float(bands)) / float(bands); // posterize into flat bands
	}
	COLOR = vec4(palette(v), 1.0);
}
