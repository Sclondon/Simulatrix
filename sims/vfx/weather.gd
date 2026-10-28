extends "res://sims/vfx/weather_lab.gd"
## Cloud Lab: GameCommon weather's clouds over the editor grid. Every cloud setting the rig has:
## the type (cumulus heaps, a stratus deck, a thunderhead with its anvil, cirrus streaks, an
## altocumulus mackerel sky), cover, base, thickness, puff size, density, softness, dark bellies,
## the silver lining, tint, the sky's own cloud layer, shadows on the grid, layout seed; with the
## time of day, the Lab or Painted sky, the painted-woodland kit's sun shafts and the wind. Look up
## from the grid, orbit it, or see the clouds from above. Rain, snow and lightning have their own labs.

const VIEWS := ["Look up", "Orbit", "Above"]
const TINTS := ["White", "Peach", "Lilac", "Steel", "Rose"]
const TINT_COLORS := [Color.WHITE, Color(1.0, 0.9, 0.8), Color(0.92, 0.88, 1.0), Color(0.86, 0.92, 1.0), Color(1.0, 0.86, 0.9)]
const PRESETS := ["Fair day", "Afternoon heaps", "Overcast", "Thunderhead", "Mackerel sky", "Mares' tails", "Golden hour", "Night"]

var view := 0
var tint := 0
var preset := -1
var sky_style := 0 # 0 the rig's sky (moon, stars, its cloud layer), 1 the painted woodland's
var shafts_on := true
var shaft_strength := 0.6

var _painted_sky := ShaderMaterial.new()
var _shafts := Node3D.new()
var _shaft_mats: Array[ShaderMaterial] = []
var _shaft_sun := Vector3.ZERO


func help() -> String:
	return ("Clouds from GameCommon's weather, over the editor grid. Pick a type and shape it. Cumulus are "
		+ "fair-weather heaps with flat bases, lit tops and dark bellies; stratus is a grey deck that dims the day; "
		+ "a storm is one towering cumulonimbus with a spreading anvil; cirrus are high ice streaks in the sky layer; "
		+ "altocumulus is a mackerel sky of small puffs in rows.\n\n"
		+ "Cover, base and thickness lay them out; puff size makes fewer big lumps or many small ones; New layout "
		+ "deals them again. Density is how solid they are (thin cloud dims the day less), softness how wispy the "
		+ "edges, bellies how dark the undersides, the silver lining how thin edges glow toward the sun. The sky "
		+ "layer is the flat cloud painted in the sky behind the puffs; shadows drift over the grid.\n\n"
		+ "Sun shafts slant down where the sun breaks through: most with broken cloud and a low sun. The Painted "
		+ "sky is the painted woodland's (no moon or stars).\n\n"
		+ "Look up: stand on the grid and drag to look round, pinch or wheel to zoom. Orbit: turn round the grid. "
		+ "Above: see the clouds from over them.\n\n"
		+ "Rain, snow and lightning are in their own labs. Export saves these clouds as a scene (needs godot/weather).")


func hint() -> String:
	return "Drag to look round the sky. Try Preset > Thunderhead, or View > Above."


func export_info() -> Dictionary:
	return {name = "Clouds", lab = "Cloud Lab", use = ""}


func setup() -> void:
	rig.hour = 15.5
	rig.cloud_type = WeatherRig.Clouds.CUMULUS
	rig.cover = 0.6
	rig.base = 1000.0
	rig.thickness = 1.3
	rig.puff_size = 1.15
	# the thunderhead stands where the views look
	rig.storm_at = Vector3(-6000, 0, -5300)
	rig.wind = 6.0
	_painted_sky.shader = Woodland.SKY
	world.add_child(_shafts)
	_set_view(0)


func controls() -> Array:
	var c: Array = [
		{type = "choice", label = "View", options = VIEWS, value = view, on = func(i: int) -> void: _set_view(i)},
		{type = "section", label = "Clouds"},
		{type = "slider", label = "Cover", min = 0.0, max = 1.0, step = 0.05, value = rig.cover, fmt = "%.2f",
			on = func(v: float) -> void: rig.cover = v},
		{type = "choice", label = "Type", options = TYPES, value = rig.cloud_type,
			on = func(i: int) -> void: rig.cloud_type = i},
		{type = "slider", label = "Base", min = 300.0, max = 4000.0, step = 50.0, value = rig.base, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void: rig.base = v},
		{type = "slider", label = "Thickness", min = 0.3, max = 2.0, step = 0.05, value = rig.thickness, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.thickness = v},
		{type = "slider", label = "Puff size", min = 0.3, max = 2.5, step = 0.05, value = rig.puff_size, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.puff_size = v},
		{type = "slider", label = "Speed", min = 0.0, max = 4.0, step = 0.1, value = rig.cloud_speed, fmt = "%.1f", unit = "×",
			on = func(v: float) -> void: rig.cloud_speed = v},
		{type = "button", label = "New layout", on = func() -> void: rig.cloud_seed += 1},
		{type = "section", label = "Presets"},
		{type = "choice", label = "Preset", options = PRESETS, value = preset, on = func(i: int) -> void: _preset(i)},
		{type = "section", label = "Look"},
		{type = "slider", label = "Density", min = 0.1, max = 1.0, step = 0.05, value = rig.density, fmt = "%.2f",
			on = func(v: float) -> void: rig.density = v},
		{type = "slider", label = "Softness", min = 0.2, max = 3.0, step = 0.05, value = rig.softness, fmt = "%.2f",
			on = func(v: float) -> void: rig.softness = v},
		{type = "slider", label = "Bellies", min = 0.0, max = 2.0, step = 0.05, value = rig.belly, fmt = "%.2f",
			on = func(v: float) -> void: rig.belly = v},
		{type = "slider", label = "Lining", min = 0.0, max = 3.0, step = 0.05, value = rig.lining, fmt = "%.2f",
			on = func(v: float) -> void: rig.lining = v},
		{type = "slider", label = "Warmth", min = 0.0, max = 1.0, step = 0.05, value = rig.warmth, fmt = "%.2f",
			on = func(v: float) -> void: rig.warmth = v},
		{type = "choice", label = "Tint", options = TINTS, value = tint, on = func(i: int) -> void:
			tint = i
			rig.cloud_tint = TINT_COLORS[i]},
		{type = "slider", label = "Sky layer", min = 0.0, max = 2.0, step = 0.05, value = rig.sky_layer, fmt = "%.2f",
			on = func(v: float) -> void: rig.sky_layer = v},
		{type = "slider", label = "Shadows", min = 0.0, max = 2.0, step = 0.05, value = rig.cloud_shadows, fmt = "%.2f",
			on = func(v: float) -> void: rig.cloud_shadows = v},
		{type = "section", label = "Time & sky"},
	]
	c.append_array(time_controls())
	c.append_array([
		{type = "choice", label = "Sky", options = ["Lab", "Painted"], value = sky_style, on = func(i: int) -> void:
			sky_style = i
			environment.sky.sky_material = _painted_sky if i == 1 else rig.sky_material},
		{type = "toggle", label = "Sun shafts", value = shafts_on, on = func(v: bool) -> void:
			shafts_on = v
			_shafts.visible = v},
		{type = "slider", label = "Shafts", min = 0.0, max = 1.5, step = 0.05, value = shaft_strength, fmt = "%.2f",
			on = func(v: float) -> void: shaft_strength = v},
		{type = "section", label = "Wind & air"},
	])
	c.append_array(wind_controls())
	c.append({type = "slider", label = "Fog", min = 0.0, max = 1.0, step = 0.05, value = rig.fog, fmt = "%.2f",
		on = func(v: float) -> void: rig.fog = v})
	c.append({type = "section", label = "View"})
	c.append({type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = rig.quality,
		on = func(i: int) -> void: rig.quality = i})
	c.append_array(export_controls())
	return c


func status() -> String:
	var s := "%s %d%% · base %d m · %05.2f h · dim %d%%" % [TYPES[rig.cloud_type], roundi(rig.cover * 100.0),
		roundi(rig.base), rig.hour, roundi(rig.dim * 100.0)]
	if rig.cloud_type == WeatherRig.Clouds.STORM:
		s += " · rain and lightning: their own labs"
	return s + ms()


# --- views and presets -----------------------------------------------------------

func _set_view(i: int) -> void:
	view = i
	# All three face away from the afternoon sun, so the clouds are lit side-on
	match i:
		0: # stand on the grid and look up
			yaw = -2.3
			pitch = 0.42
			distance = 66.0
			min_distance = 20.0
			max_distance = 95.0
			camera.near = 0.1
		1: # orbit the grid, the sky behind
			focus = Vector3(0, 2.0, 0)
			yaw = 0.85
			pitch = -0.1
			distance = 24.0
			min_distance = 4.0
			max_distance = 120.0
			min_pitch = -1.45
			max_pitch = 0.05
			camera.near = 0.1
		2: # over the clouds
			focus = Vector3(0, rig.base, 0)
			yaw = 0.85
			pitch = -0.55
			distance = 5500.0
			min_distance = 1500.0
			max_distance = 16000.0
			min_pitch = -1.45
			max_pitch = -0.05
			camera.near = 5.0
	camera.fov = 55.0
	# from above: no ground fog (it would whiten the land 4 km down), the floor fading out before its edge
	floor_mat.set_shader_parameter("far_fade", 13000.0 if i == 2 else 6000.0)
	environment.fog_enabled = i != 2
	if is_inside_tree():
		_place_camera()


## Look up: the camera stands on the grid and turns (pitch is how far up it looks; zoom is the
## field of view). The other views orbit as usual.
func _place_camera() -> void:
	if view != 0:
		if view == 2:
			focus.y = rig.base
		super()
		return
	pitch = clampf(pitch, -0.15, 1.45)
	distance = clampf(distance, min_distance, max_distance)
	camera.fov = distance
	var look := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var eye := Vector3(0, 1.7, 0)
	camera.look_at_from_position(eye, eye + look, Vector3.UP)


func _preset(i: int) -> void:
	if i < 0:
		return
	preset = i
	var r := rig
	r.density = 1.0; r.softness = 1.0; r.belly = 1.0; r.lining = 1.0; r.sky_layer = 1.0; r.puff_size = 1.0
	r.warmth = 0.0; r.thickness = 1.0; r.fog = 0.08; r.cloud_speed = 1.0
	tint = 0
	match i:
		0: # Fair day
			r.cloud_type = WeatherRig.Clouds.CUMULUS; r.cover = 0.35; r.base = 1300.0; r.hour = 12.5; r.wind = 4.0
		1: # Afternoon heaps: towering fair-weather cumulus
			r.cloud_type = WeatherRig.Clouds.CUMULUS; r.cover = 0.75; r.base = 1100.0; r.thickness = 1.7; r.hour = 15.5
			r.puff_size = 1.2; r.wind = 6.0
		2: # Overcast
			r.cloud_type = WeatherRig.Clouds.STRATUS; r.cover = 0.85; r.base = 700.0; r.hour = 13.0; r.fog = 0.25
		3: # Thunderhead
			r.cloud_type = WeatherRig.Clouds.STORM; r.cover = 0.6; r.base = 1100.0; r.thickness = 1.2; r.hour = 16.0
			r.belly = 0.8; r.cover = 0.45; r.wind = 9.0
		4: # Mackerel sky
			r.cloud_type = WeatherRig.Clouds.ALTOCUMULUS; r.cover = 0.6; r.base = 3200.0; r.hour = 16.5
		5: # Mares' tails: cirrus
			r.cloud_type = WeatherRig.Clouds.CIRRUS; r.cover = 0.6; r.hour = 11.0; r.wind = 14.0; r.sky_layer = 1.4
		6: # Golden hour
			r.cloud_type = WeatherRig.Clouds.CUMULUS; r.cover = 0.55; r.base = 1500.0; r.hour = 17.7; r.warmth = 0.6
			r.lining = 1.8; tint = 1
		7: # Night
			r.cloud_type = WeatherRig.Clouds.CUMULUS; r.cover = 0.4; r.base = 1400.0; r.hour = 22.5
	r.day_speed = 0.0
	r.cloud_tint = TINT_COLORS[tint]
	if view == 2:
		_place_camera()
	controls_changed.emit()


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
	if view == 2 and not is_equal_approx(focus.y, rig.base):
		_place_camera()
	_update_shafts(day)


# --- sun shafts (the painted-woodland kit's) ------------------------------------

## Crepuscular rays: the kit's shaft cards slanting down from the sun round the grid, re-aimed as the
## sun moves. They show where the sun breaks through: most with broken cloud and a low sun, none under
## a full deck or at night.
func _update_shafts(day: Dictionary) -> void:
	if not shafts_on:
		return
	var sun_dir: Vector3 = day.sun_dir
	if sun_dir.y < 0.03 or view == 2:
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
			var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(150.0, 600.0)
			Woodland.add_sun_shaft(_shafts, p, sun_dir, Color.WHITE, 900.0, rng.randf_range(150.0, 300.0), i * 2.3, 0.2)
		for g in _shafts.get_children():
			var m := (g as MeshInstance3D).material_override as ShaderMaterial
			if m and not _shaft_mats.has(m):
				_shaft_mats.append(m)
	# breaks in the cloud: none in clear sky (nothing to cast them) or under a full deck
	var cover := rig.cover
	var gap: float = clampf(0.25 + 3.0 * cover * (1.0 - cover), 0.0, 1.0) * [1.0, 0.35, 0.6, 0.5, 0.8][rig.cloud_type]
	var low := 1.0 + smoothstep(0.5, 0.08, sun_dir.y)
	var s: float = shaft_strength * gap * low * rig.density * (1.0 - day.night) * (1.0 - rig.dim * 0.6) * 0.45
	var lc: Color = day.light_color
	for m in _shaft_mats:
		m.set_shader_parameter("strength", s)
		m.set_shader_parameter("color", lc.lerp(Color(1.0, 0.85, 0.5), 0.3))
