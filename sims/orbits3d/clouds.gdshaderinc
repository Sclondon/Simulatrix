// Atlas's cloud cover, shared by the Earth (for cloud shadows) and the cloud shell.
// Needs uniforms cloud_cover and cloud_drift.

// A hash built from small multiplications rather than the sine of a big number: the sine
// trick loses its precision on phones and leaves seams and blocks in the noise.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
			mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
			f.z);
}

// How much cloud there is over a point (a direction from the centre of the Earth, in its frame):
// noise on the sphere itself, drifting east, squashed north-south so it lies in bands.
float cloud_at(vec3 world) {
	float a = cloud_drift;
	vec3 c = vec3(world.x * cos(a) - world.z * sin(a), world.y * 1.6, world.x * sin(a) + world.z * cos(a)) + 23.0;
	float n = noise(c * 3.2) * 0.58 + noise(c * 7.0 + 11.0) * 0.27 + noise(c * 15.0 + 5.0) * 0.1 + noise(c * 34.0 + 2.0) * 0.05;
	float cloud = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.16, n);
	return max(cloud, smoothstep(0.85, 1.0, cloud_cover));
}

// Screen gradients of an equirectangular map's UV without the seam where atan wraps: the
// across-gradient is taken from whichever of the UV and a half-turned copy is smaller.
vec4 seam_grad(vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 dx2 = dFdx(fract(uv + vec2(0.5, 0.0)));
	vec2 dy2 = dFdy(fract(uv + vec2(0.5, 0.0)));
	dx.x = abs(dx.x) < abs(dx2.x) ? dx.x : dx2.x;
	dy.x = abs(dy.x) < abs(dy2.x) ? dy.x : dy2.x;
	return vec4(dx, dy);
}
