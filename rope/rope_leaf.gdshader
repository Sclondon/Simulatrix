shader_type spatial;
// The leaves of a RopeLine, one MultiMesh: each instance's custom data says where it grows
// (x how far along, y how far round, z its size, w a random number), and this places it on
// the chain every frame. It stands out from the stem at `lean`, hangs with gravity (or floats
// up) by `droop`, streams out in the water or air moving past it (the flow less the stem's own
// speed) by `stream`, curves along its length into that by `curl`, flutters, and a blade's
// edges ripple (`ruffle`). No work on the CPU for any leaf.
render_mode world_vertex_coords, cull_disabled;

#include "res://rope/rope.gdshaderinc"

uniform vec3 vel[25];
// A flutter clock RopeLine runs, quicker in a stronger flow (so a change of speed never makes
// the phase jump, as TIME times a speed would).
uniform float clock = 0.0;
// The water or air's velocity round it (m/s), and which way leaves droop (down, or up when
// the rope is buoyant).
uniform vec3 flow = vec3(0.0);
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float size = 0.2;
uniform float lean = 0.8;
uniform float droop = 0.2;
uniform float stream = 0.3;
uniform float flutter = 0.15;
uniform float curl = 0.0;
uniform float ruffle = 0.0;
uniform float vary = 0.4;
uniform float shine = 0.0;
uniform vec3 colour_root : source_color = vec3(0.19, 0.31, 0.14);
uniform vec3 colour_tip : source_color = vec3(0.24, 0.36, 0.15);

varying vec3 tint;
varying float shade;

void vertex() {
	float t = INSTANCE_CUSTOM.x;
	float angle = INSTANCE_CUSTOM.y * TAU;
	float s = INSTANCE_CUSTOM.z * size;
	float rnd = INSTANCE_CUSTOM.w;
	vec3 p, tg, n, b;
	int i;
	float f;
	rope_frame(t, p, tg, n, b, i, f);
	vec3 v = mix(vel[i], vel[i + 1], f);
	vec3 out_dir = n * cos(angle) + b * sin(angle);
	// (at rest: out from the stem at its lean, each a little its own)
	float ln = lean * (0.7 + 0.6 * fract(rnd * 7.13));
	vec3 d = tg * cos(ln) + out_dir * sin(ln);
	// (the water going past it: the flow, less the stem's own speed)
	vec3 w = flow - v;
	float ws = length(w);
	vec3 wd = ws > 1e-4 ? w / ws : vec3(0.0);
	float push = stream * clamp(ws * 3.0, 0.0, 1.0);
	d = normalize(d + wd * push * 2.5 + fall_dir * droop * 1.5 + out_dir * 0.05);
	// (fluttering: rolling about its midrib and nodding, quicker in a stronger flow)
	float ph = clock * (2.5 + 3.5 * rnd) + rnd * TAU + t * 7.0;
	// (its width across the stem: two guesses summed, never both gone at once, so it never flips)
	vec3 across = cross(tg, out_dir);
	vec3 x = normalize(across - d * dot(across, d) + cross(d, out_dir - d * dot(out_dir, d)) + vec3(1e-5));
	vec3 z = cross(x, d);
	float roll = flutter * 0.9 * sin(ph);
	z = z * cos(roll) + x * sin(roll);
	d = normalize(d + z * flutter * 0.3 * sin(ph * 1.37 + 1.0));
	z = normalize(z - d * dot(z, d));
	x = cross(d, z);
	vec3 local = VERTEX;
	// (a blade's edges ripple along it; its midrib does not)
	local.z += ruffle * 0.6 * abs(local.x) * sin(local.y * 22.0 - clock * 5.0 + rnd * TAU);
	// (curving along its length into the flow, and with its droop)
	vec3 bow = (wd * push + fall_dir * droop * 0.5) * curl;
	vec3 foot = p + out_dir * rope_radius(t) * 0.8;
	VERTEX = foot + (x * local.x + d * local.y + z * local.z) * s + bow * local.y * local.y * s;
	NORMAL = z;
	shade = UV.x;
	tint = mix(colour_root, colour_tip, t) * (1.0 + (fract(rnd * 13.7) - 0.5) * vary * 0.9);
}

void fragment() {
	ALBEDO = tint * shade;
	ROUGHNESS = mix(0.9, 0.35, shine);
	SPECULAR = mix(0.2, 0.55, shine);
	BACKLIGHT = tint * 0.35;
}
