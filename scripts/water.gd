class_name Water
extends Node3D
## Water in a flat, painted style: a box of it, with this node in the middle of
## its surface. Matte colour that is clear where it is shallow and dark where it
## is deep, pale lines wandering over it, broken glints where it throws the sun
## at the eye, a ragged rim of foam round whatever breaks it, a gentle swell,
## a net of light on whatever lies under it, and a murk for a camera that goes
## under. Things that fall in splash; things that move in it leave rings.
##
## The ideas are those of the water in Salmon Run 2 (shaders/water.gdshader
## there): how much water there really is behind each pixel, read from the depth
## buffer, gives the colour, the clearness and the rim of foam; noise worked out
## in whole numbers, so that it has no seams; a swell that is a sum of trains of
## waves, which the script can work out too, to float things on; rings and wakes
## drawn by the water's own shader from a short list of points.
##
## It holds nothing in and floats nothing: it is only the look, and answers to
## "how deep is this point". Add one, set `size`, and call `watch` for whatever
## should splash.

## How wide, deep (downwards) and long the water is, in metres.
@export var size := Vector3(6.0, 3.0, 6.0): set = _set_size

@export_group("Colour")
## Where there is little water behind the surface, and where there is a lot.
@export var shallow := Color(0.27, 0.66, 0.67): set = _set_shallow
@export var deep := Color(0.05, 0.2, 0.3): set = _set_deep
@export var foam := Color(0.93, 0.98, 0.96): set = _set_foam
## Metres of water before it has its deep colour.
@export var depth_range := 2.6: set = _set_depth_range
## How solid it looks where it is shallow and where it is deep (1 hides what is under it).
@export_range(0.0, 1.0) var alpha_shallow := 0.3: set = _set_alpha_shallow
@export_range(0.0, 1.0) var alpha_deep := 0.97: set = _set_alpha_deep
## What it mirrors when looked across, and how strongly.
@export var sky := Color(0.72, 0.82, 0.9): set = _set_sky
@export_range(0.0, 1.0) var mirror := 0.5: set = _set_mirror
## How much it shows its own colours whatever the light (0 lit like anything else, 1 as if it gave light: for
## a painted scene that lights things by hand). Its glints still come from the lights.
@export_range(0.0, 1.0) var self_lit := 0.0: set = _set_self_lit
## Cut its light into flat tones, as a cel-shaded world is.
@export var banded := false: set = _set_banded

@export_group("Surface")
## Which way it runs, and how fast (metres a second, along this node's X and Z).
## A pool has none. With any, patches of foam drift down it (`foam_drift`).
@export var flow := Vector2.ZERO: set = _set_flow
## The swell: how high (metres), how long its longest wave is, and how fast.
@export var swell_height := 0.03: set = _set_swell_height
@export var swell_length := 5.0: set = _set_swell_length
@export var swell_speed := 0.6: set = _set_swell_speed
## The swell dies away at the sides of the box, so that it meets its walls in a level line.
@export var level_edges := true: set = _set_level_edges
## The pale lines that wander over it: how strong, and how big their loops are (metres).
@export_range(0.0, 1.0) var lines := 0.45: set = _set_lines
@export var line_size := 1.3: set = _set_line_size
## Glints off the sun (and any other light): how bright, and how big (metres).
@export var glint := 2.5: set = _set_glint
@export var glint_size := 0.06: set = _set_glint_size

@export_group("Foam")
## The rim of foam round whatever breaks the surface: how wide (metres), and how ragged.
@export var foam_width := 0.16: set = _set_foam_width
@export_range(0.0, 1.0) var foam_ragged := 0.6: set = _set_foam_ragged
## Patches of foam lying on it (0: none). They drift with `flow`.
@export_range(0.0, 1.0) var foam_drift := 0.0: set = _set_foam_drift

@export_group("Under it")
## The net of light on whatever is under the water (0: none), and how big its loops are.
@export_range(0.0, 1.0) var caustics := 0.5: set = _set_caustics
@export var caustic_size := 0.8: set = _set_caustic_size
## Seen from under the surface: how soon things are lost in the murk (the share
## of the light lost in each metre), and how much even the nearest are tinted.
@export var murk := 0.16: set = _set_murk
@export_range(0.0, 1.0) var murk_tint := 0.25: set = _set_murk_tint

@export_group("What is drawn")
## Read the depth buffer. It is what gives the depth colour, the foam round
## things and the light on the floor. Without it (a renderer or a phone that
## cannot spare it) the water is taken to be `size.y` deep everywhere, the foam
## lies along the sides of the box, and the murk is an even tint.
@export var use_depth := true: set = _set_use_depth
## The four sides of the box, for water that is looked at from beside (a tank).
## They are not drawn from inside.
@export var sides := true: set = _set_sides
## The murk over the picture while the camera is under the surface.
@export var underwater := true
## Drops thrown up by a splash.
@export var drops := true

## How many rings the surface can show at once, how long one lasts (seconds),
## and how fast it opens (metres a second).
const RINGS := 16
const RING_LIFE := 1.7
const RING_SPEED := 0.75
const DROPS := 72
const DROP_LIFE := 0.9
## The trains of waves the swell is the sum of: which way each runs, how long
## it is (as a share of `swell_length`) and how high (of `swell_height`).
const SWELLS: Array[Vector4] = [Vector4(0.34, -0.94, 1.0, 1.0), Vector4(-0.78, -0.62, 0.62, 0.55), Vector4(0.97, 0.26, 0.37, 0.3)]

## What every part of it shares: the noise, the swell, the depth buffer.
const COMMON := """
uniform vec3 shallow : source_color = vec3(0.27, 0.66, 0.67);
uniform vec3 deep : source_color = vec3(0.05, 0.2, 0.3);
uniform vec3 foam : source_color = vec3(0.93, 0.98, 0.96);
uniform float depth_range = 2.6;
uniform float alpha_shallow = 0.3;
uniform float alpha_deep = 0.97;
uniform float banded = 0.0;
// Seconds, counted by the script, which works out the same swell.
uniform float clock = 0.0;
// The box: the world as it sees it, and half its width and length and its whole depth.
uniform mat4 to_box = mat4(1.0);
uniform vec3 box = vec3(3.0, 3.0, 3.0);
uniform float surface_y = 0.0;
uniform float swell_height = 0.03;
uniform float swell_length = 5.0;
uniform float swell_speed = 0.6;
uniform float level_edges = 1.0;
uniform float caustics = 0.5;
uniform float caustic_size = 0.8;
#ifdef USE_DEPTH
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
#endif

// A random number for each corner of a grid, worked out in whole numbers: every
// square of the noise agrees about its corners, on every renderer, where the
// usual fract(sin()) does not.
float hash(vec2 p) {
	ivec2 c = ivec2(round(p));
	uint h = uint(c.x) * 668265261u ^ (uint(c.y) * 374761393u);
	h ^= h >> 15u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h) / 4294967295.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A net of thin lines that wander and never cross twice the same way: the
// level lines of two noises, pulled about by a third. 0 on a line.
float net(vec2 p, float t) {
	vec2 pull = vec2(vnoise(p * 0.5 + vec2(t * 0.11, 3.0)), vnoise(p * 0.5 + vec2(9.0, -t * 0.09))) - 0.5;
	vec2 w = p + pull * 1.6;
	float a = abs(vnoise(w + vec2(0.0, t * 0.17)) - 0.5);
	float b = abs(vnoise(w * 1.31 + vec2(17.0 - t * 0.13, 5.0)) - 0.5);
	return min(a, b);
}

float cut(float value, float edge) {
	float pixel = max(fwidth(value), 0.0005);
	return smoothstep(edge - pixel, edge + pixel, value);
}

// How far inside the sides of the box a point is (metres; less than 0: outside).
float inside(vec3 world) {
	vec3 local = (to_box * vec4(world, 1.0)).xyz;
	return min(box.x - abs(local.x), box.z - abs(local.z));
}

// How high the swell stands at a point (the script has the same sum: Water.height_at).
float swell_at(vec3 world) {
	const vec4 trains[3] = vec4[3](vec4(0.34, -0.94, 1.0, 1.0), vec4(-0.78, -0.62, 0.62, 0.55), vec4(0.97, 0.26, 0.37, 0.3));
	float sum = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = 6.2831853 / (swell_length * trains[i].z);
		sum += trains[i].w * sin(k * dot(trains[i].xy, world.xz) - sqrt(9.8 * k) * swell_speed * clock + float(i) * 1.7);
	}
	return sum * swell_height * mix(1.0, smoothstep(0.0, 0.6, inside(world)), level_edges);
}

// Where in the camera's space the thing drawn at a point of the screen is.
vec3 unproject(vec2 screen_uv, float depth, mat4 inv_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return view.xyz / view.w;
}

// The light on things under the water: 0..1 at a point, for a pixel this big.
float caustic_at(vec2 p, float pixel) {
	float wide = 0.035 + pixel * 0.5 / caustic_size;
	return 1.0 - smoothstep(wide * 0.5, wide, net(p / caustic_size, clock * 1.6));
}
"""

const SURFACE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, world_vertex_coords;
//DEFINES
//COMMON
uniform vec3 sky : source_color = vec3(0.72, 0.82, 0.9);
uniform float mirror = 0.5;
uniform float self_lit = 0.0;
uniform vec2 flow = vec2(0.0);
uniform float lines = 0.5;
uniform float line_size = 1.3;
uniform float glint = 2.5;
uniform float glint_size = 0.06;
uniform float foam_width = 0.16;
uniform float foam_ragged = 0.6;
uniform float foam_drift = 0.0;
// Rings opening on the surface: (x, z, when it began by the clock), and how strong.
uniform vec3 ring_at[16];
uniform float ring_power[16];
uniform int ring_count = 0;
uniform float ring_life = 1.7;
uniform float ring_speed = 0.75;

varying vec3 at;
varying float rise;
varying float spark;

void vertex() {
	rise = swell_at(VERTEX);
	VERTEX.y += rise;
	at = VERTEX;
}

void fragment() {
	vec3 to_eye = CAMERA_POSITION_WORLD - at;
	float far = max(length(to_eye), 0.001);
	float pixel = max(length(fwidth(at.xz)), 0.0001);
	// How steeply it is looked down into: 1 from straight above.
	float down = clamp(abs(to_eye.y) / far, 0.0, 1.0);
	vec2 p = at.xz - flow * clock;
	// A soft, slow blotchiness that every ragged edge is torn with.
	float n = vnoise(p * 3.1 + vec2(clock * 0.21, 0.0)) * 0.65 + vnoise(p * 7.3 - vec2(0.0, clock * 0.29)) * 0.35;

	// How much water there is behind the surface here: along the line of sight
	// (`thick`), and straight down to whatever is seen through it (`below`).
#ifdef USE_DEPTH
	vec3 behind = unproject(SCREEN_UV, texture(depth_texture, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	float thick = max(length(behind) - length(VERTEX), 0.0);
	vec3 under = (INV_VIEW_MATRIX * vec4(behind, 1.0)).xyz;
	float below = max(at.y - under.y, 0.0);
	float edge = thick;
#else
	float below = box.y;
	float thick = below / max(down, 0.25);
	vec3 under = at - to_eye / max(abs(to_eye.y), 0.001) * below;
	float edge = max(inside(at), 0.0);
#endif
	float depth = clamp((below + thick) * 0.5 / depth_range, 0.0, 1.0);
	// (it darkens fast at first and then slowly, as water does)
	depth = 1.0 - (1.0 - depth) * (1.0 - depth);

	vec3 colour = mix(shallow, deep, depth);
	float alpha = mix(alpha_shallow, alpha_deep, depth);
	// (a crest is a little paler than a trough)
	colour *= 1.0 + clamp(rise / max(swell_height, 0.0001), -1.0, 1.0) * 0.07 + (n - 0.5) * 0.16;

	if (!FRONT_FACING) {
		// Seen from underneath it is a bright, wrinkled ceiling.
		float wrinkle = 1.0 - smoothstep(0.03, 0.06 + pixel * 0.4, net(p / line_size * 1.6, clock * 1.4));
		ALBEDO = mix(mix(shallow, sky, 0.45), foam, wrinkle * 0.55);
		ALPHA = mix(0.55, 0.92, 1.0 - down);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		NORMAL = -NORMAL;
		spark = 0.0;
	} else {
		// The light on what lies under it, seen through it.
		float lit_floor = 0.0;
		if (caustics > 0.0) {
			lit_floor = caustic_at(under.xz, pixel) * caustics * smoothstep(0.02, 0.3, below) * (1.0 - depth) * clamp(0.25 / pixel, 0.0, 1.0);
		}
		colour += foam * lit_floor * 0.5;
		alpha = mix(alpha, 1.0, lit_floor * 0.2);

		// Looked across, it mirrors the sky and hides what is under it.
		float graze = pow(1.0 - down, 6.0);
		colour = mix(colour, sky, graze * mirror);
		alpha = mix(alpha, 1.0, graze * 0.85);

		// Pale lines wandering over it (none far off, where they would only shimmer).
		float line = 0.0;
		if (lines > 0.0) {
			float wide = 0.013 + pixel * 0.15 / line_size;
			line = (1.0 - smoothstep(wide * 0.5, wide, net(p / line_size, clock))) * clamp(0.05 * line_size / pixel, 0.0, 1.0);
		}

		// Foam. A band wherever the water is thin, breathing in and out as it
		// laps, and a second, broken line of it standing a little way off.
		float lap = 0.82 + 0.18 * sin(clock * 1.7 + n * 5.0);
		float reach = foam_width * lap * (1.0 - foam_ragged * 0.85 * (1.0 - n));
		float white = (1.0 - cut(edge, reach)) * step(0.0001, foam_width);
		float off = edge / max(foam_width * lap, 0.0001);
		white = max(white, cut(off, 1.55) * (1.0 - cut(off, 1.95)) * cut(n, 0.52) * 0.8 * step(0.0001, foam_width));
		// Patches adrift on it.
		if (foam_drift > 0.001) {
			float drift = vnoise(p * 0.9) * 0.6 + vnoise(p * 2.3 + 11.0) * 0.4;
			white = max(white, cut(drift * (0.6 + 0.8 * n), 1.0 - foam_drift * 0.62) * 0.9);
		}
		// Rings: each opens out from where something broke the surface, thins and
		// is gone; a strong one (a splash) has a second inside it and froth in its middle.
		float ring = 0.0;
		for (int i = 0; i < ring_count; i++) {
			float age = clock - ring_at[i].z;
			if (age < 0.0 || age > ring_life) {
				continue;
			}
			float power = ring_power[i];
			float k = age / ring_life;
			float d = distance(at.xz, ring_at[i].xy);
			float out_at = 0.12 * power + ring_speed * age * (1.0 - 0.3 * k) * (0.7 + 0.3 * power);
			float band = (0.024 + 0.018 * min(power, 1.5)) * (1.0 - 0.4 * k) + pixel;
			float fade = pow(1.0 - k, 1.3) * min(power * 2.5, 1.0);
			float here = 1.0 - smoothstep(band * 0.5, band, abs(d - out_at));
			here = max(here, (1.0 - smoothstep(band * 0.4, band * 0.8, abs(d - out_at * 0.55))) * 0.7 * step(0.8, power));
			here = max(here, (1.0 - smoothstep(out_at * 0.5, out_at, d)) * (1.0 - smoothstep(0.0, 0.45, age)) * step(0.8, power) * 1.4);
			ring = max(ring, here * fade);
		}
		white = max(white, cut(ring * (0.55 + 0.9 * n), 0.4));

		colour = mix(colour, mix(colour, foam, 0.4), line * lines * (1.0 - white));
		colour = mix(colour, foam, white);
		ALBEDO = colour;
		EMISSION = colour * self_lit;
		ALPHA = mix(alpha, 0.96, white);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		// Glints: not from the shape of the waves, which it has none of, but from
		// two noises sliding over one another. Where both are high there is a
		// fleck that could flash; `light` lets it, near where the sun is mirrored.
		vec2 g = p / glint_size;
		spark = vnoise(g * vec2(0.55, 1.0) + vec2(clock * 0.9, clock * 0.35)) * vnoise(g * vec2(1.0, 0.6) * 1.37 - vec2(clock * 0.6, clock * 0.8) + 23.0);
		spark *= (1.0 - white) * clamp(0.5 * glint_size / pixel, 0.0, 1.0);
	}
}

void light() {
	float reach = clamp(ATTENUATION, 0.0, 1.0);
	float facing = max(dot(NORMAL, LIGHT), 0.0);
	float hard = cut(facing * smoothstep(0.15, 0.6, reach), 0.04) * reach;
	float lit = mix(facing * reach, hard, banded);
	DIFFUSE_LIGHT += lit * LIGHT_COLOR / PI;
	// The nearer the mirror line, the smaller a fleck need be to flash.
	float aim = pow(max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0), 20.0);
	float flash = smoothstep(0.5, 0.58, spark * (0.2 + 1.0 * aim)) * smoothstep(0.0, 0.3, lit) * smoothstep(0.05, 0.3, aim);
	SPECULAR_LIGHT += flash * glint * LIGHT_COLOR / PI;
}
"""

## The sides of the box, seen from outside: the same colours, darker the more
## water there is behind, with a pale line where the surface meets them.
const SIDE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, world_vertex_coords;
//DEFINES
//COMMON
varying vec3 at;

void vertex() {
	at = VERTEX;
}

void fragment() {
	float down = max(surface_y - at.y, 0.0);
#ifdef USE_DEPTH
	vec3 behind = unproject(SCREEN_UV, texture(depth_texture, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	float thick = max(length(behind) - length(VERTEX), 0.0);
#else
	float thick = box.x + box.z;
#endif
	float depth = clamp((thick + down * 0.6) / (depth_range * 1.6), 0.0, 1.0);
	depth = 1.0 - (1.0 - depth) * (1.0 - depth);
	vec3 colour = mix(shallow, deep, depth);
	float top = 1.0 - cut(down, 0.035);
	ALBEDO = mix(colour, mix(shallow, foam, 0.5), top);
	ALPHA = mix(mix(alpha_shallow, alpha_deep, depth), 0.9, top);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	// Lit as much from one side as another: it is a body of water, not a wall.
	DIFFUSE_LIGHT += clamp(ATTENUATION, 0.0, 1.0) * LIGHT_COLOR / PI * 0.6;
}
"""

## Laid over the whole picture while the camera is under the surface: things
## fade into the colour of the water the more of it there is in front of them,
## and the net of light lies on whatever faces up. Where the surface cuts across
## the picture, only the part under it is covered.
const VEIL := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
//DEFINES
//COMMON
uniform float murk = 0.16;
uniform float murk_tint = 0.25;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.5, 1.0);
}

void fragment() {
	// (the near side of what the camera sees is at depth 1, on every renderer)
	vec3 lens = unproject(SCREEN_UV, 1.0, INV_PROJECTION_MATRIX);
	vec3 eye = (INV_VIEW_MATRIX * vec4(lens, 1.0)).xyz;
	vec3 way = normalize((INV_VIEW_MATRIX * vec4(normalize(lens), 0.0)).xyz);
	float top = surface_y + swell_at(eye);
	// (under the surface, and inside the box)
	float covered = cut(top - eye.y, 0.0) * step(-0.05, inside(eye)) * step(eye.y, top) * step(surface_y - box.y - 0.3, eye.y);
	// How far this line of sight goes before it leaves the water: by the
	// surface, or by a side of the box.
	float leaves = 1000.0;
	if (way.y > 0.0001) {
		leaves = (top - eye.y) / way.y;
	}
	vec3 local = (to_box * vec4(eye, 1.0)).xyz;
	vec3 turned = (to_box * vec4(way, 0.0)).xyz;
	if (abs(turned.x) > 0.0001) {
		leaves = min(leaves, max((sign(turned.x) * box.x - local.x) / turned.x, 0.0));
	}
	if (abs(turned.z) > 0.0001) {
		leaves = min(leaves, max((sign(turned.z) * box.z - local.z) / turned.z, 0.0));
	}
	float through = leaves;
	float net_light = 0.0;
#ifdef USE_DEPTH
	vec3 seen = unproject(SCREEN_UV, texture(depth_texture, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	float far = length(seen - lens);
	through = min(leaves, far);
	if (far < leaves && caustics > 0.0) {
		// The light of the surface, on whatever faces up towards it.
		vec3 spot = (INV_VIEW_MATRIX * vec4(seen, 1.0)).xyz;
		vec3 faces = normalize(cross(dFdy(spot), dFdx(spot)));
		float pixel = max(length(fwidth(spot.xz)), 0.0001);
		net_light = caustic_at(spot.xz, pixel) * caustics * smoothstep(0.2, 0.7, abs(faces.y)) * clamp(0.25 / pixel, 0.0, 1.0)
				* smoothstep(0.0, 0.3, surface_y - spot.y);
	}
#else
	through = min(leaves, 4.0);
#endif
	float lost = 1.0 - exp(-through * murk);
	vec3 colour = mix(shallow, deep, 0.35 + 0.45 * lost);
	// Shafts of light slanting down from the surface, drifting.
	// (bands across the picture, brightest at the top of it and looking up)
	float across = SCREEN_UV.x + SCREEN_UV.y * 0.4;
	float shaft = sin(across * 21.0 + clock * 0.5) * sin(across * 8.5 - clock * 0.35) + 0.25 * sin(across * 47.0 + clock * 1.3);
	colour += shallow * smoothstep(0.25, 1.0, shaft) * (1.0 - SCREEN_UV.y) * (1.0 - SCREEN_UV.y) * smoothstep(-0.5, 0.5, way.y) * 0.2;
	net_light *= 1.0 - lost;
	ALBEDO = mix(colour, mix(shallow, foam, 0.6), net_light * 0.6);
	ALPHA = covered * mix(mix(murk_tint, 1.0, lost), 1.0, net_light * 0.35);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += clamp(ATTENUATION, 0.0, 1.0) * LIGHT_COLOR / PI * 0.55;
}
"""

## Drops: flat discs turned to the camera, two tones, drawn all at once.
const DROP := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 pale : source_color = vec3(0.93, 0.98, 0.96);
uniform vec3 tint : source_color = vec3(0.27, 0.66, 0.67);

varying float age;
varying float seed;

void vertex() {
	age = INSTANCE_CUSTOM.x;
	seed = INSTANCE_CUSTOM.y;
	float big = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * big, INV_VIEW_MATRIX[1] * big, INV_VIEW_MATRIX[2] * big, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 from = UV * 2.0 - 1.0;
	float pixel = max(fwidth(from.x), 0.001);
	float round = 1.0 - smoothstep(1.0 - pixel * 2.0, 1.0, length(from));
	ALBEDO = mix(mix(tint, pale, 0.45), pale, step(0.0, from.y - from.x * 0.3 + (seed - 0.5) * 0.6));
	ALPHA = round * (1.0 - smoothstep(0.7, 1.0, age));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += clamp(ATTENUATION, 0.0, 1.0) * LIGHT_COLOR / PI * 0.8;
}
"""

static var _shaders := {}

var _surface: MeshInstance3D
var _sides: MeshInstance3D
var _veil: MeshInstance3D
var _spray: MultiMeshInstance3D
var _materials: Array[ShaderMaterial] = []
var _clock := 0.0
## Rings still open: (x, z, when it began), and how strong each is.
var _rings: Array[Vector3] = []
var _powers: Array[float] = []
## Each drop: where it is, how it is moving, how big, how old (1: spent).
var _drop_at := PackedVector3Array()
var _drop_going := PackedVector3Array()
var _drop_size := PackedFloat32Array()
var _drop_age := PackedFloat32Array()
var _drop_seed := PackedFloat32Array()
var _next_drop := 0
var _drops_live := false
## What is being watched: the body, and what was last known of it.
var _watched: Array[Dictionary] = []


func _ready() -> void:
	set_notify_transform(true)
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_place()


# --- What a game asks it ---

## The height of the still surface, in the world.
func surface_y() -> float:
	return global_position.y


## How far under the still surface `point` is, or a large negative number if it
## is not in this water at all.
func depth_at(point: Vector3) -> float:
	var local := to_local(point)
	if absf(local.x) > size.x * 0.5 or absf(local.z) > size.z * 0.5 or local.y < -size.y - 0.5:
		return -1000.0
	return -local.y


## The height of the surface at `point`, swell and all: for floating things on.
func height_at(point: Vector3) -> float:
	var sum := 0.0
	for i in SWELLS.size():
		var train := SWELLS[i]
		var k := TAU / (swell_length * train.z)
		sum += train.w * sin(k * (train.x * point.x + train.y * point.z) - sqrt(9.8 * k) * swell_speed * _clock + i * 1.7)
	var level := 1.0
	if level_edges:
		var local := to_local(point)
		level = smoothstep(0.0, 0.6, minf(size.x * 0.5 - absf(local.x), size.z * 0.5 - absf(local.z)))
	return global_position.y + sum * swell_height * level


## A ring opening on the surface above (or below) `at`. `power` is about 0.3
## for a hand trailed in it and 1 for a body; from 0.8 up it is drawn as a
## splash's ring, with a second inside it and froth in the middle.
func ripple(at: Vector3, power := 0.6) -> void:
	if not is_inside_tree() or depth_at(Vector3(at.x, global_position.y - 0.01, at.z)) < 0.0:
		return
	_drop_old_rings()
	if _rings.size() >= RINGS:
		_rings.remove_at(0)
		_powers.remove_at(0)
	_rings.append(Vector3(at.x, at.z, _clock))
	_powers.append(power)
	_send_rings()


## Something going in, or coming out, at `at`: a strong ring and a burst of
## drops. `power` is about 0.3 for a stone and 1 for a boy off a diving board.
func splash(at: Vector3, power := 1.0) -> void:
	ripple(at, maxf(power, 0.8) + 0.2)
	if not drops or _spray == null or depth_at(Vector3(at.x, global_position.y - 0.01, at.z)) < 0.0:
		return
	var top := Vector3(at.x, global_position.y + 0.03, at.z)
	var count := clampi(roundi(8.0 + 16.0 * power), 6, 40)
	for k in count:
		var i := _next_drop
		_next_drop = (_next_drop + 1) % DROPS
		var round := randf() * TAU
		var out := Vector3(cos(round), 0.0, sin(round))
		var lob := randf()
		_drop_at[i] = top + out * randf_range(0.05, 0.22) * sqrt(power)
		# (most are thrown up and a little out in a crown; a few low and wide)
		_drop_going[i] = out * lerpf(0.5, 2.2, lob) * sqrt(power) + Vector3.UP * lerpf(3.6, 1.6, lob) * sqrt(power) * randf_range(0.7, 1.15)
		_drop_size[i] = randf_range(0.035, 0.085) * (0.7 + 0.5 * minf(power, 1.5))
		_drop_age[i] = -randf_range(0.0, 0.05)
		_drop_seed[i] = randf()
	_drops_live = true


## Keeps an eye on `body` from now on: it splashes when it falls in, rings open
## round it while it stands or moves in the surface, and it splashes a little
## coming out. `height` is how much of it there is above its origin (a figure
## whose origin is at its feet: about its height, or less, if it is to count as
## under before its head is). `weight` scales what it throws up: 1 for a person.
func watch(body: Node3D, height := 1.0, weight := 1.0) -> void:
	for entry in _watched:
		if entry.body == body:
			entry.height = height
			entry.weight = weight
			return
	_watched.append({"body": body, "height": height, "weight": weight, "at": body.global_position, "where": -1, "beat": 0.0})


func unwatch(body: Node3D) -> void:
	for i in _watched.size():
		if _watched[i].body == body:
			_watched.remove_at(i)
			return


## Whether `body` is being watched.
func watches(body: Node3D) -> bool:
	for entry in _watched:
		if entry.body == body:
			return true
	return false


# --- Every frame ---

func _process(delta: float) -> void:
	_clock += delta
	for material in _materials:
		material.set_shader_parameter(&"clock", _clock)
	if not _rings.is_empty() and _clock - _rings[-1].z > RING_LIFE:
		_rings.clear()
		_powers.clear()
		_send_rings()
	_move_drops(delta)
	_place_veil()


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var i := 0
	while i < _watched.size():
		var entry := _watched[i]
		var body: Node3D = entry.body if is_instance_valid(entry.body) else null
		if body == null or not body.is_inside_tree():
			_watched.remove_at(i)
			continue
		i += 1
		_follow(entry, body, delta)


## Where a watched body is with respect to the surface (0: clear of the water,
## 1: breaking the surface, 2: wholly under), and what that calls for.
func _follow(entry: Dictionary, body: Node3D, delta: float) -> void:
	var at := body.global_position
	var going: Vector3 = (at - entry.at) / delta
	entry.at = at
	var depth := depth_at(at)
	var where := 0
	if depth > 0.0:
		where = 1 if depth < entry.height else 2
	var was: int = entry.where
	entry.where = where
	var weight: float = entry.weight
	if was == -1 or where == was:
		if where == 1:
			# Rings round it: slowly while it is still, quicker the faster it goes.
			var along := Vector2(going.x, going.z).length()
			entry.beat -= delta * (0.55 + along * 0.9)
			if entry.beat <= 0.0:
				entry.beat = 0.55
				ripple(at, (0.45 + minf(along, 3.0) * 0.15) * minf(weight, 1.2))
		return
	if was == 0:
		# In: a splash if it fell, a ring if it walked.
		var fell := -going.y
		if fell > 1.5:
			splash(at, clampf(fell / 6.0, 0.25, 1.6) * weight)
		else:
			ripple(at, 0.6 * weight)
	elif where == 0:
		# Out: thrown clear of it, or climbed.
		if going.y > 1.0 and depth > -1.0:
			splash(at, 0.45 * weight)
		else:
			ripple(at, 0.5 * weight)
	elif where == 1:
		# Up through the surface from under it.
		if going.y > 1.2:
			splash(at, 0.4 * weight)
		else:
			ripple(at, 0.8 * weight)
	else:
		ripple(at, 0.7 * weight)
	entry.beat = 0.4


func _move_drops(delta: float) -> void:
	if not _drops_live or _spray == null:
		return
	var any := false
	var top := global_position.y
	var mesh := _spray.multimesh
	for i in DROPS:
		if _drop_age[i] >= 1.0:
			continue
		_drop_age[i] = minf(_drop_age[i] + delta / DROP_LIFE, 1.0)
		if _drop_age[i] > 0.0:
			_drop_going[i] += Vector3.DOWN * 9.0 * delta
			_drop_at[i] += _drop_going[i] * delta
			# (back in the water, it is gone)
			if _drop_at[i].y < top and _drop_going[i].y < 0.0:
				_drop_age[i] = 1.0
		if _drop_age[i] >= 1.0 or _drop_age[i] <= 0.0:
			mesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), _drop_at[i]))
			any = any or _drop_age[i] < 1.0
			continue
		any = true
		mesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * _drop_size[i]), _drop_at[i]))
		mesh.set_instance_custom_data(i, Color(_drop_age[i], _drop_seed[i], 0.0, 0.0))
	_drops_live = any


func _place_veil() -> void:
	if _veil == null:
		return
	var camera := get_viewport().get_camera_3d() if underwater else null
	if camera == null:
		_veil.visible = false
		return
	var local := to_local(camera.global_position)
	var slack := camera.near * 2.0 + 0.25 + swell_height
	_veil.visible = absf(local.x) < size.x * 0.5 + slack and absf(local.z) < size.z * 0.5 + slack and local.y < slack and local.y > -size.y - slack
	if _veil.visible:
		_veil.global_transform = camera.global_transform.translated_local(Vector3(0.0, 0.0, -camera.near - 0.02))


# --- Building it ---

func _build() -> void:
	for child in [_surface, _sides, _veil, _spray]:
		if child:
			child.queue_free()
	_materials.clear()
	_sides = null

	var top := _material(SURFACE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	# (fine enough to be lifted into a swell: a vertex every 60 cm or so)
	plane.subdivide_width = clampi(ceili(size.x / 0.6), 1, 64)
	plane.subdivide_depth = clampi(ceili(size.z / 0.6), 1, 64)
	_surface = _part(plane, top)
	_surface.extra_cull_margin = swell_height * 2.0 + 0.1

	if sides:
		_sides = _part(_walls(), _material(SIDE))

	# The murk: a sheet held in front of the camera while it is under.
	var sheet := QuadMesh.new()
	_veil = _part(sheet, _material(VEIL))
	_veil.top_level = true
	_veil.visible = false
	_veil.extra_cull_margin = 16384.0
	(_veil.material_override as ShaderMaterial).render_priority = 100

	_spray = MultiMeshInstance3D.new()
	_spray.top_level = true
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.extra_cull_margin = 16384.0
	var drop_material := ShaderMaterial.new()
	drop_material.shader = _shader(DROP, false)
	drop_material.set_shader_parameter(&"pale", foam)
	drop_material.set_shader_parameter(&"tint", shallow)
	var disc := QuadMesh.new()
	disc.material = drop_material
	_spray.multimesh = MultiMesh.new()
	_spray.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_spray.multimesh.use_custom_data = true
	_spray.multimesh.mesh = disc
	_spray.multimesh.instance_count = DROPS
	_drop_at.resize(DROPS)
	_drop_going.resize(DROPS)
	_drop_size.resize(DROPS)
	_drop_age.resize(DROPS)
	_drop_seed.resize(DROPS)
	_drop_age.fill(1.0)
	for i in DROPS:
		_spray.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	add_child(_spray)
	_spray.global_transform = Transform3D.IDENTITY
	_place()
	_send_rings()


func _part(mesh: Mesh, material: ShaderMaterial) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


## The four sides of the box, facing out, a hair inside it so that they do not
## fight with walls built exactly round it.
func _walls() -> ArrayMesh:
	var half := Vector3(size.x * 0.5 - 0.01, size.y, size.z * 0.5 - 0.01)
	var corners := [Vector3(-half.x, 0.0, half.z), Vector3(half.x, 0.0, half.z), Vector3(half.x, 0.0, -half.z), Vector3(-half.x, 0.0, -half.z)]
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var out := (b - a).cross(Vector3.UP).normalized()
		var low := Vector3.DOWN * half.y
		for point: Vector3 in [a, a + low, b, b, a + low, b + low]:
			points.append(point)
			normals.append(out)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _material(code: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader(code, use_depth)
	_materials.append(material)
	for setting: StringName in [&"shallow", &"deep", &"foam", &"depth_range", &"alpha_shallow", &"alpha_deep", &"sky", &"mirror", &"self_lit", &"swell_height", &"swell_length", &"swell_speed", &"lines", &"line_size", &"glint", &"glint_size", &"foam_width", &"foam_ragged", &"foam_drift", &"caustics", &"caustic_size", &"murk", &"murk_tint"]:
		material.set_shader_parameter(setting, get(setting))
	material.set_shader_parameter(&"banded", 1.0 if banded else 0.0)
	material.set_shader_parameter(&"level_edges", 1.0 if level_edges else 0.0)
	material.set_shader_parameter(&"ring_life", RING_LIFE)
	material.set_shader_parameter(&"ring_speed", RING_SPEED)
	material.set_shader_parameter(&"clock", _clock)
	return material


static func _shader(code: String, depth: bool) -> Shader:
	var key := [code.hash(), depth]
	if not _shaders.has(key):
		var shader := Shader.new()
		shader.code = code.replace("//DEFINES", "#define USE_DEPTH" if depth else "").replace("//COMMON", COMMON)
		_shaders[key] = shader
	return _shaders[key]


## Tells the shaders where the box is, and which way the water runs in the world.
func _place() -> void:
	var run := global_basis * Vector3(flow.x, 0.0, flow.y)
	for material in _materials:
		material.set_shader_parameter(&"to_box", global_transform.affine_inverse())
		material.set_shader_parameter(&"box", Vector3(size.x * 0.5, size.y, size.z * 0.5))
		material.set_shader_parameter(&"surface_y", global_position.y)
		material.set_shader_parameter(&"flow", Vector2(run.x, run.z))


func _drop_old_rings() -> void:
	while not _rings.is_empty() and _clock - _rings[0].z > RING_LIFE:
		_rings.remove_at(0)
		_powers.remove_at(0)


func _send_rings() -> void:
	if _surface == null:
		return
	var at := PackedVector3Array(_rings)
	var power := PackedFloat32Array(_powers)
	at.resize(RINGS)
	power.resize(RINGS)
	var material := _surface.material_override as ShaderMaterial
	material.set_shader_parameter(&"ring_at", at)
	material.set_shader_parameter(&"ring_power", power)
	material.set_shader_parameter(&"ring_count", _rings.size())


func _pass(setting: StringName, value: Variant) -> void:
	for material in _materials:
		material.set_shader_parameter(setting, value)


# --- Settings: each one is passed on to the shaders as it is changed ---

func _set_size(value: Vector3) -> void:
	size = value
	if is_inside_tree():
		_build()

func _set_use_depth(value: bool) -> void:
	use_depth = value
	if is_inside_tree():
		_build()

func _set_sides(value: bool) -> void:
	sides = value
	if is_inside_tree():
		_build()

func _set_flow(value: Vector2) -> void:
	flow = value
	if is_inside_tree():
		_place()

func _set_shallow(value: Color) -> void:
	shallow = value
	_pass(&"shallow", value)

func _set_deep(value: Color) -> void:
	deep = value
	_pass(&"deep", value)

func _set_foam(value: Color) -> void:
	foam = value
	_pass(&"foam", value)

func _set_sky(value: Color) -> void:
	sky = value
	_pass(&"sky", value)

func _set_depth_range(value: float) -> void:
	depth_range = value
	_pass(&"depth_range", value)

func _set_alpha_shallow(value: float) -> void:
	alpha_shallow = value
	_pass(&"alpha_shallow", value)

func _set_alpha_deep(value: float) -> void:
	alpha_deep = value
	_pass(&"alpha_deep", value)

func _set_mirror(value: float) -> void:
	mirror = value
	_pass(&"mirror", value)


func _set_self_lit(value: float) -> void:
	self_lit = value
	_pass(&"self_lit", value)

func _set_banded(value: bool) -> void:
	banded = value
	_pass(&"banded", 1.0 if value else 0.0)

func _set_swell_height(value: float) -> void:
	swell_height = value
	_pass(&"swell_height", value)

func _set_swell_length(value: float) -> void:
	swell_length = value
	_pass(&"swell_length", value)

func _set_swell_speed(value: float) -> void:
	swell_speed = value
	_pass(&"swell_speed", value)

func _set_level_edges(value: bool) -> void:
	level_edges = value
	_pass(&"level_edges", 1.0 if value else 0.0)

func _set_lines(value: float) -> void:
	lines = value
	_pass(&"lines", value)

func _set_line_size(value: float) -> void:
	line_size = value
	_pass(&"line_size", value)

func _set_glint(value: float) -> void:
	glint = value
	_pass(&"glint", value)

func _set_glint_size(value: float) -> void:
	glint_size = value
	_pass(&"glint_size", value)

func _set_foam_width(value: float) -> void:
	foam_width = value
	_pass(&"foam_width", value)

func _set_foam_ragged(value: float) -> void:
	foam_ragged = value
	_pass(&"foam_ragged", value)

func _set_foam_drift(value: float) -> void:
	foam_drift = value
	_pass(&"foam_drift", value)

func _set_caustics(value: float) -> void:
	caustics = value
	_pass(&"caustics", value)

func _set_caustic_size(value: float) -> void:
	caustic_size = value
	_pass(&"caustic_size", value)

func _set_murk(value: float) -> void:
	murk = value
	_pass(&"murk", value)

func _set_murk_tint(value: float) -> void:
	murk_tint = value
	_pass(&"murk_tint", value)
