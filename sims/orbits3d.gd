extends Sim3D
## Orbits 3D: Gravity Well's 3D sibling. Atlas's Earth (Blue Marble, City Lights, clouds,
## rim of air) turns under a real sun with the Moon going round it, and satellites are flung
## into orbit by hand. Units: one unit is the Earth's radius (6371 km) and one sim second is
## 15 minutes, so low orbit takes about 6 s. The Moon is brought in from 60 radii to 14.
## Satellites feel the Earth and (optionally) the Moon, integrated by leapfrog (kick, drift,
## kick, which keeps orbits from creeping) in steps sized to each one's orbit.

const KM := 6371.0 # one unit, in km
const SECONDS := 900.0 # real seconds in a sim second at ×1
const GM_EARTH := 1.2486 # 398 600 km³/s² in these units
const MOON_RATIO := 0.0123 # the Moon's mass over the Earth's
const MOON_RADIUS := 0.273
const TILT := 0.4091 # the Earth's axial tilt, 23.44°
const MOON_INCLINE := 0.089 # the Moon's orbit against the ecliptic, 5.1°
const DAY := 95.74 # a sidereal day (86 164 s) in sim seconds
const LAUNCH_ALT := 0.06 # where a finger on the globe launches from: about 380 km up
const MAX_SATS := 30
const MAX_STEPS := 400 # per satellite per frame
const COLORS := [Color("5fd7ff"), Color("ffd166"), Color("ff6fae"), Color("9be564"), Color("c49bff"), Color("ff9a52")]
const KIND_COLORS := [Color("ff8a4c"), Color("5fe0ff"), Color("d690ff")] # suborbital, orbit, escape

var mass := 1.0
var moon_on := true
var moon_dist := 14.0
var warp := 1.0
var launch_mult := 1.0
var show_prediction := true
var trail_len := 90.0
var show_orbits := false
var spin := true
var clouds_on := true
var lights_on := true
var grid_on := false

var sun_dir := Vector3(1.0, 0.1, 0.3).normalized()
var equator := Basis(Vector3.BACK, -TILT) # the Earth's frame: its axis leans toward the sun
var moon_plane := Basis(Vector3.RIGHT, MOON_INCLINE)
var moon_theta := 2.2
var earth_angle := 0.0
var cloud_drift := 0.0

var earth_tilt := Node3D.new()
var earth := MeshInstance3D.new()
var cloud_shell := MeshInstance3D.new()
var air_shell := MeshInstance3D.new()
var moon := MeshInstance3D.new()
var earth_mat := ShaderMaterial.new()
var cloud_mat := ShaderMaterial.new()
var air_mat := ShaderMaterial.new()
var moon_mat := ShaderMaterial.new()
var sky_mat := ShaderMaterial.new()
var sat_mm := MultiMeshInstance3D.new()
var lines := MeshInstance3D.new()
var grid := MeshInstance3D.new()
var line_mat := StandardMaterial3D.new()
var flash_shader: Shader = preload("res://sims/orbits3d/flash.gdshader")

## Each satellite: {p, v, trail: Array of points, gap: float, color, fade: 1 alive / counting down}
var sats: Array[Dictionary] = []
var flashes: Array[Dictionary] = []
var aim := {} # while a finger is pulling back a launch
var prediction := PackedVector3Array()
var prediction_kind := 1
var last_info := ""
var color_index := 0
var burned := 0
var escaped := 0


func help() -> String:
	return ("The Earth from Atlas (NASA's Blue Marble, city lights, clouds and air) turning under a real sun, with the Moon going round it.\n\n"
		+ "Set Finger to Poke, then press on the globe or out in space and pull back like a slingshot: the dotted line is where it will go "
		+ "(blue an orbit, orange falling back, violet escaping). Let go to launch. A tap without pulling puts a satellite in a circular orbit.\n\n"
		+ "Physics: Newton's inverse-square gravity from the Earth, and from the Moon if Moon gravity is on (with the pull on the Earth "
		+ "itself taken off, since the view rides with the Earth). Each satellite is stepped by leapfrog integration, in steps sized to its "
		+ "own orbit, so orbits don't creep. Units are real: Earth radius 6371 km, low orbit about 90 minutes, geostationary 6.6 radii out.\n\n"
		+ "Not to scale: the Moon is 14 radii out instead of 60 (Moon distance moves it), so its pull and slingshots show up often. "
		+ "Low orbits go round in about 6 s at ×1; Time warp speeds everything up.")


func hint() -> String:
	return "Pull back from the globe and let go to launch a satellite. Tap for a circular orbit."


func status() -> String:
	var head := "%d sats · warp ×%d" % [sats.size(), int(warp)]
	if burned + escaped > 0:
		head += " · %d burned, %d escaped" % [burned, escaped]
	if not aim.is_empty():
		var el := _elements(aim.start, _aim_velocity(), _gm())
		return "%s · aim: %s · %.1f km/s" % [head, _describe(el), _aim_velocity().length() * KM / SECONDS]
	if last_info != "":
		return head + " · last: " + last_info
	return head


func pokeable() -> bool:
	return true


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Launch"},
		{type = "button", label = "LEO", on = _preset_leo},
		{type = "button", label = "GEO ring", on = _preset_geo},
		{type = "button", label = "Molniya", on = _preset_molniya},
		{type = "button", label = "Lunar transfer", on = _preset_lunar},
		{type = "button", label = "Swarm", on = _preset_swarm},
		{type = "button", label = "Clear", on = _clear},
		{type = "slider", label = "Launch speed", min = 0.25, max = 3.0, step = 0.05, value = launch_mult, fmt = "×%.2f",
			on = func(v: float) -> void: launch_mult = v},
		{type = "toggle", label = "Prediction", value = show_prediction, on = func(on: bool) -> void: show_prediction = on},
		{type = "section", label = "Gravity"},
		{type = "slider", label = "Earth mass", min = 0.25, max = 3.0, step = 0.05, value = mass, fmt = "×%.2f",
			on = func(v: float) -> void: mass = v},
		{type = "toggle", label = "Moon gravity", value = moon_on, on = func(on: bool) -> void: moon_on = on},
		{type = "slider", label = "Moon distance", min = 6.0, max = 30.0, step = 0.5, value = moon_dist, fmt = "%.1f", unit = "R",
			on = func(v: float) -> void:
				moon_dist = v
				_build_grid()},
		{type = "slider", label = "Time warp", min = 1.0, max = 100.0, step = 1.0, value = warp, fmt = "×%.0f",
			on = func(v: float) -> void: warp = v},
		{type = "section", label = "Display"},
		{type = "slider", label = "Trails", min = 0.0, max = 240.0, step = 10.0, value = trail_len, fmt = "%.0f", unit = "pts",
			on = func(v: float) -> void: trail_len = v},
		{type = "toggle", label = "Orbits", value = show_orbits, on = func(on: bool) -> void: show_orbits = on},
		{type = "toggle", label = "Spin", value = spin, on = func(on: bool) -> void: spin = on},
		{type = "toggle", label = "Clouds", value = clouds_on, on = func(on: bool) -> void:
			clouds_on = on
			cloud_shell.visible = on},
		{type = "toggle", label = "Night lights", value = lights_on, on = func(on: bool) -> void:
			lights_on = on
			earth_mat.set_shader_parameter("city_lights", 1.0 if on else 0.0)},
		{type = "toggle", label = "Grid", value = grid_on, on = func(on: bool) -> void:
			grid_on = on
			grid.visible = on},
	])
	return c


# --- building ----------------------------------------------------------------

func build() -> void:
	poke_mode = true
	focus = Vector3.ZERO
	distance = 5.0
	min_distance = 1.5
	max_distance = 90.0
	pitch = -0.32
	yaw = 0.9
	min_pitch = -1.5
	max_pitch = 1.5
	auto_orbit = 0.025
	camera.far = 2000.0

	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.55, 0.7)
	environment.ambient_light_energy = 0.25
	sky_mat.shader = preload("res://sims/orbits3d/space.gdshader")
	sky_mat.set_shader_parameter("star_map", preload("res://sims/orbits3d/starmap_nasa.jpg"))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	sun.shadow_enabled = false
	sun.light_energy = 1.3
	sun.basis = Basis.looking_at(-sun_dir)

	# the Earth: a tilted frame, the ball spinning in it, clouds on top, air round it
	earth_tilt.basis = equator
	world.add_child(earth_tilt)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 96
	ball.rings = 48
	earth.mesh = ball
	earth_mat.shader = preload("res://sims/orbits3d/earth.gdshader")
	earth_mat.set_shader_parameter("day_map", preload("res://sims/orbits3d/earth_day.jpg"))
	earth_mat.set_shader_parameter("night_map", preload("res://sims/orbits3d/earth_night.jpg"))
	earth.material_override = earth_mat
	earth_tilt.add_child(earth)
	var shell := SphereMesh.new()
	shell.radius = 1.025
	shell.height = 2.05
	shell.radial_segments = 72
	shell.rings = 36
	cloud_shell.mesh = shell
	cloud_mat.shader = preload("res://sims/orbits3d/cloud_shell.gdshader")
	cloud_shell.material_override = cloud_mat
	earth.add_child(cloud_shell)
	var outer := SphereMesh.new()
	outer.radius = 1.09
	outer.height = 2.18
	outer.radial_segments = 64
	outer.rings = 32
	air_shell.mesh = outer
	air_mat.shader = preload("res://sims/orbits3d/air.gdshader")
	air_shell.material_override = air_mat
	world.add_child(air_shell)

	var moon_ball := SphereMesh.new()
	moon_ball.radius = MOON_RADIUS
	moon_ball.height = MOON_RADIUS * 2.0
	moon_ball.radial_segments = 48
	moon_ball.rings = 24
	moon.mesh = moon_ball
	moon_mat.shader = preload("res://sims/orbits3d/moon.gdshader")
	moon_mat.set_shader_parameter("moon_map", preload("res://sims/orbits3d/moon_lroc.jpg"))
	moon.material_override = moon_mat
	world.add_child(moon)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _satellite_mesh()
	mm.instance_count = MAX_SATS
	mm.visible_instance_count = 0
	sat_mm.multimesh = mm
	world.add_child(sat_mm)

	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	lines.mesh = ArrayMesh.new()
	lines.material_override = line_mat
	world.add_child(lines)
	grid.mesh = ArrayMesh.new()
	grid.material_override = line_mat
	grid.visible = grid_on
	world.add_child(grid)
	_build_grid()

	_update_bodies()
	_preset_leo()


## A little satellite: a gold box body with a long blue solar panel on each side.
func _satellite_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	var parts := [
		[Vector3(0.5, 0.5, 0.75), [Vector3.ZERO], Color("d9a640"), 0.7],
		[Vector3(1.1, 0.04, 0.45), [Vector3(-0.85, 0, 0), Vector3(0.85, 0, 0)], Color("27407f"), 0.2],
		[Vector3(0.08, 0.08, 0.35), [Vector3(0, 0, -0.5)], Color("e8e8f0"), 0.5],
	]
	for part in parts:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var box := BoxMesh.new()
		box.size = part[0]
		for offset: Vector3 in part[1]:
			st.append_from(box, 0, Transform3D(Basis(), offset))
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		var m := StandardMaterial3D.new()
		m.albedo_color = part[2]
		m.metallic = part[3]
		m.roughness = 0.45
		m.emission_enabled = true
		m.emission = part[2] * 0.25
		am.surface_set_material(am.get_surface_count() - 1, m)
	return am


## Editor-style guides: the equator's plane in rings (geostationary picked out), the Moon's
## path, and the axes (x red, y green, z blue) with the Earth's own axis through the poles.
func _build_grid() -> void:
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var geo := _geo_radius()
	var r := 2.0
	while r <= moon_dist + 0.01:
		_circle(pts, cols, equator, r, Color(0.6, 0.7, 0.9, 0.16))
		r += 2.0
	_circle(pts, cols, equator, geo, Color(1.0, 0.82, 0.4, 0.45))
	_circle(pts, cols, moon_plane, moon_dist, Color(0.85, 0.85, 0.9, 0.35))
	var axes := [[Vector3.RIGHT, Color(0.95, 0.35, 0.35, 0.7)], [Vector3.UP, Color(0.45, 0.9, 0.45, 0.7)],
		[Vector3.BACK, Color(0.4, 0.6, 1.0, 0.7)]]
	for a in axes:
		pts.append_array([Vector3.ZERO, a[0] * 3.0])
		cols.append_array([a[1], a[1]])
	var pole: Vector3 = equator.y
	pts.append_array([-pole * 1.6, pole * 1.6])
	cols.append_array([Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.6)])
	_set_lines(grid.mesh, pts, cols)


func _circle(pts: PackedVector3Array, cols: PackedColorArray, b: Basis, r: float, c: Color, n := 128) -> void:
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		pts.append(b * Vector3(cos(a0), 0, -sin(a0)) * r)
		pts.append(b * Vector3(cos(a1), 0, -sin(a1)) * r)
		cols.append(c)
		cols.append(c)


func _set_lines(mesh: ArrayMesh, pts: PackedVector3Array, cols: PackedColorArray) -> void:
	mesh.clear_surfaces()
	if pts.size() < 2:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)


# --- physics -----------------------------------------------------------------

func _gm() -> float:
	return GM_EARTH * mass


func _gm_moon() -> float:
	return _gm() * MOON_RATIO if moon_on else 0.0


func _moon_rate() -> float:
	return sqrt(_gm() * (1.0 + MOON_RATIO) / pow(moon_dist, 3.0))


func _moon_at(theta: float) -> Vector3:
	return moon_plane * Vector3(cos(theta), 0.0, -sin(theta)) * moon_dist


func _geo_radius() -> float:
	return pow(_gm() * pow(DAY / TAU, 2.0), 1.0 / 3.0)


## Gravity at p: the Earth's, and the Moon's at m less its pull on the Earth (we ride with it).
func _accel(p: Vector3, m: Vector3, gm: float, gmm: float) -> Vector3:
	var r2 := p.length_squared()
	var a := -p * (gm / (r2 * sqrt(r2)))
	if gmm > 0.0:
		var d := p - m
		var d2 := d.length_squared()
		a -= d * (gmm / (d2 * sqrt(d2)))
		var m2 := m.length_squared()
		a -= m * (gmm / (m2 * sqrt(m2)))
	return a


## A step a fortieth of the way round whatever it is orbiting nearest.
func _step(p: Vector3, m: Vector3, gm: float, gmm: float) -> float:
	var r := p.length()
	var h := 0.025 * sqrt(r * r * r / gm)
	if gmm > 0.0:
		var d := p.distance_to(m)
		h = minf(h, 0.025 * sqrt(d * d * d / gmm))
	return maxf(h, 0.0005)


## Moves a body on by dt (sim seconds) from the moment the Moon is at theta0. Calls `visit`
## (if given) with each new position. Returns 0 still flying, 1 hit the Earth, 2 hit the Moon.
func _advance(body: Dictionary, dt: float, theta0: float, visit := Callable()) -> int:
	var gm := _gm()
	var gmm := _gm_moon()
	var w := _moon_rate()
	var p: Vector3 = body.p
	var v: Vector3 = body.v
	var t := 0.0
	var m := _moon_at(theta0)
	var a := _accel(p, m, gm, gmm)
	var steps := 0
	var result := 0
	while t < dt and steps < MAX_STEPS:
		steps += 1
		var h := minf(_step(p, m, gm, gmm), dt - t)
		v += a * (h * 0.5)
		p += v * h
		t += h
		m = _moon_at(theta0 + w * t)
		a = _accel(p, m, gm, gmm)
		v += a * (h * 0.5)
		if visit.is_valid():
			visit.call(p)
		if p.length_squared() < 1.0:
			result = 1
			break
		if gmm > 0.0 and p.distance_squared_to(m) < MOON_RADIUS * MOON_RADIUS:
			result = 2
			break
	body.p = p
	body.v = v
	body.t = t
	return result


## Orbital elements about the Earth alone (two-body).
func _elements(p: Vector3, v: Vector3, gm: float) -> Dictionary:
	var r := p.length()
	var hv := p.cross(v)
	var ev := v.cross(hv) / gm - p / r
	var e := ev.length()
	var energy := v.length_squared() * 0.5 - gm / r
	var el := {e = e, ev = ev, h = hv, energy = energy, kind = 2, rp = 0.0, ra = INF, a = INF, period = INF}
	el.rp = hv.length_squared() / (gm * (1.0 + e))
	if energy < 0.0:
		var a := -gm / (2.0 * energy)
		el.a = a
		el.ra = a * (1.0 + e)
		el.period = TAU * sqrt(a * a * a / gm)
		el.kind = 1 if el.rp > 1.0 else 0
	return el


func _describe(el: Dictionary) -> String:
	match el.kind:
		0:
			return "suborbital, peak %s" % _km(el.ra - 1.0)
		2:
			var v_inf := sqrt(maxf(2.0 * el.energy, 0.0)) * KM / SECONDS
			return "escape, Pe %s, v∞ %.1f km/s" % [_km(el.rp - 1.0), v_inf]
	var hours: float = el.period * SECONDS / 3600.0
	return "e=%.2f, Pe %s, Ap %s, T %d h %02d m" % [el.e, _km(el.rp - 1.0), _km(el.ra - 1.0), int(hours), int(fmod(hours * 60.0, 60.0))]


## An altitude in Earth radii as km, with thin spaces between the thousands.
func _km(alt: float) -> String:
	var n := int(round(alt * KM))
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out + " km"


# --- satellites --------------------------------------------------------------

func _launch(p: Vector3, v: Vector3) -> void:
	if sats.size() >= MAX_SATS:
		sats.pop_front()
	var c: Color = COLORS[color_index % COLORS.size()]
	color_index += 1
	sats.append({p = p, v = v, trail = [p], gap = 0.0, color = c, fade = 1.0, t = 0.0})
	last_info = _describe(_elements(p, v, _gm()))


## A satellite on a Kepler orbit: semi-major axis a, eccentricity e, its plane and perigee given
## by P (towards perigee) and Q (90° on, the way it goes), at true anomaly nu.
func _kepler(a: float, e: float, P: Vector3, Q: Vector3, nu: float) -> void:
	var gm := _gm()
	var semi := a * (1.0 - e * e)
	var r := semi / (1.0 + e * cos(nu))
	var p := (P * cos(nu) + Q * sin(nu)) * r
	var v := (-P * sin(nu) + Q * (e + cos(nu))) * sqrt(gm / semi)
	_launch(p, v)


## The in-plane axes of an orbit tilted by `incline` about a line of nodes turned `node` round
## the equator, with the perigee `perigee` on from the node.
func _plane(incline: float, node: float, perigee: float) -> Array:
	var b := equator * Basis(Vector3.UP, node) * Basis(Vector3.RIGHT, incline)
	var x := b * Vector3.RIGHT
	var q := b * Vector3.FORWARD
	return [x * cos(perigee) + q * sin(perigee), -x * sin(perigee) + q * cos(perigee)]


func _clear() -> void:
	sats.clear()
	last_info = ""
	burned = 0
	escaped = 0


func _preset_leo() -> void:
	_clear()
	for i in 4:
		var pl := _plane(deg_to_rad([28.5, 51.6, 97.0, 5.0][i]), i * 1.4, 0.0)
		_kepler(1.06 + i * 0.05, 0.0, pl[0], pl[1], i * 1.7)
	warp = maxf(warp, 1.0)


func _preset_geo() -> void:
	_clear()
	var pl := _plane(0.0, 0.0, 0.0)
	for i in 8:
		_kepler(_geo_radius(), 0.0, pl[0], pl[1], TAU * i / 8.0)
	_kepler(1.08, 0.0, pl[0], pl[1], 0.3)
	if distance < 16.0:
		distance = 18.0
		_place_camera()


## Molniya: twelve-hour orbits at 63.4° (where the perigee stays put), stretched so each
## satellite hangs for hours over the north with its apogee there.
func _preset_molniya() -> void:
	_clear()
	var a := pow(_gm() * pow(DAY * 0.5 / TAU, 2.0), 1.0 / 3.0)
	for i in 3:
		var pl := _plane(deg_to_rad(63.4), i * TAU / 3.0, deg_to_rad(270.0))
		_kepler(a, 0.74, pl[0], pl[1], PI * 0.75 + i * 0.6)
	if distance < 14.0:
		distance = 16.0
		_place_camera()


## A Hohmann-style transfer from low orbit, timed so it reaches the Moon's distance just as the
## Moon gets there, a little ahead of it, so the Moon swings it round into a big new orbit
## (at the default 14 radii; at other distances it may hit the Moon or come home).
func _preset_lunar() -> void:
	_clear()
	moon_on = true
	var r1 := 1.06
	var a := (r1 + moon_dist) * 0.5
	var flight := PI * sqrt(a * a * a / _gm())
	var theta := moon_theta + _moon_rate() * flight - PI + 0.2
	var dir := moon_plane * Vector3(cos(theta), 0.0, -sin(theta))
	var along := moon_plane * Vector3(-sin(theta), 0.0, -cos(theta))
	var speed := sqrt(_gm() * (2.0 / r1 - 1.0 / a))
	_launch(dir * r1, along * speed)
	warp = maxf(warp, 20.0)
	if distance < moon_dist * 1.6:
		distance = moon_dist * 1.7
		_place_camera()


func _preset_swarm() -> void:
	_clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	for i in 20:
		var pl := _plane(rng.randf_range(0.0, PI * 0.6), rng.randf() * TAU, rng.randf() * TAU)
		var rp := rng.randf_range(1.05, 2.0)
		var e := rng.randf_range(0.0, 0.45)
		_kepler(rp / (1.0 - e), e, pl[0], pl[1], rng.randf() * TAU)


func _burn(at: Vector3, on_moon: bool) -> void:
	var q := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	q.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = flash_shader
	mat.set_shader_parameter("tint", Color(0.8, 0.8, 0.9) if on_moon else Color(1.0, 0.55, 0.2))
	q.material_override = mat
	q.position = at
	world.add_child(q)
	flashes.append({node = q, mat = mat, life = 0.0})


# --- each frame --------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	var dt := minf(delta, 0.05) * warp
	var theta0 := moon_theta
	var escape_r := maxf(moon_dist * 2.5, 30.0)
	var keep: Array[Dictionary] = []
	for s in sats:
		if s.fade < 1.0:
			s.fade -= delta
			if s.fade > 0.0:
				keep.append(s)
			continue
		var trail: Array = s.trail # (an Array, so the closure below adds to this one)
		var hit := _advance(s, dt, theta0, func(p: Vector3) -> void:
			s.gap += p.distance_to(trail[trail.size() - 1])
			if s.gap > 0.03 * sqrt(p.length()):
				s.gap = 0.0
				trail.append(p))
		trail.append(s.p)
		var extra := trail.size() - int(trail_len) - 1
		if extra > 0:
			trail = trail.slice(extra)
		s.trail = trail
		if hit > 0:
			_burn(s.p, hit == 2)
			burned += 1
			continue
		if s.p.length() > escape_r:
			s.fade = 0.99
			escaped += 1
		keep.append(s)
	sats = keep
	moon_theta += _moon_rate() * dt
	if spin:
		earth_angle = fmod(earth_angle + TAU / DAY * dt, TAU)
	cloud_drift += 0.004 * dt
	_update_bodies()
	_update_flashes(delta)
	_draw_sats()
	_draw_lines()


func _update_bodies() -> void:
	earth.basis = Basis(Vector3.UP, earth_angle)
	var sun_local := earth.global_basis.inverse() * sun_dir
	for mat in [earth_mat, cloud_mat, air_mat, moon_mat]:
		mat.set_shader_parameter("sun_dir", sun_dir)
	earth_mat.set_shader_parameter("sun_local", sun_local)
	earth_mat.set_shader_parameter("cloud_drift", cloud_drift)
	earth_mat.set_shader_parameter("cloud_opacity", 0.85 if clouds_on else 0.0)
	cloud_mat.set_shader_parameter("cloud_drift", cloud_drift)
	var m := _moon_at(moon_theta)
	moon.position = m
	# near side to the Earth: the ball's +Z faces home
	moon.basis = Basis.looking_at(m.normalized(), moon_plane.y)


func _update_flashes(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for f in flashes:
		f.life += delta / 0.9
		if f.life >= 1.0:
			f.node.queue_free()
			continue
		f.mat.set_shader_parameter("life", f.life)
		f.node.scale = Vector3.ONE * (0.25 + 0.6 * sqrt(f.life)) * clampf(distance / 8.0, 0.6, 4.0)
		keep.append(f)
	flashes = keep


func _draw_sats() -> void:
	var mm := sat_mm.multimesh
	var size_k := 0.04 * clampf(distance / 5.0, 1.0, 8.0)
	mm.visible_instance_count = sats.size()
	for i in sats.size():
		var s := sats[i]
		var p: Vector3 = s.p
		var up: Vector3 = s.v.normalized()
		var down := -p.normalized()
		if absf(up.dot(down)) > 0.99:
			up = Vector3.UP if absf(down.y) < 0.9 else Vector3.RIGHT
		var b := Basis.looking_at(down, up).scaled(Vector3.ONE * size_k * clampf(s.fade, 0.0, 1.0))
		mm.set_instance_transform(i, Transform3D(b, p))


func _draw_lines() -> void:
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	for s in sats:
		var trail: Array = s.trail # (an Array, so the closure below adds to this one)
		var n := trail.size()
		var c: Color = s.color
		var f: float = clampf(s.fade, 0.0, 1.0)
		for k in range(1, n):
			pts.append(trail[k - 1])
			pts.append(trail[k])
			cols.append(Color(c, f * (0.1 + 0.85 * float(k - 1) / n)))
			cols.append(Color(c, f * (0.1 + 0.85 * float(k) / n)))
		if show_orbits and s.fade >= 1.0:
			_orbit_ring(pts, cols, s.p, s.v, Color(c, 0.35))
	if not aim.is_empty():
		var v := _aim_velocity()
		# the slingshot band, and which way it will go
		var band := Color(1, 1, 1, 0.8)
		pts.append_array([aim.start, aim.end, aim.start, aim.start + v * 0.5])
		cols.append_array([band, band, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.1)])
		if show_prediction:
			_dashes(pts, cols, prediction, KIND_COLORS[prediction_kind])
	_set_lines(lines.mesh, pts, cols)


## The osculating ellipse a satellite would follow round the Earth alone.
func _orbit_ring(pts: PackedVector3Array, cols: PackedColorArray, p: Vector3, v: Vector3, c: Color) -> void:
	var el := _elements(p, v, _gm())
	if el.kind == 2:
		return
	var h: Vector3 = el.h
	if h.length_squared() < 1e-9:
		return
	var P: Vector3 = el.ev.normalized() if el.e > 1e-4 else p.normalized()
	var Q := h.normalized().cross(P)
	var semi: float = el.a * (1.0 - el.e * el.e)
	var prev := Vector3.ZERO
	for i in 97:
		var nu := TAU * i / 96.0
		var at: Vector3 = (P * cos(nu) + Q * sin(nu)) * (semi / (1.0 + el.e * cos(nu)))
		if i > 0:
			pts.append_array([prev, at])
			cols.append_array([c, c])
		prev = at


## A line drawn in dashes of even length along a path.
func _dashes(pts: PackedVector3Array, cols: PackedColorArray, path: PackedVector3Array, c: Color) -> void:
	var dash := 0.06 * clampf(distance / 8.0, 0.6, 6.0)
	var run := 0.0
	var on := true
	for k in range(1, path.size()):
		var a := path[k - 1]
		var b := path[k]
		run += a.distance_to(b)
		if run > dash:
			run = 0.0
			on = not on
		if on:
			var fade := 1.0 - 0.6 * float(k) / path.size()
			pts.append_array([a, b])
			cols.append_array([Color(c, fade), Color(c, fade)])


# --- the finger --------------------------------------------------------------

func _aim_velocity() -> Vector3:
	if aim.is_empty():
		return Vector3.ZERO
	if not aim.moved:
		return _circular_velocity(aim.start)
	return (aim.start - aim.end) * 1.2 * launch_mult


## Prograde round the Earth's axis at the speed for a circle through p.
func _circular_velocity(p: Vector3) -> Vector3:
	var axis: Vector3 = equator.y
	var along := axis.cross(p)
	if along.length_squared() < 1e-6:
		along = camera.global_basis.x.cross(p)
	return along.normalized() * sqrt(_gm() / p.length())


func poke_down(pos: Vector2) -> void:
	var r := ray(pos)
	var from: Vector3 = r.from
	var dir: Vector3 = r.dir
	var shell := 1.0 + LAUNCH_ALT
	var start := Vector3.ZERO
	# on the globe: launch from just above where the finger is
	var b := from.dot(dir)
	var c := from.length_squared() - shell * shell
	var disc := b * b - c
	if disc >= 0.0 and -b - sqrt(disc) > 0.0:
		start = from + dir * (-b - sqrt(disc))
	else:
		# out in space: on the plane through the Earth facing the camera, kept off the ground
		var hit: Variant = Plane(camera.global_basis.z, 0.0).intersects_ray(from, dir)
		if hit == null:
			return
		start = hit
		if start.length() < shell:
			start = start.normalized() * shell
	aim = {start = start, end = start, plane = Plane(camera.global_basis.z, start), moved = false, at = pos}
	_update_prediction()


func poke_move(pos: Vector2) -> void:
	if aim.is_empty():
		return
	var r := ray(pos)
	var hit: Variant = (aim.plane as Plane).intersects_ray(r.from, r.dir)
	if hit != null:
		aim.end = hit
	if pos.distance_to(aim.at) > 14.0:
		aim.moved = true
	_update_prediction()


func poke_up(_pos: Vector2) -> void:
	if aim.is_empty():
		return
	_launch(aim.start, _aim_velocity())
	aim = {}
	auto_orbit = 0.0


func _update_prediction() -> void:
	prediction = PackedVector3Array()
	var v := _aim_velocity()
	var el := _elements(aim.start, v, _gm())
	prediction_kind = el.kind
	if not show_prediction:
		return
	var body := {p = aim.start, v = v}
	var horizon: float = minf(el.period * 1.02, 600.0) if el.kind == 1 else 600.0
	var escape_r := maxf(moon_dist * 2.5, 30.0)
	var path: Array = [aim.start]
	var elapsed := 0.0
	var theta := moon_theta
	var budget := 5
	# in chunks, so it can stop once it has gone far enough away
	while elapsed < horizon and budget > 0:
		budget -= 1
		var hit := _advance(body, horizon - elapsed, theta, func(p: Vector3) -> void: path.append(p))
		elapsed += body.t
		theta = moon_theta + _moon_rate() * elapsed
		if hit > 0 or body.p.length() > escape_r:
			break
	prediction = PackedVector3Array(path)
