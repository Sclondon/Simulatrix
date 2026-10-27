class_name Woodland
extends RefCounted
## A painted woodland kit, made for Scenic Route's Amberwood (after Over the Garden Wall): trees with roots,
## twisting ropey trunks, lean and swirling branches (`tree_builder.gd`) and their bark; leaf clumps of real
## leaves (`leaf_atlas.gd`); 3D bushes (`bush_builder.gd`); falling and fallen leaves; shafts of sun that come
## and go; a painted sky; a stream (a still pond is GameCommon's water). Everything lights itself by hand from
## a sun direction (the shaders are `unshaded`, with a `sun_dir` and `sun_color`), so give every material that
## through `material()`.
##
## A game places things itself (where trees stand is its business) and hands them here to be built and drawn.

const TreeBuilder := preload("res://woodland/tree_builder.gd")
const BushBuilder := preload("res://woodland/bush_builder.gd")
const LeafAtlas := preload("res://woodland/leaf_atlas.gd")
const BARK := preload("res://woodland/shaders/bark.gdshader")
const FOLIAGE := preload("res://woodland/shaders/foliage.gdshader")
const LEAF := preload("res://woodland/shaders/leaf.gdshader")
const LEAF3D := preload("res://woodland/shaders/leaf3d.gdshader")
const SHAFT := preload("res://woodland/shaders/shaft.gdshader")
const SKY := preload("res://woodland/shaders/sky.gdshader")
const STREAM := preload("res://woodland/shaders/stream.gdshader")

## The kinds of tree, and their shapes' ranges (see tree_builder.gd for what each setting does).
const KINDS := {
	"oak": {"height": [8.5, 12.5], "radius": [0.55, 0.95], "reach": [5.5, 8.0], "lean": [0.0, 0.18],
		"twist": [0.04, 0.12], "flute": [0.1, 0.16], "flare": [0.7, 1.1], "roots": [5, 8], "branches": [5, 7], "curl": [0.8, 1.3]},
	"tall": {"height": [12.0, 17.0], "radius": [0.24, 0.42], "reach": [3.5, 5.0], "lean": [0.0, 0.1],
		"twist": [0.0, 0.04], "flute": [0.03, 0.06], "flare": [0.4, 0.6], "roots": [2, 4], "branches": [4, 7], "curl": [0.2, 0.5]},
	"leaner": {"height": [10.0, 14.0], "radius": [0.3, 0.5], "reach": [4.0, 6.0], "lean": [0.3, 0.6],
		"twist": [0.02, 0.08], "flute": [0.05, 0.1], "flare": [0.6, 0.9], "roots": [3, 5], "branches": [4, 6], "curl": [0.5, 0.9]},
	"aspen": {"height": [10.0, 15.0], "radius": [0.14, 0.26], "reach": [2.5, 3.8], "lean": [0.0, 0.12],
		"twist": [0.0, 0.0], "flute": [0.0, 0.0], "flare": [0.25, 0.4], "roots": [0, 2], "branches": [4, 6], "curl": [0.1, 0.3], "tip": 0.25},
	"snag": {"height": [6.0, 10.0], "radius": [0.25, 0.45], "reach": [2.5, 4.0], "lean": [0.0, 0.25],
		"twist": [0.03, 0.1], "flute": [0.08, 0.12], "flare": [0.6, 0.9], "roots": [3, 5], "branches": [2, 4], "curl": [0.8, 1.2], "bare": true},
}


## A material for one of the kit's shaders, lit by the sun (and with the leaf sheet where it is wanted).
static func material(shader: Shader, sun_dir: Vector3, sun_color: Color, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("sun_dir", sun_dir.normalized())
	m.set_shader_parameter("sun_color", Vector3(sun_color.r, sun_color.g, sun_color.b))
	if shader in [FOLIAGE, LEAF, LEAF3D]:
		m.set_shader_parameter("leaf_atlas", LeafAtlas.texture())
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _shape(kind: String, r: RandomNumberGenerator, lite: bool) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var out := {"lite": lite, "bare": k.get("bare", false), "tip": k.get("tip", 0.18)}
	for key in ["height", "radius", "reach", "lean", "twist", "flute", "flare", "curl"]:
		out[key] = r.randf_range(k[key][0], k[key][1])
	out["roots"] = r.randi_range(k.roots[0], k.roots[1])
	out["branches"] = r.randi_range(k.branches[0], k.branches[1])
	return out


## A tree of a kind (KINDS), made twice from one seed: `full` for near, `lite` (fewer rings and sides, no
## roots or twigs) for far; `crowns` where its leaf clumps go (in its own space), `leaf` which real leaf
## (leaf_atlas.gd). `near` and `far` are for the game to fill with where it stands (Transform3Ds); then
## add_trees() draws them. `shape_override` sets any of the shape's settings outright.
static func variant(kind: String, seed: int, shape_override := {}) -> Dictionary:
	var builder := TreeBuilder.new()
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var shape := _shape(kind, r, false)
	shape.merge(shape_override, true)
	var full := builder.build(r, shape)
	var crowns := builder.crowns.duplicate()
	r.seed = seed
	shape = _shape(kind, r, true)
	shape.merge(shape_override, true)
	shape.lite = true
	var lite := builder.build(r, shape)
	# its leaves: oaks' and aspens' own, the rest beech, maple or birch
	var leaf: int = {"oak": 1, "aspen": 3}.get(kind, [0, 2, 4][seed % 3])
	return {"kind": kind, "full": full, "lite": lite, "crowns": crowns, "near": [], "far": [], "bare": shape.bare, "leaf": leaf}


## Things grouped by the square of `size` metres they stand in (`where` says where each is), so each square
## can be its own MultiMesh and those off screen are not drawn.
static func squares(things: Array, where: Callable, size := 40.0) -> Dictionary:
	var out := {}
	for t in things:
		var p: Vector3 = where.call(t)
		var key := Vector2i(floori(p.x / size), floori(p.z / size))
		if not out.has(key):
			out[key] = []
		out[key].append(t)
	return out


## Draws the trees placed in `variants` (their `near` and `far` lists), in squares; aspens in `birch_bark`.
static func add_trees(parent: Node, variants: Array, bark: Material, birch_bark: Material) -> void:
	for v in variants:
		for lod in ["near", "far"]:
			for square in squares(v[lod], func(t: Transform3D) -> Vector3: return t.origin).values():
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = v.full if lod == "near" else v.lite
				mm.instance_count = square.size()
				for i in square.size():
					mm.set_instance_transform(i, square[i])
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = birch_bark if v.kind == "aspen" else bark
				parent.add_child(mmi)


## Leaf clumps for one tree standing at `tr`: `cards` clumps round each crown point (4 close by, 1 far
## off), the tree's own colour give or take. Appends [position, custom] to `out`, for add_leaf_clumps().
static func crown_cards(v: Dictionary, tr: Transform3D, rng: RandomNumberGenerator, cards: int, out: Array) -> void:
	var hue := 0.12 + rng.randf() * 0.88
	if v.kind == "aspen":
		hue = rng.randf_range(0.0, 0.25)
	var top := 0.0
	for c in v.crowns:
		top = maxf(top, c.y)
	for c in v.crowns:
		var centre := tr * Vector3(c.x, c.y, c.z)
		var size: float = c.w * tr.basis.get_scale().x
		for k in cards:
			var p := centre + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)) * size * 0.8
			var lit := clampf(0.25 + 0.6 * (c.y / top) + (p.y - centre.y) / size * 0.3 + rng.randf_range(-0.15, 0.15), 0.0, 1.0)
			var h := clampf(hue + rng.randf_range(-0.18, 0.18), 0.0, 0.99)
			out.append([p, Color(size * rng.randf_range(1.3, 1.9), float(v.leaf) + h, lit, rng.randf())])


## Draws leaf clumps ([position, custom] each: foliage.gdshader's INSTANCE_CUSTOM) as camera-facing cards,
## in squares. Also for painted bushes and undergrowth (the same shader, other colours).
static func add_leaf_clumps(parent: Node, cards: Array, mat: Material) -> void:
	for square in squares(cards, func(c: Array) -> Vector3: return c[0]).values():
		var quad := QuadMesh.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = square.size()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in square.size():
			var p: Vector3 = square[i][0]
			mm.set_instance_transform(i, Transform3D(Basis(), p))
			mm.set_instance_custom_data(i, square[i][1])
			lo = lo.min(p)
			hi = hi.max(p)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		# the cards are moved and grown in the shader: room for that
		mmi.custom_aabb = AABB(lo - Vector3.ONE * 6.0, hi - lo + Vector3.ONE * 12.0)
		parent.add_child(mmi)


## Real 3D bushes: `placed` is {kind: [Transform3D, ...]} (bush_builder.gd's KINDS), one MultiMesh a kind.
## `kinds` adds kinds of your own (shaped as BushBuilder.KINDS' entries: other leaves, other colours), by name.
static func add_bushes(parent: Node, placed: Dictionary, sun_dir: Vector3, sun_color: Color, kinds := {}) -> void:
	var builder := BushBuilder.new()
	for kind in placed:
		if placed[kind].is_empty():
			continue
		var r := RandomNumberGenerator.new()
		r.seed = hash(kind)
		var info: Dictionary = kinds[kind] if kinds.has(kind) else BushBuilder.KINDS[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = builder.build(r, kind, info)
		mm.instance_count = placed[kind].size()
		for i in placed[kind].size():
			mm.set_instance_transform(i, placed[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var params: Dictionary = info.colors.duplicate()
		params["shape"] = info.shape
		mmi.material_override = material(LEAF3D, sun_dir, sun_color, params)
		parent.add_child(mmi)


## One leaf at `p` (on the ground, or with `falling` the top of its fall): [Transform3D, custom] for add_leaves().
static func leaf_card(rng: RandomNumberGenerator, p: Vector3, falling: bool) -> Array:
	var size := rng.randf_range(0.14, 0.26)
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if falling:
		p.y += rng.randf_range(7.0, 12.0)
	else:
		p.y += 0.02 + rng.randf() * 0.02
		basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.3)) * basis
	var custom := Color(rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0) if falling else rng.randf_range(0.3, 0.85), rng.randf())
	return [Transform3D(basis.scaled(Vector3(size, size, size)), p), custom]


## Draws leaves (leaf_card()s) lying or, with a material made with {"falling": 1.0}, coming down.
## `bounds` must hold all of them as they fall.
static func add_leaves(parent: Node, cards: Array, mat: Material, bounds: AABB) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = cards.size()
	for i in cards.size():
		mm.set_instance_transform(i, cards[i][0])
		mm.set_instance_custom_data(i, cards[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = bounds
	parent.add_child(mmi)


## A shaft of sun slanting down to `foot` from the sun: two crossed additive cards, coming and going on a
## slow clock of its own (`seed`).
static func add_sun_shaft(parent: Node, foot: Vector3, sun_dir: Vector3, sun_color: Color, length: float, width: float, seed: float, strength: float) -> void:
	var sun := sun_dir.normalized()
	var mid := foot + sun * length * 0.5
	var mat := material(SHAFT, sun_dir, sun_color, {"seed": seed, "strength": strength})
	for k in 2:
		var quad := QuadMesh.new()
		quad.size = Vector2(width, length)
		var m := MeshInstance3D.new()
		m.mesh = quad
		var x_axis := sun.cross(Vector3.UP).normalized().rotated(sun, k * PI * 0.5)
		var z_axis := x_axis.cross(sun).normalized()
		m.transform = Transform3D(Basis(x_axis, sun, z_axis), mid)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(m)


## A painted sky for an Environment (BG_SKY): gold low by the sun, grey-blue overhead, cloud streaks.
static func sky(sun_dir: Vector3) -> Sky:
	var m := ShaderMaterial.new()
	m.shader = SKY
	m.set_shader_parameter("sun_dir", sun_dir.normalized())
	var s := Sky.new()
	s.sky_material = m
	return s



## A stream's water: a ribbon `half` wide each side down `points` (its surface, from the top), running down it.
static func add_stream(parent: Node, points: Array[Vector3], half: float, sun_dir: Vector3, sun_color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := 0.0
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var side := (b - a).cross(Vector3.UP).normalized() * half
		var va := run
		run += a.distance_to(b)
		var quad := [[a - side, Vector2(0, va)], [a + side, Vector2(1, va)], [b - side, Vector2(0, run)], [b + side, Vector2(1, run)]]
		for q in [quad[0], quad[2], quad[1], quad[1], quad[2], quad[3]]:
			st.set_normal(Vector3.UP)
			st.set_uv(q[1])
			st.add_vertex(q[0])
	var stream := MeshInstance3D.new()
	stream.mesh = st.commit()
	stream.material_override = material(STREAM, sun_dir, sun_color)
	parent.add_child(stream)
