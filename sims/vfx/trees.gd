extends Sim3D
## Tree Lab: one tree on a turntable, grown by GameCommon's TreeGen (godot/tree), every setting on a
## slider. A species is a preset of those settings; any species takes any way of drawing its leaves.
## The tree is rebuilt at most every REBUILD seconds while a slider moves; the forest round it, once
## the sliders have been still for FOREST_WAIT. Bush is the painted-woodland kit's 3D bushes.

const GRID := preload("res://sims/vfx/trees_grid.gdshader")
const LITTER := preload("res://sims/vfx/trees_litter.gdshader")
const BUSH := "Bush"
const BUSH_NAMES := ["Bronze", "Ember", "Bracken", "Shadow", "Holly"]
const STYLES := ["Blobs", "Fluffy", "Needles", "Painted", "None"]
const SHAPES := ["Conical", "Spherical", "Hemispherical", "Cylindrical", "Tapered", "Flame", "Inverse", "Tend flame"]
const PAINTED_LEAVES := ["Beech", "Oak", "Maple", "Aspen", "Birch"]
## Leaf colours to try on any tree: inner, outer, tips. "Preset" keeps the species' own.
const PALETTES := {
	"Preset": [],
	"Summer": [Color(0.09, 0.2, 0.09), Color(0.2, 0.4, 0.16), Color(0.45, 0.62, 0.26)],
	"Spring": [Color(0.18, 0.32, 0.1), Color(0.42, 0.62, 0.2), Color(0.72, 0.86, 0.38)],
	"Autumn": [Color(0.38, 0.13, 0.04), Color(0.84, 0.4, 0.1), Color(1.0, 0.74, 0.24)],
	"Gold": [Color(0.45, 0.32, 0.06), Color(0.88, 0.64, 0.14), Color(1.0, 0.85, 0.3)],
	"Red": [Color(0.36, 0.06, 0.04), Color(0.78, 0.2, 0.08), Color(1.0, 0.55, 0.18)],
	"Conifer": [Color(0.10, 0.22, 0.16), Color(0.24, 0.42, 0.26), Color(0.40, 0.56, 0.32)],
	"Blue spruce": [Color(0.12, 0.22, 0.24), Color(0.3, 0.46, 0.48), Color(0.56, 0.7, 0.7)],
	"Ghostly": [Color(0.2, 0.22, 0.28), Color(0.55, 0.6, 0.68), Color(0.85, 0.9, 0.95)],
}
## Towards the sun (the scene's light, over the camera's left shoulder): the leaf litter and the
## bushes light themselves from it, as the painted-woodland kit's shaders do.
const SUN_DIR := Vector3(-3, 10, 9)
const SUN_COLOR := Color(1.0, 0.9, 0.74)
const PLINTH := 0.25
const REBUILD := 0.12
const FOREST_WAIT := 0.5
## The lines of View: Wire, swaying with the tree (the same wind as its shaders).
const WIRE := """
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://tree/tree_common.gdshaderinc"
uniform vec3 wire_color : source_color = vec3(0.35, 0.85, 1.0);
void vertex() {
	VERTEX += (inverse(MODEL_MATRIX) * vec4(tree_wind(MODEL_MATRIX, VERTEX, UV2.y, TIME), 0.0)).xyz;
}
void fragment() {
	ALBEDO = wire_color;
}
"""

var names: Array = TreeGen.PRESETS.keys() + [BUSH]
var species := 0
var gen := TreeGen.preset(names[0])
var tree_seed := 1
var palette := 0
var autumn := 0.0
var view := 0
var wind := 0.35
var turbulence := 0.3
var spin := true
var forest_on := false
var bush_kind := 0
var floor_kind := 0 # 0 the editor grid, 1 leaf litter

var painted := Node3D.new() # a bush on the turntable
var lying_mat: ShaderMaterial
var grid_floor := MeshInstance3D.new()
var litter_floor := MeshInstance3D.new()
var litter_mat := ShaderMaterial.new()
var lying := Node3D.new()
var stand: Array[Node3D] = [] # the plinth and its rim
var _height := 8.0

var wire_mat := ShaderMaterial.new()
var turntable := Node3D.new()
var tree := MeshInstance3D.new()
var wire := MeshInstance3D.new()
var forest := Node3D.new()

var _made: TreeGen
var _dirty := true
var _forest_dirty := false
var _since := 1.0
var _still := 0.0
var _build_ms := 0.0
var _tris := 0
var _forest_draws := 0


func help() -> String:
	return ("Every tree here is grown by one algorithm, GameCommon's TreeGen, as the games grow theirs. A trunk grows "
		+ "branches, which grow their own, up to four levels deep. Branching sets how many there are, at what angle, "
		+ "how they are turned round their parent (the golden angle, as most plants do), how long and thick they are, "
		+ "and whether they reach for the light, sag, weep, curl or wander. Apical dominance is the leader: strong, "
		+ "the trunk runs to the top and the crown is a cone (a conifer); weak, the trunk forks low into limbs (an oak). "
		+ "The trunk's branches grow out to the crown's outline, which Crown shape draws.\n\n"
		+ "Leaves grow on the outermost twigs and can be drawn five ways, on any species: Blobs (lumpy faceted balls), "
		+ "Fluffy (quads over each clump, turned part way to the camera and cut out of a leaf texture, with normals bent "
		+ "out from the crown so it shades as one soft mass), Needles (crossed cards of needles along each frond, a pine's), "
		+ "Painted (big camera-facing cards of real leaf shapes, after Over the Garden Wall), or None.\n\n"
		+ "View shows what the shaders use: Normals (bent out from the crown), Sway (how much each corner moves in "
		+ "the wind, UV2.y), Wire (the triangles). Forest plants a wood of the current tree, a MultiMesh per variant "
		+ "with plainer trees far off. The same settings and seed always make the same tree.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom, two fingers to pan.")


func hint() -> String:
	return "Pick a species, then drag the sliders. Drag the view to orbit."


func status() -> String:
	var name: String = names[species] if not _is_bush() else "%s bush" % BUSH_NAMES[bush_kind]
	var s := "%s · seed %d · %.1fk tris · built %d ms" % [name, tree_seed, _tris / 1000.0, roundi(_build_ms)]
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
	sun.look_at_from_position(SUN_DIR, Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.5
	sun.shadow_blur = 1.5
	var wire_shader := Shader.new()
	wire_shader.code = WIRE
	wire_mat.shader = wire_shader
	# the floor: an editor grid, and a turntable to stand the tree on
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(240, 240)
	grid_floor.mesh = floor_mesh
	var grid := ShaderMaterial.new()
	grid.shader = GRID
	grid_floor.material_override = grid
	grid_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(grid_floor)
	# or the painted wood's floor: leaf litter, with leaves lying on it
	litter_mat.shader = LITTER
	litter_mat.set_shader_parameter("sun_color", SUN_COLOR)
	litter_mat.set_shader_parameter("litter_a", Color(0.62, 0.36, 0.14))
	litter_mat.set_shader_parameter("litter_c", Color(0.72, 0.52, 0.2))
	litter_floor.mesh = floor_mesh
	litter_floor.material_override = litter_mat
	litter_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(litter_floor)
	world.add_child(lying)
	lying_mat = Woodland.material(Woodland.LEAF, SUN_DIR.normalized(), SUN_COLOR)
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
	stand = [plinth, rim]
	turntable.position.y = PLINTH
	world.add_child(turntable)
	turntable.add_child(tree)
	turntable.add_child(painted)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wire.material_override = wire_mat
	turntable.add_child(wire)
	world.add_child(forest)
	species = names.find("Oak")
	gen = TreeGen.preset("Oak")
	_apply_ground()
	_rebuild()
	_frame()


func controls() -> Array:
	var c: Array = [
		{type = "section", label = "Preset"},
		{type = "choice", label = "Species", options = names, value = species, on = _pick_index},
		{type = "slider", label = "Seed", min = 1, max = 9999, step = 1, value = tree_seed, fmt = "%d",
			on = func(v: float) -> void: tree_seed = int(v); _touch()},
		{type = "button", label = "Randomize", on = _randomize},
		{type = "button", label = "Reset", on = func() -> void:
			if not _is_bush():
				gen.apply_preset(names[species])
			palette = 0
			autumn = 0.0
			_touch()
			controls_changed.emit()},
	]
	if _is_bush():
		c.append_array([
			{type = "section", label = "Bush"},
			{type = "choice", label = "Bush", options = BUSH_NAMES, value = bush_kind, on = func(i: int) -> void:
				bush_kind = i
				_touch()},
		])
	else:
		c.append_array(_tree_rows())
	c.append_array([
		{type = "section", label = "Wind"},
		{type = "slider", label = "Strength", min = 0.0, max = 1.5, step = 0.05, value = wind, fmt = "%.2f",
			on = func(v: float) -> void: wind = v; _apply_uniforms()},
		{type = "slider", label = "Turbulence", min = 0.0, max = 1.0, step = 0.05, value = turbulence, fmt = "%.2f",
			on = func(v: float) -> void: turbulence = v; _apply_uniforms()},
		{type = "section", label = "Scene"},
		{type = "choice", label = "Ground", options = ["Grid", "Leaf litter"], value = floor_kind, on = func(i: int) -> void:
			floor_kind = i
			_apply_ground()
			_frame()},
		{type = "toggle", label = "Spin", value = spin, on = func(on: bool) -> void: spin = on},
		{type = "toggle", label = "Forest", value = forest_on, on = func(on: bool) -> void:
			forest_on = on
			_forest_dirty = true
			_still = FOREST_WAIT},
		{type = "button", label = "Frame", on = _frame},
		{type = "section", label = "Display"},
		{type = "choice", label = "Shading", options = ["Soft", "Toon"], value = 1 if gen.toon > 0.5 else 0,
			on = func(i: int) -> void:
				gen.toon = float(i)
				_touch()},
		{type = "choice", label = "View", options = ["Shaded", "Normals", "Sway", "Wire"], value = view,
			on = func(i: int) -> void:
				view = i
				_apply_view()},
	])
	c.append_array(Exporter.controls("%s %d" % [names[species], tree_seed], _export, "trees",
		func(t: String) -> void: say.emit(t)))
	return c


## The generator's settings, by section; the leaf style's own settings only for that style.
func _tree_rows() -> Array:
	var rows: Array = [
		{type = "section", label = "Trunk"},
		_slider("Height", "height", 1.0, 30.0, 0.1, "%.1f", " m"),
		_slider("Girth", "trunk_radius", 0.04, 1.2, 0.01, "%.2f", " m"),
		_slider("Trunk base", "trunk_base", 0.0, 0.9),
		_slider("Lean", "lean", 0.0, 0.8),
		_slider("Bend", "bend", 0.0, 1.0),
		_slider("Root flare", "root_flare", 0.0, 2.0),
		_slider("Roots", "roots", 0, 12, 1, "%d"),
		{type = "section", label = "Branching"},
		_slider("Levels", "levels", 1, 4, 1, "%d"),
		_slider("Branches", "children", 1, 150, 1, "%d"),
		_slider("Twigs", "twigs", 0, 24, 1, "%d"),
		_slider("Count random", "children_random", 0.0, 1.0),
		_slider("Whorl", "whorl", 1, 12, 1, "%d"),
		{type = "toggle", label = "Golden angle", value = gen.golden_angle, on = func(on: bool) -> void:
			gen.golden_angle = on
			_touch()},
		_slider("Angle", "branch_angle", 0.0, 150.0, 1.0, "%d", " deg"),
		_slider("Twig angle", "twig_angle", 0.0, 150.0, 1.0, "%d", " deg"),
		_slider("Angle random", "angle_random", 0.0, 60.0, 1.0, "%d", " deg"),
		_slider("Length", "length", 0.02, 1.5),
		_slider("Twig length", "twig_length", 0.05, 1.2),
		_slider("Radius ratio", "radius_ratio", 0.1, 1.0),
		_slider("Twigs from", "start", 0.0, 1.0),
		_slider("Twigs to", "end", 0.0, 1.0),
		_slider("Apical dominance", "apical", 0.0, 1.0),
		_slider("Gravitropism", "gravitropism", -1.0, 1.0, 0.02, "%+.2f"),
		_slider("Droop", "droop", 0.0, 1.5),
		_slider("Weep", "weep", 0.0, 1.0),
		_slider("Curl", "curl", 0.0, 1.5),
		_slider("Twist", "twist", -1.0, 1.0, 0.02, "%+.2f"),
		_slider("Wildness", "wildness", 0.0, 1.0),
		{type = "section", label = "Crown"},
		{type = "choice", label = "Shape", options = SHAPES, value = gen.crown_shape, on = func(i: int) -> void:
			gen.crown_shape = i
			_touch()},
		_slider("Spread", "spread", 0.2, 3.0),
		_slider("Fill", "fill", 0.0, 1.0),
		{type = "section", label = "Leaves"},
		{type = "choice", label = "Style", options = STYLES, value = gen.leaf_style, on = func(i: int) -> void:
			gen.leaf_style = i
			_touch()
			controls_changed.emit()},
	]
	if gen.leaf_style != TreeGen.Leaves.NONE:
		rows.append_array([
			_slider("Clump size", "clump_size", 0.05, 3.0, 0.01, "%.2f", " m"),
			_slider("Density", "leaf_density", 0.0, 4.0),
			_slider("Reach", "leaf_reach", 0.0, 1.0),
			{type = "choice", label = "Colours", options = PALETTES.keys(), value = palette, on = func(i: int) -> void:
				palette = i
				var cols: Array = PALETTES.values()[i]
				if cols.is_empty():
					var p := TreeGen.preset(names[species])
					cols = [p.leaves_inner, p.leaves_outer, p.leaves_tips]
				gen.leaves_inner = cols[0]
				gen.leaves_outer = cols[1]
				gen.leaves_tips = cols[2]
				_touch()},
			{type = "slider", label = "Autumn", min = 0.0, max = 1.0, step = 0.02, value = autumn, fmt = "%.2f",
				on = func(v: float) -> void: autumn = v; _touch()},
			_slider("Dapple", "dapple", 0.0, 1.0),
			{type = "slider", label = "Accent", min = 0.0, max = 0.5, step = 0.01, value = gen.accent.a, fmt = "%.2f",
				on = func(v: float) -> void: gen.accent.a = v; _touch()},
			_slider("Snow", "snow", 0.0, 1.0),
			_slider("Rim light", "rim", 0.0, 1.0),
		])
	match gen.leaf_style:
		TreeGen.Leaves.FLUFFY:
			rows.append_array([
				{type = "section", label = "Fluffy cards"},
				{type = "choice", label = "Leaf", options = ["Broad", "Narrow"], value = gen.fluffy_leaf, on = func(i: int) -> void:
					gen.fluffy_leaf = i
					_touch()},
				_slider("Card size", "card_size", 0.2, 3.0),
				_slider("Cards", "cards", 0.1, 3.0),
				_slider("Billboard", "billboard", 0.0, 1.0),
				_slider("Normal bend", "normal_bend", 0.0, 1.0),
				_slider("Alpha cut", "alpha_cut", 0.05, 0.95),
			])
		TreeGen.Leaves.PAINTED:
			rows.append_array([
				{type = "section", label = "Painted cards"},
				{type = "choice", label = "Leaf", options = PAINTED_LEAVES, value = gen.painted_leaf, on = func(i: int) -> void:
					gen.painted_leaf = i
					_touch()},
				_slider("Card size", "card_size", 0.2, 3.0),
				_slider("Cards", "cards", 0.1, 3.0),
				_slider("Normal bend", "normal_bend", 0.0, 1.0),
			])
		TreeGen.Leaves.NEEDLES:
			rows.append_array([
				{type = "section", label = "Needles"},
				_slider("Needle density", "needle_density", 0.4, 2.5),
				_slider("Sprigs", "sprigs", 0, 4, 1, "%d"),
				_slider("Fullness", "fullness", 0.1, 0.9),
				_slider("Alpha cut", "alpha_cut", 0.05, 0.95),
			])
		TreeGen.Leaves.BLOBS:
			rows.append_array([
				{type = "section", label = "Blobs"},
				_slider("Lumpiness", "lumpiness", 0.0, 1.0),
				_slider("Tufts", "tufts", 0, 14, 1, "%d"),
			])
	return rows


## A slider straight onto one of the generator's settings.
func _slider(label: String, key: String, lo: float, hi: float, step := 0.01, fmt := "%.2f", unit := "") -> Dictionary:
	var whole := typeof(gen.get(key)) == TYPE_INT
	return {type = "slider", label = label, min = lo, max = hi, step = step, value = float(gen.get(key)), fmt = fmt,
		unit = unit, on = func(v: float) -> void:
			gen.set(key, roundi(v) if whole else v)
			_touch()}


# --- export ----------------------------------------------------------------------

## Sends the tree on the turntable (never the forest) to the asset library: its generator (a TreeGen
## .tres: the same settings make the same tree in any project with godot/tree), its baked mesh, and a
## .glb for Blender and other tools (vertex colours, the cards as plain quads). A bush goes as a scene
## (the kit's material, lit from the lab's sun), its settings and a .glb.
func _export(asset_name: String) -> void:
	var file := Exporter.slug(asset_name)
	if _is_bush():
		var scene := Node3D.new()
		scene.name = asset_name.to_pascal_case().validate_node_name()
		for child in painted.get_children():
			scene.add_child(child.duplicate())
		var settings := {bush = BUSH_NAMES[bush_kind], seed = tree_seed, sun_dir = [SUN_DIR.x, SUN_DIR.y, SUN_DIR.z]}
		say.emit(Exporter.save("trees", asset_name, {"tscn": scene, "glb": _glb(scene), "json": JSON.stringify(settings, "  ")},
			["godot/painted-woodland"],
			"var bush := (load(\"res://assets/trees/%s.tscn\") as PackedScene).instantiate()\nadd_child(bush)\n" % file
			+ "# lit by hand from the sun in %s.json (sun_dir): for another sun, set its material's sun_dir" % file,
			"Tree Lab"))
		scene.free()
		return
	var made := _make()
	# the baked mesh goes without its materials (they hold a texture made at start-up): dress() gives them back
	var baked: ArrayMesh = made.mesh().duplicate()
	for i in baked.get_surface_count():
		baked.surface_set_material(i, null)
	var holder := Node3D.new()
	holder.name = asset_name.to_pascal_case().validate_node_name()
	var shown := MeshInstance3D.new()
	shown.mesh = baked
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.vertex_color_is_srgb = true
	plain.roughness = 1.0
	shown.material_override = plain
	holder.add_child(shown)
	var needs := ["godot/tree"]
	if made.leaf_style == TreeGen.Leaves.PAINTED:
		needs.append("godot/painted-woodland") # its real leaf shapes (without it, TreeGen's own clusters)
	var use := "var tree := (load(\"res://assets/trees/%s.tres\") as TreeGen).instance()   # from its settings\n" % file
	use += "add_child(tree)\n"
	use += "# or a whole wood: TreeGen.forest(self, points, load(\"res://assets/trees/%s.tres\"))\n" % file
	use += "# or the baked mesh: var mi := MeshInstance3D.new(); mi.mesh = load(\"res://assets/trees/%s.mesh.res\")\n" % file
	use += "#   (load(\"res://assets/trees/%s.tres\") as TreeGen).dress(mi)" % file
	say.emit(Exporter.save("trees", asset_name, {"tres": made, "mesh.res": baked, "glb": _glb(holder)}, needs, use, "Tree Lab"))
	holder.free()


## A node's meshes as a binary glTF, for Blender and other tools (vertex colours come along;
## Godot shaders do not).
func _glb(node: Node) -> PackedByteArray:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_scene(node, state) != OK:
		return PackedByteArray()
	return doc.generate_buffer(state)


## Shows a species (a TreeGen preset, or Bush) by name, as the Species choice does.
func pick(species_name: String) -> void:
	_pick_index(maxi(names.find(species_name), 0))


func _pick_index(i: int) -> void:
	species = i
	if not _is_bush():
		gen.apply_preset(names[i])
		palette = 0
		autumn = 0.0
	_touch()
	_rebuild()
	_frame()
	controls_changed.emit()


func _is_bush() -> bool:
	return names[species] == BUSH


func _touch() -> void:
	_dirty = true
	_still = 0.0
	if forest_on:
		_forest_dirty = true


func _randomize() -> void:
	tree_seed = randi_range(1, 9999)
	_touch()


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

## The tree as set, with the seed and the Autumn slider applied.
func _make() -> TreeGen:
	var t: TreeGen = gen.duplicate()
	t.seed = tree_seed
	if autumn > 0.0:
		var fall: Array = PALETTES["Autumn"]
		t.leaves_inner = t.leaves_inner.lerp(fall[0], autumn)
		t.leaves_outer = t.leaves_outer.lerp(fall[1], autumn)
		t.leaves_tips = t.leaves_tips.lerp(fall[2], autumn)
	return t


func _rebuild() -> void:
	_dirty = false
	_since = 0.0
	for child in painted.get_children():
		child.free()
	var t0 := Time.get_ticks_usec()
	if _is_bush():
		_made = null
		_build_bush()
	else:
		# every slider step is a new key in the component's caches: keep only what is in use
		TreeGen.clear_cache()
		_made = _make()
		tree.mesh = _made.mesh()
		_height = maxf(_made.built_height, 1.0)
	tree.visible = not _is_bush()
	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_tris = _count(tree.mesh) if tree.visible else 0
	for g in painted.find_children("*", "MeshInstance3D", false, false):
		_tris += _count((g as MeshInstance3D).mesh)
	_clumps_to_pools()
	_apply_uniforms()
	if view == 3:
		_build_wire()


func _build_bush() -> void:
	var kind: String = BUSH_NAMES[bush_kind].to_lower()
	var info: Dictionary = Woodland.BushBuilder.KINDS[kind]
	var r := RandomNumberGenerator.new()
	r.seed = tree_seed
	var mi := MeshInstance3D.new()
	mi.mesh = Woodland.BushBuilder.new().build(r, kind, info)
	var params: Dictionary = info.colors.duplicate()
	params["shape"] = info.shape
	mi.material_override = Woodland.material(Woodland.LEAF3D, SUN_DIR.normalized(), SUN_COLOR, params)
	painted.add_child(mi)
	_height = info.size.y * 2.0


## The pools of shade on the leaf litter, under the tree's crown.
func _clumps_to_pools() -> void:
	var pools := PackedVector4Array()
	pools.resize(8)
	var reach := clampf(_height * 0.45, 1.5, 7.0)
	pools[0] = Vector4(0, 0, reach, 0)
	litter_mat.set_shader_parameter("trees", pools)
	litter_mat.set_shader_parameter("tree_count", 1)


## The editor grid with the tree on its turntable, or the painted wood's leaf litter with the tree
## standing in it and leaves lying round it.
func _apply_ground() -> void:
	var litter := floor_kind == 1
	grid_floor.visible = not litter
	litter_floor.visible = litter
	for n in stand:
		n.visible = not litter
	turntable.position.y = 0.0 if litter else PLINTH
	for child in lying.get_children():
		child.free()
	if litter:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var cards: Array = []
		for i in 700:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * 14.0
			cards.append(Woodland.leaf_card(rng, p, false))
		Woodland.add_leaves(lying, cards, lying_mat, AABB(Vector3(-16, -1, -16), Vector3(32, 3, 32)))


func _count(mesh: Mesh) -> int:
	var n := 0
	if mesh:
		for s in mesh.get_surface_count():
			var idx: int = mesh.surface_get_array_index_len(s)
			n += (idx if idx > 0 else mesh.surface_get_array_len(s)) / 3
	return n


func _frame() -> void:
	var h: float = _height
	focus = Vector3(0, turntable.position.y + h * 0.45, 0)
	distance = clampf(h * 1.55 + (1.2 if _is_bush() else 3.0), min_distance, max_distance)
	pitch = -0.2
	_place_camera()


# --- views -------------------------------------------------------------------

func _apply_view() -> void:
	wire.visible = view == 3
	if view == 3:
		_build_wire()
	_apply_uniforms()


## Every material the tree and the forest are drawn with: the wind, and the debug view.
func _apply_uniforms() -> void:
	var meshes: Array[Mesh] = []
	if tree.mesh:
		meshes.append(tree.mesh)
	for node in forest.get_children():
		if node is MultiMeshInstance3D and node.multimesh:
			meshes.append(node.multimesh.mesh)
	var debug := view if view < 3 else 3
	for m in meshes:
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as ShaderMaterial
			if mat:
				mat.set_shader_parameter("wind", wind)
				mat.set_shader_parameter("turbulence", turbulence)
				mat.set_shader_parameter("debug_view", debug)
	wire_mat.set_shader_parameter("wind", wind)
	wire_mat.set_shader_parameter("turbulence", turbulence)


## The tree's triangles as lines, carrying UV2 so they sway with it.
func _build_wire() -> void:
	if not tree.mesh or not tree.visible:
		wire.mesh = null
		return
	var lv := PackedVector3Array()
	var lu := PackedVector2Array()
	for surface in tree.mesh.get_surface_count():
		var arrays := tree.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri_count := (index.size() if index.size() > 0 else verts.size()) / 3
		for t in tri_count:
			for e in 3:
				for s in 2:
					var k := t * 3 + (e + s) % 3
					var vi := index[k] if index.size() > 0 else k
					lv.append(verts[vi])
					lu.append(uv2[vi] if vi < uv2.size() else Vector2.ZERO)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = lv
	out[Mesh.ARRAY_TEX_UV2] = lu
	var lines := ArrayMesh.new()
	if lv.size() > 0:
		lines.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, out)
	wire.mesh = lines


# --- the forest --------------------------------------------------------------

func _build_forest() -> void:
	_forest_dirty = false
	for child in forest.get_children():
		child.queue_free()
	_forest_draws = 0
	if not forest_on:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var points: Array = []
	var gap: float = maxf(_height * 0.45, 3.0)
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
	if _is_bush():
		_bush_forest(points)
		return
	_forest_draws = TreeGen.forest(forest, points, _made, 3, Vector2(0.7, 1.2), 64.0, 26.0).size()
	_apply_uniforms()


## Bushes scattered round: one MultiMesh of the current bush.
func _bush_forest(points: Array) -> void:
	var src := painted.get_child(0) as MeshInstance3D if painted.get_child_count() > 0 else null
	if not src:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed + 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = src.mesh
	mm.instance_count = points.size()
	for i in points.size():
		var s := src.scale * rng.randf_range(0.7, 1.2)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(s), points[i] * 0.4))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = src.material_override
	forest.add_child(mmi)
	_forest_draws = 1
