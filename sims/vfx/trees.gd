extends Sim3D
## Tree Lab: one generated tree on a turntable, every setting of GameCommon's PineTree and LeafyTree
## on a slider. The sliders are modifiers over the chosen species' preset (100% is the preset), so
## a species change keeps them. The tree is rebuilt at most every REBUILD seconds while a slider
## moves; the forest round it, once the sliders have been still for FOREST_WAIT.

const SWAY := preload("res://sims/vfx/trees_sway.gdshader")
const GRID := preload("res://sims/vfx/trees_grid.gdshader")
const LITTER := preload("res://sims/vfx/trees_litter.gdshader")
const SPECIES := ["Fir", "Spruce", "Snowy", "Lodgepole", "Sapling", "Oak", "Aspen", "Cottonwood", "Willow", "Pinyon",
	"Painted oak", "Tall", "Leaner", "Painted aspen", "Snag", "Bush"]
## The painted-woodland kit's trees (Woodland.KINDS), after the cel-shaded species; then its 3D bushes.
const PAINTED := {"Painted oak": "oak", "Tall": "tall", "Leaner": "leaner", "Painted aspen": "aspen", "Snag": "snag"}
const FIRST_PAINTED := 10
const LEAF_NAMES := ["Own", "Beech", "Oak", "Maple", "Aspen", "Birch"]
const BUSH_NAMES := ["Bronze", "Ember", "Bracken", "Shadow", "Holly"]
## Towards the sun (the scene's light, over the camera's left shoulder): the painted trees light
## themselves from it, as the kit's shaders do.
const SUN_DIR := Vector3(-3, 10, 9)
const SUN_COLOR := Color(1.0, 0.9, 0.74)
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
	foliage = 1.0, detail = 1.0, wild = 0.0, lean = 0.0, autumn = 0.0, snow = 0.0, roots = 1.0, swirl = 0.0}
## painted trees: which real leaf their clumps are cut from (0 their own), and the season (0 summer,
## 1 autumn, 2 late autumn); which bush
var leaf_kind := 0
var season := 1.0
var bush_kind := 0
var floor_kind := 0 # 0 the editor grid, 1 leaf litter

var painted := Node3D.new() # a painted tree's leaf clumps, or a bush, on the turntable
var bark_mat: ShaderMaterial
var birch_mat: ShaderMaterial
var foliage_mat: ShaderMaterial
var lying_mat: ShaderMaterial
var grid_floor := MeshInstance3D.new()
var litter_floor := MeshInstance3D.new()
var litter_mat := ShaderMaterial.new()
var lying := Node3D.new()
var stand: Array[Node3D] = [] # the plinth and its rim
var _height := 8.0
var _clumps := 0

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
		+ "The painted species (painted oak, tall, leaner, painted aspen, snag) are the painted-woodland kit's, after Over "
		+ "the Garden Wall: rope-twisted trunks that lean and swell at the foot, roots, swirling branches, and leaf clumps "
		+ "cut from real leaf outlines. They light themselves by hand from the sun's direction instead of using the "
		+ "engine's lights. Bush is the kit's real 3D bushes, leaf by leaf. Ground: Leaf litter lays the kit's painted "
		+ "ground with leaves lying on it.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom, two fingers to pan.")


func hint() -> String:
	return "Pick a species, then drag the sliders. Drag the view to orbit."


func status() -> String:
	var name: String = SPECIES[species] if not _is_bush() else "%s bush" % BUSH_NAMES[bush_kind]
	var s := "%s · seed %d · %.1fk tris · built %d ms" % [name, tree_seed, _tris / 1000.0, roundi(_build_ms)]
	if _is_painted() and _clumps > 0:
		s += " · %d clumps" % _clumps
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
	grid_floor.mesh = floor_mesh
	var grid := ShaderMaterial.new()
	grid.shader = GRID
	grid_floor.material_override = grid
	grid_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(grid_floor)
	# or the painted wood's floor: leaf litter, with leaves lying on it
	litter_mat.shader = LITTER
	litter_mat.set_shader_parameter("sun_color", SUN_COLOR)
	litter_floor.mesh = floor_mesh
	litter_floor.material_override = litter_mat
	litter_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(litter_floor)
	world.add_child(lying)
	var sun_dir := SUN_DIR.normalized()
	bark_mat = Woodland.material(Woodland.BARK, sun_dir, SUN_COLOR, {"moss": 0.6})
	birch_mat = Woodland.material(Woodland.BARK, sun_dir, SUN_COLOR, {"birch": 1.0})
	foliage_mat = Woodland.material(Woodland.FOLIAGE, sun_dir, SUN_COLOR)
	lying_mat = Woodland.material(Woodland.LEAF, sun_dir, SUN_COLOR)
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
	_apply_ground()
	_apply_season()
	_rebuild()
	_frame()


func controls() -> Array:
	var c: Array = [
		{type = "section", label = "Preset"},
		{type = "choice", label = "Species", options = SPECIES, value = species, on = func(i: int) -> void:
			var was := _family()
			species = i
			_touch()
			_rebuild()
			_frame()
			if _family() != was:
				controls_changed.emit()},
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
				_set_all("wind", v)
				foliage_mat.set_shader_parameter("sway", v / 0.35)
				if _made:
					_apply_tree_material()},
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
		{type = "choice", label = "Shading", options = ["Soft", "Toon"], value = shading,
			on = func(i: int) -> void:
				shading = i
				tree_mat.set_shader_parameter("toon", float(i))},
		{type = "choice", label = "View", options = ["Shaded", "Normals", "Sway", "Wire"], value = view,
			on = func(i: int) -> void:
				view = i
				_apply_view()},
	]
	# the painted trees' own settings, after Trunk/Crown/Leaves; a bush's kind
	var at := 0
	while at < c.size() and not (c[at].type == "section" and c[at].label == "Wind"):
		at += 1
	if _is_bush():
		c.insert(at, {type = "choice", label = "Bush", options = BUSH_NAMES, value = bush_kind, on = func(i: int) -> void:
			bush_kind = i
			_touch()})
		c.insert(at, {type = "section", label = "Painted"})
	elif _is_painted():
		var painted_rows: Array = [
			{type = "section", label = "Painted"},
			{type = "choice", label = "Leaf", options = LEAF_NAMES, value = leaf_kind, on = func(i: int) -> void:
				leaf_kind = i
				_touch()},
			{type = "slider", label = "Season", min = 0.0, max = 2.0, step = 0.05, value = season, fmt = "%.2f",
				on = func(v: float) -> void:
					season = v
					_apply_season()},
			_mod("Roots", "roots", 0.0, 2.0),
			_offset("Swirl", "swirl", -0.8, 1.2),
		]
		for k in painted_rows.size():
			c.insert(at + k, painted_rows[k])
	return c


## Which panel a species wants: 0 the cel-shaded trees, 1 the painted trees, 2 a bush.
func _family() -> int:
	return 2 if _is_bush() else (1 if _is_painted() else 0)


func _is_painted() -> bool:
	return species >= FIRST_PAINTED


func _is_bush() -> bool:
	return SPECIES[species] == "Bush"


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
	for child in painted.get_children():
		child.free()
	_clumps = 0
	var t0 := Time.get_ticks_usec()
	if _is_bush():
		_made = null
		_build_bush()
	elif _is_painted():
		_made = null
		_build_painted()
	else:
		# every slider step is a new key in the components' mesh caches: keep only what is in use
		PineTree.clear_cache()
		LeafyTree.clear_cache()
		_made = _make()
		tree.mesh = _made.mesh()
		_apply_tree_material()
		_height = _made.height
		_set_all("pine", 1.0 if _is_pine() else 0.0)
		_set_all("tree_height", _made.height)
	tree.visible = not _is_bush()
	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_tris = _count(tree.mesh) if tree.visible else 0
	for g in painted.find_children("*", "MeshInstance3D", false, false):
		_tris += _count((g as MeshInstance3D).mesh)
	_clumps_to_pools()
	if view == 3:
		_build_wire()


# --- the painted trees (the painted-woodland kit) ------------------------------

## The kit's shape for this seed (as Woodland.variant() would draw it), bent by the sliders.
func _painted_shape(kind: String, seed: int) -> Dictionary:
	var m := mods
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var s: Dictionary = Woodland._shape(kind, r, false)
	s.erase("lite") # variant() makes the full and the lite tree itself
	s.height *= m.height
	s.radius *= m.girth
	s.reach *= m.width
	s.lean = clampf(s.lean + m.lean * 2.0, 0.0, 0.9)
	s.branches = clampi(roundi(s.branches * m.branches), 1, 12)
	s.roots = clampi(roundi(s.roots * m.roots), 0, 12)
	s.curl = maxf(s.curl + m.swirl, 0.0)
	s.twist = maxf(s.twist + m.swirl * 0.08, 0.0)
	s.flute = clampf(s.flute * (1.0 + m.wild * 2.0), 0.0, 0.3)
	return s


func _painted_variant(seed: int) -> Dictionary:
	var kind: String = PAINTED[SPECIES[species]]
	var v := Woodland.variant(kind, seed, _painted_shape(kind, seed))
	if leaf_kind > 0:
		v.leaf = leaf_kind - 1
	return v


## Leaf clumps round a painted tree's crown points, bigger or smaller with Clump size.
func _painted_cards(v: Dictionary, tr: Transform3D, rng: RandomNumberGenerator, per_crown: int, out: Array) -> void:
	if v.bare:
		return
	var from := out.size()
	Woodland.crown_cards(v, tr, rng, per_crown, out)
	for k in range(from, out.size()):
		var c: Color = out[k][1]
		c.r *= mods.foliage
		out[k][1] = c


func _build_painted() -> void:
	var v := _painted_variant(tree_seed)
	tree.mesh = v.full
	tree.material_override = birch_mat if v.kind == "aspen" else bark_mat
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var cards: Array = []
	_painted_cards(v, Transform3D.IDENTITY, rng, clampi(roundi(3 * mods.detail), 1, 6), cards)
	if not cards.is_empty():
		Woodland.add_leaf_clumps(painted, cards, foliage_mat)
	_clumps = cards.size()
	_height = 0.0
	for c: Vector4 in v.crowns:
		_height = maxf(_height, c.y + c.w)
	_height = maxf(_height, 4.0)


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
	mi.scale = Vector3(mods.width, mods.height, mods.width)
	painted.add_child(mi)
	_height = info.size.y * 2.0 * mods.height


## The pools of shade on the leaf litter, under the tree's crown.
func _clumps_to_pools() -> void:
	var pools := PackedVector4Array()
	pools.resize(8)
	var reach := clampf(_height * 0.45, 1.5, 7.0)
	pools[0] = Vector4(0, 0, reach, 0)
	litter_mat.set_shader_parameter("trees", pools)
	litter_mat.set_shader_parameter("tree_count", 1)


## 0 summer, 1 autumn (the kit's own colours), 2 late autumn: the painted leaves and the litter.
func _apply_season() -> void:
	var summer := [Color(0.55, 0.62, 0.22), Color(0.36, 0.5, 0.16), Color(0.22, 0.36, 0.12)]
	var autumn := [Color(0.93, 0.68, 0.24), Color(0.84, 0.43, 0.13), Color(0.52, 0.24, 0.1)]
	var late := [Color(0.66, 0.44, 0.2), Color(0.52, 0.28, 0.12), Color(0.33, 0.18, 0.09)]
	var keys := ["gold", "orange", "rust"]
	for i in 3:
		var col: Color = summer[i].lerp(autumn[i], clampf(season, 0.0, 1.0)) if season <= 1.0 \
			else autumn[i].lerp(late[i], season - 1.0)
		foliage_mat.set_shader_parameter(keys[i], col)
		lying_mat.set_shader_parameter(keys[i], col)
	var lit := clampf(season, 0.0, 1.0)
	litter_mat.set_shader_parameter("litter_a", Color(0.35, 0.36, 0.15).lerp(Color(0.62, 0.36, 0.14), lit))
	litter_mat.set_shader_parameter("litter_c", Color(0.45, 0.45, 0.2).lerp(Color(0.72, 0.52, 0.2), lit))


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
	if not mesh or mesh.get_surface_count() == 0:
		return 0
	var idx: int = mesh.surface_get_array_index_len(0)
	return (idx if idx > 0 else mesh.surface_get_array_len(0)) / 3


func _frame() -> void:
	var h: float = _height
	focus = Vector3(0, turntable.position.y + h * 0.45, 0)
	distance = clampf(h * 1.55 + (1.2 if _is_bush() else 3.0), min_distance, max_distance)
	pitch = -0.2
	_place_camera()


# --- views -------------------------------------------------------------------

func _apply_view() -> void:
	tree_mat.set_shader_parameter("view", view)
	wire.visible = view == 3
	if view == 3:
		_build_wire()
	if _made:
		_apply_tree_material()


## What a game gets: a pine is drawn by PineTree's own needle shader (its forest too). Leafy trees
## have no wind shader of their own (LeafyTree's README leaves that to the game), so they take the
## lab's sway material, as a game's would. The debug views (Normals, Sway, Wire) override either.
func _apply_tree_material() -> void:
	if _is_pine() and view == 0:
		var own := _made._material() as ShaderMaterial
		tree.material_override = own
		if own:
			own.set_shader_parameter("sway", clampf(wind * 0.115, 0.0, 0.3))
	else:
		tree.material_override = tree_mat


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
	if _is_painted():
		_painted_forest(points)
		return
	var made: Array
	if _is_pine():
		made = PineTree.forest(forest, points, _made, 3, Vector2(0.7, 1.2), 64.0, 26.0)
	else:
		made = LeafyTree.forest(forest, points, _made, 3, Vector2(0.7, 1.2), 64.0, 26.0)
	_forest_draws = made.size()


## A painted wood: three shapes of the tree from neighbouring seeds, full near and lite far, as the
## kit draws its woods (Woodland.add_trees, in squares), with their leaf clumps.
func _painted_forest(points: Array) -> void:
	var variants: Array = []
	for k in 3:
		variants.append(_painted_variant(tree_seed + 1 + k * 17))
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed + 5
	var cards: Array = []
	for p: Vector3 in points:
		var v: Dictionary = variants[rng.randi() % variants.size()]
		var tr := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.15)), p)
		var near := p.length() < 26.0
		v["near" if near else "far"].append(tr)
		_painted_cards(v, tr, rng, 2 if near else 1, cards)
	Woodland.add_trees(forest, variants, bark_mat, birch_mat)
	if not cards.is_empty():
		Woodland.add_leaf_clumps(forest, cards, foliage_mat)
	_forest_draws = forest.get_child_count()


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
