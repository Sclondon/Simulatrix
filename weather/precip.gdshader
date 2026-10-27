shader_type spatial;
// Rain, snow, hail and splashes, all moved here on the GPU: each instance of a MultiMesh of quads
// is one drop, placed from its INSTANCE_ID in a box that wraps round the camera, so the air near
// the eye is always full and nothing is simulated on the CPU. A raindrop is a streak along the way
// it falls (motion blur), turned to face the camera round that line; a flake tumbles and drifts;
// a splash is a little crown on the ground that opens and fades, then appears somewhere else.
// Splashes sit on the ground: at `ground_y`, or on `ground_map` (a height map over `ground_rect`)
// when one is given (WeatherRig.set_ground).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform int kind = 0;               // 0 rain, 1 snow, 2 hail, 3 splash, 4 bouncing hail
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform float speed = 9.0;          // m/s along fall_dir
uniform vec3 box = vec3(36.0, 36.0, 36.0);
uniform float width = 0.02;
uniform float streak = 0.8;
uniform float rate = 3.0;           // splashes: how many times a second each one goes off
uniform vec4 tint : source_color = vec4(0.75, 0.8, 0.9, 0.35);
uniform float ground_y = 0.0;
uniform bool use_ground_map = false;
uniform sampler2D ground_map : filter_linear, repeat_disable; // heights in metres (R)
uniform vec4 ground_rect = vec4(-300.0, -300.0, 600.0, 600.0); // x, z, width, depth

varying float fade;
varying float life;

vec4 hash4(float n) {
	return fract(sin(vec4(n, n + 1.7, n + 3.1, n + 5.3)) * vec4(43758.5453, 22578.1459, 19642.3490, 31337.1337));
}

// The ground under a splash
float terrain(vec2 p) {
	if (!use_ground_map) return ground_y;
	return textureLod(ground_map, (p - ground_rect.xy) / ground_rect.zw, 0.0).r;
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec4 h = hash4(id * 0.013 + 0.1);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 o;
	life = 0.0;
	if (kind >= 3) {
		// A splash: a new spot on the ground each time it goes off
		float cycle = TIME * rate * (0.7 + 0.6 * h.w) + h.z * 17.0;
		float k = floor(cycle);
		life = fract(cycle);
		vec4 s = hash4(id * 0.37 + k * 1.618);
		o.xz = cam.xz + (s.xy - 0.5) * box.xz;
		o.y = terrain(o.xz) + 0.02;
		if (kind == 4) {
			// Hail bounces: up and down again
			o.y += 4.0 * life * (1.0 - life) * (0.3 + s.z * 0.5);
			o.xz += (s.zw - 0.5) * life * 0.8;
		}
	} else {
		vec3 p = h.xyz * box + fall_dir * speed * TIME;
		o = cam + mod(p - cam + box * 0.5, box) - box * 0.5;
		if (kind == 1) {
			o.xz += vec2(sin(TIME * 1.3 + id * 1.37), cos(TIME * 1.1 + id * 2.11)) * 0.35;
			o.y += sin(TIME * 2.0 + id) * 0.05;
		}
	}
	vec3 to_cam = normalize(cam - o);
	float d = distance(cam, o);
	// Never thinner than about a pixel and a half, so far drops still read
	float w = width * max(1.0, d / 5.0);
	float ht = w;
	vec3 up;
	vec3 side;
	if (kind == 0) {
		up = normalize(-fall_dir);
		side = normalize(cross(up, to_cam));
		ht = streak;
	} else if (kind == 3) {
		up = vec3(0.0, 1.0, 0.0);
		side = normalize(cross(up, to_cam));
		w *= 0.4 + 0.8 * life;
		ht = w * 0.6;
		o.y += ht * 0.5;
	} else {
		float a = TIME * 2.0 + id * 0.7;
		side = normalize(INV_VIEW_MATRIX[0].xyz * cos(a) + INV_VIEW_MATRIX[1].xyz * sin(a));
		up = normalize(cross(to_cam, side));
	}
	vec3 wp = o + side * VERTEX.x * w + up * VERTEX.y * ht;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	fade = smoothstep(0.5, 2.0, d) * (1.0 - smoothstep(box.x * 0.35, box.x * 0.5, d));
	if (kind == 3) fade *= 1.0 - life;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a;
	if (kind == 0) {
		a = (1.0 - abs(p.x)) * (1.0 - smoothstep(0.2, 1.0, abs(p.y))) * (0.6 + 0.4 * (0.5 - p.y * 0.5));
	} else if (kind == 3) {
		// A crown: a ring seen from the side, open at the top, and a dot where the drop hit
		float r = length(vec2(p.x, (p.y - 1.0) * 1.2));
		a = smoothstep(0.75, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
		a += (1.0 - smoothstep(0.0, 0.3, length(p - vec2(0.0, 0.9)))) * 0.6;
	} else {
		a = 1.0 - smoothstep(0.25, 1.0, length(p));
	}
	a *= tint.a * fade;
	if (a < 0.01) discard;
	ALBEDO = tint.rgb;
	ALPHA = a;
}
