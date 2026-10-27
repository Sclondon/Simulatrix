extends Sim3D
## Ocean: a wind-driven sea of Gerstner waves (ocean_water.gdshader), from Mariner's ocean.
## The waves come from the wind the way real sea states do (a Pierson-Moskowitz spectrum: the
## stronger and longer the wind blows, the longer and higher the waves), plus a swell from
## elsewhere. A CPU copy of the wave sum (wave_at) floats a moored buoy and whatever you drop.

const Daylight := preload("res://sims/vfx/weather_daylight.gd")
const WATER := preload("res://sims/vfx/ocean_water.gdshader")
const G := 9.81
const SIZE := 240.0
const FAR := 4000.0
const MAX_FLOATERS := 20
const PALETTES := [
	# name, deep, scatter, toon
	["Open", Color(0.004, 0.035, 0.1), Color(0.03, 0.3, 0.42), false],
	["Tropic", Color(0.0, 0.12, 0.2), Color(0.06, 0.62, 0.6), false],
	["Atlantic", Color(0.015, 0.05, 0.06), Color(0.08, 0.24, 0.22), false],
	["Toon", Color(0.02, 0.24, 0.52), Color(0.1, 0.6, 0.76), true],
]
const QUALITY := [ # grid subdivisions, waves
	[110, 6], [170, 9], [240, 12],
]

var wind := 8.0          # m/s
var wind_from := 30.0    # degrees; the waves run the other way
var height_scale := 1.0
var chop := 0.55
var spread := 35.0       # degrees of spread round the wind
var swell := 0.6         # swell height, m
var foam := 0.5
var palette := 0
var quality := 1
var hour := 15.5
var cycle := false
var clouds := 0.3
var drop_kind := 0
var wind_lines := false

var _t := 0.0
var _near: MeshInstance3D
var _far: MeshInstance3D
var _mat: ShaderMaterial
var _far_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _streaks: CPUParticles3D
var _buoy: Node3D
var _lamp: OmniLight3D
var _lamp_glow: StandardMaterial3D
var _floaters: Array[Dictionary] = []
var _splashes: Array[CPUParticles3D] = []
var _splash_next := 0
var _ripples: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _ripple_next := 0
var _detail := Vector2.ZERO
var _cloud_shift := Vector2.ZERO
var _hs := 0.0
var _tp := 0.0
var _lp := 0.0
var _rng := RandomNumberGenerator.new()

# The wave set, also on the CPU: direction, amplitude, wavenumber, angular frequency, Q
var _dx := PackedFloat32Array()
var _dz := PackedFloat32Array()
var _a := PackedFloat32Array()
var _k := PackedFloat32Array()
var _w := PackedFloat32Array()
var _q := PackedFloat32Array()


func help() -> String:
	return ("A sea of Gerstner waves driven by the wind. Wind speed sets the sea state the way it does on a real "
		+ "ocean: stronger wind, longer and higher waves (Pierson-Moskowitz). Chop pushes the water toward each "
		+ "crest; where the surface folds over, the crest breaks into foam. Swell adds long waves from a distant "
		+ "storm.\n\nDrag to orbit, pinch or wheel to zoom. In Poke mode, tap the water to drop something in: "
		+ "it floats on the same waves you see.")


func hint() -> String:
	return "Drag to orbit. Switch Finger to Poke and tap to drop things in."


func pokeable() -> bool:
	return true


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Wind"},
		{type = "slider", label = "Speed", min = 0.0, max = 25.0, step = 0.5, value = wind, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: wind = v; _make_waves()},
		{type = "slider", label = "From", min = 0.0, max = 360.0, step = 5.0, value = wind_from, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: wind_from = v; _make_waves()},
		{type = "toggle", label = "Wind lines", value = wind_lines, on = func(v: bool) -> void: wind_lines = v; _streaks.emitting = v; _streaks.visible = v},
		{type = "section", label = "Waves"},
		{type = "slider", label = "Height", min = 0.0, max = 2.0, step = 0.05, value = height_scale, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: height_scale = v; _make_waves()},
		{type = "slider", label = "Chop", min = 0.0, max = 1.0, step = 0.05, value = chop, fmt = "%.2f",
			on = func(v: float) -> void: chop = v; _make_waves()},
		{type = "slider", label = "Spread", min = 0.0, max = 90.0, step = 5.0, value = spread, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: spread = v; _make_waves()},
		{type = "slider", label = "Swell", min = 0.0, max = 3.0, step = 0.1, value = swell, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: swell = v; _make_waves()},
		{type = "slider", label = "Foam", min = 0.0, max = 1.0, step = 0.05, value = foam, fmt = "%.2f",
			on = func(v: float) -> void: foam = v; _make_waves()},
		{type = "section", label = "Look"},
		{type = "choice", label = "Water", options = PALETTES.map(func(p: Array) -> String: return p[0]), value = palette,
			on = func(i: int) -> void: palette = i; _apply_palette()},
		{type = "slider", label = "Time", min = 0.0, max = 24.0, step = 0.25, value = hour, fmt = "%05.2f", unit = "h",
			on = func(v: float) -> void: hour = v; _apply_day()},
		{type = "toggle", label = "Cycle", value = cycle, on = func(v: bool) -> void: cycle = v},
		{type = "slider", label = "Clouds", min = 0.0, max = 1.0, step = 0.05, value = clouds, fmt = "%.2f",
			on = func(v: float) -> void: clouds = v; _apply_day()},
		{type = "section", label = "Scene"},
		{type = "choice", label = "Drop", options = ["Crate", "Barrel", "Float", "Splash"], value = drop_kind,
			on = func(i: int) -> void: drop_kind = i},
		{type = "button", label = "Drop 6", on = _drop_many},
		{type = "button", label = "Clear", on = _clear},
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = quality,
			on = func(i: int) -> void: quality = i; _build_patch(); _make_waves()},
	])
	return c


func status() -> String:
	return "Hs %.1f m · Tp %.1f s · λp %.0f m · %d waves · %d floating · %.1f ms" % [
		_hs, _tp, _lp, _a.size(), _floaters.size(), frame_ms()]


func build() -> void:
	_rng.seed = 7
	focus = Vector3(0, 0.6, 0)
	distance = 22.0
	yaw = 2.4
	pitch = -0.2
	max_pitch = -0.06
	min_distance = 6.0
	max_distance = 140.0
	camera.far = 5000.0
	_sky_mat = Daylight.make_sky_material()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50.0

	_mat = ShaderMaterial.new()
	_mat.shader = WATER
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
	_mat.set_shader_parameter("fade_start", SIZE * 0.33)
	_mat.set_shader_parameter("fade_end", SIZE * 0.49)
	_far_mat = _mat.duplicate()
	_far_mat.set_shader_parameter("wave_count", 0)
	_near = MeshInstance3D.new()
	_near.material_override = _mat
	_near.extra_cull_margin = 16.0
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_near)
	_far = MeshInstance3D.new()
	_far.mesh = _ring(SIZE * 0.5 - 0.5, FAR)
	_far.material_override = _far_mat
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_far)
	_build_patch()

	_build_buoy()
	_build_streaks()
	_streaks.emitting = wind_lines
	for i in 3:
		var s := _make_splash()
		world.add_child(s)
		_splashes.append(s)
	_make_waves()
	_apply_palette()
	_apply_day()
	# A few things already afloat
	for i in 4:
		var a := _rng.randf() * TAU
		_add_floater(i % 3, Vector3(cos(a), 0, sin(a)) * _rng.randf_range(6.0, 14.0), false)


func _build_patch() -> void:
	var sub: int = QUALITY[quality][0]
	var plane := PlaneMesh.new()
	plane.size = Vector2(SIZE, SIZE)
	plane.subdivide_width = sub
	plane.subdivide_depth = sub
	_near.mesh = plane


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


# --- the waves ---------------------------------------------------------------

## Builds the wave set from the wind (a Pierson-Moskowitz sea) and the swell.
func _make_waves() -> void:
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
	if _streaks:
		var d := Vector3(sin(toward), 0, cos(toward))
		_streaks.direction = d
		_streaks.initial_velocity_min = wind * 1.2
		_streaks.initial_velocity_max = wind * 1.6
		_streaks.amount = clampi(int(wind * 3.0), 4, 70)
		_streaks.emitting = wind_lines # setting the amount restarts it
		_streaks.visible = wind_lines


## The sea at (x, z): Vector4(height, and the surface's horizontal velocity x, z, plus 0).
## The Gerstner push moves points sideways, so first find which undisplaced point lands here.
func wave_at(x: float, z: float) -> Vector4:
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
	return Vector4(h, vx, vz, 0.0)


func normal_at(x: float, z: float) -> Vector3:
	var e := 0.6
	var hx := wave_at(x + e, z).x - wave_at(x - e, z).x
	var hz := wave_at(x, z + e).x - wave_at(x, z - e).x
	return Vector3(-hx, 2.0 * e, -hz).normalized()


# --- looks -------------------------------------------------------------------

## Re-applies every setting (for scripts that set the vars directly).
func refresh() -> void:
	_build_patch()
	_make_waves()
	_apply_palette()
	_apply_day()
	_streaks.emitting = wind_lines


func _apply_palette() -> void:
	var p: Array = PALETTES[palette]
	_mat.set_shader_parameter("deep_color", p[1])
	_mat.set_shader_parameter("scatter_color", p[2])
	_mat.set_shader_parameter("toon", 1.0 if p[3] else 0.0)
	_far_mat.set_shader_parameter("deep_color", p[1])
	_far_mat.set_shader_parameter("scatter_color", p[2])
	_far_mat.set_shader_parameter("toon", 1.0 if p[3] else 0.0)


func _apply_day() -> void:
	var day := Daylight.at(hour)
	var dim := clampf((clouds - 0.65) / 0.35, 0.0, 1.0)
	Daylight.apply(day, _sky_mat, environment, sun, dim)
	_sky_mat.set_shader_parameter("cloud_cover", clouds)
	_sky_mat.set_shader_parameter("ground", Color(0.02, 0.06, 0.12))
	var hor: Color = _sky_mat.get_shader_parameter("horizon")
	var zen: Color = _sky_mat.get_shader_parameter("zenith")
	for m in [_mat, _far_mat]:
		m.set_shader_parameter("horizon", hor)
		m.set_shader_parameter("zenith", zen)
		m.set_shader_parameter("light_dir", day.light_dir)
		m.set_shader_parameter("light_color", day.light_color)
		m.set_shader_parameter("light_energy", sun.light_energy)
		m.set_shader_parameter("ambient", environment.ambient_light_color * 0.55)
		m.set_shader_parameter("overcast", dim)
	_lamp.visible = day.night > 0.3


# --- things in the water -----------------------------------------------------

func _build_buoy() -> void:
	_buoy = Node3D.new()
	world.add_child(_buoy)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.78, 0.12, 0.08)
	red.roughness = 0.6
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.9, 0.9, 0.86)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.25
	cyl.height = 1.2
	cyl.material = red
	body.mesh = cyl
	_buoy.add_child(body)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.12
	bm.bottom_radius = 1.12
	bm.height = 0.25
	bm.material = white
	band.mesh = bm
	band.position.y = 0.2
	_buoy.add_child(band)
	# The lattice tower and the lamp
	for i in 3:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.05
		lm.bottom_radius = 0.07
		lm.height = 2.6
		lm.material = dark
		leg.mesh = lm
		var a := i * TAU / 3.0
		leg.position = Vector3(cos(a) * 0.4, 1.8, sin(a) * 0.4)
		leg.rotation = Vector3(sin(a) * 0.12, 0, -cos(a) * 0.12)
		_buoy.add_child(leg)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.42
	tm.bottom_radius = 0.42
	tm.height = 0.5
	tm.material = red
	top.mesh = tm
	top.position.y = 3.0
	_buoy.add_child(top)
	_lamp_glow = StandardMaterial3D.new()
	_lamp_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_glow.albedo_color = Color(1.0, 0.85, 0.5)
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.material = _lamp_glow
	bulb.mesh = sm
	bulb.position.y = 3.45
	_buoy.add_child(bulb)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.8, 0.45)
	_lamp.omni_range = 18.0
	_lamp.position.y = 3.5
	_buoy.add_child(_lamp)
	_floaters.append({node = _buoy, vel = Vector3.ZERO, half = 0.6, sink = 0.55, anchor = Vector3.ZERO, spin = 0.0,
		above = false})


func _floater_mesh(kind: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	match kind:
		0:
			var b := BoxMesh.new()
			b.size = Vector3.ONE * 1.1
			mat.albedo_color = Color(0.55, 0.38, 0.2).lerp(Color(0.7, 0.55, 0.32), _rng.randf())
			b.material = mat
			m.mesh = b
		1:
			var c := CylinderMesh.new()
			c.top_radius = 0.42
			c.bottom_radius = 0.42
			c.height = 1.25
			c.radial_segments = 14
			mat.albedo_color = [Color(0.15, 0.32, 0.55), Color(0.6, 0.12, 0.1), Color(0.75, 0.6, 0.12)][_rng.randi() % 3]
			mat.metallic = 0.3
			c.material = mat
			m.mesh = c
			m.rotation.z = PI * 0.5
		_:
			var s := SphereMesh.new()
			s.radius = 0.45
			s.height = 0.9
			s.radial_segments = 16
			s.rings = 8
			mat.albedo_color = Color(1.0, 0.42, 0.08)
			s.material = mat
			m.mesh = s
	return m


func _add_floater(kind: int, pos: Vector3, falling := true) -> void:
	if kind == 3:
		_splash(pos)
		return
	var n := Node3D.new()
	n.add_child(_floater_mesh(kind))
	world.add_child(n)
	var half: float = [0.55, 0.42, 0.45][kind]
	if falling:
		pos.y = 7.0 + _rng.randf() * 3.0
	else:
		pos.y = wave_at(pos.x, pos.z).x
	n.position = pos
	n.rotation.y = _rng.randf() * TAU
	_floaters.append({node = n, vel = Vector3.ZERO, half = half, sink = [0.45, 0.5, 0.35][kind], anchor = null,
		spin = _rng.randf_range(-0.3, 0.3), above = pos.y > 1.0})
	# The oldest loose thing goes when there are too many (the buoy is first and stays)
	if _floaters.size() > MAX_FLOATERS + 1:
		var old: Dictionary = _floaters[1]
		old.node.queue_free()
		_floaters.remove_at(1)


func _drop_many() -> void:
	for i in 6:
		var a := _rng.randf() * TAU
		var kind := drop_kind if drop_kind < 3 else i % 3
		_add_floater(kind, focus + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 12.0))


func _clear() -> void:
	while _floaters.size() > 1:
		_floaters.pop_back().node.queue_free()


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


func _splash(pos: Vector3, strength := 1.0) -> void:
	var s := _splashes[_splash_next]
	_splash_next = (_splash_next + 1) % _splashes.size()
	s.global_position = Vector3(pos.x, wave_at(pos.x, pos.z).x, pos.z)
	s.initial_velocity_max = 4.0 + 4.0 * strength
	s.restart()
	_ripples[_ripple_next] = Vector4(pos.x, pos.z, 0.0, clampf(strength, 0.3, 1.5))
	_ripple_next = (_ripple_next + 1) % 4


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
	world.add_child(_streaks)


# --- running -----------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	_t += delta
	if cycle:
		hour = fposmod(hour + delta * 0.25, 24.0)
		_apply_day()
	var toward := deg_to_rad(wind_from + 180.0)
	var wdir := Vector2(sin(toward), cos(toward))
	_detail += wdir * (0.01 + wind * 0.0016) * delta
	_cloud_shift += wdir * (0.002 + wind * 0.0004) * delta
	_sky_mat.set_shader_parameter("cloud_offset", _cloud_shift)
	# The near patch follows the focus, snapped to its grid so the vertices don't swim
	var step := SIZE / float(QUALITY[quality][0] + 1)
	_near.position = Vector3(snappedf(focus.x, step), 0, snappedf(focus.z, step))
	_far.position = _near.position
	for i in 4:
		if _ripples[i].w > 0.0:
			_ripples[i].z += delta
			if _ripples[i].z > 6.0:
				_ripples[i].w = 0.0
	for m in [_mat, _far_mat]:
		m.set_shader_parameter("wave_time", _t)
		m.set_shader_parameter("detail_offset", _detail)
	_mat.set_shader_parameter("ripples", PackedVector4Array(_ripples))
	_streaks.position = focus + Vector3(-wdir.x * 12.0, 3.5 + _hs * 0.6, -wdir.y * 12.0)
	if _lamp.visible:
		var on := fmod(_t, 2.5) < 0.6
		_lamp.light_energy = 2.5 if on else 0.0
		_lamp_glow.albedo_color = Color(1.0, 0.85, 0.5) if on else Color(0.3, 0.22, 0.12)
	# Fixed substeps, so a slow frame does not slow the floating down or blow it up
	var steps := clampi(ceili(delta * 60.0), 1, 4)
	for i in steps:
		_float(minf(delta, 4.0 / 60.0) / steps, wdir)


## Buoyancy for everything afloat: a spring toward its waterline, drag, the water's own motion,
## a little windage, and tilt toward the surface's slope.
func _float(dt: float, wdir: Vector2) -> void:
	for f in _floaters:
		var n: Node3D = f.node
		var p := n.position
		var v: Vector3 = f.vel
		var w := wave_at(p.x, p.z)
		var surface := w.x
		var half: float = f.half
		# How much of it is under: 0 above, 1 all under
		var sub := clampf((surface - (p.y - half)) / (2.0 * half), 0.0, 1.0)
		var was_above: bool = f.above
		f.above = sub <= 0.0
		if was_above and sub > 0.0 and v.y < -3.0:
			_splash(p, clampf(-v.y / 10.0, 0.3, 1.2))
		var acc := Vector3(0, -G, 0)
		acc.y += G * sub / f.sink
		if sub > 0.0:
			# Water drag toward the water's own velocity, and a little push from the wind
			var water_v := Vector3(w.y, 0, w.z) + Vector3(wdir.x, 0, wdir.y) * wind * 0.025
			acc += (water_v - Vector3(v.x, 0, v.z)) * 1.8 * sub
			acc.y -= v.y * 3.2 * sub
		if f.anchor != null:
			var to: Vector3 = f.anchor - p
			acc += Vector3(to.x, 0, to.z) * 0.6
		v += acc * dt
		p += v * dt
		n.position = p
		f.vel = v
		if sub > 0.0:
			var up := normal_at(p.x, p.z)
			var yaw_now: float = n.rotation.y + f.spin * dt
			var b := Basis(Vector3.UP, yaw_now)
			var tilt := Quaternion(Vector3.UP, up)
			var target := Basis(tilt) * b
			n.basis = n.basis.orthonormalized().slerp(target.orthonormalized(), clampf(dt * 3.0, 0.0, 1.0))


func poke_down(pos: Vector2) -> void:
	var hit: Variant = ground(pos, 0.0)
	if hit != null:
		_add_floater(drop_kind, hit)
