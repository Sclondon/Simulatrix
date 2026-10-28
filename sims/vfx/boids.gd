extends Sim3D
## Boids: GameCommon's flock (a Flock run by a FlockRules) with every rule on a slider. Six
## presets, each in a scene of its own: starlings at dusk, a fish school over a reef, bats round
## a ruined tower by moonlight, crows wheeling over a dead tree, gnats dancing over the grass at
## golden hour, sheep in a field. A finger sets the goal, chases them as a predator, or puts
## down obstacles; a hawk can make passes on its own. Debug views show one boid's perception and
## neighbours, every velocity, and the bounds. Export saves the rules (.tres) and a configured
## Flock (.tscn).

const TOOLS := ["Goal / chase", "Obstacles"]
const HOLD := 0.22
const MOVE_PX := 14.0
const HAWK_EVERY := 6.5

var flock := Flock.new()
var rules: FlockRules
var preset := 0
var tool := 0
var hawk_on := true
var show_perception := false
var show_neighbours := false
var show_velocity := false
var show_bounds := false
var wind_speed := 0.0
var field := WindField.new()

var _scene: Node3D
var _hawk := Node3D.new()
var _hawk_from := Vector3.ZERO
var _hawk_to := Vector3.ZERO
var _hawk_t := 0.0
var _chaser := Node3D.new()
var _goal_marker := MeshInstance3D.new()
var _debug := MeshInstance3D.new()
var _lines := ImmediateMesh.new()
var _user_obstacles: Array[Node3D] = []
var _rock_mat := StandardMaterial3D.new()
var _press := {}
var _rng := RandomNumberGenerator.new()


func pokeable() -> bool:
	return true


func hint() -> String:
	return "Pick a preset. Set Finger to Poke: tap to set their goal, hold or drag to chase them."


func help() -> String:
	return ("A flock of boids (GameCommon's flock, after Craig Reynolds). Each one sees only its few nearest "
		+ "neighbours (within Perception, inside its Field of view, at most Neighbours of them) and steers by "
		+ "three rules: keep clear of any too close (Separation), go the way they go (Alignment), make for the "
		+ "middle of them (Cohesion). On top: a wandering urge of its own, a goal to seek or circle, predators "
		+ "to flee (a fright passes from bird to bird: Alarm spread), obstacles to fly round, the bounds and "
		+ "the ground. Starlings heed about seven neighbours each, which is what lets a murmuration ripple.\n\n"
		+ "Look: one finger orbits, two pinch and pan, the wheel zooms.\n"
		+ "Poke, Goal / chase: tap to set where they make for; hold or drag to be a predator they scatter "
		+ "from. Poke, Obstacles: tap to put a rock down (they steer round it).\n"
		+ "Hawk makes a pass through them every few seconds. Debug shows one boid's perception (yellow) and "
		+ "the neighbours it heeds, every boid's velocity (red when frightened) and the bounds.\n\n"
		+ "All of them are one MultiMesh (one draw): wings, tails and legs move in the shader. Neighbours "
		+ "are found through a spatial hash; past the time budget, boids take turns to think.\n\n"
		+ "Export saves the rules (.tres) and a ready Flock (.tscn) for any project (needs godot/flock).")


func build() -> void:
	_rng.seed = 11
	min_distance = 2.0
	max_distance = 160.0
	camera.far = 900.0
	_rock_mat.albedo_color = Color(0.42, 0.4, 0.38)
	_rock_mat.roughness = 0.95
	world.add_child(flock)
	_hawk.add_to_group(&"flock_predators")
	world.add_child(_hawk)
	world.add_child(_chaser)
	_chaser.visible = false
	var gm := SphereMesh.new()
	gm.radius = 0.5
	gm.height = 1.0
	gm.radial_segments = 12
	gm.rings = 6
	_goal_marker.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1.0, 0.85, 0.3, 0.55)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.disable_fog = true
	_goal_marker.material_override = gmat
	_goal_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_goal_marker.visible = false
	world.add_child(_goal_marker)
	_debug.mesh = _lines
	_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.no_depth_test = true
	dm.disable_fog = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug.material_override = dm
	world.add_child(_debug)
	use_preset(0)


## Switches to a preset: its rules, its scene and its camera.
func use_preset(i: int) -> void:
	preset = i
	rules = FlockRules.preset(i)
	# (GDScript runs slower in a browser, and phones slower still: start smaller there; Count goes back up)
	if OS.has_feature("web"):
		rules.count = mini(rules.count, 400)
	flock.rules = rules
	flock.target = Vector3.INF
	flock.clear_obstacles()
	for o in _user_obstacles:
		o.queue_free()
	_user_obstacles.clear()
	_build_scene()
	flock.respawn()
	_place_camera()
	_new_hawk_pass()
	controls_changed.emit()


func status() -> String:
	var goal := "goal set" if flock.target.is_finite() else "goal: home"
	return "%d boids · %d thought about a frame · %.1f neighbours each · flock %.2f ms · %s · %.1f ms frame" % [
		flock.boid_count(), flock.steered, flock.mean_neighbours, flock.sim_ms, goal, frame_ms()]


func controls() -> Array:
	var r := rules
	var c := look_controls()
	c.append_array([
		{type = "choice", label = "Poke does", options = TOOLS, value = tool, on = func(i: int) -> void: tool = i},
		{type = "section", label = "Preset"},
		{type = "choice", label = "Preset", options = FlockRules.PRESETS, value = preset, on = use_preset},
		{type = "button", label = "Respawn", on = func() -> void: flock.respawn()},
		{type = "section", label = "Flock"},
		{type = "slider", label = "Count", min = 1.0, max = 1500.0, step = 1.0, value = r.count, fmt = "%.0f",
			on = func(v: float) -> void: r.count = int(v)},
		{type = "choice", label = "Body", options = ["Bird", "Fish", "Bat", "Bug", "Sheep"], value = mini(r.body, 4),
			on = func(i: int) -> void: r.body = i},
		{type = "choice", label = "Motion", options = ["Flap", "Swim", "Walk", "None"], value = r.motion,
			on = func(i: int) -> void: r.motion = i},
		{type = "slider", label = "Size", min = 0.02, max = 3.0, step = 0.01, value = r.size, fmt = "%.2f", unit = "m",
			on = func(v: float) -> void: r.size = v},
		{type = "slider", label = "Size varies", min = 0.0, max = 0.6, step = 0.01, value = r.size_variation, fmt = "%.2f",
			on = func(v: float) -> void: r.size_variation = v},
		{type = "slider", label = "Shade varies", min = 0.0, max = 0.6, step = 0.01, value = r.colour_variation, fmt = "%.2f",
			on = func(v: float) -> void: r.colour_variation = v},
		{type = "toggle", label = "On the ground (2D)", value = r.planar, on = func(v: bool) -> void:
			r.planar = v
			flock.respawn()},
		{type = "section", label = "Speed"},
		{type = "slider", label = "Max speed", min = 0.5, max = 40.0, step = 0.1, value = r.max_speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: r.max_speed = v},
		{type = "slider", label = "Min speed", min = 0.0, max = 30.0, step = 0.1, value = r.min_speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: r.min_speed = v},
		{type = "slider", label = "Cruise", min = 0.0, max = 30.0, step = 0.1, value = r.cruise_speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: r.cruise_speed = v},
		{type = "slider", label = "Max steer", min = 0.5, max = 80.0, step = 0.5, value = r.max_force, fmt = "%.1f", unit = "m/s²",
			on = func(v: float) -> void: r.max_force = v},
		{type = "section", label = "Senses"},
		{type = "slider", label = "Perception", min = 0.1, max = 20.0, step = 0.05, value = r.perception, fmt = "%.2f", unit = "m",
			on = func(v: float) -> void: r.perception = v},
		{type = "slider", label = "Field of view", min = 30.0, max = 360.0, step = 5.0, value = r.field_of_view, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: r.field_of_view = v},
		{type = "slider", label = "Neighbours", min = 1.0, max = 30.0, step = 1.0, value = r.max_neighbours, fmt = "%.0f",
			on = func(v: float) -> void: r.max_neighbours = int(v)},
		{type = "section", label = "Rules"},
		{type = "slider", label = "Separation", min = 0.0, max = 6.0, step = 0.05, value = r.separation, fmt = "%.2f",
			on = func(v: float) -> void: r.separation = v},
		{type = "slider", label = "Personal space", min = 0.02, max = 6.0, step = 0.01, value = r.separation_distance, fmt = "%.2f", unit = "m",
			on = func(v: float) -> void: r.separation_distance = v},
		{type = "slider", label = "Alignment", min = 0.0, max = 6.0, step = 0.05, value = r.alignment, fmt = "%.2f",
			on = func(v: float) -> void: r.alignment = v},
		{type = "slider", label = "Cohesion", min = 0.0, max = 6.0, step = 0.05, value = r.cohesion, fmt = "%.2f",
			on = func(v: float) -> void: r.cohesion = v},
		{type = "slider", label = "Wander", min = 0.0, max = 4.0, step = 0.05, value = r.wander, fmt = "%.2f",
			on = func(v: float) -> void: r.wander = v},
		{type = "slider", label = "Wander rate", min = 0.0, max = 15.0, step = 0.1, value = r.wander_rate, fmt = "%.1f", unit = "/s",
			on = func(v: float) -> void: r.wander_rate = v},
		{type = "slider", label = "Alarm spread", min = 0.0, max = 1.0, step = 0.01, value = r.alarm_spread, fmt = "%.2f",
			on = func(v: float) -> void: r.alarm_spread = v},
		{type = "section", label = "Bounds"},
		{type = "choice", label = "Shape", options = ["Box", "Sphere", "Ground layer"], value = r.bounds,
			on = func(i: int) -> void: r.bounds = i},
		{type = "slider", label = "Width", min = 0.5, max = 80.0, step = 0.5, value = r.bounds_size.x, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void:
				r.bounds_size.x = v
				r.bounds_size.z = v},
		{type = "slider", label = "Height", min = 0.5, max = 60.0, step = 0.5, value = r.bounds_size.y, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.bounds_size.y = v},
		{type = "slider", label = "Margin", min = 0.0, max = 30.0, step = 0.1, value = r.bounds_margin, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.bounds_margin = v},
		{type = "slider", label = "Turn back", min = 0.0, max = 6.0, step = 0.05, value = r.bounds_force, fmt = "%.2f",
			on = func(v: float) -> void: r.bounds_force = v},
		{type = "section", label = "Ground"},
		{type = "toggle", label = "Avoid ground", value = r.avoid_ground, on = func(v: bool) -> void: r.avoid_ground = v},
		{type = "slider", label = "Clearance", min = 0.0, max = 40.0, step = 0.1, value = r.ground_clearance, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.ground_clearance = v},
		{type = "slider", label = "Ceiling", min = 0.0, max = 80.0, step = 0.5, value = r.ceiling, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.ceiling = v},
		{type = "section", label = "Goal"},
		{type = "slider", label = "Seek", min = 0.0, max = 5.0, step = 0.05, value = r.seek, fmt = "%.2f",
			on = func(v: float) -> void: r.seek = v},
		{type = "slider", label = "Arrive radius", min = 0.0, max = 30.0, step = 0.1, value = r.arrive_radius, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.arrive_radius = v},
		{type = "slider", label = "Orbit", min = 0.0, max = 4.0, step = 0.05, value = r.orbit, fmt = "%.2f",
			on = func(v: float) -> void: r.orbit = v},
		{type = "slider", label = "Orbit radius", min = 0.5, max = 40.0, step = 0.5, value = r.orbit_radius, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.orbit_radius = v},
		{type = "button", label = "Goal home", on = func() -> void: flock.target = Vector3.INF},
		{type = "section", label = "Predators"},
		{type = "toggle", label = "Hawk", value = hawk_on, on = func(v: bool) -> void:
			hawk_on = v
			_new_hawk_pass()},
		{type = "slider", label = "Flee", min = 0.0, max = 12.0, step = 0.1, value = r.flee, fmt = "%.1f",
			on = func(v: float) -> void: r.flee = v},
		{type = "slider", label = "Flee radius", min = 0.1, max = 40.0, step = 0.1, value = r.flee_radius, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: r.flee_radius = v},
		{type = "slider", label = "Panic speed", min = 1.0, max = 3.0, step = 0.05, value = r.panic_speed, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: r.panic_speed = v},
		{type = "slider", label = "Calm down", min = 0.05, max = 3.0, step = 0.05, value = r.calm_rate, fmt = "%.2f", unit = "/s",
			on = func(v: float) -> void: r.calm_rate = v},
		{type = "button", label = "Scatter", on = func() -> void: flock.scatter(flock.centre(), 1.0)},
		{type = "section", label = "Obstacles"},
		{type = "slider", label = "Avoid", min = 0.0, max = 10.0, step = 0.1, value = r.avoid, fmt = "%.1f",
			on = func(v: float) -> void: r.avoid = v},
		{type = "slider", label = "Look ahead", min = 0.0, max = 3.0, step = 0.05, value = r.look_ahead, fmt = "%.2f", unit = "s",
			on = func(v: float) -> void: r.look_ahead = v},
		{type = "button", label = "Add 3", on = _add_random_obstacles},
		{type = "button", label = "Clear mine", on = _clear_obstacles},
		{type = "section", label = "Motion"},
		{type = "slider", label = "Banking", min = 0.0, max = 1.5, step = 0.05, value = r.banking, fmt = "%.2f",
			on = func(v: float) -> void: r.banking = v},
		{type = "slider", label = "Max bank", min = 0.0, max = 90.0, step = 1.0, value = r.max_bank, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: r.max_bank = v},
		{type = "slider", label = "Beat rate", min = 0.0, max = 50.0, step = 0.1, value = r.flap_rate, fmt = "%.1f", unit = "Hz",
			on = func(v: float) -> void: r.flap_rate = v},
		{type = "slider", label = "Beat size", min = 0.0, max = 1.5, step = 0.01, value = r.flap_amount, fmt = "%.2f",
			on = func(v: float) -> void: r.flap_amount = v},
		{type = "slider", label = "Glide", min = 0.0, max = 1.0, step = 0.01, value = r.glide, fmt = "%.2f",
			on = func(v: float) -> void: r.glide = v},
		{type = "section", label = "Wind"},
		{type = "slider", label = "Wind", min = 0.0, max = 15.0, step = 0.5, value = wind_speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void:
				wind_speed = v
				field.speed = v
				flock.wind = field if v > 0.0 else null},
		{type = "slider", label = "Carried", min = 0.0, max = 1.5, step = 0.05, value = r.wind_carry, fmt = "%.2f",
			on = func(v: float) -> void: r.wind_carry = v},
		{type = "section", label = "Debug"},
		{type = "toggle", label = "Perception", value = show_perception, on = func(v: bool) -> void: show_perception = v},
		{type = "toggle", label = "Neighbour lines", value = show_neighbours, on = func(v: bool) -> void: show_neighbours = v},
		{type = "toggle", label = "Velocities", value = show_velocity, on = func(v: bool) -> void: show_velocity = v},
		{type = "toggle", label = "Bounds", value = show_bounds, on = func(v: bool) -> void: show_bounds = v},
		{type = "slider", label = "Think budget", min = 0.5, max = 12.0, step = 0.5, value = flock.budget_ms, fmt = "%.1f", unit = "ms",
			on = func(v: float) -> void: flock.budget_ms = v},
	])
	c.append_array(Exporter.controls(FlockRules.PRESETS[preset], _export, "flocks", func(line: String) -> void: say.emit(line)))
	return c


func _export(name: String) -> void:
	var slug := Exporter.slug(name)
	var node := Flock.new()
	node.name = name.to_pascal_case().validate_node_name()
	node.rules = rules.duplicate()
	node.cast_shadows = flock.cast_shadows
	node.budget_ms = flock.budget_ms
	say.emit(Exporter.save("flocks", name, {"tres": rules.duplicate(), "tscn": node}, ["godot/flock"],
		"var flock := load(\"res://assets/flocks/%s.tscn\").instantiate() as Flock   # its bounds are round where you put it\n" % slug
		+ "add_child(flock); flock.position = Vector3(0, %.1f, 0)   # (the lab's height)\n" % flock.position.y
		+ "flock.target = point   # or target_node; hunters go in the group flock_predators; flock.scatter(at) for a bang\n"
		+ "other_flock.rules = load(\"res://assets/flocks/%s.tres\")   # just the behaviour" % slug, "Boids"))
	node.free()


# --- scenes -----------------------------------------------------------------------

func _build_scene() -> void:
	if _scene:
		_scene.queue_free()
	_scene = Node3D.new()
	world.add_child(_scene)
	environment.fog_enabled = false
	environment.fog_sky_affect = 0.0
	environment.background_mode = Environment.BG_COLOR
	environment.sky = null
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	sun.shadow_opacity = 1.0
	sun.shadow_enabled = true
	sun.light_color = Color.WHITE
	auto_orbit = 0.035
	min_pitch = -1.45
	max_pitch = 0.15
	flock.ground_y = 0.0
	match preset:
		0: _dusk()
		1: _reef()
		2: _night()
		3: _overcast()
		4: _golden()
		5: _field()
	_hawk_body()


func _ground_plane(colour: Color, size := 400.0, far := Color(-1, 0, 0)) -> MeshInstance3D:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	plane.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://sims/vfx/grass_ground.gdshader")
	gm.set_shader_parameter(&"ground", colour)
	gm.set_shader_parameter(&"far_colour", far if far.r >= 0.0 else colour.lightened(0.15))
	# (fading into the far colour well beyond where the camera looks)
	gm.set_shader_parameter(&"fade_from", distance * 1.4 + 20.0)
	gm.set_shader_parameter(&"fade_to", distance * 1.4 + 160.0)
	plane.material_override = gm
	_scene.add_child(plane)
	return plane


func _mat(colour: Color, rough := 0.9, emit := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic_specular = 0.15
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
	return m


func _shape(mesh: PrimitiveMesh, at: Vector3, mat: Material, scale := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.scale = scale
	mi.rotation = rot
	_scene.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, height: float, sides := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


func _ball(radius: float, segs := 10) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


# An obstacle that is part of the scene: drawn, and in the flock's obstacle group.
func _scene_obstacle(node: Node3D, radius: float) -> void:
	node.add_to_group(&"flock_obstacles")
	node.set_meta(&"flock_radius", radius)


# A bare tree: a trunk and a few crooked branches, as cylinders.
func _bare_tree(at: Vector3, height: float, mat: Material) -> void:
	var trunk := _shape(_cyl(height * 0.03, height * 0.06, height * 0.6, 7), at + Vector3(0, height * 0.3, 0), mat)
	trunk.rotation.z = 0.04
	for k in 7:
		var a := k * 2.4 + 0.3
		var up := 0.35 + 0.08 * k
		var len := height * (0.45 - 0.035 * k)
		var b := _shape(_cyl(height * 0.008, height * 0.025, len, 5), Vector3.ZERO, mat)
		var dir := Vector3(cos(a) * 0.8, 1.0 - k * 0.06, sin(a) * 0.8).normalized()
		b.position = at + Vector3(0, height * up, 0) + dir * len * 0.5
		b.basis = Basis(Quaternion(Vector3.UP, dir))


func _dusk() -> void:
	set_sky(Color(0.16, 0.2, 0.38), Color(0.98, 0.6, 0.36), Color(0.1, 0.08, 0.1))
	environment.ambient_light_color = Color(0.6, 0.48, 0.5)
	environment.ambient_light_energy = 0.5
	environment.fog_enabled = false
	environment.fog_density = 0.0012
	environment.fog_light_color = Color(0.85, 0.55, 0.42)
	sun.rotation = Vector3(deg_to_rad(-6), deg_to_rad(160), 0)
	sun.light_color = Color(1.0, 0.62, 0.38)
	sun.light_energy = 0.8
	sun.shadow_enabled = false
	flock.position = Vector3(0, 28, 0)
	focus = Vector3(0, 27, 0)
	distance = 40.0
	yaw = 0.15
	pitch = 0.12
	max_pitch = 0.4
	_ground_plane(Color(0.05, 0.045, 0.04), 900.0, Color(0.09, 0.06, 0.06))
	# a far line of trees and a reed bed, as silhouettes
	var dark := _mat(Color(0.02, 0.018, 0.025))
	for k in 46:
		var a := -1.2 + k * 0.055 + _rng.randf_range(-0.02, 0.02)
		var d := _rng.randf_range(110.0, 150.0)
		var h := _rng.randf_range(8.0, 16.0)
		var at := Vector3(sin(a + PI) * d, 0, cos(a + PI) * d)
		_shape(_ball(h * 0.45, 8), at + Vector3(0, h * 0.75, 0), dark, Vector3(1, 1.25, 1))
		_shape(_cyl(0.3, 0.5, h * 0.6, 5), at + Vector3(0, h * 0.3, 0), dark)
	var reed := _mat(Color(0.04, 0.035, 0.03))
	for k in 160:
		var at := Vector3(_rng.randf_range(-60, 60), 0, _rng.randf_range(-70, -30))
		var h := _rng.randf_range(1.5, 3.5)
		_shape(_cyl(0.02, 0.08, h, 3), at + Vector3(0, h * 0.5, 0), reed, Vector3.ONE, Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15)))


func _reef() -> void:
	environment.background_color = Color(0.03, 0.17, 0.26)
	environment.ambient_light_color = Color(0.32, 0.46, 0.55)
	environment.ambient_light_energy = 0.7
	environment.fog_enabled = true
	environment.fog_density = 0.045
	environment.fog_light_color = Color(0.03, 0.17, 0.26)
	sun.rotation = Vector3(deg_to_rad(-75), deg_to_rad(-30), 0)
	sun.light_color = Color(0.8, 0.92, 1.0)
	sun.light_energy = 0.85
	sun.directional_shadow_max_distance = 40.0
	flock.position = Vector3(0, 6, 0)
	flock.ground_y = 0.0
	focus = Vector3(0, 5.5, 0)
	distance = 12.5
	yaw = 0.5
	pitch = -0.12
	max_pitch = 0.5
	# sand, and the bright surface far overhead
	var sand := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	sand.mesh = pm
	sand.material_override = _mat(Color(0.62, 0.56, 0.42), 1.0)
	_scene.add_child(sand)
	var surface := MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2(300, 300)
	sp.flip_faces = true
	surface.mesh = sp
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.45, 0.85, 0.9)
	surface.material_override = sm
	surface.position.y = 20.0
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene.add_child(surface)
	# rocks and coral heads they swim round
	var rock := _mat(Color(0.36, 0.38, 0.36))
	var corals := [_mat(Color(0.85, 0.42, 0.38)), _mat(Color(0.9, 0.7, 0.35)), _mat(Color(0.55, 0.42, 0.7))]
	for spot: Vector4 in [Vector4(-5, 1.6, -3, 2.4), Vector4(6, 1.2, 4, 1.8), Vector4(2, 2.6, -8, 3.2), Vector4(-9, 0.9, 6, 1.6), Vector4(10, 1.4, -6, 2.0)]:
		var r := _shape(_ball(spot.w, 9), Vector3(spot.x, spot.y - spot.w * 0.4, spot.z), rock, Vector3(1.2, 0.8, 1.0), Vector3(0, spot.x, 0))
		_scene_obstacle(r, spot.w * 1.1)
		for k in 6:
			var a := k * 1.1 + spot.x
			var at := Vector3(spot.x + cos(a) * spot.w * 0.9, 0.0, spot.z + sin(a) * spot.w * 0.9)
			var h := _rng.randf_range(0.6, 1.6)
			_shape(_cyl(0.05, 0.12, h, 5), at + Vector3(0, h * 0.5, 0), corals[k % 3], Vector3.ONE, Vector3(_rng.randf_range(-0.3, 0.3), 0, _rng.randf_range(-0.3, 0.3)))
	for k in 30:
		var at := Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))
		_shape(_ball(_rng.randf_range(0.2, 0.6), 6), at, rock, Vector3(1, 0.6, 1))


func _night() -> void:
	set_sky(Color(0.03, 0.04, 0.11), Color(0.2, 0.22, 0.4), Color(0.02, 0.02, 0.03))
	environment.ambient_light_color = Color(0.35, 0.4, 0.6)
	environment.ambient_light_energy = 0.6
	environment.fog_enabled = true
	environment.fog_density = 0.008
	environment.fog_light_color = Color(0.1, 0.12, 0.22)
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(20), 0)
	sun.light_color = Color(0.65, 0.75, 1.0)
	sun.light_energy = 0.55
	flock.position = Vector3(0, 9, 0)
	focus = Vector3(0, 8, 0)
	distance = 26.0
	yaw = -0.4
	pitch = 0.0
	max_pitch = 0.35
	_ground_plane(Color(0.06, 0.07, 0.07), 400.0, Color(0.05, 0.06, 0.1))
	# the moon, and a ruined tower the bats come out of
	var moon := MeshInstance3D.new()
	moon.mesh = _ball(9.0, 24)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.97, 0.85)
	mm.disable_fog = true
	moon.material_override = mm
	moon.position = Vector3(22, 34, -150)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene.add_child(moon)
	var stone := _mat(Color(0.2, 0.2, 0.22))
	var tower := _shape(_cyl(2.6, 3.0, 16.0, 10), Vector3(9, 8, -8), stone)
	_scene_obstacle(tower, 3.6)
	for k in 5:
		var a := k * TAU / 5.0
		_shape(_box(Vector3(1.2, 1.4 + (k % 2) * 0.8, 1.0)), Vector3(9 + cos(a) * 2.4, 16.6, -8 + sin(a) * 2.4), stone)
	var bark := _mat(Color(0.08, 0.07, 0.07))
	_bare_tree(Vector3(-12, 0, -4), 13.0, bark)
	_bare_tree(Vector3(-16, 0, 6), 10.0, bark)
	var t1 := Node3D.new()
	t1.position = Vector3(-12, 7, -4)
	_scene.add_child(t1)
	_scene_obstacle(t1, 3.5)


func _overcast() -> void:
	set_sky(Color(0.5, 0.53, 0.56), Color(0.76, 0.76, 0.74), Color(0.3, 0.3, 0.28))
	environment.ambient_light_color = Color(0.7, 0.7, 0.72)
	environment.ambient_light_energy = 0.7
	environment.fog_enabled = true
	environment.fog_density = 0.004
	environment.fog_light_color = Color(0.7, 0.71, 0.72)
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-40), 0)
	sun.light_energy = 0.45
	sun.shadow_opacity = 0.4
	flock.position = Vector3(0, 15, 0)
	focus = Vector3(0, 11, 0)
	distance = 38.0
	yaw = 0.7
	pitch = -0.08
	max_pitch = 0.3
	_ground_plane(Color(0.2, 0.19, 0.11), 500.0, Color(0.42, 0.42, 0.38))
	var bark := _mat(Color(0.05, 0.045, 0.04))
	_bare_tree(Vector3(0, 0, 0), 16.0, bark)
	_bare_tree(Vector3(-28, 0, -20), 11.0, bark)
	# a fence line across the field
	var post := _mat(Color(0.3, 0.25, 0.2))
	for k in 30:
		_shape(_box(Vector3(0.15, 1.3, 0.15)), Vector3(-45 + k * 3.0, 0.65, 18 + sin(k * 0.3) * 1.5), post)
	# stubble rows
	var row := _mat(Color(0.3, 0.25, 0.15))
	for k in 24:
		_shape(_box(Vector3(120, 0.08, 0.5)), Vector3(0, 0.04, -60 + k * 5.0), row)


func _golden() -> void:
	set_sky(Color(0.38, 0.55, 0.8), Color(1.0, 0.78, 0.5))
	environment.ambient_light_color = Color(0.75, 0.68, 0.55)
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_density = 0.02
	environment.fog_light_color = Color(0.95, 0.75, 0.5)
	sun.rotation = Vector3(deg_to_rad(-12), deg_to_rad(-200), 0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 0.75
	sun.directional_shadow_max_distance = 20.0
	flock.position = Vector3(0, 1.7, 0)
	focus = Vector3(0, 1.5, 0)
	distance = 4.2
	yaw = 0.3
	pitch = -0.05
	max_pitch = 0.4
	min_distance = 0.6
	auto_orbit = 0.05
	_ground_plane(Color(0.24, 0.3, 0.11), 300.0, Color(0.55, 0.5, 0.3))
	Grass.field(_scene, Rect2(-12, -12, 24, 24), 1.0, {
		"seed": 3, "flowers": 0.0, "blade_height": 0.5,
		"ground": Color(0.2, 0.25, 0.09), "body": Color(0.28, 0.36, 0.12), "tip": Color(0.48, 0.48, 0.2), "translucency": 0.12,
		"dry": Color(0.62, 0.48, 0.22), "dryness": 0.4,
	})
	var tree := LeafyTree.oak()
	tree.height = 9.0
	tree.seed = 4
	var node := tree.instance()
	node.position = Vector3(-6, 0, -9)
	_scene.add_child(node)
	# a fence post the gnats dance beside
	_shape(_box(Vector3(0.14, 1.4, 0.14)), Vector3(0.9, 0.7, -0.6), _mat(Color(0.4, 0.32, 0.24)))


func _field() -> void:
	set_sky(Color(0.32, 0.52, 0.8), Color(0.82, 0.86, 0.85))
	environment.ambient_light_color = Color(0.62, 0.68, 0.74)
	environment.ambient_light_energy = 0.5
	environment.fog_enabled = true
	environment.fog_density = 0.0025
	environment.fog_light_color = Color(0.7, 0.76, 0.8)
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-130), 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 0.95
	sun.directional_shadow_max_distance = 70.0
	flock.position = Vector3.ZERO
	focus = Vector3(0, 0, 0)
	distance = 32.0
	yaw = 0.5
	pitch = -0.6
	max_pitch = -0.05
	_ground_plane(Color(0.17, 0.26, 0.08), 400.0, Color(0.36, 0.45, 0.26))
	Grass.field(_scene, Rect2(-30, -30, 60, 60), 0.7, {
		"seed": 9, "flowers": 0.02, "blade_height": 0.22,
		"ground": Color(0.17, 0.26, 0.08), "body": Color(0.24, 0.36, 0.1), "tip": Color(0.45, 0.55, 0.22), "translucency": 0.1,
	})
	var post := _mat(Color(0.4, 0.32, 0.24))
	var rail := _mat(Color(0.5, 0.42, 0.32))
	var e := 27.0
	for side in 4:
		for k in 19:
			var t := -e + k * 3.0
			var at := [Vector3(t, 0, -e), Vector3(e, 0, t), Vector3(-t, 0, e), Vector3(-e, 0, -t)][side] as Vector3
			_shape(_box(Vector3(0.18, 1.2, 0.18)), at + Vector3(0, 0.6, 0), post)
		var along := Vector3(1, 0, 0) if side % 2 == 0 else Vector3(0, 0, 1)
		var mid := [Vector3(0, 0, -e), Vector3(e, 0, 0), Vector3(0, 0, e), Vector3(-e, 0, 0)][side] as Vector3
		for h: float in [0.55, 0.95]:
			var r := _shape(_box(Vector3(e * 2.0, 0.08, 0.06)), mid + Vector3(0, h, 0), rail)
			if side % 2 == 1:
				r.rotation.y = PI / 2.0
	for spot: Vector3 in [Vector3(-8, 0, -6), Vector3(10, 0, 8), Vector3(14, 0, -12)]:
		var tree := LeafyTree.oak()
		tree.height = 8.0 + spot.x * 0.05
		tree.seed = int(spot.z) + 20
		var node := tree.instance()
		node.position = spot
		_scene.add_child(node)
		var trunk := Node3D.new()
		trunk.position = spot
		_scene.add_child(trunk)
		_scene_obstacle(trunk, 1.6)


# What the hawk (and the finger, chasing) looks like here: a hawk, a shark, a sheepdog.
func _hawk_body() -> void:
	for c in _hawk.get_children():
		c.queue_free()
	for c in _chaser.get_children():
		c.queue_free()
	for holder: Node3D in [_hawk, _chaser]:
		var mi := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		match preset:
			1:
				mi.mesh = Flock.body_mesh(FlockRules.Body.FISH)
				m.albedo_color = Color(0.45, 0.5, 0.55)
				mi.scale = Vector3.ONE * 2.6
			4:
				mi.mesh = _ball(0.06, 8)
				m.albedo_color = Color(0.2, 0.5, 0.25)
			5:
				mi.mesh = Flock.body_mesh(FlockRules.Body.SHEEP)
				m.albedo_color = Color(0.2, 0.16, 0.14)
				mi.scale = Vector3(0.75, 0.75, 0.9)
			_:
				mi.mesh = Flock.body_mesh(FlockRules.Body.BIRD)
				m.albedo_color = Color(0.32, 0.22, 0.16)
				mi.scale = Vector3.ONE * (1.2 if preset != 0 else 0.8)
		mi.material_override = m
		holder.add_child(mi)


# --- the hawk ----------------------------------------------------------------------

func _new_hawk_pass() -> void:
	_hawk_t = -_rng.randf_range(1.0, HAWK_EVERY * 0.5)
	_hawk.visible = false
	_hawk.remove_from_group(&"flock_predators")


func _hawk_step(delta: float) -> void:
	if not hawk_on:
		_hawk.visible = false
		_hawk.remove_from_group(&"flock_predators")
		return
	var r := rules
	var reach := maxf(r.bounds_size.x, r.bounds_size.z) * 1.4 + 4.0
	var speed := maxf(r.max_speed * 1.5, 2.0)
	var span := 2.0 * reach / speed
	if _hawk_t < 0.0:
		_hawk_t += delta
		if _hawk_t >= 0.0:
			# a pass through the middle of them, from somewhere off to one side
			var a := _rng.randf() * TAU
			var mid := flock.centre()
			var off := Vector3(cos(a), 0.0, sin(a)) * reach
			if not r.planar:
				off.y = _rng.randf_range(-0.2, 0.4) * reach
			_hawk_from = mid + off
			_hawk_to = mid - off
			if r.planar:
				_hawk_from.y = flock.ground_y
				_hawk_to.y = flock.ground_y
			_hawk.visible = true
			_hawk.add_to_group(&"flock_predators")
		return
	_hawk_t += delta
	var u := _hawk_t / span
	if u >= 1.0:
		_hawk_t = -HAWK_EVERY * _rng.randf_range(0.6, 1.2)
		_hawk.visible = false
		_hawk.remove_from_group(&"flock_predators")
		return
	var p := _hawk_from.lerp(_hawk_to, u)
	if not r.planar:
		p.y -= sin(u * PI) * reach * 0.1
	var ahead := (_hawk_to - _hawk_from).normalized()
	_hawk.position = p
	if ahead.length_squared() > 0.001:
		_hawk.basis = Basis.looking_at(ahead, Vector3.UP)


# --- the finger --------------------------------------------------------------------

# Where a finger points: on the ground for a herd, else on the plane facing the camera
# through their goal.
func _point(pos: Vector2) -> Variant:
	if rules.planar:
		return ground(pos, flock.ground_y)
	var rr := ray(pos)
	var through := flock.goal_point()
	var plane := Plane(-camera.global_basis.z, through)
	return plane.intersects_ray(rr.from, rr.dir)


func poke_down(pos: Vector2) -> void:
	_press = {at = pos, time = 0.0, moved = false, chasing = false}


func poke_move(pos: Vector2) -> void:
	if _press.is_empty():
		return
	if pos.distance_to(_press.at) > MOVE_PX:
		_press.moved = true
	_press.last = pos
	if _press.chasing:
		_move_chaser(pos)
	elif _press.moved and tool == 0:
		_start_chase(pos)


func poke_up(pos: Vector2) -> void:
	if _press.is_empty():
		return
	if _press.chasing:
		_chaser.visible = false
		_chaser.remove_from_group(&"flock_predators")
	elif not _press.moved:
		var p: Variant = _point(pos)
		if p != null:
			if tool == 0:
				flock.target = p
				_goal_marker.position = p
			else:
				_add_obstacle(p, rules.size * 4.0 + (1.5 if rules.planar else 1.0) * rules.perception * 0.6)
	_press = {}


func _start_chase(pos: Vector2) -> void:
	_press.chasing = true
	_chaser.visible = true
	_chaser.add_to_group(&"flock_predators")
	_move_chaser(pos)
	var p: Variant = _point(pos)
	if p != null:
		flock.scatter(p, 0.6)


func _move_chaser(pos: Vector2) -> void:
	var p: Variant = _point(pos)
	if p == null:
		return
	var to: Vector3 = p
	var step := to - _chaser.position
	_chaser.position = to
	step.y = 0.0 if rules.planar else step.y
	if step.length() > 0.02:
		_chaser.basis = Basis.looking_at(step.normalized(), Vector3.UP)


func _add_obstacle(at: Vector3, radius: float) -> void:
	radius = maxf(radius, 0.15)
	var rock := MeshInstance3D.new()
	rock.mesh = _ball(radius, 10)
	rock.material_override = _rock_mat
	rock.position = at
	if rules.planar:
		rock.scale = Vector3(1, 0.6, 1)
	world.add_child(rock)
	_user_obstacles.append(rock)
	_scene_obstacle(rock, radius)


func _add_random_obstacles() -> void:
	var r := rules
	for k in 3:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.2, 0.6) * r.bounds_size.x
		var at := flock.global_position + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if r.planar:
			at.y = flock.ground_y
		else:
			at.y += _rng.randf_range(-0.4, 0.4) * r.bounds_size.y
		_add_obstacle(at, maxf(r.perception * 0.7, r.size * 3.0))


func _clear_obstacles() -> void:
	for o in _user_obstacles:
		o.queue_free()
	_user_obstacles.clear()


# --- every frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if wind_speed > 0.0:
		field.step()
	if not _press.is_empty():
		_press.time += delta
		if not _press.chasing and tool == 0 and _press.time > HOLD:
			_start_chase(_press.get("last", _press.at))
	_hawk_step(delta)
	_goal_marker.visible = flock.target.is_finite()
	if _goal_marker.visible:
		_goal_marker.position = flock.target
		_goal_marker.scale = Vector3.ONE * clampf(rules.size * 3.0, 0.08, 1.2) * (1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.006))
	flock.watch = 0 if (show_perception or show_neighbours) else -1
	_draw_debug()


func _draw_debug() -> void:
	_lines.clear_surfaces()
	if not (show_perception or show_neighbours or show_velocity or show_bounds) or flock.boid_count() == 0:
		return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var r := rules
	if show_bounds:
		_draw_bounds(Color(0.5, 0.85, 1.0, 0.7))
	if show_velocity:
		var pos := flock.positions()
		var vel := flock.velocities()
		var k := 0.25 if r.max_speed > 3.0 else 0.6
		for i in pos.size():
			var c := Color(1, 1, 1, 0.7).lerp(Color(1.0, 0.2, 0.15, 0.9), flock.fear_of(i))
			_line(pos[i], pos[i] + vel[i] * k, c)
	if flock.watch >= 0:
		var me := flock.boid_position(flock.watch)
		var yellow := Color(1.0, 0.9, 0.2, 0.9)
		if show_perception:
			var cam := camera.global_basis
			_circle(me, cam.x, cam.y, r.perception, yellow)
			if not r.planar:
				_circle(me, Vector3.RIGHT, Vector3.FORWARD, r.perception, Color(yellow, 0.4))
			else:
				_circle(me, Vector3.RIGHT, Vector3.FORWARD, r.perception, yellow)
			_circle(me, cam.x, cam.y, r.separation_distance, Color(1.0, 0.5, 0.2, 0.9))
			# its field of view: the two edges of the blind spot behind it
			var v := flock.velocities()[flock.watch]
			if v.length() > 0.01 and r.field_of_view < 359.0:
				var f := v.normalized()
				var side := f.cross(Vector3.UP).normalized() if absf(f.y) < 0.99 else Vector3.RIGHT
				var half := deg_to_rad(r.field_of_view * 0.5)
				for s: float in [-1.0, 1.0]:
					var edge := f.rotated(Vector3.UP if r.planar else f.cross(side).normalized(), s * half)
					_line(me, me + edge * r.perception, Color(1.0, 0.9, 0.2, 0.5))
		if show_neighbours:
			for j in flock.watched:
				_line(me, flock.boid_position(j), Color(0.4, 1.0, 0.5, 0.95))
		var mark := clampf(r.size * 1.5, 0.05, 2.0)
		var cam2 := camera.global_basis
		_circle(me, cam2.x, cam2.y, mark, Color(1, 1, 1, 1))
	_lines.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_lines.surface_set_color(c)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(c)
	_lines.surface_add_vertex(b)


func _circle(at: Vector3, u: Vector3, v: Vector3, radius: float, c: Color, steps := 40) -> void:
	for k in steps:
		var a0 := TAU * k / steps
		var a1 := TAU * (k + 1) / steps
		_line(at + (u * cos(a0) + v * sin(a0)) * radius, at + (u * cos(a1) + v * sin(a1)) * radius, c)


func _draw_bounds(c: Color) -> void:
	var r := rules
	var o := flock.global_position
	var h := r.bounds_size
	if r.bounds == FlockRules.Bounds.SPHERE:
		_circle(o, Vector3.RIGHT, Vector3.FORWARD, h.x, c, 64)
		_circle(o, Vector3.RIGHT, Vector3.UP, h.x, c, 64)
		_circle(o, Vector3.FORWARD, Vector3.UP, h.x, c, 64)
		return
	var lo_y := o.y - h.y
	var hi_y := o.y + h.y
	if r.bounds == FlockRules.Bounds.LAYER or r.planar:
		lo_y = flock.ground_y + r.ground_clearance
		hi_y = flock.ground_y + r.ceiling if r.ceiling > 0.0 else lo_y
	var xs := [o.x - h.x, o.x + h.x]
	var zs := [o.z - h.z, o.z + h.z]
	for y: float in [lo_y, hi_y]:
		_line(Vector3(xs[0], y, zs[0]), Vector3(xs[1], y, zs[0]), c)
		_line(Vector3(xs[1], y, zs[0]), Vector3(xs[1], y, zs[1]), c)
		_line(Vector3(xs[1], y, zs[1]), Vector3(xs[0], y, zs[1]), c)
		_line(Vector3(xs[0], y, zs[1]), Vector3(xs[0], y, zs[0]), c)
	if hi_y > lo_y:
		for x: float in xs:
			for z: float in zs:
				_line(Vector3(x, lo_y, z), Vector3(x, hi_y, z), c)
	# the margin, where they begin to turn back
	var m := r.bounds_margin
	var mc := Color(c, c.a * 0.35)
	var y2 := (lo_y + hi_y) * 0.5
	_line(Vector3(xs[0] + m, y2, zs[0] + m), Vector3(xs[1] - m, y2, zs[0] + m), mc)
	_line(Vector3(xs[1] - m, y2, zs[0] + m), Vector3(xs[1] - m, y2, zs[1] - m), mc)
	_line(Vector3(xs[1] - m, y2, zs[1] - m), Vector3(xs[0] + m, y2, zs[1] - m), mc)
	_line(Vector3(xs[0] + m, y2, zs[1] - m), Vector3(xs[0] + m, y2, zs[0] + m), mc)
