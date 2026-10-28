shader_type spatial;
render_mode cull_disabled;
// A Flock's boids, all drawn by one MultiMesh. The instance colour is the boid's own shade
// (multiplied into COLOR with the mesh's vertex colours); its custom data is its pose, which
// the Flock writes as it moves them: x the beat phase (radians, kept by the Flock so a change
// of pace never jumps), y effort (0..2), z glide (0: beating, 1: wings held out), w fright
// (0..1). The mesh faces -z, wings along +x/-x, up +y.
//
// motion 0 flap: everything further out than body_half is a wing, hinged at the body and
// beaten up and down (the outer wing lags, so it bends like a real one). 1 swim: the tail half
// swishes side to side in a wave running back along the body. 2 walk: everything below leg_top
// is a leg, swung fore and aft from the hip in diagonal pairs, and the body bobs.

uniform vec4 colour : source_color = vec4(0.12, 0.11, 0.13, 1.0);
uniform int motion = 0;
uniform float amount = 0.7;
uniform float body_half = 0.06;
uniform float span_half = 0.5;
uniform float length_half = 0.5;
uniform float leg_top = 0.35;
uniform float sheen = 0.25;
uniform float roughness = 0.65;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float effort = INSTANCE_CUSTOM.y;
	float glide = INSTANCE_CUSTOM.z;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	if (motion == 0) {
		float ax = abs(v.x);
		float beat = sin(phase) * amount * (0.75 + 0.25 * effort);
		if (ax > body_half) {
			float side = sign(v.x);
			float out_d = ax - body_half;
			float tip = clamp(out_d / max(span_half - body_half, 0.001), 0.0, 1.0);
			// held out a little above level when gliding; the tip lags the beat
			float a = mix(beat + sin(phase - 1.1) * amount * 0.45 * tip, 0.1 + 0.08 * tip, glide);
			float c = cos(a);
			float s = sin(a);
			v.x = side * (body_half + out_d * c - v.y * s);
			v.y = out_d * s + v.y * c;
			float nx = n.x * side;
			n.x = side * (nx * c - n.y * s);
			n.y = nx * s + n.y * c;
		}
		// the body rides opposite the wings
		v.y -= sin(phase) * amount * 0.05 * span_half * (1.0 - glide);
	} else if (motion == 1) {
		float w = clamp((v.z / length_half + 0.35) / 1.35, 0.0, 1.0);
		w *= w;
		float wave = sin(phase - v.z / length_half * 2.6);
		v.x += wave * amount * w * length_half * (0.7 + 0.3 * effort);
		v.x -= sin(phase) * amount * 0.06 * length_half;
		n.x += wave * amount * w * 0.8;
	} else if (motion == 2) {
		float stride = clamp(effort, 0.0, 1.5);
		if (v.y < leg_top) {
			float pair = sign(v.x) * sign(v.z + 0.0001);
			v.z += sin(phase) * pair * amount * (leg_top - v.y) * stride;
		}
		v.y += abs(sin(phase)) * 0.04 * leg_top * stride;
	}
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	ALBEDO = COLOR.rgb * colour.rgb;
	ROUGHNESS = roughness;
	SPECULAR = sheen;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
