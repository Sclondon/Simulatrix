extends Sim3D
## Ocean: GameCommon's ocean (OceanSurface, a wind-built Gerstner sea out to the horizon) with
## a moored buoy and whatever you drop in floating on it (OceanFloater), under GameCommon
## weather's sky and time of day (Daylight). Export saves the sea's settings as a scene.

const MAX_FLOATERS := 20

var sea := OceanSurface.new()
var palette := 0
var hour := 15.5
var cycle := false
var clouds := 0.3
var drop_kind := 0

var _sky_mat: ShaderMaterial
var _buoy: OceanFloater
var _lamp: OmniLight3D
var _lamp_glow: StandardMaterial3D
var _floaters: Array[OceanFloater] = []
var _cloud_shift := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func help() -> String:
	return ("A sea of Gerstner waves driven by the wind (GameCommon's ocean). Wind speed sets the sea state the "
		+ "way it does on a real ocean: stronger wind, longer and higher waves (Pierson-Moskowitz). Chop pushes "
		+ "the water toward each crest; where the surface folds over, the crest breaks into foam. Swell adds long "
		+ "waves from a distant storm; gusts darken and roughen the water in patches running downwind.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom. In Poke mode, tap the water to drop something in: it floats on "
		+ "the same waves you see.\n\nExport saves this sea as a scene for any project (needs godot/ocean).")


func hint() -> String:
	return "Drag to orbit. Switch Finger to Poke and tap to drop things in."


func pokeable() -> bool:
	return true


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Wind"},
		{type = "slider", label = "Speed", min = 0.0, max = 25.0, step = 0.5, value = sea.wind, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: sea.wind = v},
		{type = "slider", label = "From", min = 0.0, max = 360.0, step = 5.0, value = sea.wind_from, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: sea.wind_from = v},
		{type = "slider", label = "Gusts", min = 0.0, max = 1.0, step = 0.05, value = sea.gusts, fmt = "%.2f",
			on = func(v: float) -> void: sea.gusts = v},
		{type = "toggle", label = "Wind lines", value = sea.wind_lines, on = func(v: bool) -> void: sea.wind_lines = v},
		{type = "section", label = "Waves"},
		{type = "slider", label = "Height", min = 0.0, max = 2.0, step = 0.05, value = sea.height_scale, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: sea.height_scale = v},
		{type = "slider", label = "Chop", min = 0.0, max = 1.0, step = 0.05, value = sea.chop, fmt = "%.2f",
			on = func(v: float) -> void: sea.chop = v},
		{type = "slider", label = "Spread", min = 0.0, max = 90.0, step = 5.0, value = sea.spread, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: sea.spread = v},
		{type = "slider", label = "Swell", min = 0.0, max = 3.0, step = 0.1, value = sea.swell, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: sea.swell = v},
		{type = "slider", label = "Foam", min = 0.0, max = 1.0, step = 0.05, value = sea.foam, fmt = "%.2f",
			on = func(v: float) -> void: sea.foam = v},
		{type = "section", label = "Look"},
		{type = "choice", label = "Water", options = OceanSurface.PALETTES.map(func(p: Array) -> String: return p[0]), value = palette,
			on = func(i: int) -> void: palette = i; sea.use_palette(i)},
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
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = sea.quality,
			on = func(i: int) -> void: sea.quality = i},
	])
	c.append_array(Exporter.controls("Sea", _export, "ocean", func(line: String) -> void: say.emit(line)))
	return c


func status() -> String:
	return "Hs %.1f m · Tp %.1f s · λp %.0f m · %d waves · %d floating · %.1f ms" % [
		sea.significant_height(), sea.peak_period(), sea.peak_length(), sea.wave_count(), _floaters.size() + 1, frame_ms()]


## Re-applies every setting (for scripts that set the vars directly).
func refresh() -> void:
	sea.refresh()
	_apply_day()


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
	sea.sun = sun
	world.add_child(sea)
	_build_buoy()
	_apply_day()
	# A few things already afloat
	for i in 4:
		var a := _rng.randf() * TAU
		_add_floater(i % 3, Vector3(cos(a), 0, sin(a)) * _rng.randf_range(6.0, 14.0), false)


func _apply_day() -> void:
	var day := Daylight.at(hour)
	var dim := clampf((clouds - 0.65) / 0.35, 0.0, 1.0)
	Daylight.apply(day, _sky_mat, environment, sun, dim)
	_sky_mat.set_shader_parameter("cloud_cover", clouds)
	_sky_mat.set_shader_parameter("ground", Color(0.02, 0.06, 0.12))
	sea.horizon_color = _sky_mat.get_shader_parameter("horizon")
	sea.zenith_color = _sky_mat.get_shader_parameter("zenith")
	sea.overcast = dim
	if _lamp:
		_lamp.visible = day.night > 0.3


# --- things in the water -----------------------------------------------------

func _build_buoy() -> void:
	_buoy = OceanFloater.new()
	_buoy.ocean = sea
	_buoy.half_height = 0.6
	_buoy.sink = 0.55
	_buoy.anchored = true
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
	world.add_child(_buoy)


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
		sea.splash(pos)
		return
	var f := OceanFloater.new()
	f.ocean = sea
	f.add_child(_floater_mesh(kind))
	f.half_height = [0.55, 0.42, 0.45][kind]
	f.sink = [0.45, 0.5, 0.35][kind]
	f.spin = _rng.randf_range(-0.3, 0.3)
	pos.y = 7.0 + _rng.randf() * 3.0 if falling else sea.height_at(pos.x, pos.z)
	f.position = pos
	f.rotation.y = _rng.randf() * TAU
	world.add_child(f)
	_floaters.append(f)
	# The oldest goes when there are too many
	if _floaters.size() > MAX_FLOATERS:
		_floaters.pop_front().queue_free()


func _drop_many() -> void:
	for i in 6:
		var a := _rng.randf() * TAU
		var kind := drop_kind if drop_kind < 3 else i % 3
		_add_floater(kind, focus + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 12.0))


func _clear() -> void:
	for f in _floaters:
		f.queue_free()
	_floaters.clear()


func _export(name: String) -> void:
	# A fresh sea with these settings (not the running one, so none of its built meshes go too)
	var out := OceanSurface.new()
	out.name = Exporter.slug(name).to_pascal_case()
	for p in ["wind", "wind_from", "height_scale", "chop", "spread", "swell", "foam", "gusts", "deep_color",
			"scatter_color", "foam_color", "toon", "wind_lines", "quality", "size", "horizon_color", "zenith_color", "overcast"]:
		out.set(p, sea.get(p))
	var slug := Exporter.slug(name)
	say.emit(Exporter.save("ocean", name, {"tscn": out}, ["godot/ocean"],
		"var sea := (load(\"res://assets/ocean/%s.tscn\") as PackedScene).instantiate() as OceanSurface\n" % slug
		+ "add_child(sea)   # then: sea.sun = $Sun, and OceanFloater children to float things", "Ocean"))
	out.free()


# --- running -----------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	if cycle:
		hour = fposmod(hour + delta * 0.25, 24.0)
		_apply_day()
	_cloud_shift += sea.wind_dir() * (0.002 + sea.wind * 0.0004) * delta
	_sky_mat.set_shader_parameter("cloud_offset", _cloud_shift)
	if _lamp and _lamp.visible:
		var on := fmod(Time.get_ticks_msec() / 1000.0, 2.5) < 0.6
		_lamp.light_energy = 2.5 if on else 0.0
		_lamp_glow.albedo_color = Color(1.0, 0.85, 0.5) if on else Color(0.3, 0.22, 0.12)


func poke_down(pos: Vector2) -> void:
	var hit: Variant = ground(pos, 0.0)
	if hit != null:
		_add_floater(drop_kind, hit)
