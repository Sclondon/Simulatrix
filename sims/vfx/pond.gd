extends Sim3D
## A pond: GameCommon's Water in a dug basin with a sandy shore, rocks and lily
## pads. Pebbles dropped in are watched by the water, which splashes them in;
## a float dragged about leaves rings; a tap can splash on its own.
## Or a stream (Body): the painted-woodland kit's running water down a winding channel
## that falls away downhill (a level box of water cannot run); taps drop leaves that
## the current carries off.

const LOOKS := [
	# name, shallow, deep, sky, depth range, clarity (alpha_shallow), murk
	["Clear", Color(0.27, 0.66, 0.67), Color(0.05, 0.2, 0.3), Color(0.72, 0.82, 0.9), 2.6, 0.3, 0.16],
	["Lake", Color(0.2, 0.48, 0.62), Color(0.03, 0.1, 0.24), Color(0.64, 0.76, 0.9), 1.8, 0.45, 0.22],
	["Tropic", Color(0.36, 0.86, 0.8), Color(0.04, 0.42, 0.56), Color(0.78, 0.9, 0.95), 3.5, 0.18, 0.08],
	["Swamp", Color(0.42, 0.5, 0.24), Color(0.12, 0.16, 0.06), Color(0.62, 0.66, 0.56), 0.9, 0.7, 0.5],
	["Ink", Color(0.16, 0.22, 0.3), Color(0.01, 0.02, 0.05), Color(0.3, 0.34, 0.42), 1.2, 0.6, 0.4],
]
const TOOLS := ["Pebble", "Splash", "Wake"]
const POND := Vector2(12.0, 9.0) # the water box, metres
const GRID := 120

var water: Water
var basin: MeshInstance3D
var look := 0
var tool := 0
var depth := 1.6
var night := false
var pebbles: Array[Dictionary] = [] # {node, speed, sunk}
var pads: Array[Node3D] = []
var duck: Node3D
var _time := 0.0
var _stone_mat: StandardMaterial3D
var body := 0 # 0 the pond, 1 a stream
var stream_speed := 1.6
var stream := Node3D.new()
var stream_mat: ShaderMaterial
var pond_things: Array[Node3D] = [] # hidden while it is a stream
var floaters: Array[Dictionary] = [] # {node, z, side, spin}: leaves carried down the stream
var _leaf_mat: StandardMaterial3D

const STREAM_HALF := 1.35 # the stream's half width, metres
const STREAM_FALL := 0.04 # how far it drops each metre it runs


func build() -> void:
	set_sky(Color("5d8fc4"), Color("cfdce6"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.66, 0.74)
	environment.ambient_light_energy = 0.5
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	environment.fog_enabled = true
	environment.fog_light_color = Color("c4d2de")
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.0
	sun.light_energy = 0.7
	focus = Vector3(0.0, -0.2, 0.0)
	distance = 15.0
	pitch = -0.55
	min_distance = 1.5
	max_distance = 40.0
	min_pitch = -1.5
	max_pitch = 0.3 # low enough to dip under the surface

	_stone_mat = _matte(Color(0.3, 0.29, 0.28))
	basin = MeshInstance3D.new()
	world.add_child(basin)
	_build_basin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r: Array in [[Vector3(-2.6, -0.4, -1.4), 0.75], [Vector3(-3.4, -0.2, 1.6), 0.5], [Vector3(1.2, -0.7, 2.1), 0.42],
			[Vector3(4.9, 0.1, -2.6), 0.9], [Vector3(-5.6, 0.2, 2.9), 0.7], [Vector3(3.2, -0.8, -0.9), 0.35]]:
		var rock := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radial_segments = 7
		m.rings = 4
		rock.mesh = m
		rock.material_override = _stone_mat
		rock.position = r[0]
		rock.scale = Vector3(r[1] * 2.2, r[1] * 1.4, r[1] * 1.8)
		rock.rotation.y = rng.randf() * TAU
		world.add_child(rock)
		pond_things.append(rock)

	water = Water.new()
	water.size = Vector3(POND.x, 4.5, POND.y)
	water.sides = false
	world.add_child(water)
	pond_things.append(water)
	_apply_look()

	# Lily pads riding the swell.
	var pad_mat := _matte(Color(0.27, 0.5, 0.22))
	for i in 7:
		var pad := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		var r := rng.randf_range(0.22, 0.38)
		disc.top_radius = r
		disc.bottom_radius = r
		disc.height = 0.02
		disc.radial_segments = 14
		pad.mesh = disc
		pad.material_override = pad_mat
		var a := rng.randf() * TAU
		pad.position = Vector3(2.2 + cos(a) * rng.randf_range(0.3, 1.6), 0.0, -2.2 + sin(a) * rng.randf_range(0.3, 1.2))
		world.add_child(pad)
		pond_things.append(pad)
		pads.append(pad)

	# A float on a string, for the wake tool.
	duck = Node3D.new()
	var body := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.2
	ball.height = 0.3
	body.mesh = ball
	body.material_override = _matte(Color(0.96, 0.78, 0.18))
	duck.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.22
	head.mesh = hm
	head.material_override = body.material_override
	head.position = Vector3(0.14, 0.16, 0.0)
	duck.add_child(head)
	duck.position = Vector3(-1.0, 0.0, 0.5)
	world.add_child(duck)
	water.watch(duck, 0.3, 0.6)
	pond_things.append(duck)
	world.add_child(stream)
	_leaf_mat = _matte(Color(0.86, 0.5, 0.16))
	_leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## A dug basin: an oval hollow inside the water box, its rim above the water so
## the box's edges are buried, sand down to the water and grass above it.
func _build_basin() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize((GRID + 1) * (GRID + 1))
	for j in GRID + 1:
		for i in GRID + 1:
			var x := _spread(float(i) / GRID) * 90.0
			var z := _spread(float(j) / GRID) * 90.0
			heights[j * (GRID + 1) + i] = _ground_y(x, z)
	# (rows bunched towards the middle: fine round the pond, coarse out to the horizon)
	for j in GRID + 1:
		for i in GRID + 1:
			var x := _spread(float(i) / GRID) * 90.0
			var z := _spread(float(j) / GRID) * 90.0
			var y := heights[j * (GRID + 1) + i]
			var r := _shore_r(x, z)
			var mud := Color(0.42, 0.37, 0.28).lerp(Color(0.24, 0.22, 0.17), clampf(-(y - _fall(z)) / depth, 0.0, 1.0))
			var grass := Color(0.27, 0.38, 0.18).lerp(Color(0.21, 0.31, 0.15), 0.5 + 0.5 * sin(x * 0.7 + sin(z * 0.5) * 2.0) * sin(z * 0.6))
			grass = grass.lerp(Color(0.38, 0.44, 0.3), smoothstep(10.0, 50.0, Vector2(x, z).length()))
			var c := mud.lerp(Color(0.66, 0.58, 0.43), smoothstep(0.82, 0.95, r))
			c = c.lerp(grass, smoothstep(1.2, 1.36, r + 0.05 * sin(x * 2.3) * sin(z * 1.9)))
			st.set_color(c)
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, y, z))
	for j in GRID:
		for i in GRID:
			var a := j * (GRID + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + GRID + 1)
			st.add_index(a + 1)
			st.add_index(a + GRID + 2)
			st.add_index(a + GRID + 1)
	st.generate_normals()
	basin.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	basin.material_override = mat


func _spread(u: float) -> float:
	var t := u * 2.0 - 1.0
	return signf(t) * pow(absf(t), 1.7)


## 0 in the middle of the pond's oval, 1 at its edge (well inside the water box).
func _oval(x: float, z: float) -> float:
	var wob := 1.0 + 0.08 * sin(atan2(z, x) * 3.0 + 1.0) + 0.05 * sin(atan2(z, x) * 5.0)
	return Vector2(x / (POND.x * 0.43), z / (POND.y * 0.43)).length() / wob


func _ground_y(x: float, z: float) -> float:
	if body == 1:
		# a channel cut down a slope: its bed in the middle, banks either side
		var d := absf(x - _stream_x(z)) / STREAM_HALF
		var bed := -minf(depth, 0.7) * (1.0 - smoothstep(0.2, 1.15, d))
		var bank := 0.3 * smoothstep(1.0, 1.5, d) + 0.25 * smoothstep(2.0, 4.0, d)
		return _fall(z) + bed + bank - 0.1 + 0.04 * sin(x * 1.3) * sin(z * 1.1)
	var r := _oval(x, z)
	var bowl := -depth * (1.0 - smoothstep(0.15, 1.0, r))
	var bank := 0.35 * smoothstep(0.95, 1.25, r) + 0.25 * smoothstep(1.4, 2.4, r)
	return bowl + bank - 0.1 + 0.04 * sin(x * 1.3) * sin(z * 1.1)


## The ground falls away downhill (towards +z) when it is a stream; level for the pond.
func _fall(z: float) -> float:
	return -z * STREAM_FALL if body == 1 else 0.0


## Where the stream's middle is, `z` metres along it.
func _stream_x(z: float) -> float:
	return 2.0 * sin(z * 0.12) + 0.8 * sin(z * 0.31 + 1.0)


## 0 in the middle of the water, ~0.95 at the water's edge, more up the bank: the shore's colours go by it.
func _shore_r(x: float, z: float) -> float:
	if body == 1:
		return absf(x - _stream_x(z)) / (STREAM_HALF * 1.05)
	return _oval(x, z)


func _set_body(i: int) -> void:
	body = i
	_build_basin()
	for n in pond_things:
		n.visible = body == 0
	for p: Dictionary in pebbles:
		p.node.queue_free()
	pebbles.clear()
	floaters.clear() # the leaves are the stream's children, freed with it just below
	for child in stream.get_children():
		child.free()
	stream_mat = null
	if body == 1:
		# the kit's stream: a ribbon of running water down the channel, a little below its banks
		var pts: Array[Vector3] = []
		var z := -44.0
		while z <= 44.0:
			pts.append(Vector3(_stream_x(z), _fall(z) - 0.12, z))
			z += 1.2
		var c := sun.light_color
		Woodland.add_stream(stream, pts, STREAM_HALF, -sun.global_basis.z, c)
		stream_mat = (stream.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
		_apply_look()
		focus = Vector3(_stream_x(0.0), -0.3, 0.0)
		_place_camera()


func _matte(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


func _apply_look() -> void:
	var l: Array = LOOKS[look]
	water.shallow = l[1]
	water.deep = l[2]
	water.sky = l[3] if not night else Color(0.12, 0.16, 0.26)
	water.depth_range = l[4]
	water.alpha_shallow = l[5]
	water.murk = l[6]
	if stream_mat:
		var sky: Color = l[3] if not night else Color(0.12, 0.16, 0.26)
		stream_mat.set_shader_parameter("deep", (l[2] as Color).darkened(0.5))
		stream_mat.set_shader_parameter("shallow", (l[1] as Color).lerp(Color(0.42, 0.37, 0.28), 0.5).darkened(0.2))
		stream_mat.set_shader_parameter("sky", sky)
		stream_mat.set_shader_parameter("sky_low", sky.darkened(0.7))
		stream_mat.set_shader_parameter("sun_color", sun.light_color)
		stream_mat.set_shader_parameter("sun_dir", -sun.global_basis.z)
		stream_mat.set_shader_parameter("speed", stream_speed)


func _set_night(on: bool) -> void:
	night = on
	if on:
		set_sky(Color("05070f"), Color("1c2438"))
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.35
		environment.ambient_light_color = Color(0.25, 0.3, 0.45)
		environment.fog_light_color = Color("1c2438")
		environment.ambient_light_energy = 0.5
	else:
		set_sky(Color("5d8fc4"), Color("cfdce6"))
		sun.light_color = Color(1.0, 0.96, 0.9)
		sun.light_energy = 0.7
		environment.ambient_light_color = Color(0.62, 0.66, 0.74)
		environment.fog_light_color = Color("c4d2de")
		environment.ambient_light_energy = 0.5
	_apply_look()


func pokeable() -> bool:
	return true


func poke_down(pos: Vector2) -> void:
	if body == 1:
		# a leaf dropped on the stream, carried off downhill
		var hit: Variant = ground(pos, -0.12)
		if hit != null:
			_drop_leaf(hit.z, clampf((hit.x - _stream_x(hit.z)) / STREAM_HALF, -0.85, 0.85))
		return
	var at: Variant = ground(pos, water.surface_y())
	if at == null:
		return
	match tool:
		0: _drop_pebble(at)
		1: water.splash(at, 0.8)
		2: _move_duck(at)


func _drop_leaf(z: float, side: float) -> void:
	if floaters.size() >= 40:
		floaters[0].node.queue_free()
		floaters.remove_at(0)
	var leaf := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.16, 0.24)
	leaf.mesh = q
	leaf.material_override = _leaf_mat
	stream.add_child(leaf)
	floaters.append({node = leaf, z = z, side = side, spin = randf_range(-1.5, 1.5), turn = randf() * TAU})


func poke_move(pos: Vector2) -> void:
	if body == 1:
		return
	if tool == 2:
		var at: Variant = ground(pos, water.surface_y())
		if at != null:
			_move_duck(at)


func _move_duck(at: Vector3) -> void:
	var to := Vector3(at.x, 0.0, at.z)
	var was := Vector3(duck.position.x, 0.0, duck.position.z)
	if to.distance_to(was) > 0.02:
		duck.rotation.y = atan2(-(to.z - was.z), to.x - was.x)
	duck.position = Vector3(to.x, water.height_at(to) - 0.08, to.z)


func _drop_pebble(at: Vector3) -> void:
	if pebbles.size() >= 24:
		pebbles[0].node.queue_free()
		pebbles.remove_at(0)
	var p := MeshInstance3D.new()
	var m := SphereMesh.new()
	var r := randf_range(0.08, 0.18)
	m.radius = r
	m.height = r * 1.6
	m.radial_segments = 8
	m.rings = 4
	p.mesh = m
	p.material_override = _stone_mat
	p.position = at + Vector3.UP * randf_range(2.5, 4.0)
	world.add_child(p)
	water.watch(p, r, r * 4.0)
	pebbles.append({node = p, speed = 0.0, life = 0.0})


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	for p: Dictionary in pebbles:
		var node: Node3D = p.node
		var under := water.depth_at(node.position) > 0.0
		# falls, then drifts down slowly once in the water
		p.speed = minf(p.speed + 9.8 * delta, 12.0) if not under else lerpf(p.speed, 0.6, delta * 6.0)
		var floor_y := _ground_y(node.position.x, node.position.z) + 0.06
		node.position.y = maxf(node.position.y - p.speed * delta, floor_y)
		p.life += delta
	while pebbles.size() > 0 and pebbles[0].life > 20.0:
		water.unwatch(pebbles[0].node)
		pebbles[0].node.queue_free()
		pebbles.remove_at(0)
	for i in pads.size():
		var pad := pads[i]
		pad.position.y = water.height_at(pad.position) + 0.005
		pad.rotation.y += sin(_time * 0.3 + i) * delta * 0.05
	if tool != 2 or _poking == -1:
		duck.position.y = water.height_at(duck.position) - 0.08
	# leaves riding the stream: fastest in the middle, bobbing and turning as they go
	var k := 0
	while k < floaters.size():
		var f: Dictionary = floaters[k]
		f.z += stream_speed / 1.4 * (1.0 - 0.5 * f.side * f.side) * delta
		f.turn += f.spin * delta
		if f.z > 44.0:
			f.node.queue_free()
			floaters.remove_at(k)
			continue
		var x: float = _stream_x(f.z) + f.side * STREAM_HALF
		var bob := sin(_time * 2.3 + f.turn) * 0.015
		f.node.position = Vector3(x, _fall(f.z) - 0.1 + bob, f.z)
		f.node.rotation = Vector3(sin(_time + f.turn) * 0.15, f.turn, 0.0)
		k += 1


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "choice", label = "Tool", options = TOOLS, value = tool, on = func(i: int) -> void: tool = i},
		{type = "section", label = "Water"},
		{type = "choice", label = "Body", options = ["Pond", "Stream"], value = body, on = _set_body},
		{type = "slider", label = "Stream flow", min = 0.0, max = 4.0, step = 0.1, value = stream_speed, unit = "m/s",
			fmt = "%.1f", on = func(v: float) -> void:
				stream_speed = v
				if stream_mat:
					stream_mat.set_shader_parameter("speed", v)},
		{type = "choice", label = "Preset", options = LOOKS.map(func(l: Array) -> String: return l[0]), value = look,
			on = func(i: int) -> void:
				look = i
				_apply_look()},
		{type = "slider", label = "Level", min = -0.8, max = 0.1, step = 0.01, value = 0.0, unit = "m", fmt = "%.2f",
			on = func(v: float) -> void: water.position.y = v},
		{type = "slider", label = "Basin depth", min = 0.4, max = 3.0, step = 0.1, value = depth, unit = "m",
			on = func(v: float) -> void:
				depth = v
				_build_basin()},
		{type = "slider", label = "Clarity", min = 0.0, max = 1.0, step = 0.05, value = 1.0 - water.alpha_shallow, fmt = "%.2f",
			on = func(v: float) -> void: water.alpha_shallow = 1.0 - v},
		{type = "slider", label = "Depth range", min = 0.3, max = 6.0, step = 0.1, value = water.depth_range, unit = "m",
			on = func(v: float) -> void: water.depth_range = v},
		{type = "section", label = "Surface"},
		{type = "slider", label = "Swell height", min = 0.0, max = 0.25, step = 0.005, value = water.swell_height, unit = "m", fmt = "%.3f",
			on = func(v: float) -> void: water.swell_height = v},
		{type = "slider", label = "Swell length", min = 1.0, max = 12.0, step = 0.5, value = water.swell_length, unit = "m",
			on = func(v: float) -> void: water.swell_length = v},
		{type = "slider", label = "Flow", min = -1.5, max = 1.5, step = 0.05, value = 0.0, unit = "m/s", fmt = "%.2f",
			on = func(v: float) -> void: water.flow = Vector2(v, 0.0)},
		{type = "slider", label = "Lines", min = 0.0, max = 1.0, step = 0.05, value = water.lines, fmt = "%.2f",
			on = func(v: float) -> void: water.lines = v},
		{type = "slider", label = "Glint", min = 0.0, max = 6.0, step = 0.1, value = water.glint,
			on = func(v: float) -> void: water.glint = v},
		{type = "slider", label = "Mirror", min = 0.0, max = 1.0, step = 0.05, value = water.mirror, fmt = "%.2f",
			on = func(v: float) -> void: water.mirror = v},
		{type = "section", label = "Foam & floor"},
		{type = "slider", label = "Foam width", min = 0.0, max = 0.6, step = 0.01, value = water.foam_width, unit = "m", fmt = "%.2f",
			on = func(v: float) -> void: water.foam_width = v},
		{type = "slider", label = "Foam ragged", min = 0.0, max = 1.0, step = 0.05, value = water.foam_ragged, fmt = "%.2f",
			on = func(v: float) -> void: water.foam_ragged = v},
		{type = "slider", label = "Drifting foam", min = 0.0, max = 0.6, step = 0.02, value = 0.0, fmt = "%.2f",
			on = func(v: float) -> void: water.foam_drift = v},
		{type = "slider", label = "Caustics", min = 0.0, max = 1.0, step = 0.05, value = water.caustics, fmt = "%.2f",
			on = func(v: float) -> void: water.caustics = v},
		{type = "slider", label = "Murk", min = 0.0, max = 1.0, step = 0.02, value = water.murk, fmt = "%.2f",
			on = func(v: float) -> void: water.murk = v},
		{type = "section", label = "Render"},
		{type = "toggle", label = "Night", value = night, on = _set_night},
		{type = "toggle", label = "Banded", value = water.banded, on = func(on: bool) -> void: water.banded = on},
		{type = "toggle", label = "Depth buffer", value = water.use_depth, on = func(on: bool) -> void: water.use_depth = on},
		{type = "button", label = "Rain pebbles", on = func() -> void:
			for i in 10:
				_drop_pebble(Vector3(randf_range(-3.5, 3.5), 0.0, randf_range(-2.5, 2.5)) + Vector3.UP * randf() * 3.0)},
	])
	return c


func help() -> String:
	return ("GameCommon's Water (scripts/water.gd) in a dug basin. Its colour comes from how much water is really behind "
		+ "each pixel (read from the depth buffer), so the shallows go clear and foam rings whatever breaks the surface.\n\n"
		+ "Finger on Poke: Pebble drops a stone the water watches (it splashes by how fast it falls), Splash throws a ring "
		+ "of froth and drops, Wake drags a float that leaves rings. Two fingers zoom and pan; dip the camera under the "
		+ "surface to see the murk and the light on the floor.\n\n"
		+ "Body: Stream swaps the pond for the painted-woodland kit's running water, down a channel that falls away "
		+ "downhill (a level box of water cannot run). Ripples run down it at Stream flow; tap it to drop leaves the "
		+ "current carries off.")


func hint() -> String:
	return "Finger: Poke to drop pebbles, splash, or drag a float. Dip under to see the murk."


func status() -> String:
	if body == 1:
		return "stream %.1f m/s  falls %d cm/m  leaves %d  %.1f ms" % [stream_speed, roundi(STREAM_FALL * 100.0),
			floaters.size(), frame_ms()]
	return "water %dx%d m  level %.2f  pebbles %d  %s  %.1f ms" % [POND.x, POND.y, water.position.y, pebbles.size(),
		TOOLS[tool].to_lower(), frame_ms()]
