class_name OceanSurface
extends Node3D
## An open sea of Gerstner waves built by the wind, out to the horizon. The waves come from the
## wind the way real sea states do (a Pierson-Moskowitz spectrum: the stronger the wind, the
## longer and higher the waves), plus a swell from elsewhere; `chop` pushes the water toward each
## crest, and where the surface folds over the crest breaks into foam. Gusts show as darker,
## rougher patches drifting downwind. Things that hit the water splash and send out rings.
##
## A near patch of grid follows the camera (snapped to its grid so the water doesn't swim) and a
## flat ring carries the sea to the horizon. The same wave sum runs on the CPU (wave_at,
## height_at, normal_at) so OceanFloater can float things on the waves you see.
##
## Add one to a scene (it sits at y = 0), set its exports or call use_palette(); give it `sun`
## and the sky's colours (`horizon_color`, `zenith_color`) so its shading matches the scene's.
## From Mariner's ocean, made Gerstner in The Simulatrix (2026-10-27).

const SHADER := preload("res://ocean/ocean.gdshader")
const G := 9.81
const FAR := 4000.0
## Palettes: name, deep colour, scatter (light through the crests), toon.
const PALETTES := [
	["Open", Color(0.004, 0.035, 0.1), Color(0.03, 0.3, 0.42), false],
	["Tropic", Color(0.0, 0.12, 0.2), Color(0.06, 0.62, 0.6), false],
	["Atlantic", Color(0.015, 0.05, 0.06), Color(0.08, 0.24, 0.22), false],
	["Toon", Color(0.02, 0.24, 0.52), Color(0.1, 0.6, 0.76), true],
]
## Grid subdivisions of the near patch, and how many waves, for each quality.
const QUALITY := [[110, 6], [170, 9], [240, 12]]

@export_group("Wind and waves")
## Wind speed, m/s: it sets the sea state.
@export_range(0.0, 30.0, 0.5) var wind := 8.0:
	set(v): wind = v; _dirty = true
## The compass bearing the wind comes from, degrees (the waves run the other way).
@export_range(0.0, 360.0, 1.0) var wind_from := 30.0:
	set(v): wind_from = v; _dirty = true
## Wave height against what this wind would raise.
@export_range(0.0, 3.0, 0.05) var height_scale := 1.0:
	set(v): height_scale = v; _dirty = true
## How far the water pushes toward each crest (0 round swells, 1 breaking).
@export_range(0.0, 1.0, 0.05) var chop := 0.55:
	set(v): chop = v; _dirty = true
## Degrees of spread of the waves round the wind.
@export_range(0.0, 90.0, 1.0) var spread := 35.0:
	set(v): spread = v; _dirty = true
## Height of a long swell from a distant storm, m (0 none).
@export_range(0.0, 4.0, 0.1) var swell := 0.6:
	set(v): swell = v; _dirty = true
## Whitecaps.
@export_range(0.0, 1.0, 0.05) var foam := 0.5:
	set(v): foam = v; _dirty = true
## How strongly gusts show as dark, rough patches drifting downwind.
@export_range(0.0, 1.0, 0.05) var gusts := 0.5:
	set(v): gusts = v; _dirty = true

@export_group("Look")
@export var deep_color := Color(0.004, 0.035, 0.1):
	set(v): deep_color = v; _dirty = true
@export var scatter_color := Color(0.03, 0.3, 0.42):
	set(v): scatter_color = v; _dirty = true
@export var foam_color := Color(0.92, 0.95, 0.97):
	set(v): foam_color = v; _dirty = true
## Wind Waker banding instead of the realistic shading.
@export var toon := false:
	set(v): toon = v; _dirty = true
## The sky, for the water to reflect (set them from your sky as the day goes).
@export var horizon_color := Color(0.66, 0.8, 0.94)
@export var zenith_color := Color(0.13, 0.36, 0.78)
## 0 clear, 1 a grey overcast: the sun's glitter and the light through the crests fade.
@export_range(0.0, 1.0, 0.05) var overcast := 0.0
## The light the water is lit by; with none, a high afternoon sun.
@export var sun: DirectionalLight3D
## White streaks blowing over the water downwind.
@export var wind_lines := false:
	set(v): wind_lines = v; _dirty = true

@export_group("Size")
## 0 low (phones), 1 medium, 2 high.
@export_range(0, 2) var quality := 1:
	set(v): quality = v; _rebuild = true
## The near patch's size, m (its waves fade out toward its edge).
@export var size := 240.0:
	set(v): size = v; _rebuild = true
## What the near patch follows; empty: the current camera.
@export var follow: Node3D

var _t := 0.0
var _dirty := true
var _rebuild := true
var _near: MeshInstance3D
var _far: MeshInstance3D
var _mat: ShaderMaterial
var _far_mat: ShaderMaterial
var _streaks: CPUParticles3D
var _splashes: Array[CPUParticles3D] = []
var _splash_next := 0
var _ripples: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _ripple_next := 0
var _detail := Vector2.ZERO
var _gust_offset := Vector2.ZERO
var _hs := 0.0
var _tp := 0.0
var _lp := 0.0

# The wave set, also on the CPU: direction, amplitude, wavenumber, angular frequency, Q
var _dx := PackedFloat32Array()
var _dz := PackedFloat32Array()
var _a := PackedFloat32Array()
var _k := PackedFloat32Array()
var _w := PackedFloat32Array()
var _q := PackedFloat32Array()


## Sets the colours (and toon) from PALETTES: 0 Open, 1 Tropic, 2 Atlantic, 3 Toon.
func use_palette(i: int) -> void:
	var p: Array = PALETTES[clampi(i, 0, PALETTES.size() - 1)]
	deep_color = p[1]
	scatter_color = p[2]
	toon = p[3]


## Significant wave height (m), peak period (s) and peak wavelength (m) of the wind sea.
func significant_height() -> float:
	return _hs


func peak_period() -> float:
	return _tp


func peak_length() -> float:
	return _lp


func wave_count() -> int:
	return _a.size()


func _ready() -> void:
	add_to_group("oceans")
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 5.0
	var nn := FastNoiseLite.new()
	nn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nn.frequency = 0.03
	nn.fractal_octaves = 3
	nt.noise = nn
	_mat.set_shader_parameter("detail_normal", nt)
	var ft := NoiseTexture2D.new()
	ft.width = 256
	ft.height = 256
	ft.seamless = true
	var fnz := FastNoiseLite.new()
	fnz.noise_type = FastNoiseLite.TYPE_SIMPLEX
	fnz.frequency = 0.035
	fnz.fractal_octaves = 4
	ft.noise = fnz
	_mat.set_shader_parameter("foam_noise", ft)
	_far_mat = _mat.duplicate()
	_far_mat.set_shader_parameter("wave_count", 0)
	_near = MeshInstance3D.new()
	_near.material_override = _mat
	_near.extra_cull_margin = 16.0
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_near)
	_far = MeshInstance3D.new()
	_far.material_override = _far_mat
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_far)
	_build_streaks()
	for i in 3:
		var s := _make_splash()
		add_child(s)
		_splashes.append(s)
	_build_patch()
	_make_waves()


func _build_patch() -> void:
	_rebuild = false
	if _near == null:
		return
	var sub: int = QUALITY[quality][0]
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = sub
	plane.subdivide_depth = sub
	_near.mesh = plane
	_far.mesh = _ring(size * 0.5 - 0.5, FAR)
	for m in [_mat, _far_mat]:
		m.set_shader_parameter("fade_start", size * 0.33)
		m.set_shader_parameter("fade_end", size * 0.49)
	_dirty = true


func _ring(inner: float, outer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var i := [Vector3(-inner, 0, -inner), Vector3(inner, 0, -inner), Vector3(inner, 0, inner), Vector3(-inner, 0, inner)]
	var o := [Vector3(-outer, 0, -outer), Vector3(outer, 0, -outer), Vector3(outer, 0, outer), Vector3(-outer, 0, outer)]
	for k in 4:
		var n := (k + 1) % 4
		for v in [o[k], o[n], i[n], o[k], i[n], i[k]]:
			st.add_vertex(v)
	return st.commit()


## The way the wind blows to, on the ground (x, z).
func wind_dir() -> Vector2:
	var toward := deg_to_rad(wind_from + 180.0)
	return Vector2(sin(toward), cos(toward))


# --- the waves ---------------------------------------------------------------

## Builds the wave set from the wind (a Pierson-Moskowitz sea) and the swell.
func _make_waves() -> void:
	_dirty = false
	if _mat == null:
		return
	var count: int = QUALITY[quality][1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	_dx.clear(); _dz.clear(); _a.clear(); _k.clear(); _w.clear(); _q.clear()
	var toward := deg_to_rad(wind_from + 180.0)
	var u := maxf(wind, 0.3)
	var wp := 0.877 * G / u               # peak angular frequency
	_lp = minf(TAU * G / (wp * wp), 70.0)
	_tp = TAU / sqrt(G * TAU / _lp)
	_hs = 0.21 * u * u / G * height_scale
	var n_wind := count - (1 if swell > 0.0 else 0)
	var longest := _lp * 1.25
	var ratio := pow(0.07, 1.0 / maxf(n_wind - 1, 1))
	var amps := PackedFloat32Array()
	var total := 0.0
	for i in n_wind:
		var lam := longest * pow(ratio, i)
		var k := TAU / lam
		var om := sqrt(G * k)
		# Spectral density at this frequency, times the band of frequencies it stands for
		var s := 0.0081 * G * G / pow(om, 5.0) * exp(-1.25 * pow(wp / om, 4.0))
		var band := om * (1.0 / sqrt(ratio) - sqrt(ratio))
		var a := sqrt(2.0 * s * band)
		amps.append(a)
		total += a * a
		var ang := toward + deg_to_rad(spread) * rng.randf_range(-1.0, 1.0) * (0.4 + 0.6 * float(i) / maxf(n_wind - 1, 1))
		_dx.append(sin(ang)); _dz.append(cos(ang)); _k.append(k); _w.append(om)
	# Scale so the significant height (4 x the RMS elevation) is Hs
	var rms := sqrt(total * 0.5)
	var fit := (_hs / 4.0) / maxf(rms, 0.0001)
	if wind < 0.31:
		fit = 0.0
		_hs = 0.0
	for a in amps:
		_a.append(a * fit)
	if swell > 0.0:
		var ang := toward + deg_to_rad(55.0)
		var lam := 96.0
		_dx.append(sin(ang)); _dz.append(cos(ang)); _a.append(swell * 0.5); _k.append(TAU / lam); _w.append(sqrt(G * TAU / lam))
	# Gerstner steepness: one Q for all, so the push adds up to `chop` of the total slope and the
	# surface just folds at chop 1 where the crests line up (the swell stays round)
	var n := _a.size()
	var max_h := 0.0
	var slope := 0.0
	for i in n_wind:
		slope += _k[i] * _a[i]
	for i in n:
		_q.append(chop / maxf(slope, 0.0001) if i < n_wind else 0.25 * chop)
		max_h += _a[i]
	var packed := PackedVector4Array()
	var qs := PackedFloat32Array()
	for i in 12:
		if i < n:
			packed.append(Vector4(_dx[i], _dz[i], _a[i], TAU / _k[i]))
			qs.append(_q[i])
		else:
			packed.append(Vector4(1, 0, 0, 10))
			qs.append(0.0)
	_mat.set_shader_parameter("waves", packed)
	_mat.set_shader_parameter("steepness", qs)
	_mat.set_shader_parameter("wave_count", n)
	_mat.set_shader_parameter("max_height", maxf(max_h * 0.6, 0.1))
	_mat.set_shader_parameter("detail_strength", clampf(0.15 + wind / 40.0, 0.15, 0.6))
	_mat.set_shader_parameter("chop", chop)
	# Whitecaps start at about 4 m/s of wind and are everywhere by 15
	_mat.set_shader_parameter("foam_amount", foam * clampf((wind - 3.0) / 10.0, 0.0, 1.2) * minf(height_scale, 1.0) + foam * 0.15)
	for m in [_mat, _far_mat]:
		m.set_shader_parameter("deep_color", deep_color)
		m.set_shader_parameter("scatter_color", scatter_color)
		m.set_shader_parameter("foam_color", foam_color)
		m.set_shader_parameter("toon", 1.0 if toon else 0.0)
		m.set_shader_parameter("gusts", gusts * clampf(wind / 6.0, 0.0, 1.0))
	if _streaks:
		var d := Vector3(sin(toward), 0, cos(toward))
		_streaks.direction = d
		_streaks.initial_velocity_min = wind * 1.2
		_streaks.initial_velocity_max = wind * 1.6
		_streaks.amount = clampi(int(wind * 3.0), 4, 70)
		_streaks.emitting = wind_lines # setting the amount restarts it
		_streaks.visible = wind_lines


## The sea at (x, z): Vector4(height, the surface's horizontal velocity x and z, 0).
## The Gerstner push moves points sideways, so first find which undisplaced point lands here.
func wave_at(x: float, z: float) -> Vector4:
	x -= global_position.x
	z -= global_position.z
	var px := x
	var pz := z
	for it in 3:
		var ox := 0.0
		var oz := 0.0
		for i in _a.size():
			var c := cos(_k[i] * (_dx[i] * px + _dz[i] * pz) - _w[i] * _t)
			ox += _q[i] * _a[i] * _dx[i] * c
			oz += _q[i] * _a[i] * _dz[i] * c
		px = x - ox
		pz = z - oz
	var h := 0.0
	var vx := 0.0
	var vz := 0.0
	for i in _a.size():
		var ph := _k[i] * (_dx[i] * px + _dz[i] * pz) - _w[i] * _t
		h += _a[i] * sin(ph)
		var sv := _q[i] * _a[i] * _w[i] * sin(ph)
		vx += sv * _dx[i]
		vz += sv * _dz[i]
	return Vector4(h + global_position.y, vx, vz, 0.0)


## The water's height at (x, z), in world space.
func height_at(x: float, z: float) -> float:
	return wave_at(x, z).x


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.6
	var hx := wave_at(x + e, z).x - wave_at(x - e, z).x
	var hz := wave_at(x, z + e).x - wave_at(x, z - e).x
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## 0..1: how much of a gust patch (x, z) is in. Matches the shader's gust_factor.
func gust_at(x: float, z: float) -> float:
	var q := Vector2(x, z) - _gust_offset
	var g := sin(q.x * 0.021 + q.y * 0.013) * sin(-q.x * 0.011 + q.y * 0.027 + 1.7)
	g += 0.5 * sin(q.x * 0.043 - q.y * 0.031 + 4.0) * sin(q.x * 0.017 + q.y * 0.009)
	return clampf(g * 0.6 + 0.45, 0.0, 1.0)


## Spray and a ring of ripples where something hits the water (strength about 0.3..1.5).
func splash(pos: Vector3, strength := 1.0) -> void:
	if _splashes.is_empty():
		return
	var s := _splashes[_splash_next]
	_splash_next = (_splash_next + 1) % _splashes.size()
	s.global_position = Vector3(pos.x, height_at(pos.x, pos.z), pos.z)
	s.initial_velocity_max = 4.0 + 4.0 * strength
	s.restart()
	_ripples[_ripple_next] = Vector4(pos.x, pos.z, 0.0, clampf(strength, 0.3, 1.5))
	_ripple_next = (_ripple_next + 1) % 4


## Re-applies every setting now (they are otherwise applied on the next frame).
func refresh() -> void:
	if _rebuild:
		_build_patch()
	_make_waves()


func _make_splash() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 36
	p.lifetime = 1.4
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0, -G, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.local_coords = false
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.92, 0.96, 1.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := SphereMesh.new()
	q.radius = 0.06
	q.height = 0.12
	q.radial_segments = 6
	q.rings = 3
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _build_streaks() -> void:
	_streaks = CPUParticles3D.new()
	_streaks.amount = 30
	_streaks.lifetime = 2.2
	_streaks.preprocess = 2.0
	_streaks.local_coords = false
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(30.0, 3.0, 30.0)
	_streaks.spread = 2.0
	_streaks.gravity = Vector3.ZERO
	_streaks.particle_flag_align_y = true
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 1.6, 0.02)
	box.material = m
	_streaks.mesh = box
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.3))
	g.add_point(0.7, Color(1, 1, 1, 0.2))
	_streaks.color_ramp = g
	add_child(_streaks)


func _process(delta: float) -> void:
	if _rebuild:
		_build_patch()
	if _dirty:
		_make_waves()
	_t += delta
	var wdir := wind_dir()
	_detail += wdir * (0.01 + wind * 0.0016) * delta
	_gust_offset += wdir * wind * 0.9 * delta
	var eye: Node3D = follow if follow else get_viewport().get_camera_3d()
	var at := eye.global_position if eye else global_position
	# The near patch follows, snapped to its grid so the vertices don't swim
	var step := size / float(QUALITY[quality][0] + 1)
	_near.global_position = Vector3(snappedf(at.x, step), global_position.y, snappedf(at.z, step))
	_far.global_position = _near.global_position
	for i in 4:
		if _ripples[i].w > 0.0:
			_ripples[i].z += delta
			if _ripples[i].z > 6.0:
				_ripples[i].w = 0.0
	var light_dir := Vector3(0.3, 0.75, -0.6).normalized()
	var light_color := Color(1, 0.97, 0.9)
	var energy := 1.3
	if sun:
		light_dir = sun.global_basis.z
		light_color = sun.light_color
		energy = sun.light_energy
	var ambient := Color(0.55, 0.6, 0.7)
	var env := get_world_3d().environment if is_inside_tree() else null
	if env:
		ambient = env.ambient_light_color
	for m in [_mat, _far_mat]:
		m.set_shader_parameter("wave_time", _t)
		m.set_shader_parameter("detail_offset", _detail)
		m.set_shader_parameter("gust_offset", _gust_offset)
		m.set_shader_parameter("horizon", horizon_color)
		m.set_shader_parameter("zenith", zenith_color)
		m.set_shader_parameter("light_dir", light_dir)
		m.set_shader_parameter("light_color", light_color)
		m.set_shader_parameter("light_energy", energy)
		m.set_shader_parameter("ambient", ambient * 0.55)
		m.set_shader_parameter("overcast", overcast)
	_mat.set_shader_parameter("ripples", PackedVector4Array(_ripples))
	if _streaks.visible:
		_streaks.global_position = at + Vector3(-wdir.x * 12.0, 3.5 + _hs * 0.6, -wdir.y * 12.0)
