extends RefCounted
## Time of day, shared by the Ocean and Sky & Weather sims: for an hour 0..24 it gives the
## sun and moon directions, the colour and strength of the light that is up, and the sky's
## colours. Also builds the sky material (weather_sky.gdshader) both sims draw.

const SKY_SHADER := preload("res://sims/vfx/weather_sky.gdshader")

# hour, zenith, horizon, light colour, light energy, ambient
const KEYS := [
	[0.0, Color(0.012, 0.02, 0.055), Color(0.05, 0.07, 0.14), Color(0.55, 0.66, 1.0), 0.16, Color(0.2, 0.24, 0.42)],
	[4.6, Color(0.015, 0.025, 0.07), Color(0.07, 0.08, 0.17), Color(0.55, 0.66, 1.0), 0.14, Color(0.2, 0.24, 0.42)],
	[5.6, Color(0.08, 0.1, 0.25), Color(0.55, 0.36, 0.38), Color(0.9, 0.5, 0.4), 0.15, Color(0.25, 0.24, 0.36)],
	[6.4, Color(0.16, 0.25, 0.5), Color(1.0, 0.6, 0.36), Color(1.0, 0.56, 0.3), 0.7, Color(0.42, 0.4, 0.48)],
	[8.0, Color(0.2, 0.4, 0.75), Color(0.85, 0.82, 0.78), Color(1.0, 0.86, 0.68), 1.15, Color(0.52, 0.56, 0.66)],
	[12.0, Color(0.13, 0.36, 0.78), Color(0.66, 0.8, 0.94), Color(1.0, 0.97, 0.9), 1.35, Color(0.58, 0.64, 0.76)],
	[16.0, Color(0.17, 0.38, 0.75), Color(0.8, 0.8, 0.8), Color(1.0, 0.88, 0.7), 1.15, Color(0.54, 0.56, 0.66)],
	[17.6, Color(0.17, 0.25, 0.52), Color(1.0, 0.55, 0.3), Color(1.0, 0.5, 0.25), 0.7, Color(0.45, 0.38, 0.45)],
	[18.4, Color(0.09, 0.09, 0.25), Color(0.6, 0.3, 0.32), Color(0.9, 0.45, 0.4), 0.15, Color(0.25, 0.22, 0.34)],
	[19.4, Color(0.015, 0.025, 0.07), Color(0.07, 0.08, 0.17), Color(0.55, 0.66, 1.0), 0.14, Color(0.2, 0.24, 0.42)],
	[24.0, Color(0.012, 0.02, 0.055), Color(0.05, 0.07, 0.14), Color(0.55, 0.66, 1.0), 0.16, Color(0.2, 0.24, 0.42)],
]


## Everything about the light at `hour`: sun_dir and moon_dir (toward them), light_dir (toward
## whichever lights the scene), zenith, horizon, light_color, light_energy, ambient, night (0..1).
static func at(hour: float) -> Dictionary:
	hour = fposmod(hour, 24.0)
	var i := 0
	while i < KEYS.size() - 2 and hour >= KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var t := smoothstep(0.0, 1.0, (hour - a[0]) / (b[0] - a[0]))
	var elev := sin((hour - 6.0) / 12.0 * PI) * deg_to_rad(62.0)
	var az := (hour - 12.0) / 12.0 * PI
	var sun_dir := Vector3(sin(az) * cos(elev), sin(elev), -cos(az) * cos(elev) * 0.6 - 0.4 * cos(elev)).normalized()
	var moon_dir := Vector3(-sun_dir.x, absf(sun_dir.y) * 0.85 + 0.15, -sun_dir.z * 0.5 - 0.5).normalized()
	var night := clampf(-sun_dir.y * 6.0 + 0.2, 0.0, 1.0)
	# The light that's up: the sun until it nearly sets, then the moon
	var light_dir := sun_dir
	if sun_dir.y < 0.04:
		light_dir = moon_dir
	return {
		sun_dir = sun_dir, moon_dir = moon_dir, light_dir = light_dir, night = night,
		zenith = (a[1] as Color).lerp(b[1], t), horizon = (a[2] as Color).lerp(b[2], t),
		light_color = (a[3] as Color).lerp(b[3], t), light_energy = lerpf(a[4], b[4], t),
		ambient = (a[5] as Color).lerp(b[5], t),
	}


## Points a DirectionalLight3D so it shines from `toward` (a unit vector toward the light).
static func aim(light: DirectionalLight3D, toward: Vector3) -> void:
	var up := Vector3.UP if absf(toward.y) < 0.98 else Vector3.FORWARD
	light.global_transform = Transform3D(Basis.looking_at(-toward, up), Vector3.ZERO)


## A sky material with clouds; drive it with apply().
static func make_sky_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("cloud_noise", cloud_noise())
	return mat


static var _noise: NoiseTexture2D


## One seamless fBm noise texture for clouds, shared.
static func cloud_noise() -> NoiseTexture2D:
	if _noise:
		return _noise
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = 0.008
	n.fractal_octaves = 5
	n.fractal_gain = 0.5
	_noise = NoiseTexture2D.new()
	_noise.width = 512
	_noise.height = 512
	_noise.seamless = true
	_noise.normalize = true
	_noise.noise = n
	return _noise


## Feeds a day dictionary into the sky material and the environment, and aims the light.
static func apply(day: Dictionary, sky_mat: ShaderMaterial, env: Environment, light: DirectionalLight3D, dim := 0.0) -> void:
	var gray := Color(0.42, 0.44, 0.48).lerp(Color(0.06, 0.065, 0.08), day.night)
	var zen: Color = (day.zenith as Color).lerp(gray.darkened(0.15), dim * 0.85)
	var hor: Color = (day.horizon as Color).lerp(gray.lightened(0.15), dim * 0.8)
	sky_mat.set_shader_parameter("zenith", zen)
	sky_mat.set_shader_parameter("horizon", hor)
	sky_mat.set_shader_parameter("sun_dir", day.sun_dir)
	sky_mat.set_shader_parameter("moon_dir", day.moon_dir)
	sky_mat.set_shader_parameter("sun_color", day.light_color)
	sky_mat.set_shader_parameter("night", day.night)
	sky_mat.set_shader_parameter("overcast", dim)
	aim(light, day.light_dir)
	light.light_color = day.light_color
	light.light_energy = day.light_energy * (1.0 - dim * 0.75)
	env.ambient_light_color = (day.ambient as Color).lerp(gray, dim * 0.6)
	env.ambient_light_energy = 0.9
	env.fog_light_color = hor
