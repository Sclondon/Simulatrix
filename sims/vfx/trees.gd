extends Sim3D
## Tree Lab: one generated tree on a turntable, every setting of GameCommon's PineTree and LeafyTree
## on a slider. The sliders are modifiers over the chosen species' preset (100% is the preset), so
## a species change keeps them. The tree is rebuilt at most every REBUILD seconds while a slider
## moves; the forest round it, once the sliders have been still for FOREST_WAIT.

const SWAY := preload("res://sims/vfx/trees_sway.gdshader")
const GRID := preload("res://sims/vfx/trees_grid.gdshader")
const SPECIES := ["Fir", "Spruce", "Snowy", "Lodgepole", "Sapling", "Oak", "Aspen", "Cottonwood", "Willow", "Pinyon"]
## PineTree settings for the pine species (as the component's example.gd)
const PINES := [
	{},
	{droop = 0.85, spread = 0.36, whorls = 15, branches = 9, taper = 0.9},
	{snow = 0.8, droop = 0.6, needles_outer = Color(0.2, 0.36, 0.26)},
	{spread = 0.22, crown_base = 0.45, whorls = 8, droop = 0.2, height = 13.0},
	{height = 3.5, whorls = 6, branches = 6, sprigs = 1},
]
const PLINTH := 0.25
const REBUILD := 0.12
const FOREST_WAIT := 0.5

var species := 5
var tree_seed := 1
var view := 0
var shading := 1
var wind := 0.35
var spin := true
var forest_on := false
var mods := {height = 1.0, girth = 1.0, width = 1.0, base = 0.0, branches = 1.0, droop = 0.0,
	foliage = 1.0, detail = 1.0, wild = 0.0, lean = 0.0, autumn = 0.0, snow = 0.0}

var tree_mat := ShaderMaterial.new()
var wire_mat := ShaderMaterial.new()
var turntable := Node3D.new()
var tree := MeshInstance3D.new()
var wire := MeshInstance3D.new()
var forest := Node3D.new()

var _made: Resource
var _dirty := true
var _forest_dirty := false
var _since := 1.0
var _still := 0.0
var _build_ms := 0.0
var _tris := 0
var _forest_tris := 0
var _forest_draws := 0


func help() -> String:
	return ("A tree grown from code, as the games grow theirs: GameCommon's PineTree (fir, spruce, lodgepole, sapling) "
		+ "and LeafyTree (oak, aspen, cottonwood, willow, pinyon). Pick a species, then bend its settings: the sliders are "
		+ "modifiers on that species' preset. The same settings and seed always make the same tree.\n\n"
		+ "View shows what the games' shaders use: Normals are bent out from the trunk so the crown shades as one soft shape; "
		+ "Sway is how much each corner moves in the wind (UV2.y on leafy trees); Wire shows the triangles.\n\n"
		+ "Forest plants a wood of the current tree: a MultiMesh per variant, plainer trees far off.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom, two fingers to pan.")


func hint() -> String:
	return "Pick a species, then drag the sliders. Drag the view to orbit."


func status() -> String:
	var s := "%s · seed %d · %.1fk tris · built %d ms" % [SPECIES[species], tree_seed, _tris / 1000.0, roundi(_build_ms)]
	if forest_on and _forest_draws > 0:
		s += " · forest %d draws" % _forest_draws
	return s


func build() -> void:
	set_sky(Color("5d7894"), Color("b9c3cc"), Color("2a2c30"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.68, 0.78)
	environment.ambient_light_energy = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("aeb8c2")
	environment.fog_density = 0.006
	# over the camera's left shoulder, so the crown is lit with its shading turning away to the right
	sun.look_at_from_position(Vector3(-3, 10, 9), Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.5
	sun.shadow_blur = 1.5
	tree_mat.shader = SWAY
	wire_mat.shader = SWAY
	wire_mat.set_shader_parameter("view", 4)
	tree_mat.set_shader_parameter("toon", float(shading))
	# the floor: an editor grid, and a turntable to stand the tree on
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(240, 240)
	var ground_node := MeshInstance3D.new()
	ground_node.mesh = floor_mesh
	var grid := ShaderMaterial.new()
	grid.shader = GRID
	ground_node.material_override = grid
	ground_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground_node)
	var plinth := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.4
	cyl.bottom_radius = 2.5
	cyl.height = PLINTH
	cyl.radial_segments = 48
	plinth.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("2a2c31")
	pm.roughness = 0.85
	plinth.material_override = pm
	plinth.position.y = PLINTH * 0.5
	world.add_child(plinth)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.38
	torus.outer_radius = 2.46
	torus.rings = 48
	rim.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color("e0a03a")
	rim.material_override = rm
	rim.position.y = PLINTH
	rim.scale.y = 0.3
	world.add_child(rim)
	turntable.position.y = PLINTH
	world.add_child(turntable)
	turntable.add_child(tree)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wire.material_override = wire_mat
	turntable.add_child(wire)
	world.add_child(forest)
	_rebuild()
	_frame()


func controls() -> Array:
	var c: Array = [
		{type = "section", label = "Preset"},
		{type = "choice", label = "Species", options = SPECIES, value = species, on = func(i: int) -> void:
			species = i
			_touch()
			_rebuild()
			_frame()},
		{type = "slider", label = "Seed", min = 1, max = 9999, step = 1, value = tree_seed, fmt = "%d",
			on = func(v: float) -> void: tree_seed = int(v); _touch()},
		{type = "button", label = "Randomize", on = _randomize},
		{type = "button", label = "Reset", on = _reset},
		{type = "section", label = "Trunk"},
		_mod("Height", "height", 0.5, 1.6),
		_mod("Girth", "girth", 0.5, 2.0),
		_offset("Lean", "lean", 0.0, 0.3),
		{type = "section", label = "Crown"},
		_mod("Width", "width", 0.5, 1.7),
		_offset("Base", "base", -0.3, 0.3),
		_mod("Branches", "branches", 0.4, 2.0),
		_offset("Droop", "droop", -0.6, 1.0),
		_offset("Wildness", "wild", -0.4, 0.6),
		{type = "section", label = "Leaves"},
		_mod("Clump size", "foliage", 0.5, 1.7),
		_mod("Detail", "detail", 0.0, 2.0),
		_offset("Autumn", "autumn", 0.0, 1.0),
		_offset("Snow", "snow", 0.0, 1.0),
		{type = "section", label = "Wind"},
		{type = "slider", label = "Strength", min = 0.0, max = 1.5, step = 0.05, value = wind, fmt = "%.2f",
			on = func(v: float) -> void:
				wind = v
				_set_all("wind", v)},
		{type = "section", label = "Scene"},
		{type = "toggle", label = "Spin", value = spin, on = func(on: bool) -> void: spin = on},
		{type = "toggle", label = "Forest", value = forest_on, on = func(on: bool) -> void:
			forest_on = on
			_forest_dirty = true
			_still = FOREST_WAIT},
		{type = "button", label = "Frame", on = _frame},
		{type = "section", label = "Display"},
		{type = "choice", label = "Shading", options = ["Soft", "Toon"], value = shading,
			on = func(i: int) -> void:
				shading = i
				tree_mat.set_shader_parameter("toon", float(i))},
		{type = "choice", label = "View", options = ["Shaded", "Normals", "Sway", "Wire"], value = view,
			on = func(i: int) -> void:
				view = i
				_apply_view()},
	]
	return c


## A slider that scales a setting of the preset (100% is the preset's own).
func _mod(label: String, key: String, lo: float, hi: float) -> Dictionary:
	return {type = "slider", label = label, min = lo * 100.0, max = hi * 100.0, step = 5, value = mods[key] * 100.0,
		fmt = "%d", unit = "%", on = func(v: float) -> void:
			mods[key] = v / 100.0
			_touch()}


## A slider that adds to a setting of the preset.
func _offset(label: String, key: String, lo: float, hi: float) -> Dictionary:
	return {type = "slider", label = label, min = lo, max = hi, step = 0.02, value = mods[key], fmt = "%+.2f",
		on = func(v: float) -> void:
			mods[key] = v
			_touch()}


func _touch() -> void:
	_dirty = true
	_still = 0.0
	if forest_on:
		_forest_dirty = true


func _randomize() -> void:
	tree_seed = randi_range(1, 9999)
	_touch()


func _reset() -> void:
	for k in mods:
		mods[k] = 0.0 if k in ["base", "droop", "wild", "lean", "autumn", "snow"] else 1.0
	_touch()


func _set_all(param: String, value: Variant) -> void:
	tree_mat.set_shader_parameter(param, value)
	wire_mat.set_shader_parameter(param, value)


func _process(delta: float) -> void:
	super(delta)
	if spin:
		turntable.rotate_y(delta * 0.25)
	_since += delta
	_still += delta
	if _dirty and _since >= REBUILD:
		_rebuild()
	if _forest_dirty and _still >= FOREST_WAIT and not _dirty:
		_build_forest()


# --- making the tree ---------------------------------------------------------

func _is_pine() -> bool:
	return species < PINES.size()


## The current species with the modifiers applied, as a PineTree or LeafyTree.
func _make() -> Resource:
	var m := mods
	if _is_pine():
		var p := PineTree.new()
		var preset: Dictionary = PINES[species]
		for k in preset:
			p.set(k, preset[k])
		p.height *= m.height
		p.trunk_radius *= m.girth
		p.spread = clampf(p.spread * m.width, 0.15, 1.0)
		p.crown_base = clampf(p.crown_base + m.base, 0.0, 0.8)
		p.whorls = clampi(roundi(p.whorls * m.branches), 3, 30)
		p.branches = clampi(roundi(p.branches * lerpf(1.0, m.branches, 0.5)), 3, 14)
		p.droop = clampf(p.droop + m.droop, 0.0, 1.0)
		p.fullness = clampf(p.fullness * m.foliage, 0.1, 0.8)
		p.sprigs = clampi(roundi(p.sprigs * m.detail), 0, 4)
		p.wildness = clampf(p.wildness + m.wild, 0.0, 1.0)
		p.lean = clampf(p.lean + m.lean, 0.0, 0.3)
		p.snow = clampf(p.snow + m.snow, 0.0, 1.0)
		# autumn on a conifer: a larch going gold
		p.needles_inner = p.needles_inner.lerp(Color(0.32, 0.2, 0.07), m.autumn)
		p.needles_outer = p.needles_outer.lerp(Color(0.72, 0.5, 0.14), m.autumn)
		p.tips = p.tips.lerp(Color(0.92, 0.7, 0.25), m.autumn)
		p.seed = tree_seed
		p.material = tree_mat
		return p
	var t: LeafyTree
	match SPECIES[species]:
		"Aspen": t = LeafyTree.aspen()
		"Cottonwood": t = LeafyTree.cottonwood()
		"Willow": t = LeafyTree.willow()
		"Pinyon": t = LeafyTree.pinyon()
		_: t = LeafyTree.oak()
	t.height *= m.height
	t.trunk_radius *= m.girth
	t.spread = clampf(t.spread * m.width, 0.15, 1.6)
	t.crown_base = clampf(t.crown_base + m.base, 0.05, 0.9)
	t.limbs = clampi(roundi(t.limbs * lerpf(1.0, m.branches, 0.6)), 1, 7)
	t.clumps = clampi(roundi(t.clumps * m.branches), 3, 48)
	t.weep = clampf(t.weep + m.droop, 0.0, 1.0)
	t.clump_size = clampf(t.clump_size * m.foliage, 0.12, 0.7)
	t.tufts = clampi(roundi(t.tufts * m.detail), 0, 14)
	t.wildness = clampf(t.wildness + m.wild, 0.0, 1.0)
	t.lean = clampf(t.lean + m.lean, 0.0, 0.3)
	t.leaves_dark = t.leaves_dark.lerp(Color(0.38, 0.13, 0.04), m.autumn)
	t.leaves = t.leaves.lerp(Color(0.84, 0.4, 0.1), m.autumn)
	t.leaves_light = t.leaves_light.lerp(Color(1.0, 0.74, 0.24), m.autumn)
	if m.autumn > 0.0:
		t.accent = Color(0.72, 0.12, 0.06, maxf(t.accent.a, m.autumn * 0.3))
	# snow on a broadleaf: a frost settling on the light tops
	t.leaves_light = t.leaves_light.lerp(Color(0.92, 0.95, 1.0), m.snow * 0.8)
	t.seed = tree_seed
	t.material = tree_mat
	return t


func _rebuild() -> void:
	_dirty = false
	_since = 0.0
	# every slider step is a new key in the components' mesh caches: keep only what is in use
	PineTree._cache.clear()
	LeafyTree._cache.clear()
	var t0 := Time.get_ticks_usec()
	_made = _make()
	tree.mesh = _made.mesh()
	tree.material_override = tree_mat
	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_tris = _count(tree.mesh)
	_set_all("pine", 1.0 if _is_pine() else 0.0)
	_set_all("tree_height", _made.height)
	if view == 3:
		_build_wire()


func _count(mesh: Mesh) -> int:
	if not mesh or mesh.get_surface_count() == 0:
		return 0
	var idx: int = mesh.surface_get_array_index_len(0)
	return (idx if idx > 0 else mesh.surface_get_array_len(0)) / 3


func _frame() -> void:
	var h: float = _made.height if _made else 8.0
	focus = Vector3(0, PLINTH + h * 0.45, 0)
	distance = clampf(h * 1.55 + 3.0, min_distance, max_distance)
	pitch = -0.2
	_place_camera()


# --- views -------------------------------------------------------------------

func _apply_view() -> void:
	tree_mat.set_shader_parameter("view", view)
	wire.visible = view == 3
	if view == 3:
		_build_wire()


## The tree's triangles as lines, carrying UV2 so they sway with it.
func _build_wire() -> void:
	var arrays := tree.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2_in = arrays[Mesh.ARRAY_TEX_UV2]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tri_count := (index.size() if index.size() > 0 else verts.size()) / 3
	var lv := PackedVector3Array()
	var lu := PackedVector2Array()
	lv.resize(tri_count * 6)
	lu.resize(tri_count * 6)
	var has_uv2: bool = uv2_in != null and (uv2_in as PackedVector2Array).size() == verts.size()
	var n := 0
	for t in tri_count:
		for e in 3:
			for s in 2:
				var k := t * 3 + (e + s) % 3
				var vi := index[k] if index.size() > 0 else k
				lv[n] = verts[vi]
				lu[n] = uv2_in[vi] if has_uv2 else Vector2.ZERO
				n += 1
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = lv
	out[Mesh.ARRAY_TEX_UV2] = lu
	var lines := ArrayMesh.new()
	lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, out)
	wire.mesh = lines


# --- the forest --------------------------------------------------------------

func _build_forest() -> void:
	_forest_dirty = false
	for child in forest.get_children():
		child.queue_free()
	_forest_draws = 0
	if not forest_on or not _made:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var points: Array = []
	var gap: float = maxf(_made.height * 0.45, 3.0)
	var tries := 0
	while points.size() < 60 and tries < 2000:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(0.04, 1.0)) * 46.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.length() < 4.5 + gap * 0.5:
			continue
		var ok := true
		for q: Vector3 in points:
			if q.distance_to(p) < gap:
				ok = false
				break
		if ok:
			points.append(p)
	var made: Array
	if _is_pine():
		made = PineTree.forest(forest, points, _made, 3, Vector2(0.7, 1.2), 64.0, 26.0)
	else:
		made = LeafyTree.forest(forest, points, _made, 3, Vector2(0.7, 1.2), 64.0, 26.0)
	_forest_draws = made.size()
