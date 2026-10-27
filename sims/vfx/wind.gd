extends Sim3D
## Wind: GameCommon's wind (one WindField) moving everything in a meadow. The grass (GameCommon's
## Grass, kept in step by field.apply_grass) and the trees (LeafyTree and PineTree meshes swayed
## by the field's sway materials) work the wind out in their shaders from the same numbers;
## leaves and thistledown (WindDebris), ribbons (WindRibbons), the flag (WindFlag) and the vector
## grid ask the field. A poke sets off a blast. Export saves the wind as a .tres preset.

const FLAG_AT := Vector3(-3.5, 0, 4.0)

var field := WindField.new()
var grass: Grass
var flag := WindFlag.new()
var leaves := WindDebris.new()
var seeds := WindDebris.new()
var streaks := WindRibbons.new()
var vectors := MeshInstance3D.new()
var vector_mesh := ImmediateMesh.new()
var rings: Array = [] # [MeshInstance3D, age]
var blast_strength := 1.5
var show_vectors := false


func pokeable() -> bool:
	return true


func hint() -> String:
	return "One wind moves everything here. Set Finger to Poke and tap to set off a blast."


func help() -> String:
	return "A single wind field (GameCommon's wind) drives the whole meadow. Gusts are noise rolling downwind; " \
		+ "the grass and trees work them out in their vertex shaders from the same formula the CPU uses " \
		+ "for the leaves, thistledown, ribbons and flag, so a gust you see crossing the grass is the " \
		+ "one that tears leaves off the next tree. Turbulence adds swirling eddies. A blast is a ring " \
		+ "of air running out at 9 m/s that lays the grass flat, throws the trees back and lifts the " \
		+ "fallen leaves.\n\nLook: one finger orbits, two pinch and pan, the wheel zooms.\n" \
		+ "Poke: tap the ground to set off a blast. Vectors shows the field as arrows.\n\n" \
		+ "Export saves this wind as a WindField preset (.tres) for any project (needs godot/wind)."


func build() -> void:
	set_sky(Color(0.32, 0.5, 0.78), Color(0.86, 0.82, 0.72))
	environment.fog_enabled = true
	environment.fog_density = 0.007
	environment.fog_light_color = Color(0.68, 0.74, 0.78)
	environment.fog_sky_affect = 0.0
	environment.ambient_light_color = Color(0.6, 0.66, 0.72)
	environment.ambient_light_energy = 0.45
	sun.rotation = Vector3(deg_to_rad(-32), deg_to_rad(-140), 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.0
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_opacity = 0.75
	sun.shadow_blur = 1.5
	focus = Vector3(0, 2.0, 0)
	distance = 23.0
	pitch = -0.33
	yaw = -0.35
	min_distance = 2.0
	max_distance = 45.0
	max_pitch = -0.02
	auto_orbit = 0.04

	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 240)
	plane.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://sims/vfx/grass_ground.gdshader")
	gm.set_shader_parameter(&"ground", Color(0.24, 0.3, 0.11))
	gm.set_shader_parameter(&"far_colour", Color(0.4, 0.47, 0.3))
	plane.material_override = gm
	world.add_child(plane)

	grass = Grass.field(world, Rect2(-40, -40, 80, 80), 1.0, {
		"seed": 5, "flowers": 0.05, "blade_height": 0.6,
		"ground": Color(0.24, 0.3, 0.11), "body": Color(0.4, 0.5, 0.15), "tip": Color(0.66, 0.68, 0.3), "translucency": 0.12,
		"dry": Color(0.72, 0.55, 0.24), "dryness": 0.5,
		"mask": func(p: Vector2) -> float: return 0.0 if p.distance_to(Vector2(FLAG_AT.x, FLAG_AT.z)) < 0.4 else 1.0,
	})
	field.apply_grass(grass)

	var tree_mat := field.sway_material()
	var trees := [
		[LeafyTree.oak(), Vector3(6, 0, -6), 9.0, Color(0, 0, 0, 0)],
		[LeafyTree.cottonwood(), Vector3(-8, 0, -11), 12.0, Color(0.95, 0.72, 0.2, 0.25)],
		[LeafyTree.willow(), Vector3(13, 0, 2), 8.0, Color(0, 0, 0, 0)],
		[LeafyTree.aspen(), Vector3(-14, 0, -2), 10.0, Color(0.98, 0.78, 0.15, 0.3)],
		[LeafyTree.aspen(), Vector3(-16, 0, 1.5), 8.5, Color(0.98, 0.78, 0.15, 0.3)],
	]
	var crowns: Array = []
	var k := 0
	for t: Array in trees:
		var shape: LeafyTree = t[0]
		shape.height = t[2]
		shape.seed = 10 + k
		if t[3].a > 0.0:
			shape.accent = t[3]
		shape.material = tree_mat
		var node := shape.instance()
		node.position = t[1]
		node.rotation.y = k * 1.7
		world.add_child(node)
		crowns.append([t[1] + Vector3.UP * t[2] * 0.7, t[2] * 0.25])
		k += 1
	# pines are stiffer than broadleaf trees
	var pine_mat := field.sway_material(11.0, 0.46)
	for p: Vector3 in [Vector3(16, 0, -14), Vector3(19, 0, -10), Vector3(-20, 0, -18)]:
		var pine := PineTree.new()
		pine.height = 11.0
		pine.seed = int(p.x)
		pine.material = pine_mat
		var node := pine.instance()
		node.position = p
		world.add_child(node)

	# a flagpole, so the wind's strength and heading read at a glance
	flag.field = field
	flag.position = FLAG_AT
	world.add_child(flag)

	leaves.field = field
	leaves.crowns = crowns
	world.add_child(leaves)
	seeds.field = field
	seeds.kind = WindDebris.Kind.SEED
	seeds.count = 160
	world.add_child(seeds)
	streaks.field = field
	world.add_child(streaks)

	vectors.mesh = vector_mesh
	vectors.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.vertex_color_use_as_albedo = true
	vm.no_depth_test = true
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	vm.disable_fog = true
	vectors.material_override = vm
	vectors.visible = false
	world.add_child(vectors)


func status() -> String:
	var at := flag.air()
	var heading := fposmod(rad_to_deg(atan2(at.z, at.x)), 360.0)
	return "flag %.1f m/s @ %03.0f°  leaves aloft %d  streaks %d  %.1f ms" % [
		Vector2(at.x, at.z).length(), heading, leaves.aloft(), streaks.heads.size(), frame_ms()]


func controls() -> Array:
	var list := look_controls()
	list.append_array([
		{type = "section", label = "Wind"},
		{type = "slider", label = "Speed", min = 0.0, max = 20.0, step = 0.5, value = field.speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: field.speed = v},
		{type = "slider", label = "Direction", min = 0.0, max = 360.0, step = 5.0, value = field.direction, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: field.direction = v},
		{type = "slider", label = "Gustiness", min = 0.0, max = 1.0, step = 0.05, value = field.gustiness, fmt = "%.2f",
			on = func(v: float) -> void: field.gustiness = v},
		{type = "slider", label = "Gust front", min = 4.0, max = 40.0, step = 1.0, value = field.gust_size, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void: field.gust_size = v},
		{type = "slider", label = "Turbulence", min = 0.0, max = 1.0, step = 0.05, value = field.turbulence, fmt = "%.2f",
			on = func(v: float) -> void: field.turbulence = v},
		{type = "section", label = "Blast"},
		{type = "slider", label = "Strength", min = 0.5, max = 3.0, step = 0.1, value = blast_strength, fmt = "%.1f",
			on = func(v: float) -> void: blast_strength = v},
		{type = "button", label = "Blast centre", on = func() -> void: _blast(Vector3.ZERO)},
		{type = "section", label = "Carried"},
		{type = "slider", label = "Leaves", min = 0.0, max = 1.0, step = 0.05, value = leaves.amount, fmt = "%.2f",
			on = func(v: float) -> void: leaves.amount = v},
		{type = "slider", label = "Seeds", min = 0.0, max = 1.0, step = 0.05, value = seeds.amount, fmt = "%.2f",
			on = func(v: float) -> void: seeds.amount = v},
		{type = "section", label = "Display"},
		{type = "toggle", label = "Streaks", value = streaks.visible, on = func(on: bool) -> void: streaks.visible = on},
		{type = "toggle", label = "Vectors", value = show_vectors, on = func(on: bool) -> void:
			show_vectors = on
			vectors.visible = on},
		{type = "choice", label = "Grass quality", options = ["Low", "Medium", "High"], value = Grass.quality,
			on = func(i: int) -> void: Grass.set_quality(i)},
	])
	list.append_array(Exporter.controls("Breeze", _export, "wind", func(line: String) -> void: say.emit(line)))
	return list


func _export(name: String) -> void:
	var out := WindField.new()
	for p in ["speed", "direction", "gustiness", "gust_size", "turbulence"]:
		out.set(p, field.get(p))
	var slug := Exporter.slug(name)
	say.emit(Exporter.save("wind", name, {"tres": out}, ["godot/wind"],
		"var wind := load(\"res://assets/wind/%s.tres\") as WindField\n" % slug
		+ "tree.material = wind.sway_material(tree_height)   # trees sway; wind.apply_grass(grass); wind.sample(p) for the rest\n"
		+ "var flag := WindFlag.new(); flag.field = wind; add_child(flag)", "Wind"))


func _blast(at: Vector3) -> void:
	field.blast(at, blast_strength)
	# a faint ring on the ground running out with the blast
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 48
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.5)
	m.disable_fog = true
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = at + Vector3.UP * 0.3
	world.add_child(ring)
	rings.append([ring, 0.0])


func poke_down(pos: Vector2) -> void:
	var p: Variant = ground(pos)
	if p != null:
		_blast(p)


func _process(delta: float) -> void:
	super._process(delta)
	field.step()
	streaks.around = focus
	for r: Array in rings:
		r[1] += delta
		var radius: float = r[1] * WindField.BLAST_SPEED
		r[0].scale = Vector3(radius, 1.0, radius)
		r[0].material_override.albedo_color.a = 0.5 * (1.0 - r[1] / WindField.BLAST_LIFE)
		if r[1] >= WindField.BLAST_LIFE:
			r[0].queue_free()
	rings = rings.filter(func(r: Array) -> bool: return r[1] < WindField.BLAST_LIFE)
	if show_vectors:
		_draw_vectors()


func _draw_vectors() -> void:
	vector_mesh.clear_surfaces()
	vector_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 3.0
	var eye := camera.global_position
	for gz in range(-7, 8):
		for gx in range(-7, 8):
			var p := Vector3(gx * step, 1.5, gz * step)
			var v: Vector3 = field.sample(p)
			var len := v.length()
			if len < 0.05:
				continue
			# blue calm, yellow 10 m/s, red 20
			var c := Color(0.3, 0.6, 1.0).lerp(Color(1.0, 0.85, 0.15), clampf(len / 10.0, 0.0, 1.0))
			c = c.lerp(Color(1.0, 0.2, 0.15), clampf((len - 10.0) / 10.0, 0.0, 1.0))
			var along := v / len
			var tip := p + v * minf(0.16, 2.6 / len)
			var side := along.cross(eye - p).normalized()
			var neck := tip - along * 0.45
			var corners := [p + side * 0.05, neck + side * 0.05, neck - side * 0.05,
				p + side * 0.05, neck - side * 0.05, p - side * 0.05,
				neck + side * 0.22, tip, neck - side * 0.22]
			for q: Vector3 in corners:
				vector_mesh.surface_set_color(c)
				vector_mesh.surface_add_vertex(q)
	vector_mesh.surface_end()
