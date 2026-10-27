// Fireflies (FireflyField): every one of them moved and blinked here, from where
// it lives and who it is, so that a field of hundreds costs one draw and no work
// on the CPU from frame to frame.
//
// Each firefly is an instance of a MultiMesh: its transform's origin is its home
// (a point on the ground where it rose from) and its scale its size; its custom
// data says who it is:
//   x  its own number (0..1): its timing, its wandering
//   y  its kind: 0 a "big dipper" (Photinus: one long flash every few seconds, as
//      it swoops up in a J), 1 a synchronous firefly (bursts of quick flashes,
//      all of them together, the burst rolling across the field in a wave),
//      2 a cold green Photuris (a slow glow, on and off)
//   z  how dark it must be before it comes out (0..1 of `night`)
//   w  how high it flies over its home, metres
// Drawn two ways, from the same numbers: `is_body` false, a glow (a quad that
// faces the camera: a bright core and a soft halo, added to what is behind it);
// true, the beetle itself (FireflyField's model: its shield, wing cases, and the
// lantern that lights), for the few close to the camera.
//
// They come out as `night` comes (each at its own darkness, rising from the
// grass), wander low and slow, and scatter from `scarers` (up to four points with
// how hard each scatters them: someone running through), flashing as they go,
// then drift back. The mist dims them with distance (`mist`), as the fog does
// everything else; the game's own fog is not laid over them (it would show their quads).

shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_draw_never, fog_disabled, skip_vertex_transform, shadows_disabled;

uniform bool is_body = false;
uniform float night = 1.0;
// Up to four that scatter them: xyz where, w how hard (0..1).
uniform vec4 scarers[4];
uniform float scatter_reach = 2.6;
// The way the synchronous kind's bursts roll across the field, and how fast (m/s).
uniform vec2 wave_way = vec2(0.8, 0.6);
uniform float wave_speed = 3.5;
uniform float brightness = 1.0;
uniform float halo_size = 0.16;
uniform float mist = 0.022;
uniform float far = 70.0;
uniform vec3 colour_dipper : source_color = vec3(0.84, 1.0, 0.38);
uniform vec3 colour_together : source_color = vec3(0.74, 1.0, 0.46);
uniform vec3 colour_cold : source_color = vec3(0.5, 1.0, 0.62);

varying float glow;
varying vec3 tint;
varying vec2 corner;
varying float part;
varying float fade;

float hash1(float n) {
	return fract(sin(n * 91.345 + 7.13) * 47453.5453);
}

// A pulse 0..1 from `x` = 0 to `width`, round-shouldered.
float pulse(float x, float width) {
	return x > 0.0 && x < width ? pow(sin(3.14159 * x / width), 1.5) : 0.0;
}

// How bright it is now (0..1), and how far up its swoop has it (metres).
vec2 blink(float t, float id, int kind, vec2 home) {
	if (kind == 0) {
		// One long flash every 5 to 7 s, swooping up as it flashes (the J).
		float period = 3.4 + 2.2 * hash1(id * 3.1);
		float x = mod(t + id * 97.0, period);
		float lit = pulse(x, 0.8);
		float swoop = x < 1.0 ? -0.1 * sin(3.14159 * clamp(x / 0.45, 0.0, 1.0)) + 0.22 * smoothstep(0.2, 1.0, x) : 0.22 * (1.0 - smoothstep(1.0, period, x));
		return vec2(lit, swoop);
	} else if (kind == 1) {
		// Together: a burst of six quick flashes, then dark; the burst rolls across in a wave.
		float period = 7.0;
		float t_ = t - dot(home, normalize(wave_way)) / wave_speed + (hash1(id * 5.7) - 0.5) * 0.12;
		float burst = floor(t_ / period);
		float x = mod(t_, period);
		// (not every one joins every burst)
		float joins = step(0.3, hash1(id * 13.1 + burst * 1.7));
		float n = floor(x / 0.42);
		float lit = n < 6.0 ? pulse(mod(x, 0.42), 0.16) : 0.0;
		return vec2(lit * joins, 0.0);
	}
	// Cold and slow: a glow that swells and fades, on its own long, wandering beat.
	float period = 2.2 + 1.8 * hash1(id * 7.3);
	float x = mod(t + id * 53.0, period);
	return vec2(pulse(x, 1.4) * 0.8, 0.0);
}

void vertex() {
	vec3 home = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	float id = INSTANCE_CUSTOM.x;
	int kind = int(INSTANCE_CUSTOM.y + 0.5);
	float out_ = smoothstep(INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.z + 0.12, night);
	float high = INSTANCE_CUSTOM.w;
	float t = TIME;
	// Rising out of the grass as it gets dark, to its own height.
	vec3 at = home + vec3(0.0, mix(0.03, high, out_), 0.0);
	// Wandering slowly about its home: a loop of its own, low and lazy.
	float a1 = hash1(id * 1.3) * 6.283;
	float a2 = hash1(id * 2.9) * 6.283;
	float f1 = 0.11 + 0.1 * hash1(id * 4.1);
	float f2 = 0.08 + 0.09 * hash1(id * 6.7);
	float reach = 0.8 + 1.4 * hash1(id * 8.3);
	vec3 wander = vec3(sin(t * f1 + a1) * reach, sin(t * f2 * 1.7 + a2) * 0.25, cos(t * f2 + a1 * 0.7) * reach);
	vec3 moving = vec3(cos(t * f1 + a1) * f1 * reach, 0.0, -sin(t * f2 + a1 * 0.7) * f2 * reach);
	vec2 lit = blink(t, id, kind, home.xz);
	at += wander * out_ + vec3(0.0, lit.y, 0.0);
	// Scattered by anyone running through them, flashing as they go; they drift back.
	float startled = 0.0;
	for (int k = 0; k < 4; k++) {
		vec4 s = scarers[k];
		if (s.w <= 0.0) {
			continue;
		}
		vec3 off = at - (s.xyz + vec3(0.0, 0.8, 0.0));
		float d = length(off);
		float push = s.w * (1.0 - smoothstep(0.0, scatter_reach, d));
		at += normalize(off + vec3(0.0, 0.4, 0.0)) * push * 1.7;
		startled = max(startled, push);
	}
	glow = max(lit.x, smoothstep(0.15, 0.6, startled)) * out_;
	tint = kind == 0 ? colour_dipper : (kind == 1 ? colour_together : colour_cold);
	part = UV2.x;
	vec3 seen = (VIEW_MATRIX * vec4(at, 1.0)).xyz;
	float away = length(seen);
	fade = exp(-away * mist) * (1.0 - smoothstep(far * 0.8, far, away)) * out_;
	if (out_ <= 0.001 || fade <= 0.002) {
		// (not out yet: nothing drawn)
		VERTEX = vec3(0.0, 0.0, 1.0);
	} else if (!is_body) {
		// A glow, facing the camera; never smaller than a few pixels' worth far off.
		corner = UV * 2.0 - 1.0;
		float across = max(halo_size, away * 0.014);
		VERTEX = seen + vec3(corner * across, 0.0);
	} else {
		// The beetle, heading the way it drifts, its nose a little up.
		vec3 ahead = length(moving) > 0.0001 ? normalize(moving + vec3(0.0, 0.04, 0.0)) : vec3(0.0, 0.0, 1.0);
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), ahead));
		vec3 up = cross(ahead, side);
		vec3 body = side * VERTEX.x + up * VERTEX.y + ahead * VERTEX.z;
		VERTEX = (VIEW_MATRIX * vec4(at + body * size, 1.0)).xyz;
	}
}

void fragment() {
	if (!is_body) {
		float r = length(corner);
		float core = exp(-r * r * 45.0);
		float halo = exp(-r * r * 7.0) * 0.5 + exp(-r * r * 1.8) * 0.08;
		float shine = (core * 2.0 + halo) * glow * brightness * fade;
		// (added to what is behind: alpha 0, premultiplied)
		ALBEDO = tint * shine;
		ALPHA = 0.0;
	} else {
		int which = int(part + 0.5);
		vec3 colour = vec3(0.07, 0.06, 0.05);
		float alpha = 1.0;
		if (which == 1) {
			// The shield over the head: pale.
			colour = vec3(0.42, 0.36, 0.24);
		} else if (which == 2) {
			colour = vec3(0.06, 0.055, 0.05);
		} else if (which == 3) {
			colour = vec3(0.16, 0.14, 0.11);
		} else if (which == 4) {
			// The lantern: pale yellow cold, and alight as it flashes.
			colour = mix(vec3(0.32, 0.33, 0.2), tint * 2.2, glow);
		} else if (which == 5) {
			// The hindwings, a blur.
			colour = vec3(0.3, 0.3, 0.28) * 0.35;
			alpha = 0.35;
		}
		// (it is dusk or night: a dark shape, lit a little by its own lantern)
		float lit = which == 4 ? 1.0 : 0.35 + 0.5 * glow;
		ALBEDO = colour * lit * alpha * fade;
		ALPHA = alpha * clamp(fade * 3.0, 0.0, 1.0);
	}
}
