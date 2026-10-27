class_name LeafyTree
extends Resource
## A broadleaf tree (oak, aspen, cottonwood, willow, pinyon...) built from code, as a mesh: a trunk that
## forks into limbs, and a crown of lumpy leaf clumps at the limbs' ends and filling out between them,
## each ragged with tufts of leaves standing out of it, darker within and underneath, lighter on top
## and outside, every facet a shade of its own like a leaf catching the light; and, if asked, strands
## hanging from the crown (a willow's). Every setting below can be changed; the same settings and seed
## always make the same tree. It works as PineTree does:
##
## One tree:   var made := LeafyTree.oak(); made.height = 9.0; add_child(made.instance())
## A forest:   LeafyTree.forest(parent, points, made, 6)   (a MultiMesh per variant: a few draws)
##
## The mesh carries vertex colours (sRGB), normals bent outward from the middle of the crown (so the
## crown shades as one soft shape, good with cel shading), and in UV2.y how much each corner should
## sway in the wind (0 on the trunk, up to 1 at the outside of the crown and the tips of hanging
## strands) for a shader that wants it; UV2.x is 0. It is drawn with `material` if set, or else a
## plain material that uses the vertex colours.

## Overall height, metres, and the trunk's radius at its foot.
@export var height := 7.0
@export var trunk_radius := 0.24
## How far up the tree the crown starts (0..1 of the height).
@export_range(0.05, 0.9) var crown_base := 0.38
## How wide the crown is, against the height (0.3 a slim aspen, 1 a broad oak).
@export_range(0.15, 1.6) var spread := 0.7
## Limbs the trunk forks into, and the clumps of leaves in the crown.
@export_range(1, 7) var limbs := 4
@export_range(3, 48) var clumps := 16
## How big a clump is, against the crown.
@export_range(0.12, 0.7) var clump_size := 0.34
## How lumpy each clump is, and how many tufts of leaves stand out of it.
@export_range(0.0, 1.0) var lumpiness := 0.4
@export_range(0, 14) var tufts := 6
## Gaps in the crown: 0 a full ball, 1 clumps out at the edge with sky between them.
@export_range(0.0, 1.0) var openness := 0.25
## Strands hanging from the crown (0 none, 1 a weeping willow's down nearly to the ground).
@export_range(0.0, 1.0) var weep := 0.0
## Unevenness: limb angles, clump sizes and places, and the lean of the whole tree.
@export_range(0.0, 1.0) var wildness := 0.4
@export_range(0.0, 0.3) var lean := 0.04
## Colours: the bark, the leaves from deep in the crown to its sunlit outside, and how much each facet
## differs from the next (0 smooth, 1 well speckled).
@export var bark := Color(0.36, 0.27, 0.2)
@export var leaves_dark := Color(0.09, 0.2, 0.09)
@export var leaves := Color(0.2, 0.4, 0.16)
@export var leaves_light := Color(0.45, 0.62, 0.26)
@export_range(0.0, 1.0) var dapple := 0.5
## Now and then a clump in another colour (a turning leaf, blossom): how often in its alpha.
@export var accent := Color(0.9, 0.6, 0.15, 0.0)
@export var seed := 1
## What to draw it with. Empty: a plain material that takes the vertex colours.
@export var material: Material

static var _cache := {}
## How finely a clump is made (1: 80 faces; 0, the plain far tree: 20)
var _detail := 1


## Ready-made kinds. Change anything after.
static func oak() -> LeafyTree:
	return LeafyTree.new()


static func aspen() -> LeafyTree:
	var t := LeafyTree.new()
	t.height = 7.5
	t.trunk_radius = 0.14
	t.crown_base = 0.42
	t.spread = 0.32
	t.limbs = 2
	t.clumps = 13
	t.clump_size = 0.42
	t.tufts = 5
	t.openness = 0.15
	t.bark = Color(0.88, 0.86, 0.8)
	t.leaves_dark = Color(0.45, 0.32, 0.06)
	t.leaves = Color(0.88, 0.64, 0.14)
	t.leaves_light = Color(1.0, 0.85, 0.3)
	t.accent = Color(0.85, 0.35, 0.1, 0.12)
	return t


static func cottonwood() -> LeafyTree:
	var t := LeafyTree.new()
	t.height = 8.5
	t.trunk_radius = 0.36
	t.crown_base = 0.45
	t.spread = 0.7
	t.limbs = 5
	t.clumps = 18
	t.clump_size = 0.3
	t.lumpiness = 0.55
	t.openness = 0.6
	t.wildness = 0.65
	t.bark = Color(0.5, 0.47, 0.42)
	t.accent = Color(0.85, 0.7, 0.2, 0.15)
	return t


static func willow() -> LeafyTree:
	var t := LeafyTree.new()
	t.height = 6.5
	t.trunk_radius = 0.34
	t.crown_base = 0.55
	t.spread = 0.75
	t.limbs = 4
	t.clumps = 12
	t.clump_size = 0.36
	t.tufts = 3
	t.openness = 0.2
	t.weep = 0.85
	t.lean = 0.1
	t.leaves_dark = Color(0.14, 0.26, 0.1)
	t.leaves = Color(0.32, 0.5, 0.2)
	t.leaves_light = Color(0.55, 0.7, 0.32)
	return t


static func pinyon() -> LeafyTree:
	var t := LeafyTree.new()
	t.height = 3.4
	t.trunk_radius = 0.18
	t.crown_base = 0.2
	t.spread = 0.85
	t.limbs = 3
	t.clumps = 11
	t.clump_size = 0.4
	t.lumpiness = 0.5
	t.tufts = 7
	t.openness = 0.1
	t.wildness = 0.6
	t.bark = Color(0.33, 0.24, 0.17)
	t.leaves_dark = Color(0.07, 0.16, 0.09)
	t.leaves = Color(0.16, 0.3, 0.17)
	t.leaves_light = Color(0.3, 0.44, 0.26)
	return t


## The settings as a key (for sharing built meshes).
func _key(variant: int) -> String:
	return "%s|%d" % [var_to_str([_detail, height, trunk_radius, crown_base, spread, limbs, clumps, clump_size, lumpiness, tufts, openness, weep,
		wildness, lean, bark, leaves_dark, leaves, leaves_light, dapple, accent, seed]).hash(), variant]


## The tree's mesh, built once for each variant and kept.
func mesh(variant := 0) -> ArrayMesh:
	var key := _key(variant)
	if _cache.has(key):
		return _cache[key]
	var built := _build(seed * 7919 + variant * 104729)
	_cache[key] = built
	return built


## A MeshInstance3D of it.
func instance(variant := 0) -> MeshInstance3D:
	var made := MeshInstance3D.new()
	made.mesh = mesh(variant)
	made.material_override = _material()
	return made


## Plants trees at `points` (Vector3s on the ground), `variants` different ones turned and sized at
## random, under `parent`, as MultiMeshes, one per variant in each square of `chunk` metres; beyond
## `near` metres each square changes over to the plain version (see `simple`), with no shadow.
## `near` 0 keeps the full tree at every distance. (As PineTree.forest.)
static func forest(parent: Node3D, points: Array, shape: LeafyTree, variants := 4, sizes := Vector2(0.8, 1.25), chunk := 64.0, near := 70.0) -> Array[MultiMeshInstance3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape.seed
	var plain := shape.simple() if near > 0.0 else null
	var groups := {}
	for p: Vector3 in points:
		var size := rng.randf_range(sizes.x, sizes.y)
		var cell := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
		var key := [cell, rng.randi() % variants]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), p))
	var made: Array[MultiMeshInstance3D] = []
	for key: Array in groups:
		var trees: Array = groups[key]
		for detailed: bool in ([true, false] if plain else [true]):
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = shape.mesh(key[1]) if detailed else plain.mesh(key[1])
			multi.instance_count = trees.size()
			for i in trees.size():
				multi.set_instance_transform(i, trees[i])
			var node := MultiMeshInstance3D.new()
			node.multimesh = multi
			node.material_override = shape._material()
			if plain:
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if detailed:
					node.visibility_range_end = near
					node.visibility_range_end_margin = 10.0
				else:
					node.visibility_range_begin = near
					node.visibility_range_begin_margin = 10.0
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(node)
			made.append(node)
	return made


## A plainer version of this tree, for far off or for a phone: the same height, shape and colours, with
## coarser clumps, fewer of them and no tufts (about a fifth of the triangles).
func simple() -> LeafyTree:
	var plain: LeafyTree = duplicate()
	plain._detail = 0
	plain.tufts = 0
	plain.clumps = maxi(int(clumps * 0.7), 4)
	plain.clump_size = minf(clump_size * 1.15, 0.7)
	return plain


func _material() -> Material:
	if material:
		return material
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.vertex_color_is_srgb = true
	plain.roughness = 1.0
	return plain


# ------------------------------------------------------------------ building it

var _top := 0.0
var _crown := Vector3.ZERO
var _radius := 1.0
var _tall := 1.0
var _fork := 0.0


func _build(variant_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, lean)) if lean > 0.0 else Basis.IDENTITY
	_top = height * rng.randf_range(0.94, 1.06)
	var low := _top * crown_base
	_tall = (_top - low) * 0.5
	_radius = maxf(spread * _top * 0.5, 0.3)
	_crown = Vector3(0, low + _tall, 0)
	_fork = low + _tall * 0.25
	# The trunk, up to where it forks
	_tube(st, tilt, [Vector3.ZERO, Vector3(0, _fork * 0.5, 0), Vector3(0, _fork, 0)], trunk_radius, trunk_radius * 0.72, true, 0.0)
	# The limbs, out and up to the crown's clumps
	var ends: Array[Vector3] = []
	var turn := rng.randf() * TAU
	for i in limbs:
		var a := turn + i * TAU / limbs + rng.randf_range(-0.5, 0.5) * wildness
		var out := 0.5 if limbs > 1 else 0.0
		var end := _crown + Vector3(cos(a) * _radius * out, _tall * rng.randf_range(-0.05, 0.5), sin(a) * _radius * out)
		var bend := Vector3(0, _fork, 0).lerp(end, 0.5) + Vector3(cos(a), 0, sin(a)) * _radius * 0.1 * wildness + Vector3(0, -_tall * 0.08, 0)
		_tube(st, tilt, [Vector3(0, _fork, 0), bend, end], trunk_radius * 0.66, trunk_radius * 0.22, false, 0.15)
		ends.append(end)
	# The crown: a dark mass in its middle (so it reads as solid), a clump at each limb's end, and
	# the rest spread over it, more toward the outside the more open it is
	_clump(st, tilt, _crown + Vector3(0, -_tall * 0.08, 0), Vector3(_radius, _tall, _radius) * (0.62 - openness * 0.25), rng, true)
	var places: Array[Vector3] = ends.duplicate()
	var tries := 0
	while places.size() < clumps and tries < clumps * 20:
		tries += 1
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1.0), rng.randf_range(-1, 1))
		if d.length() > 1.0 or d.length() < 0.2:
			continue
		d = d.normalized() * lerpf(rng.randf_range(0.35, 0.8), rng.randf_range(0.7, 0.85), openness)
		places.append(_crown + Vector3(d.x * _radius, d.y * _tall, d.z * _radius))
	var big := maxf(_radius, _tall) * clump_size
	for p in places:
		var s := big * rng.randf_range(1.0 - 0.3 * wildness, 1.0 + 0.25 * wildness)
		# (flatter underneath, as leaves grow out to the light)
		var squash := 0.75 if p.y < _crown.y else 0.9
		_clump(st, tilt, p, Vector3(s, s * squash, s), rng, false)
	# Strands hanging from the crown, a willow's
	if weep > 0.0:
		var strands := int(weep * 64.0) if _detail > 0 else int(weep * 30.0)
		for i in strands:
			var a := i * 2.39996 + rng.randf_range(-0.2, 0.2)
			var r := _radius * rng.randf_range(0.6, 0.98)
			var from := _crown + Vector3(cos(a) * r, -_tall * rng.randf_range(-0.2, 0.35), sin(a) * r)
			var long := from.y * weep * rng.randf_range(0.6, 0.95)
			_strand(st, tilt, from, long, rng)
	return st.commit()


## A tube along `line` (a trunk or a limb), from radius `r0` to `r1`, with a flare at its foot if
## `foot`; `sway` how much its top should move in the wind.
func _tube(st: SurfaceTool, tilt: Basis, line: Array, r0: float, r1: float, foot: bool, sway: float) -> void:
	var sides := 7 if _detail > 0 else 5
	var count := line.size()
	var rings: Array = []
	for k in count:
		var s := float(k) / (count - 1)
		var ahead: Vector3 = ((line[mini(k + 1, count - 1)] as Vector3) - (line[maxi(k - 1, 0)] as Vector3)).normalized()
		var side := ahead.cross(Vector3.FORWARD if absf(ahead.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var other := ahead.cross(side).normalized()
		var r := lerpf(r0, r1, s) * ((1.0 + 0.6 * pow(1.0 - s, 6.0)) if foot else 1.0)
		var ring: Array = []
		for j in sides:
			var u := j * TAU / sides
			ring.append([line[k] + (side * cos(u) + other * sin(u)) * r, (side * cos(u) + other * sin(u))])
		rings.append(ring)
	for k in count - 1:
		var w0 := sway * float(k) / (count - 1)
		var w1 := sway * float(k + 1) / (count - 1)
		for j in sides:
			var a: Array = rings[k][j]
			var b: Array = rings[k][(j + 1) % sides]
			var c: Array = rings[k + 1][j]
			var d: Array = rings[k + 1][(j + 1) % sides]
			var shade := bark.darkened(0.14 * float(j % 2))
			_tri(st, [tilt * a[0], tilt * c[0], tilt * b[0]], [tilt * a[1], tilt * c[1], tilt * b[1]], [shade, shade, shade], [w0, w1, w0])
			_tri(st, [tilt * b[0], tilt * c[0], tilt * d[0]], [tilt * b[1], tilt * c[1], tilt * d[1]], [shade, shade, shade], [w0, w1, w1])


## One clump of leaves at `at`, `size` across each way: a lumpy ball, every facet a shade of its own,
## with tufts standing out of it; `core` the dark mass in the middle of the crown (no tufts, darker)
func _clump(st: SurfaceTool, tilt: Basis, at: Vector3, size: Vector3, rng: RandomNumberGenerator, core: bool) -> void:
	var phase := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	var freq := rng.randf_range(2.2, 3.4)
	var lump := lumpiness * (0.5 if core else 1.0)
	var odd := accent.a > 0.0 and not core and rng.randf() < accent.a
	var faces := _sphere(_detail)
	for f in faces:
		var pts: Array = []
		var normals: Array = []
		var colours: Array = []
		var sways: Array = []
		var shade := rng.randf_range(-1.0, 1.0) * dapple
		for v: Vector3 in f:
			var bump := 1.0 + lump * 0.32 * (sin(v.x * freq + phase.x) * sin(v.y * freq + phase.y) * sin(v.z * freq + phase.z) * 2.0 + sin(v.x * freq * 2.3 + phase.y) * 0.5)
			var p := at + v * size * bump
			pts.append(tilt * p)
			normals.append(tilt * _round(p, v))
			colours.append(_leaf_colour(p, v, shade, core, odd))
			sways.append(_sway(p))
		_tri(st, pts, normals, colours, sways)
	if core or tufts <= 0:
		return
	for i in tufts:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1.0), rng.randf_range(-1, 1)).normalized()
		var foot := at + d * size * 0.82
		var tip := foot + (d + Vector3.UP * 0.3).normalized() * size.x * rng.randf_range(0.35, 0.6)
		_tuft(st, tilt, foot, tip, size.x * rng.randf_range(0.22, 0.34), rng, odd)


## A tuft of leaves: a little four-sided point standing out of a clump, so the crown's edge is ragged
func _tuft(st: SurfaceTool, tilt: Basis, foot: Vector3, tip: Vector3, wide: float, rng: RandomNumberGenerator, odd: bool) -> void:
	var ahead := (tip - foot).normalized()
	var side := ahead.cross(Vector3.UP if absf(ahead.y) < 0.95 else Vector3.RIGHT).normalized()
	var other := ahead.cross(side).normalized()
	var base: Array[Vector3] = [foot + side * wide, foot + other * wide, foot - side * wide, foot - other * wide]
	var shade := rng.randf_range(-1.0, 1.0) * dapple
	for j in 4:
		var a: Vector3 = base[j]
		var b: Vector3 = base[(j + 1) % 4]
		var pts := [tilt * a, tilt * tip, tilt * b]
		var normals := [tilt * _round(a, ahead), tilt * _round(tip, ahead), tilt * _round(b, ahead)]
		var c_foot := _leaf_colour(a, ahead, shade, false, odd)
		var c_tip := _leaf_colour(tip, ahead, shade + 0.4, false, odd)
		_tri(st, pts, normals, [c_foot, c_tip, c_foot], [_sway(a), _sway(tip), _sway(b)])


## A strand hanging from the crown (a willow's): a long thin blade of leaves, swinging most at its tip
func _strand(st: SurfaceTool, tilt: Basis, from: Vector3, long: float, rng: RandomNumberGenerator) -> void:
	var out := Vector3(from.x, 0, from.z).normalized()
	var across := out.cross(Vector3.UP).normalized()
	var steps := 4 if _detail > 0 else 2
	var wide := 0.26 + rng.randf() * 0.12
	var shade := rng.randf_range(-1.0, 1.0) * dapple
	var prev: Array = []
	for k in steps + 1:
		var s := float(k) / steps
		var p := from + Vector3.DOWN * long * s + out * long * 0.12 * s * s
		var w := wide * (1.0 - s * 0.7)
		var ring := [p + across * w, p + out * w * 0.5, p - across * w]
		if k > 0:
			for j in 2:
				var a: Vector3 = prev[j]
				var b: Vector3 = prev[j + 1]
				var c: Vector3 = ring[j]
				var d: Vector3 = ring[j + 1]
				var ca := _leaf_colour(a, out, shade, false, false)
				var cc := _leaf_colour(c, out, shade + s * 0.5, false, false)
				var sa := 0.6 + 0.4 * (float(k - 1) / steps)
				var sc := 0.6 + 0.4 * s
				_tri(st, [tilt * a, tilt * c, tilt * b], [tilt * out, tilt * out, tilt * out], [ca, cc, ca], [sa, sc, sa])
				_tri(st, [tilt * b, tilt * c, tilt * d], [tilt * out, tilt * out, tilt * out], [ca, cc, cc], [sa, sc, sc])
		prev = ring


## The normal for a corner of the crown: mostly outward from the crown's middle, a little its own clump's
func _round(p: Vector3, own: Vector3) -> Vector3:
	var off := p - _crown
	var round_ := Vector3(off.x / _radius, off.y / _tall + 0.3, off.z / _radius).normalized()
	return round_.lerp(own.normalized(), 0.3).normalized()


## A leaf's colour at `p`: darker deep in the crown and underneath, lighter on top and outside; `shade`
## the facet's own difference (-1..1, by `dapple`)
func _leaf_colour(p: Vector3, own: Vector3, shade: float, core: bool, odd: bool) -> Color:
	var off := p - _crown
	var outside := clampf(Vector3(off.x / _radius, off.y / _tall, off.z / _radius).length(), 0.0, 1.2)
	var light := clampf(0.15 + 0.55 * outside + 0.3 * own.normalized().y + 0.25 * off.y / _tall + shade * 0.35, 0.0, 1.0)
	if core:
		light *= 0.45
	var c := leaves_dark.lerp(leaves, smoothstep(0.0, 0.55, light)).lerp(leaves_light, smoothstep(0.55, 1.0, light))
	if odd:
		c = c.lerp(accent, 0.75)
	return Color(c.r, c.g, c.b, 1.0)


## How much a point of the crown should sway in the wind: more toward its outside and top
func _sway(p: Vector3) -> float:
	var off := p - _crown
	return clampf(0.25 + 0.6 * Vector3(off.x / _radius, maxf(off.y, 0.0) / _tall, off.z / _radius).length(), 0.2, 1.0)


func _tri(st: SurfaceTool, points: Array, normals: Array, colours: Array, sways: Array) -> void:
	for i in 3:
		st.set_color(colours[i])
		st.set_normal(normals[i])
		st.set_uv2(Vector2(0.0, sways[i]))
		st.add_vertex(points[i])


## A ball's faces (unit radius): an icosahedron, split once into 80 if `detail` is 1
static var _spheres := {}


static func _sphere(detail: int) -> Array:
	if _spheres.has(detail):
		return _spheres[detail]
	var g := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0), Vector3(0, -1, g), Vector3(0, 1, g),
		Vector3(0, -1, -g), Vector3(0, 1, -g), Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var idx := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var faces: Array = []
	for f in idx:
		faces.append([v[f[0]], v[f[1]], v[f[2]]])
	for d in detail:
		var finer: Array = []
		for f: Array in faces:
			var a: Vector3 = f[0]
			var b: Vector3 = f[1]
			var c: Vector3 = f[2]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			finer.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		faces = finer
	_spheres[detail] = faces
	return faces
