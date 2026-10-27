extends Sim3D
## Weather Lab: GameCommon's weather (WeatherRig: clouds you can shape, rain with splashes and
## puddles, settling snow, hail, branching lightning with its flash and thunder delay, fog, the
## time of day) over a meadow of GameCommon pines and broadleaf trees with mountains round it.
## The land (weather_ground.gdshader) and the trees take the weather through the rig's register()
## and weathered(). The painted-woodland kit gives the sun shafts (crepuscular rays through the
## gaps in the cloud) and the Painted sky style. Export saves the weather as a scene.

const GROUND := preload("res://sims/vfx/weather_ground.gdshader")
const TYPES := ["Cumulus", "Stratus", "Storm", "Cirrus"]
const KINDS := ["None", "Rain", "Snow", "Hail"]

var rig := WeatherRig.new()
var sky_style := 0 # 0 the rig's sky (moon, stars, its cloud layer), 1 the painted woodland's
var shafts_on := true
var shaft_strength := 0.6

var _painted_sky := ShaderMaterial.new()
var _shafts := Node3D.new()
var _shaft_mats: Array[ShaderMaterial] = []
var _shaft_sun := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func help() -> String:
	return ("A weather lab on GameCommon's weather. Pick a cloud type and shape it: cover, base height, thickness, "
		+ "speed. Cumulus are fair-weather heaps lit from the sun with dark bellies; stratus is a grey deck that dims "
		+ "the day; a storm is a towering cumulonimbus with a spreading anvil; cirrus are high ice streaks.\n\n"
		+ "Rain wets the ground (it darkens, puddles form in the low spots and ring with drops), snow settles "
		+ "on everything that faces up, hail bounces. Lightning branches down from the cloud base; count the "
		+ "seconds to the thunder (sound travels 343 m/s) to know how far it struck.\n\n"
		+ "Sun shafts (crepuscular rays) slant down from the sun where it breaks through: strongest with broken "
		+ "cloud and a low sun, gone under a full deck or at night. The Painted sky is the painted woodland's: gold "
		+ "low by the sun, cooling overhead, with long streaks (no moon, stars or flash in it).\n\n"
		+ "Drag to orbit, pinch or wheel to zoom. In Poke mode, tap the ground to strike it.\n\n"
		+ "Export saves this weather as a scene for any project (needs godot/weather).")


func hint() -> String:
	return "Drag to orbit. Try Clouds > Storm, Rain, and Auto storm."


func pokeable() -> bool:
	return true


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Time"},
		{type = "slider", label = "Hour", min = 0.0, max = 24.0, step = 0.25, value = rig.hour, fmt = "%05.2f", unit = "h",
			on = func(v: float) -> void: rig.hour = v},
		{type = "toggle", label = "Day cycle", value = rig.day_speed > 0.0, on = func(v: bool) -> void: rig.day_speed = 0.2 if v else 0.0},
		{type = "section", label = "Light"},
		{type = "choice", label = "Sky", options = ["Lab", "Painted"], value = sky_style, on = func(i: int) -> void:
			sky_style = i
			environment.sky.sky_material = _painted_sky if i == 1 else rig.sky_material},
		{type = "toggle", label = "Sun shafts", value = shafts_on, on = func(v: bool) -> void:
			shafts_on = v
			_shafts.visible = v},
		{type = "slider", label = "Shafts", min = 0.0, max = 1.5, step = 0.05, value = shaft_strength, fmt = "%.2f",
			on = func(v: float) -> void: shaft_strength = v},
		{type = "section", label = "Clouds"},
		{type = "choice", label = "Type", options = TYPES, value = rig.cloud_type,
			on = func(i: int) -> void: rig.cloud_type = i},
		{type = "slider", label = "Cover", min = 0.0, max = 1.0, step = 0.05, value = rig.cover, fmt = "%.2f",
			on = func(v: float) -> void: rig.cover = v},
		{type = "slider", label = "Base", min = 300.0, max = 3000.0, step = 50.0, value = rig.base, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void: rig.base = v},
		{type = "slider", label = "Thickness", min = 0.3, max = 2.0, step = 0.05, value = rig.thickness, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.thickness = v},
		{type = "slider", label = "Speed", min = 0.0, max = 4.0, step = 0.1, value = rig.cloud_speed, fmt = "%.1f", unit = "×",
			on = func(v: float) -> void: rig.cloud_speed = v},
		{type = "slider", label = "Warmth", min = 0.0, max = 1.0, step = 0.05, value = rig.warmth, fmt = "%.2f",
			on = func(v: float) -> void: rig.warmth = v},
		{type = "section", label = "Precipitation"},
		{type = "choice", label = "Kind", options = KINDS, value = rig.precip,
			on = func(i: int) -> void: rig.precip = i},
		{type = "slider", label = "Intensity", min = 0.05, max = 1.0, step = 0.05, value = rig.intensity, fmt = "%.2f",
			on = func(v: float) -> void: rig.intensity = v},
		{type = "toggle", label = "Settle", value = rig.settle, on = func(v: bool) -> void: rig.settle = v},
		{type = "button", label = "Dry ground", on = func() -> void: rig.dry()},
		{type = "section", label = "Lightning"},
		{type = "button", label = "Strike", on = func() -> void: rig.strike()},
		{type = "toggle", label = "Auto storm", value = rig.auto_storm, on = func(v: bool) -> void: rig.auto_storm = v},
		{type = "slider", label = "Rate", min = 0.0, max = 1.0, step = 0.05, value = rig.strike_rate, fmt = "%.2f",
			on = func(v: float) -> void: rig.strike_rate = v},
		{type = "section", label = "Wind & air"},
		{type = "slider", label = "Wind", min = 0.0, max = 25.0, step = 0.5, value = rig.wind, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: rig.wind = v},
		{type = "slider", label = "From", min = 0.0, max = 360.0, step = 5.0, value = rig.wind_from, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: rig.wind_from = v},
		{type = "slider", label = "Fog", min = 0.0, max = 1.0, step = 0.05, value = rig.fog, fmt = "%.2f",
			on = func(v: float) -> void: rig.fog = v},
		{type = "section", label = "View"},
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = rig.quality,
			on = func(i: int) -> void: rig.quality = i},
	])
	c.append_array(Exporter.controls("Weather", _export, "weather", func(line: String) -> void: say.emit(line)))
	return c


func status() -> String:
	var s := "%s %d%% · base %d m" % [TYPES[rig.cloud_type], roundi(rig.cover * 100.0), roundi(rig.base)]
	if rig.precip > 0:
		s += " · %s %d%%" % [KINDS[rig.precip].to_lower(), roundi(rig.intensity * 100.0)]
	s += " · wet %d%% · snow %.0f cm · %d bolts" % [roundi(rig.wet * 100.0), rig.snow_depth * 25.0, rig.bolts]
	if rig.thunder_in() > 0.0:
		s += " · thunder in %.1f s (%.1f km)" % [rig.thunder_in(), rig.thunder_km()]
	return s + " · %.1f ms" % frame_ms()


## Re-applies every setting (for scripts that set the rig's exports directly).
func refresh() -> void:
	rig.refresh()


# --- building ----------------------------------------------------------------

func build() -> void:
	_rng.seed = 11
	focus = Vector3(0, 14, 0)
	distance = 46.0
	yaw = 0.5
	pitch = 0.06
	min_pitch = -1.2
	max_pitch = 0.25
	min_distance = 8.0
	max_distance = 110.0
	camera.near = 0.3
	camera.far = 22000.0
	sun.directional_shadow_max_distance = 120.0
	rig.sun = sun
	rig.environment = environment
	rig.ground_height = terrain
	world.add_child(rig)
	rig.set_ground(_ground_map(), Rect2(-300, -300, 600, 600))
	_painted_sky.shader = Woodland.SKY
	world.add_child(_shafts)
	_build_ground()
	_build_trees()


## Height of the land at (x, z): must match terrain() in weather_ground.gdshader.
static func terrain(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var bumps := sin(x * 0.05) * cos(z * 0.043) * 0.6 + sin(x * 0.13 + 1.0) * sin(z * 0.11) * 0.2
	var hills := sin(x * 0.004) * cos(z * 0.0035) * 28.0 + sin(x * 0.011 + 1.3) * sin(z * 0.009 + 0.7) * 9.0
	var a := atan2(z, x)
	var ridge := 0.6 + 0.4 * sin(a * 5.0 + 1.0) * sin(a * 3.0 + 2.0) + 0.15 * sin(a * 17.0) + 0.08 * sin(x * 0.003 + z * 0.002)
	var mountains := smoothstep(1800.0, 4800.0, r) * 900.0 * ridge
	return bumps + (hills + 6.0) * smoothstep(160.0, 700.0, r) + mountains


## The land round the middle as a height map, for the rain to splash on.
func _ground_map() -> ImageTexture:
	var n := 300
	var img := Image.create(n, n, false, Image.FORMAT_RH)
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color(terrain(-300.0 + (x + 0.5) * 2.0, -300.0 + (y + 0.5) * 2.0), 0, 0))
	return ImageTexture.create_from_image(img)


func _build_ground() -> void:
	for far in [false, true]:
		var mat := ShaderMaterial.new()
		mat.shader = GROUND
		mat.set_shader_parameter("noise_tex", Daylight.cloud_noise())
		mat.set_shader_parameter("hole", 1.0 if far else 0.0)
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * (16000.0 if far else 600.0)
		plane.subdivide_width = 300 if far else 120
		plane.subdivide_depth = plane.subdivide_width
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.extra_cull_margin = 1200.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		rig.register(mat)


func _build_trees() -> void:
	var pines := []
	var broad := []
	for i in 150:
		var a := _rng.randf() * TAU
		var r := 22.0 + pow(_rng.randf(), 0.8) * 240.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = terrain(p.x, p.z) - 0.1
		# Pines in stands to the north, broadleaf in the south and along the meadow
		if sin(a + 0.4) + _rng.randf_range(-0.6, 0.6) > 0.0:
			pines.append(p)
		else:
			broad.append(p)
	var pine := PineTree.new()
	pine.height = 11.0
	pine.material = rig.weathered(false, 11.0)
	PineTree.forest(world, pines, pine, 4, Vector2(0.7, 1.3), 64.0, 110.0)
	var oak := LeafyTree.oak()
	oak.material = rig.weathered(true, oak.height)
	LeafyTree.forest(world, broad.slice(0, broad.size() / 2), oak, 3, Vector2(0.8, 1.3), 64.0, 110.0)
	var aspen := LeafyTree.aspen()
	aspen.material = rig.weathered(true, aspen.height)
	LeafyTree.forest(world, broad.slice(broad.size() / 2), aspen, 3, Vector2(0.8, 1.3), 64.0, 110.0)
	# Boulders, for snow to settle on
	var rock_mat := rig.weathered(false, 1.0, Color(0.5, 0.49, 0.47), false)
	for i in 18:
		var a := _rng.randf() * TAU
		var r := 10.0 + _rng.randf() * 80.0
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radial_segments = 7
		s.rings = 4
		s.radius = 1.0
		s.height = 2.0
		mi.mesh = s
		mi.material_override = rock_mat
		var size := _rng.randf_range(0.5, 2.2)
		mi.scale = Vector3(size * _rng.randf_range(1.0, 1.6), size * 0.7, size)
		mi.rotation.y = _rng.randf() * TAU
		mi.position = Vector3(cos(a) * r, 0, sin(a) * r)
		mi.position.y = terrain(mi.position.x, mi.position.z) + size * 0.15
		world.add_child(mi)


func _export(name: String) -> void:
	# A fresh rig with these settings (not the running one, so none of what it built goes too)
	var out := WeatherRig.new()
	out.name = Exporter.slug(name).to_pascal_case()
	for p in ["hour", "day_speed", "cloud_type", "cover", "base", "thickness", "cloud_speed", "warmth", "precip",
			"intensity", "settle", "auto_storm", "strike_rate", "wind", "wind_from", "fog", "quality"]:
		out.set(p, rig.get(p))
	var slug := Exporter.slug(name)
	say.emit(Exporter.save("weather", name, {"tscn": out}, ["godot/weather"],
		"var weather := (load(\"res://assets/weather/%s.tscn\") as PackedScene).instantiate() as WeatherRig\n" % slug
		+ "weather.sun = $Sun   # or leave it to make its own; it drives the WorldEnvironment's sky and fog\n"
		+ "add_child(weather)", "Weather Lab"))
	out.free()


# --- running -----------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	if rig.day.is_empty():
		return
	var day := rig.day
	if sky_style == 1:
		var hor := rig.horizon_color()
		_painted_sky.set_shader_parameter("sun_dir", day.sun_dir)
		_painted_sky.set_shader_parameter("zenith", rig.zenith_color())
		_painted_sky.set_shader_parameter("horizon", hor)
		var lc: Color = day.light_color
		_painted_sky.set_shader_parameter("glow", hor.lerp(lc, (1.0 - day.night) * (1.0 - rig.dim * 0.7)))
	_update_shafts(day)


func poke_down(pos: Vector2) -> void:
	var r := ray(pos)
	# March the ray to the land
	var p: Vector3 = r.from
	var dir: Vector3 = r.dir
	var step := 2.0
	for i in 400:
		p += dir * step
		if p.y < terrain(p.x, p.z):
			rig.strike(p)
			return
		step *= 1.03


# --- sun shafts (the painted-woodland kit's) ------------------------------------

## Crepuscular rays: the kit's shaft cards slanting down from the sun over the valley, re-aimed as the
## sun moves. They show where the sun breaks through: most with broken cloud and a low sun, none under a
## full deck, in rain or at night.
func _update_shafts(day: Dictionary) -> void:
	if not shafts_on:
		return
	var sun_dir: Vector3 = day.sun_dir
	if sun_dir.y < 0.03:
		_shafts.visible = false
		return
	_shafts.visible = true
	if _shaft_sun == Vector3.ZERO or sun_dir.angle_to(_shaft_sun) > 0.03:
		_shaft_sun = sun_dir
		for child in _shafts.get_children():
			child.free()
		_shaft_mats.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		for i in 9:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(15.0, 120.0)
			p.y = terrain(p.x, p.z)
			Woodland.add_sun_shaft(_shafts, p, sun_dir, Color.WHITE, 260.0, rng.randf_range(14.0, 28.0), i * 2.3, 0.2)
		for g in _shafts.get_children():
			var m := (g as MeshInstance3D).material_override as ShaderMaterial
			if m and not _shaft_mats.has(m):
				_shaft_mats.append(m)
	# breaks in the cloud: none in clear sky (nothing to cast them) or under a full deck
	var cover := rig.cover
	var gap: float = clampf(0.25 + 3.0 * cover * (1.0 - cover), 0.0, 1.0) * [1.0, 0.35, 0.6, 0.5][rig.cloud_type]
	var low := 1.0 + smoothstep(0.5, 0.08, sun_dir.y)
	var rain := 1.0 - (rig.intensity * 0.8 if rig.precip > 0 else 0.0)
	var s: float = shaft_strength * gap * low * rain * (1.0 - day.night) * (1.0 - rig.dim * 0.6) * 0.45
	var lc: Color = day.light_color
	for m in _shaft_mats:
		m.set_shader_parameter("strength", s)
		m.set_shader_parameter("color", lc.lerp(Color(1.0, 0.85, 0.5), 0.3))
