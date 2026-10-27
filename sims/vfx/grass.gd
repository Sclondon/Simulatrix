extends Sim3D
## Grass: a field of GameCommon's `Grass` (real 3D blades in a MultiMesh per 10 m square),
## with every setting on the panel. A finger pushes the blades aside and leaves a trail that
## stands back up; a ball can roll laps through it; Blast sends a ring of wind out.

const PRESETS := [
	{name = "Spring", ground = Color(0.2, 0.33, 0.1), body = Color(0.32, 0.55, 0.14), tip = Color(0.66, 0.82, 0.3),
		dry = Color(0.55, 0.62, 0.25), dryness = 0.15, flowers = [Color(0.98, 0.96, 0.9), Color(0.98, 0.82, 0.25), Color(0.75, 0.6, 0.95)],
		sky = Color(0.33, 0.55, 0.85), horizon = Color(0.78, 0.86, 0.9), sun = Color(1.0, 0.97, 0.9), sun_energy = 1.0},
	{name = "Summer", ground = Color(0.2, 0.31, 0.1), body = Color(0.3, 0.47, 0.13), tip = Color(0.6, 0.72, 0.27),
		dry = Color(0.62, 0.58, 0.26), dryness = 0.35, flowers = [Color(0.95, 0.94, 0.86), Color(0.98, 0.8, 0.25), Color(0.7, 0.55, 0.9)],
		sky = Color(0.25, 0.48, 0.82), horizon = Color(0.82, 0.86, 0.84), sun = Color(1.0, 0.93, 0.8), sun_energy = 1.05},
	{name = "Dry", ground = Color(0.3, 0.27, 0.13), body = Color(0.55, 0.5, 0.24), tip = Color(0.86, 0.78, 0.48),
		dry = Color(0.72, 0.62, 0.36), dryness = 0.7, flowers = [Color(0.95, 0.9, 0.7), Color(0.9, 0.6, 0.2), Color(0.8, 0.8, 0.75)],
		sky = Color(0.42, 0.6, 0.82), horizon = Color(0.92, 0.86, 0.72), sun = Color(1.0, 0.88, 0.7), sun_energy = 1.1},
	{name = "Autumn", ground = Color(0.24, 0.2, 0.1), body = Color(0.5, 0.36, 0.14), tip = Color(0.86, 0.55, 0.2),
		dry = Color(0.62, 0.22, 0.12), dryness = 0.55, flowers = [Color(0.95, 0.75, 0.3), Color(0.8, 0.3, 0.15), Color(0.6, 0.35, 0.5)],
		sky = Color(0.45, 0.5, 0.65), horizon = Color(0.95, 0.72, 0.5), sun = Color(1.0, 0.72, 0.45), sun_energy = 1.2},
	{name = "Spooky", ground = Color(0.05, 0.07, 0.09), body = Color(0.1, 0.17, 0.2), tip = Color(0.42, 0.5, 0.62),
		dry = Color(0.3, 0.2, 0.36), dryness = 0.5, flowers = [Color(0.75, 0.95, 0.8), Color(0.65, 0.4, 0.9), Color(0.9, 0.9, 1.0)],
		sky = Color(0.02, 0.03, 0.08), horizon = Color(0.16, 0.2, 0.32), sun = Color(0.6, 0.7, 1.0), sun_energy = 0.8},
]
const AREA := Rect2(-45, -45, 90, 90)

var grass: Grass
var ground_mat := ShaderMaterial.new()
var finger := Node3D.new()
var ring := MeshInstance3D.new()
var ball := MeshInstance3D.new()
var preset := 1
var density := 1.0
var flowers := 0.04
var brush := 0.8
var direction := 20.0
var rolling := false
var _lap := 0.0


func pokeable() -> bool:
	return true


func hint() -> String:
	return "Drag to orbit. Set Finger to Poke and drag through the grass to part it."


func help() -> String:
	return "GameCommon's Grass: tufts of curved, tapered blades, one MultiMesh per 10 m square, " \
		+ "built and swayed entirely in the vertex shader. Gusts are noise rolling across the field in " \
		+ "world space; each blade flutters on its own. Pushers bend blades away and stamp the time into " \
		+ "a trail texture, so trodden grass stands back up over Recover seconds. Far squares thin out " \
		+ "and fade into the ground.\n\nLook: one finger orbits, two pinch and pan, the wheel zooms.\n" \
		+ "Poke: drag to push the grass. Blast sends a ring of wind out from the middle."


func build() -> void:
	set_sky(Color(0.25, 0.48, 0.82), Color(0.82, 0.86, 0.84))
	environment.fog_enabled = true
	environment.fog_density = 0.008
	environment.fog_sky_affect = 0.0
	environment.ambient_light_energy = 0.45
	sun.rotation = Vector3(deg_to_rad(-28), deg_to_rad(-150), 0)
	focus = Vector3(0, 0.35, 0)
	distance = 10.0
	pitch = -0.42
	yaw = 0.4
	min_distance = 1.2
	max_distance = 40.0
	max_pitch = -0.04
	auto_orbit = 0.05

	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	plane.mesh = pm
	ground_mat.shader = preload("res://sims/vfx/grass_ground.gdshader")
	plane.material_override = ground_mat
	world.add_child(plane)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 32
	ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1, 1, 1, 0.55)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position.y = 0.05
	finger.add_child(ring)
	finger.visible = false
	world.add_child(finger)

	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	ball.mesh = sphere
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.3, 0.25)
	bm.roughness = 0.5
	ball.material_override = bm
	ball.visible = false
	world.add_child(ball)

	grass = Grass.field(world, AREA, density, {"flowers": flowers, "seed": 3})
	_apply_preset()
	_apply_wind()


func status() -> String:
	if grass == null:
		return ""
	var c := grass.counts()
	return "tufts %d  drawn %d  tris %dk  %s  %.1f ms" % [c.x, c.y, c.z / 1000, ["low", "medium", "high"][Grass.quality], frame_ms()]


func controls() -> Array:
	var list := look_controls()
	list.append_array([
		{type = "section", label = "Field"},
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = Grass.quality,
			on = func(i: int) -> void: Grass.set_quality(i)},
		{type = "slider", label = "Density", min = 0.2, max = 2.0, step = 0.1, value = density, fmt = "%.1f",
			on = func(v: float) -> void:
				density = v
				grass.density = v
				grass.build()},
		{type = "slider", label = "Flowers", min = 0.0, max = 0.25, step = 0.01, value = flowers, fmt = "%.2f",
			on = func(v: float) -> void:
				flowers = v
				grass.flowers = v
				grass.build()},
		{type = "button", label = "Reseed", on = func() -> void:
			grass.seed += 1
			grass.build()},
		{type = "section", label = "Blades"},
		{type = "slider", label = "Height", min = 0.15, max = 1.4, step = 0.05, value = grass.blade_height, fmt = "%.2f", unit = "m",
			on = func(v: float) -> void:
				grass.blade_height = v
				grass.apply_settings()},
		{type = "slider", label = "Width", min = 0.01, max = 0.09, step = 0.005, value = grass.blade_width, fmt = "%.3f", unit = "m",
			on = func(v: float) -> void:
				grass.blade_width = v
				grass.apply_settings()},
		{type = "slider", label = "Lean", min = 0.0, max = 1.0, step = 0.05, value = grass.lean, fmt = "%.2f", unit = "rad",
			on = func(v: float) -> void:
				grass.lean = v
				grass.apply_settings()},
		{type = "slider", label = "Dryness", min = 0.0, max = 1.0, step = 0.05, value = grass.dryness, fmt = "%.2f",
			on = func(v: float) -> void:
				grass.dryness = v
				grass.apply_settings()},
		{type = "slider", label = "Shading bands", min = 0.0, max = 1.0, step = 0.05, value = grass.banded, fmt = "%.2f",
			on = func(v: float) -> void:
				grass.banded = v
				grass.apply_settings()},
		{type = "section", label = "Palette"},
		{type = "choice", label = "Preset", options = PRESETS.map(func(p: Dictionary) -> String: return p.name), value = preset,
			colors = PRESETS.map(func(p: Dictionary) -> Color: return p.tip),
			on = func(i: int) -> void:
				preset = i
				_apply_preset()},
		{type = "section", label = "Wind"},
		{type = "slider", label = "Strength", min = 0.0, max = 2.0, step = 0.05, value = grass.wind, fmt = "%.2f",
			on = func(v: float) -> void:
				grass.wind = v
				_apply_wind()},
		{type = "slider", label = "Direction", min = 0.0, max = 360.0, step = 5.0, value = direction, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void:
				direction = v
				_apply_wind()},
		{type = "slider", label = "Gust size", min = 4.0, max = 40.0, step = 1.0, value = grass.gust_size, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void:
				grass.gust_size = v
				_apply_wind()},
		{type = "slider", label = "Gust speed", min = 0.0, max = 15.0, step = 0.5, value = grass.gust_speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void:
				grass.gust_speed = v
				_apply_wind()},
		{type = "slider", label = "Flutter", min = 0.0, max = 0.5, step = 0.02, value = grass.flutter, fmt = "%.2f",
			on = func(v: float) -> void:
				grass.flutter = v
				_apply_wind()},
		{type = "section", label = "Pushers"},
		{type = "slider", label = "Brush", min = 0.3, max = 3.0, step = 0.1, value = brush, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void:
				brush = v
				finger.set_meta(&"grass_radius", v)
				ring.scale = Vector3.ONE * v},
		{type = "slider", label = "Recover", min = 1.0, max = 20.0, step = 0.5, value = grass.recover, fmt = "%.1f", unit = "s",
			on = func(v: float) -> void:
				grass.recover = v
				grass.apply_settings()},
		{type = "toggle", label = "Rolling ball", value = rolling, on = func(on: bool) -> void:
			rolling = on
			ball.visible = on
			if on:
				Grass.push(ball, 0.75)
			else:
				Grass.unpush(ball)},
		{type = "button", label = "Blast", on = func() -> void: Grass.blast(Vector3.ZERO, 1.6)},
	])
	list.append_array(Exporter.controls("%s grass" % PRESETS[preset].name, _export, "grass",
		func(t: String) -> void: say.emit(t)))
	return list


## Sends the field's settings (blades, colours, flowers, wind, size) to the asset library as a
## scene: one Grass node, which builds itself when the project calls build().
func _export(asset_name: String) -> void:
	var made := NodeCopy.fresh(grass, asset_name.to_pascal_case().validate_node_name())
	var file := Exporter.slug(asset_name)
	var p: Dictionary = PRESETS[preset]
	say.emit(Exporter.save("grass", asset_name, {"tscn": made}, ["godot/grass"],
		"var grass := (load(\"res://assets/grass/%s.tscn\") as PackedScene).instantiate() as Grass\n" % file
		+ "grass.area = Rect2(-20, -20, 40, 40)   # world x, z (it was %s here); keep the node at the origin\n" % str(grass.area)
		+ "add_child(grass)\ngrass.build()\n"
		+ "Grass.push(player)   # anything that should part it\n"
		+ "# ground under it in its root colour: Color(%.2f, %.2f, %.2f)" % [p.ground.r, p.ground.g, p.ground.b],
		"Grass"))
	made.free()


func _apply_preset() -> void:
	var p: Dictionary = PRESETS[preset]
	grass.ground = p.ground
	grass.body = p.body
	grass.tip = p.tip
	grass.dry = p.dry
	grass.dryness = p.dryness
	var petals: Array[Color] = []
	petals.assign(p.flowers)
	grass.petals = petals
	grass.apply_settings()
	set_sky(p.sky, p.horizon)
	environment.fog_light_color = p.horizon.lerp(p.sky, 0.3)
	environment.ambient_light_color = p.sky.lerp(p.horizon, 0.5)
	ground_mat.set_shader_parameter(&"ground", p.ground)
	ground_mat.set_shader_parameter(&"far_colour", p.body.lerp(p.horizon, 0.35))
	sun.light_color = p.sun
	sun.light_energy = p.sun_energy


func _apply_wind() -> void:
	var a := deg_to_rad(direction)
	grass.wind_dir = Vector2(cos(a), sin(a))
	grass.apply_settings()


func _process(delta: float) -> void:
	super._process(delta)
	if rolling:
		_lap += delta * 0.32
		var r := 6.0 + sin(_lap * 2.3) * 2.0
		var at := Vector3(cos(_lap) * r, 0.45, sin(_lap) * r)
		var step := at - ball.position
		ball.position = at
		if step.length() > 0.0001:
			ball.rotate(step.cross(Vector3.DOWN).normalized(), -step.length() / 0.45)


func poke_down(pos: Vector2) -> void:
	var p: Variant = ground(pos)
	if p == null:
		return
	finger.position = p
	finger.visible = true
	ring.scale = Vector3.ONE * brush
	Grass.push(finger, brush)


func poke_move(pos: Vector2) -> void:
	var p: Variant = ground(pos)
	if p != null:
		finger.position = p


func poke_up(_pos: Vector2) -> void:
	finger.visible = false
	Grass.unpush(finger)
