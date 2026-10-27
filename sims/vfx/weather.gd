extends Sim3D
## Weather Lab: clouds you can shape (fair-weather cumulus, a stratus deck, a thunderstorm with
## its anvil, high cirrus), rain with splashes and puddles, settling snow, hail, branching
## lightning with its flash and thunder delay, fog, wind and the time of day, over a meadow of
## GameCommon pines and broadleaf trees with mountains round it.
##
## Clouds are heaps of soft puffs (weather_cloud.gdshader, one MultiMesh, sorted back to front),
## over a cloud layer in the sky shader (weather_sky.gdshader). Ideas from Hemlock's Tower's
## weather (puff clouds, lightning) and Mariner's; the time of day is weather_daylight.gd. The
## painted-woodland kit gives the sun shafts (crepuscular rays through the gaps in the cloud) and the
## Painted sky style.

const Daylight := preload("res://sims/vfx/weather_daylight.gd")
const CLOUD := preload("res://sims/vfx/weather_cloud.gdshader")
const GROUND := preload("res://sims/vfx/weather_ground.gdshader")
const TREE := preload("res://sims/vfx/weather_tree.gdshader")
const PRECIP := preload("res://sims/vfx/weather_precip.gdshader")
const TYPES := ["Cumulus", "Stratus", "Storm", "Cirrus"]
const KINDS := ["None", "Rain", "Snow", "Hail"]
const QUALITY := [
	{puffs = 150, rain = 1500, snow = 1500},
	{puffs = 260, rain = 3000, snow = 3000},
	{puffs = 380, rain = 5000, snow = 5000},
]
const FIELD := 7000.0        # clouds wrap round a square this far each way
const SOUND := 343.0         # m/s, for the thunder

var hour := 16.5
var cycle := false
var cloud_type := 0
var cover := 0.5
var base := 1300.0
var thickness := 1.0
var cloud_speed := 1.0
var warmth := 0.0
var precip := 0
var intensity := 0.7
var settle := true
var auto_storm := false
var strike_rate := 0.5
var wind := 5.0
var wind_from := 250.0
var fog := 0.08
var quality := 1
var sky_style := 0 # 0 the lab's sky (moon, stars, its cloud layer), 1 the painted woodland's
var shafts_on := true
var shaft_strength := 0.6

var wet := 0.0
var snow_depth := 0.0
var bolts := 0

var _sky_mat: ShaderMaterial
var _painted_sky := ShaderMaterial.new()
var _shafts := Node3D.new()
var _shaft_mats: Array[ShaderMaterial] = []
var _shaft_sun := Vector3.ZERO
var _cloud_mat: ShaderMaterial
var _cloud_mm: MultiMesh
var _ground_mats: Array[ShaderMaterial] = []
var _tree_mats: Array[ShaderMaterial] = []
var _fall: MultiMesh
var _splash: MultiMesh
var _fall_mat: ShaderMaterial
var _splash_mat: ShaderMaterial
var _bolt_mesh := ImmediateMesh.new()
var _bolt_mat := StandardMaterial3D.new()
var _bolt_light := OmniLight3D.new()
var _rng := RandomNumberGenerator.new()

# Cloud puffs: which cluster, offset from it, size, and the shader's per-puff data
var _clusters := PackedVector3Array()
var _p_cluster := PackedInt32Array()
var _p_off := PackedVector3Array()
var _p_size := PackedFloat32Array()
var _p_custom := PackedColorArray()
var _p_flat := PackedByteArray() # 1: cut flat at the cloud base (cumulus)
var _order := PackedInt32Array()
var _sort_in := 0
var _drift := Vector2.ZERO
var _sky_drift := Vector2.ZERO

# The bolt: polylines with a width and brightness each, how long ago it struck, and where
var _bolt_paths: Array = []
var _bolt_t := 99.0
var _bolt_at := Vector3.ZERO
var _thunder := -1.0
var _thunder_km := 0.0
var _storm_timer := 3.0
var _flash := 0.0
var _dim := 0.0


func help() -> String:
	return ("A weather lab. Pick a cloud type and shape it: cover, base height, thickness, speed. Cumulus are "
		+ "fair-weather heaps lit from the sun with dark bellies; stratus is a grey deck that dims the day; a storm "
		+ "is a towering cumulonimbus with a spreading anvil; cirrus are high ice streaks.\n\n"
		+ "Rain wets the ground (it darkens, puddles form in the low spots and ring with drops), snow settles "
		+ "on everything that faces up, hail bounces. Lightning branches down from the cloud base; count the "
		+ "seconds to the thunder (sound travels 343 m/s) to know how far it struck.\n\n"
		+ "Sun shafts (crepuscular rays) slant down from the sun where it breaks through: strongest with broken "
		+ "cloud and a low sun, gone under a full deck or at night. The Painted sky is the painted woodland's: gold "
		+ "low by the sun, cooling overhead, with long streaks (no moon, stars or flash in it).\n\n"
		+ "Drag to orbit, pinch or wheel to zoom. In Poke mode, tap the ground to strike it.")


func hint() -> String:
	return "Drag to orbit. Try Clouds > Storm, Rain, and Auto storm."


func pokeable() -> bool:
	return true


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Time"},
		{type = "slider", label = "Hour", min = 0.0, max = 24.0, step = 0.25, value = hour, fmt = "%05.2f", unit = "h",
			on = func(v: float) -> void: hour = v},
		{type = "toggle", label = "Day cycle", value = cycle, on = func(v: bool) -> void: cycle = v},
		{type = "section", label = "Light"},
		{type = "choice", label = "Sky", options = ["Lab", "Painted"], value = sky_style, on = func(i: int) -> void:
			sky_style = i
			environment.sky.sky_material = _painted_sky if i == 1 else _sky_mat},
		{type = "toggle", label = "Sun shafts", value = shafts_on, on = func(v: bool) -> void:
			shafts_on = v
			_shafts.visible = v},
		{type = "slider", label = "Shafts", min = 0.0, max = 1.5, step = 0.05, value = shaft_strength, fmt = "%.2f",
			on = func(v: float) -> void: shaft_strength = v},
		{type = "section", label = "Clouds"},
		{type = "choice", label = "Type", options = TYPES, value = cloud_type,
			on = func(i: int) -> void: cloud_type = i; _make_clouds()},
		{type = "slider", label = "Cover", min = 0.0, max = 1.0, step = 0.05, value = cover, fmt = "%.2f",
			on = func(v: float) -> void: cover = v; _make_clouds()},
		{type = "slider", label = "Base", min = 300.0, max = 3000.0, step = 50.0, value = base, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void: base = v; _make_clouds()},
		{type = "slider", label = "Thickness", min = 0.3, max = 2.0, step = 0.05, value = thickness, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: thickness = v; _make_clouds()},
		{type = "slider", label = "Speed", min = 0.0, max = 4.0, step = 0.1, value = cloud_speed, fmt = "%.1f", unit = "×",
			on = func(v: float) -> void: cloud_speed = v},
		{type = "slider", label = "Warmth", min = 0.0, max = 1.0, step = 0.05, value = warmth, fmt = "%.2f",
			on = func(v: float) -> void: warmth = v},
		{type = "section", label = "Precipitation"},
		{type = "choice", label = "Kind", options = KINDS, value = precip,
			on = func(i: int) -> void: precip = i; _setup_precip()},
		{type = "slider", label = "Intensity", min = 0.05, max = 1.0, step = 0.05, value = intensity, fmt = "%.2f",
			on = func(v: float) -> void: intensity = v; _setup_precip()},
		{type = "toggle", label = "Settle", value = settle, on = func(v: bool) -> void: settle = v},
		{type = "button", label = "Dry ground", on = func() -> void: wet = 0.0; snow_depth = 0.0},
		{type = "section", label = "Lightning"},
		{type = "button", label = "Strike", on = func() -> void: strike()},
		{type = "toggle", label = "Auto storm", value = auto_storm, on = func(v: bool) -> void: auto_storm = v; _storm_timer = 0.5},
		{type = "slider", label = "Rate", min = 0.0, max = 1.0, step = 0.05, value = strike_rate, fmt = "%.2f",
			on = func(v: float) -> void: strike_rate = v},
		{type = "section", label = "Wind & air"},
		{type = "slider", label = "Wind", min = 0.0, max = 25.0, step = 0.5, value = wind, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: wind = v; _setup_precip()},
		{type = "slider", label = "From", min = 0.0, max = 360.0, step = 5.0, value = wind_from, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: wind_from = v; _setup_precip()},
		{type = "slider", label = "Fog", min = 0.0, max = 1.0, step = 0.05, value = fog, fmt = "%.2f",
			on = func(v: float) -> void: fog = v},
		{type = "section", label = "View"},
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = quality,
			on = func(i: int) -> void: quality = i; _make_clouds(); _setup_precip()},
	])
	return c


func status() -> String:
	var s := "%s %d%% · base %d m" % [TYPES[cloud_type], roundi(cover * 100.0), roundi(base)]
	if precip > 0:
		s += " · %s %d%%" % [KINDS[precip].to_lower(), roundi(intensity * 100.0)]
	s += " · wet %d%% · snow %.0f cm · %d bolts" % [roundi(wet * 100.0), snow_depth * 25.0, bolts]
	if _thunder > 0.0:
		s += " · thunder in %.1f s (%.1f km)" % [_thunder, _thunder_km]
	return s + " · %.1f ms" % frame_ms()


## Re-applies every setting (for scripts that set the vars directly).
func refresh() -> void:
	_make_clouds()
	_setup_precip()


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
	_sky_mat = Daylight.make_sky_material()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	_painted_sky.shader = Woodland.SKY
	world.add_child(_shafts)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_sky_affect = 0.15
	sun.directional_shadow_max_distance = 120.0
	_build_ground()
	_build_trees()
	_build_clouds()
	_build_precip()
	_build_bolt()
	_make_clouds()
	_setup_precip()


## Height of the land at (x, z): must match terrain() in weather_ground.gdshader.
static func terrain(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var bumps := sin(x * 0.05) * cos(z * 0.043) * 0.6 + sin(x * 0.13 + 1.0) * sin(z * 0.11) * 0.2
	var hills := sin(x * 0.004) * cos(z * 0.0035) * 28.0 + sin(x * 0.011 + 1.3) * sin(z * 0.009 + 0.7) * 9.0
	var a := atan2(z, x)
	var ridge := 0.6 + 0.4 * sin(a * 5.0 + 1.0) * sin(a * 3.0 + 2.0) + 0.15 * sin(a * 17.0) + 0.08 * sin(x * 0.003 + z * 0.002)
	var mountains := smoothstep(1800.0, 4800.0, r) * 900.0 * ridge
	return bumps + (hills + 6.0) * smoothstep(160.0, 700.0, r) + mountains


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
		_ground_mats.append(mat)


func _tree_mat(uv2: bool, height: float, tint := Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TREE
	m.set_shader_parameter("use_uv2", 1.0 if uv2 else 0.0)
	m.set_shader_parameter("tree_height", height)
	m.set_shader_parameter("tint", tint)
	_tree_mats.append(m)
	return m


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
	pine.material = _tree_mat(false, 11.0)
	PineTree.forest(world, pines, pine, 4, Vector2(0.7, 1.3), 64.0, 110.0)
	var oak := LeafyTree.oak()
	oak.material = _tree_mat(true, oak.height)
	LeafyTree.forest(world, broad.slice(0, broad.size() / 2), oak, 3, Vector2(0.8, 1.3), 64.0, 110.0)
	var aspen := LeafyTree.aspen()
	aspen.material = _tree_mat(true, aspen.height)
	LeafyTree.forest(world, broad.slice(broad.size() / 2), aspen, 3, Vector2(0.8, 1.3), 64.0, 110.0)
	# Boulders, for snow to settle on
	var rock_mat := _tree_mat(false, 1.0, Color(0.5, 0.49, 0.47))
	rock_mat.set_shader_parameter("wind", 0.0)
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


func _build_clouds() -> void:
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = CLOUD
	_cloud_mat.set_shader_parameter("noise_tex", Daylight.cloud_noise())
	_cloud_mat.set_shader_parameter("fade_far", 14000.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _cloud_mat
	_cloud_mm = MultiMesh.new()
	_cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	_cloud_mm.use_custom_data = true
	_cloud_mm.mesh = quad
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _cloud_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 20000.0
	world.add_child(mmi)


func _puff(cluster: int, off: Vector3, size: float, up: float, dark: float, squash := 1.0, flat := false) -> void:
	_p_flat.append(1 if flat else 0)
	_p_cluster.append(cluster)
	_p_off.append(off)
	_p_size.append(size)
	_p_custom.append(Color(clampf(up, 0.0, 1.0), dark, _rng.randf(), squash))


## A heap of puffs: a flat base and a domed top, narrower as it rises.
func _heap(cluster: int, w: float, h: float, count: int, dark: float) -> void:
	for j in count:
		var t := pow(_rng.randf(), 1.3) if j > 2 else 0.0
		var rr := w * 0.5 * (1.0 - t * 0.55)
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * rr
		var size := _rng.randf_range(0.26, 0.4) * w * (1.0 - 0.3 * t)
		var y := t * h + size * 0.35
		_puff(cluster, Vector3(cos(a) * d, y, sin(a) * d), size, t, dark, 1.0 if t > 0.25 else 0.8, true)


## Lays the clouds out again for the type, cover, base and thickness.
func _make_clouds() -> void:
	_rng.seed = 100 + cloud_type
	_clusters.clear()
	_p_cluster.clear(); _p_off.clear(); _p_size.clear(); _p_custom.clear(); _p_flat.clear()
	var cap: int = QUALITY[quality].puffs
	match cloud_type:
		0: # Cumulus: separate heaps, more and bigger with cover
			var n := roundi(cover * 64.0)
			for i in n:
				var c := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-FIELD, FIELD), base, _rng.randf_range(-FIELD, FIELD)))
				var w := _rng.randf_range(550.0, 1100.0) * (0.7 + 0.6 * cover)
				_heap(c, w, w * 0.5 * thickness, clampi(int(cap / maxf(n, 1)), 5, 12), 0.15 + 0.35 * cover)
		1: # Stratus: a low, flat deck of wide puffs
			var n := roundi(cover * 34.0) + 6
			for i in n:
				var c := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-FIELD, FIELD), base, _rng.randf_range(-FIELD, FIELD)))
				for j in clampi(cap / n, 3, 8):
					var a := _rng.randf() * TAU
					var d := _rng.randf() * 1400.0
					_puff(c, Vector3(cos(a) * d, _rng.randf_range(0.0, 120.0) * thickness, sin(a) * d),
						_rng.randf_range(650.0, 1100.0), _rng.randf_range(0.3, 0.8), 0.35, 0.45)
		2: # Storm: one cumulonimbus, a tower to an anvil, ragged scud under it, heaps round it
			var c := 0
			_clusters.append(Vector3(-5000.0, base, -9200.0))
			var top := 4800.0 * thickness
			var tower := int(cap * 0.38)
			for j in tower:
				var t := float(j) / tower
				var rr := lerpf(1300.0, 750.0, sin(t * PI * 0.5)) * (0.8 + 0.2 * cover)
				var a := _rng.randf() * TAU
				var d := sqrt(_rng.randf()) * rr
				_puff(c, Vector3(cos(a) * d, t * top + 300.0, sin(a) * d), _rng.randf_range(650.0, 950.0), t * 0.9, 0.85, 1.0, true)
			var anvil := int(cap * 0.3)
			for j in anvil:
				var a := _rng.randf() * TAU
				var d := sqrt(_rng.randf()) * 4200.0 * (0.7 + 0.3 * cover)
				# The anvil spreads downwind
				var off := Vector3(cos(a) * d, top + _rng.randf_range(-250.0, 350.0), sin(a) * d * 0.7) + Vector3(-1200.0, 0, 600.0)
				_puff(c, off, _rng.randf_range(900.0, 1500.0), 0.85 + _rng.randf() * 0.15, 0.2, 0.42)
			for j in int(cap * 0.08):
				var a := _rng.randf() * TAU
				var d := _rng.randf_range(600.0, 2600.0)
				_puff(c, Vector3(cos(a) * d, -_rng.randf_range(80.0, 300.0), sin(a) * d), _rng.randf_range(250.0, 500.0), 0.0, 1.0, 0.6)
			var left := cap - _p_off.size()
			var heaps := roundi(cover * 14.0)
			for i in heaps:
				var k := _clusters.size()
				_clusters.append(Vector3(_rng.randf_range(-FIELD, FIELD), base, _rng.randf_range(-FIELD, FIELD)))
				var w := _rng.randf_range(500.0, 1000.0)
				_heap(k, w, w * 0.6 * thickness, clampi(left / maxi(heaps, 1), 4, 10), 0.6)
		_: # Cirrus: only in the sky layer
			pass
	var n := mini(_p_off.size(), cap)
	_cloud_mm.instance_count = n
	_order.resize(n)
	for i in n:
		_order[i] = i
	_sort_in = 0


func _build_precip() -> void:
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = PRECIP
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = PRECIP
	_fall = _drops(_fall_mat)
	_splash = _drops(_splash_mat)


## A MultiMesh of quads that the precip shader places itself (from INSTANCE_ID, round the camera).
func _drops(mat: ShaderMaterial) -> MultiMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.custom_aabb = AABB(Vector3.ONE * -50000.0, Vector3.ONE * 100000.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mmi)
	return mm


## Sets the rain, snow or hail up for the kind, intensity and wind.
func _setup_precip() -> void:
	var w := _wind_vec() * wind
	var q: Dictionary = QUALITY[quality]
	_fall.instance_count = 0
	_splash.instance_count = 0
	if precip == 0:
		return
	var fall: Vector3
	var count := 0
	match precip:
		1: # Rain: ~9 m/s streaks, slanted by the wind
			fall = Vector3(w.x * 0.7, -9.5, w.y * 0.7)
			count = int(q.rain * intensity)
			_fall_mat.set_shader_parameter("kind", 0)
			_fall_mat.set_shader_parameter("width", 0.012)
			_fall_mat.set_shader_parameter("streak", 0.8)
			_fall_mat.set_shader_parameter("box", Vector3(40, 40, 40))
			_fall_mat.set_shader_parameter("tint", Color(0.8, 0.84, 0.92, 0.6))
		2: # Snow: slow, drifting, tumbling
			fall = Vector3(w.x * 0.45, -1.1, w.y * 0.45)
			count = int(q.snow * intensity)
			_fall_mat.set_shader_parameter("kind", 1)
			_fall_mat.set_shader_parameter("width", 0.06)
			_fall_mat.set_shader_parameter("box", Vector3(26, 26, 26))
			_fall_mat.set_shader_parameter("tint", Color(1, 1, 1, 0.95))
		3: # Hail: fast pellets
			fall = Vector3(w.x * 0.4, -16.0, w.y * 0.4)
			count = int(q.rain * intensity * 0.35)
			_fall_mat.set_shader_parameter("kind", 2)
			_fall_mat.set_shader_parameter("width", 0.03)
			_fall_mat.set_shader_parameter("box", Vector3(36, 36, 36))
			_fall_mat.set_shader_parameter("tint", Color(0.95, 0.97, 1.0, 0.95))
	_fall_mat.set_shader_parameter("fall_dir", fall.normalized())
	_fall_mat.set_shader_parameter("speed", fall.length())
	_fall.instance_count = maxi(count, 30)
	if precip == 1:
		# Crowns where the drops land, and rings in the puddles (the ground's shader)
		_splash_mat.set_shader_parameter("kind", 3)
		_splash_mat.set_shader_parameter("width", 0.12)
		_splash_mat.set_shader_parameter("rate", 3.5)
		_splash_mat.set_shader_parameter("box", Vector3(30, 30, 30))
		_splash_mat.set_shader_parameter("tint", Color(0.82, 0.86, 0.92, 0.75))
		_splash.instance_count = maxi(int(q.rain * intensity * 0.3), 20)
	elif precip == 3:
		# Hailstones bouncing
		_splash_mat.set_shader_parameter("kind", 4)
		_splash_mat.set_shader_parameter("width", 0.03)
		_splash_mat.set_shader_parameter("rate", 1.6)
		_splash_mat.set_shader_parameter("box", Vector3(26, 26, 26))
		_splash_mat.set_shader_parameter("tint", Color(0.95, 0.97, 1.0, 0.95))
		_splash.instance_count = maxi(int(q.rain * intensity * 0.15), 20)


func _build_bolt() -> void:
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.vertex_color_use_as_albedo = true
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_mat.disable_fog = true
	_bolt_mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20000.0
	world.add_child(mi)
	_bolt_light.light_color = Color(0.8, 0.82, 1.0)
	_bolt_light.omni_range = 4000.0
	_bolt_light.omni_attenuation = 0.6
	_bolt_light.light_energy = 0.0
	world.add_child(_bolt_light)


# --- lightning ---------------------------------------------------------------

## Lightning from the cloud base to the ground: at `at`, or somewhere in front of the camera.
func strike(at: Variant = null) -> void:
	var target: Vector3
	if at is Vector3:
		target = at
	else:
		var fwd := -camera.global_basis.z
		var ang := atan2(fwd.x, fwd.z) + _rng.randf_range(-0.6, 0.6)
		var d := _rng.randf_range(450.0, 2600.0)
		var cam := camera.global_position
		target = Vector3(cam.x + sin(ang) * d, 0, cam.z + cos(ang) * d)
	target.y = terrain(target.x, target.z)
	var top := target + Vector3(_rng.randf_range(-400.0, 400.0), 0, _rng.randf_range(-400.0, 400.0))
	top.y = maxf(base, target.y + 300.0)
	_bolt_paths.clear()
	var main := _jag(top, target, 8, 0.16)
	_bolt_paths.append({pts = main, w = 1.0, b = 1.0})
	_branch(main, 0.55, 2, target.y)
	_bolt_at = target
	_bolt_t = 0.0
	bolts += 1
	var dist := camera.global_position.distance_to(target)
	_thunder = dist / SOUND
	_thunder_km = dist / 1000.0
	_bolt_light.position = target + Vector3(0, 200, 0)


func _branch(path: PackedVector3Array, bright: float, depth: int, ground_y: float) -> void:
	if depth <= 0:
		return
	for i in range(3, path.size() - 6):
		if _rng.randf() > 0.07:
			continue
		var start := path[i]
		var drop := (start.y - ground_y) * _rng.randf_range(0.15, 0.45)
		var end := start + Vector3(_rng.randf_range(-0.8, 0.8) * drop, -drop, _rng.randf_range(-0.8, 0.8) * drop)
		var b := _jag(start, end, 6, 0.2)
		_bolt_paths.append({pts = b, w = 0.5 * bright, b = bright})
		_branch(b, bright * 0.55, depth - 1, ground_y)


## A jagged line by midpoint displacement: each pass splits every segment and nudges the middle.
func _jag(a: Vector3, b: Vector3, passes: int, rough: float) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	for p in passes:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var len := p0.distance_to(p1)
			var mid := (p0 + p1) * 0.5 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)) * len * rough
			next.append(p0)
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


## How bright the bolt is `t` seconds after it struck: a few return strokes, then gone.
func _bolt_brightness(t: float) -> float:
	if t < 0.07: return 1.0
	if t < 0.13: return 0.15
	if t < 0.2: return 0.9
	if t < 0.27: return 0.2
	if t < 0.5: return 0.75 * (1.0 - (t - 0.27) / 0.23)
	return 0.0


func _draw_bolt(bright: float) -> void:
	_bolt_mesh.clear_surfaces()
	if bright <= 0.0:
		return
	var cam := camera.global_position
	var dist := cam.distance_to(_bolt_at)
	# Wider when far, so it reads at any distance; a soft glow round a white core
	var core := clampf(dist * 0.0018, 0.6, 6.0)
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _bolt_mat)
	for pass_i in 2:
		var glow := pass_i == 0
		for path in _bolt_paths:
			var pts: PackedVector3Array = path.pts
			var w: float = core * path.w * (7.0 if glow else 1.0)
			var col := Color(0.55, 0.6, 1.0, 0.22 * bright * path.b) if glow else Color(1, 1, 1, bright * path.b)
			_bolt_mesh.surface_set_color(col)
			for i in pts.size() - 1:
				var p0 := pts[i]
				var p1 := pts[i + 1]
				var side := (p1 - p0).cross(cam - p0).normalized() * w
				for v in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
					_bolt_mesh.surface_add_vertex(v)
	_bolt_mesh.surface_end()


# --- running -----------------------------------------------------------------

func _wind_vec() -> Vector2:
	var toward := deg_to_rad(wind_from + 180.0)
	return Vector2(sin(toward), cos(toward))


func _process(delta: float) -> void:
	super(delta)
	if cycle:
		hour = fposmod(hour + delta * 0.2, 24.0)
	var wv := _wind_vec()
	var dt := minf(delta, 0.1)

	# Light: clouds and rain take the brightness out of the day
	var day := Daylight.at(hour)
	var dim_target: float = [cover * 0.25, 0.45 + 0.5 * cover, 0.55 + 0.4 * cover, cover * 0.1][cloud_type]
	if precip > 0:
		dim_target = maxf(dim_target, 0.35 + 0.4 * intensity)
	_dim = lerpf(_dim, clampf(dim_target, 0.0, 0.95), clampf(dt * 2.0, 0.0, 1.0))
	Daylight.apply(day, _sky_mat, environment, sun, _dim)

	# Lightning
	if auto_storm:
		_storm_timer -= dt
		if _storm_timer <= 0.0:
			strike()
			_storm_timer = lerpf(14.0, 1.5, strike_rate) * _rng.randf_range(0.4, 1.4)
	_bolt_t += dt
	var bright := _bolt_brightness(_bolt_t)
	_draw_bolt(bright)
	_flash = maxf(bright, _flash - dt * 4.0)
	var near_flash := _flash * clampf(1.6 - camera.global_position.distance_to(_bolt_at) / 3000.0, 0.25, 1.0)
	_bolt_light.light_energy = _flash * 6.0
	environment.ambient_light_energy = 0.9 + near_flash * 2.5
	if _thunder > 0.0:
		_thunder -= dt

	# Sky layer
	_sky_drift += wv * (0.0008 + wind * 0.00015) * cloud_speed * dt
	var hor: Color = _sky_mat.get_shader_parameter("horizon")
	var zen: Color = _sky_mat.get_shader_parameter("zenith")
	_sky_mat.set_shader_parameter("cloud_offset", _sky_drift)
	_sky_mat.set_shader_parameter("flash", near_flash * 0.35)
	match cloud_type:
		0:
			_sky_mat.set_shader_parameter("cloud_cover", cover * 0.3)
			_sky_mat.set_shader_parameter("cloud_scale", 2.2)
			_sky_mat.set_shader_parameter("cloud_stretch", Vector2(1, 2.5))
		1:
			_sky_mat.set_shader_parameter("cloud_cover", 0.55 + cover * 0.45)
			_sky_mat.set_shader_parameter("cloud_scale", 0.6)
			_sky_mat.set_shader_parameter("cloud_stretch", Vector2(1, 1))
		2:
			_sky_mat.set_shader_parameter("cloud_cover", 0.5 + cover * 0.3)
			_sky_mat.set_shader_parameter("cloud_scale", 0.8)
			_sky_mat.set_shader_parameter("cloud_stretch", Vector2(1, 1))
		3:
			_sky_mat.set_shader_parameter("cloud_cover", cover * 0.85)
			_sky_mat.set_shader_parameter("cloud_scale", 2.6)
			_sky_mat.set_shader_parameter("cloud_stretch", Vector2(1, 5))
	if sky_style == 1:
		_painted_sky.set_shader_parameter("sun_dir", day.sun_dir)
		_painted_sky.set_shader_parameter("zenith", zen)
		_painted_sky.set_shader_parameter("horizon", hor)
		var lc: Color = day.light_color
		_painted_sky.set_shader_parameter("glow", hor.lerp(lc, (1.0 - day.night) * (1.0 - _dim * 0.7)))
	_update_shafts(day)
	var fog_d := 0.00006 + fog * fog * 0.006
	if precip > 0:
		fog_d += intensity * (0.0012 if precip != 2 else 0.003)
	environment.fog_density = fog_d

	# Cloud puffs
	_drift += wv * (2.0 + wind) * 6.0 * cloud_speed * dt
	_cloud_mat.set_shader_parameter("light_dir", day.light_dir)
	_cloud_mat.set_shader_parameter("light_color", day.light_color)
	_cloud_mat.set_shader_parameter("light_energy", day.light_energy * (1.0 - _dim * 0.5) * 0.85 + 0.1)
	_cloud_mat.set_shader_parameter("ambient", environment.ambient_light_color * (0.55 + 0.25 * (1.0 - day.night)))
	_cloud_mat.set_shader_parameter("horizon", hor)
	_cloud_mat.set_shader_parameter("warmth", clampf(warmth + smoothstep(0.35, 0.05, day.sun_dir.y) * (1.0 - day.night) * 0.6, 0.0, 1.0))
	_cloud_mat.set_shader_parameter("flash", _flash)
	_cloud_mat.set_shader_parameter("gloom", _dim if cloud_type != 0 else _dim * 0.5)
	_cloud_mat.set_shader_parameter("flash_pos", Vector3(_bolt_at.x, base + 300.0, _bolt_at.z))
	_place_puffs()

	# What the rain and snow leave behind
	var raining := intensity if precip == 1 else (intensity * 0.4 if precip == 3 else 0.0)
	if settle:
		if raining > 0.0:
			wet = minf(wet + raining * dt * 0.08, 1.0)
		else:
			wet = maxf(wet - dt * (0.004 + 0.012 * (1.0 - day.night) * (1.0 - _dim)), 0.0)
		if precip == 2 or precip == 3:
			snow_depth = minf(snow_depth + intensity * dt * (0.03 if precip == 2 else 0.012), 1.0)
		else:
			snow_depth = maxf(snow_depth - dt * (0.002 + 0.006 * (1.0 - day.night) + raining * 0.02), 0.0)
	else:
		wet = 0.0
		snow_depth = 0.0
	for m in _ground_mats:
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("snow", snow_depth)
		m.set_shader_parameter("raining", raining)
		m.set_shader_parameter("zenith", zen)
		m.set_shader_parameter("horizon", hor)
		m.set_shader_parameter("shadow_amount", cover * (1.0 - _dim) * (1.0 - day.night) * (0.9 if cloud_type == 0 else 0.0))
		m.set_shader_parameter("shadow_cover", cover * 0.6)
		m.set_shader_parameter("shadow_offset", _drift / 8000.0)
	for m in _tree_mats:
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("snow", snow_depth)
		m.set_shader_parameter("wind", wind)
		m.set_shader_parameter("wind_dir", wv)


## Moves every puff with the wind (wrapping round the field), and every few frames sorts them
## back to front from the camera so the soft edges blend the right way.
func _place_puffs() -> void:
	var n := _cloud_mm.instance_count
	if n == 0:
		return
	var cam := camera.global_position
	var centres := PackedVector3Array()
	centres.resize(_clusters.size())
	for c in _clusters.size():
		var k := _clusters[c]
		if cloud_type == 2 and c == 0:
			# The thunderstorm stays where it is, so it can be watched
			centres[c] = k
			continue
		var x := fposmod(k.x + _drift.x - cam.x + FIELD, FIELD * 2.0) - FIELD + cam.x
		var z := fposmod(k.z + _drift.y - cam.z + FIELD, FIELD * 2.0) - FIELD + cam.z
		centres[c] = Vector3(x, k.y, z)
	var pos := PackedVector3Array()
	pos.resize(n)
	for i in n:
		pos[i] = centres[_p_cluster[i]] + _p_off[i]
	_sort_in -= 1
	if _sort_in <= 0:
		_sort_in = 8
		var d := PackedFloat32Array()
		d.resize(n)
		for i in n:
			d[i] = pos[i].distance_squared_to(cam)
		var idx := Array(_order)
		idx.sort_custom(func(a: int, b: int) -> bool: return d[a] > d[b])
		_order = PackedInt32Array(idx)
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	for slot in n:
		var i := _order[slot]
		var p := pos[i]
		var s := _p_size[i]
		var c := _p_custom[i]
		var o := slot * 16
		buf[o] = s; buf[o + 3] = p.x
		# The basis Y column is free (the shader billboards): it carries the flat base height
		buf[o + 5] = centres[_p_cluster[i]].y if _p_flat[i] else -100000.0; buf[o + 7] = p.y
		buf[o + 10] = s; buf[o + 11] = p.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
	_cloud_mm.buffer = buf


func poke_down(pos: Vector2) -> void:
	var r := ray(pos)
	# March the ray to the land
	var p: Vector3 = r.from
	var dir: Vector3 = r.dir
	var step := 2.0
	for i in 400:
		p += dir * step
		if p.y < terrain(p.x, p.z):
			strike(p)
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
	var gap: float = clampf(0.25 + 3.0 * cover * (1.0 - cover), 0.0, 1.0) * [1.0, 0.35, 0.6, 0.5][cloud_type]
	var low := 1.0 + smoothstep(0.5, 0.08, sun_dir.y)
	var rain := 1.0 - (intensity * 0.8 if precip > 0 else 0.0)
	var s: float = shaft_strength * gap * low * rain * (1.0 - day.night) * (1.0 - _dim * 0.6) * 0.45
	var lc: Color = day.light_color
	for m in _shaft_mats:
		m.set_shader_parameter("strength", s)
		m.set_shader_parameter("color", lc.lerp(Color(1.0, 0.85, 0.5), 0.3))
