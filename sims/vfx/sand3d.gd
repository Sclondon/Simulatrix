extends Sim3D
## Sand: GameCommon's sand kit. A SandGround that takes furrows, prints and
## paint from a finger, SandWind over it, SandFall pouring a heap, a lump of
## wet sand (SandBlob), and SandDunes for the lie of the land.

const SANDS := ["Desert", "White", "Red", "Black", "Snow"]
## ground colour, kind painted over all of it (-1: none), spray colour
const SAND_LOOKS := [
	[Sand.COLOUR, -1, Color(0, 0, 0, 0)],
	[Sand.WHITE, Sand.Kind.WHITE, Color(0, 0, 0, 0)],
	[Sand.RED, Sand.Kind.RED, Color(0, 0, 0, 0)],
	[Sand.BLACK, Sand.Kind.BLACK, Color(0.42, 0.42, 0.46, 0.8)],
	[Sand.SNOW, Sand.Kind.SNOW, Color(0.9, 0.93, 1.0, 0.8)],
]
const TERRAINS := ["Flat", "Barchan", "Ridges", "Star"]
const TOOLS := ["Furrow", "Prints", "Paint", "Heap", "Pour"]
const KINDS := ["Coarse", "Damp", "Packed", "Pale", "Dirt", "Stone", "White", "Red", "Black", "Snow"]
const KIND_SWATCH := [Color(0.76, 0.62, 0.42), Sand.WET, Color(0.7, 0.58, 0.42), Color(0.9, 0.82, 0.66), Sand.DIRT,
	Sand.SANDSTONE, Sand.WHITE, Sand.RED, Sand.BLACK, Sand.SNOW]
const HALF := 22.0
const WEB_SUN := 0.3

var land: SandGround
var wind: SandWind
var fall: SandFall
var blob: SandBlob
var marker := Node3D.new() # what the ground's fine mesh and its patch of dents follow
var sand_look := 0
var terrain := 1
var tool := 0
var kind := 7
var brush := 0.3
var weather := SandWind.Weather.BREEZE
var wind_angle := 20.0
var ripples := 0
var _last := Vector3.INF
var _stride := 0.0
var _left := false
var _pour_at := Vector3(5.0, 0.0, 4.0)


func build() -> void:
	set_sky(Color("6f9fd0"), Color("e7dccb"), Color("c9b48f"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.66, 0.78)
	environment.ambient_light_energy = 0.55
	sun.rotation_degrees = Vector3(-30.0, -140.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	sun.directional_shadow_max_distance = 50.0
	# The web's renderer makes a sun that casts shadows much too bright: turn it
	# down there and tell the sand, which lights itself back up (before any sand is made).
	Sand.sun_gain = 1.0
	Sand.sky = Color.BLACK
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		sun.light_energy *= WEB_SUN
		Sand.sun_gain = 1.0 / WEB_SUN
		Sand.sky = environment.ambient_light_color.srgb_to_linear() * environment.ambient_light_energy
	focus = Vector3(0.0, 0.3, 0.0)
	distance = 9.0
	pitch = -0.5
	yaw = 0.9
	min_distance = 1.5
	max_distance = 30.0
	world.add_child(marker)
	_make_ground()


func _exit_tree() -> void:
	# (the sand's statics are shared: leave them as a level would expect)
	Sand.sun_gain = 1.0
	Sand.sky = Color.BLACK


## Makes the ground (again): clears every mark and all the paint.
func _make_ground() -> void:
	for old: Node in [land, wind, fall, blob]:
		if old:
			old.queue_free()
	if land:
		land.remove_from_group(&"sand_grounds")
	var look: Array = SAND_LOOKS[sand_look]
	land = SandGround.new()
	land.half = Vector2(HALF, HALF)
	land.cell = 0.5
	land.colour = look[0]
	land.spray_colour = look[2]
	land.snow = sand_look == 4
	land.dent_cell = 0.05 # 5 cm squares: a patch about 25 m wide on a phone
	land.fill_seconds = Vector2(120.0, 8.0)
	land.apron = 0.0
	land.apron_roll = 0.0
	land.ripples = ripples
	if terrain > 0:
		var dunes := SandDunes.new()
		dunes.wind = Vector2.from_angle(deg_to_rad(wind_angle))
		dunes.floor_roll = 0.0
		match terrain:
			1:
				dunes.add_barchan(Vector2(-9.0, -7.0), 13.0, 2.6)
				dunes.add_barchan(Vector2(10.0, 9.0), 9.0, 1.6)
			2:
				dunes.add_ridge(Vector2(-18.0, -9.0), Vector2(18.0, -6.0), 2.4, 0.08, 2)
				dunes.add_ridge(Vector2(-18.0, 10.0), Vector2(18.0, 12.0), 1.8, 0.08, 1)
			3:
				dunes.add_star(Vector2(-8.0, -8.0), 9.0, 3.2, 3, 1)
		land.height = func(x: float, z: float) -> float:
			# (the middle stays level, to draw on)
			return dunes.height_at(x, z) * smoothstep(3.0, 8.0, Vector2(x, z).length())
	if look[1] >= 0:
		land.paint(look[1], Vector2.ZERO, HALF * 3.0)
	land.focus = marker
	world.add_child(land)
	if terrain == 0:
		land.build()
	if sand_look == 3:
		var m := land.material()
		m.set_shader_parameter(&"sparkle", 3.0)
		m.set_shader_parameter(&"sparkle_aim", 0.965)
		m.set_shader_parameter(&"glint", Color(0.8, 0.88, 1.0))

	wind = SandWind.new()
	wind.direction = Vector2.from_angle(deg_to_rad(wind_angle))
	wind.weather = weather
	var c: Color = look[0]
	wind.colour = c.lerp(Color(0.86, 0.78, 0.62), 0.4)
	wind.streamers = c.lightened(0.15)
	world.add_child(wind)
	var pouring := fall != null and fall.running
	var lump := blob != null
	fall = null
	blob = null
	if pouring:
		_make_fall(_pour_at)
	if lump:
		_toggle_blob(true)


func _make_fall(at: Vector3) -> void:
	if fall:
		fall.queue_free()
	_pour_at = at
	fall = SandFall.new()
	fall.position = Vector3(at.x, land.height_at(at.x, at.z) + 4.0, at.z)
	fall.rate = 0.35
	fall.colour = SAND_LOOKS[sand_look][0].lightened(0.06)
	world.add_child(fall)


func _toggle_blob(on: bool) -> void:
	if blob:
		blob.queue_free()
		blob = null
	if on:
		blob = SandBlob.new()
		blob.position = Vector3(-3.0, land.height_at(-3.0, 3.0), 3.0)
		blob.count = 48
		blob.colour = SAND_LOOKS[sand_look][0].darkened(0.3)
		world.add_child(blob)


func pokeable() -> bool:
	return true


func _ground_point(pos: Vector2) -> Variant:
	# a ray onto the plane at the ground's height under the first guess, twice over (good enough on dunes)
	var at: Variant = ground(pos, 0.0)
	if at == null:
		return null
	for i in 2:
		at = ground(pos, land.height_at(at.x, at.z))
		if at == null:
			return null
	return at


func poke_down(pos: Vector2) -> void:
	_last = Vector3.INF
	_stride = 0.0
	var at: Variant = _ground_point(pos)
	if at == null:
		return
	marker.position = at
	match tool:
		3: land.heap(at, brush * 2.0, 0.06)
		4: _make_fall(at)
	_stroke(at)


func poke_move(pos: Vector2) -> void:
	var at: Variant = _ground_point(pos)
	if at != null:
		marker.position = marker.position.lerp(at, 0.5)
		_stroke(at)


func _stroke(at: Vector3) -> void:
	match tool:
		0:
			land.trail(self, at, brush, 0.05)
		1:
			if _last != Vector3.INF:
				_stride += at.distance_to(_last)
				if _stride > 0.7:
					_stride = 0.0
					_left = not _left
					var way := at - _last
					var yaw_now := atan2(way.x, way.z)
					var side := Vector3(cos(yaw_now), 0.0, -sin(yaw_now)) * (0.12 if _left else -0.12)
					land.footprint(at + side, yaw_now, 0.04, _left)
					land.spray.kick(at, way.normalized() * 2.0, 18, 0.4, Color(0, 0, 0, 0), 1.0, 0.0, Vector3.UP)
		2:
			land.paint(kind, Vector2(at.x, at.z), brush * 4.0, 1.0, brush * 3.0)
	_last = at


func poke_up(_pos: Vector2) -> void:
	_last = Vector3.INF


func _process(delta: float) -> void:
	super(delta)
	if _poking == -1:
		marker.position = marker.position.lerp(focus, minf(1.0, delta * 2.0))


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "choice", label = "Tool", options = TOOLS, value = tool, on = func(i: int) -> void: tool = i},
		{type = "slider", label = "Brush", min = 0.1, max = 0.8, step = 0.05, value = brush, unit = "m", fmt = "%.2f",
			on = func(v: float) -> void: brush = v},
		{type = "choice", label = "Paint kind", options = KINDS, value = kind, colors = KIND_SWATCH,
			on = func(i: int) -> void:
				kind = i
				tool = 2},
		{type = "section", label = "Ground"},
		{type = "choice", label = "Sand", options = SANDS, value = sand_look,
			colors = SAND_LOOKS.map(func(l: Array) -> Color: return l[0]),
			on = func(i: int) -> void:
				sand_look = i
				_make_ground()},
		{type = "choice", label = "Dunes", options = TERRAINS, value = terrain,
			on = func(i: int) -> void:
				terrain = i
				_make_ground()},
		{type = "choice", label = "Ripples", options = ["Soft", "Mixed", "Fine", "None"], value = ripples,
			on = func(i: int) -> void:
				ripples = i
				land.ripples = i},
		{type = "button", label = "Smooth", on = _make_ground},
		{type = "toggle", label = "Wet lump", value = false, on = _toggle_blob},
		{type = "toggle", label = "Pour", value = false, on = func(on: bool) -> void:
			if on:
				_make_fall(_pour_at)
			elif fall:
				fall.running = false},
		{type = "section", label = "Wind"},
		{type = "choice", label = "Weather", options = ["Calm", "Breeze", "Storm"], value = weather,
			on = func(i: int) -> void:
				weather = i
				wind.weather = i},
		{type = "slider", label = "Direction", min = 0.0, max = 360.0, step = 5.0, value = wind_angle, unit = "deg", fmt = "%.0f",
			on = func(v: float) -> void:
				wind_angle = v
				wind.direction = Vector2.from_angle(deg_to_rad(v))},
		{type = "slider", label = "Gusty", min = 0.0, max = 1.0, step = 0.05, value = 0.6, fmt = "%.2f",
			on = func(v: float) -> void: wind.gusty = v},
		{type = "section", label = "Render"},
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = Sand.quality,
			on = func(i: int) -> void:
				Sand.quality = i
				Sand.refresh()
				land.refit()},
	])
	return c


func help() -> String:
	return ("GameCommon's sand kit (scripts/sand*.gd). The ground is a grid of heights drawn by one shader: grain, glints "
		+ "from grains that face the sun, wind ripples and ten kinds of ground. A patch of dents round the finger takes "
		+ "furrows and prints, which the wind slowly fills back in.\n\n"
		+ "Finger on Poke: Furrow drags a trough and throws sand up, Prints walks boot prints, Paint lays the chosen kind, "
		+ "Heap pushes up a mound, Pour moves a stream of sand that builds a heap. Smooth makes the ground again. Storm "
		+ "raises sand in the air and fills marks fast.")


func hint() -> String:
	return "Finger: Poke, then drag across the sand to draw in it."


func status() -> String:
	return "%s %s  %s  q%d  ground %.2f ms  %.1f ms" % [SANDS[sand_look].to_lower(), TERRAINS[terrain].to_lower(),
		TOOLS[tool].to_lower(), Sand.quality, land.cost_usec / 1000.0, frame_ms()]
