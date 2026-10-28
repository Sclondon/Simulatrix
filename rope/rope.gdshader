shader_type spatial;
// The tube of a RopeLine: a still mesh of rings (UV.x how far along, UV.y how far round,
// UV2.x 0 for the centre of an end cap) that this places along the chain's points every
// frame, tapering from root to tip, coloured root to tip, with laid strands, chain links or
// a knot at the end as its RopeStyle says.
render_mode world_vertex_coords, cull_back;

#include "res://rope/rope.gdshaderinc"

uniform vec3 colour_root : source_color = vec3(0.55, 0.45, 0.3);
uniform vec3 colour_tip : source_color = vec3(0.5, 0.41, 0.27);
uniform float twist = 0.0;
uniform float beads = 0.0;
uniform float knot = 0.0;
uniform float shine = 0.0;

varying float along;
varying float round_about;

void vertex() {
	vec3 p, tg, n, b;
	int i;
	float f;
	float t = UV.x;
	rope_frame(t, p, tg, n, b, i, f);
	float a = UV.y * TAU;
	vec3 out_dir = n * cos(a) + b * sin(a);
	float r = rope_radius(t);
	if (beads > 0.0) {
		// links a little longer than thick, pinched between
		float links = rope_length / max(r_root * 3.2, 0.004);
		r *= mix(1.0, 0.5 + 0.75 * sqrt(abs(sin(t * links * PI))), beads);
	}
	if (knot > 0.0) {
		// a knot a few of its radii back from the free end, rounding off the end
		float back = (1.0 - t) * rope_length / max(r_root, 0.004);
		r += knot * r_root * 1.5 * exp(-pow((back - 2.2) / 1.5, 2.0));
	}
	float cap = UV2.x;
	VERTEX = p + out_dir * r * cap;
	// (an end cap faces out along the rope)
	vec3 end_dir = t < 0.5 ? -tg : tg;
	NORMAL = normalize(mix(end_dir, out_dir, cap));
	along = t;
	round_about = UV.y;
}

void fragment() {
	vec3 c = mix(colour_root, colour_tip, along);
	if (twist > 0.0) {
		// three strands laid round it, a turn every six radii or so
		float s = sin((round_about * 3.0 + along * rope_length / max(r_root * 6.0, 0.003)) * TAU);
		c *= 1.0 - twist * 0.5 * smoothstep(0.2, 1.0, s);
	}
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.3, shine);
	SPECULAR = mix(0.25, 0.65, shine);
	METALLIC = shine * 0.35;
}
